/**
 * 业务日期与信用卡账单周期。
 * ============================================================================
 *
 * 全部业务日期都是 'YYYY-MM-DD' 字符串（**本地日期，不含时区**）。
 * 「今天」由客户端按本地时区判定后传入，服务端从不自行推算业务日期。
 *
 * 只在做日期加减法时才临时借用 Date，并且**固定用 Date.UTC + getUTC\***
 * 取回 —— 这样运算结果与运行环境的时区完全无关。如果用本地时间的
 * `new Date(y, m, d)`，一台跑 UTC 的容器和一台跑 Asia/Shanghai 的机器
 * 算出的「减 5 天」结果会在跨越夏令时或日界时不一致。
 *
 * 这一层是纯函数、无副作用，所以它被单独拎出来配了单元测试：
 * 它是整个系统里最容易写出「看着对、少数情况下错一个月」的地方。
 */

import { HttpError } from '../lib/http-error.ts';

export interface Ymd {
  year: number;
  /** 1–12，不是 JS 的 0–11 */
  month: number;
  day: number;
}

/** 支付方式的账单周期描述 */
export type PaymentCycle =
  | { type: 'cash' }
  | { type: 'credit'; billingDay: number; repaymentDay: number };

export interface ResolvedDates {
  /** 入账日（账单日） */
  postingDate: string;
  /** 还款日 —— 报表月份归属以此为准 */
  repaymentDate: string;
}

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isDateString(value: unknown): value is string {
  return typeof value === 'string' && DATE_RE.test(value);
}

/** 某年某月的天数。注意 Date.UTC 的月份是 0 基的，这里传入的是 1 基月份。 */
export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * 把「几号」钳到该月实际存在的范围内。
 *
 * 「每月 31 号」在 2 月是不存在的。**必须钳到该月最后一天（2/28 或 2/29），
 * 绝不能顺延到下个月 1 号** —— 顺延会让「2 月的房贷」落到 3 月，
 * 报表的月份归属直接错乱，而且这种错误只在特定月份出现，极难被发现。
 */
export function clampDay(year: number, month: number, day: number): number {
  return Math.min(day, daysInMonth(year, month));
}

export function toDateString(year: number, month: number, day: number): string {
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

export function parseDate(value: string): Ymd {
  const matched = DATE_RE.exec(value);
  if (matched === null) {
    throw new HttpError(400, `日期格式必须是 YYYY-MM-DD，收到：${value}`);
  }

  const [, rawYear, rawMonth, rawDay] = matched;
  if (rawYear === undefined || rawMonth === undefined || rawDay === undefined) {
    throw new HttpError(400, `日期格式必须是 YYYY-MM-DD，收到：${value}`);
  }

  const year = Number(rawYear);
  const month = Number(rawMonth);
  const day = Number(rawDay);

  if (month < 1 || month > 12) {
    throw new HttpError(400, `月份必须在 01–12 之间：${value}`);
  }
  if (day < 1 || day > daysInMonth(year, month)) {
    throw new HttpError(400, `该月没有这一天：${value}`);
  }

  return { year, month, day };
}

/** 月份加减，返回归一化后的年月。 */
function shiftMonth(year: number, month: number, delta: number): { year: number; month: number } {
  const total = year * 12 + (month - 1) + delta;
  return { year: Math.floor(total / 12), month: (total % 12) + 1 };
}

/**
 * 日期顺延 N 个月，**保持「几号」不变，遇该月无此日则取该月最后一天**。
 * 这是计划（房贷 / 分期）逐期生成日期用的核心函数。
 */
export function addMonthsToDate(date: string, delta: number): string {
  const { year, month, day } = parseDate(date);
  const shifted = shiftMonth(year, month, delta);
  return toDateString(shifted.year, shifted.month, clampDay(shifted.year, shifted.month, day));
}

/**
 * 日期加减天数。用 UTC 毫秒运算，结果与运行环境时区无关。
 * 用于「还款日前 n 天提醒」，这需要跨越月末甚至跨年。
 */
export function addDaysToDate(date: string, delta: number): string {
  const { year, month, day } = parseDate(date);
  const millis = Date.UTC(year, month - 1, day) + delta * 86_400_000;
  const shifted = new Date(millis);
  return toDateString(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1, shifted.getUTCDate());
}

/** 'YYYY-MM-DD' → 'YYYY-MM'，报表按月聚合用 */
export function monthOf(date: string): string {
  return date.slice(0, 7);
}

/** 起始月 + n 个月 → 'YYYY-MM' */
export function shiftMonthString(month: string, delta: number): string {
  const matched = /^(\d{4})-(\d{2})$/.exec(month);
  if (matched === null || matched[1] === undefined || matched[2] === undefined) {
    throw new HttpError(400, `月份格式必须是 YYYY-MM，收到：${month}`);
  }
  const shifted = shiftMonth(Number(matched[1]), Number(matched[2]), delta);
  return `${String(shifted.year).padStart(4, '0')}-${String(shifted.month).padStart(2, '0')}`;
}

/**
 * 消费日 → 入账日 / 还款日。
 *
 * 信用卡规则（消费日 d，账单日 B，还款日 R）：
 *
 *     d <= B  →  入账日 = 本期的 B
 *     d >  B  →  入账日 = 次期的 B
 *
 * 还款日的「期」必须与入账日对齐，而不能简单地取本月的 R：
 *   R > B（如账单日 10、还款日 28）  → 还款日与入账日同月
 *   R < B（如账单日 25、还款日次月 10）→ 还款日落在入账日的下一个月
 * 这里用 `R > B ? 本月 : 下月` 判定，等于或小于都推到下月 ——
 * 因为还款日必须在入账日之后，同日或更早都不成立。
 *
 * 现金 / 储蓄卡没有账单周期，入账日 = 还款日 = 消费日。
 */
export function resolveExpenseDates(spendDate: string, cycle: PaymentCycle): ResolvedDates {
  const spend = parseDate(spendDate);

  if (cycle.type === 'cash') {
    return { postingDate: spendDate, repaymentDate: spendDate };
  }

  const { billingDay, repaymentDay } = cycle;

  // 账单日当天消费算本期（`<=`），这是我们自己定死的规则，不留「看情况」
  const billPeriod =
    spend.day <= billingDay
      ? { year: spend.year, month: spend.month }
      : shiftMonth(spend.year, spend.month, 1);

  const postingDate = toDateString(
    billPeriod.year,
    billPeriod.month,
    clampDay(billPeriod.year, billPeriod.month, billingDay),
  );

  const repayPeriod =
    repaymentDay > billingDay ? billPeriod : shiftMonth(billPeriod.year, billPeriod.month, 1);

  const repaymentDate = toDateString(
    repayPeriod.year,
    repayPeriod.month,
    clampDay(repayPeriod.year, repayPeriod.month, repaymentDay),
  );

  return { postingDate, repaymentDate };
}

/**
 * 还款日 → 入账日。`resolveExpenseDates` 的逆向推算。
 *
 * 用途是计划的待办：待办的日期是从计划的「首期还款日」逐期推出来的
 * （用户只给了还款日），但记录里还要有入账日（账单日）。所以需要反向算。
 *
 * 规则与正向一致，只是方向相反：
 *   R > B（还款日在本月账单日之后）→ 入账日 = 本月的 B
 *   R <= B（还款日在本月账单日当天或之前）→ 入账日 = 上个月的 B
 * 后者对应「账单日 25、还款日次月 10」这类卡：10 号还款，账单其实是上月 25 号出的。
 */
export function resolvePostingDate(repaymentDate: string, cycle: PaymentCycle): string {
  if (cycle.type === 'cash') return repaymentDate;

  const repay = parseDate(repaymentDate);
  const { billingDay, repaymentDay } = cycle;

  // 月末吸附还原：待办日期是「每月 R 号、遇该月无此日取月末」生成的，
  // 平年 2 月的「R=31 号」落在 2/28。直接拿 28 与账单日比较会把它误判成
  // 上一期（如账单日 28 时 28 > 28 不成立），入账日倒退一个月。
  // 因此当日期被月末吸附（是该月最后一天且 R 比它大）时，按配置的 R 参与比较。
  const clampedToMonthEnd =
    repay.day === daysInMonth(repay.year, repay.month) && repaymentDay > repay.day;
  const effectiveDay = clampedToMonthEnd ? repaymentDay : repay.day;

  const period =
    effectiveDay > billingDay
      ? { year: repay.year, month: repay.month }
      : shiftMonth(repay.year, repay.month, -1);

  return toDateString(period.year, period.month, clampDay(period.year, period.month, billingDay));
}

/** 还款日往前推 n 天 = 提醒日。n = 0 时即还款日当天。 */
export function computeRemindDate(repaymentDate: string, daysBefore: number): string {
  return addDaysToDate(repaymentDate, -daysBefore);
}

/**
 * 计划逐期生成日期。
 *
 * 第 1 期用首期还款日，之后每期同上「保持几号、遇无此日取月末」。
 * 注意这里是**从首期日递推**（`addMonthsToDate(firstDue, i)`）而不是
 * 「上一期 + 1 个月」逐级累加 —— 逐级累加会把 1/31 → 2/28 的错误一路
 * 传染下去，后面每一期都变成 28 号。
 */
export function generatePeriodDates(firstDueDate: string, count: number): string[] {
  const dates: string[] = [];
  for (let index = 0; index < count; index += 1) {
    dates.push(addMonthsToDate(firstDueDate, index));
  }
  return dates;
}
