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
  adaptiveAmountStyle,
  centsToInput,
  formatCents,
  formatCompact,
  formatYuan,
  parseYuanToCents,
  splitInstallment,
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

  test('✱ 负数：符号剥离后按绝对值计算再统一赋符号', () => {
    // 旧实现的两个 bug："-15.50" 切出 yuan=-15、fen=50 算成 -1450（少算 1 元）；
    // "-0.50" 切出 Number("-0")===0 算成 +50（负数翻正）。
    assert.equal(parseYuanToCents('-15.50'), -1550);
    assert.equal(parseYuanToCents('-0.50'), -50);
    assert.equal(parseYuanToCents('-32'), -3200);
    assert.equal(parseYuanToCents('-.5'), -50);
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

describe('splitInstallment', () => {
  test('整除场景：各期均分', () => {
    assert.deepEqual(splitInstallment(120000, 12), Array(12).fill(10000));
    assert.deepEqual(splitInstallment(300, 3), [100, 100, 100]);
  });

  test('除不尽场景：前 n-1 期取整，末期补差', () => {
    // 10000 分拆 3 期：10000 / 3 = 3333.33 -> 3333 + 3333 + 3334 = 10000
    const parts3 = splitInstallment(10000, 3);
    assert.deepEqual(parts3, [3333, 3333, 3334]);
    assert.equal(parts3.reduce((a, b) => a + b, 0), 10000);

    // 10000 分拆 6 期：10000 / 6 = 1666.66 -> 1666 * 5 + 1670 = 10000
    const parts6 = splitInstallment(10000, 6);
    assert.deepEqual(parts6, [1666, 1666, 1666, 1666, 1666, 1670]);
    assert.equal(parts6.reduce((a, b) => a + b, 0), 10000);
  });

  test('单期场景：原样返回', () => {
    assert.deepEqual(splitInstallment(5000, 1), [5000]);
  });

  test('边界与非法输入保护', () => {
    assert.deepEqual(splitInstallment(0, 12), []);
    assert.deepEqual(splitInstallment(-100, 3), []);
    assert.deepEqual(splitInstallment(1000, 0), []);
    assert.deepEqual(splitInstallment(1000, -1), []);
    assert.deepEqual(splitInstallment(1000, 601), []);
    assert.deepEqual(splitInstallment(2, 3), []); // totalCents < periods
  });
});

describe('adaptiveAmountStyle', () => {
  test('Hero 变体：短金额保持大字号', () => {
    const s1 = adaptiveAmountStyle('¥0.00', 'hero');
    assert.match(s1.fontSize, /3\.5rem/); // max 56px

    const s2 = adaptiveAmountStyle('¥842.50', 'hero');
    assert.match(s2.fontSize, /3\.5rem/);
  });

  test('Hero 变体：大金额阶梯式递减', () => {
    const sThousands = adaptiveAmountStyle('¥1,234.56', 'hero'); // len 9
    const sTenThousands = adaptiveAmountStyle('¥12,345.67', 'hero'); // len 10
    const sHundredThousands = adaptiveAmountStyle('¥123,456.78', 'hero'); // len 11
    const sMillions = adaptiveAmountStyle('¥1,234,567.89', 'hero'); // len 13
    const sTenMillions = adaptiveAmountStyle('¥12,345,678.90', 'hero'); // len 14
    const sHundredMillions = adaptiveAmountStyle('¥123,456,789.00', 'hero'); // len 15

    // 每一档最大字号都应该逐步缩小
    assert.match(sThousands.fontSize, /3\.25rem/);
    assert.match(sTenThousands.fontSize, /2\.75rem/);
    assert.match(sHundredThousands.fontSize, /2\.75rem/);
    assert.match(sMillions.fontSize, /2\.25rem/);
    assert.match(sTenMillions.fontSize, /1\.875rem/);
    assert.match(sHundredMillions.fontSize, /1\.875rem/);

    const sBillions = adaptiveAmountStyle('¥1,234,567,890.00', 'hero'); // len 17
    assert.match(sBillions.fontSize, /1\.625rem/); // 26px max
  });

  test('Card 变体：流水卡片金额自适应', () => {
    const shortAmount = adaptiveAmountStyle('12.50', 'card');
    assert.match(shortAmount.fontSize, /2\.75rem/);

    const millions = adaptiveAmountStyle('1,234,567.89', 'card');
    assert.match(millions.fontSize, /1\.75rem/);
  });
});

