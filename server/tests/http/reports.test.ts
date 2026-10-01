/**
 * 待还口径与「转分期」的端到端测试。
 *
 * 守的是一个**只在跨月时才暴露**的账务正确性缺陷：一笔信用卡支出转成分期后，
 * 它在下月待还里的呈现必须是「分期后的一期金额」，而不是原全额；且分期期次
 * 一旦确认入账，就不能再被待还口径重复算一遍。
 *
 * 这些错了都不会报错，只会让某个月的「要还多少」安静地多算或少算一笔 ——
 * 所以断言全部落在具体数字上，而不是「接口返回 200」。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-report-'));
const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;
let token = '';
let partnerToken = '';
let categoryId = '';
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
    payload: { name: '数码' },
  });
  categoryId = category.json().category.id as string;

  // 账单日 10 / 还款日 28：消费日 3-05 的账落在 3-10 入账、3-28 还款
  const card = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '测试信用卡', type: 'credit', billingDay: 10, repaymentDay: 28 },
  });
  cardId = card.json().paymentMethod.id as string;
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

const createExpense = (payload: Record<string, unknown>, t = token) =>
  app.inject({ method: 'POST', url: '/api/expenses', headers: auth(t), payload });

const monthly = async (month: string) =>
  (
    await app.inject({
      method: 'GET',
      url: `/api/reports/monthly?month=${month}`,
      headers: auth(),
    })
  ).json().report as Record<string, unknown>;

/** 某月报表里的「下月应还合计」（分）。 */
const nextMonthDue = async (month: string) => Number((await monthly(month)).nextMonthDueTotalCents);

describe('转分期后次月待还的口径', () => {
  /**
   * 看 2029-02 的报表，它的「次月」是 2029-03。原始支出与第 1 期都落在 3-28，
   * 这样「原全额 → 一期金额」的替换可以在同一个刻度上直接对比。
   */
  const VIEW_MONTH = '2029-02';
  const DUE_MONTH = '2029-03';
  const TOTAL_CENTS = 1_200_000; // ¥12,000
  const PERIODS = 12;
  const PERIOD_CENTS = 100_000; // 12000 / 12

  let expenseId = '';
  let planId = '';

  test('转换前：次月待还是原全额', async () => {
    const res = await createExpense({
      amountCents: TOTAL_CENTS,
      categoryId,
      paymentMethodId: cardId,
      spendDate: '2029-03-05',
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().expense.repaymentDate, DUE_MONTH + '-28');
    expenseId = res.json().expense.id as string;

    assert.equal(await nextMonthDue(VIEW_MONTH), TOTAL_CENTS);
  });

  test('转分期是一个原子请求：建计划 + 软删原支出一起完成', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/plans',
      headers: auth(),
      payload: {
        name: '相机分期',
        categoryId,
        paymentMethodId: cardId,
        source: 'installment',
        totalAmountCents: TOTAL_CENTS,
        purchaseDate: '2029-03-05',
        periods: PERIODS,
        firstDueDate: DUE_MONTH + '-28',
        consumeExpenseId: expenseId,
      },
    });
    assert.equal(res.statusCode, 201);
    planId = res.json().plan.id as string;

    // 原支出已打成墓碑（软删），不会再被任何报表口径统计
    const row = db.prepare('SELECT deleted_at FROM expenses WHERE id = ?').get(expenseId) as
      | Record<string, unknown>
      | undefined;
    assert.ok(row !== undefined && row['deleted_at'] !== null, '原支出应被软删');

    const todos = (await app.inject({ method: 'GET', url: `/api/plans/${planId}`, headers: auth() }))
      .json().todos as Array<Record<string, unknown>>;
    assert.equal(todos[0]!['status'], 'pending');
    assert.equal(todos[0]!['amountCents'], PERIOD_CENTS);
    assert.equal(todos[0]!['repaymentDate'], DUE_MONTH + '-28');
  });

  test('转换后：次月待还是「一期金额」，原全额不再出现，也没有并存', async () => {
    const cents = await nextMonthDue(VIEW_MONTH);
    assert.equal(cents, PERIOD_CENTS, '原全额应被 12 期的一期金额取代');
    assert.notEqual(cents, TOTAL_CENTS + PERIOD_CENTS, '原全额与期次绝不能并存');
  });

  test('再下个月：期次按其还款日归月，出现在它的月份里', async () => {
    // 2029-03 报表的次月是 2029-04，对应第 2 期（4-28）
    assert.equal(await nextMonthDue(DUE_MONTH), PERIOD_CENTS);
  });

  test('期次确认入账后：不重复计数（同一期不会既算 todo 又算 expense）', async () => {
    const todos = (await app.inject({ method: 'GET', url: `/api/plans/${planId}`, headers: auth() }))
      .json().todos as Array<Record<string, unknown>>;
    const first = todos.find((item) => item['periodSeq'] === 1)!;

    const confirm = await app.inject({
      method: 'POST',
      url: `/api/plan-todos/${String(first['id'])}/confirm`,
      headers: auth(),
    });
    assert.equal(confirm.statusCode, 200);
    assert.equal(confirm.json().todo.status, 'confirmed');

    // 这一期现在以一条 source='plan' 的支出存在，pending 口径不再算它。
    // 若两边都算，这里会变成 2 × PERIOD_CENTS。
    assert.equal(await nextMonthDue(VIEW_MONTH), PERIOD_CENTS);
  });
});

describe('转分期的原子性', () => {
  /**
   * 用一个**上面那个分期计划够不到**的月份（它最远只到 2030-02），
   * 所以这里的待还数字就是这个用例自己的，不会被别的待办污染。
   */
  const DUE_MONTH = '2030-06';
  const VIEW_MONTH = '2030-05';

  test('消费一条不属于自己的支出 → 整体回滚，不留下任何计划或期次', async () => {
    const partnerExpense = await createExpense(
      {
        amountCents: 600_000,
        categoryId,
        paymentMethodId: cardId,
        spendDate: '2030-06-05',
      },
      partnerToken,
    );
    assert.equal(partnerExpense.statusCode, 201);
    const partnerExpenseId = partnerExpense.json().expense.id as string;

    // 家人这条账落在 6-28，属于 2030-05 报表的次月
    assert.equal(await nextMonthDue(VIEW_MONTH), 600_000);

    const res = await app.inject({
      method: 'POST',
      url: '/api/plans',
      headers: auth(), // 我（非记录人）
      payload: {
        name: '越权转分期',
        categoryId,
        paymentMethodId: cardId,
        source: 'installment',
        totalAmountCents: 600_000,
        purchaseDate: '2030-06-05',
        periods: 6,
        firstDueDate: `${DUE_MONTH}-28`,
        consumeExpenseId: partnerExpenseId,
      },
    });
    assert.equal(res.statusCode, 403, '不能把别人的支出转成自己的计划');

    // 计划必须整体回滚掉，而不是「计划建好了、原支出没删掉」
    const plans = (await app.inject({ method: 'GET', url: '/api/plans', headers: auth() })).json()
      .plans as Array<Record<string, unknown>>;
    assert.ok(!plans.some((item) => item['name'] === '越权转分期'), '失败时不应留下半截计划');

    // 原支出仍然活着、金额不变：不存在「原全额 + 期次」并存
    const stillThere = await app.inject({
      method: 'GET',
      url: `/api/expenses/${partnerExpenseId}`,
      headers: auth(),
    });
    assert.equal(stillThere.statusCode, 200);
    assert.equal(await nextMonthDue(VIEW_MONTH), 600_000);
  });

  test('消费一个不存在的支出 → 404，且不留下计划', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/plans',
      headers: auth(),
      payload: {
        name: '幽灵支出转分期',
        categoryId,
        paymentMethodId: cardId,
        source: 'installment',
        totalAmountCents: 100_000,
        purchaseDate: '2029-06-05',
        periods: 3,
        firstDueDate: '2029-06-28',
        consumeExpenseId: '01NOSUCHULID0000000000000',
      },
    });
    assert.equal(res.statusCode, 404);

    const plans = (await app.inject({ method: 'GET', url: '/api/plans', headers: auth() })).json()
      .plans as Array<Record<string, unknown>>;
    assert.ok(!plans.some((item) => item['name'] === '幽灵支出转分期'));
  });
});
