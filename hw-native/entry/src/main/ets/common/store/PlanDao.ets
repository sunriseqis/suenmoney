/**
 * 计划与待办的本地库（**本地优先**的读侧）。
 *
 * 与 `ExpenseDao` 同一思路：本地是唯一显示源，服务端只负责同步。
 *
 * ## 提醒口径必须与服务端一致
 *
 * 流水页顶卡「N 笔待处理」用的是服务端 `reminderToday` 口径（2026-10-29 用户裁决）：
 *   1. `status = 'pending'` 且还款日 ≤ today + 3 天（含已逾期）且未被「我知道了」摘掉；
 *   2. `status = 'skipped'` 且已逾期且**该计划不是自动入账** —— 逾期重现。
 *
 * 第 2 条的意思是「忽略」只是「这次别提醒我」，不是「这笔不用还了」。
 * 本地照抄这段 SQL，否则离线看到的条数和在线不一致。
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from './Db';
import { PlanItem, PlanTodoItem } from '../net/Api';

/** 计划进度（由待办派生，不存冗余计数） */
export interface PlanProgressLocal {
  paidCount: number;
  paidCents: number;
  totalCount: number;
  totalCents: number;
}

/** 本地计划（含派生的分类/支付方式名与进度） */
export interface PlanLocal {
  id: string;
  name: string;
  categoryId: string;
  categoryName: string;
  categoryIcon: string;
  paymentMethodId: string;
  paymentMethodName: string;
  amountCents: number;
  totalAmountCents: number | null;
  purchaseDate: string | null;
  firstDueDate: string;
  remindDaysBefore: number;
  autoPost: boolean;
  source: string;
  state: string;
  note: string;
  progress: PlanProgressLocal;
}

const SELECT_PLANS = `SELECT p.id, p.name, p.category_id, p.payment_method_id, p.amount_cents,
       p.total_amount_cents, p.purchase_date, p.first_due_date, p.remind_days_before,
       p.auto_post, p.source, p.state, p.note,
       COALESCE(c.name, '') AS category_name,
       COALESCE(c.icon, '') AS category_icon,
       COALESCE(m.name, '') AS payment_method_name
  FROM plans p
  LEFT JOIN categories c ON c.id = p.category_id
  LEFT JOIN payment_methods m ON m.id = p.payment_method_id`;

// plan_name 一律从 plans 表 JOIN 取真名。
// `plan_todos.plan_name` 是历史冗余列：增量 payload 不带它，只信它会出现空名字。
const SELECT_TODOS = `SELECT t.id, t.plan_id, COALESCE(p.name, t.plan_name, '') AS plan_name,
       t.period_seq, t.amount_cents, t.repayment_date, t.status, t.will_auto_post,
       t.expense_id, t.posted_date
  FROM plan_todos t
  LEFT JOIN plans p ON p.id = t.plan_id`;

export class PlanDao {
  /** 批量写计划（快照/增量用，冲突替换） */
  static async cachePlans(items: PlanLocal[]): Promise<void> {
    const store = Db.get();
    for (const p of items) {
      const bucket: relationalStore.ValuesBucket = {
        'id': p.id,
        'name': p.name,
        'category_id': p.categoryId,
        'payment_method_id': p.paymentMethodId,
        'amount_cents': p.amountCents,
        'total_amount_cents': p.totalAmountCents === null ? 0 : p.totalAmountCents,
        'purchase_date': p.purchaseDate === null ? '' : p.purchaseDate,
        'first_due_date': p.firstDueDate,
        'remind_days_before': p.remindDaysBefore,
        'auto_post': p.autoPost ? 1 : 0,
        'source': p.source,
        'state': p.state,
        'note': p.note,
        'updated_at': new Date().toISOString()
      };
      await store.insert('plans', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /** 批量写待办 */
  static async cacheTodos(items: PlanTodoItem[]): Promise<void> {
    const store = Db.get();
    for (const t of items) {
      const bucket: relationalStore.ValuesBucket = {
        'id': t.id,
        'plan_id': t.planId,
        'plan_name': t.planName,
        'period_seq': t.periodSeq,
        'amount_cents': t.amountCents,
        'repayment_date': t.repaymentDate,
        'status': t.status,
        'will_auto_post': t.willAutoPost ? 1 : 0,
        'expense_id': t.expenseId === undefined || t.expenseId === null ? '' : t.expenseId,
        'posted_date': t.postedDate === undefined || t.postedDate === null ? '' : t.postedDate,
        'updated_at': new Date().toISOString()
      };
      await store.insert('plan_todos', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  static async removePlan(id: string): Promise<void> {
    await Db.get().executeSql('DELETE FROM plans WHERE id = ?', [id]);
  }

  static async removeTodo(id: string): Promise<void> {
    await Db.get().executeSql('DELETE FROM plan_todos WHERE id = ?', [id]);
  }

  /** 全部计划（本地，含进度） */
  static async plans(): Promise<PlanLocal[]> {
    const rs = await Db.get().querySql(
      `${SELECT_PLANS} ORDER BY CASE p.state WHEN 'active' THEN 0 ELSE 1 END, p.first_due_date, p.id`
    );
    const out: PlanLocal[] = [];
    while (rs.goToNextRow()) {
      out.push(PlanDao.rowToPlan(rs));
    }
    rs.close();
    for (const p of out) {
      p.progress = await PlanDao.progressOf(p.id);
    }
    return out;
  }

  /** 计划进度：由待办派生 */
  static async progressOf(planId: string): Promise<PlanProgressLocal> {
    const rs = await Db.get().querySql(
      `SELECT
         SUM(CASE WHEN status = 'confirmed' THEN 1 ELSE 0 END) AS paid_cnt,
         SUM(CASE WHEN status = 'confirmed' THEN amount_cents ELSE 0 END) AS paid_cents,
         COUNT(*) AS total_cnt,
         SUM(amount_cents) AS total_cents
       FROM plan_todos WHERE plan_id = ?`,
      [planId]
    );
    let paidCount = 0;
    let paidCents = 0;
    let totalCount = 0;
    let totalCents = 0;
    if (rs.goToFirstRow()) {
      paidCount = rs.getLong(rs.getColumnIndex('paid_cnt'));
      paidCents = rs.getLong(rs.getColumnIndex('paid_cents'));
      totalCount = rs.getLong(rs.getColumnIndex('total_cnt'));
      totalCents = rs.getLong(rs.getColumnIndex('total_cents'));
    }
    rs.close();
    return {
      paidCount: paidCount,
      paidCents: paidCents,
      totalCount: totalCount,
      totalCents: totalCents
    };
  }

  /**
   * 提醒窗口内的待办（流水页顶卡 / 概况页）。
   *
   * SQL 与服务端 `listTodos({ reminderToday })` 逐条对齐，别单独改一边。
   */
  static async reminderTodos(today: string): Promise<PlanTodoItem[]> {
    const rs = await Db.get().querySql(
      `${SELECT_TODOS}
        WHERE (
          (t.status = 'pending' AND t.repayment_date <= date(?, '+3 days') AND t.ack_at IS NULL)
          OR (t.status = 'skipped' AND t.repayment_date < ? AND t.plan_id IN (
            SELECT id FROM plans WHERE auto_post = 0
          ))
        )
        ORDER BY t.repayment_date, t.period_seq`,
      [today, today]
    );
    const out: PlanTodoItem[] = [];
    while (rs.goToNextRow()) {
      out.push(PlanDao.rowToTodo(rs));
    }
    rs.close();
    return out;
  }

  /** 全部 pending 待办（设置页「待处理期次」用，不做提醒窗口过滤） */
  static async pendingTodos(): Promise<PlanTodoItem[]> {
    const rs = await Db.get().querySql(
      `${SELECT_TODOS} WHERE t.status = 'pending' ORDER BY t.repayment_date, t.period_seq`
    );
    const out: PlanTodoItem[] = [];
    while (rs.goToNextRow()) {
      out.push(PlanDao.rowToTodo(rs));
    }
    rs.close();
    return out;
  }

  /** 按状态查待办（设置页「已处理」区用：skipped / confirmed） */
  static async todosByStatus(status: string): Promise<PlanTodoItem[]> {
    const rs = await Db.get().querySql(
      `${SELECT_TODOS} WHERE t.status = ? ORDER BY t.repayment_date, t.period_seq`,
      [status]
    );
    const out: PlanTodoItem[] = [];
    while (rs.goToNextRow()) {
      out.push(PlanDao.rowToTodo(rs));
    }
    rs.close();
    return out;
  }

  /** 待办计数（诊断/自检用） */
  static async counts(): Promise<string> {
    const rs = await Db.get().querySql('SELECT (SELECT COUNT(*) FROM plans) AS p, (SELECT COUNT(*) FROM plan_todos) AS t');
    let text = 'plans=0 todos=0';
    if (rs.goToFirstRow()) {
      text = `plans=${rs.getLong(rs.getColumnIndex('p'))} todos=${rs.getLong(rs.getColumnIndex('t'))}`;
    }
    rs.close();
    return text;
  }

  private static rowToPlan(rs: relationalStore.ResultSet): PlanLocal {
    const total = rs.getColumnIndex('total_amount_cents');
    const purchase = rs.getColumnIndex('purchase_date');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      name: rs.getString(rs.getColumnIndex('name')),
      categoryId: rs.getString(rs.getColumnIndex('category_id')),
      categoryName: rs.getString(rs.getColumnIndex('category_name')),
      categoryIcon: rs.getString(rs.getColumnIndex('category_icon')),
      paymentMethodId: rs.getString(rs.getColumnIndex('payment_method_id')),
      paymentMethodName: rs.getString(rs.getColumnIndex('payment_method_name')),
      amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
      totalAmountCents: rs.isColumnNull(total) ? null : rs.getLong(total),
      purchaseDate: rs.isColumnNull(purchase) ? null : rs.getString(purchase),
      firstDueDate: rs.getString(rs.getColumnIndex('first_due_date')),
      remindDaysBefore: rs.getLong(rs.getColumnIndex('remind_days_before')),
      autoPost: rs.getLong(rs.getColumnIndex('auto_post')) === 1,
      source: rs.getString(rs.getColumnIndex('source')),
      state: rs.getString(rs.getColumnIndex('state')),
      note: rs.getString(rs.getColumnIndex('note')),
      progress: { paidCount: 0, paidCents: 0, totalCount: 0, totalCents: 0 }
    };
  }

  private static rowToTodo(rs: relationalStore.ResultSet): PlanTodoItem {
    const expenseId = rs.getColumnIndex('expense_id');
    const posted = rs.getColumnIndex('posted_date');
    return {
      id: rs.getString(rs.getColumnIndex('id')),
      planId: rs.getString(rs.getColumnIndex('plan_id')),
      planName: rs.getString(rs.getColumnIndex('plan_name')),
      periodSeq: rs.getLong(rs.getColumnIndex('period_seq')),
      amountCents: rs.getLong(rs.getColumnIndex('amount_cents')),
      repaymentDate: rs.getString(rs.getColumnIndex('repayment_date')),
      willAutoPost: rs.getLong(rs.getColumnIndex('will_auto_post')) === 1,
      status: rs.getString(rs.getColumnIndex('status')),
      expenseId: rs.isColumnNull(expenseId) || rs.getString(expenseId) === '' ? null : rs.getString(expenseId),
      postedDate: rs.isColumnNull(posted) || rs.getString(posted) === '' ? null : rs.getString(posted)
    };
  }
}
