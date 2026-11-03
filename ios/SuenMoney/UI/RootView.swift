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
    /// 跨屏带的年份（报表 → 年度报告）。鸿蒙用 `AppStorage('annualYear')`，
    /// 不传的话年报屏永远打开「当前年」，锚定 2025 时看到的是 2026 的报告。
    public var annualYear: String = ""
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
        // 状态栏文字色跟随主题：不设的话 candy（#FFFDF5 底）+ 系统深色时
        // 系统给白字，时间/电量对比度 ≈1.02:1，等于看不见。
        .preferredColorScheme(theme.isCyber ? .dark : .light)
        // 全局强调色：不设的话弹层按钮 / Menu 项 / 分段 Picker 全部是
        // iOS 系统蓝 #007AFF、系统红 #FF3B30，与 candy 紫 / cyber 绿完全脱节。
        .tint(Color(css: tokens.accent))
        // 系统返回：鸿蒙靠 onBackPress()，iOS 没有 NavigationStack 时
        // 必须自己接一个「左边缘右滑」——否则进二级页后没有任何返回途径。
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { v in
                    guard v.startLocation.x < 40, v.translation.width > 80 else { return }
                    withAnimation(appCurve) { _ = app.goBack() }
                }
        )
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
        // 本应用没有底部 tab，内容要能到**物理底边**（鸿蒙 `expandSafeArea(BOTTOM)`）。
        // 不展开的话底部会多出 34pt（Face ID 机型）空白，列表少显示一行。
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 背景铺到**上下物理边缘**（鸿蒙 setWindowSystemBarProperties 的等价物）：
        // 只铺 bottom 会在顶部露出一条系统窗口色带（#FFFFFF / #000000），
        // 与主题底 #FFFDF5 / #0a0a0f 明显不同 —— 鸿蒙注释里叫「像被切了一刀」。
        .background(Color(css: tokens.bg).ignoresSafeArea())
    }

    @ViewBuilder
    private var screenBody: some View {
        // 切屏过渡：Web 侧是路由切换 + 淡入，这里用「淡入 + 轻微位移」对齐观感
        Group {
            screenContent
        }
        // 过渡方向要跟着「前进 / 返回」变：返回时也从右侧滑入，语义是反的。
        // 用 opacity 为主 + 轻微位移，前后进退都能接受（鸿蒙端本来就是 0ms 瞬切，
        // 这里保留一点淡入是为了不显得生硬）。
        .transition(.opacity)
        .animation(appCurveFast, value: app.screen)
    }

    @ViewBuilder
    private var screenContent: some View {
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
