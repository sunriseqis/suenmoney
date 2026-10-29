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
    // ⚠ 这三个**不能**用属性初始化器（`= ThemeManager.shared`）：
    //   Swift 里属性初始化器先于 `init()` body 执行，而 `AuthStore.init` 要读
    //   Keychain 里的令牌 —— 那时 `ServerConfig.load()` 还没跑，读到的永远是空串，
    //   于是冷启动时 isAuthenticated 恒为 false，界面永远停在登录页。
    //   改成在 init 里「先 load 配置、再取单例」。
    @State private var theme: ThemeManager
    @State private var auth: AuthStore
    @State private var network: NetworkMonitor

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

        // 2) 令牌与服务器配置（必须在取 AuthStore 之前）
        ServerConfig.shared.load()

        // 3) 现在才能取单例：AuthStore.init 依赖上一步读到的令牌
        _theme = State(initialValue: ThemeManager.shared)
        _auth = State(initialValue: AuthStore.shared)
        _network = State(initialValue: NetworkMonitor.shared)

        // 4) 网络监听
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
