/**
 * 账单周期与业务日期推算的单元测试。
 *
 *   npm test
 *
 * 这里的用例覆盖的是「跨月」「月末无此日」「提醒日减到上一个月/上一年」
 * 这三类边界 —— 它们共同的特点是：**绝大多数月份都正常，只在个别月份出错**，
 * 所以线上很难被发现，只能靠测试钉死。
 */
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import {
  addDaysToDate,
  addMonthsToDate,
  clampDay,
  computeRemindDate,
  daysInMonth,
  generatePeriodDates,
  monthOf,
  parseDate,
  resolveExpenseDates,
  resolvePostingDate,
  shiftMonthString,
  type PaymentCycle,
} from '../../src/domain/billing-cycle.ts';

/** 用户给的例子：账单日 10、还款日 28 */
const CARD_10_28: PaymentCycle = { type: 'credit', billingDay: 10, repaymentDay: 28 };
/** 跨月的卡：账单日 25、还款日次月 10 */
const CARD_25_10: PaymentCycle = { type: 'credit', billingDay: 25, repaymentDay: 10 };

describe('现金 / 储蓄卡：没有账单周期', () => {
  test('入账日与还款日都等于消费日', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-09', { type: 'cash' }), {
      postingDate: '2026-01-09',
      repaymentDate: '2026-01-09',
    });
  });
});

describe('信用卡：账单日 10、还款日 28', () => {
  test('9 日消费 → 本期 10 日入账、28 日还款', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-09', CARD_10_28), {
      postingDate: '2026-01-10',
      repaymentDate: '2026-01-28',
    });
  });

  test('账单日当天消费算本期（我们自己定死的规则）', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-10', CARD_10_28), {
      postingDate: '2026-01-10',
      repaymentDate: '2026-01-28',
    });
  });

  test('11 日消费 → 次期入账、次期还款', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-11', CARD_10_28), {
      postingDate: '2026-02-10',
      repaymentDate: '2026-02-28',
    });
  });

  test('跨年：12 月 20 日消费 → 次年 1 月入账与还款', () => {
    assert.deepEqual(resolveExpenseDates('2026-12-20', CARD_10_28), {
      postingDate: '2027-01-10',
      repaymentDate: '2027-01-28',
    });
  });
});

describe('信用卡：账单日 25、还款日次月 10（入账与还款跨月）', () => {
  test('24 日消费 → 本月 25 入账、次月 10 还款', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-24', CARD_25_10), {
      postingDate: '2026-01-25',
      repaymentDate: '2026-02-10',
    });
  });

  test('26 日消费 → 次月 25 入账、再次月 10 还款', () => {
    assert.deepEqual(resolveExpenseDates('2026-01-26', CARD_25_10), {
      postingDate: '2026-02-25',
      repaymentDate: '2026-03-10',
    });
  });

  test('还款日不会早于入账日', () => {
    for (let day = 1; day <= 28; day += 1) {
      const spendDate = `2026-03-${String(day).padStart(2, '0')}`;
      const { postingDate, repaymentDate } = resolveExpenseDates(spendDate, CARD_25_10);
      assert.ok(
        repaymentDate > postingDate,
        `${spendDate}：还款日 ${repaymentDate} 应晚于入账日 ${postingDate}`,
      );
    }
  });
});

describe('月末无此日：钳到当月最后一天，绝不顺延到下个月', () => {
  test('1 月 31 日顺延 1 个月 → 2 月 28 日（平年）', () => {
    assert.equal(addMonthsToDate('2026-01-31', 1), '2026-02-28');
  });

  test('1 月 31 日顺延 1 个月 → 2 月 29 日（闰年）', () => {
    assert.equal(addMonthsToDate('2028-01-31', 1), '2028-02-29');
  });

  test('顺延后不会污染后续期数（从首期递推，而非逐级累加）', () => {
    // 若实现是「上一期 +1 月」逐级累加，2/28 之后所有期都会变成 28 号
    assert.deepEqual(generatePeriodDates('2026-01-31', 5), [
      '2026-01-31',
      '2026-02-28',
      '2026-03-31',
      '2026-04-30',
      '2026-05-31',
    ]);
  });

  test('clampDay 与 daysInMonth', () => {
    assert.equal(daysInMonth(2026, 2), 28);
    assert.equal(daysInMonth(2028, 2), 29);
    assert.equal(daysInMonth(2026, 4), 30);
    assert.equal(clampDay(2026, 2, 31), 28);
    assert.equal(clampDay(2026, 4, 31), 30);
    assert.equal(clampDay(2026, 5, 31), 31);
  });
});

describe('还款日 → 入账日（计划的待办用它反推）', () => {
  test('现金：入账日等于还款日', () => {
    assert.equal(resolvePostingDate('2026-01-28', { type: 'cash' }), '2026-01-28');
  });

  test('账单日 10 / 还款日 28：入账日是同月 10 日', () => {
    assert.equal(resolvePostingDate('2026-01-28', CARD_10_28), '2026-01-10');
  });

  test('账单日 25 / 还款日次月 10：入账日落到上个月 25 日', () => {
    assert.equal(resolvePostingDate('2026-02-10', CARD_25_10), '2026-01-25');
  });

  test('跨年：1 月 10 日还款 → 上一年 12 月 25 日入账', () => {
    assert.equal(resolvePostingDate('2027-01-10', CARD_25_10), '2026-12-25');
  });

  test('还款日正好等于账单日 → 归上一期', () => {
    // 还款日必须晚于入账日，同日不成立，所以推到上个月
    const same: PaymentCycle = { type: 'credit', billingDay: 15, repaymentDay: 15 };
    assert.equal(resolvePostingDate('2026-03-15', same), '2026-02-15');
  });

  test('✱ 平年 2 月末吸附：账单日 28 / 还款日 31，2/28 不倒退到 1 月', () => {
    // 还款日是「每月 31 号、遇月末取月末」生成的：平年 2 月的 31 号吸附成 2/28。
    // 直接拿 28 与账单日 28 比较会误判成上一期（28 > 28 不成立）→ 入账日倒退到 1 月。
    const monthEnd: PaymentCycle = { type: 'credit', billingDay: 28, repaymentDay: 31 };
    assert.equal(resolvePostingDate('2027-02-28', monthEnd), '2027-02-28');
    // 闰年 2 月 29 日同理（吸附自 31 号）
    assert.equal(resolvePostingDate('2028-02-29', monthEnd), '2028-02-28');
    // 其它月份不吸附，行为不变：1/31 → 本月 28
    assert.equal(resolvePostingDate('2027-01-31', monthEnd), '2027-01-28');
  });

  test('✱ 平年 2 月末吸附不越权：真实的月末还款（还款日本身就是月末号）不受影响', () => {
    // 还款日 28 的卡在 2/28 还款不是吸附，是真实日期：28 <= 31 仍归上一期
    const real28: PaymentCycle = { type: 'credit', billingDay: 31, repaymentDay: 28 };
    assert.equal(resolvePostingDate('2027-02-28', real28), '2027-01-31');
  });

  test('✱ 与 resolveExpenseDates 互为逆运算（入账日回推得到原还款日所在期）', () => {
    // 显式标注数组类型：内联字面量会让 TS 在这个嵌套循环里推断出循环依赖
    const cycles: readonly PaymentCycle[] = [CARD_10_28, CARD_25_10];

    for (const spendDate of [
      '2026-01-09',
      '2026-01-11',
      '2026-02-24',
      '2026-02-26',
      '2026-12-05',
    ]) {
      for (const cycle of cycles) {
        const resolved = resolveExpenseDates(spendDate, cycle);
        assert.equal(
          resolvePostingDate(resolved.repaymentDate, cycle),
          resolved.postingDate,
          `${spendDate} 经账单周期正向再反向应还原入账日`,
        );
      }
    }
  });
});

describe('提醒日：往前推 n 天，可跨月跨年', () => {
  test('还款日 1 月 28、提前 3 天 → 1 月 25', () => {
    assert.equal(computeRemindDate('2026-01-28', 3), '2026-01-25');
  });

  test('还款日 3 月 3、提前 5 天 → 跨到 2 月 26', () => {
    assert.equal(computeRemindDate('2026-03-03', 5), '2026-02-26');
  });

  test('还款日 1 月 2、提前 5 天 → 跨到上一年 12 月 28', () => {
    assert.equal(computeRemindDate('2026-01-02', 5), '2025-12-28');
  });

  test('提前 0 天 → 就是还款日当天', () => {
    assert.equal(computeRemindDate('2026-01-28', 0), '2026-01-28');
  });

  test('addDaysToDate 逆运算自洽', () => {
    for (const date of ['2026-01-01', '2026-02-28', '2028-02-29', '2026-12-31']) {
      assert.equal(addDaysToDate(addDaysToDate(date, 7), -7), date);
    }
  });
});

describe('日期字符串校验', () => {
  test('拒绝格式错误', () => {
    assert.throws(() => parseDate('2026/01/09'));
    assert.throws(() => parseDate('2026-1-9'));
    assert.throws(() => parseDate('not-a-date'));
  });

  test('拒绝不存在的日期', () => {
    assert.throws(() => parseDate('2026-02-29'), /没有这一天/);
    assert.throws(() => parseDate('2026-04-31'), /没有这一天/);
    assert.throws(() => parseDate('2026-13-01'), /月份/);
  });

  test('接受闰年 2 月 29 日', () => {
    assert.deepEqual(parseDate('2028-02-29'), { year: 2028, month: 2, day: 29 });
  });
});

describe('月份字符串', () => {
  test('monthOf 取前缀', () => {
    assert.equal(monthOf('2026-01-09'), '2026-01');
  });

  test('shiftMonthString 跨年', () => {
    assert.equal(shiftMonthString('2026-01', -1), '2025-12');
    assert.equal(shiftMonthString('2026-12', 1), '2027-01');
    assert.equal(shiftMonthString('2026-06', 7), '2027-01');
  });
});
