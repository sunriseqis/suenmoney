/**
 * 增量同步与离线补偿（Sync API）测试。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-sync-'));
process.env['SUENMONEY_DB_PATH'] = join(tempDir, 'test.sqlite');

const { migrate, openDatabase } = await import('../../src/db/index.ts');
const { createUser } = await import('../../src/db/repo/users.ts');
const { createCategory } = await import('../../src/db/repo/categories.ts');
const { createPaymentMethod } = await import('../../src/db/repo/payment-methods.ts');
const { createPlan, confirmTodo, listTodos } = await import('../../src/db/repo/plans.ts');
const { buildServer } = await import('../../src/http/server.ts');

let app: FastifyInstance;
let userToken = '';
let testUserId = '';
let testCategoryId = '';
let testPaymentMethodId = '';
let syncDb: ReturnType<typeof openDatabase>;

const auth = (token: string) => ({ authorization: `Bearer ${token}` });

before(async () => {
  const db = openDatabase();
  migrate(db);
  syncDb = db;

  const testUser = createUser(db, {
    username: 'syncuser',
    displayName: '同步用户',
    password: 'password123',
    role: 'admin',
  });
  testUserId = testUser.id;

  const cat = createCategory(db, {
    name: '餐饮食品',
    icon: 'utensils',
    color: 'amber',
    actorId: testUser.id,
  });
  testCategoryId = cat.id;

  const pm = createPaymentMethod(db, {
    name: '微信支付',
    type: 'cash',
    icon: 'wechat',
    actorId: testUser.id,
  });
  testPaymentMethodId = pm.id;

  app = await buildServer({ logger: false });
  await app.ready();

  const res = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { username: 'syncuser', password: 'password123' },
  });
  userToken = res.json().token;
});

after(async () => {
  if (app) await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

describe('增量同步接口（GET/POST /api/sync）', () => {
  test('未登录请求拦截 → 401', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/sync/pull',
    });
    assert.equal(res.statusCode, 401);
  });

  test('状态接口返回当前服务端的最新同步版本', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/sync/status',
      headers: auth(userToken),
    });
    assert.equal(res.statusCode, 200);
    const json = res.json();
    assert.equal(typeof json.latestVersion, 'number');
    assert.ok(json.latestVersion >= 1);
  });

  test('拉取初始实体变更（分类与支付方式）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/sync/pull?since=0&limit=100',
      headers: auth(userToken),
    });
    assert.equal(res.statusCode, 200);
    const json = res.json();
    assert.ok(Array.isArray(json.changes));
    assert.ok(json.changes.length >= 2);
    assert.equal(typeof json.latestVersion, 'number');
    assert.equal(typeof json.hasMore, 'boolean');

    // 确认有 category 和 payment_method 的变更
    const entityTypes = json.changes.map((c: { entityType: string }) => c.entityType);
    assert.ok(entityTypes.includes('category'));
    assert.ok(entityTypes.includes('payment_method'));
  });

  test('传入当前最新版本拉取 → 返回空增量', async () => {
    const statusRes = await app.inject({
      method: 'GET',
      url: '/api/sync/status',
      headers: auth(userToken),
    });
    const latest = statusRes.json().latestVersion;

    const pullRes = await app.inject({
      method: 'GET',
      url: `/api/sync/pull?since=${latest}`,
      headers: auth(userToken),
    });
    assert.equal(pullRes.statusCode, 200);
    const json = pullRes.json();
    assert.equal(json.changes.length, 0);
    assert.equal(json.latestVersion, latest);
    assert.equal(json.hasMore, false);
  });

  test('离线补偿推送（POST /api/sync/push）批量写入多笔离线支出', async () => {
    const statusBefore = await app.inject({
      method: 'GET',
      url: '/api/sync/status',
      headers: auth(userToken),
    });
    const vBefore = statusBefore.json().latestVersion;

    const offlineId1 = '01J9OFFLINE000000000000001';
    const offlineId2 = '01J9OFFLINE000000000000002';

    const pushRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: {
        deviceId: 'android-phone-01',
        expenses: [
          {
            id: offlineId1,
            amountCents: 2500,
            categoryId: testCategoryId,
            paymentMethodId: testPaymentMethodId,
            spendDate: '2026-09-29',
            note: '地铁站便利店早餐',
          },
          {
            id: offlineId2,
            amountCents: 4800,
            categoryId: testCategoryId,
            paymentMethodId: testPaymentMethodId,
            spendDate: '2026-09-29',
            note: '离线咖啡',
          },
        ],
      },
    });

    assert.equal(pushRes.statusCode, 200);
    const pushJson = pushRes.json();
    assert.equal(pushJson.pushedExpensesCount, 2);
    assert.deepEqual(pushJson.expenseIds, [offlineId1, offlineId2]);
    assert.ok(pushJson.latestVersion > vBefore);

    // 随后拉取增量，确认可以增量拉出这两笔记录且 deviceId 与 payload 准确
    const pullRes = await app.inject({
      method: 'GET',
      url: `/api/sync/pull?since=${vBefore}`,
      headers: auth(userToken),
    });
    assert.equal(pullRes.statusCode, 200);
    const pullJson = pullRes.json();
    const expenseChanges = pullJson.changes.filter(
      (c: { entityType: string }) => c.entityType === 'expense',
    );
    assert.equal(expenseChanges.length, 2);
    assert.equal(expenseChanges[0].deviceId, 'android-phone-01');
    assert.equal(expenseChanges[0].payload.amount_cents, 2500);
    assert.equal(expenseChanges[1].payload.amount_cents, 4800);
  });

  test('网络抖动重复推送相同 ID 的离线记录具有幂等性', async () => {
    const offlineId1 = '01J9OFFLINE000000000000001';

    const pushRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: {
        expenses: [
          {
            id: offlineId1,
            amountCents: 2500,
            categoryId: testCategoryId,
            paymentMethodId: testPaymentMethodId,
            spendDate: '2026-09-29',
          },
        ],
      },
    });

    assert.equal(pushRes.statusCode, 200);
    const pushJson = pushRes.json();
    // 幂等确认返回该 id，并不重复创建额外记录
    assert.equal(pushJson.expenseIds.length, 1);
  });

  test('毒丸隔离：单条新增被拒不影响同批其他条目入库', async () => {    const offlineId = '01J9OFFLINE000000000000003';

    const pushRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: {
        expenses: [
          {
            id: '01J9OFFLINE000000000000BAD',
            amountCents: 1000,
            categoryId: '01J9NOPTEXISTCATEGORY00000',
            paymentMethodId: testPaymentMethodId,
            spendDate: '2026-09-29',
            note: '引用了不存在的分类 —— 服务端必须拒收这一条',
          },
          {
            id: offlineId,
            amountCents: 6600,
            categoryId: testCategoryId,
            paymentMethodId: testPaymentMethodId,
            spendDate: '2026-09-29',
            note: '同批的正常条目必须照常入库',
          },
        ],
      },
    });

    assert.equal(pushRes.statusCode, 200, '单条坏数据不应把整个推送打回（否则 Outbox 被永久锁死）');
    const pushJson = pushRes.json();
    assert.equal(pushJson.pushedExpensesCount, 1);
    assert.deepEqual(pushJson.expenseIds, [offlineId]);
    assert.deepEqual(pushJson.failedExpenseIndexes, [0], '失败条目按请求下标回传，供客户端死信隔离');
  });

  test('离线撤销确认与恢复跳过（revertedTodoIds / restoredTodoIds）', async () => {
    const plan = createPlan(syncDb, {
      name: '同步撤销测试',
      categoryId: testCategoryId,
      paymentMethodId: testPaymentMethodId,
      source: 'manual',
      amountCents: 5_000,
      periods: 2,
      firstDueDate: '2026-10-05',
      ownerId: testUserId,
    });
    const todos = listTodos(syncDb, { planId: plan.id });
    assert.equal(todos.length, 2);

    // 确认第 1 期 → 离线撤销 → 待办回 pending
    confirmTodo(syncDb, todos[0]!.id, testUserId);

    const revertRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: { revertedTodoIds: [todos[0]!.id] },
    });
    assert.equal(revertRes.statusCode, 200);
    assert.equal(revertRes.json().revertedTodosCount, 1);
    assert.equal(
      listTodos(syncDb, { planId: plan.id }).find((t) => t.id === todos[0]!.id)!.status,
      'pending',
      '撤销推送后待办应回到 pending',
    );

    // 跳过第 2 期 → 离线恢复 → 待办回 pending
    const skipRes = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todos[1]!.id}/skip`,
      headers: auth(userToken),
    });
    assert.equal(skipRes.statusCode, 200);

    const restoreRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: { restoredTodoIds: [todos[1]!.id] },
    });
    assert.equal(restoreRes.statusCode, 200);
    assert.equal(restoreRes.json().restoredTodosCount, 1);
    assert.equal(
      listTodos(syncDb, { planId: plan.id }).find((t) => t.id === todos[1]!.id)!.status,
      'pending',
      '恢复推送后待办应回到 pending',
    );
  });

  test('离线补偿推送支持批量更新与删除支出（updatedExpenses / deletedExpenseIds）', async () => {
    const offlineId1 = '01J9OFFLINE000000000000001';

    // 1. 批量更新金额与备注
    const updateRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: {
        updatedExpenses: [
          {
            id: offlineId1,
            amountCents: 3200,
            note: '修改后的便利店早餐',
          },
        ],
      },
    });

    assert.equal(updateRes.statusCode, 200);
    const updateJson = updateRes.json();
    assert.equal(updateJson.updatedExpensesCount, 1);

    // 2. 批量删除
    const deleteRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: {
        deletedExpenseIds: [offlineId1],
      },
    });

    assert.equal(deleteRes.statusCode, 200);
    const deleteJson = deleteRes.json();
    assert.equal(deleteJson.deletedExpensesCount, 1);

    // 3. 拉取验证包含 delete 操作
    const pullRes = await app.inject({
      method: 'GET',
      url: `/api/sync/pull?since=${updateJson.latestVersion}`,
      headers: auth(userToken),
    });
    assert.equal(pullRes.statusCode, 200);
    const pullJson = pullRes.json();
    const deletedChanges = pullJson.changes.filter(
      (c: { entityId: string; op: string }) => c.entityId === offlineId1 && c.op === 'delete',
    );
    assert.equal(deletedChanges.length, 1);
  });
});


/**
 * 增量游标契约（v2.1.1）。
 *
 * 背景：iOS / 鸿蒙两端曾把响应里的 `latestVersion`（**全局最新版本**）当成
 * 下一页的 `since`。一页取不完时 latestVersion 远大于本页最后一条，于是
 * 「第 1 页消费完 → 游标直接跳到最新 → 中间那批变更再也拉不到」。
 * 表现是单向同步：落后的一端永远看不到另一端记的账，且**没有任何报错**。
 *
 * 这组测试锁死两件事：
 *   1. `nextSince` 必须等于本页最后一条变更的版本（不是 latestVersion）；
 *   2. 按 `nextSince` 翻页必须零丢失 —— 这是客户端唯一的正确用法。
 */
describe('增量游标 nextSince（一页取不完时不能丢变更）', () => {
  test('hasMore=true 时 nextSince 指向本页最后一条，而不是全局最新版本', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/sync/pull?since=0&limit=2',
      headers: auth(userToken),
    });
    assert.equal(res.statusCode, 200);
    const json = res.json();

    assert.equal(json.changes.length, 2);
    assert.equal(json.hasMore, true);
    assert.equal(json.nextSince, json.changes[1].version, 'nextSince 必须是本页最后一条的版本');
    assert.ok(
      json.nextSince < json.latestVersion,
      '只要还有下一页，nextSince 就必须小于 latestVersion —— 否则说明服务端又想让我们一页吞完',
    );
  });

  test('本页为空时 nextSince 等于 latestVersion（追平后不再前进）', async () => {
    const statusRes = await app.inject({
      method: 'GET',
      url: '/api/sync/status',
      headers: auth(userToken),
    });
    const latest = statusRes.json().latestVersion;

    const res = await app.inject({
      method: 'GET',
      url: `/api/sync/pull?since=${latest}`,
      headers: auth(userToken),
    });
    const json = res.json();
    assert.equal(json.changes.length, 0);
    assert.equal(json.hasMore, false);
    assert.equal(json.nextSince, latest);
  });

  test('250 条变更按 nextSince 翻页拉取：零丢失（回归：曾经会永久丢 50 条）', async () => {
    const before = await app.inject({
      method: 'GET',
      url: '/api/sync/status',
      headers: auth(userToken),
    });
    const since = before.json().latestVersion;

    // 一次推入 250 笔 → 250 条 change，超过一页(200)
    const items = Array.from({ length: 250 }, (_, i) => ({
      id: `01J9PAGING${String(i).padStart(14, '0')}`,
      amountCents: 100 + i,
      categoryId: testCategoryId,
      paymentMethodId: testPaymentMethodId,
      spendDate: '2026-11-19',
      note: `翻页-${i}`,
    }));

    const pushRes = await app.inject({
      method: 'POST',
      url: '/api/sync/push',
      headers: auth(userToken),
      payload: { expenses: items },
    });
    assert.equal(pushRes.statusCode, 200);
    assert.equal(pushRes.json().pushedExpensesCount, 250);

    // 客户端算法：since ← nextSince，一页一页翻到 hasMore=false
    let cursor = since;
    const seen = new Set<string>();
    let pages = 0;
    let hasMore = true;
    while (hasMore && pages < 50) {
      const res = await app.inject({
        method: 'GET',
        url: `/api/sync/pull?since=${cursor}&limit=200`,
        headers: auth(userToken),
      });
      const body = res.json();
      for (const change of body.changes) {
        if (change.entityType === 'expense') seen.add(change.entityId);
      }
      // 游标必须单调前进，否则会死循环
      assert.ok(body.nextSince >= cursor, 'nextSince 不能倒退');
      cursor = body.nextSince;
      hasMore = body.hasMore;
      pages++;
      if (body.changes.length === 0) break;
    }

    assert.equal(hasMore, false, '应在 50 页内追平');
    assert.equal(pages, 2, '250 条 = 两页（200 + 50）');
    assert.equal(seen.size, 250, '一条都不能丢');
    for (const item of items) {
      assert.ok(seen.has(item.id), `丢失了 ${item.id}`);
    }
  });
});
