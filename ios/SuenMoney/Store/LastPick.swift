//
//  LastPick.swift
//  SuenMoney
//
//  记住上次用的分类与支付方式。
//
//  记账是高频动作，绝大多数时候重复的是同一组选择；每次都从第一项重选，
//  等于每天多做两次没有信息量的点击。
//
//  沿用前必须校验「它现在仍然可选」——分类可能已被停用。
//  这条校验由调用方做（它手上有字典），这里只负责存取。
//

import Foundation

private let keyLastPick = "suenmoney:last-pick"

public struct LastPickValue: Codable {
    public let categoryId: String
    public let paymentMethodId: String

    public init(categoryId: String, paymentMethodId: String) {
        self.categoryId = categoryId
        self.paymentMethodId = paymentMethodId
    }
}

public enum LastPick {
    public static func read() -> LastPickValue? {
        guard let raw = UserDefaults.standard.string(forKey: keyLastPick),
              let data = raw.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(LastPickValue.self, from: data) else {
            return nil
        }
        return parsed
    }

    public static func write(_ value: LastPickValue) {
        guard let data = try? JSONEncoder().encode(value),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: keyLastPick)
    }
}
