// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
import SwiftUI

enum DesignTokens {
    struct Theme { let surface: Color; let container: Color; let on: Color; let accent: Color }
    static let dark = Theme(
        surface: Color(hex: 0x0A0A0F), container: Color(hex: 0x12121A),
        on: Color(hex: 0xE0E0E0), accent: Color(hex: 0x00FF88))
    static let light = Theme(
        surface: Color(hex: 0xFFFDF5), container: Color(hex: 0xFFFFFF),
        on: Color(hex: 0x1E293B), accent: Color(hex: 0x8B5CF6))
    // 圆角
    static let radiusCardDark: CGFloat = 0
    static let radiusCardLight: CGFloat = 16
    static let grid: CGFloat = 8
}
