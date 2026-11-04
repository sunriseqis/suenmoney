//
//  ExpenseActions.swift
//  SuenMoney
//
//  记账动作：**本地先写 + 入队 + 触发同步**（与鸿蒙 `ExpenseActions.ets` 同构）。
//
//  ## 为什么本地要自己算账单日期
//
//  `posting_date` / `repayment_date` 决定这笔账归属哪个月（报表按还款日聚合），
//  不能留空等同步回填 —— 否则本地列表在同步前会把它归到错误的月份。
//  算法见 `BillingCycle.swift`（与服务端 `domain/billing-cycle.ts` 逐条对应）。
//
//  ## 归属
//
//  `owner_id` 取当前登录用户 —— **谁记归谁**。离线启动时 `AuthStore.user` 为 nil，
//  用登录时写进 meta 的 `current_user_id` 兜底（归属不能空）。
//

import Foundation

public enum ExpenseActions {
    /// 本地新增：算日期 → 写本地 → 入队 → 触发同步，返回新记录 id
    public static func create(amountCents: Int,
                              categoryId: String,
                              paymentMethodId: String,
                              spendDate: String,
                              note: String,
                              cycle: PaymentCycle) throws -> String {
        let id = ulid()
        let dates = resolveExpenseDates(spendDate: spendDate, cycle: cycle)
        let ownerId = currentOwnerId()

        try Db.shared.run("""
            INSERT OR REPLACE INTO expenses
              (id, owner_id, amount_cents, category_id, payment_method_id, spend_date,
               posting_date, repayment_date, note, source, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [id, ownerId, amountCents, categoryId, paymentMethodId, spendDate,
                  dates.postingDate, dates.repaymentDate, note, "manual",
                  ISO8601DateFormatter().string(from: Date())])

        let payload: [String: Any] = [
            "id": id,
            "amountCents": amountCents,
            "categoryId": categoryId,
            "paymentMethodId": paymentMethodId,
            "spendDate": spendDate,
            "note": note,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            try Outbox.enqueue(.createExpense, entityId: id, payload: text)
        }
        SyncEngine.shared.schedulePush()
        return id
    }

    /// 本地修改：先改本地再入队（金额/分类/支付方式/消费日改动会重算账单日期）
    public static func update(id: String,
                              amountCents: Int,
                              categoryId: String,
                              paymentMethodId: String,
                              spendDate: String,
                              note: String,
                              cycle: PaymentCycle) throws {
        let dates = resolveExpenseDates(spendDate: spendDate, cycle: cycle)
        try Db.shared.run("""
            UPDATE expenses SET amount_cents = ?, category_id = ?, payment_method_id = ?,
                   spend_date = ?, posting_date = ?, repayment_date = ?, note = ?, updated_at = ?
             WHERE id = ?
            """, [amountCents, categoryId, paymentMethodId, spendDate,
                  dates.postingDate, dates.repaymentDate, note,
                  ISO8601DateFormatter().string(from: Date()), id])

        let payload: [String: Any] = [
            "id": id,
            "amountCents": amountCents,
            "categoryId": categoryId,
            "paymentMethodId": paymentMethodId,
            "spendDate": spendDate,
            "note": note,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let text = String(data: data, encoding: .utf8) {
            try Outbox.enqueue(.updateExpense, entityId: id, payload: text)
        }
        SyncEngine.shared.schedulePush()
    }

    /// 本地删除：先删本地再入队
    public static func remove(id: String) throws {
        try Db.shared.run("DELETE FROM expenses WHERE id = ?", [id])
        try Outbox.enqueue(.deleteExpense, entityId: id,
                           payload: "{\"id\":\"\(id)\"}")
        SyncEngine.shared.schedulePush()
    }

    /// 从本地支付方式表取账单周期；查不到按现金处理
    public static func cycleOf(paymentMethodId: String) -> PaymentCycle {
        let rows = (try? Db.shared.query(
            "SELECT type, billing_day, repayment_day FROM payment_methods WHERE id = ?",
            [paymentMethodId])) ?? []
        guard let row = rows.first else {
            return PaymentCycle(type: "cash", billingDay: 0, repaymentDay: 0)
        }
        return PaymentCycle(
            type: row["type"] as? String ?? "cash",
            billingDay: row["billing_day"] as? Int ?? 0,
            repaymentDay: row["repayment_day"] as? Int ?? 0
        )
    }

    /// 当前用户 id：内存优先，离线启动时回落 meta
    private static func currentOwnerId() -> String {
        if let id = AuthStore.shared.user?.id, !id.isEmpty {
            return id
        }
        let rows = (try? Db.shared.query(
            "SELECT value FROM meta WHERE key = ?", ["current_user_id"])) ?? []
        return rows.first?["value"] as? String ?? ""
    }
}
