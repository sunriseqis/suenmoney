//
//  AppTheme.swift
//  SuenMoney
//
//  主题令牌 —— 与鸿蒙 `common/theme/AppTheme.ets` **逐字段一致**（同一份 51 令牌）。
//  源头是 `web/styles/proto/theme.css`，映射表见 `docs/design/generated/hw-theme-mapping.md`。
//
//  两套设计语言：candy（水果硬糖 / 浅色）与 cyber（赛博朋克 / 深色）。
//
//  Swift 侧用 struct + 两个静态常量，取字段走 `t.bg` 静态成员访问（与 ArkTS 同构）。
//

import SwiftUI

public struct ThemeTokens {
    public let densityPad: CGFloat
    public let densityRow: CGFloat

    public let bg: String
    public let bg2: String
    public let bg3: String
    public let surface: String
    public let surface2: String
    public let surface3: String
    public let line: String
    public let line2: String
    public let line3: String
    public let ink: String
    public let ink2: String
    public let ink3: String
    public let accent: String
    public let accentInk: String
    public let cyan: String
    public let pink: String
    public let amber: String
    public let mint: String
    public let sky: String
    public let danger: String
    public let warn: String
    public let ok: String
    public let onColor: String

    public let rCard: CGFloat
    public let rMd: CGFloat
    public let rSm: CGFloat
    public let rPill: CGFloat
    public let borderW: CGFloat

    public let fontDisplay: String
    public let fontBody: String
    public let fontMono: String

    public let shadowCard: String
    public let shadowCardPop: String
    public let shadowBtn: String
    public let shadowBtnHover: String
    public let shadowBtnActive: String
    public let shadowSoft: String

    public let navBg: String
    public let scrim: String
    public let glow: String

    public let chart1: String
    public let chart2: String
    public let chart3: String
    public let chart4: String
    public let chart5: String
    public let chart6: String
    public let chart7: String
    public let chart8: String

    public let fontScale: String
}

public let candyTheme = ThemeTokens(
    densityPad: 18,
    densityRow: 12,
    bg: "#FFFDF5",
    bg2: "#FFF8E7",
    bg3: "#F6F3FF",
    surface: "#FFFFFF",
    surface2: "#F8F7FF",
    surface3: "#F1F5F9",
    line: "#E2E8F0",
    line2: "#1E293B",
    line3: "#CBD5E1",
    ink: "#1E293B",
    ink2: "#64748B",
    ink3: "#94A3B8",
    accent: "#8B5CF6",
    accentInk: "#FFFFFF",
    cyan: "#22D3EE",
    pink: "#F472B6",
    amber: "#FBBF24",
    mint: "#34D399",
    sky: "#38BDF8",
    danger: "#EF4444",
    warn: "#F59E0B",
    ok: "#10B981",
    onColor: "#1E293B",
    rCard: 20,
    rMd: 14,
    rSm: 9,
    rPill: 999,
    borderW: 2,
    fontDisplay: "Outfit",
    fontBody: "Plus Jakarta Sans",
    fontMono: "Plus Jakarta Sans",
    shadowCard: "6px 6px 0 #E9EEF6",
    shadowCardPop: "8px 8px 0 #1E293B",
    shadowBtn: "3px 3px 0 #1E293B",
    shadowBtnHover: "5px 5px 0 #1E293B",
    shadowBtnActive: "1px 1px 0 #1E293B",
    shadowSoft: "0 10px 24px -18px rgba(30, 41, 59, 0.6)",
    navBg: "rgba(255, 253, 245, 0.9)",
    scrim: "rgba(30, 41, 59, 0.35)",
    glow: "none",
    chart1: "#8B5CF6",
    chart2: "#F472B6",
    chart3: "#FBBF24",
    chart4: "#34D399",
    chart5: "#38BDF8",
    chart6: "#A78BFA",
    chart7: "#FB7185",
    chart8: "#22D3EE",
    fontScale: "1"
)

public let cyberTheme = ThemeTokens(
    densityPad: 18,
    densityRow: 12,
    bg: "#0a0a0f",
    bg2: "#0d0d16",
    bg3: "#10101c",
    surface: "#12121a",
    surface2: "#1c1c2e",
    surface3: "#16162a",
    line: "#2a2a3a",
    line2: "#2a2a3a",
    line3: "#3b3b52",
    ink: "#e0e0e0",
    ink2: "#8f93ad",
    ink3: "#6b7280",
    accent: "#00ff88",
    accentInk: "#04220f",
    cyan: "#00d4ff",
    pink: "#ff00ff",
    amber: "#ffb020",
    mint: "#00ff88",
    sky: "#00d4ff",
    danger: "#ff3366",
    warn: "#ffb020",
    ok: "#00ff88",
    onColor: "#05050c",
    rCard: 2,
    rMd: 2,
    rSm: 2,
    rPill: 2,
    borderW: 1,
    fontDisplay: "Orbitron",
    fontBody: "JetBrains Mono",
    fontMono: "JetBrains Mono",
    shadowCard: "0 0 0 rgba(0, 0, 0, 0)",
    shadowCardPop: "0 0 0 rgba(0, 0, 0, 0)",
    shadowBtn: "none",
    shadowBtnHover: "0 0 12px rgba(0, 255, 136, 0.45)",
    shadowBtnActive: "none",
    shadowSoft: "0 0 20px -10px rgba(0, 212, 255, 0.5)",
    navBg: "rgba(8, 8, 14, 0.92)",
    scrim: "rgba(2, 2, 8, 0.78)",
    glow: "0 0 10px rgba(0, 255, 136, 0.55)",
    chart1: "#00ff88",
    chart2: "#ff00ff",
    chart3: "#00d4ff",
    chart4: "#ffb020",
    chart5: "#8b5cff",
    chart6: "#00a3ff",
    chart7: "#ff3366",
    chart8: "#7dffd0",
    fontScale: "1"
)

// MARK: - 颜色解析

extension Color {
    /// 从 `#RRGGBB` / `#RRGGBBAA` / `rgba(r,g,b,a)` 构造
    ///
    /// CSS 里的颜色值（含 `rgba(...)` 与 `transparent`）不能直接喂给 SwiftUI，
    /// 全项目统一走这个入口，避免各处自己写解析。
    public init(css: String) {
        let text = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "none" || text == "transparent" {
            self = .clear
            return
        }
        if text.hasPrefix("rgba") || text.hasPrefix("rgb") {
            self = Color(cssRGB: text)
            return
        }
        if text.hasPrefix("#") {
            self = Color(cssHex: String(text.dropFirst()))
            return
        }
        // 未知格式：退回不透明黑，至少不会崩
        self = .black
    }

    private init(cssHex hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r, g, b, a: Double
        switch hex.count {
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 3:
            // #abc → #aabbcc
            let chars = Array(hex)
            let expanded = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
            var v2: UInt64 = 0
            Scanner(string: expanded).scanHexInt64(&v2)
            r = Double((v2 >> 16) & 0xFF) / 255
            g = Double((v2 >> 8) & 0xFF) / 255
            b = Double(v2 & 0xFF) / 255
            a = 1
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private init(cssRGB text: String) {
        // rgba(30, 41, 59, 0.35) / rgb(30 41 59)
        let inner = text
            .replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: "rgb(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let parts = inner
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let r = parts.count > 0 ? parts[0] / 255 : 0
        let g = parts.count > 1 ? parts[1] / 255 : 0
        let b = parts.count > 2 ? parts[2] / 255 : 0
        let a = parts.count > 3 ? parts[3] : 1
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension ThemeTokens {
    /// 便捷：直接把令牌当 Color 用
    public func color(_ key: KeyPath<ThemeTokens, String>) -> Color {
        Color(css: self[keyPath: key])
    }
}
