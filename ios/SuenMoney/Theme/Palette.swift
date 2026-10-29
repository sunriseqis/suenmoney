//
//  Palette.swift
//  SuenMoney
//
//  分类配色：把「色号」翻译成当前主题的 chart 颜色。
//
//  三端口径一致：**存色号不存色值**。换主题时账本色整体重排，
//  存死色值会让同一分类在深浅主题下颜色对不上。
//  没设过色号时按分类 id 哈希取一个稳定值（同一分类永远同一个颜色）。
//

import Foundation

private let paletteSize = 8

/// 色号（`"1".."16"` 或 `""`）→ 0..7 的槽位
public func slotOf(_ colorField: String, _ categoryId: String) -> Int {
    if let n = Int(colorField), n >= 1 {
        return (n - 1) % paletteSize
    }
    return hashIndex(categoryId)
}

public func chartColor(_ tokens: ThemeTokens, _ slot: Int) -> String {
    switch slot % paletteSize {
    case 0: return tokens.chart1
    case 1: return tokens.chart2
    case 2: return tokens.chart3
    case 3: return tokens.chart4
    case 4: return tokens.chart5
    case 5: return tokens.chart6
    case 6: return tokens.chart7
    default: return tokens.chart8
    }
}

/// 稳定哈希：同一 id 在任何设备上取到同一槽位
public func hashIndex(_ id: String) -> Int {
    var h = 0
    for ch in id.unicodeScalars {
        h = (h &* 31 &+ Int(ch.value)) % 100_000
    }
    return h % paletteSize
}

/// 16 色槽（鸿蒙 `CATEGORY_COLORS` 同源）
public let categoryColors: [String] = [
    "#00ff88", "#ff00ff", "#00d4ff", "#FBBF24",
    "#5FD6A8", "#66C4CC", "#E07060", "#93A5F0",
    "#C8D656", "#5AD4C4", "#E37FB2", "#A8C056",
    "#E0A878", "#9D8FF5", "#74A8D6", "#8C8C8C"
]

/// 分类名/ID → 16 色槽里的稳定颜色（鸿蒙 `categoryColorOf` 同源）
public func categoryColorOf(_ name: String, _ explicit: String) -> String {
    if !explicit.isEmpty {
        if let n = Int(explicit), n >= 1, n <= categoryColors.count {
            return categoryColors[n - 1]
        }
        if explicit.hasPrefix("#") {
            return explicit
        }
    }
    return categoryColors[deriveColorIndex(name) - 1]
}

/// 名称哈希 → 1..16
public func deriveColorIndex(_ text: String) -> Int {
    var h = 0
    for ch in text.unicodeScalars {
        h = (h &* 31 &+ Int(ch.value)) % 100_000
    }
    return h % categoryColors.count + 1
}
