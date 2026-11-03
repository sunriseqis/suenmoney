//
//  SyncStore.swift
//  SuenMoney
//
//  快照落地：把服务端全量状态写进本地库。
//
//  与鸿蒙 `SyncStore.ets` 同一套语义：
//    · 只在「本地是空的 / 换账号 / 清过库」时调一次，日常走增量 pull；
//    · 分类 / 支付方式的 **color / icon 不覆盖** —— 这两列在本地是各端的个性化
//      偏好（服务端不再存也不再下发），同步冲掉的话用户挑的配色每次都白设；
//    · 支出 / 计划 / 待办先清后灌（快照即全量，否则服务端已删的记录会永远留着）；
//    · outbox 与 meta 游标**不清**。
//

import Foundation

public enum SyncStore {
    /// 拉快照并落库，返回快照点版本号（作为后续增量的游标）
    public static func bootstrap() async throws -> Int {
        let body = try await Api.syncSnapshot()
        try applySnapshot(body)
        return body.version
    }

    public static func applySnapshot(_ body: SyncSnapshotBody) throws {
        // 0. 用户：流水行的「记录人」靠它
        try Db.shared.run("DELETE FROM users")
        for u in body.users {
            try Db.shared.run("""
                INSERT OR REPLACE INTO users (id, display_name, role, updated_at)
                VALUES (?, ?, ?, ?)
                """, [u.id, u.displayName, u.role,
                      ISO8601DateFormatter().string(from: Date())])
        }

        // 1. 分类：只同步契约字段，**保留本地 color / icon**
        try mergeCategories(body.categories)

        // 2. 支付方式：同样保留本地 icon
        try mergePayments(body.paymentMethods)

        // 3. 支出 / 计划 / 待办：先清后灌
        try Db.shared.run("DELETE FROM expenses")
        try ExpenseDao.cache(body.expenses)

        try PlanDao.clearAll()
        try PlanDao.cachePlans(body.plans)
        try PlanDao.cacheTodos(body.planTodos)
    }

    /// 分类合并：有则只 UPDATE 名称类字段，无则 INSERT（保留本地个性化）
    private static func mergeCategories(_ nodes: [CategoryNode]) throws {
        var flat: [CategoryNode] = []
        for root in nodes {
            flat.append(root)
            flat.append(contentsOf: root.children)
        }
        var seen = Set<String>()
        for node in flat {
            seen.insert(node.id)
            let existing = try Db.shared.query("SELECT id FROM categories WHERE id = ?", [node.id])
            if existing.isEmpty {
                try Db.shared.run("""
                    INSERT OR REPLACE INTO categories
                      (id, parent_id, name, depth, icon, color, sort_order, is_enabled)
                    VALUES (?, ?, ?, ?, '', '', ?, ?)
                    """, [node.id, node.parentId ?? "", node.name, node.depth,
                          node.sortOrder, node.isEnabled ? 1 : 0])
            } else {
                // ⚠ 不碰 icon / color
                try Db.shared.run("""
                    UPDATE categories SET parent_id = ?, name = ?, depth = ?,
                           sort_order = ?, is_enabled = ? WHERE id = ?
                    """, [node.parentId ?? "", node.name, node.depth, node.sortOrder,
                          node.isEnabled ? 1 : 0, node.id])
            }
        }
        let all = try Db.shared.query("SELECT id FROM categories")
        for row in all {
            let id = row["id"] as? String ?? ""
            if !seen.contains(id) {
                try Db.shared.run("DELETE FROM categories WHERE id = ?", [id])
            }
        }
    }

    /// 支付方式合并：同样保留本地 icon
    private static func mergePayments(_ items: [PaymentMethodItem]) throws {
        var seen = Set<String>()
        for p in items {
            seen.insert(p.id)
            let existing = try Db.shared.query("SELECT id FROM payment_methods WHERE id = ?", [p.id])
            if existing.isEmpty {
                try Db.shared.run("""
                    INSERT OR REPLACE INTO payment_methods
                      (id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order)
                    VALUES (?, ?, ?, '', ?, ?, ?, ?)
                    """, [p.id, p.name, p.type, p.billingDay ?? 0, p.repaymentDay ?? 0,
                          p.isEnabled ? 1 : 0, p.sortOrder])
            } else {
                try Db.shared.run("""
                    UPDATE payment_methods SET name = ?, type = ?, billing_day = ?,
                           repayment_day = ?, is_enabled = ?, sort_order = ? WHERE id = ?
                    """, [p.name, p.type, p.billingDay ?? 0, p.repaymentDay ?? 0,
                          p.isEnabled ? 1 : 0, p.sortOrder, p.id])
            }
        }
        let all = try Db.shared.query("SELECT id FROM payment_methods")
        for row in all {
            let id = row["id"] as? String ?? ""
            if !seen.contains(id) {
                try Db.shared.run("DELETE FROM payment_methods WHERE id = ?", [id])
            }
        }
    }
}
