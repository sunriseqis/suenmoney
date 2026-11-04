//
//  DictPref.swift
//  SuenMoney
//
//  分类 / 支付方式的**本地个性化**（颜色、图标）。
//
//  服务端只把「名称 + 层级」当跨端契约：`color` / `icon` 是各端渲染细节
//  （Web 用 lucide + `--chart-N`，原生用 `sys.symbol.*` + 本地调色板），
//  跨端无法也不该统一。服务端已不再接受这两个字段写入。
//
//  因此本地直接改 `categories` / `payment_methods` 表的这两列 ——
//  **不发请求、不回推**。同步时 `SyncStore` / `SyncEngine` 会刻意跳过这两列
//  （见其注释），保证每次同步不会把用户挑的配色冲掉。
//

import Foundation

public enum DictPref {
    /// 改分类的颜色/图标（仅本机）
    public static func setCategoryVisual(id: String, icon: String, color: String) throws {
        try Db.shared.run("UPDATE categories SET icon = ?, color = ? WHERE id = ?",
                          [icon, color, id])
    }

    /// 改支付方式的图标（仅本机；支付方式没有 color 字段）
    public static func setPaymentVisual(id: String, icon: String) throws {
        try Db.shared.run("UPDATE payment_methods SET icon = ? WHERE id = ?", [icon, id])
    }

    /// 读分类的本地图标/颜色（编辑弹层回填用）
    public static func categoryVisual(id: String) -> (icon: String, color: String) {
        let rows = (try? Db.shared.query(
            "SELECT icon, color FROM categories WHERE id = ?", [id])) ?? []
        guard let row = rows.first else { return ("", "") }
        return (row["icon"] as? String ?? "", row["color"] as? String ?? "")
    }

    /// 读支付方式的本地图标
    public static func paymentVisual(id: String) -> String {
        let rows = (try? Db.shared.query(
            "SELECT icon FROM payment_methods WHERE id = ?", [id])) ?? []
        return rows.first?["icon"] as? String ?? ""
    }
}
