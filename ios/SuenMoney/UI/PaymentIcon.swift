//
//  PaymentIcon.swift
//  SuenMoney
//
//  支付方式图标（与 Web `payment-icons.ts`、鸿蒙 `PaymentIcon.ets` 同构）。
//
//  渲染方案：
//  - 品牌图形（支付宝 / 微信 / 云闪付 / 京东 / 抖音）：系统符号里没有品牌 logo，
//    改用随包 **SVG**（Asset Catalog 里 `pay_*.imageset`，1024 坐标系矢量，
//    已设 `preserves-vector-representation` + `template-rendering-intent`），
//    任意尺寸清晰，运行时用 `foregroundStyle` 染品牌色。
//  - 其余（银行卡 / 信用卡 / 现金 / 银行转账 / 其它钱包）：**SF Symbols**。
//  - 解析优先级不变：**显式 icon > 按支付方式名反推 > 兜底银行卡**。
//
//  注意：品牌色是**品牌识别色**（支付宝蓝、微信绿…），跟主题的 accent 无关，
//  也不是语义色 —— 所以这里是一张固定的色表，不参与语义配色。
//

import SwiftUI

public enum PayIconId: String, CaseIterable {
    case alipay, wechat, unionpay, jd, douyin
    case card, creditcard, cash, bank, wallet
}

public struct PayOption {
    public let id: PayIconId
    public let label: String
    public let color: String
    /// true = 品牌 SVG（`Image` 渲染）；false = SF Symbol
    public let svg: Bool
    /// svg == true → Asset 名；svg == false → SF Symbol 名
    public let res: String
}

/// 与 Web `PAYMENT_ICON_OPTIONS` 一一对应
public let payOptions: [PayOption] = [
    PayOption(id: .alipay, label: "支付宝", color: "#1677FF", svg: true, res: "pay_alipay"),
    PayOption(id: .wechat, label: "微信支付", color: "#07C160", svg: true, res: "pay_wechat"),
    PayOption(id: .unionpay, label: "云闪付/银联", color: "#D83B01", svg: true, res: "pay_unionpay"),
    PayOption(id: .jd, label: "京东支付", color: "#E1251B", svg: true, res: "pay_jd"),
    PayOption(id: .douyin, label: "抖音支付", color: "#111827", svg: true, res: "pay_douyin"),
    PayOption(id: .card, label: "银行卡", color: "#4F46E5", svg: false, res: "creditcard"),
    PayOption(id: .creditcard, label: "信用卡", color: "#F59E0B", svg: false, res: "creditcard.fill"),
    PayOption(id: .cash, label: "现金", color: "#10B981", svg: false, res: "banknote.fill"),
    PayOption(id: .bank, label: "银行转账", color: "#2563EB", svg: false, res: "building.columns.fill"),
    PayOption(id: .wallet, label: "其它钱包", color: "#6B7280", svg: false, res: "wallet.pass.fill")
]

public struct PayVisual {
    public let id: PayIconId
    public let color: String
    public let svg: Bool
    public let res: String
}

private func optionOf(_ id: PayIconId) -> PayOption {
    payOptions.first { $0.id == id } ?? payOptions[5]
}

private func visualOf(_ id: PayIconId) -> PayVisual {
    let opt = optionOf(id)
    return PayVisual(id: opt.id, color: opt.color, svg: opt.svg, res: opt.res)
}

private func has(_ hay: String, _ needle: String) -> Bool {
    hay.contains(needle)
}

/// 支付方式名/显式 icon → 图标 + 品牌色（复刻 Web `resolvePaymentIcon` 的判定顺序）
public func resolvePayVisual(name: String, explicitIcon: String) -> PayVisual {
    let explicit = explicitIcon.trimmingCharacters(in: .whitespaces).lowercased()
    if !explicit.isEmpty {
        if let hit = payOptions.first(where: { $0.id.rawValue == explicit }) {
            return visualOf(hit.id)
        }
    }
    let n = name.lowercased()
    if has(n, "支付宝") || has(n, "花呗") || has(n, "alipay") { return visualOf(.alipay) }
    if has(n, "微信") || has(n, "财付通") || has(n, "wechat") || has(n, "wx") { return visualOf(.wechat) }
    if has(n, "银联") || has(n, "云闪付") || has(n, "unionpay") { return visualOf(.unionpay) }
    if has(n, "京东") || has(n, "白条") || has(n, "jd") { return visualOf(.jd) }
    if has(n, "抖音") || has(n, "douyin") { return visualOf(.douyin) }
    if has(n, "现金") || has(n, "cash") { return visualOf(.cash) }
    if has(n, "信用卡") || has(n, "贷记卡") || has(n, "credit") { return visualOf(.creditcard) }
    if has(n, "储蓄卡") || has(n, "借记卡") || has(n, "银行卡") || has(n, "卡") { return visualOf(.card) }
    if has(n, "银行") || has(n, "转账") || has(n, "汇款") { return visualOf(.bank) }
    return visualOf(.card)
}

// MARK: - 支付图标视图

/// 支付徽位（鸿蒙 `PayIconView` 的 iOS 版）
public struct PayIconView: View {
    public let name: String
    public let icon: String
    public let iconSize: CGFloat
    /// 是否用品牌色；false 时用 `foreground`（列表里通常用品牌色）
    public let tinted: Bool
    /// 显式前景色（选中态传 `accentInk`）。nil 时回落 `.primary`
    public let foreground: Color?

    public init(name: String, icon: String = "", iconSize: CGFloat = 18,
                tinted: Bool = true, foreground: Color? = nil) {
        self.name = name
        self.icon = icon
        self.iconSize = iconSize
        self.tinted = tinted
        self.foreground = foreground
    }

    private var visual: PayVisual { resolvePayVisual(name: name, explicitIcon: icon) }

    public var body: some View {
        Group {
            if visual.svg {
                // Asset Catalog 里已设 template-rendering-intent，直接 foregroundStyle 染色
                Image(visual.res)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: visual.res)
                    .font(.system(size: iconSize, weight: .medium))
            }
        }
        .foregroundStyle(tinted ? Color(css: visual.color) : (foreground ?? Color.primary))
    }
}
