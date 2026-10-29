//
//  CategoryIcon.swift
//  SuenMoney
//
//  分类图标（R134 解析链）。
//
//  ⚠ **与鸿蒙的有意差异**：鸿蒙用 `sys.symbol` 系列内置符号，iOS 用 **SF Symbols**。
//  用户口径：「存在系统图标没有的或者不一致的，一律按照 iOS 可用的操作」。
//  但**功能与视觉必须与 hw 一致** —— 所以映射原则不变：
//    **按分类名直接命中 > 通用兜底**，永不出现空徽位。
//
//  分类色仍走 `categoryColorOf(name, explicit)`（16 色槽，与 Web 对齐）——
//  只换图形，不动颜色逻辑。
//

import SwiftUI

/// 兜底符号：名字不在表里时用它（永不为空，保证徽位不出现空洞）
public let fallbackSymbol = "doc.text"

/// 分类名 → SF Symbol 名
///
/// 每个名字都是 SF Symbols 里**确定存在**的符号（不是拼出来的）。
/// 若某天 Apple 改名，`Image(systemName:)` 会渲染空图 —— 所以宁可退到
/// `circle.dashed` 这类长期稳定的符号，也不写生僻名。
private let categorySymbols: [String: String] = [
    "餐饮": "fork.knife",
    "外卖": "fork.knife",
    "下馆子": "fork.knife",
    "买菜": "cart.fill",
    "交通": "tram.fill",
    "打车": "car.fill",
    "加油": "fuelpump.fill",
    "购物": "bag.fill",
    "衣物": "tshirt.fill",
    "数码": "desktopcomputer",
    "居住": "house.fill",
    "房租": "house.fill",
    "水电": "bolt.fill",
    "医疗": "cross.case.fill",
    "药品": "pills.fill",
    "娱乐": "gamecontroller.fill",
    "游戏": "gamecontroller.fill",
    "电影": "film.fill",
    "健身": "dumbbell.fill",
    "学习": "book.fill",
    "教育": "graduationcap.fill",
    "人情": "gift.fill",
    "宠物": "pawprint.fill",
    "通讯": "phone.fill",
    "工资": "banknote.fill",
    "还款": "creditcard.fill"
]

/// 分类名 → SF Symbol；自建分类回落到兜底符号（永不为空）
public func categorySymbolOf(_ name: String) -> String {
    categorySymbols[name.trimmingCharacters(in: .whitespaces)] ?? fallbackSymbol
}

// MARK: - 分类图标视图

/// 分类徽位（鸿蒙 `CatIconView` 的 iOS 版）
public struct CatIconView: View {
    public let catName: String
    public let iconSize: CGFloat
    public let color: String

    public init(catName: String, iconSize: CGFloat = 19, color: String = "") {
        self.catName = catName
        self.iconSize = iconSize
        self.color = color
    }

    public var body: some View {
        Image(systemName: categorySymbolOf(catName))
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(color.isEmpty ? Color.primary : Color(css: color))
    }
}
