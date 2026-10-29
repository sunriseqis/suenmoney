//
//  DonutChart.swift
//  SuenMoney
//
//  环图（web PDonut 1:1）：stroke-dasharray 同款几何 —— r = size/2 - 12、
//  环宽 16、每段留 2.5px 的缝、12 点方向起笔；环心是「标签 + 数值」两行。
//
//  ⚠ 与鸿蒙的一处差异：鸿蒙用 `Canvas` 手绘且必须靠 `signature` 指纹触发重绘
//  （Canvas 不会自动重绘）；SwiftUI 用 `Path` + `.stroke`，状态变了自动重绘，
//  不需要指纹 —— 所以本文件没有 `signature` 参数。
//

import SwiftUI

/// 环图一段（value 为绝对金额，图内按合计归一 —— 与 web sum 口径一致）
public struct DonutSliceView: Identifiable {
    public let id: String
    public let value: Int
    public let color: String

    public init(id: String, value: Int, color: String) {
        self.id = id
        self.value = value
        self.color = color
    }
}

public struct DonutChart: View {
    public let slices: [DonutSliceView]
    public let tokens: ThemeTokens
    /// 直径（移动端报表 136，views.css:1146）
    public let ringSize: CGFloat
    /// 环心小标签（web donut-c-l）
    public let centerLabel: String
    /// 环心数值（web donut-c-v）
    public let centerValue: String
    public let isCyber: Bool

    private let lineWidth: CGFloat = 16

    public init(
        slices: [DonutSliceView],
        tokens: ThemeTokens,
        ringSize: CGFloat = 136,
        centerLabel: String = "",
        centerValue: String = "",
        isCyber: Bool = false
    ) {
        self.slices = slices
        self.tokens = tokens
        self.ringSize = ringSize
        self.centerLabel = centerLabel
        self.centerValue = centerValue
        self.isCyber = isCyber
    }

    public var body: some View {
        ZStack {
            // 底环（surface-3）：没有任何数据时也要有形状
            Circle()
                .stroke(Color(css: tokens.surface3), lineWidth: lineWidth)
                .padding(12)

            ForEach(arcs, id: \.id) { arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(Color(css: arc.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .padding(12)
                    // Circle 的 0 度在 3 点方向；Web/鸿蒙都从 12 点起笔 → 逆时针转 90°
                    .rotationEffect(.degrees(-90))
            }

            // 环心：donut-c-l（9.5 mono 大写 + 0.14em）+ donut-c-v（21 display 800）
            VStack(spacing: 2) {
                if !centerLabel.isEmpty {
                    Text(centerLabel)
                        .font(.custom(fontMonoOf(), size: 9.5))
                        .tracking(1.33)
                        .foregroundStyle(Color(css: tokens.ink3))
                        .lineLimit(1)
                }
                if !centerValue.isEmpty {
                    Text(centerValue)
                        .font(.custom(fontDisplayOf(isCyber), size: 21).weight(.bold))
                        .tracking(-0.42)
                        .foregroundStyle(Color(css: tokens.ink))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    private struct Arc {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let color: String
    }

    /// 按 stroke-dasharray 同款几何切段：每段留 2.5px 缝，12 点方向起笔
    private var arcs: [Arc] {
        let sum = slices.reduce(0) { $0 + max(0, $1.value) }
        guard sum > 0 else { return [] }

        let radius = ringSize / 2 - 12
        let circumference = 2 * Double.pi * radius
        var out: [Arc] = []
        var startPx: Double = 0

        for slice in slices {
            let len = (Double(max(0, slice.value)) / Double(sum)) * circumference
            if len <= 2.5 {
                startPx += len
                continue
            }
            // 换算成 0–1 的 trim 比例（从 12 点方向开始，Circle 默认从 3 点起 → 旋转 -90°）
            let from = startPx / circumference
            let to = (startPx + len - 2.5) / circumference
            out.append(Arc(id: slice.id, start: from, end: to, color: slice.color))
            startPx += len
        }
        return out
    }
}
