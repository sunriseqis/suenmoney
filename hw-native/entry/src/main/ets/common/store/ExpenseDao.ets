/**
 * 流水本地缓存（H2 · 离线 A 档的读侧）。
 *
 * 原则：本地库是**服务端数据的副本**，不是第二个真相源。
 *   - 线上：拉到的每一页写入本地；列表直接展示服务端返回值。
 *   - 断网：从本地按还款日取数现算（合计、分类聚合都在本地做）。
 * 两边口径必须一致 —— 所以月份归属统一用 repayment_date，
 * 与 Web 的 `by=repayment_date` 和服务端报表同义。
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from './Db';
import { ExpenseItem } from '../net/Api';

export interface LocalMonthTotal {
  totalCents: number;
  count: number;
}

export interface LocalCategoryTotal {
  categoryId: string;
  categoryName: string;
  cents: number;
  count: number;
}

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
    'updated_at': new Date().toISOString()
  };
  return bucket;
}

export class ExpenseDao {
  /** 批量缓存（每页拉回来就写一次，冲突替换） */
  static async cache(items: ExpenseItem[]): Promise<void> {
    if (items.length === 0) {
      return;
    }
    const store = Db.get();
    for (const item of items) {
      await store.insert('expenses', toBucket(item), relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /** 某月的本地流水（按还款日归属，与报表口径一致） */
  static async byMonth(month: string): Promise<ExpenseItem[]> {
    const store = Db.get();
    const rs = await store.querySql(
      'SELECT * FROM expenses WHERE substr(repayment_date, 1, 7) = ? ORDER BY spend_date DESC, id DESC',
      [month]
    );
    const out: ExpenseItem[] = [];
    while (rs.goToNextRow()) {
      out.push(ExpenseDao.rowToItem(rs));
    }
    rs.close();
    return out;
  }

  /** 某月合计（离线时取代 /api/reports/monthly 的 totalCents） */
  static async monthTotal(month: string): Promise<LocalMonthTotal> {
    const store = Db.get();
    const rs = await store.querySql(
      'SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS cnt FROM expenses WHERE substr(repayment_date, 1, 7) = ?',
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

  /** 某月按分类聚合（离线构成条用） */


  private static rowToItem(rs: relationalStore.ResultSet): ExpenseItem {
    const item: ExpenseItem = {
      id: rs.getString(rs.getColumnIndex('id')),
      ownerId: rs.getString(rs.getColumnIndex('owner_id')),
      ownerName: '',
      amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
      categoryId: rs.getString(rs.getColumnIndex('category_id')),
      categoryName: '',
      categoryIcon: '',
      categoryColor: '',
      parentCategoryColor: null,
      parentCategoryName: null,
      paymentMethodId: rs.getString(rs.getColumnIndex('payment_method_id')),
      paymentMethodName: '',
      paymentMethodType: '',
      spendDate: rs.getString(rs.getColumnIndex('spend_date')),
      postingDate: rs.getString(rs.getColumnIndex('posting_date')),
      repaymentDate: rs.getString(rs.getColumnIndex('repayment_date')),
      note: rs.getString(rs.getColumnIndex('note')),
      source: rs.getString(rs.getColumnIndex('source'))
    };
    return item;
  }
}
