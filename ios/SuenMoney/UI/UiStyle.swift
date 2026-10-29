//
//  UiStyle.swift
//  SuenMoney
//
//  把原型 CSS（web/styles/proto/*.css）里的样式值翻译成 SwiftUI 可用的参数。
//  与鸿蒙 `common/ui/UiStyle.ets` 逐函数对应。
//
//  为什么要有这一层：原型里 `--shadow-card: 6px 6px 0 #E9EEF6` 这种 CSS 简写
//  在 SwiftUI 里对应 `.shadow(color:radius:x:y:)`，没有等价简写；
//  每个屏各写一遍就会各处走形。**所有视觉数值都以原型为准**，不自己发明。
//

import SwiftUI

public struct ParsedShadow {
    public let radius: CGFloat
    public let offsetX: CGFloat
    public let offsetY: CGFloat
    public let color: String
}

/// 解析 CSS box-shadow 简写（只支持原型里出现的形式）：
///   `"6px 6px 0 #E9EEF6"`   → 硬阴影（radius = 0）
///   `"0 10px 24px -18px rgba(...)"` → 软阴影
public func parseShadow(_ css: String) -> ParsedShadow {
    if css == "none" {
        return ParsedShadow(radius: 0, offsetX: 0, offsetY: 0, color: "transparent")
    }
    // 按空白切，但括号内的空格不切（rgba(30, 41, 59, 0.6) 里有空格）
    var parts: [String] = []
    var current = ""
    var depth = 0
    for ch in css {
        if ch == "(" { depth += 1 }
        if ch == ")" { depth -= 1 }
        if ch.isWhitespace && depth == 0 {
            if !current.isEmpty { parts.append(current); current = "" }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { parts.append(current) }

    var nums: [CGFloat] = []
    var color = "#000000"
    for p in parts {
        if p.hasPrefix("#") || p.hasPrefix("rgb") {
            color = p
        } else if p.hasSuffix("px") {
            nums.append(CGFloat(Double(p.replacingOccurrences(of: "px", with: "")) ?? 0))
        } else if let v = Double(p) {
            nums.append(CGFloat(v))
        }
    }
    // 原型里没有 inset，顺序固定为 X Y [blur] [spread]
    return ParsedShadow(
        radius: nums.count > 2 ? nums[2] : 0,
        offsetX: nums.count > 0 ? nums[0] : 0,
        offsetY: nums.count > 1 ? nums[1] : 1,
        color: color
    )
}

/// 卡片阴影。
///
/// **移动端不是桌面那套**：`app.css:759` 的移动 `.card` 规则（单类、位置更后）
/// 把 `--shadow-card`(6px) 覆盖成 `3px 3px 0 #E9EEF6`，连 `.card--pop` 也一起覆盖。
public func cardShadow(_ tokens: ThemeTokens, _ isCyber: Bool, mobile: Bool = true) -> ParsedShadow {
    if isCyber {
        return parseShadow("0px 0px 0px rgba(0, 212, 255, 0.04)")
    }
    return parseShadow(mobile ? "3px 3px 0 #E9EEF6" : tokens.shadowCard)
}

/// 图标描边：cyber 1.6 / candy 2.4（原型 `.ic` 与主题覆盖）
public func strokeWidthOf(_ isCyber: Bool) -> CGFloat {
    isCyber ? 1.6 : 2.4
}

/// cyber 的切角（原型 `clip-path: polygon(0 7px, 7px 0, 100% 0, ...)`）
public let cyberCut: CGFloat = 7

/// 圆角：cyber 一律 0（原型用 clip-path 切角），candy 用 token
public func radiusOf(_ tokens: ThemeTokens, _ isCyber: Bool, _ candyValue: CGFloat) -> CGFloat {
    isCyber ? 0 : candyValue
}

/// 字体族
///
/// iOS 上 `Outfit` / `Plus Jakarta Sans` / `JetBrains Mono` **不是系统字体**，
/// 需要随包附带字体文件才能用；未附带时退回系统字体（观感差异可接受，
/// 且 `.custom` 找不到字体时会自动 fallback，不会崩）。
public func fontDisplayOf(_ isCyber: Bool) -> String {
    isCyber ? "Orbitron" : "Outfit"
}

public func fontBodyOf(_ isCyber: Bool) -> String {
    isCyber ? "JetBrainsMono" : "PlusJakartaSans"
}

public func fontMonoOf() -> String {
    "JetBrainsMono"
}

/// hex 混色（替代 CSS `color-mix()`）
///
/// 用法与原型一致：`mixHex(色, 底, 0.12)` 等价 `color-mix(色 12%, 透明底)`，
/// 用于分类图标底色（12%）与描边（45%）。
public func mixHex(_ hex: String, _ base: String, _ ratio: Double) -> String {
    let a = toRGB(hex)
    let b = toRGB(base)
    let r = Int((a.0 * ratio + b.0 * (1 - ratio)).rounded())
    let g = Int((a.1 * ratio + b.1 * (1 - ratio)).rounded())
    let bl = Int((a.2 * ratio + b.2 * (1 - ratio)).rounded())
    return String(format: "#%02x%02x%02x", r, g, bl)
}

private func toRGB(_ hex: String) -> (Double, Double, Double) {
    var text = hex
    if text.hasPrefix("#") { text = String(text.dropFirst()) }
    if text.count == 3 {
        let c = Array(text)
        text = "\(c[0])\(c[0])\(c[1])\(c[1])\(c[2])\(c[2])"
    }
    var value: UInt64 = 0
    Scanner(string: text).scanHexInt64(&value)
    return (
        Double((value >> 16) & 0xFF),
        Double((value >> 8) & 0xFF),
        Double(value & 0xFF)
    )
}

extension View {
    /// 顶卡质感（原型 `.card--pop` 的移动端覆盖）：
    ///   candy → 深色硬阴影 `4px 4px 0 line2`（比普通卡片的 3px 淡紫明显得多）
    ///   cyber → 绿色发光 `radius 16 rgba(0,255,136,0.35)` + 顶部半透明绿渐变 + 绿描边
    ///
    /// 这是「一眼能看出是不是同一个设计」的地方：普通卡片用 `card()`，
    /// 顶卡必须用它自己的这套，否则 cyber 下完全没有科技感、candy 下缺一记重阴影。
    public func heroCard(_ tokens: ThemeTokens, _ isCyber: Bool, radius: CGFloat = 20) -> some View {
        let r = radiusOf(tokens, isCyber, radius)
        let shape = RoundedRectangle(cornerRadius: r)
        return self
            .background(
                ZStack {
                    shape.fill(Color(css: tokens.surface))
                    if isCyber {
                        // angle 180：#0F00FF88 (0%) → surface (62%)
                        shape.fill(
                            LinearGradient(
                                colors: [Color(css: "#0F00FF88"), Color(css: tokens.surface)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
            )
            .overlay(
                shape.stroke(
                    Color(css: isCyber ? "rgba(0,255,136,0.45)" : tokens.line2),
                    lineWidth: isCyber ? 1 : 2
                )
            )
            .background {
                if isCyber {
                    // 发光是模糊的，用 .shadow 才对
                    EmptyView()
                } else {
                    // candy：4px 硬阴影（深色），同样用实心偏移画
                    shape.fill(Color(css: tokens.line2)).offset(x: 4, y: 4)
                }
            }
            .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.35)") : .clear,
                    radius: isCyber ? 16 : 0, x: 0, y: 0)
    }
}

// MARK: - 动效

/// 原型统一动效曲线 `cubic-bezier(.2, 0, 0, 1)` —— 起步快、收尾稳，
/// 与 Web/鸿蒙的 `transition-timing-function` 同一根曲线。
public let appCurve = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.28)
/// 短动作（点击反馈、指示器）
public let appCurveFast = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.18)
/// 抽屉/浮层
public let appCurveSheet = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.32)

// MARK: - 统一卡片修饰符

extension View {
    /// 卡片质感（原型 `.card`）：底色 + 圆角/直角 + 描边 + **阴影**。
    ///
    /// 阴影是最容易被漏掉的一环：鸿蒙端有 36 处 `.shadow(cardShadow(...))`，
    /// 而 iOS 侧最初只有 1 处 —— 于是 candy 主题的「贴纸硬阴影」完全消失，
    /// 整屏看起来就是「只有颜色对、质感不对」。
    ///
    /// SwiftUI 的 `.shadow(radius: 0)` 等价 CSS 的 `box-shadow: Xpx Ypx 0`（实心、无模糊），
    /// 所以直接透传 parseShadow 的结果即可。
    public func card(_ tokens: ThemeTokens, _ isCyber: Bool,
                     radius: CGFloat = 16,
                     surface: String? = nil,
                     border: String? = nil,
                     shadow: Bool = true) -> some View {
        let r = radiusOf(tokens, isCyber, radius)
        let shape = RoundedRectangle(cornerRadius: r)
        let sh = cardShadow(tokens, isCyber)
        let hasHardShadow = shadow && (sh.offsetX != 0 || sh.offsetY != 0) && sh.color != "transparent"

        return self
            .background(shape.fill(Color(css: surface ?? tokens.surface)))
            .overlay(shape.stroke(Color(css: border ?? tokens.line), lineWidth: tokens.borderW))
            // 硬阴影必须用「层叠的实心图形 + 偏移」来画。
            // SwiftUI 的 .shadow(radius: 0) 仍然会做抗锯齿，看起来是柔光；
            // 而原型是 CSS `box-shadow: 3px 3px 0 #E9EEF6` —— 边缘锋利、完全不模糊。
            .background {
                if hasHardShadow {
                    shape.fill(Color(css: sh.color))
                        .offset(x: sh.offsetX, y: sh.offsetY)
                }
            }
    }
}

// MARK: - 常用修饰符

extension View {
    /// 卡片：底色 + 圆角/切角 + 描边 + 阴影（原型 `.card`）
    public func cardStyle(_ tokens: ThemeTokens, _ isCyber: Bool, radius: CGFloat? = nil) -> some View {
        let r = radius ?? radiusOf(tokens, isCyber, tokens.rCard)
        let sh = cardShadow(tokens, isCyber)
        return self
            .background(Color(css: tokens.surface))
            .clipShape(isCyber ? AnyShape(CyberCutShape(cut: cyberCut)) : AnyShape(RoundedRectangle(cornerRadius: r)))
            .overlay(
                (isCyber ? AnyShape(CyberCutShape(cut: cyberCut)) : AnyShape(RoundedRectangle(cornerRadius: r)))
                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
            )
            .shadow(
                color: Color(css: sh.color),
                radius: sh.radius / 2,
                x: sh.offsetX,
                y: sh.offsetY
            )
    }

    /// 主题背景色（含 cyber 的细网格纹理由调用方另加）
    public func themeBackground(_ tokens: ThemeTokens) -> some View {
        self.background(Color(css: tokens.bg).ignoresSafeArea())
    }
}

/// cyber 的六边形切角（左上 + 右下各切一刀）
public struct CyberCutShape: Shape {
    public let cut: CGFloat

    public init(cut: CGFloat = cyberCut) {
        self.cut = cut
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: cut))
        p.addLine(to: CGPoint(x: cut, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        p.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
