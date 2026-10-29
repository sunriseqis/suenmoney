//
//  DictionaryDao.swift
//  SuenMoney
//
//  字典缓存（分类 / 支付方式）。
//
//  为什么必须缓存：离线时流水行要显示「分类名 + 分类色 + 支付方式名」，
//  而这些都不在 expenses 表里（表里只有 id）。不缓存字典，断网后整列表会变成一堆空名字。
//
//  颜色规则与 Web 一致：**显式 color 优先，没设过才按 id 哈希**。
//  二级分类的颜色跟一级走 —— 所以写入时二级存父级的 color（服务端已归一化）。
//

import Foundation

public struct CachedCategory {
    public let id: String
    public let name: String
    public let icon: String
    public let color: String
    public let parentId: String
}

public enum DictionaryDao {
    public static func cacheCategories(_ categories: [CategoryNode]) throws {
        for root in categories {
            try putCategory(root, colorOverride: "")
            for child in root.children {
                // 二级的颜色跟一级走：服务端已把父色给到 child.color；空则用父的
                let childColor = child.color.isEmpty ? root.color : child.color
                try putCategory(child, colorOverride: childColor)
            }
        }
    }

    public static func cachePayments(_ payments: [PaymentMethodItem]) throws {
        let db = Db.shared
        for p in payments {
            try db.run("""
                INSERT OR REPLACE INTO payment_methods
                  (id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [
                    p.id, p.name, p.type, p.icon,
                    p.billingDay ?? 0, p.repaymentDay ?? 0,
                    p.isEnabled ? 1 : 0, p.sortOrder
                ])
        }
    }

    /// 分类名映射（离线行显示用）
    public static func categoryNames() throws -> [String: CachedCategory] {
        let rows = try Db.shared.query("SELECT id, name, icon, color, parent_id FROM categories")
        var out: [String: CachedCategory] = [:]
        for row in rows {
            let id = row["id"] as? String ?? ""
            out[id] = CachedCategory(
                id: id,
                name: row["name"] as? String ?? "",
                icon: row["icon"] as? String ?? "",
                color: row["color"] as? String ?? "",
                parentId: row["parent_id"] as? String ?? ""
            )
        }
        return out
    }

    /// 支付方式名映射
    public static func paymentNames() throws -> [String: String] {
        let rows = try Db.shared.query("SELECT id, name FROM payment_methods")
        var out: [String: String] = [:]
        for row in rows {
            out[row["id"] as? String ?? ""] = row["name"] as? String ?? ""
        }
        return out
    }

    private static func putCategory(_ cat: CategoryNode, colorOverride: String) throws {
        let color = colorOverride.isEmpty ? cat.color : colorOverride
        try Db.shared.run("""
            INSERT OR REPLACE INTO categories
              (id, parent_id, name, depth, icon, color, sort_order, is_enabled)
            VALUES (?,?,?,?,?,?,?,?)
            """,
            [
                cat.id, cat.parentId ?? "", cat.name, cat.depth,
                cat.icon, color, cat.sortOrder, cat.isEnabled ? 1 : 0
            ])
    }
}
