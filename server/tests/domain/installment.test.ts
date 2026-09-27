import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { splitInstallment } from '../../src/domain/installment.ts';

describe('splitInstallment', () => {
  test('能整除时每期相同', () => {
    assert.deepEqual(splitInstallment(600_000, 12), Array.from({ length: 12 }, () => 50_000));
  });

  test('✱ 除不尽时最后一期补足差额，各期之和恰好等于总额', () => {
    const amounts = splitInstallment(100_000, 3);
    assert.deepEqual(amounts, [33_333, 33_333, 33_334]);
    assert.equal(
      amounts.reduce((sum, item) => sum + item, 0),
      100_000,
      '各期之和必须恰好等于总额，否则「剩余未付」永远结不清',
    );
  });

  test('差额永远在最后一期，不会分散到中间', () => {
    const amounts = splitInstallment(1_000, 7);
    assert.equal(amounts.slice(0, 6).every((item) => item === amounts[0]), true);
    assert.notEqual(amounts[6], amounts[0]);
  });

  test('1 期就是总额本身', () => {
    assert.deepEqual(splitInstallment(12_345, 1), [12_345]);
  });

  test('任何合法输入都满足「各期之和 = 总额」且每期 > 0', () => {
    for (const total of [1, 3, 99, 100, 10_000, 600_000, 9_999_999]) {
      for (const periods of [1, 2, 3, 7, 12, 24, 60]) {
        if (total < periods) continue;

        const amounts = splitInstallment(total, periods);
        assert.equal(amounts.length, periods);
        assert.equal(
          amounts.reduce((sum, item) => sum + item, 0),
          total,
          `总额 ${total} 分 ${periods} 期之和应等于总额`,
        );
        assert.ok(
          amounts.every((item) => Number.isInteger(item) && item > 0),
          `总额 ${total} 分 ${periods} 期不应出现非正整数`,
        );
      }
    }
  });

  test('总额不足以分满每期 1 分时拒绝，而不是产生 0 元的期', () => {
    // amount_cents > 0 是数据库的硬约束，这里提前拦住并给出人话提示
    assert.throws(() => splitInstallment(5, 12), /无法分成/);
  });

  test('非法入参', () => {
    assert.throws(() => splitInstallment(0, 3));
    assert.throws(() => splitInstallment(-100, 3));
    assert.throws(() => splitInstallment(100, 0));
    assert.throws(() => splitInstallment(100, 601));
    assert.throws(() => splitInstallment(100.5, 3));
  });
});
