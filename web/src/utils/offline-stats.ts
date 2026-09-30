/**
 * 离线本地统计：把 IndexedDB 里缓存的流水在本地聚合成与在线报表同口径的结构。
 *
 * 存在的理由：报表接口在离线（`ApiError.status === 0`）时不可用，但用户离线记完
 * 一笔后，概况 / 报表 / 流水顶卡的「总额、分类统计、支付统计」必须立刻跟着变 ——
 * 否则数字停在旧值，看起来像「没记上」或「记了没反应」。
 *
 * 铁律：期间归属一律按 **repaymentDate（还款日）** 前缀匹配，与报表接口同源
 * （见 `docs/decisions.md`「报表月份归属以还款日为准」）。
 *   一笔 1 月 11 日的消费，若信用卡账单日 10、还款日 28，归属 **2 月**。
 *   若这里改用 spendDate，离线数字就会与在线数字对不上 —— 用户会以为丢账。
 *
 * 纯函数、不 import IDB：只接收数组入参，方便单测。
 */
import type {
  CategoryBucket,
  DailyRhythmPoint,
  Expense,
  LargestExpense,
  MemberBucket,
  MonthlyReport,
  PaymentBucket,
  SummaryReport,
  YearlyReport,
} from '../api/types.ts';

export type OfflineScope =
  | { scope: 'month'; month: string }
  | { scope: 'year'; year: string }
  | { scope: 'all' };

export interface OfflineStats {
  totalCents: number;
  count: number;
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  largestExpense: LargestExpense | null;
}

/** 缓存里删除是直接移除条目；若将来带上 deletedAt 之类的墓碑，这里兜底排除。 */
function isLive(expense: Expense): boolean {
  return (expense as { deletedAt?: unknown }).deletedAt == null;
}

/** 按 repaymentDate 判断是否落在目标期间：月档匹配 YYYY-MM、年档匹配 YYYY-。 */
function matchesPeriod(expense: Expense, scope: OfflineScope): boolean {
  if (scope.scope === 'all') return true;
  const date = expense.repaymentDate;
  if (typeof date !== 'string' || date.length < 7) return false;
  if (scope.scope === 'month') return date.slice(0, 7) === scope.month;
  return date.slice(0, 4) === scope.year;
}

function liveInScope(expenses: Expense[], scope: OfflineScope): Expense[] {
  return expenses.filter((item) => isLive(item) && matchesPeriod(item, scope));
}

/**
 * 从缓存流水算出某期间的报表口径统计。
 *
 * 说明：`Expense` 没有下发父分类 id，二级归并到一级时只能拿到父分类的**名称**，
 * 因此一级桶的 `categoryId` 用组内首笔的分类 id 近似；颜色 / 名称才是关键 ——
 * `dict.colorOf` 会优先用显式色号、再按名称回退到同一一级色，渲染结果与在线一致。
 */
export function computeOfflineStats(expenses: Expense[], scope: OfflineScope): OfflineStats {
  const list = liveInScope(expenses, scope);

  let totalCents = 0;
  let largestExpense: LargestExpense | null = null;

  interface CategoryAcc {
    id: string;
    name: string;
    icon: string;
    color: string;
    cents: number;
    count: number;
  }

  const categoryMap = new Map<string, CategoryAcc>();
  const paymentMap = new Map<string, PaymentBucket>();

  for (const item of list) {
    totalCents += item.amountCents;

    // 只在一级展示构成：有父分类就归并到父分类。
    const isChild = item.parentCategoryName !== null && item.parentCategoryName !== '';
    const name = isChild ? item.parentCategoryName! : item.categoryName;

    let category = categoryMap.get(name);
    if (category === undefined) {
      category = {
        id: item.categoryId,
        name,
        icon: item.categoryIcon,
        // 二级分类的颜色跟随父分类；一级就是自身颜色。
        color: isChild ? (item.parentCategoryColor ?? '') : item.categoryColor,
        cents: 0,
        count: 0,
      };
      categoryMap.set(name, category);
    }
    category.cents += item.amountCents;
    category.count += 1;

    let payment = paymentMap.get(item.paymentMethodId);
    if (payment === undefined) {
      payment = {
        paymentMethodId: item.paymentMethodId,
        name: item.paymentMethodName,
        type: item.paymentMethodType,
        cents: 0,
        count: 0,
        repaymentDate: null,
      };
      paymentMap.set(item.paymentMethodId, payment);
    }
    payment.cents += item.amountCents;
    payment.count += 1;

    // 单笔最高只认正数支出：退款 / 冲销（负数）不能冒充「最高一笔」。
    if (item.amountCents > 0 && (largestExpense === null || item.amountCents > largestExpense.cents)) {
      largestExpense = {
        expenseId: item.id,
        categoryName: name,
        cents: item.amountCents,
        repaymentDate: item.repaymentDate,
      };
    }
  }

  const categories: CategoryBucket[] = [...categoryMap.values()]
    .map((bucket) => ({
      categoryId: bucket.id,
      name: bucket.name,
      icon: bucket.icon,
      color: bucket.color,
      cents: bucket.cents,
      count: bucket.count,
      ratio: totalCents === 0 ? 0 : bucket.cents / totalCents,
      // 离线拿不到上一期数据：环比留空由界面显示「—」，不编造数字。
      previousCents: 0,
      changeRatio: null,
    }))
    .sort((a, b) => b.cents - a.cents);

  const paymentMethods: PaymentBucket[] = [...paymentMap.values()].sort(
    (a, b) => b.cents - a.cents,
  );

  return {
    totalCents,
    count: list.length,
    categories,
    paymentMethods,
    largestExpense,
  };
}

// ---------------------------------------------------------------------------
// 报表形状回退：视图直接把这些对象塞回原来的 `monthly/yearly/summary` ref，
// 这样模板里已有的字段绑定（分类构成、支付统计、热力图、笔数…）无需改造即可消费。
// ---------------------------------------------------------------------------

function shiftMonthString(month: string, delta: number): string {
  const [yearStr, monthStr] = month.split('-');
  const shifted = new Date(Date.UTC(Number(yearStr), Number(monthStr) - 1 + delta, 1));
  const year = shifted.getUTCFullYear();
  const mon = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${mon}`;
}

function daysInMonthOf(month: string): number {
  const [yearStr, monthStr] = month.split('-');
  return new Date(Date.UTC(Number(yearStr), Number(monthStr), 0)).getUTCDate();
}

function changeOf(current: number, previous: number): { deltaCents: number; ratio: number | null } {
  const deltaCents = current - previous;
  return { deltaCents, ratio: previous > 0 ? deltaCents / previous : null };
}

function averageOf(values: number[]): number {
  if (values.length === 0) return 0;
  return Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
}

function buildMembers(expenses: Expense[], scope: OfflineScope): MemberBucket[] {
  const map = new Map<string, MemberBucket>();
  for (const item of liveInScope(expenses, scope)) {
    const key = item.ownerId !== '' ? item.ownerId : item.ownerName;
    let bucket = map.get(key);
    if (bucket === undefined) {
      bucket = { ownerId: item.ownerId, name: item.ownerName, cents: 0, count: 0 };
      map.set(key, bucket);
    }
    bucket.cents += item.amountCents;
    bucket.count += 1;
  }
  return [...map.values()].sort((a, b) => b.cents - a.cents);
}

function buildDaily(expenses: Expense[], month: string): DailyRhythmPoint[] {
  const days = daysInMonthOf(month);
  const buckets: DailyRhythmPoint[] = Array.from({ length: days }, (_, index) => {
    const day = index + 1;
    return { date: `${month}-${String(day).padStart(2, '0')}`, day, cents: 0, count: 0 };
  });
  for (const item of liveInScope(expenses, { scope: 'month', month })) {
    const day = Number(item.repaymentDate.slice(8, 10));
    const bucket = buckets[day - 1];
    if (bucket !== undefined) {
      bucket.cents += item.amountCents;
      bucket.count += 1;
    }
  }
  return buckets;
}

function buildRolling12(
  expenses: Expense[],
  month: string,
): Array<{ month: string; totalCents: number | null; count: number }> {
  const result: Array<{ month: string; totalCents: number | null; count: number }> = [];
  for (let offset = 11; offset >= 0; offset -= 1) {
    const target = shiftMonthString(month, -offset);
    const stats = computeOfflineStats(expenses, { scope: 'month', month: target });
    result.push({
      month: target,
      // 无记录与「记录为 0」在热力图里用 null 区分（与在线一致）。
      totalCents: stats.count === 0 ? null : stats.totalCents,
      count: stats.count,
    });
  }
  return result;
}

export function buildMonthlyReportFallback(expenses: Expense[], month: string): MonthlyReport {
  const stats = computeOfflineStats(expenses, { scope: 'month', month });
  const previousMonth = shiftMonthString(month, -1);
  const previousStats = computeOfflineStats(expenses, { scope: 'month', month: previousMonth });
  const yearAgoMonth = shiftMonthString(month, -12);
  const yearAgoStats = computeOfflineStats(expenses, { scope: 'month', month: yearAgoMonth });

  const rolling12Months = buildRolling12(expenses, month);
  const rollingTotals = rolling12Months
    .map((item) => item.totalCents)
    .filter((value): value is number => value !== null && value > 0);
  const last3 = rolling12Months.slice(-3);
  const last3Days = last3.reduce(
    (sum, item) => sum + (item.count > 0 ? daysInMonthOf(item.month) : 0),
    0,
  );
  const last3Total = last3.reduce((sum, item) => sum + (item.totalCents ?? 0), 0);

  return {
    month,
    totalCents: stats.totalCents,
    count: stats.count,
    previous: { month: previousMonth, totalCents: previousStats.totalCents },
    change: changeOf(stats.totalCents, previousStats.totalCents),
    yearAgo: {
      label: yearAgoMonth,
      totalCents: yearAgoStats.totalCents,
      change: changeOf(stats.totalCents, yearAgoStats.totalCents),
    },
    largest: stats.largestExpense,
    categories: stats.categories,
    paymentMethods: stats.paymentMethods,
    members: buildMembers(expenses, { scope: 'month', month }),
    daily: buildDaily(expenses, month),
    rolling12Months,
    average12MonthsCents: averageOf(rollingTotals),
    rolling3MonthsDailyAverageCents: last3Days > 0 ? Math.round(last3Total / last3Days) : 0,
    // 下月应还依赖账单周期推导，离线做不出口径一致的值，留空不编造。
    nextMonthRepayments: [],
    nextMonthDueTotalCents: 0,
  };
}

export function buildYearlyReportFallback(expenses: Expense[], year: string): YearlyReport {
  const stats = computeOfflineStats(expenses, { scope: 'year', year });
  const previousYear = String(Number(year) - 1);
  const previousStats = computeOfflineStats(expenses, { scope: 'year', year: previousYear });

  const months = Array.from({ length: 12 }, (_, index) => {
    const month = `${year}-${String(index + 1).padStart(2, '0')}`;
    const monthStats = computeOfflineStats(expenses, { scope: 'month', month });
    return { month, totalCents: monthStats.totalCents, count: monthStats.count };
  });

  let peakMonth: { month: string; totalCents: number } | null = null;
  for (const item of months) {
    if (item.totalCents > 0 && (peakMonth === null || item.totalCents > peakMonth.totalCents)) {
      peakMonth = { month: item.month, totalCents: item.totalCents };
    }
  }

  const last3YearTotals = [0, 1, 2].map(
    (offset) =>
      computeOfflineStats(expenses, { scope: 'year', year: String(Number(year) - offset) }).totalCents,
  );

  return {
    year,
    totalCents: stats.totalCents,
    count: stats.count,
    months,
    yearAgo: {
      label: previousYear,
      totalCents: previousStats.totalCents,
      change: changeOf(stats.totalCents, previousStats.totalCents),
    },
    largest: stats.largestExpense,
    categories: stats.categories,
    members: buildMembers(expenses, { scope: 'year', year }),
    average3YearsCents: averageOf(last3YearTotals),
    peakMonth,
  };
}

export function buildSummaryReportFallback(expenses: Expense[]): SummaryReport {
  const stats = computeOfflineStats(expenses, { scope: 'all' });
  const live = expenses.filter(isLive);
  const dates = live
    .map((item) => item.repaymentDate)
    .filter((value) => typeof value === 'string' && value.length >= 10)
    .sort();

  const distinctDays = new Set(dates);
  const distinctMonths = new Set(dates.map((value) => value.slice(0, 7)));
  const yearKeys = [...new Set([...distinctMonths].map((value) => value.slice(0, 4)))].sort();
  const years = yearKeys.map((value) => {
    const yearStats = computeOfflineStats(expenses, { scope: 'year', year: value });
    return { year: value, totalCents: yearStats.totalCents, count: yearStats.count };
  });

  const monthTotals = new Map<string, number>();
  for (const item of live) {
    const key = item.repaymentDate.slice(0, 7);
    if (key.length !== 7) continue;
    monthTotals.set(key, (monthTotals.get(key) ?? 0) + item.amountCents);
  }
  let peakMonth: { month: string; totalCents: number } | null = null;
  for (const [month, cents] of monthTotals) {
    if (cents > 0 && (peakMonth === null || cents > peakMonth.totalCents)) {
      peakMonth = { month, totalCents: cents };
    }
  }

  return {
    totalCents: stats.totalCents,
    count: stats.count,
    firstRepaymentDate: dates[0] ?? null,
    lastRepaymentDate: dates.length > 0 ? dates[dates.length - 1]! : null,
    recordedDays: distinctDays.size,
    monthlyAverageCents:
      distinctMonths.size > 0 ? Math.round(stats.totalCents / distinctMonths.size) : 0,
    dailyAverageCents: distinctDays.size > 0 ? Math.round(stats.totalCents / distinctDays.size) : 0,
    perExpenseAverageCents: stats.count > 0 ? Math.round(stats.totalCents / stats.count) : 0,
    peakMonth,
    years,
    categories: stats.categories,
    members: buildMembers(expenses, { scope: 'all' }),
  };
}
