//
//  ThemeManager.swift
//  SuenMoney
//
//  主题管理（docs R129–R131，三档）。
//
//  **三档**：深色（Cyberpunk）/ 浅色（Playful Geometric）/ **跟随系统**。
//  未显式选择时实时跟随系统（R130）：系统切深色，界面跟着变。
//
//  ⚠ iOS 侧与鸿蒙的一处实现差异：鸿蒙用 `AppStorage[themeName]` 广播生效主题，
//  iOS 用 `@Observable` + `@Environment` 注入 —— 语义相同（各屏都订阅「生效主题」，
//  不存 tokens 快照，否则切主题只有设置页自己变）。
//

import SwiftUI

public enum ThemeMode: String, CaseIterable {
    case dark
    case light
    case system

    public var label: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        case .system: return "跟随系统"
        }
    }
}

/// 生效主题（两套设计语言）
public enum ThemeName: String {
    case candy
    case cyber
}

private let keyMode = "suenmoney:theme-mode"

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public private(set) var mode: ThemeMode = .dark
    /// 系统当前是否深色（`mode == .system` 时用它决定生效主题）。
    ///
    /// ⚠ 初值必须取**真实系统值**：硬编码 true 会让 `mode == .system` + 系统浅色时
    /// 首帧先渲染 cyber（#0a0a0f）再跳到 candy（#FFFDF5）——一次明显的深色闪烁。
    public var systemDark: Bool

    private init() {
        let saved = UserDefaults.standard.string(forKey: keyMode) ?? "dark"
        mode = ThemeMode(rawValue: saved) ?? .dark
        systemDark = UITraitCollection.current.userInterfaceStyle == .dark
    }

    /// 生效主题名（candy 浅色 / cyber 深色）
    public var name: ThemeName {
        switch mode {
        case .light: return .candy
        case .dark: return .cyber
        case .system: return systemDark ? .cyber : .candy
        }
    }

    public var isCyber: Bool { name == .cyber }

    public var tokens: ThemeTokens {
        name == .candy ? candyTheme : cyberTheme
    }

    /// 切换三档并持久化
    public func setMode(_ next: ThemeMode) {
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: keyMode)
    }
}
