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

  // 符号位先剥离，剩余部分按绝对值计算，最后统一赋符号。
  // 否则 "-15.50" 会切出 yuan=-15、fen=50，算成 -1500+50=-1450（少算 1 元）；
  // "-0.50" 会切出 yuan=Number("-0")===0，算成 0+50=+50（负数翻正）。
  const negative = input.startsWith('-');
  const abs = negative ? input.slice(1) : input;

  const [intPart = '0', decPart = ''] = abs.split('.');
  const yuan = Number(intPart === '' ? '0' : intPart);
  const fen = Number((decPart + '00').slice(0, 2));

  if (!Number.isFinite(yuan) || !Number.isFinite(fen)) return 0;
  const cents = yuan * 100 + fen;
  return negative ? -cents : cents;
}

/**
 * 把总额等额拆成每期金额。
 * 前 n−1 期取整，最后一期补足差额，保证各期之和恰好等于总额。
 */
export function splitInstallment(totalCents: number, periods: number): number[] {
  if (!Number.isInteger(totalCents) || totalCents <= 0) return [];
  if (!Number.isInteger(periods) || periods < 1 || periods > 600) return [];
  if (totalCents < periods) return [];

  const base = Math.floor(totalCents / periods);
  const amounts = Array.from({ length: periods }, () => base);
  amounts[periods - 1] = totalCents - base * (periods - 1);
  return amounts;
}

/**
 * 根据金额格式化字符串长度，返回响应式自适应字号样式（基于 CSS clamp）。
 *
 * 保证：
 * 1. 简短金额（千元以下）保持大字体视觉冲击力；
 * 2. 百万、千万、甚至亿级大金额自动逐级等比缩减；
 * 3. 在移动端 360px~390px 窄屏与桌面端均能单行完整容纳，绝不折行或撑出卡片。
 */
export function adaptiveAmountStyle(
  formattedText: string,
  variant: 'hero' | 'card' = 'hero',
): { fontSize: string } {
  const len = formattedText.length;

  if (variant === 'hero') {
    // 概况顶部 Hero 卡片（主视觉指标）
    if (len <= 7) {
      return { fontSize: 'clamp(2.25rem, 8vw, 3.5rem)' }; // 36px ~ 56px
    }
    if (len <= 9) {
      return { fontSize: 'clamp(2rem, 7.2vw, 3.25rem)' }; // 32px ~ 52px
    }
    if (len <= 11) {
      return { fontSize: 'clamp(1.75rem, 6.2vw, 2.75rem)' }; // 28px ~ 44px
    }
    if (len <= 13) {
      return { fontSize: 'clamp(1.5rem, 5.2vw, 2.25rem)' }; // 24px ~ 36px
    }
    if (len <= 15) {
      return { fontSize: 'clamp(1.25rem, 4.4vw, 1.875rem)' }; // 20px ~ 30px
    }
    return { fontSize: 'clamp(1.125rem, 3.8vw, 1.625rem)' }; // 18px ~ 26px
  }

  // 记账流水页等紧凑卡片
  if (len <= 7) {
    return { fontSize: 'clamp(1.875rem, 6.5vw, 2.75rem)' }; // 30px ~ 44px
  }
  if (len <= 9) {
    return { fontSize: 'clamp(1.625rem, 5.8vw, 2.375rem)' }; // 26px ~ 38px
  }
  if (len <= 11) {
    return { fontSize: 'clamp(1.375rem, 5vw, 2rem)' }; // 22px ~ 32px
  }
  if (len <= 13) {
    return { fontSize: 'clamp(1.2rem, 4.4vw, 1.75rem)' }; // 19px ~ 28px
  }
  return { fontSize: 'clamp(1.05rem, 3.8vw, 1.5rem)' }; // 17px ~ 24px
}

