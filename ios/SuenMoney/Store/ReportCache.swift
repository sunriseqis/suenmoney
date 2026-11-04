//
//  ReportCache.swift
//  SuenMoney
//
//  报表响应缓存（与鸿蒙 `ReportCache.ets` 同构）。
//
//  ## 为什么缓存而不是本地重算
//
//  报表逻辑在服务端（月报/汇总/年报合计 800+ 行 SQL：分类桶、环比、去年同期、
//  维度排行…）。在客户端重写一份，两套实现必然随时间跑偏 —— 而「三端数字一致」
//  是硬要求。所以口径仍由服务端唯一提供，本地只**缓存它最后一次的响应**。
//
//  离线时展示缓存；`reportWithCache` 采用 stale-while-revalidate：
//  缓存缺失或超过 TTL 就后台问一次，失败保留旧值。
//
//  存储：`meta` 表，键 `report:<key>`，值是 JSON。不值得为缓存单独建表。
//

import Foundation

public struct CachedReport<T: Decodable>: Decodable {
    public let data: T
    public let fetchedAt: String
}

public enum ReportCache {
    /// 缓存有效期
    private static let ttl: TimeInterval = 5 * 60

    /// 读缓存（没有就返回 nil）
    public static func get<T: Decodable>(_ key: String, as type: T.Type) -> CachedReport<T>? {
        let rows = (try? Db.shared.query("SELECT value FROM meta WHERE key = ?",
                                         ["report:\(key)"])) ?? []
        guard let raw = rows.first?["value"] as? String, !raw.isEmpty,
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(CachedReport<T>.self, from: data)
    }

    /// 写缓存（拿服务端新响应时调）
    public static func put<T: Encodable>(_ key: String, _ value: T) {
        let wrapped = Wrap(data: value,
                           fetchedAt: ISO8601DateFormatter().string(from: Date()))
        guard let data = try? JSONEncoder().encode(wrapped),
              let text = String(data: data, encoding: .utf8)
        else { return }
        try? Db.shared.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
                           ["report:\(key)", text])
    }

    /// 缓存是否过期（无缓存也算过期）
    public static func isStale(_ fetchedAt: String) -> Bool {
        let fmt = ISO8601DateFormatter()
        guard let then = fmt.date(from: fetchedAt) else { return true }
        return Date().timeIntervalSince(then) > ttl
    }

    private struct Wrap<T: Encodable>: Encodable {
        let data: T
        let fetchedAt: String
    }
}

/// 报表取数：**先用缓存，再后台刷新**。
///
/// `fetch` 拿服务端新值；成功就写缓存并回调 `onFresh`。
/// 缓存为空且请求失败时返回 nil（调用方显示空态），不抛错打断页面。
public func reportWithCache<T: Decodable & Encodable>(
    key: String,
    fetch: () async throws -> T,
    onFresh: @escaping (T) -> Void
) async -> T? {
    let cached = ReportCache.get(key, as: T.self)
    if cached == nil || ReportCache.isStale(cached!.fetchedAt) {
        if let fresh = try? await fetch() {
            ReportCache.put(key, fresh)
            onFresh(fresh)
            return fresh
        }
    }
    return cached?.data
}
