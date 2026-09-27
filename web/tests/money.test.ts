/**
 * 金额工具的单元测试。
 *
 * 这些函数的共同特点是：**错了不会报错，只会显示成另一个数字**。
 * 尤其是「元文本 → 整数分」这一步，用 parseFloat 乘 100 的写法在
 * 19.99 这类值上会得到 1998.9999999999998，四舍五入的时机稍有不同就差一分钱，
 * 而这一分钱会一直累进到月度总额里，事后根本无法定位。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  centsToInput,
  formatCents,
  formatCompact,
  formatYuan,
  parseYuanToCents,
} from '../src/utils/money.ts';

describe('formatCents', () => {
  test('补零到两位小数', () => {
    assert.equal(formatCents(0), '0.00');
    assert.equal(formatCents(5), '0.05');
    assert.equal(formatCents(50), '0.50');
    assert.equal(formatCents(100), '1.00');
  });

  test('千分位分组', () => {
    assert.equal(formatCents(123_456), '1,234.56');
    assert.equal(formatCents(100_000_000), '1,000,000.00');
  });

  test('负数（退款 / 冲销）', () => {
    assert.equal(formatCents(-3200), '-32.00');
  });

  test('✱ 整数累加不产生浮点误差', () => {
    // 0.1 + 0.2 用浮点会得到 0.30000000000000004；这里必须精确
    const sum = [10, 20, 70, 999, 1].reduce((acc, item) => acc + item, 0);
    assert.equal(formatCents(sum), '11.00');
  });
});

describe('formatYuan', () => {
  test('带货币符号', () => {
    assert.equal(formatYuan(3200), '¥32.00');
    assert.equal(formatYuan(-3200), '¥-32.00');
  });
});

describe('formatCompact', () => {
  test('一万元以下舍去角分', () => {
    assert.equal(formatCompact(0), '¥0');
    assert.equal(formatCompact(843_210), '¥8,432');
  });

  test('一万元以上用「万」压缩', () => {
    assert.equal(formatCompact(1_000_000), '¥1.0万');
    assert.equal(formatCompact(12_345_600), '¥12.3万');
    assert.equal(formatCompact(5_000_000_00), '¥500万');
  });

  test('负数', () => {
    assert.equal(formatCompact(-843_210), '-¥8,432');
  });
});

describe('centsToInput', () => {
  test('整数元不带小数点', () => {
    assert.equal(centsToInput(3200), '32');
    assert.equal(centsToInput(0), '0');
  });

  test('有角分时补齐两位', () => {
    assert.equal(centsToInput(3205), '32.05');
    assert.equal(centsToInput(3250), '32.50');
  });

  test('负数取绝对值（符号由「退款」开关单独表达）', () => {
    assert.equal(centsToInput(-3205), '32.05');
  });
});

describe('parseYuanToCents', () => {
  test('空输入视为 0', () => {
    assert.equal(parseYuanToCents(''), 0);
    assert.equal(parseYuanToCents('.'), 0);
  });

  test('整数与小数', () => {
    assert.equal(parseYuanToCents('32'), 3200);
    assert.equal(parseYuanToCents('32.5'), 3250);
    assert.equal(parseYuanToCents('32.56'), 3256);
    assert.equal(parseYuanToCents('.5'), 50);
  });

  test('✱ 19.99 必须是 1999，不能是 1998', () => {
    // parseFloat('19.99') * 100 === 1998.9999999999998，取整方式稍偏就差一分
    assert.equal(parseYuanToCents('19.99'), 1999);
    assert.equal(parseYuanToCents('0.29'), 29);
    assert.equal(parseYuanToCents('1.00'), 100);
  });

  test('超过两位小数截断而不是四舍五入（键盘本身就限制两位）', () => {
    assert.equal(parseYuanToCents('32.567'), 3256);
  });

  test('✱ 与 centsToInput 互为逆运算', () => {
    for (const cents of [0, 1, 99, 100, 3200, 1999, 123_456, 999_999_999]) {
      assert.equal(
        parseYuanToCents(centsToInput(cents)),
        cents,
        `${cents} 分经过「回填输入框 → 解析」后应还原`,
      );
    }
  });
});
