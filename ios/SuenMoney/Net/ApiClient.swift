//
//  ApiClient.swift
//  SuenMoney
//
//  HTTP 客户端。
//
//  三条设计约束，都来自踩过的坑：
//    1. **超时分开设**：connect 4s / read 10s。连接阶段慢说明地址不通，快点失败
//       才能尽快换下一个服务端；读阶段慢说明服务端在算（报表聚合），给足时间。
//       ⚠ URLSession 只有 `timeoutInterval`（整个请求）+ `timeoutIntervalForResource`，
//       没有独立的 connect 超时；这里用 `timeoutInterval = 4` + `resourceTimeout = 10`
//       近似同一语义（探活另走 ServerRouter 的 4s）。
//    2. **错误必须分类**（见 ApiError）：401 要跳登录，网络错误要进离线模式，
//       两者混成一句「请求失败」会让后续逻辑全部走错分支。
//    3. **非 2xx 也要读出服务端 message**：服务端的错误文案是中文、可读的，
//       直接显示比我们自己编「操作失败」有用。
//
//  认证：`POST /api/auth/login` 拿 token，之后一律 `Authorization: Bearer <token>`。
//

import Foundation

public enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct RequestOptions {
    public var method: HttpMethod = .get
    public var body: String?
    /// 覆盖读超时（报表聚合、批量导入这类长事务型请求用）
    public var readTimeout: TimeInterval = 10
    /// 是否带 Bearer（登录、status 不需要）
    public var withAuth: Bool = true

    public init(method: HttpMethod = .get, body: String? = nil, readTimeout: TimeInterval = 10, withAuth: Bool = true) {
        self.method = method
        self.body = body
        self.readTimeout = readTimeout
        self.withAuth = withAuth
    }
}

/// 服务端统一错误体：`{ error, details, code }`
private struct ServerErrorBody: Decodable {
    let error: String?
    let details: String?
    let code: String?
}

public final class ApiClient {
    public static let shared = ApiClient()
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 10
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    /// 请求并反序列化成 T
    public func request<T: Decodable>(_ path: String, _ options: RequestOptions) async throws -> T {
        let data = try await rawRequest(path, options)
        if data.isEmpty {
            // 204 / 空体：调用方按 Void 用 —— 但泛型这里要求非空，
            // 所以约定：空体一律由 `requestVoid` 处理，这里给一个明确错误
            throw ApiError(.parse, "服务端返回空体，但调用方要求对象")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ApiError(.parse, "服务端返回的不是预期 JSON 结构", status: 0)
        }
    }

    /// 请求但不关心响应体（DELETE 之类）
    public func requestVoid(_ path: String, _ options: RequestOptions) async throws {
        _ = try await rawRequest(path, options)
    }

    /// 底层：只负责拿 Data，错误分类在这里做
    private func rawRequest(_ path: String, _ options: RequestOptions) async throws -> Data {
        let base = path.hasPrefix("http") ? path : "\(ServerConfig.shared.baseUrl)\(path)"
        guard let url = URL(string: base) else {
            throw ApiError(.client, "地址不合法：\(base)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = options.method.rawValue
        req.timeoutInterval = options.readTimeout

        // Content-Type 只在**真的有 body** 时发。
        // 之前无条件带 application/json，DELETE（如删流水）没 body 时服务端 Fastify 会直接
        // 报 `Body cannot be empty when content-type is set to 'application/json'`。
        if let body = options.body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.data(using: .utf8)
        }
        if options.withAuth {
            let token = ServerConfig.shared.authToken
            if !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError(.network, "连不上服务端（\((error as NSError).code)）", status: 0,
                           code: String((error as NSError).code))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 200 && status < 300 {
            return data
        }
        throw toError(status: status, data: data)
    }

    // MARK: 便捷方法

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, RequestOptions(method: .get))
    }

    public func post<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await request(path, RequestOptions(method: .post, body: encode(body)))
    }

    public func patch<T: Decodable>(_ path: String, _ body: some Encodable) async throws -> T {
        try await request(path, RequestOptions(method: .patch, body: encode(body)))
    }

    public func delete(_ path: String) async throws {
        try await requestVoid(path, RequestOptions(method: .delete))
    }

    /// POST 但不关心返回体
    public func postVoid(_ path: String, _ body: some Encodable) async throws {
        try await requestVoid(path, RequestOptions(method: .post, body: encode(body)))
    }

    public func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: 错误归类

    /// 把 HTTP 状态码与错误体归到四类之一
    private func toError(status: Int, data: Data) -> ApiError {
        var message = "请求失败（\(status)）"
        var code = ""
        if !data.isEmpty, let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data) {
            if let e = body.error, !e.isEmpty {
                message = e
            }
            code = body.code ?? ""
        }

        let kind: ApiErrorKind
        if status == 401 || status == 403 {
            kind = .unauthorized
        } else if status >= 500 {
            kind = .server
        } else {
            kind = .client
        }
        return ApiError(kind, message, status: status, code: code)
    }
}
