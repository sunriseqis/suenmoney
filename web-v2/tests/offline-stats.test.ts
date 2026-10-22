/**
 * 离线本地统计的单元测试。
 *
 * 这组函数的错法是**静默的**：归属月份算错，数字仍是一个合理的金额，
 * 只是与在线报表对不上；负数退款混进「单笔最高」，用户看到的最大一笔是负的。
 * 所以这里重点盯：还款日归属、一级归并、支付归并、退款处理。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import type { Expense } from '../src/api/types.ts';
import { computeOfflineStats } from '../src/utils/offline-stats.ts';

function makeExpense(overrides: Partial<Expense>): Expense {
  return {
    id: overrides.id ?? 'e1',
    ownerId: 'u1',
    ownerName: '我',
    amountCents: 0,
    categoryId: 'c1',
    categoryName: '餐饮',
    categoryIcon: '',
    categoryColor: '',
    parentCategoryColor: null,
    parentCategoryName: null,
    paymentMethodId: 'p1',
    paymentMethodName: '现金',
    paymentMethodType: 'cash',
    spendDate: '2026-01-11',
    postingDate: '2026-01-11',
    repaymentDate: '2026-01-11',
    note: '',
    source: 'manual',
    planId: null,
    planPeriodSeq: null,
    createdAt: '2026-01-11T00:00:00.000Z',
    updatedAt: '2026-01-11T00:00:00.000Z',
    ...overrides,
  };
}

describe('computeOfflineStats 期间归属（按 repaymentDate）', () => {
  test('✱ 跨月信用卡：1 月消费、2 月还款，归属 2 月而非 1 月', () => {
    const expenses = [
      // 信用卡：1 月 11 日刷、2 月 28 日还 → 报表口径属于 2 月
      makeExpense({
        id: 'credit',
        amountCents: 10_000,
        spendDate: '2026-01-11',
        repaymentDate: '2026-02-28',
        paymentMethodId: 'pm-credit',
        paymentMethodType: 'credit',
      }),
      // 现金：1 月消费、1 月记账 → 属于 1 月
      makeExpense({
        id: 'cash',
        amountCents: 5_000,
        spendDate: '2026-01-20',
        repaymentDate: '2026-01-20',
      }),
    ];

    const february = computeOfflineStats(expenses, { scope: 'month', month: '2026-02' });
    assert.equal(february.totalCents, 10_000);
    assert.equal(february.count, 1);

    const january = computeOfflineStats(expenses, { scope: 'month', month: '2026-01' });
    assert.equal(january.totalCents, 5_000);
    assert.equal(january.count, 1);
  });

  test('年档按 YYYY- 前缀过滤，全部档不过滤', () => {
    const expenses = [
      makeExpense({ id: 'a', amountCents: 100, repaymentDate: '2026-03-01' }),
      makeExpense({ id: 'b', amountCents: 200, repaymentDate: '2025-12-31' }),
    ];
    assert.equal(computeOfflineStats(expenses, { scope: 'year', year: '2026' }).totalCents, 100);
    assert.equal(computeOfflineStats(expenses, { scope: 'year', year: '2025' }).totalCents, 200);
    assert.equal(computeOfflineStats(expenses, { scope: 'all' }).totalCents, 300);
  });
});

describe('computeOfflineStats 分类归并', () => {
  test('✱ 二级分类归并到一级：同父分类合并成一个桶，按金额降序', () => {
    const expenses = [
      makeExpense({
        id: 'breakfast',
        amountCents: 3_000,
        categoryId: 'c-breakfast',
        categoryName: '早饭',
        parentCategoryName: '餐饮',
        parentCategoryColor: '3',
      }),
      makeExpense({
        id: 'lunch',
        amountCents: 7_000,
        categoryId: 'c-lunch',
        categoryName: '午饭',
        parentCategoryName: '餐饮',
        parentCategoryColor: '3',
      }),
      makeExpense({
        id: 'bus',
        amountCents: 2_000,
        categoryId: 'c-transport',
        categoryName: '交通',
      }),
    ];

    const stats = computeOfflineStats(expenses, { scope: 'all' });
    assert.equal(stats.categories.length, 2);

    const food = stats.categories[0];
    assert.equal(food?.name, '餐饮');
    assert.equal(food?.cents, 10_000);
    assert.equal(food?.count, 2);
    // 二级归并到一级时颜色取父分类色
    assert.equal(food?.color, '3');
    assert.equal(food?.ratio, 10_000 / 12_000);

    const transport = stats.categories[1];
    assert.equal(transport?.name, '交通');
    assert.equal(transport?.cents, 2_000);
    assert.equal(transport?.ratio, 2_000 / 12_000);
  });
});

describe('computeOfflineStats 支付方式归并', () => {
  test('同一支付方式合并为一条，保留类型', () => {
    const expenses = [
      makeExpense({ id: 'a', amountCents: 3_000, paymentMethodId: 'cash', paymentMethodName: '现金' }),
      makeExpense({ id: 'b', amountCents: 2_000, paymentMethodId: 'cash', paymentMethodName: '现金' }),
      makeExpense({
        id: 'c',
        amountCents: 1_000,
        paymentMethodId: 'credit',
        paymentMethodName: '信用卡',
        paymentMethodType: 'credit',
      }),
    ];

    const stats = computeOfflineStats(expenses, { scope: 'all' });
    assert.equal(stats.paymentMethods.length, 2);

    const cash = stats.paymentMethods.find((item) => item.paymentMethodId === 'cash');
    assert.equal(cash?.cents, 5_000);
    assert.equal(cash?.count, 2);
    assert.equal(cash?.type, 'cash');

    const credit = stats.paymentMethods.find((item) => item.paymentMethodId === 'credit');
    assert.equal(credit?.type, 'credit');
  });
});

describe('computeOfflineStats 退款与单笔最高', () => {
  test('✱ 负数退款按原样累加合计，但不计入单笔最高', () => {
    const expenses = [
      makeExpense({ id: 'big', amountCents: 8_000, categoryName: '数码' }),
      makeExpense({ id: 'refund', amountCents: -3_000, categoryName: '数码' }),
      makeExpense({ id: 'small', amountCents: 2_000, categoryName: '餐饮' }),
    ];

    const stats = computeOfflineStats(expenses, { scope: 'all' });
    assert.equal(stats.totalCents, 7_000);
    assert.equal(stats.count, 3);
    assert.equal(stats.largestExpense?.expenseId, 'big');
    assert.equal(stats.largestExpense?.cents, 8_000);
  });

  test('全是退款时单笔最高为 null', () => {
    const stats = computeOfflineStats(
      [makeExpense({ id: 'r1', amountCents: -1_000 }), makeExpense({ id: 'r2', amountCents: -2_000 })],
      { scope: 'all' },
    );
    assert.equal(stats.totalCents, -3_000);
    assert.equal(stats.largestExpense, null);
  });
});

describe('computeOfflineStats 边界', () => {
  test('空数组返回零值', () => {
    const stats = computeOfflineStats([], { scope: 'all' });
    assert.equal(stats.totalCents, 0);
    assert.equal(stats.count, 0);
    assert.deepEqual(stats.categories, []);
    assert.deepEqual(stats.paymentMethods, []);
    assert.equal(stats.largestExpense, null);
  });

  test('带 deletedAt 墓碑的记录不计入', () => {
    const expenses = [
      makeExpense({ id: 'alive', amountCents: 1_000 }),
      makeExpense({ id: 'dead', amountCents: 9_999, deletedAt: '2026-02-01' } as Partial<Expense>),
    ];
    const stats = computeOfflineStats(expenses, { scope: 'all' });
    assert.equal(stats.totalCents, 1_000);
    assert.equal(stats.count, 1);
  });
});
