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

/// 开发期默认地址：本机能直连的实例
public let defaultServer = "http://192.168.89.10:5310"

private let keyToken = "suenmoney:token"
private let keyServers = "suenmoney:servers"
private let keyActive = "suenmoney:active-server"
private let keychainService = "com.suenmoney.app"

public final class ServerConfig {
    public static let shared = ServerConfig()

    private var token: String = ""
    private var servers: [String] = [defaultServer]
    private var active: String = defaultServer

    private init() {}

    /// 启动时读一次（App.init 里调用）
    public func load() {
        token = Keychain.read(key: keyToken) ?? ""
        if let raw = UserDefaults.standard.string(forKey: keyServers),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data),
           !parsed.isEmpty {
            servers = parsed
        }
        let savedActive = UserDefaults.standard.string(forKey: keyActive) ?? ""
        active = savedActive.isEmpty ? servers[0] : savedActive
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
        SecItemAdd(add as CFDictionary, nil)
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
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
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
