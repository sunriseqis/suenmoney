//
//  BrandMark.swift
//  SuenMoney
//
//  品牌徽标（docs R139）：**机身 + 显示屏（有内容、带指示灯） + 4×5 键盘**，三者缺一不可；
//  亮起的键位拼出 `S`。三形态：≥32px 完整版 / <32px 简化版。
//
//  ⚠ 与鸿蒙的一处差异：鸿蒙用 `Grid` + `layoutWeight` 铺 4×5 键盘（且 Grid 必须定高，
//  否则撑满父容器）；SwiftUI 用 `LazyVGrid` + `aspectRatio`，没有那个坑。
//

import SwiftUI

/// 4×5 键盘里需要点亮的位置（拼出 S）
private let litKeys: Set<Int> = [0, 1, 2, 5, 8, 9, 10, 13, 16, 17, 18]
private let keyCount = 20

public struct BrandMark: View {
    public let markSize: CGFloat
    @Environment(ThemeManager.self) private var theme

    public init(_ markSize: CGFloat = 46) {
        self.markSize = markSize
    }

    private var tokens: ThemeTokens { theme.tokens }

    public var body: some View {
        if markSize < 32 {
            simplified
        } else {
            full
        }
    }

    /// 简化版（<32px）：只保留机身与显示屏，键位改为一条亮线
    private var simplified: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(css: tokens.accent))
                .frame(width: markSize * 0.86, height: markSize * 0.22)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(css: tokens.accentInk))
                .frame(width: markSize * 0.56, height: markSize * 0.10)
        }
        .frame(width: markSize, height: markSize)
        .background(Color(css: tokens.ink))
        .clipShape(RoundedRectangle(cornerRadius: markSize * 0.22))
    }

    /// 完整版：显示屏 + 4×5 键盘
    private var full: some View {
        VStack(spacing: markSize * 0.06) {
            // 显示屏：带指示灯 + 内容
            HStack(spacing: markSize * 0.06) {
                Circle()
                    .fill(Color(css: tokens.accent))
                    .frame(width: markSize * 0.08, height: markSize * 0.08)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(css: tokens.accent))
                    .frame(width: markSize * 0.34, height: markSize * 0.07)
                Spacer(minLength: 0)
            }
            .padding(.leading, markSize * 0.06)
            .frame(width: markSize * 0.84, height: markSize * 0.24)
            .background(Color(css: tokens.accentInk))
            .clipShape(RoundedRectangle(cornerRadius: markSize * 0.06))

            // 4×5 键盘：亮键拼 S
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1.5), count: 4),
                spacing: 1.5
            ) {
                ForEach(0..<keyCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(css: litKeys.contains(i) ? tokens.accent : tokens.ink3))
                        .aspectRatio(1, contentMode: .fill)
                }
            }
            .frame(width: markSize * 0.84)
        }
        .padding(markSize * 0.07)
        .frame(width: markSize, height: markSize)
        .background(Color(css: tokens.ink))
        .clipShape(RoundedRectangle(cornerRadius: markSize * 0.22))
    }
}
