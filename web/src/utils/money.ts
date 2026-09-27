/**
 * 金额工具。
 *
 * 贯穿全项目的一条约定：**金额一律是整数「分」**。
 * 浮点求和会出现「总账差一分钱」这类查不出原因的 bug，
 * 所以这里所有运算都走整数，只在最后一步做显示格式化。
 */

/** 分 → '1,234.56'（不含货币符号） */
export function formatCents(cents: number): string {
  const negative = cents < 0;
  const abs = Math.abs(cents);

  const yuan = Math.floor(abs / 100);
  const fen = abs % 100;

  // 用正则分组而不是 toLocaleString：不同设备的 Intl 数据版本不一，
  // 同一笔钱在两台手机上可能显示成不同的分组方式
  const grouped = String(yuan).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${negative ? '-' : ''}${grouped}.${String(fen).padStart(2, '0')}`;
}

/** 分 → '¥1,234.56' */
export function formatYuan(cents: number): string {
  return `¥${formatCents(cents)}`;
}

/**
 * 分 → 紧凑显示，用于超大字号的位置（首页总额、报表大数字）。
 *
 * 大字号下小数位是纯噪音：「¥8,432.10」的小数点在小屏上几乎看不见，
 * 反而挤掉了整数位的可读性。所以万元以下舍去角分，万元以上用「万」压缩。
 */
export function formatCompact(cents: number): string {
  const abs = Math.abs(cents);
  const sign = cents < 0 ? '-' : '';

  if (abs < 1_000_000) {
    return `${sign}¥${String(Math.round(abs / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
  }

  const wan = abs / 1_000_000;
  return `${sign}¥${wan >= 100 ? wan.toFixed(0) : wan.toFixed(1)}万`;
}

/** 分 → '1234.56'（不带千分位与符号，用于回填输入框） */
export function centsToInput(cents: number): string {
  const abs = Math.abs(cents);
  const yuan = Math.floor(abs / 100);
  const fen = abs % 100;
  if (fen === 0) return String(yuan);
  return `${yuan}.${String(fen).padStart(2, '0')}`;
}

/**
 * 输入框里的「元」文本 → 整数分。
 *
 * 全程整数运算：先把元部分当整数乘 100，再把小数部分补齐到两位。
 * 绝不用 `parseFloat(input) * 100` —— 那会引入浮点误差
 * （`19.99 * 100 = 1998.9999999999998`），四舍五入的时机稍有不同就差一分钱。
 */
export function parseYuanToCents(input: string): number {
  if (input === '' || input === '.') return 0;

  const [intPart = '0', decPart = ''] = input.split('.');
  const yuan = Number(intPart === '' ? '0' : intPart);
  const fen = Number((decPart + '00').slice(0, 2));

  if (!Number.isFinite(yuan) || !Number.isFinite(fen)) return 0;
  return yuan * 100 + fen;
}
