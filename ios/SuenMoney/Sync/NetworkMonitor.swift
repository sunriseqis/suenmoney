//
//  NetworkMonitor.swift
//  SuenMoney
//
//  网络恢复触发同步。
//
//  为什么需要它：`scenePhase` 只能覆盖「切回前台」这一种情况。
//  Wi-Fi 断掉又恢复时应用一直在前台，不会触发任何生命周期回调 ——
//  那三笔离线账会一直躺在队列里，直到用户手动点「立即同步」或切后台再回来。
//
//  所以订阅 `NWPathMonitor`：从「无网」变「有网」时补一次推送。
//

import Foundation
import Network

@Observable
@MainActor
public final class NetworkMonitor {
    public static let shared = NetworkMonitor()

    /// 当前是否联网（界面据此显示「离线」提示）
    public private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.suenmoney.network")
    private var started = false

    private init() {}

    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowOnline = path.status == .satisfied
            Task { @MainActor in
                let wasOnline = self.isOnline
                self.isOnline = nowOnline
                // 从「无网」变「有网」：补一次推送
                if nowOnline && !wasOnline {
                    _ = await SyncEngine.shared.syncNow()
                }
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        started = false
    }
}
