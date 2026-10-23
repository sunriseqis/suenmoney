/**
 * 纯逻辑层：金额 / 日期 / 紧急度 / 环图（H0-5）。
 *
 * 与 Web 的 `web/src/utils/{money,dates,urgency,donut}.ts` **逐条同义**，
 * 因为三端共用同一份测试向量（docs/test-vectors/vectors.json）：
 * 谁改了实现，那份 JSON 就会有一条不过 —— 这是唯一能防止「三个端各算各的」的手段。
 *
 * 全项目口径（写错了不报错，只会算成另一个数）：
 *   金额：整数分；日期：YYYY-MM-DD 字符串；紧急度：迟于还款日=overdue，0–1 天=due，更远=later。
 */

// ── 金额 ────────────────────────────────────────────────────────────────────

/** 分 → '1,234.56'（不含货币符号，手写分组而不是 toLocaleString：各设备 Intl 版本不一） */
export function formatCents(cents: number): string {
  const negative = cents < 0;
  const abs = Math.abs(cents);
  const yuan = Math.floor(abs / 100);
  const fen = abs % 100;
  return `${negative ? '-' : ''}${groupThousands(yuan)}.${pad2(fen)}`;
}

/** 分 → '¥1,234.56' */
export function formatYuan(cents: number): string {
  return `¥${formatCents(cents)}`;
}

/** 分 → '1234.56' / '12'（回填输入框用，不带符号与千分位） */
export function centsToInput(cents: number): string {
  const abs = Math.abs(cents);
  const yuan = Math.floor(abs / 100);
  const fen = abs % 100;
  return fen === 0 ? String(yuan) : `${yuan}.${pad2(fen)}`;
}

/**
 * 元文本 → 整数分。
 *
 * **禁止** `parseFloat(x) * 100`：19.99 会得到 1998.9999999999998，
 * 四舍五入时机差一点就差一分钱，而这一分钱会一路累进到月度总额里。
 * 这里全程整数：元部分 ×100 + 小数部分补齐两位；符号先剥离再统一赋回
 * （否则 "-0.50" 会被算成 +50）。
 */
export function parseYuanToCents(input: string): number {
  if (input === '' || input === '.') {
    return 0;
  }
  const negative = input.startsWith('-');
  const abs = negative ? input.substring(1) : input;
  const parts = abs.split('.');
  const intPart = parts.length > 0 && parts[0] !== '' ? parts[0] : '0';
  const decPart = parts.length > 1 ? parts[1] : '';
  const yuan = Number(intPart);
  const fen = Number((decPart + '00').substring(0, 2));
  if (!Number.isFinite(yuan) || !Number.isFinite(fen)) {
    return 0;
  }
  const cents = yuan * 100 + fen;
  return negative ? -cents : cents;
}

/** 等额分期：前 n−1 期取整，末期补差，保证各期之和恰好等于总额 */
export function splitInstallment(totalCents: number, periods: number): number[] {
  if (!Number.isInteger(totalCents) || totalCents <= 0) {
    return [];
  }
  if (!Number.isInteger(periods) || periods < 1 || periods > 600) {
    return [];
  }
  if (totalCents < periods) {
    return [];
  }
  const base = Math.floor(totalCents / periods);
  const out: number[] = [];
  for (let i = 0; i < periods - 1; i++) {
    out.push(base);
  }
  out.push(totalCents - base * (periods - 1));
  return out;
}

// ── 日期（只用 YYYY-MM-DD 与 YYYY-MM，不用时间戳）──────────────────────────

/** 'YYYY-MM' 平移 n 个月，跨年正确 */
export function shiftMonth(month: string, delta: number): string {
  const parts = month.split('-');
  const y = Number(parts[0]);
  const m = Number(parts[1]);
  const total = y * 12 + (m - 1) + delta;
  const ny = Math.floor(total / 12);
  const nm = total % 12;
  return `${ny}-${pad2(nm + 1)}`;
}

/** 距目标日期还有几天（负数是已过去）。用 UTC 归一到整天，避免时区/夏令时误差 */
export function daysUntil(target: string, from: string): number {
  const a = Date.UTC(
    Number(from.substring(0, 4)),
    Number(from.substring(5, 7)) - 1,
    Number(from.substring(8, 10))
  );
  const b = Date.UTC(
    Number(target.substring(0, 4)),
    Number(target.substring(5, 7)) - 1,
    Number(target.substring(8, 10))
  );
  return Math.round((b - a) / 86400000);
}

// ── 紧急度 ──────────────────────────────────────────────────────────────────

export type Urgency = 'overdue' | 'due' | 'later';

/** 迟于还款日 = overdue；0–1 天 = due；更远 = later */
export function urgencyOf(date: string, today: string): Urgency {
  const days = daysUntil(date, today);
  if (days < 0) {
    return 'overdue';
  }
  if (days <= 1) {
    return 'due';
  }
  return 'later';
}

export function urgencyLabel(date: string, today: string): string {
  const days = daysUntil(date, today);
  if (days === 0) {
    return '今天到期';
  }
  if (days < 0) {
    return `已逾期 ${-days} 天`;
  }
  return `还有 ${days} 天`;
}

// ── 环图 ────────────────────────────────────────────────────────────────────

const DONUT_START_OFFSET = 25;

export interface DonutSlice {
  id: string;
  /** 0–1 的占比 */
  ratio: number;
  color: string;
}

export interface DonutArc {
  id: string;
  percent: number;
  offset: number;
  color: string;
}

/** 环图各段：offset 从 25 起递减累计；负 ratio 钳到 0（负的 dasharray 会破坏 SVG 语法） */
export function buildDonutArcs(slices: DonutSlice[]): DonutArc[] {
  const out: DonutArc[] = [];
  let cumulative = 0;
  for (const slice of slices) {
    const percent = round2(Math.max(0, slice.ratio) * 100);
    out.push({
      id: slice.id,
      percent: percent,
      offset: round2(DONUT_START_OFFSET - cumulative),
      color: slice.color
    });
    cumulative += percent;
  }
  return out;
}

// ── 内部工具 ────────────────────────────────────────────────────────────────

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

/** 千分位分组 */
function groupThousands(n: number): string {
  const s = String(n);
  let out = '';
  let count = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    out = s.charAt(i) + out;
    count++;
    if (count % 3 === 0 && i > 0) {
      out = ',' + out;
    }
  }
  return out;
}

function round2(v: number): number {
  return Math.round(v * 100) / 100;
}
