import type { DatabaseSync } from 'node:sqlite';

import { daysInMonth, shiftMonthString } from '../../domain/billing-cycle.ts';

/**
 * 报表聚合。
 *
 * 所有查询都锚在 `repayment_date`（还款日）上 —— 这是「钱什么时候出去」的
 * 现金流出视角，也是整个项目的月份归属口径。因为该列有索引
 * （`ix_expenses_repayment_date`），聚合能走索引而无需全表扫描。
 *
 * 每月/每年都**由查询参数显式传入**，服务端从不自己推算「今天是几号」：
 * 服务端的时区不可信，而客户端的本地日期才是用户认知里的「今天」。
 */

export interface SubCategoryBucket {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  cents: number;
  count: number;
  ratio: number;
}

export interface CategoryBucket {
  categoryId: string;
  name: string;
  /** 图标名（见前端 utils/icons.ts）；空字符串表示没设图标，由前端按名字兜底 */
  icon: string;
  color: string;
  cents: number;
  count: number;
  /** 占总额比例，0–1。总额为 0 时统一为 0 */
  ratio: number;
  /** 上一个同口径期间的金额（分）。月报比上月、年报比去年；没有则为 0 */
  previousCents: number;
  /**
   * 环比。上期为 0 时 null —— 「从 0 涨到 X」算不出有意义的百分比，
   * 给成 100% 或 ∞ 都会误导。与 MonthlyReport.change.ratio 同一套口径。
   */
  changeRatio: number | null;
  /** 二级子分类明细，按金额倒序 */
  children: SubCategoryBucket[];
}

export interface PaymentBucket {
  paymentMethodId: string;
  name: string;
  type: 'cash' | 'credit';
  cents: number;
  count: number;
  /**
   * 该支付方式在本月的还款日（仅信用类有值）。
   * 直接取该组记录的 MIN(repayment_date) —— 同一张卡在同一账单周期内的
   * 还款日必然相同，所以这是精确值，不需要再按「账单日 + 还款日」反推。
   */
  repaymentDate: string | null;
}

export interface MemberBucket {
  ownerId: string;
  name: string;
  cents: number;
  count: number;
}

export interface PeriodTotals {
  totalCents: number;
  count: number;
}

/**
 * 单笔最高。
 *
 * 只给「最大的一笔」这一条，不做「Top N」—— 界面上它是一行提示，
 * 用来回答「这个月最肉疼的是哪一笔」；要排前列的话，流水页按金额排序更合适。
 */
export interface LargestExpense {
  expenseId: string;
  /** 归并后的一级分类名（与报表其他部分同粒度） */
  categoryName: string;
  cents: number;
  repaymentDate: string;
}

/** 同期对比（同比）。ratio 的 null 规则与环比一致 */
export interface ComparedPeriod {
  label: string;
  totalCents: number;
  change: { deltaCents: number; ratio: number | null };
}

export interface DailyRhythmPoint {
  date: string;
  day: number;
  cents: number;
  count: number;
}

export interface MonthlyReport {
  month: string;
  totalCents: number;
  count: number;
  previous: { month: string; totalCents: number };
  /** 环比。上期为 0 时 ratio 为 null —— 「从 0 涨到 X」算不出有意义的百分比 */
  change: { deltaCents: number; ratio: number | null };
  /** 同比（去年同月）。月初的月份看环比没意义（上个月常常还是空的），同比才有参照 */
  yearAgo: ComparedPeriod;
  /** 本月金额最大的一笔；整月没有记录时为 null */
  largest: LargestExpense | null;
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  members: MemberBucket[];
  /** 逐日节奏 */
  daily: DailyRhythmPoint[];
  /** 滚动 12 个月（含本月及过去 11 个月），供热力图与 12 月均值 */
  rolling12Months: Array<{ month: string; totalCents: number | null; count: number }>;
  average12MonthsCents: number;
  /** 过去 3 个月日均消费（分），供进度对比卡 */
  rolling3MonthsDailyAverageCents: number;
  /** 下月要还（信用类） */
  nextMonthRepayments: PaymentBucket[];
  nextMonthDueTotalCents: number;
}

export interface YearlyReport {
  year: string;
  totalCents: number;
  count: number;
  /** 12 个月，没有数据的月份补 0，保证图表不会缺格 */
  months: Array<{ month: string; totalCents: number; count: number }>;
  /** 同比（去年整年） */
  yearAgo: ComparedPeriod;
  largest: LargestExpense | null;
  categories: CategoryBucket[];
  members: MemberBucket[];
  /** 近 3 年年均消费（分） */
  average3YearsCents: number;
  /** 本年支出最高月份 */
  peakMonth: { month: string; totalCents: number } | null;
}

export interface SummaryReport {
  totalCents: number;
  count: number;
  firstRepaymentDate: string | null;
  lastRepaymentDate: string | null;
  recordedDays: number;
  monthlyAverageCents: number;
  dailyAverageCents: number;
  perExpenseAverageCents: number;
  peakMonth: { month: string; totalCents: number } | null;
  years: Array<{ year: string; totalCents: number; count: number }>;
  categories: CategoryBucket[];
  members: MemberBucket[];
}

interface PeriodScope {
  /** 'YYYY-MM' 或 'YYYY-'，用作 repayment_date 的前缀；空字符串表示全量 */
  prefix: string;
  ownerId?: string | undefined;
}

function scopeClause(scope: PeriodScope): { sql: string; params: string[] } {
  const sql = ['e.deleted_at IS NULL'];
  const params: string[] = [];
  if (scope.prefix !== '') {
    sql.push("e.repayment_date LIKE ? || '%'");
    params.push(scope.prefix);
  }
  if (scope.ownerId !== undefined) {
    sql.push('e.owner_id = ?');
    params.push(scope.ownerId);
  }
  return { sql: sql.join(' AND '), params };
}

function totals(db: DatabaseSync, period: string, ownerId?: string): PeriodTotals {
  const scope = scopeClause({ prefix: period, ownerId });
  const row = db
    .prepare(
      `SELECT COALESCE(SUM(e.amount_cents), 0) AS cents, COUNT(*) AS cnt
         FROM expenses e WHERE ${scope.sql}`,
    )
    .get(...scope.params);

  return {
    totalCents: row === undefined ? 0 : Number(row['cents']),
    count: row === undefined ? 0 : Number(row['cnt']),
  };
}

/**
 * 按**一级分类**聚合。
 *
 * 二级分类的支出归并到它的一级父级下 —— 报表要回答的是「花在什么上面」，
 * 这个问题的粒度是一级分类；二级分类是记账时的精细度，不是分析的粒度。
 * `COALESCE(c.parent_id, c.id)` 同时覆盖了「记录直接挂在一级分类上」的情况。
 *
 * `previous` 是**环比用的上一期同口径金额**，按 root_id 索引。
 * 做成必传参数而不是可选：漏传的表现只是「所有分类的环比都是 0 或 null」，
 * 界面上看起来像是这个月每个分类都没变化 —— 不报错，只是安静地错。
 */
function subCategoryBuckets(
  db: DatabaseSync,
  scope: PeriodScope,
  rootId: string,
  rootTotalCents: number,
): SubCategoryBucket[] {
  const where = scopeClause(scope);
  const rows = db
    .prepare(
      `SELECT c.id AS sub_id, c.name AS sub_name, c.icon AS sub_icon, c.color AS sub_color,
              SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
         JOIN categories c ON c.id = e.category_id
        WHERE ${where.sql}
          AND COALESCE(c.parent_id, c.id) = ?
        GROUP BY c.id
        ORDER BY cents DESC`,
    )
    .all(...where.params, rootId) as unknown as Array<Record<string, unknown>>;

  return rows.map((row) => {
    const cents = Number(row['cents']);
    return {
      categoryId: String(row['sub_id']),
      name: String(row['sub_name']),
      icon: String(row['sub_icon'] ?? ''),
      color: String(row['sub_color'] ?? ''),
      cents,
      count: Number(row['cnt']),
      ratio: rootTotalCents === 0 ? 0 : cents / rootTotalCents,
    };
  });
}

function categoryBuckets(
  db: DatabaseSync,
  scope: PeriodScope,
  totalCents: number,
  previous: Map<string, number>,
): CategoryBucket[] {
  const where = scopeClause(scope);

  const rows = db
    .prepare(
      `SELECT COALESCE(c.parent_id, c.id) AS root_id,
              SUM(e.amount_cents) AS cents,
              COUNT(*) AS cnt
         FROM expenses e
         JOIN categories c ON c.id = e.category_id
        WHERE ${where.sql}
        GROUP BY root_id
        ORDER BY cents DESC`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  return rows.map((row) => {
    const cents = Number(row['cents']);
    const rootId = String(row['root_id']);
    const meta = db.prepare('SELECT name, icon, color FROM categories WHERE id = ?').get(rootId);
    const previousCents = previous.get(rootId) ?? 0;

    return {
      categoryId: rootId,
      name: meta === undefined ? '未知分类' : String(meta['name']),
      icon: meta === undefined ? '' : String(meta['icon']),
      color: meta === undefined ? '' : String(meta['color']),
      cents,
      count: Number(row['cnt']),
      ratio: totalCents === 0 ? 0 : cents / totalCents,
      previousCents,
      changeRatio: previousCents === 0 ? null : (cents - previousCents) / previousCents,
      children: subCategoryBuckets(db, scope, rootId, cents),
    };
  });
}

/**
 * 某一期里「每个一级分类各花了多少」，只用来喂环比。
 *
 * 单开一个查询而不是复用 `categoryBuckets`：后者要按 name/icon/color 逐条回查
 * 分类表，而上期数据只需要两个数字，没必要为它多查 N 次元数据。
 */
function categoryCentsByRoot(db: DatabaseSync, scope: PeriodScope): Map<string, number> {
  const where = scopeClause(scope);

  const rows = db
    .prepare(
      `SELECT COALESCE(c.parent_id, c.id) AS root_id, SUM(e.amount_cents) AS cents
         FROM expenses e
         JOIN categories c ON c.id = e.category_id
        WHERE ${where.sql}
        GROUP BY root_id`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  const map = new Map<string, number>();
  for (const row of rows) map.set(String(row['root_id']), Number(row['cents']));
  return map;
}

/**
 * 金额最大的一笔。
 *
 * 负数金额（退款）永远不会被选中 —— 它按 `amount_cents DESC` 排在最末尾，
 * 而「本月最大的一笔」问的是花出去的钱。
 * 平局时按 id 兜底，保证同一份数据每次返回同一条（否则界面上会出现
 * 「刷新一下最大的一笔换了个分类」这种无从解释的现象）。
 */
/**
 * 金额最大的一笔。
 *
 * 强制只看正数支出：`amount_cents > 0` 把退款/冲销排除在外。
 * 仅按 `DESC` 排序是不够的 —— 全退款月份里所有金额都是负数，
 * 「最大的」-100.00 也会被选中，退款就被评成了最大支出。
 * 平局时按 id 兜底，保证同一份数据每次返回同一条（否则界面上会出现
 * 「刷新一下最大的一笔换了个分类」这种无从解释的现象）。
 */
function largestExpense(db: DatabaseSync, scope: PeriodScope): LargestExpense | null {
  const where = scopeClause(scope);

  const row = db
    .prepare(
      `SELECT e.id AS id,
              e.amount_cents AS cents,
              e.repayment_date AS repayment_date,
              root.name AS root_name
         FROM expenses e
         JOIN categories c ON c.id = e.category_id
    LEFT JOIN categories root ON root.id = COALESCE(c.parent_id, c.id)
        WHERE e.amount_cents > 0 AND ${where.sql}
        ORDER BY e.amount_cents DESC, e.id
        LIMIT 1`,
    )
    .get(...where.params) as Record<string, unknown> | undefined;

  if (row === undefined) return null;

  return {
    expenseId: String(row['id']),
    categoryName: row['root_name'] === null ? '未知分类' : String(row['root_name']),
    cents: Number(row['cents']),
    repaymentDate: String(row['repayment_date']),
  };
}

/** 同期对比。ratio 的 null 规则与环比完全一致，两处不要各写一套 */
function compare(label: string, currentCents: number, comparedCents: number): ComparedPeriod {
  const deltaCents = currentCents - comparedCents;
  return {
    label,
    totalCents: comparedCents,
    change: {
      deltaCents,
      ratio: comparedCents === 0 ? null : deltaCents / comparedCents,
    },
  };
}

function paymentBuckets(db: DatabaseSync, scope: PeriodScope): PaymentBucket[] {
  const where = scopeClause(scope);

  const rows = db
    .prepare(
      `SELECT m.id AS id, m.name AS name, m.type AS type,
              SUM(e.amount_cents) AS cents,
              COUNT(*) AS cnt,
              MIN(e.repayment_date) AS repayment_date
         FROM expenses e
         JOIN payment_methods m ON m.id = e.payment_method_id
        WHERE ${where.sql}
        GROUP BY m.id
        ORDER BY cents DESC`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  return rows.map((row) => ({
    paymentMethodId: String(row['id']),
    name: String(row['name']),
    type: row['type'] === 'credit' ? 'credit' : 'cash',
    cents: Number(row['cents']),
    count: Number(row['cnt']),
    repaymentDate: row['repayment_date'] === null ? null : String(row['repayment_date']),
  }));
}

/**
 * 「尚未入账的计划期次」按支付方式分组。
 *
 * 待还口径必须同时看两处：
 *   · `expenses` —— 已经入账、有明确还款日的钱（含计划确认后生成的 `source='plan'` 记录）；
 *   · `plan_todos` 中 `status='pending'` 的期次 —— 已经安排在某天要还、
 *     但**还没有**落成支出记录的钱。
 * 只看前者，会让「刚转成分期的账」在下月待还里凭空消失：原支出被软删了，
 * 期次又还没入账，于是那一期一份钱都不剩（用户报的正是这个 bug）。
 *
 * 只算 `pending` 是口径，必须同时满足 `expense_id IS NULL` 是防御：
 *   · `confirmed` 的期次早已由 `confirmTodo` 生成了 expenses，再算一次就是重复计数；
 *   · `skipped` / `cancelled` 是用户明确表示「这一期不记」，本就不该出现在待还里。
 * 两个条件一起写，是为了万一将来出现「状态仍是 pending 却已挂支出」的脏数据，
 * 也不会把同一笔钱算两遍。
 *
 * 期次的支付方式来自它所属的计划（`plan_todos` 本身不带支付方式），
 * 所以要 JOIN `plans` 再 JOIN `payment_methods`。计划被软删（`deleted_at` 非空）
 * 或已终止（`state != 'active'`）时，它的期次不再是「待还」，一律不计入。
 */
function pendingTodoBuckets(db: DatabaseSync, scope: PeriodScope): PaymentBucket[] {
  const where: string[] = [
    't.deleted_at IS NULL',
    "t.status = 'pending'",
    't.expense_id IS NULL',
    'p.deleted_at IS NULL',
    "p.state = 'active'",
  ];
  const params: string[] = [];
  if (scope.prefix !== '') {
    where.push("t.repayment_date LIKE ? || '%'");
    params.push(scope.prefix);
  }
  if (scope.ownerId !== undefined) {
    where.push('p.owner_id = ?');
    params.push(scope.ownerId);
  }

  const rows = db
    .prepare(
      `SELECT m.id AS id, m.name AS name, m.type AS type,
              SUM(t.amount_cents) AS cents,
              COUNT(*) AS cnt,
              MIN(t.repayment_date) AS repayment_date
         FROM plan_todos t
         JOIN plans p ON p.id = t.plan_id
         JOIN payment_methods m ON m.id = p.payment_method_id
        WHERE ${where.join(' AND ')}
        GROUP BY m.id
        ORDER BY cents DESC`,
    )
    .all(...params) as unknown as Array<Record<string, unknown>>;

  return rows.map((row) => ({
    paymentMethodId: String(row['id']),
    name: String(row['name']),
    type: row['type'] === 'credit' ? 'credit' : 'cash',
    cents: Number(row['cents']),
    count: Number(row['cnt']),
    repaymentDate: row['repayment_date'] === null ? null : String(row['repayment_date']),
  }));
}

/** 取两个日期里更早的一个；null 表示「没有」。合并桶时用它对齐还款日。 */
function earliestDate(a: string | null, b: string | null): string | null {
  if (a === null) return b;
  if (b === null) return a;
  return a <= b ? a : b;
}

/**
 * 按支付方式合并两组桶：金额与笔数相加，还款日取更早的那个。
 *
 * 必须合并成一行而不是并列两行：同一张卡可能既有已入账的支出、又有未入账的期次，
 * 界面上「招行信用卡」出现两次会让人以为是两张不同的账单。
 */
function mergeBuckets(base: PaymentBucket[], extra: PaymentBucket[]): PaymentBucket[] {
  const merged = new Map<string, PaymentBucket>();
  for (const item of base) merged.set(item.paymentMethodId, { ...item });

  for (const item of extra) {
    const found = merged.get(item.paymentMethodId);
    if (found === undefined) {
      merged.set(item.paymentMethodId, { ...item });
      continue;
    }
    found.cents += item.cents;
    found.count += item.count;
    found.repaymentDate = earliestDate(found.repaymentDate, item.repaymentDate);
  }

  return [...merged.values()].sort((a, b) => b.cents - a.cents);
}

function memberBuckets(db: DatabaseSync, scope: PeriodScope): MemberBucket[] {
  const where = scopeClause(scope);

  const rows = db
    .prepare(
      `SELECT u.id AS id, u.display_name AS name,
              SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
         JOIN users u ON u.id = e.owner_id
        WHERE ${where.sql}
        GROUP BY u.id
        ORDER BY cents DESC`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  return rows.map((row) => ({
    ownerId: String(row['id']),
    name: String(row['name']),
    cents: Number(row['cents']),
    count: Number(row['cnt']),
  }));
}

function dailyRhythm(db: DatabaseSync, scope: PeriodScope, month: string): DailyRhythmPoint[] {
  const [y = 1970, m = 1] = month.split('-').map(Number);
  const totalDays = daysInMonth(y, m);
  const where = scopeClause(scope);

  const rows = db
    .prepare(
      `SELECT e.repayment_date AS d, SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
        WHERE ${where.sql}
        GROUP BY e.repayment_date`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  const map = new Map<string, { cents: number; count: number }>();
  for (const row of rows) {
    map.set(String(row['d']), {
      cents: Number(row['cents']),
      count: Number(row['cnt']),
    });
  }

  const result: DailyRhythmPoint[] = [];
  for (let day = 1; day <= totalDays; day++) {
    const dayStr = String(day).padStart(2, '0');
    const date = `${month}-${dayStr}`;
    const found = map.get(date) ?? { cents: 0, count: 0 };
    result.push({
      date,
      day,
      cents: found.cents,
      count: found.count,
    });
  }
  return result;
}

function rolling12(
  db: DatabaseSync,
  month: string,
  ownerId?: string,
): {
  rolling12Months: Array<{ month: string; totalCents: number | null; count: number }>;
  average12MonthsCents: number;
} {
  const startMonth = shiftMonthString(month, -11);
  const nextMonth = shiftMonthString(month, 1);
  const startDate = `${startMonth}-01`;
  const endDate = `${nextMonth}-01`;

  const sql = ['e.deleted_at IS NULL', 'e.repayment_date >= ?', 'e.repayment_date < ?'];
  const params: string[] = [startDate, endDate];
  if (ownerId !== undefined) {
    sql.push('e.owner_id = ?');
    params.push(ownerId);
  }

  const rows = db
    .prepare(
      `SELECT substr(e.repayment_date, 1, 7) AS ym,
              SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
        WHERE ${sql.join(' AND ')}
        GROUP BY ym`,
    )
    .all(...params) as unknown as Array<Record<string, unknown>>;

  const map = new Map<string, { cents: number; count: number }>();
  for (const row of rows) {
    map.set(String(row['ym']), {
      cents: Number(row['cents']),
      count: Number(row['cnt']),
    });
  }

  let totalSum = 0;
  const list: Array<{ month: string; totalCents: number | null; count: number }> = [];
  for (let i = -11; i <= 0; i++) {
    const ym = shiftMonthString(month, i);
    const found = map.get(ym);
    if (found !== undefined) {
      list.push({ month: ym, totalCents: found.cents, count: found.count });
      totalSum += found.cents;
    } else {
      list.push({ month: ym, totalCents: null, count: 0 });
    }
  }

  return {
    rolling12Months: list,
    average12MonthsCents: Math.round(totalSum / 12),
  };
}

function rolling3MonthsDailyAvg(db: DatabaseSync, month: string, ownerId?: string): number {
  let totalCents = 0;
  let totalDays = 0;
  for (let i = -3; i <= -1; i++) {
    const ym = shiftMonthString(month, i);
    const [y = 1970, m = 1] = ym.split('-').map(Number);
    totalDays += daysInMonth(y, m);
    const t = totals(db, ym, ownerId);
    totalCents += t.totalCents;
  }
  return totalDays === 0 ? 0 : Math.round(totalCents / totalDays);
}

function nextMonthCreditBuckets(
  db: DatabaseSync,
  month: string,
  ownerId?: string,
): {
  items: PaymentBucket[];
  totalCents: number;
} {
  const nextMonth = shiftMonthString(month, 1);
  const scope: PeriodScope = ownerId === undefined ? { prefix: nextMonth } : { prefix: nextMonth, ownerId };
  /**
   * 次月待还 = 已入账支出 + 尚未入账的计划期次。
   *
   * **只有待还口径走这个合并**：`paymentMethods`（本月各方式支出明细）必须保持
   * 「只算已入账」—— 期次是「将要花的钱」，混进支出构成会把占比算虚，
   * 而月报 `totalCents` 也不该因为一笔还没发生的消费而变大。
   */
  const credits = mergeBuckets(paymentBuckets(db, scope), pendingTodoBuckets(db, scope)).filter(
    (item) => item.type === 'credit',
  );
  const sum = credits.reduce((acc, c) => acc + c.cents, 0);
  return { items: credits, totalCents: sum };
}

function daysBetween(startStr: string, endStr: string): number {
  const [y1 = 1970, m1 = 1, d1 = 1] = startStr.split('-').map(Number);
  const [y2 = 1970, m2 = 1, d2 = 1] = endStr.split('-').map(Number);
  const utc1 = Date.UTC(y1, m1 - 1, d1);
  const utc2 = Date.UTC(y2, m2 - 1, d2);
  return Math.max(1, Math.round(Math.abs(utc2 - utc1) / (24 * 60 * 60 * 1000)) + 1);
}

export function monthlyReport(db: DatabaseSync, month: string, ownerId?: string): MonthlyReport {
  const current = totals(db, month, ownerId);
  const previousMonth = shiftMonthString(month, -1);
  const previous = totals(db, previousMonth, ownerId);

  // 去年同月。用 shiftMonthString(-12) 而不是拼字符串 —— 跨年（1 月）时
  // 手工拼年份是最容易错的一处，而这个函数已经有测试覆盖。
  const yearAgoMonth = shiftMonthString(month, -12);
  const yearAgoTotals = totals(db, yearAgoMonth, ownerId);

  const scope: PeriodScope = ownerId === undefined ? { prefix: month } : { prefix: month, ownerId };
  const previousScope: PeriodScope =
    ownerId === undefined ? { prefix: previousMonth } : { prefix: previousMonth, ownerId };
  const deltaCents = current.totalCents - previous.totalCents;

  const rolling = rolling12(db, month, ownerId);
  const rolling3Daily = rolling3MonthsDailyAvg(db, month, ownerId);
  const nextMonthCredit = nextMonthCreditBuckets(db, month, ownerId);

  return {
    month,
    totalCents: current.totalCents,
    count: current.count,
    previous: { month: previousMonth, totalCents: previous.totalCents },
    change: {
      deltaCents,
      // 上期为 0 时不给百分比：从 0 涨到 X 的「涨幅」是无穷大，显示成 100% 更误导
      ratio: previous.totalCents === 0 ? null : deltaCents / previous.totalCents,
    },
    yearAgo: compare(month.slice(5), current.totalCents, yearAgoTotals.totalCents),
    largest: largestExpense(db, scope),
    categories: categoryBuckets(
      db,
      scope,
      current.totalCents,
      categoryCentsByRoot(db, previousScope),
    ),
    paymentMethods: paymentBuckets(db, scope),
    members: memberBuckets(db, scope),
    daily: dailyRhythm(db, scope, month),
    rolling12Months: rolling.rolling12Months,
    average12MonthsCents: rolling.average12MonthsCents,
    rolling3MonthsDailyAverageCents: rolling3Daily,
    nextMonthRepayments: nextMonthCredit.items,
    nextMonthDueTotalCents: nextMonthCredit.totalCents,
  };
}

export function yearlyReport(db: DatabaseSync, year: string, ownerId?: string): YearlyReport {
  const prefix = `${year}-`;
  const scope: PeriodScope = ownerId === undefined ? { prefix } : { prefix, ownerId };

  const current = totals(db, prefix, ownerId);
  const where = scopeClause(scope);

  const rawMonths = db
    .prepare(
      `SELECT substr(e.repayment_date, 1, 7) AS ym,
              SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
        WHERE ${where.sql}
        GROUP BY ym`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  const byMonth = new Map<string, PeriodTotals>();
  for (const row of rawMonths) {
    byMonth.set(String(row['ym']), {
      totalCents: Number(row['cents']),
      count: Number(row['cnt']),
    });
  }

  const months = Array.from({ length: 12 }, (_, index) => {
    const month = `${year}-${String(index + 1).padStart(2, '0')}`;
    const found = byMonth.get(month) ?? { totalCents: 0, count: 0 };
    return { month, totalCents: found.totalCents, count: found.count };
  });

  const previousYear = String(Number(year) - 1);
  const previousPrefix = `${previousYear}-`;
  const previousScope: PeriodScope =
    ownerId === undefined ? { prefix: previousPrefix } : { prefix: previousPrefix, ownerId };

  let sum3 = 0;
  for (let i = -2; i <= 0; i++) {
    const y = String(Number(year) + i);
    sum3 += totals(db, `${y}-`, ownerId).totalCents;
  }
  const average3YearsCents = Math.round(sum3 / 3);

  const peak = months.reduce(
    (best, m) => (m.totalCents > best.totalCents ? m : best),
    months[0] ?? { month: `${year}-01`, totalCents: 0, count: 0 },
  );
  const peakMonth =
    peak && peak.totalCents > 0 ? { month: peak.month, totalCents: peak.totalCents } : null;

  return {
    year,
    totalCents: current.totalCents,
    count: current.count,
    months,
    yearAgo: compare('去年', current.totalCents, totals(db, previousPrefix, ownerId).totalCents),
    largest: largestExpense(db, scope),
    categories: categoryBuckets(db, scope, current.totalCents, categoryCentsByRoot(db, previousScope)),
    members: memberBuckets(db, scope),
    average3YearsCents,
    peakMonth,
  };
}

export function summaryReport(db: DatabaseSync, ownerId?: string): SummaryReport {
  const scope: PeriodScope = { prefix: '', ownerId };
  const current = totals(db, '', ownerId);
  const where = scopeClause(scope);

  const datesRow = db
    .prepare(
      `SELECT MIN(e.repayment_date) AS min_d,
              MAX(e.repayment_date) AS max_d,
              COUNT(DISTINCT substr(e.repayment_date, 1, 7)) AS m_cnt
         FROM expenses e
        WHERE ${where.sql}`,
    )
    .get(...where.params) as Record<string, unknown> | undefined;

  const minD = datesRow?.min_d ? String(datesRow.min_d) : null;
  const maxD = datesRow?.max_d ? String(datesRow.max_d) : null;
  const monthCount = Number(datesRow?.m_cnt ?? 0);
  const recordedDays = minD && maxD ? daysBetween(minD, maxD) : 0;

  const rawYears = db
    .prepare(
      `SELECT substr(e.repayment_date, 1, 4) AS y,
              SUM(e.amount_cents) AS cents, COUNT(*) AS cnt
         FROM expenses e
        WHERE ${where.sql}
        GROUP BY y
        ORDER BY y ASC`,
    )
    .all(...where.params) as unknown as Array<Record<string, unknown>>;

  const years = rawYears.map((row) => ({
    year: String(row['y']),
    totalCents: Number(row['cents']),
    count: Number(row['cnt']),
  }));

  const peakRow = db
    .prepare(
      `SELECT substr(e.repayment_date, 1, 7) AS ym,
              SUM(e.amount_cents) AS cents
         FROM expenses e
        WHERE ${where.sql}
        GROUP BY ym
        ORDER BY cents DESC
        LIMIT 1`,
    )
    .get(...where.params) as Record<string, unknown> | undefined;

  const peakMonth =
    peakRow && Number(peakRow.cents) > 0
      ? { month: String(peakRow.ym), totalCents: Number(peakRow.cents) }
      : null;

  return {
    totalCents: current.totalCents,
    count: current.count,
    firstRepaymentDate: minD,
    lastRepaymentDate: maxD,
    recordedDays,
    monthlyAverageCents: monthCount === 0 ? 0 : Math.round(current.totalCents / monthCount),
    dailyAverageCents: recordedDays === 0 ? 0 : Math.round(current.totalCents / recordedDays),
    perExpenseAverageCents: current.count === 0 ? 0 : Math.round(current.totalCents / current.count),
    peakMonth,
    years,
    categories: categoryBuckets(db, scope, current.totalCents, new Map()),
    members: memberBuckets(db, scope),
  };
}
