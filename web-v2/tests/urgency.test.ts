/**
 * 提醒的编码规则。
 *
 * 这一组全是**纯函数**，但它们错了在界面上看不出来 ——
 * 颜色不对、按钮给错，页面照常渲染、控制台照常干净。
 * 尤其 `reminderToneOf`：一叠里只要漏判一条逾期，箭头就从红变成黄，
 * 而用户据以决定「现在要不要处理」的正是那个颜色。
 *
 * 日期一律**相对今天**构造（而不是写死 '2026-09-28'）：
 * `urgencyOf` 的分档是相对当天的，写死日期会让测试在换一天的机器上失败。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { todayLocal } from '../src/utils/dates.ts';
import {
  REMINDER_CHEV,
  reminderActionOf,
  reminderPrimaryLabel,
  reminderStateLabel,
  reminderToneOf,
  urgencyOf,
} from '../src/utils/urgency.ts';

/** 相对今天偏移 N 天的日期（'YYYY-MM-DD'） */
function dayOffset(days: number): string {
  const base = new Date();
  base.setDate(base.getDate() + days);
  return todayLocal(base);
}

describe('urgencyOf 的三档边界', () => {
  test('昨天 = overdue，今天与明天 = due，后天起 = later', () => {
    assert.equal(urgencyOf(dayOffset(-1)), 'overdue');
    assert.equal(urgencyOf(dayOffset(0)), 'due');
    assert.equal(urgencyOf(dayOffset(1)), 'due');
    assert.equal(urgencyOf(dayOffset(2)), 'later');
  });
});

describe('reminderToneOf', () => {
  const auto = (days: number) => ({ willAutoPost: true, repaymentDate: dayOffset(days) });
  const manual = (days: number) => ({ willAutoPost: false, repaymentDate: dayOffset(days) });

  test('全部自动入账、且都没到期 → 中性（这一叠确实不需要你动手）', () => {
    assert.equal(reminderToneOf([auto(5), auto(20)]), 'none');
  });

  test('有一条不会自动入账 → 黄（要等用户做决定）', () => {
    assert.equal(reminderToneOf([auto(5), manual(20)]), 'manual');
  });

  test('有一条逾期 → 红', () => {
    assert.equal(reminderToneOf([auto(-1), auto(20)]), 'late');
  });

  test('逾期优先于「需手动」：同时存在时仍取红', () => {
    // 顺序反过来也要是红 —— 若实现写成「先到先得」，
    // 把 manual 放前面就会返回黄，那是错的
    assert.equal(reminderToneOf([manual(20), auto(-1)]), 'late');
  });

  test('空数组 → 中性，且不抛异常', () => {
    assert.equal(reminderToneOf([]), 'none');
  });

  test('「需手动」但已逾期 → 红（逾期是同一件事的更急版本）', () => {
    assert.equal(reminderToneOf([manual(-3)]), 'late');
  });
});

describe('动作分流', () => {
  test('会自动入账 → 只给「确认」；不会 → 给「入账 / 忽略」', () => {
    assert.equal(reminderActionOf(true), 'ack');
    assert.equal(reminderActionOf(false), 'decide');
  });

  test('主操作文案', () => {
    assert.equal(reminderPrimaryLabel('ack'), '确认');
    assert.equal(reminderPrimaryLabel('decide'), '入账');
  });

  test('状态词说的是「我不点会怎样」，不是「原因」', () => {
    assert.equal(reminderStateLabel(true), '自动入账');
    assert.equal(reminderStateLabel(false), '需手动入账');
  });
});

describe('箭头配色', () => {
  test('三档各有一个颜色，且互不相同 —— 中性必须有颜色，否则读起来像漏了一格', () => {
    const colors = [REMINDER_CHEV.none, REMINDER_CHEV.manual, REMINDER_CHEV.late];
    assert.equal(new Set(colors).size, 3);
    for (const color of colors) assert.notEqual(color, '');
  });
});
