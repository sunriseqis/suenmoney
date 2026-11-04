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
    /// 从本地缓存**还原分类树**（本地优先的读取源；记账抽屉 / 设置页都要它）
    ///
    /// 根节点的 `parent_id` 可能是 NULL 也可能是空串（快照写入用空串），
    /// 两种都必须当成「没有父级」，否则整棵树会被过滤成空。
    public static func categoriesTree() throws -> [CategoryNode] {
        let rows = try Db.shared.query("""
            SELECT id, parent_id, name, depth, icon, color, sort_order, is_enabled
              FROM categories ORDER BY sort_order, id
            """)
        var flat: [CategoryNode] = []
        for r in rows {
            let rawParent = r["parent_id"] as? String ?? ""
            flat.append(CategoryNode(
                id: r["id"] as? String ?? "",
                parentId: rawParent.isEmpty ? nil : rawParent,
                name: r["name"] as? String ?? "",
                depth: r["depth"] as? Int ?? 1,
                icon: r["icon"] as? String ?? "",
                color: r["color"] as? String ?? "",
                sortOrder: r["sort_order"] as? Int ?? 0,
                isEnabled: (r["is_enabled"] as? Int ?? 1) == 1,
                expenseCount: 0,
                children: []
            ))
        }
        // 补笔数：quickCats 要按笔数挑「常用分类」，全 0 会让整条分类条消失
        let counts = (try? categoryCounts()) ?? [:]
        for i in flat.indices {
            flat[i] = CategoryNode(
                id: flat[i].id, parentId: flat[i].parentId, name: flat[i].name,
                depth: flat[i].depth, icon: flat[i].icon, color: flat[i].color,
                sortOrder: flat[i].sortOrder, isEnabled: flat[i].isEnabled,
                expenseCount: counts[flat[i].id] ?? 0, children: []
            )
        }
        // 挂二级到一级
        return flat.filter { $0.parentId == nil }.map { root in
            let kids = flat.filter { $0.parentId == root.id }
            return CategoryNode(id: root.id, parentId: nil, name: root.name, depth: root.depth,
                                icon: root.icon, color: root.color, sortOrder: root.sortOrder,
                                isEnabled: root.isEnabled, expenseCount: 0, children: kids)
        }
    }

    /// 各分类的流水笔数（全历史，与服务端 `expenseCount` 同口径）。
    /// 用途：记账抽屉「常用分类」按笔数排序 —— 本地全 0 会让整条分类条滤空。
    public static func categoryCounts() throws -> [String: Int] {
        let rows = try Db.shared.query(
            "SELECT category_id, COUNT(*) AS c FROM expenses GROUP BY category_id")
        var out: [String: Int] = [:]
        for r in rows {
            if let id = r["category_id"] as? String {
                out[id] = r["c"] as? Int ?? 0
            }
        }
        return out
    }

    /// 从本地缓存还原支付方式列表（本地优先的读取源）
    public static func paymentsList() throws -> [PaymentMethodItem] {
        let rows = try Db.shared.query("""
            SELECT id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order
              FROM payment_methods ORDER BY sort_order, id
            """)
        return rows.map { r in
            let billing = r["billing_day"] as? Int ?? 0
            let repay = r["repayment_day"] as? Int ?? 0
            return PaymentMethodItem(
                // 本地表没有「本月笔数」（那是服务端按当前月份算的），设置页要显示就走接口
                monthExpenseCount: nil,
                id: r["id"] as? String ?? "",
                name: r["name"] as? String ?? "",
                type: r["type"] as? String ?? "cash",
                icon: r["icon"] as? String ?? "",
                billingDay: billing > 0 ? billing : nil,
                repaymentDay: repay > 0 ? repay : nil,
                isEnabled: (r["is_enabled"] as? Int ?? 1) == 1,
                sortOrder: r["sort_order"] as? Int ?? 0,
                expenseCount: 0
            )
        }
    }

    /// 记录人列表（本地 users 表；流水筛选与归属显示用）
    public static func owners() throws -> [CachedCategory] {
        let rows = try Db.shared.query(
            "SELECT id, display_name FROM users ORDER BY display_name, id")
        return rows.map {
            CachedCategory(id: $0["id"] as? String ?? "",
                           name: $0["display_name"] as? String ?? "",
                           icon: "", color: "", parentId: "")
        }
    }

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
