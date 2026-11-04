//
//  ServerConfig.swift
//  SuenMoney
//
//  服务端地址与令牌存储。
//
//  ⚠ 与鸿蒙端的一处**有意差异**：鸿蒙把 token 存在 `preferences`，
//  iOS 存在 **Keychain**（方案文档 §六「令牌：iOS Keychain」）。
//  键名保持一致（`suenmoney:token` 等），便于将来排错与互通。
//

import Foundation
import Security

/// **不内置任何服务端地址**（用户裁决 2026-11-04）。
///
/// 之前这里 hardcode 着开发机的 `http://192.168.89.10:5310`，等于每个装包的人都
/// 自带一个他根本连不上的地址：装完就能看到「服务器」里填着一串别人的内网 IP，
/// 登录只会得到「连不上服务端」，还很难判断是自己填错了还是包的问题。
/// 首次装包应当是**空**的，地址由用户自己填。
public let defaultServer = ""

private let keyToken = "suenmoney:token"
private let keyServers = "suenmoney:servers"
private let keyActive = "suenmoney:active-server"
private let keychainService = "com.suenmoney.app"

/// `@unchecked Sendable`：`ApiClient` 在任意线程读 `authToken` / `baseUrl`，
/// 写只发生在登录与设置页（主线程）。字段都是 String/[String] 的值拷贝，
/// 读到的要么是旧值要么是新值，不会读到半个状态 —— 故可安全标记。
public final class ServerConfig: @unchecked Sendable {
    public static let shared = ServerConfig()

    private var token: String = ""
    private var servers: [String] = []
    private var active: String = ""

    private init() {}

    /// 启动时读一次（App.init 里调用）
    public func load() {
        token = Keychain.read(key: keyToken) ?? ""
        print("[ServerConfig] load: tokenLen=\(token.count) servers=\(servers.count) active=\(active)")
        if let raw = UserDefaults.standard.string(forKey: keyServers),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data),
           !parsed.isEmpty {
            servers = parsed
        }
        let savedActive = UserDefaults.standard.string(forKey: keyActive) ?? ""
        // 没存过生效地址：取候选首项；候选也是空（首次装包）→ 保持空，让登录页显示占位符
        active = savedActive.isEmpty ? (servers.first ?? "") : savedActive
    }

    public var authToken: String { token }
    public var baseUrl: String { active }
    public var allServers: [String] { servers }

    public func saveToken(_ value: String) {
        token = value
        Keychain.write(key: keyToken, value: value)
    }

    public func clearToken() {
        token = ""
        Keychain.delete(key: keyToken)
    }

    public func setServers(_ list: [String], active chosen: String) {
        servers = list
        active = chosen
        if let data = try? JSONEncoder().encode(list),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: keyServers)
        }
        UserDefaults.standard.set(chosen, forKey: keyActive)
    }
}

// MARK: - Keychain

/// 极简 Keychain 包装：只存「令牌」这一类短字符串。
///
/// 为什么不放 UserDefaults：令牌等同密码，UserDefaults 是明文 plist，
/// 越狱设备/备份文件里能直接读出来。
public enum Keychain {
    public static func write(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        // 先删再加：SecItemUpdate 在「不存在」时返回 errSecItemNotFound，
        // 每次都要判断两种返回码，不如直接覆盖
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        // 首次解锁后可读、不随备份迁移（换机时令牌本就该失效重登）
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            // 写失败此前是**完全静默**的：登录「成功」了但令牌没落盘，
            // 冷启动又回到登录页，现象和「登录不上」一模一样。
            print("[Keychain] 写入失败 \(key) status=\(status)")
        }
    }

    public static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            print("[Keychain] 读取失败 \(key) status=\(status)")
            return nil
        }
        return text
    }

    public static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
