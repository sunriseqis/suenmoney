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
const { buildServer } = await import('../../src/http/server.ts');

let app: FastifyInstance;
let userToken = '';
let testCategoryId = '';
let testPaymentMethodId = '';

const auth = (token: string) => ({ authorization: `Bearer ${token}` });

before(async () => {
  const db = openDatabase();
  migrate(db);

  const testUser = createUser(db, {
    username: 'syncuser',
    displayName: '同步用户',
    password: 'password123',
    role: 'admin',
  });

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

