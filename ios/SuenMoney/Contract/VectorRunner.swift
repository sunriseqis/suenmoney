//
//  VectorRunner.swift
//  SuenMoney
//
//  三端共用测试向量的 Swift runner。
//
//  数据源：`docs/test-vectors/vectors.json`（与 Web、鸿蒙同一份）。
//  用法：`VectorRunner.runAll()` 返回 PASS/FAIL 报告字符串，可直接贴进验收包。
//
//  为什么手写成断言而不是运行时读 JSON：iOS 主 bundle 里不打包这份 JSON，
//  而向量是**契约**——改了就三端一起改，写死在这里反而更容易在 code review 里看见。
//  断言文本与 vectors.json 的 `note` 逐条对应，便于对照。
//

import Foundation

public final class VectorReport {
    public private(set) var total: Int = 0
    public private(set) var passed: Int = 0
    public private(set) var failures: [String] = []

    public init() {}

    public func check(_ name: String, _ actual: String, _ expect: String) {
        total += 1
        if actual == expect {
            passed += 1
        } else {
            failures.append("\(name): 期望 \(expect)，实际 \(actual)")
        }
    }

    public func summary() -> String {
        let head = failures.isEmpty ? "向量 PASS：\(passed)/\(total)" : "向量 FAIL：\(passed)/\(total)"
        return failures.isEmpty ? head : head + "\n" + failures.joined(separator: "\n")
    }
}

public enum VectorRunner {
    public static func runAll() -> String {
        let r = VectorReport()
        money(r)
        dates(r)
        urgency(r)
        donut(r)
        ulidChecks(r)
        return r.summary()
    }

    // MARK: money（13 条）

    private static func money(_ r: VectorReport) {
        r.check("常规两位小数", String(parseYuanToCents("12.34")), "1234")
        r.check("一位小数补齐", String(parseYuanToCents("0.5")), "50")
        r.check("负数不得翻正（历史 bug）", String(parseYuanToCents("-15.50")), "-1550")
        r.check("-0 必须仍是负", String(parseYuanToCents("-0.50")), "-50")
        r.check("空串为 0", String(parseYuanToCents("")), "0")
        r.check("浮点陷阱：19.99*100=1998.99…", String(parseYuanToCents("19.99")), "1999")
        r.check("千分位 + 两位小数", formatCents(1234), "12.34")
        r.check("退款为负", formatCents(-1550), "-15.50")
        r.check("带 ¥ 前缀", formatYuan(1234), "¥12.34")
        r.check("整元不带小数", centsToInput(1200), "12")
        r.check("补零", centsToInput(1205), "12.05")
        r.check("各期之和必须恰好等于总额（末期补差）",
                splitInstallment(totalCents: 100_000, periods: 3).map(String.init).joined(separator: ","),
                "33333,33333,33334")
        r.check("总额（2 分）小于期数（3）→ 空数组；注意 100 分分 3 期是合法的",
                splitInstallment(totalCents: 2, periods: 3).map(String.init).joined(separator: ","),
                "")
    }

    // MARK: dates（6 条）

    private static func dates(_ r: VectorReport) {
        r.check("跨年回退", shiftMonth("2026-01", -1), "2025-12")
        r.check("跨年前进", shiftMonth("2026-12", 1), "2027-01")
        r.check("普通回退", shiftMonth("2026-10", -1), "2026-09")
        r.check("同一天为 0", String(daysUntil("2026-10-22", from: "2026-10-22")), "0")
        r.check("过去为负", String(daysUntil("2026-10-20", from: "2026-10-22")), "-2")
        r.check("未来为正", String(daysUntil("2026-11-01", from: "2026-10-22")), "10")
    }

    // MARK: urgency（7 条）

    private static func urgency(_ r: VectorReport) {
        r.check("迟于还款日", urgencyOf("2026-10-21", today: "2026-10-22").rawValue, "overdue")
        r.check("今天到期", urgencyOf("2026-10-22", today: "2026-10-22").rawValue, "due")
        r.check("0–1 天都算 due", urgencyOf("2026-10-23", today: "2026-10-22").rawValue, "due")
        r.check("2 天起为 later", urgencyOf("2026-10-24", today: "2026-10-22").rawValue, "later")
        r.check("逾期文案", urgencyLabel("2026-10-20", today: "2026-10-22"), "已逾期 2 天")
        r.check("当天文案", urgencyLabel("2026-10-22", today: "2026-10-22"), "今天到期")
        r.check("未来文案", urgencyLabel("2026-10-25", today: "2026-10-22"), "还有 3 天")
    }

    // MARK: donut（4 条）

    private static func donut(_ r: VectorReport) {
        do {
            let arcs = buildDonutArcs([
                DonutSlice(id: "a", ratio: 0.5, color: "#111111"),
                DonutSlice(id: "b", ratio: 0.3, color: "#222222"),
                DonutSlice(id: "c", ratio: 0.2, color: "#333333")
            ])
            let a = arcs[0]
            r.check("offset 严格递增（首段 25 起步，逐段减 percent）；比例 50/30/20",
                    "\(a.id):\(trimNum(a.percent)):\(trimNum(a.offset))", "a:50:25")
            let b = arcs[1]
            r.check("第二段 offset 应为 -25", "\(b.id):\(trimNum(b.percent)):\(trimNum(b.offset))", "b:30:-25")
        }
        do {
            let arcs = buildDonutArcs([DonutSlice(id: "only", ratio: 1, color: "#111111")])
            let a = arcs[0]
            r.check("单一分类占满 100", "\(a.id):\(trimNum(a.percent)):\(trimNum(a.offset))", "only:100:25")
        }
        r.check("空输入返回空数组", String(buildDonutArcs([]).count), "0")
        do {
            let arcs = buildDonutArcs([DonutSlice(id: "neg", ratio: -0.4, color: "#000000")])
            let a = arcs[0]
            r.check("负 ratio 钳到 0（否则 stroke-dasharray 语法被破坏）",
                    "\(a.id):\(trimNum(a.percent)):\(trimNum(a.offset))", "neg:0:25")
        }
    }

    // MARK: ulid（1 条）

    private static func ulidChecks(_ r: VectorReport) {
        let id = ulid()
        r.check("长度 26", String(id.count), "26")
        let charset = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        let allValid = id.allSatisfy { charset.contains($0) }
        r.check("Crockford 字符集", allValid ? "ok" : "bad", "ok")
    }

    // MARK: 工具

    /// 50.0 → "50"（向量里 percent/offset 都是整数写法）
    private static func trimNum(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}
