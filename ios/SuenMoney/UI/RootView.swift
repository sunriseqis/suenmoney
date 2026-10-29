//
//  RootView.swift
//  SuenMoney
//
//  移动外壳 —— 照 Web 移动端现状（App.vue ≤860px + views.css:1112 覆盖段）1:1 复刻。
//  对应鸿蒙 `pages/MainPage.ets`。
//
//  结构（自上而下）：
//    无品牌条 / 无顶栏（用户裁决 U01/U02：logo、标题、主题切换、记一笔、返回键全部去掉）
//    content  padding 6/12/12（views.css:1121 的 64 是浏览器滚动留白，原生端照抄会压掉一行）
//    二级页的返回改由**系统返回手势**承担
//
//  ⚠ iOS 与鸿蒙的差异：鸿蒙没有原生返回手势回调，靠 `onBackPress()`；
//  iOS 用 `NavigationStack` 的默认边缘返回 + 自定义返回目标（见 `AppState.goBack()`）。
//

import SwiftUI

/// 屏标识（顺序无关，仅作路由键）
public enum ScreenKey: String {
    case ledger
    case dashboard
    case report
    case annual
    case settings
}

@Observable
@MainActor
public final class AppState {
    public var screen: ScreenKey = .ledger
    /// 跨屏下钻带的月份（概况热力格 / 年度报告月柱 → 报表）
    public var pickMonth: String = ""
    /// 跨屏「记一笔」请求（先切回流水屏，再由流水屏打开抽屉）
    public var createRequest: Int = 0

    public init() {}

    /// 系统返回（对应鸿蒙 `onBackPress`）
    /// - 年度报告是报表的子页 → 回到报表
    /// - 其余二级页 → 回到流水
    /// - 流水页是主页 → 交给系统退出到桌面
    public func goBack() -> Bool {
        switch screen {
        case .annual:
            screen = .report
            return true
        case .dashboard, .report, .settings:
            screen = .ledger
            return true
        case .ledger:
            return false
        }
    }

    /// 从其它屏触发「记一笔」：先回流水屏，再投递请求
    public func requestCreate() {
        screen = .ledger
        // 等一帧，让流水屏先挂载（鸿蒙端用 120ms 延迟解决同一问题）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.createRequest += 1
        }
    }
}

public struct RootView: View {
    @State private var app = AppState()
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthStore.self) private var auth

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        Group {
            if auth.isAuthenticated {
                content
            } else {
                LoginView()
            }
        }
        .environment(app)
        .background(Color(css: tokens.bg))
        // 跟随系统档：系统切深色，界面立刻跟着变（R130）
        .onAppear { theme.systemDark = colorScheme == .dark }
        .onChange(of: colorScheme) { _, next in theme.systemDark = next == .dark }
    }

    private var content: some View {
        VStack(spacing: 12) {
            screenBody
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        // 顶部不再补状态栏高度：SwiftUI 的 safeArea 已含状态栏；
        // 底部只让背景铺到物理边缘（本应用没有底部 tab）
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(css: tokens.bg).ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private var screenBody: some View {
        switch app.screen {
        case .ledger:
            LedgerScreen()
        case .dashboard:
            DashboardScreen()
        case .report:
            ReportScreen()
        case .annual:
            AnnualScreen()
        case .settings:
            SettingsScreen()
        }
    }
}
