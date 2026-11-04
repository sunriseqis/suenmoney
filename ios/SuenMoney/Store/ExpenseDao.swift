//
//  ExpenseDao.swift
//  SuenMoney
//
//  流水本地库（**本地优先**的读侧）。
//
//  与鸿蒙 `ExpenseDao.ets` 同一套语义：本地是唯一显示源，服务端只负责同步。
//  网络在不在，列表/筛选/合计都走同一条代码路径，行为天然一致。
//
//  月份归属用 `spend_date`（消费日），与服务端 `/api/expenses` 的默认 `by`
//  以及 Web 的 `listQuery()`（不传 by）一致。
//  ⚠ 旧实现用 `repayment_date`，与在线列表口径不同 —— 同一个月会列出不同记录。
//

import Foundation

public struct LocalMonthTotal {
    public let totalCents: Int
    public let count: Int
}

public struct LocalCategoryTotal {
    public let categoryId: String
    public let categoryName: String
    public let cents: Int
    public let count: Int
}

public enum ExpenseDao {
    /// 批量缓存（每页拉回来就写一次，冲突替换）
    public static func cache(_ items: [ExpenseItem]) throws {
        guard !items.isEmpty else { return }
        let db = Db.shared
        for item in items {
            try db.run("""
                INSERT OR REPLACE INTO expenses
                  (id, owner_id, amount_cents, category_id, payment_method_id,
                   spend_date, posting_date, repayment_date, note, source, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
                [
                    item.id, item.ownerId, item.amountCents, item.categoryId, item.paymentMethodId,
                    item.spendDate, item.postingDate, item.repaymentDate, item.note, item.source,
                    ISO8601DateFormatter().string(from: Date())
                ])
        }
    }

    /// 某月的本地流水（按还款日归属，与报表口径一致）
    public static func byMonth(_ month: String) throws -> [ExpenseItem] {
        let rows = try Db.shared.query(
            "SELECT * FROM expenses WHERE substr(spend_date, 1, 7) = ? ORDER BY spend_date DESC, id DESC",
            [month]
        )
        return rows.map { rowToItem($0) }
    }

    /// 某月合计（离线时取代 /api/reports/monthly 的 totalCents）
    public static func monthTotal(_ month: String) throws -> LocalMonthTotal {
        let rows = try Db.shared.query(
            "SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS cnt FROM expenses WHERE substr(spend_date, 1, 7) = ?",
            [month]
        )
        guard let row = rows.first else {
            return LocalMonthTotal(totalCents: 0, count: 0)
        }
        return LocalMonthTotal(totalCents: row["total"] as? Int ?? 0, count: row["cnt"] as? Int ?? 0)
    }

    /// 某月按分类聚合（离线构成条用）
    public static func categoryTotals(_ month: String) throws -> [LocalCategoryTotal] {
        let rows = try Db.shared.query("""
            SELECT category_id AS cid,
                   COALESCE(SUM(amount_cents), 0) AS total,
                   COUNT(*) AS cnt
              FROM expenses
             WHERE substr(repayment_date, 1, 7) = ?
             GROUP BY category_id
             ORDER BY total DESC
            """,
            [month])
        return rows.map {
            LocalCategoryTotal(
                categoryId: $0["cid"] as? String ?? "",
                categoryName: "",
                cents: $0["total"] as? Int ?? 0,
                count: $0["cnt"] as? Int ?? 0
            )
        }
    }

    /// 单条删除（本地）
    public static func delete(id: String) throws {
        try Db.shared.run("DELETE FROM expenses WHERE id = ?", [id])
    }

    /// 清空（换服务端时用）
    public static func clear() throws {
        try Db.shared.run("DELETE FROM expenses")
    }

    /// 单条写入（记账后立刻可见，不必等同步）
    public static func upsert(_ item: ExpenseItem) throws {
        try Db.shared.run("""
            INSERT OR REPLACE INTO expenses
              (id, owner_id, amount_cents, category_id, payment_method_id, spend_date,
               posting_date, repayment_date, note, source, plan_id, plan_period_seq, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [item.id, item.ownerId, item.amountCents, item.categoryId, item.paymentMethodId,
                  item.spendDate, item.postingDate, item.repaymentDate, item.note, item.source,
                  item.planId ?? "", item.planPeriodSeq ?? 0,
                  ISO8601DateFormatter().string(from: Date())])
    }

    public static func remove(id: String) throws {
        try Db.shared.run("DELETE FROM expenses WHERE id = ?", [id])
    }

    public static func count() throws -> Int {
        let rows = try Db.shared.query("SELECT COUNT(*) AS c FROM expenses")
        return rows.first?["c"] as? Int ?? 0
    }

    /// 列表查询：支出 JOIN 字典与用户，一次拿全展示字段。
    ///
    /// 筛选条件全部下推到 SQL，与服务端 `/api/expenses` 同一套口径。
    public static func query(month: String,
                             cursor: String? = nil,
                             limit: Int = 100,
                             keyword: String = "",
                             categoryId: String = "",
                             paymentMethodId: String = "",
                             ownerId: String = "") throws -> ExpensePage {
        var conds: [String] = ["substr(e.spend_date, 1, 7) = ?"]
        var args: [Any?] = [month]

        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty {
            conds.append("(e.note LIKE '%' || ? || '%' OR c.name LIKE '%' || ? || '%' OR pc.name LIKE '%' || ? || '%')")
            args.append(contentsOf: [kw, kw, kw])
        }
        if !categoryId.isEmpty {
            conds.append("(e.category_id = ? OR c.parent_id = ?)")
            args.append(contentsOf: [categoryId, categoryId])
        }
        if !paymentMethodId.isEmpty {
            conds.append("e.payment_method_id = ?")
            args.append(paymentMethodId)
        }
        if !ownerId.isEmpty {
            conds.append("e.owner_id = ?")
            args.append(ownerId)
        }
        if let cur = cursor, !cur.isEmpty {
            let parts = cur.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                conds.append("(e.spend_date < ? OR (e.spend_date = ? AND e.id < ?))")
                args.append(contentsOf: [parts[0], parts[0], parts[1]])
            }
        }

        let sql = """
            SELECT e.id, e.owner_id, e.amount_cents, e.category_id, e.payment_method_id,
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
              LEFT JOIN payment_methods m ON m.id = e.payment_method_id
             WHERE \(conds.joined(separator: " AND "))
             ORDER BY e.spend_date DESC, e.id DESC
             LIMIT ?
            """
        args.append(limit + 1)

        let rows = try Db.shared.query(sql, args)
        let hasMore = rows.count > limit
        let page = hasMore ? Array(rows.prefix(limit)) : rows
        let items = page.map { rowToJoinedItem($0) }
        let next: String? = hasMore
            ? (items.last.map { "\($0.spendDate)|\($0.id)" })
            : nil
        return ExpensePage(items: items, nextCursor: next, hasMore: hasMore)
    }

    /// 带 JOIN 的行 → 展示模型
    private static func rowToJoinedItem(_ row: [String: Any]) -> ExpenseItem {
        ExpenseItem(
            id: row["id"] as? String ?? "",
            ownerId: row["owner_id"] as? String ?? "",
            ownerName: row["owner_name"] as? String ?? "",
            amountCents: row["amount_cents"] as? Int ?? 0,
            categoryId: row["category_id"] as? String ?? "",
            categoryName: row["category_name"] as? String ?? "",
            categoryIcon: row["category_icon"] as? String ?? "",
            categoryColor: row["category_color"] as? String ?? "",
            parentCategoryColor: row["parent_category_color"] as? String,
            parentCategoryName: row["parent_category_name"] as? String,
            paymentMethodId: row["payment_method_id"] as? String ?? "",
            paymentMethodName: row["payment_method_name"] as? String ?? "",
            paymentMethodType: row["payment_method_type"] as? String ?? "",
            spendDate: row["spend_date"] as? String ?? "",
            postingDate: row["posting_date"] as? String ?? "",
            repaymentDate: row["repayment_date"] as? String ?? "",
            note: row["note"] as? String ?? "",
            source: row["source"] as? String ?? "manual",
            planPeriodSeq: row["plan_period_seq"] as? Int,
            planId: (row["plan_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func rowToItem(_ row: [String: Any]) -> ExpenseItem {
        // 本地表只有 id 列没有展示字段，名字/颜色/图标由 DictionaryDao 补
        ExpenseItem(
            id: row["id"] as? String ?? "",
            ownerId: row["owner_id"] as? String ?? "",
            ownerName: "",
            amountCents: row["amount_cents"] as? Int ?? 0,
            categoryId: row["category_id"] as? String ?? "",
            categoryName: "",
            categoryIcon: "",
            categoryColor: "",
            parentCategoryColor: nil,
            parentCategoryName: nil,
            paymentMethodId: row["payment_method_id"] as? String ?? "",
            paymentMethodName: "",
            paymentMethodType: "",
            spendDate: row["spend_date"] as? String ?? "",
            postingDate: row["posting_date"] as? String ?? "",
            repaymentDate: row["repayment_date"] as? String ?? "",
            note: row["note"] as? String ?? "",
            source: row["source"] as? String ?? "manual",
            planPeriodSeq: row["plan_period_seq"] as? Int,
            planId: (row["plan_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
