//
//  BillingCycle.swift
//  SuenMoney
//
//  业务日期与信用卡账单周期。
//
//  ⚠ **与服务端 `server/src/domain/billing-cycle.ts` 逐条对应**，
//    也与鸿蒙 `common/contract/BillingCycle.ets` 一致。三处必须同步改。
//
//  客户端算一份是为了本地记账能立刻算出 `posting_date` / `repayment_date`
//  （报表按还款日聚合，算错会把这笔账归到错误的月份）；同步回推后服务端会
//  再算一次并以它为准。
//
//  全部业务日期都是 'YYYY-MM-DD' 字符串（本地日期，不含时区）。
//  日期加减一律走 UTC 日历，结果与运行环境时区无关。
//

import Foundation

/// 支付方式的账单周期描述
public struct PaymentCycle {
    /// 'cash' | 'credit'
    public let type: String
    public let billingDay: Int
    public let repaymentDay: Int

    public init(type: String, billingDay: Int, repaymentDay: Int) {
        self.type = type
        self.billingDay = billingDay
        self.repaymentDay = repaymentDay
    }
}

public struct ResolvedDates {
    /// 入账日（账单日）
    public let postingDate: String
    /// 还款日 —— 报表月份归属以此为准
    public let repaymentDate: String
}

private let datePattern = #"^(\d{4})-(\d{2})-(\d{2})$"#

/// 某年某月的天数（month 为 1 基）
public func bcDaysInMonth(_ year: Int, _ month: Int) -> Int {
    var comps = DateComponents()
    comps.year = year
    comps.month = month + 1
    comps.day = 0
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    guard let date = cal.date(from: comps) else { return 30 }
    return cal.component(.day, from: date)
}

/// 把「几号」钳到该月实际存在的范围。
///
/// 「每月 31 号」在 2 月不存在，**必须钳到该月最后一天，绝不能顺延到下月 1 号** ——
/// 顺延会让 2 月的房贷落到 3 月，报表月份归属直接错乱。
public func bcClampDay(_ year: Int, _ month: Int, _ day: Int) -> Int {
    min(day, bcDaysInMonth(year, month))
}

public func bcDateString(_ year: Int, _ month: Int, _ day: Int) -> String {
    String(format: "%04d-%02d-%02d", year, month, day)
}

/// 解析 'YYYY-MM-DD'（失败返回 nil，调用方按「原样返回」处理）
public func bcParse(_ value: String) -> (year: Int, month: Int, day: Int)? {
    guard let re = try? NSRegularExpression(pattern: datePattern),
          let m = re.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          m.numberOfRanges == 4,
          let y = Range(m.range(at: 1), in: value).flatMap({ Int(value[$0]) }),
          let mo = Range(m.range(at: 2), in: value).flatMap({ Int(value[$0]) }),
          let d = Range(m.range(at: 3), in: value).flatMap({ Int(value[$0]) }),
          mo >= 1, mo <= 12, d >= 1, d <= bcDaysInMonth(y, mo)
    else { return nil }
    return (y, mo, d)
}

/// 月份加减，返回归一化后的年月（日固定 1）
private func bcShiftMonth(_ year: Int, _ month: Int, _ delta: Int) -> (year: Int, month: Int) {
    let total = year * 12 + (month - 1) + delta
    return (Int(floor(Double(total) / 12)), total % 12 + 1)
}

/// 日期顺延 N 个月，保持「几号」不变，遇该月无此日取该月最后一天。
///
/// 计划（房贷/分期）逐期生成日期用的核心函数。
public func bcAddMonths(_ date: String, _ delta: Int) -> String {
    guard let p = bcParse(date) else { return date }
    let s = bcShiftMonth(p.year, p.month, delta)
    return bcDateString(s.year, s.month, bcClampDay(s.year, s.month, p.day))
}

/// 日期加减天数（UTC 毫秒运算，与时区无关）
public func bcAddDays(_ date: String, _ delta: Int) -> String {
    guard let p = bcParse(date) else { return date }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    var comps = DateComponents()
    comps.year = p.year
    comps.month = p.month
    comps.day = p.day
    guard let base = cal.date(from: comps),
          let shift = cal.date(byAdding: .day, value: delta, to: base)
    else { return date }
    let out = cal.dateComponents([.year, .month, .day], from: shift)
    guard let y = out.year, let m = out.month, let d = out.day else { return date }
    return bcDateString(y, m, d)
}

/// 消费日 → 入账日 / 还款日。
///
/// 信用卡规则（消费日 d，账单日 B，还款日 R）：
///     d <= B  → 入账日 = 本期的 B
///     d >  B  → 入账日 = 次期的 B
/// 还款日的「期」必须与入账日对齐：
///     R >  B → 还款日与入账日同月
///     R <= B → 还款日落在入账日的下一个月
/// 现金 / 储蓄卡没有账单周期，入账日 = 还款日 = 消费日。
public func resolveExpenseDates(spendDate: String, cycle: PaymentCycle) -> ResolvedDates {
    if cycle.type == "cash" {
        return ResolvedDates(postingDate: spendDate, repaymentDate: spendDate)
    }
    guard let spend = bcParse(spendDate) else {
        return ResolvedDates(postingDate: spendDate, repaymentDate: spendDate)
    }

    // 账单日当天消费算本期（`<=`），这是定死的规则
    let billPeriod = spend.day <= cycle.billingDay
        ? (year: spend.year, month: spend.month)
        : bcShiftMonth(spend.year, spend.month, 1)

    let postingDate = bcDateString(billPeriod.year, billPeriod.month,
                                   bcClampDay(billPeriod.year, billPeriod.month, cycle.billingDay))

    let repayPeriod = cycle.repaymentDay > cycle.billingDay
        ? billPeriod
        : bcShiftMonth(billPeriod.year, billPeriod.month, 1)

    let repaymentDate = bcDateString(repayPeriod.year, repayPeriod.month,
                                     bcClampDay(repayPeriod.year, repayPeriod.month, cycle.repaymentDay))

    return ResolvedDates(postingDate: postingDate, repaymentDate: repaymentDate)
}

/// 还款日 → 入账日（`resolveExpenseDates` 的逆向）。
///
/// 月末吸附还原：待办日期按「遇该月无此日取月末」生成，平年 2 月的 R=31 落在 2/28，
/// 直接拿 28 与账单日比较会误判成上一期。因此被月末吸附时按配置的 R 参与比较。
public func resolvePostingDate(repaymentDate: String, cycle: PaymentCycle) -> String {
    if cycle.type == "cash" { return repaymentDate }
    guard let repay = bcParse(repaymentDate) else { return repaymentDate }

    let clampedToMonthEnd = repay.day == bcDaysInMonth(repay.year, repay.month)
        && cycle.repaymentDay > repay.day
    let effectiveDay = clampedToMonthEnd ? cycle.repaymentDay : repay.day

    let period = effectiveDay > cycle.billingDay
        ? (year: repay.year, month: repay.month)
        : bcShiftMonth(repay.year, repay.month, -1)

    return bcDateString(period.year, period.month,
                        bcClampDay(period.year, period.month, cycle.billingDay))
}

/// 还款日往前推 n 天 = 提醒日
public func computeRemindDate(_ repaymentDate: String, daysBefore: Int) -> String {
    bcAddDays(repaymentDate, -daysBefore)
}

/// 计划逐期生成日期。
///
/// 从首期日**递推**，而不是「上一期 +1 个月」逐级累加 ——
/// 逐级累加会把 1/31 → 2/28 的错误一路传染，后面每期都变成 28 号。
public func generatePeriodDates(firstDueDate: String, count: Int) -> [String] {
    (0..<count).map { bcAddMonths(firstDueDate, $0) }
}
