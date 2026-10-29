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

@Observable
public final class AuthStore {
    public static let shared = AuthStore()

    public private(set) var current: UserSummary?

    private init() {}

    public var isAuthenticated: Bool {
        !ServerConfig.shared.authToken.isEmpty
    }

    public var user: UserSummary? { current }

    /// 登录：成功后持久化令牌
    @discardableResult
    public func login(username: String, password: String) async throws -> UserSummary {
        let body = try await Api.login(username: username, password: password)
        ServerConfig.shared.saveToken(body.token)
        current = body.user
        return body.user
    }

    /// 登出：清本机令牌（不强制注销服务端会话，与 Web 一致：本机先干净）
    public func logout() {
        ServerConfig.shared.clearToken()
        current = nil
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
            }
            return nil
        } catch {
            return nil
        }
    }
}
