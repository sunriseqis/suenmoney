import type { DatabaseSync } from 'node:sqlite';

import { shiftMonthString } from '../../domain/billing-cycle.ts';

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
}

export interface YearlyReport {
  year: string;
  totalCents: number;
  count: number;
  /** 12 个月，没有数据的月份补 0，保证图表不会缺格 */
  months: Array<{ month: string; totalCents: number; count: number }>;
  /** 同比（去年整年） */
  yearAgo: ComparedPeriod;
  categories: CategoryBucket[];
  members: MemberBucket[];
}

interface PeriodScope {
  /** 'YYYY-MM' 或 'YYYY-'，用作 repayment_date 的前缀 */
  prefix: string;
  ownerId?: string | undefined;
}

function scopeClause(scope: PeriodScope): { sql: string; params: string[] } {
  const sql = ['e.deleted_at IS NULL', "e.repayment_date LIKE ? || '%'"];
  const params = [scope.prefix];
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
        WHERE ${where.sql}
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

  return {
    year,
    totalCents: current.totalCents,
    count: current.count,
    months,
    yearAgo: compare('去年', current.totalCents, totals(db, previousPrefix, ownerId).totalCents),
    categories: categoryBuckets(db, scope, current.totalCents, categoryCentsByRoot(db, previousScope)),
    members: memberBuckets(db, scope),
  };
}
