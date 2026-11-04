//
//  AuthStore.swift
//  SuenMoney
//
//  登录态。
//
//  令牌存 Keychain（ServerConfig 负责读写），这里只管「登录 / 登出 / 是否已登录」。
//  不缓存用户资料：资料随 /api/auth/me 取 —— 缓存了会在改显示名后仍显示旧名字。
//

import Foundation

/// 登录态。
///
/// ⚠ 必须 `@MainActor`：`login` / `refreshMe` 是 async，里面会写 `current`。
/// 不加的话它们在**非隔离上下文**执行，改的却是被 SwiftUI 观察的状态 ——
/// Swift 6 严格并发会直接报错，宽松模式下则是「偶发的界面不刷新」。
@Observable
@MainActor
public final class AuthStore {
    public static let shared = AuthStore()

    public private(set) var current: UserSummary?

    /// 登录态**必须是 @Observable 的存储属性**。
    ///
    /// 原来写成 computed `!ServerConfig.shared.authToken.isEmpty` 是个隐蔽的坑：
    /// `@Observable` 只追踪**自己**的存储属性，读另一个非 Observable 对象的字段
    /// 不会建立依赖 —— 于是 `login()` 成功、token 也存进 Keychain 了，
    /// 但 `RootView` 里 `if auth.isAuthenticated` 永远求值成 false，界面卡在登录页。
    /// （服务端日志显示登录成功、界面却不动，就是这个原因。）
    public private(set) var isAuthenticated: Bool

    /// 会话是否已失效（服务端不认这个令牌了）。
    ///
    /// ⚠ 失效**不等于**要把人踢去登录页 —— 记账软件的核心数据在本地，
    ///   令牌失效只意味着「暂时不能同步」。真正回登录页只有两种：
    ///   用户主动登出，或本地从来没登录过。
    public var sessionExpired: Bool = false

    private init() {
        // 冷启动：Keychain 里已有令牌就认为已登录（随后 refreshMe 校验有效性）
        isAuthenticated = !ServerConfig.shared.authToken.isEmpty
    }

    public var user: UserSummary? { current }

    /// 登录：成功后持久化令牌
    @discardableResult
    public func login(username: String, password: String) async throws -> UserSummary {
        let body = try await Api.login(username: username, password: password)
        ServerConfig.shared.saveToken(body.token)
        current = body.user
        isAuthenticated = true
        /*
         把用户 id 落到 meta：离线启动时 `AuthStore.current` 是 nil，
         而记账要拿 owner_id（谁记归谁）—— 没有它归属就是空。
         与鸿蒙 `AuthStore.login` 同一处理。
         */
        try? Db.shared.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
                           ["current_user_id", body.user.id])
        return body.user
    }

    /// 登出：清本机令牌（不强制注销服务端会话，与 Web 一致：本机先干净）
    /// 登录成功后清掉「会话失效」标记
    public func clearSessionExpired() {
        sessionExpired = false
    }

    public func logout() {
        ServerConfig.shared.clearToken()
        current = nil
        isAuthenticated = false

        /*
         主动登出要**清空本地业务数据**：家庭账本多人共用一台设备时，
         A 登出、B 登录，B 在首次同步完成前会看到 A 的全部账目 —— 串号。

         只清业务表，`meta.schema_version` 保留；
         同步游标也重置为 0，下次登录会重新拉全量快照
         （`SyncEngine.pull` 里「本地空 → 快照」的分支会命中）。
         注意：**登录失效（401）不走这里** —— 那种情况要保留数据让用户继续看。
         */
        try? ExpenseDao.clear()
        try? PlanDao.clearAll()
        try? Db.shared.run("DELETE FROM categories")
        try? Db.shared.run("DELETE FROM payment_methods")
        try? Db.shared.run("DELETE FROM users")
        try? Db.shared.run("INSERT OR REPLACE INTO meta(key, value) VALUES ('sync_cursor', '0')")
    }

    /// 拉当前用户（启动时校验令牌是否还有效）
    ///
    /// ⚠ 只有 **401** 才清令牌。403（权限不足）、5xx（服务端重启/网关 502）、
    ///   网络错误都**必须保留令牌** —— 否则一次瞬时故障就把人踢回登录页，
    ///   用户看到的就是「莫名其妙掉登录」。
    ///
    /// 对「没结果」的失败（network / server）重试两次：服务端重启、WiFi 切 4G
    /// 这类抖动通常几秒内自愈，重试比让用户重新输密码划算得多。
    @discardableResult
    public func refreshMe() async -> UserSummary? {
        let maxAttempts = 3
        for attempt in 0..<maxAttempts {
            do {
                let me = try await Api.me()
                current = me
                return me
            } catch let err as ApiError {
                // 令牌真的失效了 —— 只有这一条路清令牌
                if err.kind == .unauthorized {
                    /// 令牌失效：**保留令牌与本地数据**，只打一个标记。
                    ///
                    /// 清掉令牌 = 把人踢回登录页 = 看不到自己的账 —— 对一个记账软件
                    /// 这是最糟的失败方式（服务器一挂，历史全「消失」）。
                    /// 保留令牌后 App 仍然进主界面、照常用本地库，只是同步暂停。
                    sessionExpired = true
                    return nil
                }
                // 403 / 其它 4xx：登录状态没问题，直接返回，不重试也不清令牌
                if !err.retryable {
                    return nil
                }
                // network / server：退避后重试
                if attempt < maxAttempts - 1 {
                    try? await Task.sleep(nanoseconds: UInt64(400_000_000 * (attempt + 1)))
                }
            } catch {
                return nil
            }
        }
        // 重试用尽仍是瞬时故障：保留令牌，按离线处理（用户仍是登录态）
        return nil
    }
}
