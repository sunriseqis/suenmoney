/**
 * 业务日期工具。
 *
 * 贯穿全项目的一条约定：**业务日期是 'YYYY-MM-DD' 字符串，不是 Date 对象**。
 * 只有需要做日期加减法时才临时借 Date.UTC 运算，并且一定用 `getUTC*` 取回结果 ——
 * 这样结果与设备时区无关。用 `new Date(y, m, d)` 那种本地构造，
 * 同一段代码在跨时区或跨夏令时的设备上会给出不同答案。
 */

/** 取本地时区下的今天，'YYYY-MM-DD'。业务日期一律由它产出，服务端不推算。 */
export function todayLocal(now: Date = new Date()): string {
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/** 当前月份 'YYYY-MM' */
export function currentMonth(now: Date = new Date()): string {
  return todayLocal(now).slice(0, 7);
}

/** '2026-09' → '2026 年 9 月' */
export function formatMonthLabel(month: string): string {
  const [year, mon] = month.split('-');
  if (year === undefined || mon === undefined) return month;
  return `${year} 年 ${Number(mon)} 月`;
}

/** '2026-09-24' → '09-24' */
export function formatDayLabel(date: string): string {
  const parts = date.split('-');
  return parts.length === 3 ? `${parts[1]}-${parts[2]}` : date;
}

/** '2026-09-24' → '9月24日' */
export function formatMonthDay(date: string): string {
  const parts = date.split('-');
  if (parts.length !== 3) return date;
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

/** 月份加减：'2026-01' - 1 → '2025-12' */
export function shiftMonth(month: string, delta: number): string {
  const [rawYear, rawMon] = month.split('-');
  const year = Number(rawYear);
  const mon = Number(rawMon);
  if (!Number.isFinite(year) || !Number.isFinite(mon)) return month;

  const total = year * 12 + (mon - 1) + delta;
  const nextYear = Math.floor(total / 12);
  const nextMon = (total % 12) + 1;
  return `${String(nextYear).padStart(4, '0')}-${String(nextMon).padStart(2, '0')}`;
}

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'] as const;

/** '2026-09-24' → '周四'。同样走 UTC，避免时区把日期挤到前后一天。 */
export function weekdayOf(date: string): string {
  const [year, month, day] = date.split('-').map(Number);
  if (year === undefined || month === undefined || day === undefined) return '';
  const index = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return WEEKDAYS[index] ?? '';
}

/**
 * 从 from 到 target 相差多少天。target 已过则为负数。
 *
 * 用于「距还款日还有 N 天」—— 这个数字必须在**用户所在时区**的
 * 「今天」基础上算，所以 from 默认取本地今天，而不是服务端时间。
 */
export function daysUntil(target: string, from: string = todayLocal()): number {
  const [ty, tm, td] = target.split('-').map(Number);
  const [fy, fm, fd] = from.split('-').map(Number);
  if (ty === undefined || tm === undefined || td === undefined) return 0;
  if (fy === undefined || fm === undefined || fd === undefined) return 0;

  const targetMs = Date.UTC(ty, tm - 1, td);
  const fromMs = Date.UTC(fy, fm - 1, fd);
  return Math.round((targetMs - fromMs) / 86_400_000);
}
