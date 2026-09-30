/**
 * 支出与报表的端到端测试。
 *
 * 这是整个项目最该被覆盖的一组用例：支出的写入路径汇合了账单周期推算、
 * 权限判定、软删除与变更日志；报表则把「月份归属以还款日为准」这个口径
 * 兑现成用户能看到数字。这些地方错了都不会报错，只会安静地显示错误金额。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-exp-'));
const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;
/** 管理员（我） */
let token = '';
/** 另一个家庭成员的令牌 */
let partnerToken = '';

let foodParent = '';
let takeout = '';
let groceries = '';
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

  // 管理员创建第二个成员账号，用来验证「只能改自己记录的账」
  const created = await app.inject({
    method: 'POST',
    url: '/api/users',
    headers: auth(),
    payload: { username: 'partner', displayName: '家人', password: 'partner-pw' },
  });
  assert.equal(created.statusCode, 201);

  const partnerLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { username: 'partner', password: 'partner-pw' },
  });
  partnerToken = partnerLogin.json().token as string;

  // 分类：餐饮（一级）→ 外卖 / 买菜（二级）
  const parent = await app.inject({
    method: 'POST',
    url: '/api/categories',
    headers: auth(),
    payload: { name: '餐饮' },
  });
  foodParent = parent.json().category.id;

  const child = async (name: string) => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name, parentId: foodParent },
    });
    return res.json().category.id as string;
  };
  takeout = await child('外卖');
  groceries = await child('买菜');

  const cash = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '现金', type: 'cash' },
  });
  cashId = cash.json().paymentMethod.id;

  // 账单日 10、还款日 28 的信用卡
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

const create = (payload: Record<string, unknown>, t = token) =>
  app.inject({ method: 'POST', url: '/api/expenses', headers: auth(t), payload });

describe('记账：账单周期落库', () => {
  test('未登录不能记账', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses',
      payload: { amountCents: 100 },
    });
    assert.equal(res.statusCode, 401);
  });

  test('搜索：关键词能命中分类名（二级与一级），不只是备注', async () => {
    // 备注为空、分类为「餐饮/外卖」的记录：搜「外卖」（二级）与「餐饮」（一级）都应命中
    // 用一个独立的远期月份，避免污染 2026-01 的月度报表用例
    const seeded = await create({
      amountCents: 4_200,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2024-06-05',
    });
    assert.equal(seeded.statusCode, 201);

    const byChild = await app.inject({
      method: 'GET',
      url: '/api/expenses?q=' + encodeURIComponent('外卖'),
      headers: auth(),
    });
    assert.ok(
      byChild.json().items.some((item: { id: string }) => item.id === seeded.json().expense.id),
      '二级分类名应命中',
    );

    const byParent = await app.inject({
      method: 'GET',
      url: '/api/expenses?q=' + encodeURIComponent('餐饮'),
      headers: auth(),
    });
    assert.ok(
      byParent.json().items.some((item: { id: string }) => item.id === seeded.json().expense.id),
      '一级分类名应命中',
    );
  });

  test('现金：入账日与还款日都等于消费日', async () => {
    const res = await create({
      amountCents: 3200,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
      note: '午饭',
    });
    assert.equal(res.statusCode, 201);

    const expense = res.json().expense;
    assert.equal(expense.postingDate, '2026-01-09');
    assert.equal(expense.repaymentDate, '2026-01-09');
    assert.equal(expense.source, 'manual');
    assert.equal(expense.ownerName, '我');
  });

  test('信用卡：9 日消费 → 本月 10 日入账、28 日还款', async () => {
    const res = await create({
      amountCents: 15000,
      categoryId: takeout,
      paymentMethodId: cardId,
      spendDate: '2026-01-09',
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().expense.postingDate, '2026-01-10');
    assert.equal(res.json().expense.repaymentDate, '2026-01-28');
  });

  test('信用卡：11 日消费 → 次月入账、次月还款（归属下个月）', async () => {
    const res = await create({
      amountCents: 8000,
      categoryId: groceries,
      paymentMethodId: cardId,
      spendDate: '2026-01-11',
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().expense.postingDate, '2026-02-10');
    assert.equal(res.json().expense.repaymentDate, '2026-02-28');
  });

  test('退款用负数金额表示', async () => {
    const res = await create({
      amountCents: -15000,
      categoryId: takeout,
      paymentMethodId: cardId,
      spendDate: '2026-01-09',
      note: '退货',
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().expense.amountCents, -15000);
  });
});

describe('记账：入参防呆', () => {
  test('金额为 0 → 400', async () => {
    const res = await create({
      amountCents: 0,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
    });
    assert.equal(res.statusCode, 400);
  });

  test('金额多输几个 0 → 400，且提示能看懂', async () => {
    const res = await create({
      amountCents: 123_456_789_012,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /上限/);
  });

  test('金额传字符串 → 400（不做隐式转换）', async () => {
    const res = await create({
      amountCents: '3200',
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
    });
    assert.equal(res.statusCode, 400);
  });

  test('消费日格式非法 → 400', async () => {
    const res = await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026/01/09',
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /YYYY-MM-DD/);
  });

  test('不存在的日期 → 400', async () => {
    const res = await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-02-30',
    });
    assert.equal(res.statusCode, 400);
  });

  test('停用的分类不能用于新记录', async () => {
    const created = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '暂时不用' },
    });
    const id = created.json().category.id;

    await app.inject({
      method: 'PATCH',
      url: `/api/categories/${id}`,
      headers: auth(),
      payload: { isEnabled: false },
    });

    const res = await create({
      amountCents: 100,
      categoryId: id,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /已停用/);
  });

  test('备注超长 → 400', async () => {
    const res = await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-01-09',
      note: 'x'.repeat(201),
    });
    assert.equal(res.statusCode, 400);
  });
});

describe('账单日期预览', () => {
  /**
   * 这个接口的存在意义是让记账抽屉能说出「这笔会记在哪个月」。
   * 它必须与实际写入的结果**完全一致**，否则提示本身就成了新的误导来源。
   */
  test('预览结果与真实写入完全一致（信用卡跨月）', async () => {
    const preview = await app.inject({
      method: 'POST',
      url: '/api/expenses/preview',
      headers: auth(),
      payload: { spendDate: '2026-11-11', paymentMethodId: cardId },
    });
    assert.equal(preview.statusCode, 200);
    assert.equal(preview.json().postingDate, '2026-12-10');
    assert.equal(preview.json().repaymentDate, '2026-12-28');

    const created = await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cardId,
      spendDate: '2026-11-11',
    });
    assert.equal(created.json().expense.postingDate, preview.json().postingDate);
    assert.equal(created.json().expense.repaymentDate, preview.json().repaymentDate);
  });

  test('现金：预览的入账日与还款日都等于消费日', async () => {
    const preview = await app.inject({
      method: 'POST',
      url: '/api/expenses/preview',
      headers: auth(),
      payload: { spendDate: '2026-11-11', paymentMethodId: cashId },
    });
    assert.equal(preview.json().postingDate, '2026-11-11');
    assert.equal(preview.json().repaymentDate, '2026-11-11');
  });

  test('预览不写库', async () => {
    const before = db.prepare('SELECT COUNT(*) AS n FROM expenses').get();
    await app.inject({
      method: 'POST',
      url: '/api/expenses/preview',
      headers: auth(),
      payload: { spendDate: '2026-11-11', paymentMethodId: cashId },
    });
    const after = db.prepare('SELECT COUNT(*) AS n FROM expenses').get();
    assert.equal(Number(after?.['n']), Number(before?.['n']));
  });

  test('日期非法 → 400（与真实写入同一套校验）', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/preview',
      headers: auth(),
      payload: { spendDate: '2026-11-31', paymentMethodId: cashId },
    });
    assert.equal(res.statusCode, 400);
  });

  test('未登录 → 401', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/preview',
      payload: { spendDate: '2026-11-11', paymentMethodId: cashId },
    });
    assert.equal(res.statusCode, 401);
  });
});

describe('付款方式排序', () => {
  /**
   * 「列表第一个」就是记账抽屉的默认选中项，所以顺序有实际后果。
   * 曾经只按 name 排：SQLite 走 BINARY 排序即 UTF-8 字节序，
   * 「招行信用卡」的「招」排在「现金」的「现」前面 —— 于是随手记的一笔
   * 默认用了信用卡、还款日跨到下个月，本月报表纹丝不动，看起来像没记上。
   */
  test('按建立顺序返回，现金排在信用卡之前', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/payment-methods',
      headers: auth(),
    });
    const names = (res.json().paymentMethods as Array<{ name: string }>).map((item) => item.name);
    const cashIndex = names.indexOf('现金');
    const cardIndex = names.indexOf('招行信用卡');

    assert.ok(cashIndex >= 0 && cardIndex >= 0);
    assert.ok(cashIndex < cardIndex, `「现金」应先建所以排在前，实际顺序：${names.join(' / ')}`);
  });
});

describe('权限：读全开放，写仅限创建者', () => {
  let myExpenseId = '';

  test('家人能看到我记的账', async () => {
    const res = await create(
      {
        amountCents: 5000,
        categoryId: takeout,
        paymentMethodId: cashId,
        spendDate: '2026-03-05',
        note: '我的记录',
      },
      token,
    );
    myExpenseId = res.json().expense.id;

    const list = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-03',
      headers: auth(partnerToken),
    });
    assert.equal(list.statusCode, 200);
    assert.ok(
      (list.json().items as Array<{ id: string }>).some((item) => item.id === myExpenseId),
      '共享账本：家人应当能看到我记的账',
    );
  });

  test('家人不能修改我记的账 → 403', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/expenses/${myExpenseId}`,
      headers: auth(partnerToken),
      payload: { amountCents: 1 },
    });
    assert.equal(res.statusCode, 403);
    assert.match(res.json().error, /只能修改自己记录的/);
  });

  test('家人不能删除我记的账 → 403', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/expenses/${myExpenseId}`,
      headers: auth(partnerToken),
    });
    assert.equal(res.statusCode, 403);
  });

  test('我自己可以修改', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/expenses/${myExpenseId}`,
      headers: auth(),
      payload: { amountCents: 6600, note: '改过了' },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().expense.amountCents, 6600);
    assert.equal(res.json().expense.note, '改过了');
  });

  test('改消费日会重算入账日与还款日', async () => {
    // 3/5 用信用卡（账单日 10）→ 3/10 入账、3/28 还款
    const created = await create({
      amountCents: 1000,
      categoryId: takeout,
      paymentMethodId: cardId,
      spendDate: '2026-04-05',
    });
    const id = created.json().expense.id;
    assert.equal(created.json().expense.repaymentDate, '2026-04-28');

    // 改成 4/11 → 跨到 5 月
    const updated = await app.inject({
      method: 'PATCH',
      url: `/api/expenses/${id}`,
      headers: auth(),
      payload: { spendDate: '2026-04-11' },
    });
    assert.equal(updated.statusCode, 200);
    assert.equal(updated.json().expense.postingDate, '2026-05-10');
    assert.equal(
      updated.json().expense.repaymentDate,
      '2026-05-28',
      '改了消费日却沿用旧的还款日，月份归属就会错',
    );
  });

  test('换支付方式也会重算日期', async () => {
    const created = await create({
      amountCents: 2000,
      categoryId: takeout,
      paymentMethodId: cardId,
      spendDate: '2026-05-20',
    });
    const id = created.json().expense.id;
    assert.equal(created.json().expense.repaymentDate, '2026-06-28');

    const updated = await app.inject({
      method: 'PATCH',
      url: `/api/expenses/${id}`,
      headers: auth(),
      payload: { paymentMethodId: cashId },
    });
    assert.equal(updated.json().expense.repaymentDate, '2026-05-20', '换成现金后应回到消费日本身');
  });

  test('软删除后不再出现在列表，但历史报表口径不受影响', async () => {
    const created = await create({
      amountCents: 999,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-06-01',
    });
    const id = created.json().expense.id;

    const deleted = await app.inject({
      method: 'DELETE',
      url: `/api/expenses/${id}`,
      headers: auth(),
    });
    assert.equal(deleted.statusCode, 204);

    const list = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-06',
      headers: auth(),
    });
    assert.equal((list.json().items as unknown[]).length, 0, '已删除的记录不该出现在列表里');

    const detail = await app.inject({
      method: 'GET',
      url: `/api/expenses/${id}`,
      headers: auth(),
    });
    assert.equal(detail.statusCode, 404);
  });
});

describe('列表筛选与分页', () => {
  test('按还款日所在月份筛选（当指定 by=repayment_date 时）', async () => {
    const jan = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-01&by=repayment_date',
      headers: auth(),
    });
    const janItems = jan.json().items as Array<Record<string, unknown>>;

    assert.ok(janItems.length >= 2);
    for (const item of janItems) {
      assert.ok(
        String(item['repaymentDate']).startsWith('2026-01'),
        `2026-01 的列表里不该出现还款日为 ${item['repaymentDate']} 的记录`,
      );
    }

    // 1/11 那笔虽然消费在 1 月，但还款日在 2 月，指定 by=repayment_date 时归入 2 月
    const feb = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-02&by=repayment_date',
      headers: auth(),
    });
    assert.ok(
      (feb.json().items as Array<Record<string, unknown>>).some(
        (item) => item['spendDate'] === '2026-01-11',
      ),
      '1/11 消费、2/28 还款的记录应出现在 2 月还款列表里',
    );
  });

  test('默认按消费日所在月份筛选（流水展示口径）', async () => {
    const jan = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-01',
      headers: auth(),
    });
    const janItems = jan.json().items as Array<Record<string, unknown>>;
    assert.ok(
      janItems.some((item) => item['spendDate'] === '2026-01-11'),
      '1/11 消费的记录默认应出现在 1 月流水列表里',
    );
  });

  test('给一级分类能带出它的二级分类', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/expenses?month=2026-01&categoryId=${foodParent}`,
      headers: auth(),
    });
    const items = res.json().items as Array<Record<string, unknown>>;
    assert.ok(items.length > 0, '点「餐饮」应当看到其下所有子分类的记录');
  });

  test('给二级分类只返回该二级分类的记录', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/expenses?month=2026-01&categoryId=${groceries}`,
      headers: auth(),
    });
    const items = res.json().items as Array<Record<string, unknown>>;
    for (const item of items) {
      assert.equal(item['categoryId'], groceries);
    }
  });

  test('备注关键词搜索', async () => {
    await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-07-01',
      note: '独特关键词甲',
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/expenses?q=${encodeURIComponent('独特关键词甲')}`,
      headers: auth(),
    });
    assert.equal((res.json().items as unknown[]).length, 1);
  });

  test('搜索里的 % 不会被当成通配符', async () => {
    await create({
      amountCents: 100,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-07-02',
      note: '折扣 50% 的券',
    });

    const res = await app.inject({
      method: 'GET',
      url: `/api/expenses?q=${encodeURIComponent('50%')}`,
      headers: auth(),
    });
    const items = res.json().items as Array<Record<string, unknown>>;
    assert.equal(items.length, 1, '用户搜「50%」时 % 是字面量，不该匹配任意字符');
  });

  test('键集分页不重复也不遗漏', async () => {
    const first = await app.inject({
      method: 'GET',
      url: '/api/expenses?month=2026-01&limit=2',
      headers: auth(),
    });
    const firstBody = first.json();
    assert.equal((firstBody.items as unknown[]).length, 2);
    assert.equal(firstBody.hasMore, true);

    const second = await app.inject({
      method: 'GET',
      url: `/api/expenses?month=2026-01&limit=2&cursor=${encodeURIComponent(String(firstBody.nextCursor))}`,
      headers: auth(),
    });

    const firstIds = (firstBody.items as Array<{ id: string }>).map((item) => item.id);
    const secondIds = (second.json().items as Array<{ id: string }>).map((item) => item.id);

    assert.equal(
      firstIds.filter((id) => secondIds.includes(id)).length,
      0,
      '分页不该重复返回同一条记录',
    );
  });
});

describe('报表', () => {
  test('month 必填（服务端不推算当前月份）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly',
      headers: auth(),
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /不推算/);
  });

  test('月度报表：总额、一级分类构成、按支付方式', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-01',
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const report = res.json().report;

    // 1 月：现金 3200 + 信用卡 15000 − 退款 15000 = 3200
    assert.equal(report.totalCents, 3200);
    assert.equal(report.count, 3);

    // 二级分类（外卖 / 买菜）应归并到一级分类「餐饮」
    assert.equal(report.categories.length, 1);
    assert.equal(report.categories[0].categoryId, foodParent);
    assert.equal(report.categories[0].name, '餐饮');
    assert.equal(report.categories[0].cents, 3200);
    assert.equal(report.categories[0].ratio, 1);

    const card = (report.paymentMethods as Array<Record<string, unknown>>).find(
      (item) => item['paymentMethodId'] === cardId,
    );
    assert.ok(card !== undefined);
    assert.equal(card['type'], 'credit');
    assert.equal(card['repaymentDate'], '2026-01-28', '信用卡的还款日应带出来供界面显示待还');
  });

  test('环比：上期为 0 时不给百分比（避免「涨了 100%」的误导）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2025-11',
      headers: auth(),
    });
    const report = res.json().report;
    assert.equal(report.totalCents, 0);
    assert.equal(report.change.ratio, null);
  });

  test('环比：有上期数据时算出比例', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-02',
      headers: auth(),
    });
    const report = res.json().report;
    assert.equal(report.previous.month, '2026-01');
    assert.equal(report.change.deltaCents, report.totalCents - report.previous.totalCents);
    assert.notEqual(report.change.ratio, null);
  });

  test('年度报表补满 12 个月，图表不会缺格', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/yearly?year=2026',
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const report = res.json().report;
    assert.equal(report.months.length, 12);
    assert.equal(report.months[0].month, '2026-01');
    assert.equal(report.months[11].month, '2026-12');

    const sum = (report.months as Array<{ totalCents: number }>).reduce(
      (acc, item) => acc + item.totalCents,
      0,
    );
    assert.equal(sum, report.totalCents, '12 个月之和应等于年度总额');
  });

  test('按记录人拆分', async () => {
    // 两人各记一笔，报表应当各占一行
    await create(
      {
        amountCents: 777,
        categoryId: takeout,
        paymentMethodId: cashId,
        spendDate: '2026-08-08',
        note: '家人记的',
      },
      partnerToken,
    );
    await create({
      amountCents: 223,
      categoryId: groceries,
      paymentMethodId: cashId,
      spendDate: '2026-08-09',
      note: '我记的',
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-08',
      headers: auth(),
    });
    const report = res.json().report;

    const members = report.members as Array<Record<string, unknown>>;
    assert.equal(members.length, 2, '两个人都记过账时应各占一行');
    assert.equal(
      members.reduce((acc, item) => acc + Number(item['cents']), 0),
      1000,
      '按人拆分之和应等于总额',
    );
    assert.equal(report.totalCents, 1000);

    // 按记录人筛选时，只应看到该人的记录
    const partnerId = members.find((item) => item['name'] === '家人')?.['ownerId'] as string;
    assert.ok(partnerId !== undefined);

    const filtered = await app.inject({
      method: 'GET',
      url: `/api/reports/monthly?month=2026-08&ownerId=${partnerId}`,
      headers: auth(),
    });
    assert.equal(filtered.json().report.totalCents, 777);
  });

  /**
   * 以下三条覆盖第三轮报表新增的三项指标。
   *
   * 刻意用 2026-09（此前没有任何测试用过）：报表是**聚合**，断言依赖整月数据。
   * 直接借用一个已被别处写过的月份，等于把这条测试的成功与否挂在
   * 另一个测试的执行顺序上 —— 那种耦合只会在某天重排测试时爆发。
   * 上一期这里取 2026-08，它在「按记录人拆分」里已经被写成 1000 元，
   * 于是「有上期」与「没上期」两种情况可以一次覆盖掉。
   */
  test('单笔最高：取金额最大的一笔，且归并到一级分类', async () => {
    const jan = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-01',
      headers: auth(),
    });
    const largest = jan.json().report.largest;

    assert.ok(largest !== null, '有记录的月份必须有单笔最高');
    assert.equal(largest.cents, 15000);
    assert.equal(largest.categoryName, '餐饮', '应归并到一级分类，与报表其余部分同粒度');
    assert.equal(largest.repaymentDate, '2026-01-28');
    assert.ok(largest.cents > 0, '退款的负数金额不该被当成「最大的一笔」');
  });

  test('没有记录的月份，单笔最高为 null（不是 0 元的一条假记录）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2025-11',
      headers: auth(),
    });
    assert.equal(res.json().report.largest, null);
  });

  test('分类环比：有上期给比例、没有上期给 null', async () => {
    // 造一个第二个一级分类 —— 演示数据全挂在「餐饮」下，只有一个桶时
    // 「环比」是不是按分类算的根本验不出来。
    const traffic = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '交通' },
    });
    const taxi = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '打车', parentId: traffic.json().category.id },
    });

    await create({
      amountCents: 1000,
      categoryId: takeout,
      paymentMethodId: cashId,
      spendDate: '2026-09-05',
    });
    await create({
      amountCents: 5000,
      categoryId: taxi.json().category.id,
      paymentMethodId: cashId,
      spendDate: '2026-09-06',
    });

    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/monthly?month=2026-09',
      headers: auth(),
    });
    const report = res.json().report;
    assert.equal(report.totalCents, 6000);

    const buckets = report.categories as Array<Record<string, unknown>>;
    const food = buckets.find((item) => item['name'] === '餐饮');
    const transport = buckets.find((item) => item['name'] === '交通');

    // 餐饮：上期（8 月）也是 1000，持平
    assert.ok(food !== undefined);
    assert.equal(food['previousCents'], 1000);
    assert.equal(food['changeRatio'], 0, '持平是 0，不是 null');

    // 交通：上期没有这个分类 —— 给 null 而不是「涨了 100%」
    assert.ok(transport !== undefined);
    assert.equal(transport['previousCents'], 0);
    assert.equal(transport['changeRatio'], null);

    // 同比：去年同月没有数据
    assert.equal(report.yearAgo.label, '09');
    assert.equal(report.yearAgo.totalCents, 0);
    assert.equal(report.yearAgo.change.ratio, null);
  });

  test('年度报表：同比取去年整年', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/yearly?year=2026',
      headers: auth(),
    });
    const report = res.json().report;

    assert.equal(report.yearAgo.label, '去年');
    assert.equal(report.yearAgo.totalCents, 0, '2025 年没有任何记录');
    assert.equal(report.yearAgo.change.ratio, null);
    assert.equal(report.yearAgo.change.deltaCents, report.totalCents);
  });

  test('汇总报表：全量统计指标与年度拆分', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/reports/summary',
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);
    const report = res.json().report;
    assert.ok(report.totalCents > 0);
    assert.ok(report.count > 0);
    assert.ok(Array.isArray(report.years));
    assert.ok(Array.isArray(report.categories));
    assert.ok(Array.isArray(report.members));
    assert.ok(report.recordedDays >= 1);
  });
});

describe('分类转移', () => {
  test('转移后原分类下的记录归零，可停用', async () => {
    // 先把 2026-01 的餐饮记录都挪到 groceries，再试着停用 takeout
    const moved = await app.inject({
      method: 'POST',
      url: '/api/expenses/transfer',
      headers: auth(),
      payload: { fromCategoryId: takeout, toCategoryId: groceries },
    });
    assert.equal(moved.statusCode, 200);
    assert.ok(Number(moved.json().moved) > 0);

    // 还有别的月份的记录也一起被转移了，此时 takeout 应为空
    const list = await app.inject({
      method: 'GET',
      url: `/api/expenses?categoryId=${takeout}`,
      headers: auth(),
    });
    assert.equal((list.json().items as unknown[]).length, 0);

    const disable = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${takeout}`,
      headers: auth(),
      payload: { isEnabled: false },
    });
    assert.equal(disable.statusCode, 200, '腾空后应当可以停用');
  });

  test('转移到不存在的分类 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/transfer',
      headers: auth(),
      payload: { fromCategoryId: groceries, toCategoryId: '01M3FARY3CT5HGYJ37PB1E2TW7' },
    });
    assert.equal(res.statusCode, 400);
  });
});

describe('账号管理', () => {
  test('普通成员不能创建账号 → 403', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/users',
      headers: auth(partnerToken),
      payload: { username: 'sneaky', password: 'whatever123' },
    });
    assert.equal(res.statusCode, 403);
  });

  test('成员可以看到彼此（界面要显示记录人）', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/users', headers: auth(partnerToken) });
    assert.equal(res.statusCode, 200);
    assert.equal((res.json().users as unknown[]).length, 2);
  });

  test('口令过短 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/users',
      headers: auth(),
      payload: { username: 'shorty', password: '123' },
    });
    assert.equal(res.statusCode, 400);
  });

  test('不能把唯一的管理员降级（否则没人能进后台）', async () => {
    const me = await app.inject({ method: 'GET', url: '/api/auth/me', headers: auth() });
    const myId = me.json().user.id as string;

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/users/${myId}`,
      headers: auth(),
      payload: { role: 'member' },
    });
    assert.equal(res.statusCode, 409);
    assert.match(res.json().error, /唯一/);
  });
});

describe('批量创建支出（POST /api/expenses/batch）', () => {
  test('正常批量创建多笔支出', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/batch',
      headers: auth(),
      payload: {
        items: [
          {
            amountCents: 1500,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-10',
            note: '买菜A',
          },
          {
            amountCents: 2500,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-11',
            note: '买菜B',
          },
        ],
      },
    });
    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.createdCount, 2);
    assert.equal(body.expenseIds.length, 2);

    // 验证查出其中一笔
    const getRes = await app.inject({
      method: 'GET',
      url: `/api/expenses/${body.expenseIds[0]}`,
      headers: auth(),
    });
    assert.equal(getRes.statusCode, 200);
    assert.equal(getRes.json().expense.amountCents, 1500);
    assert.equal(getRes.json().expense.note, '买菜A');
  });

  test('items 不是数组 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/batch',
      headers: auth(),
      payload: { items: 'not-array' },
    });
    assert.equal(res.statusCode, 400);
  });

  /**
   * 导入健壮性的核心用例：**一笔坏数据不该作废整批**。
   *
   * 旧的「整批回滚」语义下，3228 笔的 CSV 只要有一行引用了已失效的分类，
   * 全部作废；而且返回的只是一句笼统报错，用户无从知道是哪一行。
   * 现在改为逐条容错：好行照常写入，坏行被跳过并在 failed 里回报下标与原因。
   */
  test('逐条容错：中间一条分类无效时，其余照常写入并回报行号', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/batch',
      headers: auth(),
      payload: {
        items: [
          {
            amountCents: 3000,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-12',
            note: '容错首行',
          },
          {
            amountCents: 4000,
            categoryId: '01INVALID00000000000000000',
            paymentMethodId: cashId,
            spendDate: '2026-09-12',
            note: '容错坏行',
          },
          {
            amountCents: 5000,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-13',
            note: '容错末行',
          },
        ],
      },
    });

    assert.equal(res.statusCode, 201, '单行业务无效不该让整批失败');
    const body = res.json();
    assert.equal(body.createdCount, 2);
    assert.equal(body.expenseIds.length, 2);
    assert.equal(body.failed.length, 1, '只有坏行被跳过');
    assert.equal(body.failed[0].index, 1, '下标应是入参数组下标（从 0 起）');
    assert.ok(
      typeof body.failed[0].reason === 'string' && body.failed[0].reason.length > 0,
      'failed 里要带可读的原因，前端才能告诉用户哪一行错在哪',
    );

    // 数据库里确实只有两笔好数据，坏行没有落库
    const list = await app.inject({
      method: 'GET',
      url: `/api/expenses?q=${encodeURIComponent('容错')}`,
      headers: auth(),
    });
    const notes = (list.json().items as Array<{ note: string }>)
      .map((item) => item.note)
      .sort();
    assert.deepEqual(notes, ['容错末行', '容错首行']);
  });

  test('全部有效时 failed 为空', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/batch',
      headers: auth(),
      payload: {
        items: [
          {
            amountCents: 100,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-14',
          },
          {
            amountCents: 200,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-14',
          },
        ],
      },
    });

    assert.equal(res.statusCode, 201);
    assert.equal(res.json().createdCount, 2);
    assert.deepEqual(res.json().failed, []);
  });

  test('结构性错误（某行缺 categoryId）仍然整批 400', async () => {
    // 这是客户端 bug 而非数据问题：逐条跳过会把 bug 藏起来，所以整批拒绝
    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses/batch',
      headers: auth(),
      payload: {
        items: [
          {
            amountCents: 100,
            categoryId: groceries,
            paymentMethodId: cashId,
            spendDate: '2026-09-15',
          },
          { amountCents: 200, paymentMethodId: cashId, spendDate: '2026-09-15' },
        ],
      },
    });
    assert.equal(res.statusCode, 400);
  });
});

