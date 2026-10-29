//
//  SuenMoneyApp.swift
//  SuenMoney
//
//  应用入口（对应鸿蒙 `entryability/EntryAbility.ets`）。
//
//  启动顺序（错一步就会「有令牌但列表空白」或「字体没注册」）：
//    1. 打开本地库（建表 + 迁移）
//    2. 读 Keychain 里的令牌与服务器配置
//    3. 起网络监听（恢复网络时补推离线队列）
//    4. 有令牌 → 校验 /api/auth/me；无令牌 → 停在登录页
//
//  「跟随系统」档靠 `RootView` 里的 `colorScheme` 驱动（App struct 拿不到环境值）。
//

import SwiftUI

@main
struct SuenMoneyApp: App {
    @State private var theme = ThemeManager.shared
    @State private var auth = AuthStore.shared
    @State private var network = NetworkMonitor.shared

    /// 构建标记：用于在设备日志里确认装的是哪一版
    static let clientBuild = "2026-10-29.1-ios"

    init() {
        // 1) 本地库
        do {
            try Db.shared.open()
        } catch {
            // 打不开本地库不阻塞启动：线上路径仍然可用（只是没有离线缓存）
            print("[SuenMoney] 本地库打开失败：\(error)")
        }

        // 2) 令牌与服务器配置
        ServerConfig.shared.load()

        // 3) 网络监听
        NetworkMonitor.shared.start()

        print("[SuenMoney] client build \(SuenMoneyApp.clientBuild)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(theme)
                .environment(auth)
                .environment(network)
                .task {
                    if auth.isAuthenticated {
                        await auth.refreshMe()
                        _ = await SyncEngine.shared.syncNow()
                    }
                }
        }
    }
}
