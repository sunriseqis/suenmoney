//
//  ServerRouter.swift
//  SuenMoney
//
//  多服务端选路。
//
//  语义照 Web `web/src/api/client.ts` 与鸿蒙 `ServerRouter.ets` 重写，不是重新发明：
//    1. 按用户配置的**顺序**逐个探活（同源优先 → 内网 → 备用/公网）
//    2. 每次探活 **connect 4s 失败即换下一个** —— 地址不通时快速失败，
//       否则用户要等 3 个 10s 才看到「连不上」
//    3. 选定后记住，后续请求直接用；再次失败才重新选路
//    4. 全部失败 → 进离线冷却（10s 内不再探，避免每个请求都等一圈）
//
//  为什么不用「并发探活取最快」：家用环境里备用地址通常不可达，
//  并发会让每次启动都白等最慢的那个超时；顺序 + 快失败更可预测。
//

import Foundation

public struct ProbeResult {
    public let url: String
    public let ok: Bool
    public let latencyMs: Int
    /// 失败原因（ok == false 时）
    public let reason: String
}

public enum ServerRouter {
    private static var chosen: String = ""
    private static var cooldownUntil: Date = .distantPast
    private static let probeTimeout: TimeInterval = 4
    private static let cooldown: TimeInterval = 10

    /// 当前是否处于离线冷却期
    public static var isCoolingDown: Bool {
        Date() < cooldownUntil
    }

    public static var current: String {
        chosen.isEmpty ? ServerConfig.shared.baseUrl : chosen
    }

    /// 单地址探活（登录页「测试」按钮也用它）
    public static func probe(_ url: String) async -> ProbeResult {
        let start = Date()
        guard let healthURL = URL(string: "\(url)/api/health") else {
            return ProbeResult(url: url, ok: false, latencyMs: 0, reason: "地址格式不合法")
        }
        var req = URLRequest(url: healthURL)
        req.httpMethod = "GET"
        req.timeoutInterval = probeTimeout
        // 探活不要走缓存：上一次的 200 会让「已经断了」误判成还活着
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = status == 200
            return ProbeResult(url: url, ok: ok, latencyMs: ms, reason: ok ? "" : "HTTP \(status)")
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return ProbeResult(url: url, ok: false, latencyMs: ms, reason: "连接失败")
        }
    }

    /// 按顺序选路：返回第一个可用的地址，全失败返回 ""
    /// 结果写入 ServerConfig（active），后续 ApiClient 直接用它。
    @discardableResult
    public static func choose(_ servers: [String]) async -> String {
        for url in servers {
            let result = await probe(url)
            #if DEBUG
            print("[ServerRouter] probe \(url) → \(result.ok ? "ok" : result.reason) \(result.latencyMs)ms")
            #endif
            if result.ok {
                chosen = url
                cooldownUntil = .distantPast
                ServerConfig.shared.setServers(servers, active: url)
                return url
            }
        }
        cooldownUntil = Date().addingTimeInterval(cooldown)
        return ""
    }

    /// 请求失败时调用：清掉当前选择，下次请求会重新选路
    public static func invalidate() {
        chosen = ""
        cooldownUntil = Date().addingTimeInterval(cooldown)
    }
}
