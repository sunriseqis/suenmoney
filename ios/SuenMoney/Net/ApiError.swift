//
//  ApiError.swift
//  SuenMoney
//
//  接口错误分类。
//
//  为什么要分类而不是统一抛「网络错误」：
//    - unauthorized（401）→ 跳登录，而不是提示「网络不好」
//    - network（连不上/超时）→ 进入离线模式、写入走 Outbox
//    - server（5xx）→ 可重试，提示「稍后再试」
//    - client（4xx）→ 是请求写错了，重试也没用，直接把服务端的 message 显示出来
//  四类混成一句「请求失败」会让用户和我们都无法判断下一步该做什么。
//

import Foundation

public enum ApiErrorKind: String {
    case network
    case unauthorized
    case client
    case server
    case parse
}

public struct ApiError: Error, LocalizedError {
    public let kind: ApiErrorKind
    public let message: String
    public let status: Int
    public let code: String

    public init(_ kind: ApiErrorKind, _ message: String, status: Int = 0, code: String = "") {
        self.kind = kind
        self.message = message
        self.status = status
        self.code = code
    }

    /// 是否值得重试（网络与服务端错误可重试，其余不可）
    public var retryable: Bool {
        kind == .network || kind == .server
    }

    public var errorDescription: String? { message }
}
