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
        return body.user
    }

    /// 登出：清本机令牌（不强制注销服务端会话，与 Web 一致：本机先干净）
    public func logout() {
        ServerConfig.shared.clearToken()
        current = nil
        isAuthenticated = false
    }

    /// 拉当前用户（启动时校验令牌是否还有效）
    @discardableResult
    public func refreshMe() async -> UserSummary? {
        do {
            let me = try await Api.me()
            current = me
            return me
        } catch let err as ApiError {
            // 401 → 令牌失效，清掉；网络错 → 保留令牌，进离线
            if err.kind == .unauthorized {
                ServerConfig.shared.clearToken()
                current = nil
                isAuthenticated = false
            }
            return nil
        } catch {
            return nil
        }
    }
}
