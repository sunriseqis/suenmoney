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

/** 该月有多少天。走 UTC，避免时区/DST 把结果挤到相邻月份。 */
export function daysInMonth(month: string): number {
  const [year, mon] = month.split('-').map(Number);
  if (year === undefined || mon === undefined || !Number.isFinite(year) || !Number.isFinite(mon)) {
    return 30;
  }
  // Date.UTC 的月份从 0 起，day=0 表示「上个月的最后一天」，正好是我们要的
  return new Date(Date.UTC(year, mon, 0)).getUTCDate();
}

/**
 * 这个月已经过了多少天 —— 算「日均」时的分母。
 *
 * 口径是「已过天数」而不是整月天数：月初拿整月天数去除，日均会被压得很低，
 * 看起来像「这个月花得很少」，而实际上只是月还没过完。月末两种算法趋于一致。
 *
 * 历史月份按整月算（已经过完了），未来月份也按整月算（反正没有数据）。
 */
export function elapsedDays(month: string, today: string = todayLocal()): number {
  const total = daysInMonth(month);
  if (month !== today.slice(0, 7)) return total;
  return Math.min(total, Math.max(1, Number(today.slice(8, 10))));
}

const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'] as const;
const FULL_WEEKDAYS = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'] as const;

/** '2026-09-24' → '周四'。走 UTC，避免时区把日期挤到前后一天。 */
export function weekdayOf(date: string): string {
  const [year, month, day] = date.split('-').map(Number);
  if (year === undefined || month === undefined || day === undefined) return '';
  const index = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return WEEKDAYS[index] ?? '';
}

/** '2026-09-24' → '星期四'。走 UTC。 */
export function fullWeekdayOf(date: string): string {
  const [year, month, day] = date.split('-').map(Number);
  if (year === undefined || month === undefined || day === undefined) return '';
  const index = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
  return FULL_WEEKDAYS[index] ?? '';
}

export interface LedgerDateInfo {
  /** 日期主文本：今日 / 昨日 / 26日 */
  dayText: string;
  /** 星期副文本：星期一 / 星期日 / 星期六 */
  weekdayText: string;
  /** 完整拼接文本：今日星期一 / 昨日星期日 / 26日星期六 */
  full: string;
  /** 是否为近两天（今日或昨日） */
  isRecent: boolean;
}

/**
 * 流水日期简化显示（最远支持到 2 天简化显示）：
 * - 今天：今日 + 星期X，例如「今日星期一」
 * - 昨天：昨日 + 星期X，例如「昨日星期日」
 * - 2天前及更早：N日 + 星期X，例如「26日星期六」
 */
export function formatLedgerDate(date: string, today: string = todayLocal()): LedgerDateInfo {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return {
      dayText: date,
      weekdayText: '',
      full: date,
      isRecent: false,
    };
  }

  const weekday = fullWeekdayOf(date);
  const diff = daysUntil(date, today);

  if (diff === 0) {
    return {
      dayText: '今日',
      weekdayText: weekday,
      full: `今日${weekday}`,
      isRecent: true,
    };
  }

  if (diff === -1) {
    return {
      dayText: '昨日',
      weekdayText: weekday,
      full: `昨日${weekday}`,
      isRecent: true,
    };
  }

  const dayNum = Number(date.slice(8, 10));
  const dayText = `${dayNum}日`;

  return {
    dayText,
    weekdayText: weekday,
    full: `${dayText}${weekday}`,
    isRecent: false,
  };
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
