/**
 * 业务日期工具的单元测试。
 *
 * 这些函数全部**刻意绕开本地时区**（只借 Date.UTC 做运算，再用 getUTC* 取回）。
 * 用 `new Date(y, m, d)` 那种本地构造的写法，在跨时区或跨夏令时的设备上
 * 会给出不同答案 —— 而「还款日前 N 天提醒」和「月份归属」都建立在它们之上，
 * 错一天就可能让提醒落在错误的月份里。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  currentMonth,
  daysInMonth,
  daysUntil,
  elapsedDays,
  formatDayLabel,
  formatLedgerDate,
  formatMonthDay,
  formatMonthLabel,
  fullWeekdayOf,
  shiftMonth,
  todayLocal,
  weekdayOf,
} from '../src/utils/dates.ts';

describe('todayLocal / currentMonth', () => {
  test('格式固定为 YYYY-MM-DD，个位数补零', () => {
    // 用本地时间构造一个明确的日期，避免依赖运行环境的「今天」
    assert.equal(todayLocal(new Date(2026, 0, 9)), '2026-01-09');
    assert.equal(todayLocal(new Date(2026, 11, 31)), '2026-12-31');
  });

  test('currentMonth 取前 7 位', () => {
    assert.equal(currentMonth(new Date(2026, 0, 9)), '2026-01');
  });
});

describe('格式化', () => {
  test('月份标签', () => {
    assert.equal(formatMonthLabel('2026-09'), '2026 年 9 月');
    assert.equal(formatMonthLabel('2026-01'), '2026 年 1 月');
  });

  test('日期标签', () => {
    assert.equal(formatDayLabel('2026-09-24'), '09-24');
    assert.equal(formatMonthDay('2026-09-24'), '9月24日');
  });

  test('格式不对时原样返回，不抛错', () => {
    assert.equal(formatMonthLabel('乱七八糟'), '乱七八糟');
    assert.equal(formatDayLabel('2026-09'), '2026-09');
  });
});

describe('shiftMonth', () => {
  test('跨年', () => {
    assert.equal(shiftMonth('2026-01', -1), '2025-12');
    assert.equal(shiftMonth('2026-12', 1), '2027-01');
  });

  test('跨多年', () => {
    assert.equal(shiftMonth('2026-06', 18), '2027-12');
    assert.equal(shiftMonth('2026-06', -18), '2024-12');
  });

  test('✱ 加减互为逆运算，且不会出现 13 月或 0 月', () => {
    for (const month of ['2026-01', '2026-06', '2026-12', '2027-02']) {
      assert.equal(shiftMonth(shiftMonth(month, 7), -7), month);
      assert.match(shiftMonth(month, 13), /^\d{4}-(0[1-9]|1[0-2])$/);
    }
  });
});

describe('weekdayOf', () => {
  test('以已知日期为锚点（避开对「今天是周几」的记忆）', () => {
    // Unix 纪元 1970-01-01 是周四；2000-01-01 是周六 —— 两个公认的锚点
    assert.equal(weekdayOf('1970-01-01'), '周四');
    assert.equal(weekdayOf('2000-01-01'), '周六');
  });

  test('连续七天恰好覆盖一周', () => {
    const days = ['2026-03-01', '2026-03-02', '2026-03-03', '2026-03-04', '2026-03-05', '2026-03-06', '2026-03-07'];
    const labels = days.map(weekdayOf);
    assert.equal(new Set(labels).size, 7, `七天应互不相同，实际 ${labels.join(',')}`);
  });
});

describe('fullWeekdayOf', () => {
  test('全称星期锚点', () => {
    assert.equal(fullWeekdayOf('1970-01-01'), '星期四');
    assert.equal(fullWeekdayOf('2000-01-01'), '星期六');
  });

  test('连续七天恰好覆盖全称一周', () => {
    const days = ['2026-03-01', '2026-03-02', '2026-03-03', '2026-03-04', '2026-03-05', '2026-03-06', '2026-03-07'];
    const labels = days.map(fullWeekdayOf);
    assert.deepEqual(labels, [
      '星期日',
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
    ]);
  });
});

describe('formatLedgerDate（最远支持到 2 天简化显示）', () => {
  const mockToday = '2026-09-28'; // 星期一

  test('今日：今日星期一', () => {
    const res = formatLedgerDate('2026-09-28', mockToday);
    assert.equal(res.dayText, '今日');
    assert.equal(res.weekdayText, '星期一');
    assert.equal(res.full, '今日星期一');
    assert.equal(res.isRecent, true);
  });

  test('昨日：昨日星期日', () => {
    const res = formatLedgerDate('2026-09-27', mockToday);
    assert.equal(res.dayText, '昨日');
    assert.equal(res.weekdayText, '星期日');
    assert.equal(res.full, '昨日星期日');
    assert.equal(res.isRecent, true);
  });

  test('2天前及更早：26日星期六、25日星期五、1日星期二', () => {
    const d26 = formatLedgerDate('2026-09-26', mockToday);
    assert.equal(d26.dayText, '26日');
    assert.equal(d26.weekdayText, '星期六');
    assert.equal(d26.full, '26日星期六');
    assert.equal(d26.isRecent, false);

    const d25 = formatLedgerDate('2026-09-25', mockToday);
    assert.equal(d25.dayText, '25日');
    assert.equal(d25.weekdayText, '星期五');
    assert.equal(d25.full, '25日星期五');
    assert.equal(d25.isRecent, false);

    const d01 = formatLedgerDate('2026-09-01', mockToday);
    assert.equal(d01.dayText, '1日');
    assert.equal(d01.weekdayText, '星期二');
    assert.equal(d01.full, '1日星期二');
    assert.equal(d01.isRecent, false);
  });

  test('月初跨月场景：今天如果是 1 号，昨天就是上个月末日', () => {
    const monthFirst = '2026-09-01'; // 星期二
    const todayRes = formatLedgerDate('2026-09-01', monthFirst);
    assert.equal(todayRes.dayText, '今日');
    assert.equal(todayRes.weekdayText, '星期二');
    assert.equal(todayRes.full, '今日星期二');

    const yesterdayRes = formatLedgerDate('2026-08-31', monthFirst);
    assert.equal(yesterdayRes.dayText, '昨日');
    assert.equal(yesterdayRes.weekdayText, '星期一');
    assert.equal(yesterdayRes.full, '昨日星期一');

    const twoDaysAgoRes = formatLedgerDate('2026-08-30', monthFirst);
    assert.equal(twoDaysAgoRes.dayText, '30日');
    assert.equal(twoDaysAgoRes.weekdayText, '星期日');
    assert.equal(twoDaysAgoRes.full, '30日星期日');
  });

  test('非法格式安全降级', () => {
    const res = formatLedgerDate('invalid-date', mockToday);
    assert.equal(res.dayText, 'invalid-date');
    assert.equal(res.weekdayText, '');
    assert.equal(res.full, 'invalid-date');
    assert.equal(res.isRecent, false);
  });
});

describe('daysUntil', () => {
  test('当天为 0，明天为 1，昨天为 -1', () => {
    assert.equal(daysUntil('2026-01-01', '2026-01-01'), 0);
    assert.equal(daysUntil('2026-01-02', '2026-01-01'), 1);
    assert.equal(daysUntil('2026-01-01', '2026-01-02'), -1);
  });

  test('跨月与跨年', () => {
    assert.equal(daysUntil('2026-02-01', '2026-01-31'), 1);
    assert.equal(daysUntil('2027-01-01', '2026-12-31'), 1);
    assert.equal(daysUntil('2028-03-01', '2028-02-28'), 2, '2028 是闰年，2 月有 29 天');
  });

  test('✱ 跨越夏令时切换仍应是整天数', () => {
    // 美国 2026-03-08 进入夏令时：用本地时间做减法的实现会在这里差 1 天
    assert.equal(daysUntil('2026-03-09', '2026-03-07'), 2);
    // 欧洲 2026-10-25 退出夏令时
    assert.equal(daysUntil('2026-10-26', '2026-10-24'), 2);
  });

  test('✱ 提醒日跨月的典型场景：还款日 3 日、提前 5 天 → 上月月末', () => {
    assert.equal(daysUntil('2026-03-03', '2026-02-26'), 5);
  });
});

describe('daysInMonth / elapsedDays', () => {
  test('月份天数，含闰年二月', () => {
    assert.equal(daysInMonth('2026-01'), 31);
    assert.equal(daysInMonth('2026-02'), 28);
    assert.equal(daysInMonth('2028-02'), 29, '2028 是闰年');
    assert.equal(daysInMonth('2026-04'), 30);
    assert.equal(daysInMonth('2026-12'), 31);
  });

  test('格式不对时退到 30，不抛错', () => {
    assert.equal(daysInMonth('乱七八糟'), 30);
  });

  test('当月按「今天」的日号算，历史与未来月份按整月算', () => {
    assert.equal(elapsedDays('2026-09', '2026-09-05'), 5, '当月只算已过的天数');
    assert.equal(elapsedDays('2026-08', '2026-09-05'), 31, '历史月份已经过完了');
    assert.equal(elapsedDays('2026-10', '2026-09-05'), 31, '未来月份按整月，反正没有数据');
  });

  test('✱ 分母永远不小于 1，月初不会除出 Infinity', () => {
    // 「今天是 1 号」时 elapsedDays 若返回 0，日均就会是 Infinity，
    // 而 Infinity 在界面上会显示成一个诡异的数字而不是报错。
    for (const day of ['01', '15', '31']) {
      assert.ok(elapsedDays('2026-09', `2026-09-${day}`) >= 1);
    }
  });
});
