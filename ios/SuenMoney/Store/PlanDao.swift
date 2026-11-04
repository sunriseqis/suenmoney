//
//  PlanDao.swift
//  SuenMoney
//
//  计划与待办的本地库（**本地优先**的读侧）。
//
//  与鸿蒙 `PlanDao.ets` 同一套语义：本地是唯一显示源，服务端只负责同步。
//
//  ## 提醒口径必须与服务端一致
//
//  流水页顶卡「N 笔待处理」用服务端 `reminderToday` 口径：
//    1. `status = 'pending'` 且还款日 ≤ today + 3 天（含已逾期）且未被「我知道了」摘掉；
//    2. `status = 'skipped'` 且已逾期且**该计划不是自动入账** —— 逾期重现。
//  第 2 条的意思是「忽略」只是「这次别提醒我」，不是「这笔不用还了」。
//

import Foundation

public enum PlanDao {
    /// 提醒窗口内的待办（流水页顶卡 / 概况页）
    public static func reminderTodos(today: String) throws -> [PlanTodoItem] {
        let rows = try Db.shared.query("""
            SELECT t.id, t.plan_id, COALESCE(p.name, t.plan_name, '') AS plan_name,
                   t.period_seq, t.amount_cents, t.repayment_date, t.status,
                   t.will_auto_post, t.expense_id, t.posted_date, t.ack_at
              FROM plan_todos t
              LEFT JOIN plans p ON p.id = t.plan_id
             WHERE (
               (t.status = 'pending' AND t.repayment_date <= date(?, '+3 days') AND t.ack_at IS NULL)
               OR (t.status = 'skipped' AND t.repayment_date < ? AND t.plan_id IN (
                 SELECT id FROM plans WHERE auto_post = 0
               ))
             )
             ORDER BY t.repayment_date, t.period_seq
            """, [today, today])
        return rows.map(rowToTodo)
    }

    /// 全部 pending 待办（设置页「待处理期次」用，不做提醒窗口过滤）
    public static func pendingTodos() throws -> [PlanTodoItem] {
        let rows = try Db.shared.query("""
            SELECT t.id, t.plan_id, COALESCE(p.name, t.plan_name, '') AS plan_name,
                   t.period_seq, t.amount_cents, t.repayment_date, t.status,
                   t.will_auto_post, t.expense_id, t.posted_date, t.ack_at
              FROM plan_todos t
              LEFT JOIN plans p ON p.id = t.plan_id
             WHERE t.status = 'pending'
             ORDER BY t.repayment_date, t.period_seq
            """)
        return rows.map(rowToTodo)
    }

    /// 按状态查待办（设置页「已处理」区用：skipped / confirmed）
    public static func todosByStatus(_ status: String) throws -> [PlanTodoItem] {
        let rows = try Db.shared.query("""
            SELECT t.id, t.plan_id, COALESCE(p.name, t.plan_name, '') AS plan_name,
                   t.period_seq, t.amount_cents, t.repayment_date, t.status,
                   t.will_auto_post, t.expense_id, t.posted_date, t.ack_at
              FROM plan_todos t
              LEFT JOIN plans p ON p.id = t.plan_id
             WHERE t.status = ?
             ORDER BY t.repayment_date, t.period_seq
            """, [status])
        return rows.map(rowToTodo)
    }

    /// 待办动作的本地状态改写（由 PlanActions 调用）
    public static func setStatus(id: String, status: String,
                                 postedDate: String? = nil,
                                 clearPosting: Bool = false) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        if clearPosting {
            try Db.shared.run("""
                UPDATE plan_todos SET status = ?, posted_date = NULL, expense_id = NULL, updated_at = ?
                 WHERE id = ?
                """, [status, now, id])
        } else if let posted = postedDate {
            try Db.shared.run("""
                UPDATE plan_todos SET status = ?, posted_date = ?, updated_at = ? WHERE id = ?
                """, [status, posted, now, id])
        } else {
            try Db.shared.run("UPDATE plan_todos SET status = ?, updated_at = ? WHERE id = ?",
                              [status, now, id])
        }
    }

    public static func setAck(id: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try Db.shared.run("UPDATE plan_todos SET ack_at = ?, updated_at = ? WHERE id = ?",
                          [now, now, id])
    }

    /// 批量写待办（快照/增量用，冲突替换）
    public static func cacheTodos(_ items: [PlanTodoItem]) throws {
        for t in items {
            try Db.shared.run("""
                INSERT OR REPLACE INTO plan_todos
                  (id, plan_id, plan_name, period_seq, amount_cents, repayment_date,
                   status, will_auto_post, expense_id, posted_date, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [t.id, t.planId, t.planName, t.periodSeq, t.amountCents, t.repaymentDate,
                      t.status, t.willAutoPost ? 1 : 0, t.expenseId ?? "", t.postedDate ?? "",
                      ISO8601DateFormatter().string(from: Date())])
        }
    }

    /// 批量写计划（只写契约字段；分类/支付名走 JOIN）
    public static func cachePlans(_ items: [PlanItem]) throws {
        for p in items {
            try Db.shared.run("""
                INSERT OR REPLACE INTO plans
                  (id, name, category_id, payment_method_id, amount_cents, total_amount_cents,
                   purchase_date, first_due_date, remind_days_before, auto_post, source, state,
                   note, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [p.id, p.name, p.categoryId, p.paymentMethodId, p.amountCents, NSNull(),
                      NSNull(), p.firstDueDate, 3, p.autoPost ? 1 : 0, p.source, p.state, "",
                      ISO8601DateFormatter().string(from: Date())])
        }
    }

    public static func clearAll() throws {
        try Db.shared.run("DELETE FROM plan_todos")
        try Db.shared.run("DELETE FROM plans")
    }

    private static func rowToTodo(_ row: [String: Any]) -> PlanTodoItem {
        PlanTodoItem(
            expenseMonth: nil,
            expenseId: (row["expense_id"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            id: row["id"] as? String ?? "",
            planId: row["plan_id"] as? String ?? "",
            planName: row["plan_name"] as? String ?? "",
            periodSeq: row["period_seq"] as? Int ?? 0,
            amountCents: row["amount_cents"] as? Int ?? 0,
            repaymentDate: row["repayment_date"] as? String ?? "",
            willAutoPost: (row["will_auto_post"] as? Int ?? 0) == 1,
            status: row["status"] as? String ?? "pending",
            postedDate: (row["posted_date"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            ackAt: (row["ack_at"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
