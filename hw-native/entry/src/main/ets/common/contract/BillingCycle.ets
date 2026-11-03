/**
 * 业务日期与信用卡账单周期。
 *
 * ⚠ **与服务端 `server/src/domain/billing-cycle.ts` 逐条对应**。
 *   两边必须同步改：这是纯确定性日期运算（不涉及业务口径），
 *   客户端算一份是为了本地记账能立刻算出 `posting_date` / `repayment_date`；
 *   同步回推后服务端会再算一次并以它为准。
 *
 * 全部业务日期都是 'YYYY-MM-DD' 字符串（本地日期，不含时区）。
 * 只在做日期加减法时临时借用 Date，并且固定用 `Date.UTC` + `getUTC*` ——
 * 这样结果与运行环境时区无关。
 */

export interface Ymd {
  year: number;
  /** 1–12，不是 JS 的 0–11 */
  month: number;
  day: number;
}

/** 支付方式的账单周期描述（现金 vs 信用卡） */
export interface PaymentCycle {
  type: string;
  billingDay: number;
  repaymentDay: number;
}

export interface ResolvedDates {
  /** 入账日（账单日） */
  postingDate: string;
  /** 还款日 —— 报表月份归属以此为准 */
  repaymentDate: string;
}

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

/** 某年某月的天数。Date.UTC 的月份是 0 基，这里传入 1 基月份 */
export function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

/**
 * 把「几号」钳到该月实际存在的范围内。
 *
 * 「每月 31 号」在 2 月不存在，**必须钳到该月最后一天，绝不能顺延到下月 1 号** ——
 * 顺延会让「2 月的房贷」落到 3 月，报表月份归属直接错乱。
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
    throw new Error(`日期格式必须是 YYYY-MM-DD，收到：${value}`);
  }
  const year = Number(matched[1]);
  const month = Number(matched[2]);
  const day = Number(matched[3]);
  if (month < 1 || month > 12) {
    throw new Error(`月份必须在 01–12 之间：${value}`);
  }
  if (day < 1 || day > daysInMonth(year, month)) {
    throw new Error(`该月没有这一天：${value}`);
  }
  const out: Ymd = { year: year, month: month, day: day };
  return out;
}

/** 月份加减，返回归一化后的年月 */
function shiftMonth(year: number, month: number, delta: number): Ymd {
  const total = year * 12 + (month - 1) + delta;
  const y = Math.floor(total / 12);
  const m = (total % 12) + 1;
  const out: Ymd = { year: y, month: m, day: 1 };
  return out;
}

/**
 * 日期顺延 N 个月，保持「几号」不变，遇该月无此日则取该月最后一天。
 * 计划（房贷/分期）逐期生成日期用的核心函数。
 */
export function addMonthsToDate(date: string, delta: number): string {
  const d = parseDate(date);
  const shifted = shiftMonth(d.year, d.month, delta);
  return toDateString(shifted.year, shifted.month, clampDay(shifted.year, shifted.month, d.day));
}

/** 日期加减天数。用 UTC 毫秒运算，结果与运行环境时区无关 */
export function addDaysToDate(date: string, delta: number): string {
  const d = parseDate(date);
  const millis = Date.UTC(d.year, d.month - 1, d.day) + delta * 86400000;
  const shifted = new Date(millis);
  return toDateString(shifted.getUTCFullYear(), shifted.getUTCMonth() + 1, shifted.getUTCDate());
}

/**
 * 消费日 → 入账日 / 还款日。
 *
 * 信用卡规则（消费日 d，账单日 B，还款日 R）：
 *
 *     d <= B  →  入账日 = 本期的 B
 *     d >  B  →  入账日 = 次期的 B
 *
 * 还款日的「期」必须与入账日对齐：
 *   R > B（账单日 10、还款日 28）  → 还款日与入账日同月
 *   R <= B（账单日 25、还款日次月 10）→ 还款日落在入账日的下一个月
 *
 * 现金 / 储蓄卡没有账单周期，入账日 = 还款日 = 消费日。
 */
export function resolveExpenseDates(spendDate: string, cycle: PaymentCycle): ResolvedDates {
  const spend = parseDate(spendDate);
  if (cycle.type === 'cash') {
    const same: ResolvedDates = { postingDate: spendDate, repaymentDate: spendDate };
    return same;
  }

  // 账单日当天消费算本期（`<=`），这是定死的规则
  const billPeriod: Ymd = spend.day <= cycle.billingDay
    ? { year: spend.year, month: spend.month, day: 1 }
    : shiftMonth(spend.year, spend.month, 1);

  const postingDate = toDateString(
    billPeriod.year,
    billPeriod.month,
    clampDay(billPeriod.year, billPeriod.month, cycle.billingDay)
  );

  const repayPeriod: Ymd = cycle.repaymentDay > cycle.billingDay
    ? billPeriod
    : shiftMonth(billPeriod.year, billPeriod.month, 1);

  const repaymentDate = toDateString(
    repayPeriod.year,
    repayPeriod.month,
    clampDay(repayPeriod.year, repayPeriod.month, cycle.repaymentDay)
  );

  const out: ResolvedDates = { postingDate: postingDate, repaymentDate: repaymentDate };
  return out;
}

/**
 * 还款日 → 入账日（`resolveExpenseDates` 的逆向）。
 *
 *   R > B  → 入账日 = 本月 B
 *   R <= B → 入账日 = 上月 B
 *
 * 月末吸附还原：待办日期按「遇该月无此日取月末」生成，平年 2 月的 R=31 落在 2/28，
 * 直接拿 28 与账单日比较会误判成上一期。因此当日期被月末吸附时按配置的 R 参与比较。
 */
export function resolvePostingDate(repaymentDate: string, cycle: PaymentCycle): string {
  if (cycle.type === 'cash') {
    return repaymentDate;
  }
  const repay = parseDate(repaymentDate);
  const clampedToMonthEnd =
    repay.day === daysInMonth(repay.year, repay.month) && cycle.repaymentDay > repay.day;
  const effectiveDay = clampedToMonthEnd ? cycle.repaymentDay : repay.day;
  const period: Ymd = effectiveDay > cycle.billingDay
    ? { year: repay.year, month: repay.month, day: 1 }
    : shiftMonth(repay.year, repay.month, -1);
  return toDateString(period.year, period.month, clampDay(period.year, period.month, cycle.billingDay));
}

/** 还款日往前推 n 天 = 提醒日 */
export function computeRemindDate(repaymentDate: string, daysBefore: number): string {
  return addDaysToDate(repaymentDate, -daysBefore);
}

/**
 * 计划逐期生成日期。
 *
 * 从首期日**递推**（`addMonthsToDate(firstDue, i)`），而不是「上一期 +1 个月」逐级累加 ——
 * 逐级累加会把 1/31 → 2/28 的错误一路传染，后面每期都变成 28 号。
 */
export function generatePeriodDates(firstDueDate: string, count: number): string[] {
  const dates: string[] = [];
  for (let index = 0; index < count; index += 1) {
    dates.push(addMonthsToDate(firstDueDate, index));
  }
  return dates;
}
