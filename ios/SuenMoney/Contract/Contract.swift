//
//  Contract.swift
//  SuenMoney
//
//  纯逻辑层：金额 / 日期 / 紧急度 / 环图 / 标识。
//
//  与 Web `web/src/utils/{money,dates,urgency,donut}.ts` 及鸿蒙 `common/contract/Contract.ets`
//  **逐条同义** —— 三端共用同一份测试向量（docs/test-vectors/vectors.json），
//  谁改了实现，那份 JSON 就会有一条不过。这是唯一能防止「三个端各算各的」的手段。
//
//  全项目口径（写错了不报错，只会算成另一个数）：
//    金额：整数分；日期：YYYY-MM-DD 字符串；紧急度：迟于还款日 = overdue，0–1 天 = due，更远 = later。
//

import Foundation

// MARK: - 金额

/// 分 → `1,234.56`（不含货币符号）
///
/// 手写分组而不是 NumberFormatter：各系统区域设置不一致，且这里要的是**固定格式**。
public func formatCents(_ cents: Int) -> String {
    let negative = cents < 0
    let absCents = abs(cents)
    let yuan = absCents / 100
    let fen = absCents % 100
    return "\(negative ? "-" : "")\(groupThousands(yuan)).\(pad2(fen))"
}

/// 分 → `¥1,234.56`
public func formatYuan(_ cents: Int) -> String {
    "¥\(formatCents(cents))"
}

/// 紧凑金额（web `formatCompact`）：万元以下舍角分，万元以上用「万」
///
/// 用于热力格、构成条这类**空间很窄**的地方 —— 那里放不下 `¥1,234.56`。
public func formatCompactCents(_ cents: Int) -> String {
    let absCents = abs(cents)
    let sign = cents < 0 ? "-" : ""
    if absCents < 1_000_000 {
        let yuan = (absCents + 50) / 100
        return "\(sign)¥\(groupThousands(yuan))"
    }
    let wan = Double(absCents) / 1_000_000
    return wan >= 100
        ? "\(sign)¥\(String(format: "%.0f", wan))万"
        : "\(sign)¥\(String(format: "%.1f", wan))万"
}

/// 服务端可能没给的比率 → nil（`undefined * 100` = NaN → 界面出现 `NaN%`）
public func ratioOf(_ r: Double?) -> Double? {
    guard let r, r.isFinite else { return nil }
    return r
}

/// 分 → `1234.56` / `12`（回填输入框用，不带符号与千分位）
public func centsToInput(_ cents: Int) -> String {
    let absCents = abs(cents)
    let yuan = absCents / 100
    let fen = absCents % 100
    return fen == 0 ? String(yuan) : "\(yuan).\(pad2(fen))"
}

/// 元文本 → 整数分
///
/// **禁止** `Double(x) * 100`：19.99 会得到 1998.9999999999998，
/// 四舍五入时机差一点就差一分钱，而这一分钱会一路累进到月度总额里。
/// 这里全程整数：元部分 ×100 + 小数部分补齐两位；符号先剥离再统一赋回
/// （否则 "-0.50" 会被算成 +50）。
public func parseYuanToCents(_ input: String) -> Int {
    if input.isEmpty || input == "." {
        return 0
    }
    let negative = input.hasPrefix("-")
    let absText = negative ? String(input.dropFirst()) : input
    let parts = absText.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    let intPart = (parts.first?.isEmpty == false) ? parts[0] : "0"
    let decPart = parts.count > 1 ? parts[1] : ""
    guard let yuan = Int(intPart) else { return 0 }
    let fenText = String((decPart + "00").prefix(2))
    guard let fen = Int(fenText) else { return 0 }
    let cents = yuan * 100 + fen
    return negative ? -cents : cents
}

/// 等额分期：前 n−1 期取整，末期补差，保证各期之和恰好等于总额
public func splitInstallment(totalCents: Int, periods: Int) -> [Int] {
    guard totalCents > 0, periods >= 1, periods <= 600, totalCents >= periods else {
        return []
    }
    let base = totalCents / periods
    var out: [Int] = []
    for _ in 0..<(periods - 1) {
        out.append(base)
    }
    out.append(totalCents - base * (periods - 1))
    return out
}

// MARK: - 日期（只用 YYYY-MM-DD 与 YYYY-MM，不用时间戳）

/// `YYYY-MM` 平移 n 个月，跨年正确
public func shiftMonth(_ month: String, _ delta: Int) -> String {
    let parts = month.split(separator: "-").map(String.init)
    guard parts.count >= 2, let y = Int(parts[0]), let m = Int(parts[1]) else {
        return month
    }
    let total = y * 12 + (m - 1) + delta
    let ny = total / 12
    let nm = total % 12
    return "\(ny)-\(pad2(nm + 1))"
}

/// `YYYY-MM` → `2026 年 10 月`
public func formatMonthLabel(_ month: String) -> String {
    let y = String(month.prefix(4))
    let m = Int(month.dropFirst(5).prefix(2)) ?? 0
    return "\(y) 年 \(m) 月"
}

/// 距目标日期还有几天（负数是已过去）。用 UTC 归一到整天，避免时区/夏令时误差
public func daysUntil(_ target: String, from: String) -> Int {
    let a = utcDay(from)
    let b = utcDay(target)
    return Int(((b - a) / 86_400_000).rounded())
}

/// `YYYY-MM-DD` → `MM月DD日`
public func formatMonthDay(_ date: String) -> String {
    let m = Int(date.dropFirst(5).prefix(2)) ?? 0
    let d = Int(date.dropFirst(8).prefix(2)) ?? 0
    return "\(m)月\(d)日"
}

// MARK: - 紧急度

public enum Urgency: String {
    case overdue
    case due
    case later
}

/// 逾期文案：`已逾期 N 天` / `今天到期` / `还有 N 天`
///
/// ⚠ 这个函数**与 vectors.json、Web 端一致**，用「已逾期」。
/// 但鸿蒙端 UI 里的待办标签按 R49 裁决用精简口径「逾期 N 天」——
/// 那是 UI 层自己拼的（`todoTag()`），**不经过这个函数**。
/// 两边不冲突：本函数只服务于三端共用的向量测试，UI 文案各按裁决。
public func urgencyLabel(_ date: String, today: String) -> String {
    let d = daysUntil(date, from: today)
    if d == 0 {
        return "今天到期"
    }
    if d < 0 {
        return "已逾期 \(-d) 天"
    }
    return "还有 \(d) 天"
}

/// 迟于还款日 = overdue；0–1 天 = due；更远 = later
public func urgencyOf(_ date: String, today: String) -> Urgency {
    let days = daysUntil(date, from: today)
    if days < 0 { return .overdue }
    if days <= 1 { return .due }
    return .later
}

// MARK: - 环图

private let donutStartOffset: Double = 25

public struct DonutSlice {
    public let id: String
    /// 0–1 的占比
    public let ratio: Double
    public let color: String

    public init(id: String, ratio: Double, color: String) {
        self.id = id
        self.ratio = ratio
        self.color = color
    }
}

public struct DonutArc {
    public let id: String
    public let percent: Double
    public let offset: Double
    public let color: String
}

/// 环图各段：offset 从 25 起递减累计；负 ratio 钳到 0（负的 dasharray 会破坏路径）
public func buildDonutArcs(_ slices: [DonutSlice]) -> [DonutArc] {
    var out: [DonutArc] = []
    var cumulative: Double = 0
    for slice in slices {
        let percent = round2(max(0, slice.ratio) * 100)
        out.append(DonutArc(
            id: slice.id,
            percent: percent,
            offset: round2(donutStartOffset - cumulative),
            color: slice.color
        ))
        cumulative += percent
    }
    return out
}

// MARK: - 标识

private let ulidChars = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
private var lastUlidTime: Int = 0
private var ulidSeq: Int = 0
private let ulidLock = NSLock()

/// ULID：26 位、Crockford Base32、前 10 位时间戳
///
/// 与服务端/Web 同构：主键由**客户端**生成，这样离线记的账在入队时就已有最终 id，
/// 联网后不会「换一个 id」。同毫秒内用序号避免撞车。
public func ulid() -> String {
    ulidLock.lock()
    defer { ulidLock.unlock() }

    let now = Int(Date().timeIntervalSince1970 * 1000)
    if now != lastUlidTime {
        lastUlidTime = now
        ulidSeq = 0
    } else {
        ulidSeq = (ulidSeq + 1) % 32
    }

    var timePart = ""
    var t = now
    for _ in 0..<10 {
        timePart = String(ulidChars[t % 32]) + timePart
        t /= 32
    }
    var randomPart = ""
    for _ in 0..<15 {
        randomPart += String(ulidChars[Int.random(in: 0..<32)])
    }
    return timePart + String(ulidChars[ulidSeq]) + String(randomPart.prefix(15))
}

// MARK: - 本地时区工具

/// 本地时区「今天」`YYYY-MM-DD`
public func todayKey() -> String {
    dateKey(Date())
}

/// 本地时区「昨天」`YYYY-MM-DD`
public func yesterdayKey() -> String {
    dateKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
}

/// 当前月 `YYYY-MM`
public func currentMonthKey() -> String {
    String(todayKey().prefix(7))
}

/// Date → `YYYY-MM-DD`（本地时区）
public func dateKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    let y = c.year ?? 1970
    let m = c.month ?? 1
    let d = c.day ?? 1
    return "\(y)-\(pad2(m))-\(pad2(d))"
}

/// `YYYY-MM-DD` → Date（本地时区零点，避免时区偏移一天）
public func parseDateKey(_ key: String) -> Date {
    let parts = key.split(separator: "-").map(String.init)
    var c = DateComponents()
    c.year = Int(parts.count > 0 ? parts[0] : "1970") ?? 1970
    c.month = Int(parts.count > 1 ? parts[1] : "1") ?? 1
    c.day = Int(parts.count > 2 ? parts[2] : "1") ?? 1
    return Calendar.current.date(from: c) ?? Date()
}

/// `(年, 月, 日)` → `YYYY-MM-DD`
public func dateKeyOf(year: Int, month: Int, day: Int) -> String {
    "\(year)-\(pad2(month))-\(pad2(day))"
}

/// `(年, 月)` → `YYYY-MM`
public func monthKeyOf(year: Int, month: Int) -> String {
    "\(year)-\(pad2(month))"
}

/// 某年某月的天数
public func daysInMonth(year: Int, month: Int) -> Int {
    var c = DateComponents()
    c.year = year
    c.month = month
    let cal = Calendar.current
    guard let date = cal.date(from: c),
          let range = cal.range(of: .day, in: .month, for: date) else {
        return 30
    }
    return range.count
}

/// 某年某月 1 号是星期几（1 = 周日，与 Calendar 的 weekday 一致）
public func firstWeekday(year: Int, month: Int) -> Int {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = 1
    guard let date = Calendar.current.date(from: c) else { return 1 }
    return Calendar.current.component(.weekday, from: date)
}

/// 该月已过天数（概况页「日均」用）
///
/// 口径与鸿蒙 `DashboardScreen.elapsedDaysOf` 一致：
/// **非当前月一律返回整月天数**（历史月和未来月都是）—— 不是「未来月返回 0」。
/// 未来月总额本来就是 0，返回 0 会让 `0/0` 需要额外兜底，返回整月天数更简单也更一致。
public func elapsedDaysOf(_ month: String) -> Int {
    let parts = month.split(separator: "-").map(String.init)
    guard parts.count >= 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return 0 }
    let total = daysInMonth(year: y, month: m)
    if month != currentMonthKey() {
        return total
    }
    let day = Calendar.current.component(.day, from: Date())
    return min(total, max(1, day))
}

// MARK: - 内部工具

private func pad2(_ n: Int) -> String {
    n < 10 ? "0\(n)" : String(n)
}

/// 千分位分组
private func groupThousands(_ n: Int) -> String {
    let s = String(n)
    var out = ""
    var count = 0
    for ch in s.reversed() {
        out = String(ch) + out
        count += 1
        if count % 3 == 0 && out.count < s.count {
            out = "," + out
        }
    }
    return out
}

private func round2(_ v: Double) -> Double {
    (v * 100).rounded() / 100
}

/// `YYYY-MM-DD` → 该日 UTC 零点毫秒
private func utcDay(_ key: String) -> Double {
    let y = Int(key.prefix(4)) ?? 1970
    let m = Int(key.dropFirst(5).prefix(2)) ?? 1
    let d = Int(key.dropFirst(8).prefix(2)) ?? 1
    var c = DateComponents()
    c.year = y
    c.month = m
    c.day = d
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    guard let date = cal.date(from: c) else { return 0 }
    return date.timeIntervalSince1970 * 1000
}
