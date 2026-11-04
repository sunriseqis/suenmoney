/**
 * 流水本地库（**本地优先**的读侧）。
 *
 * ## 为什么改成「本地是唯一显示源」
 *
 * 旧实现是「在线优先 + 离线兜底」：列表直接展示服务端返回值，只有网络失败才回退本地。
 * 结果是断网时大量功能不可用（列表、筛选、合计都要重新走一遍本地逻辑，且行为与在线不一致）。
 *
 * 现在：**所有读取都走本地**，服务端只负责同步（快照 + 增量）。
 * 网络在不在，列表、筛选、合计都是同一条代码路径 —— 行为天然一致。
 *
 * ## 月份归属
 *
 * 用 `spend_date`（消费日），与服务端 `/api/expenses` 的默认 `by` 一致。
 * ⚠ 旧实现用 `repayment_date`，而在线列表用 `spend_date` —— 同一个月份在
 * 在线/离线两条路径下会列出**不同的记录**。这次统一到 `spend_date`。
 * （「本月要还」那类按还款日的口径是报表的事，不走这个列表。）
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from './Db';
import { ExpenseItem } from '../net/Api';

export interface LocalMonthTotal {
  totalCents: number;
  count: number;
}

/** 列表筛选条件（与服务端 `/api/expenses` 的 query 一一对应） */
export interface ExpenseQuery {
  month: string;
  /** 分页游标 `${date}|${id}`，null/空表示第一页 */
  cursor?: string | null;
  limit?: number;
  q?: string;
  categoryId?: string;
  paymentMethodId?: string;
  ownerId?: string;
}

export interface ExpensePageLocal {
  items: ExpenseItem[];
  nextCursor: string | null;
  hasMore: boolean;
}

const DEFAULT_LIMIT = 100;

/** 一行的写入形态（与 RDB 列名一致，snake_case） */
function toBucket(item: ExpenseItem): relationalStore.ValuesBucket {
  const bucket: relationalStore.ValuesBucket = {
    'id': item.id,
    'owner_id': item.ownerId,
    'amount_cents': item.amountCents,
    'category_id': item.categoryId,
    'payment_method_id': item.paymentMethodId,
    'spend_date': item.spendDate,
    'posting_date': item.postingDate,
    'repayment_date': item.repaymentDate,
    'note': item.note,
    'source': item.source,
    'plan_id': item.planId ?? '',
    'plan_period_seq': item.planPeriodSeq ?? 0,
    'updated_at': new Date().toISOString()
  };
  return bucket;
}

/**
 * 列表查询：支出表 JOIN 字典与用户，一次拿全展示所需字段。
 *
 * 为什么要 JOIN 而不是在 UI 层再查：流水行要显示分类名/图标/色、支付方式名、
 * 记录人 —— 每行单独查字典会变成 N+1，几十行就是上百次查询。
 */
const SELECT_JOINED = `SELECT e.id, e.owner_id, e.amount_cents, e.category_id, e.payment_method_id,
       e.spend_date, e.posting_date, e.repayment_date, e.note, e.source,
       e.plan_id, e.plan_period_seq,
       COALESCE(u.display_name, '') AS owner_name,
       COALESCE(c.name, '') AS category_name,
       COALESCE(c.icon, '') AS category_icon,
       COALESCE(c.color, '') AS category_color,
       pc.name AS parent_category_name,
       pc.color AS parent_category_color,
       COALESCE(m.name, '') AS payment_method_name,
       COALESCE(m.type, '') AS payment_method_type
  FROM expenses e
  LEFT JOIN users u ON u.id = e.owner_id
  LEFT JOIN categories c ON c.id = e.category_id
  LEFT JOIN categories pc ON pc.id = c.parent_id
  LEFT JOIN payment_methods m ON m.id = e.payment_method_id`;

export class ExpenseDao {
  /** 批量缓存（冲突替换） */
  static async cache(items: ExpenseItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    const store = Db.get();
    for (const item of items) {
      await store.insert('expenses', toBucket(item), relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /** 单条写入（记账后立刻可见，不必等下一次同步） */
  static async upsert(item: ExpenseItem): Promise<void> {
    await Db.get().insert('expenses', toBucket(item), relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  /** 软删语义：本地直接删行（服务端的软删记录不会出现在快照里） */
  static async remove(id: string): Promise<void> {
    await Db.get().executeSql('DELETE FROM expenses WHERE id = ?', [id]);
  }

  /**
   * 某月流水（分页）。筛选条件全部下推到 SQL —— 与服务端同一套口径。
   */
  static async query(cond: ExpenseQuery): Promise<ExpensePageLocal> {
    const where: string[] = ["substr(e.spend_date, 1, 7) = ?"];
    const params: Array<string | number> = [cond.month];

    const keyword = (cond.q ?? '').trim();
    if (keyword !== '') {
      // 备注、二级分类名、一级分类名都参与匹配（与服务端一致）
      where.push("(e.note LIKE '%' || ? || '%' OR c.name LIKE '%' || ? || '%' OR pc.name LIKE '%' || ? || '%')");
      params.push(keyword, keyword, keyword);
    }
    // 注意：ArkTS 不用非空断言 `!`，一律先落到局部常量再判空
    const categoryId: string = cond.categoryId ?? '';
    if (categoryId !== '') {
      // 给一级分类时连带它的二级一起算
      where.push('(e.category_id = ? OR c.parent_id = ?)');
      params.push(categoryId, categoryId);
    }
    const paymentId: string = cond.paymentMethodId ?? '';
    if (paymentId !== '') {
      where.push('e.payment_method_id = ?');
      params.push(paymentId);
    }
    const ownerId: string = cond.ownerId ?? '';
    if (ownerId !== '') {
      where.push('e.owner_id = ?');
      params.push(ownerId);
    }

    const cursor = cond.cursor ?? '';
    if (cursor !== '') {
      const parts = cursor.split('|');
      if (parts.length === 2) {
        // 键集分页：日期倒序，同日按 id 倒序
        where.push('(e.spend_date < ? OR (e.spend_date = ? AND e.id < ?))');
        params.push(parts[0], parts[0], parts[1]);
      }
    }

    const limit = Math.max(1, cond.limit ?? DEFAULT_LIMIT);
    const rs = await Db.get().querySql(
      `${SELECT_JOINED} WHERE ${where.join(' AND ')} ORDER BY e.spend_date DESC, e.id DESC LIMIT ?`,
      [...params, limit + 1]
    );

    const rows: ExpenseItem[] = [];
    while (rs.goToNextRow()) {
      rows.push(ExpenseDao.rowToItem(rs));
    }
    rs.close();

    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const last = page.length > 0 ? page[page.length - 1] : null;
    return {
      items: page,
      nextCursor: hasMore && last !== null ? `${last.spendDate}|${last.id}` : null,
      hasMore: hasMore
    };
  }

  /** 某月全部流水（不分页；离线聚合/报表用） */
  static async byMonth(month: string): Promise<ExpenseItem[]> {
    const page = await ExpenseDao.query({ month: month, limit: 100000 });
    return page.items;
  }

  /** 某月合计（消费日口径，与列表一致） */
  static async monthTotal(month: string): Promise<LocalMonthTotal> {
    const rs = await Db.get().querySql(
      "SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS cnt FROM expenses WHERE substr(spend_date, 1, 7) = ?",
      [month]
    );
    let total = 0;
    let count = 0;
    if (rs.goToFirstRow()) {
      total = rs.getLong(rs.getColumnIndex('total'));
      count = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return { totalCents: total, count: count };
  }

  /**
   * 某月合计 —— **按还款日归属**（与服务端月报同口径）。
   *
   * 与 `monthTotal()` 的区别：那个按 `spend_date`（跟列表筛选一致），
   * 这个按 `repayment_date`（跟报表口径一致）。hero 的「本月支出」要用后者。
   */
  static async monthTotalByRepayment(month: string): Promise<LocalMonthTotal> {
    const rs = await Db.get().querySql(
      "SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS cnt FROM expenses WHERE substr(repayment_date, 1, 7) = ?",
      [month]
    );
    let total = 0;
    let count = 0;
    if (rs.goToFirstRow()) {
      total = rs.getLong(rs.getColumnIndex('total'));
      count = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return { totalCents: total, count: count };
  }

  /** 某月「要还」金额：信用卡类支付方式的还款额（与月报 creditDueCents 同口径） */
  static async creditDueByRepayment(month: string): Promise<number> {
    const rs = await Db.get().querySql(
      `SELECT COALESCE(SUM(e.amount_cents), 0) AS total
         FROM expenses e
         JOIN payment_methods m ON m.id = e.payment_method_id
        WHERE substr(e.repayment_date, 1, 7) = ? AND m.type = 'credit'`,
      [month]
    );
    let total = 0;
    if (rs.goToFirstRow()) {
      total = rs.getLong(rs.getColumnIndex('total'));
    }
    rs.close();
    return total;
  }

  /** 本地总条数（诊断/自检用） */
  static async count(): Promise<number> {
    const rs = await Db.get().querySql('SELECT COUNT(*) AS cnt FROM expenses');
    let n = 0;
    if (rs.goToFirstRow()) {
      n = rs.getLong(rs.getColumnIndex('cnt'));
    }
    rs.close();
    return n;
  }

  private static rowToItem(rs: relationalStore.ResultSet): ExpenseItem {
    const parentName = rs.getColumnIndex('parent_category_name');
    const parentColor = rs.getColumnIndex('parent_category_color');
    const item: ExpenseItem = {
      id: rs.getString(rs.getColumnIndex('id')),
      ownerId: rs.getString(rs.getColumnIndex('owner_id')),
      ownerName: rs.getString(rs.getColumnIndex('owner_name')),
      amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
      categoryId: rs.getString(rs.getColumnIndex('category_id')),
      categoryName: rs.getString(rs.getColumnIndex('category_name')),
      categoryIcon: rs.getString(rs.getColumnIndex('category_icon')),
      categoryColor: rs.getString(rs.getColumnIndex('category_color')),
      parentCategoryColor: rs.isColumnNull(parentColor) ? null : rs.getString(parentColor),
      parentCategoryName: rs.isColumnNull(parentName) ? null : rs.getString(parentName),
      paymentMethodId: rs.getString(rs.getColumnIndex('payment_method_id')),
      paymentMethodName: rs.getString(rs.getColumnIndex('payment_method_name')),
      paymentMethodType: rs.getString(rs.getColumnIndex('payment_method_type')),
      spendDate: rs.getString(rs.getColumnIndex('spend_date')),
      postingDate: rs.getString(rs.getColumnIndex('posting_date')),
      repaymentDate: rs.getString(rs.getColumnIndex('repayment_date')),
      note: rs.getString(rs.getColumnIndex('note')),
      source: rs.getString(rs.getColumnIndex('source')),
      planId: rs.isColumnNull(rs.getColumnIndex('plan_id'))
        ? null : rs.getString(rs.getColumnIndex('plan_id')),
      planPeriodSeq: rs.isColumnNull(rs.getColumnIndex('plan_period_seq'))
        ? null : rs.getLong(rs.getColumnIndex('plan_period_seq'))
    };
    return item;
  }
}
