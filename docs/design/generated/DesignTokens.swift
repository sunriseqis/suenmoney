// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
// 计划三 S0 时搬进 ios/SuenMoney/UI/DesignTokens.swift，并补 Color(hex:) 扩展。
import SwiftUI

enum DesignTokens {
    // 表面
    static let surface = Color(hex: 0x141222)
    static let surfaceContainer = Color(hex: 0x1E1D2E)
    static let surfaceHigh = Color(hex: 0x282740)
    // 文字
    static let onSurface = Color(hex: 0xF2EFFA)
    static let onSurfaceVariant = Color(hex: 0xB9B5CC)
    // 描边
    static let outline = Color(hex: 0x3A3852)
    static let outlineStrong = Color(hex: 0x706D96)
    // 五色
    static let primary = Color(hex: 0xB388FF)
    static let onPrimary = Color(hex: 0x2A1065)
    static let secondary = Color(hex: 0x4DFFD2)
    static let onSecondary = Color(hex: 0x00352E)
    static let tertiary = Color(hex: 0xFF7AB8)
    static let onTertiary = Color(hex: 0x5F1606)
    static let lemon = Color(hex: 0xE5FF41)
    static let onLemon = Color(hex: 0x3F2E00)
    static let info = Color(hex: 0x5DB8FF)
    static let onInfo = Color(hex: 0x00344F)

    // 圆角 / 间距 / 动效
    static let radiusCard: CGFloat = 24
    static let radiusSheet: CGFloat = 24
    static let radiusField: CGFloat = 14
    static let radiusPill: CGFloat = 999
    static let grid: CGFloat = 8
    static let durationsFast: Double = 0.2
    static let durationsMid: Double = 0.35
    static let durationsSlow: Double = 0.4
}
