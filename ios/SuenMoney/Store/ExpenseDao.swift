//
//  ExpenseDao.swift
//  SuenMoney
//
//  流水本地缓存（离线 A 档的读侧）。
//
//  原则：本地库是**服务端数据的副本**，不是第二个真相源。
//    - 线上：拉到的每一页写入本地；列表直接展示服务端返回值。
//    - 断网：从本地按还款日取数现算（合计、分类聚合都在本地做）。
//  两边口径必须一致 —— 所以月份归属统一用 repayment_date，
//  与 Web 的 `by=repayment_date` 和服务端报表同义。
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
            "SELECT * FROM expenses WHERE substr(repayment_date, 1, 7) = ? ORDER BY spend_date DESC, id DESC",
            [month]
        )
        return rows.map { rowToItem($0) }
    }

    /// 某月合计（离线时取代 /api/reports/monthly 的 totalCents）
    public static func monthTotal(_ month: String) throws -> LocalMonthTotal {
        let rows = try Db.shared.query(
            "SELECT COALESCE(SUM(amount_cents), 0) AS total, COUNT(*) AS cnt FROM expenses WHERE substr(repayment_date, 1, 7) = ?",
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
            planPeriodSeq: nil
        )
    }
}
