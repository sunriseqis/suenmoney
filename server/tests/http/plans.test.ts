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

  test('记账抽屉分期：confirmFirst=true 同时创建分期计划并确认入账第 1 期', async () => {
    const res = await createPlan({
      name: 'iPhone 17 分期',
      categoryId,
      paymentMethodId: cardId,
      source: 'installment',
      totalAmountCents: 120_000, // 1200元
      purchaseDate: '2026-09-05',
      periods: 12,
      firstDueDate: '2026-09-28',
      confirmFirst: true,
      confirmSpendDate: '2026-09-05',
    });
    assert.equal(res.statusCode, 201);
    const plan = res.json().plan;

    assert.equal(plan.progress.paidCount, 1, '第 1 期应直接入账');
    assert.equal(plan.progress.paidCents, 10_000);
    assert.equal(plan.progress.pendingCount, 11, '剩余 11 期转入待办');
    assert.equal(plan.progress.pendingCents, 110_000);

    const todos = (await todosOf(plan.id)).json().todos as Array<Record<string, unknown>>;
    assert.equal(todos[0]!['status'], 'confirmed');
    assert.ok(todos[0]!['expenseId'] !== null);
    assert.equal(todos[1]!['status'], 'pending');

    // 验证第一笔支出记录确实已写入
    const expenseRes = await app.inject({
      method: 'GET',
      url: `/api/expenses/${todos[0]!['expenseId']}`,
      headers: auth(),
    });
    assert.equal(expenseRes.statusCode, 200);
    assert.equal(expenseRes.json().expense.amountCents, 10_000);
    assert.equal(expenseRes.json().expense.spendDate, '2026-09-05');
    assert.equal(expenseRes.json().expense.source, 'plan');
    assert.equal(expenseRes.json().expense.planPeriodSeq, 1);
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

describe('撤销确认与恢复跳过', () => {
  /** 把一个计划的全部期待办读出来（按 period_seq 升序）。 */
  const todoRows = async (planId: string) =>
    (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;

  test('撤销：支出打成墓碑、该期回待办、且不会被自动入账重新捡回来', async () => {
    /**
     * 特意用 2027-02/03：这两个月没有任何其他用例写过账，
     * 所以月度报表的断言是「这个库里的全部」，不会因为用例执行顺序而红。
     */
    const created = await createPlan({
      name: '撤销用例',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 123_400,
      periods: 2,
      firstDueDate: '2027-02-05',
      autoPost: true,
    });
    const planId = created.json().plan.id as string;

    // 2027-03-01：第 1 期（02-05）已到期，被自动入账
    const settled = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2027-03-01&planId=${planId}`,
      headers: auth(),
    });
    const before = settled.json().todos as Array<Record<string, unknown>>;
    assert.equal(before[0]!['status'], 'confirmed', '到期且开了自动入账，应已入账');
    assert.equal(before[0]!['holdAutoPost'], false, '新建的期待办不该带「摘出自动入账」标记');

    const todoId = String(before[0]!['id']);
    const expenseId = String(before[0]!['expenseId']);
    assert.ok(expenseId.length > 0, '确认后应当有关联支出');

    const reportBefore = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2027-02',
      headers: auth(),
    });
    assert.equal(reportBefore.json().report.totalCents, 123_400);

    const reverted = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/revert`,
      headers: auth(),
    });
    assert.equal(reverted.statusCode, 200);
    assert.equal(reverted.json().expenseId, expenseId, '要告诉客户端撤掉的是哪一笔');
    assert.equal(reverted.json().todo.status, 'pending');
    assert.equal(reverted.json().todo.expenseId, null);
    assert.equal(reverted.json().todo.postedDate, null);
    assert.equal(reverted.json().todo.confirmedBy, null);
    assert.equal(
      reverted.json().todo.holdAutoPost,
      true,
      '撤销必须把该期摘出自动入账，否则下次打开首页它自己就回来了',
    );

    // 支出是**软删（墓碑）**而不是物理删除 —— 物理删除会让其他设备永远不知道它没了
    const expenseRow = db
      .prepare('SELECT deleted_at AS deleted_at FROM expenses WHERE id = ?')
      .get(expenseId) as unknown as Record<string, unknown>;
    assert.ok(expenseRow['deleted_at'] !== null, '被撤销的支出应留下墓碑');

    const alive = db
      .prepare('SELECT COUNT(*) AS n FROM expenses WHERE plan_id = ? AND deleted_at IS NULL')
      .get(planId) as unknown as Record<string, unknown>;
    assert.equal(Number(alive['n']), 0, '撤销后这个计划不应还留有活着的账目');

    const tombstone = db
      .prepare(
        `SELECT COUNT(*) AS n FROM changes
          WHERE entity_type = 'expense' AND entity_id = ? AND op = 'delete'`,
      )
      .get(expenseId) as unknown as Record<string, unknown>;
    assert.equal(Number(tombstone['n']), 1, '必须有 expense 的 delete 变更记录，否则同步会漏');

    const reportAfter = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2027-02',
      headers: auth(),
    });
    assert.equal(reportAfter.json().report.totalCents, 0, '报表应随撤销一起回落');

    /**
     * ★ 这条是整个分支存在的理由。
     *
     * 先「预热」一次把库里其他已到期的自动入账一次结清（`settled` 是全局计数，
     * 不复用别的用例留下的到期待办就没法断言它归零）；再结算第二次。
     * 若 `settleAutoPost` 少了 `hold_auto_post = 0` 这个条件，
     * 预热那次就会把这一期重新入账，下面的 pending 断言会红。
     */
    await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2027-04-01&planId=${planId}`,
      headers: auth(),
    });
    const resettled = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2027-04-01&planId=${planId}`,
      headers: auth(),
    });
    assert.equal(resettled.json().settled, 0, '同一批到期待办不该被结算两次');

    const after = resettled.json().todos as Array<Record<string, unknown>>;
    const first = after.find((row) => row['id'] === todoId)!;
    assert.equal(first['status'], 'pending', '撤销过的期次不该被自动入账重新捡回来');

    // 撤销之后仍然可以手动确认回来 —— 撤销本身是可逆的
    const again = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/confirm`,
      headers: auth(),
    });
    assert.equal(again.statusCode, 200);
    assert.equal(again.json().todo.status, 'confirmed');
    assert.notEqual(again.json().expenseId, expenseId, '重新确认要生成一条新的支出，不是复活墓碑');
  });

  test('对未确认的期次撤销 → 409', async () => {
    const created = await createPlan({
      name: '没确认过',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 5_000,
      periods: 1,
      firstDueDate: '2027-05-05',
    });
    const planId = created.json().plan.id as string;
    const rows = await todoRows(planId);

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${String(rows[0]!['id'])}/revert`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 409);
  });

  test('重复撤销 → 409（第二次时它已经不是已确认状态）', async () => {
    const created = await createPlan({
      name: '重复撤销',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 6_000,
      periods: 1,
      firstDueDate: '2027-05-15',
    });
    const planId = created.json().plan.id as string;
    const rows = await todoRows(planId);
    const todoId = String(rows[0]!['id']);

    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/confirm`, headers: auth() });
    const first = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/revert`,
      headers: auth(),
    });
    assert.equal(first.statusCode, 200);

    const second = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/revert`,
      headers: auth(),
    });
    assert.equal(second.statusCode, 409);

    // 幂等失败不该留下第二笔活着的账目
    const alive = db
      .prepare('SELECT COUNT(*) AS n FROM expenses WHERE plan_id = ? AND deleted_at IS NULL')
      .get(planId) as unknown as Record<string, unknown>;
    assert.equal(Number(alive['n']), 0);
  });

  test('恢复跳过：回到待办，且不会在恢复的瞬间被自动入账', async () => {
    const created = await createPlan({
      name: '跳过后恢复',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 33_000,
      periods: 1,
      firstDueDate: '2027-06-05',
      autoPost: true,
    });
    const planId = created.json().plan.id as string;
    const rows = await todoRows(planId);
    const todoId = String(rows[0]!['id']);

    const skipped = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/skip`,
      headers: auth(),
    });
    assert.equal(skipped.json().todo.status, 'skipped');

    const restored = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/restore`,
      headers: auth(),
    });
    assert.equal(restored.statusCode, 200);
    assert.equal(restored.json().todo.status, 'pending');
    assert.equal(
      restored.json().todo.holdAutoPost,
      true,
      '恢复时若不摘出自动入账，恢复的那一刻它就到期了，会被当场入账',
    );

    // 预热一次结清库里其他到期待办，再结算第二次
    await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2027-08-01&planId=${planId}`,
      headers: auth(),
    });
    const resettled = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?today=2027-08-01&planId=${planId}`,
      headers: auth(),
    });
    assert.equal(resettled.json().settled, 0);

    const after = resettled.json().todos as Array<Record<string, unknown>>;
    assert.equal(after.find((row) => row['id'] === todoId)!['status'], 'pending');

    const alive = db
      .prepare('SELECT COUNT(*) AS n FROM expenses WHERE plan_id = ? AND deleted_at IS NULL')
      .get(planId) as unknown as Record<string, unknown>;
    assert.equal(Number(alive['n']), 0, '恢复跳过不该凭空生成账目');
  });

  test('对未跳过的期次恢复 → 409', async () => {
    const created = await createPlan({
      name: '没跳过',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 7_000,
      periods: 1,
      firstDueDate: '2027-09-05',
    });
    const planId = created.json().plan.id as string;
    const rows = await todoRows(planId);

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${String(rows[0]!['id'])}/restore`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 409);
  });

  test('家人也能撤销：与「确认」的权限对称', async () => {
    const created = await createPlan({
      name: '家人撤销',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 11_000,
      periods: 1,
      firstDueDate: '2027-10-05',
    });
    const planId = created.json().plan.id as string;
    const rows = await todoRows(planId);
    const todoId = String(rows[0]!['id']);

    // 本人确认，家人撤销 —— 确认两人都能做，撤销是它的逆操作，也两人都能做
    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/confirm`, headers: auth() });
    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/revert`,
      headers: auth(partnerToken),
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().todo.status, 'pending');
  });
});

/**
 * 「我知道了」（ack）。
 *
 * 这一组守的是一个**静默**的错：ack 与 confirm 都能让一条提醒「消失」，
 * 但只有 confirm 会生成账目。用错了不报错 —— 报表少一笔或多一笔，
 * 而且看不出是哪一天少的。
 */
describe('「我知道了」（ack）', () => {
  /**
   * 用一个**别的用例都不碰**的月份，月度报表的断言才是「整个库的全部」，
   * 不会因为用例执行顺序而红。
   */
  const MONTH = '2028-05';

  const createAckedPlan = async (name: string) => {
    const created = await createPlan({
      name,
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 280_000,
      periods: 2,
      firstDueDate: `${MONTH}-05`,
      autoPost: true,
      remindDaysBefore: 3,
    });
    const planId = created.json().plan.id as string;
    const rows = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;
    return { planId, rows };
  };

  const monthlyTotal = async (month: string) => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/reports/monthly?month=${month}`,
      headers: auth(),
    });
    const report = res.json().report as Record<string, unknown>;
    return { totalCents: Number(report['totalCents']), count: Number(report['count']) };
  };

  test('ack 只记「看过了」：状态仍是 pending，且不产生任何账目', async () => {
    const { rows } = await createAckedPlan('确认用例');
    const todoId = String(rows[0]!['id']);

    // 计划开了自动入账、这一期没被撤销过 → 现在会自己入账
    assert.equal(rows[0]!['willAutoPost'], true);
    assert.equal(rows[0]!['ackAt'], null);

    const before = await monthlyTotal(MONTH);

    const res = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/ack`,
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const todo = res.json().todo as Record<string, unknown>;
    assert.equal(todo['status'], 'pending', 'ack 不是确认入账，状态必须留在 pending');
    assert.ok(typeof todo['ackAt'] === 'string' && todo['ackAt'] !== '', 'ackAt 应被写上');
    assert.equal(todo['expenseId'], null, 'ack 不该生成支出');

    const after = await monthlyTotal(MONTH);
    assert.deepEqual(after, before, 'ack 不产生账目，报表必须一字不变');
  });

  test('hideAcked=1 把它排除；不带这个参数仍然返回（计划详情要看得到）', async () => {
    const { planId, rows } = await createAckedPlan('过滤用例');
    const todoId = String(rows[0]!['id']);

    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/ack`, headers: auth() });

    const hidden = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?status=pending&planId=${planId}&hideAcked=1`,
      headers: auth(),
    });
    const hiddenIds = (hidden.json().todos as Array<Record<string, unknown>>).map((t) => String(t['id']));
    assert.ok(!hiddenIds.includes(todoId), '确认过的期次不该再占「该处理了」的位置');

    const shown = await app.inject({
      method: 'GET',
      url: `/api/plan-todos?status=pending&planId=${planId}`,
      headers: auth(),
    });
    const shownIds = (shown.json().todos as Array<Record<string, unknown>>).map((t) => String(t['id']));
    assert.ok(shownIds.includes(todoId), '默认不过滤 —— 计划详情里那一期仍然是 pending');
  });

  test('重复 ack 不覆盖第一次的时间戳（「什么时候看到的」不该被第二次点击改写）', async () => {
    const { rows } = await createAckedPlan('幂等用例');
    const todoId = String(rows[0]!['id']);

    const first = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/ack`,
      headers: auth(),
    });
    const stamp = first.json().todo.ackAt as string;

    // 家人再点一次：不该报错，也不该改写时间戳
    const second = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/ack`,
      headers: auth(partnerToken),
    });
    assert.equal(second.statusCode, 200);
    assert.equal(second.json().todo.ackAt, stamp);
  });

  test('撤销确认会清掉 ack：那一期重新回到「要处理」里', async () => {
    const { rows } = await createAckedPlan('撤销清 ack');
    const todoId = String(rows[0]!['id']);

    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/ack`, headers: auth() });
    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/confirm`, headers: auth() });
    const reverted = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/revert`,
      headers: auth(),
    });

    const todo = reverted.json().todo as Record<string, unknown>;
    assert.equal(todo['ackAt'], null, '不清的话，撤销后的期次再也不会提醒，看起来像撤销失败');
    assert.equal(todo['willAutoPost'], false, '撤销会置 hold_auto_post，因此这一期不再自动入账');
  });

  test('恢复跳过同样清 ack', async () => {
    const { rows } = await createAckedPlan('恢复清 ack');
    const todoId = String(rows[0]!['id']);

    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/ack`, headers: auth() });
    await app.inject({ method: 'POST', url: `/api/plan-todos/${todoId}/skip`, headers: auth() });
    const restored = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${todoId}/restore`,
      headers: auth(),
    });

    assert.equal((restored.json().todo as Record<string, unknown>)['ackAt'], null);
  });

  test('willAutoPost 是「计划开了自动入账」与「本期没被摘出」的合取', async () => {
    const created = await createPlan({
      name: '合取判据',
      categoryId,
      paymentMethodId: cashId,
      source: 'manual',
      amountCents: 50_000,
      periods: 1,
      firstDueDate: '2028-09-05',
      // 计划**没有**开自动入账
      autoPost: false,
    });
    const planId = created.json().plan.id as string;
    const rows = (await todosOf(planId)).json().todos as Array<Record<string, unknown>>;

    // 只看计划那一级会判成「会」，于是界面给一个「确认」，
    // 用户点了以为没事 —— 那笔账却永远不入。所以这里必须是 false。
    assert.equal(rows[0]!['willAutoPost'], false);
  });

  test('hideAcked 取值非法 → 400（而不是被当成 true 静默多筛掉东西）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/plan-todos?hideAcked=maybe',
      headers: auth(),
    });
    assert.equal(res.statusCode, 400);
  });
});

describe('删除计划（DELETE /api/plans/:id）', () => {
  test('终止后的计划可以被彻底删除，待办清理，历史支出保留', async () => {
    const created = await app.inject({
      method: 'POST',
      url: '/api/plans',
      headers: auth(),
      payload: {
        name: '待删除计划',
        categoryId,
        paymentMethodId: cashId,
        source: 'manual',
        amountCents: 10_000,
        periods: 3,
        firstDueDate: '2028-10-01',
      },
    });
    assert.equal(created.statusCode, 201);
    const planId = created.json().plan.id as string;

    const listRes = await app.inject({
      method: 'GET',
      url: `/api/plans/${planId}`,
      headers: auth(),
    });
    const todos = listRes.json().todos as Array<{ id: string }>;
    const firstTodoId = todos[0]!.id;

    // 确认第 1 期，生成一笔支出
    const confirmRes = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${firstTodoId}/confirm`,
      headers: auth(),
    });
    assert.equal(confirmRes.statusCode, 200);
    const expenseId = confirmRes.json().expenseId as string;

    // 终止计划
    const endRes = await app.inject({
      method: 'POST',
      url: `/api/plans/${planId}/end`,
      headers: auth(),
    });
    assert.equal(endRes.statusCode, 200);

    // 家人尝试删除别人的计划 → 403
    const partnerDel = await app.inject({
      method: 'DELETE',
      url: `/api/plans/${planId}`,
      headers: auth(partnerToken),
    });
    assert.equal(partnerDel.statusCode, 403);

    // 创建者删除计划 → 204
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/plans/${planId}`,
      headers: auth(),
    });
    assert.equal(delRes.statusCode, 204);

    // 计划已被软删除，查找返回 404
    const getRes = await app.inject({
      method: 'GET',
      url: `/api/plans/${planId}`,
      headers: auth(),
    });
    assert.equal(getRes.statusCode, 404);

    // 列表中不再包含该计划
    const allPlans = await app.inject({
      method: 'GET',
      url: '/api/plans',
      headers: auth(),
    });
    const plansList = allPlans.json().plans as Array<{ id: string }>;
    assert.ok(!plansList.some((p) => p.id === planId));

    // 历史已生成的支出依然存在且有效
    const expenseCheck = await app.inject({
      method: 'GET',
      url: `/api/expenses`,
      headers: auth(),
    });
    const expenses = expenseCheck.json().items as Array<{ id: string }>;
    assert.ok(expenses.some((e) => e.id === expenseId));
  });

  test('未登录不能删除计划 → 401', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: '/api/plans/fake-id',
    });
    assert.equal(res.statusCode, 401);
  });
});
