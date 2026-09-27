/**
 * 计划与待办的端到端测试。
 *
 * 这一组覆盖的是「会持续几个月、且会在用户没看着的时候自动产生账目」的功能，
 * 所以重点全在**状态机**上：生成多少期、确认后发生了什么、改计划后历史有没有被
 * 动过、两人同时确认会怎样、自动入账会不会重复生成。
 * 这些错了都不会报错，只会让账目在某个月悄悄多一笔或少一笔。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-plan-'));
const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;
let token = '';
let partnerToken = '';

let categoryId = '';
let cashId = '';
let cardId = '';

const auth = (t = token) => ({ authorization: `Bearer ${t}` });

before(async () => {
  app = await buildServer({ logger: false });

  const setup = await app.inject({
    method: 'POST',
    url: '/api/auth/setup',
    payload: { username: 'suen', displayName: '我', password: 'correct-horse' },
  });
  token = setup.json().token as string;

  const partner = await app.inject({
    method: 'POST',
    url: '/api/users',
    headers: auth(),
    payload: { username: 'partner', displayName: '家人', password: 'partner-pw' },
  });
  assert.equal(partner.statusCode, 201);

  const partnerLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { username: 'partner', password: 'partner-pw' },
  });
  partnerToken = partnerLogin.json().token as string;

  const category = await app.inject({
    method: 'POST',
    url: '/api/categories',
    headers: auth(),
    payload: { name: '居住' },
  });
  categoryId = category.json().category.id;

  const cash = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '现金', type: 'cash' },
  });
  cashId = cash.json().paymentMethod.id;

  const card = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '招行信用卡', type: 'credit', billingDay: 10, repaymentDay: 28 },
  });
  cardId = card.json().paymentMethod.id;
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

const createPlan = (payload: Record<string, unknown>, t = token) =>
  app.inject({ method: 'POST', url: '/api/plans', headers: auth(t), payload });

const todosOf = (planId: string) =>
  app.inject({ method: 'GET', url: `/api/plans/${planId}`, headers: auth() });

describe('创建计划', () => {
  let planId = '';

  test('手动计划：一次性生成全部期待办，还款日按月递推', async () => {
    const res = await createPlan({
      name: '房贷',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 1_000_000,
      periods: 3,
      firstDueDate: '2026-01-20',
      remindDaysBefore: 3,
    });
    assert.equal(res.statusCode, 201);

    const plan = res.json().plan;
    planId = plan.id;

    assert.equal(plan.state, 'active');
    assert.equal(plan.amountCents, 1_000_000);
    assert.equal(plan.progress.paidCount, 0);
    assert.equal(plan.progress.pendingCount, 3);
    assert.equal(plan.progress.pendingCents, 3_000_000);
    assert.equal(plan.progress.nextDueDate, '2026-01-20');
    assert.equal(plan.progress.expectedEndDate, '2026-03-20');

    const all = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;
    assert.equal(all.length, 3);
    assert.deepEqual(
      all.map((item) => `${item['periodSeq']}:${item['repaymentDate']}`),
      ['1:2026-01-20', '2:2026-02-20', '3:2026-03-20'],
    );
    // 现金支付方式：入账日 = 还款日；提醒日 = 还款日 − 3 天
    assert.equal(all[0]!['postingDate'], '2026-01-20');
    assert.equal(all[0]!['remindDate'], '2026-01-17');
    assert.equal(all[0]!['status'], 'pending');
  });

  test('通知日跨月：3 日还款、提前 5 天 → 上月月末', async () => {
    const res = await createPlan({
      name: '跨月提醒',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 100,
      periods: 1,
      firstDueDate: '2026-03-03',
      remindDaysBefore: 5,
    });
    const id = res.json().plan.id;
    const todos = (await todosOf(id)).json().todos as Array<Record<string, unknown>>;
    assert.equal(todos[0]!['remindDate'], '2026-02-26');
  });

  test('分期计划：每期 = 原价 ÷ 期数，最后一期补足差额', async () => {
    const res = await createPlan({
      name: '手机分期',
      categoryId,
      paymentMethodId: cardId,
      source: 'installment',
      totalAmountCents: 100_000, // ¥1000
      purchaseDate: '2026-01-05',
      periods: 3,
      firstDueDate: '2026-02-28',
    });
    assert.equal(res.statusCode, 201);

    const plan = res.json().plan;
    assert.equal(plan.totalAmountCents, 100_000, '原价要作为历史快照保留');
    assert.equal(plan.purchaseDate, '2026-01-05');

    const todos = (await todosOf(plan.id)).json().todos as Array<Record<string, unknown>>;
    assert.deepEqual(
      todos.map((item) => item['amountCents']),
      [33_333, 33_333, 33_334],
    );
    assert.equal(
      todos.reduce((sum, item) => sum + Number(item['amountCents']), 0),
      100_000,
      '各期之和必须恰好等于原价，否则「剩余未付」永远结不清',
    );
  });

  test('信用卡分期：入账日取自账单日（账单日 10、还款日 28）', async () => {
    const res = await createPlan({
      name: '卡分期',
      categoryId,
      paymentMethodId: cardId,
      source: 'manual',
      amountCents: 50_000,
      periods: 1,
      firstDueDate: '2026-05-28',
    });
    const id = res.json().plan.id;
    const todos = (await todosOf(id)).json().todos as Array<Record<string, unknown>>;
    assert.equal(todos[0]!['postingDate'], '2026-05-10', '入账日应是同月的账单日');
    assert.equal(todos[0]!['repaymentDate'], '2026-05-28');
  });

  test('校验', async () => {
    const missingAmount = await createPlan({
      name: '缺金额',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      periods: 3,
      firstDueDate: '2026-01-20',
    });
    assert.equal(missingAmount.statusCode, 400);

    const missingTotal = await createPlan({
      name: '分期缺原价',
      categoryId,
      paymentMethodId: cashId,
      source: 'installment',
      periods: 3,
      firstDueDate: '2026-01-20',
      purchaseDate: '2026-01-01',
    });
    assert.equal(missingTotal.statusCode, 400);

    const tooSmall = await createPlan({
      name: '金额太小',
      categoryId,
      paymentMethodId: cashId,
      source: 'installment',
      totalAmountCents: 5,
      purchaseDate: '2026-01-01',
      periods: 12,
      firstDueDate: '2026-01-20',
    });
    assert.equal(tooSmall.statusCode, 400);
    assert.match(tooSmall.json().error, /无法分成/);

    const badPeriods = await createPlan({
      name: '期数过多',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 100,
      periods: 601,
      firstDueDate: '2026-01-20',
    });
    assert.equal(badPeriods.statusCode, 400);

    const badDate = await createPlan({
      name: '日期不存在',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 100,
      periods: 1,
      firstDueDate: '2026-02-30',
    });
    assert.equal(badDate.statusCode, 400);
  });

  test('未登录不能创建', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/plans',
      payload: { name: 'x', source: 'manual', periods: 1, firstDueDate: '2026-01-01' },
    });
    assert.equal(res.statusCode, 401);
  });
});

describe('确认待办', () => {
  let planId = '';
  let firstTodoId = '';

  before(async () => {
    const res = await createPlan({
      name: '房租',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 300_000,
      periods: 3,
      firstDueDate: '2026-06-01',
      remindDaysBefore: 3,
    });
    planId = res.json().plan.id;
    firstTodoId = ((await todosOf(planId)).json().todos as Array<{ id: string }>)[0]!.id;
  });

  test('确认后生成支出记录，记录人 = 点确认的人', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${firstTodoId}/confirm`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const { todo, expenseId } = res.json();
    assert.equal(todo.status, 'confirmed');
    assert.equal(todo.postedDate, '2026-06-01');
    assert.equal(todo.expenseId, expenseId);

    const expense = await app.inject({
      method: 'GET',
      url: `/api/expenses/${expenseId}`,
      headers: auth(),
    });
    assert.equal(expense.statusCode, 200);

    const row = expense.json().expense;
    assert.equal(row.source, 'plan', '来源要标出来，界面据此限制可编辑的字段');
    assert.equal(row.ownerId, res.json().todo.confirmedBy);
    assert.equal(row.amountCents, 300_000);
    assert.equal(row.repaymentDate, '2026-06-01');
    assert.equal(row.planId, planId);
    assert.equal(row.planPeriodSeq, 1);
  });

  test('这一期算进 6 月报表', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-06',
      headers: auth(),
    });
    assert.equal(res.json().report.totalCents, 300_000);
  });

  test('重复确认 → 409', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${firstTodoId}/confirm`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 409);
    assert.match(res.json().error, /已经确认过/);
  });

  test('家人确认：记录人是家人，两人都能确认', async () => {
    const todos = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;
    const second = todos.find((item) => item['status'] === 'pending');
    assert.ok(second !== undefined);

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${String(second['id'])}/confirm`,
      headers: auth(partnerToken),
    });
    assert.equal(res.statusCode, 200);

    const expense = await app.inject({
      method: 'GET',
      url: `/api/expenses/${String(res.json().expenseId)}`,
      headers: auth(),
    });
    assert.equal(expense.json().expense.ownerName, '家人');
  });

  test('逾期确认可以指定实际付款日，但不改变报表月份归属', async () => {
    const todos = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;
    const third = todos.find((item) => item['status'] === 'pending');
    assert.ok(third !== undefined);
    assert.equal(third['repaymentDate'], '2026-08-01');

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${String(third['id'])}/confirm`,
      headers: auth(),
      payload: { spendDate: '2026-08-05' },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().todo.postedDate, '2026-08-05');

    const expense = await app.inject({
      method: 'GET',
      url: `/api/expenses/${String(res.json().expenseId)}`,
      headers: auth(),
    });
    assert.equal(expense.json().expense.spendDate, '2026-08-05', '记录实际付款日');
    assert.equal(
      expense.json().expense.repaymentDate,
      '2026-08-01',
      '归属仍以计划里的还款日为准 —— 补点确认不该挪动历史报表',
    );
  });

  test('进度由待办派生', async () => {
    const plan = (await todosOf(planId)).json().plan;
    assert.equal(plan.progress.paidCount, 3);
    assert.equal(plan.progress.paidCents, 900_000);
    assert.equal(plan.progress.pendingCount, 0);
    assert.equal(plan.progress.nextDueDate, null, '没有未执行待办时不应返回下一个付款日');
  });
});

describe('跳过某一期', () => {
  test('跳过后不生成支出记录', async () => {
    const plan = await createPlan({
      name: '免租一个月',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 100_000,
      periods: 2,
      firstDueDate: '2026-07-01',
    });
    const planId = plan.json().plan.id;
    const todos = (await todosOf(planId)).json().todos as Array<{ id: string }>;

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todos[0]!.id}/skip`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().todo.status, 'skipped');

    // 按计划断言，而不是按月份总额 —— 同一个库里还有别的用例造的账目
    const count = db
      .prepare('SELECT COUNT(*) AS n FROM expenses WHERE plan_id = ?')
      .get(planId) as unknown as Record<string, unknown>;
    assert.equal(Number(count['n']), 0, '跳过不该产生任何账目');
  });
});

describe('改计划（LPR 调整 / 提前还款）', () => {
  let planId = '';

  test('准备：5 期计划，已确认前 2 期', async () => {
    const res = await createPlan({
      name: '房贷-待调整',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 1_000_000,
      periods: 5,
      firstDueDate: '2026-01-15',
    });
    planId = res.json().plan.id;

    const todos = (await todosOf(planId)).json().todos as Array<{ id: string }>;
    for (const todo of todos.slice(0, 2)) {
      const confirmed = await app.inject({
        method: 'POST',
        url: `/api/plan-todos/${todo.id}/confirm`,
        headers: auth(),
      });
      assert.equal(confirmed.statusCode, 200);
    }
  });

  test('改成 2000 元 × 3 期：未执行的待办被删除并重新生成，期序续接', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/plans/${planId}`,
      headers: auth(),
      payload: { amountCents: 200_000, remainingPeriods: 3 },
    });
    assert.equal(res.statusCode, 200);

    const plan = res.json().plan;
    assert.equal(plan.amountCents, 200_000);
    assert.equal(plan.progress.paidCount, 2, '已确认的历史期数不变');
    assert.equal(plan.progress.pendingCount, 3);

    const todos = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;
    assert.deepEqual(
      todos.map((item) => `${item['periodSeq']}:${item['amountCents']}:${item['status']}`),
      [
        '1:1000000:confirmed',
        '2:1000000:confirmed',
        '3:200000:pending',
        '4:200000:pending',
        '5:200000:pending',
      ],
      '已确认的 1、2 期原地不动；新生成的从第 3 期续接，金额用新值',
    );
    assert.deepEqual(
      todos.slice(2).map((item) => item['repaymentDate']),
      ['2026-03-15', '2026-04-15', '2026-05-15'],
      '新待办的日期仍从首期日递推，月份连续不重叠',
    );
  });

  test('不传剩余期数时沿用当前剩余数（只调金额的场景）', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/plans/${planId}`,
      headers: auth(),
      payload: { amountCents: 250_000 },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().plan.progress.pendingCount, 3, '剩余期数应保持不变');
    assert.equal(res.json().plan.amountCents, 250_000);
  });

  test('剩余期数设为 0 = 只保留历史（相当于提前结清）', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/plans/${planId}`,
      headers: auth(),
      payload: { remainingPeriods: 0 },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().plan.progress.pendingCount, 0);
    assert.equal(res.json().plan.progress.paidCount, 2);
    assert.equal(res.json().plan.state, 'active', '期数清零不等于终止计划');
  });

  test('别人不能改我的计划 → 403', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/plans/${planId}`,
      headers: auth(partnerToken),
      payload: { amountCents: 1 },
    });
    assert.equal(res.statusCode, 403);
  });

  test('变更记进 plan_revisions，可追溯', () => {
    const rows = db
      .prepare('SELECT prev_amount_cents, cancelled_todo_count, regenerated_todo_count FROM plan_revisions WHERE plan_id = ? ORDER BY created_at')
      .all(planId) as unknown as Array<Record<string, unknown>>;

    assert.ok(rows.length >= 3, `每次改计划都应留痕，实际 ${rows.length} 条`);
    assert.equal(Number(rows[0]!['prev_amount_cents']), 1_000_000);
    assert.equal(Number(rows[0]!['cancelled_todo_count']), 3, '第一次调整删掉了 3 期未执行待办');
    assert.equal(Number(rows[0]!['regenerated_todo_count']), 3);
  });
});

describe('终止计划', () => {
  test('未执行的待办全部删除，已确认的历史保留', async () => {
    const created = await createPlan({
      name: '待终止',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 50_000,
      periods: 4,
      firstDueDate: '2026-09-10',
    });
    const planId = created.json().plan.id;
    const todos = (await todosOf(planId)).json().todos as Array<{ id: string }>;

    await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todos[0]!.id}/confirm`,
      headers: auth(),
    });

    const res = await app.inject({
      method: 'POST',
      url: `/api/plans/${planId}/end`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().plan.state, 'ended');
    assert.equal(res.json().plan.progress.paidCount, 1);
    assert.equal(res.json().plan.progress.pendingCount, 0);
  });
});

describe('自动入账', () => {
  test('到期且开启自动入账的期，在打开待办列表时被结算', async () => {
    const created = await createPlan({
      name: '自动扣款',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 80_000,
      periods: 3,
      firstDueDate: '2026-10-05',
      autoPost: true,
    });
    const planId = created.json().plan.id;

    // today = 2026-11-01：第 1 期（10-05）与第 2 期（11-05）中，只有第 1 期已到期
    const settled = await app.inject({
      method: 'GET',
      url: '/api/plan-todos?today=2026-11-01&planId=' + planId,
      headers: auth(),
    });
    assert.equal(settled.statusCode, 200);
    assert.equal(settled.json().settled, 1, '只应结算已到期的那一期');

    const todos = settled.json().todos as Array<Record<string, unknown>>;
    assert.equal(todos[0]!['status'], 'confirmed');
    assert.equal(todos[0]!['postedDate'], '2026-10-05');
    assert.equal(todos[1]!['status'], 'pending', '未到期的期不该被提前入账');

    const report = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-10',
      headers: auth(),
    });
    assert.equal(report.json().report.totalCents, 80_000);
  });

  test('重复结算不会重复生成账目（幂等）', async () => {
    const created = await createPlan({
      name: '幂等检查',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 10_000,
      periods: 1,
      firstDueDate: '2026-11-20',
      autoPost: true,
    });
    const planId = created.json().plan.id;

    const first = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2026-12-01&planId=${planId}`,
      headers: auth(),
    });
    const second = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2026-12-01&planId=${planId}`,
      headers: auth(),
    });

    /**
     * 不断言 `settled` 的具体数字：**结算是全局的**（打开仪表盘时把所有到期的
     * 自动入账待办一次结清），所以这个计数会带上同一库里其他用例造的待办。
     * 按计划本身断言才有意义，也才不会因为用例顺序变化而红。
     */
    assert.equal(second.json().settled, 0, '第二次调用不该再结算出任何东西');

    const count = db
      .prepare('SELECT COUNT(*) AS n FROM expenses WHERE plan_id = ?')
      .get(planId) as unknown as Record<string, unknown>;
    assert.equal(Number(count['n']), 1, '同一期只能生成一笔账目');

    assert.equal(
      (first.json().todos as Array<Record<string, unknown>>)[0]!['status'],
      'confirmed',
    );
  });

  test('未开启自动入账的计划不会被结算', async () => {
    const created = await createPlan({
      name: '手动确认',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 10_000,
      periods: 1,
      firstDueDate: '2026-11-25',
      autoPost: false,
    });
    const planId = created.json().plan.id;

    const res = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2026-12-01&planId=${planId}`,
      headers: auth(),
    });
    assert.equal(res.json().settled, 0);
    assert.equal((res.json().todos as Array<Record<string, unknown>>)[0]!['status'], 'pending');
  });

  test('已终止的计划不再自动入账', async () => {
    const created = await createPlan({
      name: '已终止',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 10_000,
      periods: 1,
      firstDueDate: '2026-11-28',
      autoPost: true,
    });
    const planId = created.json().plan.id;
    await app.inject({ method: 'POST', url: `/api/plans/${planId}/end`, headers: auth() });

    const res = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2026-12-01&planId=${planId}`,
      headers: auth(),
    });
    assert.equal(res.json().settled, 0);
  });
});

describe('待办列表筛选', () => {
  test('remindBefore 用来取「该处理了」的待办（含逾期）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/plan-todos?status=pending&remindBefore=2026-06-02',
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const todos = res.json().todos as Array<Record<string, unknown>>;
    for (const todo of todos) {
      assert.equal(todo['status'], 'pending');
      assert.ok(String(todo['remindDate']) <= '2026-06-02');
    }
  });

  test('status 取值非法 → 400（而不是静默返回空列表）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/plan-todos?status=whatever',
      headers: auth(),
    });
    assert.equal(res.statusCode, 400);
  });
});
