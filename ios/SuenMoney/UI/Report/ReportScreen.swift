//
//  ReportScreen.swift
//  SuenMoney
//
//  报表页（对应鸿蒙 `components/report/ReportScreen.ets`，1169 行）。
//
//  五块：
//    headCard      档位 Seg + 期间导航 + 期间支出/环比/对比/日均/笔数
//    composeCard   支出构成（环图 + 分类/支付/记录人三维切换 + 明细条）
//    moversCard    涨跌榜（分类环比 · 按差额排序）
//    repayCard     还款节奏（近 6 个月柱）
//    annualBanner  年度报告大横幅（**唯一入口**，顶部不再重复，用户 2026-10-29 裁决）
//
//  ⚠ 两处踩过的坑（已在本文件修正）：
//    1. 期间标签必须显式给 `foregroundStyle` —— 不给会用系统默认色，
//       深色主题下变成黑字黑底。
//    2. 比率用 `ratioOf()` 归一 —— 服务端「上年无数据」时可能**不带**该字段，
//       `nil * 100` 会让界面出现 `NaN%`。
//

import SwiftUI

struct Mover: Identifiable {
    let name: String
    let categoryId: String
    let color: String
    let now: Int
    let before: Int
    let diff: Int

    var id: String { categoryId }
}

struct DimRow: Identifiable {
    let id: String
    let name: String
    let cents: Int
    let color: String
}

public struct ReportScreen: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var app

    @State private var tier: Int = 0
    @State private var anchorMonth: String = currentMonthKey()
    @State private var dim: String = "cat"

    @State private var monthReport: MonthlyReport?
    @State private var prevMonthReport: MonthlyReport?
    @State private var yearReport: YearlyReport?
    @State private var summary: SummaryReport?
    @State private var loading: Bool = true
    @State private var errorText: String = ""

    @State private var calOpen: Bool = false
    @State private var calYear: Int = Int(currentMonthKey().prefix(4)) ?? 2026

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }
    private var anchorYear: String { String(anchorMonth.prefix(4)) }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    headCard
                    composeCard
                    moversCard
                    repayCard
                    annualBanner
                    if loading {
                        Text("加载中…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)

            if calOpen { periodCalendar }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 只在一个地方触发加载：之前 `.task` 和 `.onAppear` 各发一轮，
        // 下钻进入时会打 8 个接口（两轮 × 四个报表）。
        .onAppear {
            // 其它屏下钻过来时带的月份（概况热力格 / 年报月柱）
            if !app.pickMonth.isEmpty {
                anchorMonth = app.pickMonth
                tier = 0
                app.pickMonth = ""
            }
            Task { await load() }
        }
    }

    // MARK: - 加载

    /// 四个报表**都拉**（与鸿蒙 `ReportScreen.load()` 同构）：
    /// 本月 / 上月 / 年报 / 汇总。
    ///
    /// 上月是给涨跌榜兜底用的（月报里 `categories[].previousCents` 缺省时还能对一下），
    /// 年报与汇总在非对应档位也要有值（构成条、还款节奏会跨档复用）。
    /// 单个失败置 nil、不清其他。
    private func load() async {
        loading = true
        defer { loading = false }
        errorText = ""

        var m: MonthlyReport?
        var p: MonthlyReport?
        var y: YearlyReport?
        var s: SummaryReport?
        m = try? await Api.monthlyReport(month: anchorMonth).report
        p = try? await Api.monthlyReport(month: shiftMonth(anchorMonth, -1)).report
        y = try? await Api.yearlyReport(year: anchorYear).report
        s = try? await Api.summaryReport().report

        monthReport = m
        prevMonthReport = p
        yearReport = y
        summary = s

        if m == nil && y == nil && s == nil {
            errorText = "报表加载失败，请检查网络后重试"
        }
    }

    private func applyPeriod(_ month: String, _ newTier: Int) {
        anchorMonth = month
        tier = newTier
        calOpen = false
        // 切到年档时把锚点归一到该年 1 月（鸿蒙 switchTier('year') 同），
        // 否则月报请求会去打「该年-某月」，与年档的热力/下钻范围对不上
        if newTier == 1 {
            anchorMonth = "\(String(month.prefix(4)))-01"
        }
        Task { await load() }
    }

    private func shift(_ delta: Int) {
        if tier == 0 {
            anchorMonth = shiftMonth(anchorMonth, delta)
        } else if tier == 1 {
            let y = (Int(anchorYear) ?? 2026) + delta
            anchorMonth = "\(y)-01"
        }
        Task { await load() }
    }

    // MARK: - 派生值

    private func activeTotal() -> Int {
        if tier == 0 { return monthReport?.totalCents ?? 0 }
        if tier == 1 { return yearReport?.totalCents ?? 0 }
        return summary?.totalCents ?? 0
    }

    private func activeCount() -> Int {
        if tier == 0 { return monthReport?.count ?? 0 }
        if tier == 1 { return yearReport?.count ?? 0 }
        return summary?.count ?? 0
    }

    private func prevTotal() -> Int {
        if tier == 0 { return monthReport?.previous.totalCents ?? 0 }
        if tier == 1 { return yearReport?.yearAgo?.totalCents ?? 0 }
        return 0
    }

    /// 环比：`ratioOf` 归一（NaN → nil → 胶囊不显示）
    private func deltaRatio() -> Double? {
        if tier == 0 { return ratioOf(monthReport?.change.ratio) }
        if tier == 1 { return ratioOf(yearReport?.yearAgo?.change?.ratio) }
        return nil
    }

    /// 日均 / 单笔均值（与鸿蒙 `ReportScreen.perDayCents` 同义）
    ///
    /// ⚠ 非月档**不是**「总额 / 天数」：年档/全部档下这个位置显示的是
    /// **单笔均值**（总额 / 笔数）。鸿蒙端就是这么分的，照抄。
    private func perDayCents() -> Int {
        if tier != 0 {
            let n = activeCount()
            return n > 0 ? activeTotal() / max(1, n) : 0
        }
        let day = max(1, Calendar.current.component(.day, from: Date()))
        return activeTotal() / day
    }

    private func periodLabel() -> String {
        if tier == 1 { return "\(anchorYear) 年" }
        if tier == 2 { return "全部" }
        return formatMonthLabel(anchorMonth)
    }

    /// 构成数据行（鸿蒙 `dimRows`）：
    /// - cat：过滤 >0 → 降序 → **前 7 + 「其他」**（色 ink3）
    /// - pay / owner：**恒取 monthReport**（与档位无关），颜色按**数组下标**取槽位
    /// - week：按 monthReport.daily 聚合星期几，色统一 accent
    private func dimRows() -> [DimRow] {
        if dim == "cat" {
            var rows = (categoriesForTier()).filter { $0.cents > 0 }.sorted { $0.cents > $1.cents }
            var out: [DimRow] = rows.prefix(7).map {
                DimRow(id: $0.categoryId, name: $0.name, cents: $0.cents,
                       color: chartColor(tokens, slotOf($0.color, $0.categoryId)))
            }
            let rest = rows.dropFirst(7).reduce(0) { $0 + $1.cents }
            if rest > 0 {
                out.append(DimRow(id: "__rest", name: "其他", cents: rest, color: tokens.ink3))
            }
            return out
        }
        if dim == "pay" {
            let src = monthReport?.paymentMethods ?? []
            // 按**下标**取色槽（鸿蒙 `chartColor(tok, i % 8)`），按 id 哈希会让三端配色错开
            return filterSort(src.enumerated().map { i, p in
                DimRow(id: p.paymentMethodId, name: p.name, cents: p.cents,
                       color: chartColor(tokens, i % 8))
            })
        }
        if dim == "owner" {
            let src = monthReport?.members ?? []
            // owner 有 +3 偏移（鸿蒙 `(i + 3) % 8`）
            return filterSort(src.enumerated().map { i, m in
                DimRow(id: m.ownerId, name: m.name, cents: m.cents,
                       color: chartColor(tokens, (i + 3) % 8))
            })
        }
        // 节奏：周日 → 周六
        let wd = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        var byWeekday = [Int](repeating: 0, count: 7)
        for d in (monthReport?.daily ?? []) {
            let day = weekdayIndex(d.date)
            byWeekday[day] += d.cents
        }
        return (0..<7).map { DimRow(id: "wd\($0)", name: wd[$0], cents: byWeekday[$0], color: tokens.accent) }
    }

    private func categoriesForTier() -> [CategoryBucket] {
        if tier == 0 { return monthReport?.categories ?? [] }
        if tier == 1 { return yearReport?.categories ?? [] }
        return summary?.categories ?? []
    }

    private func filterSort(_ src: [DimRow]) -> [DimRow] {
        src.filter { $0.cents > 0 }.sorted { $0.cents > $1.cents }
    }

    /// `YYYY-MM-DD` → 0(周日)..6(周六)
    /// Calendar 的 `.weekday` 是 1(周日)…7(周六)，减 1 即得 0 起下标
    private func weekdayIndex(_ date: String) -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: parseDateKey(date))
        return max(0, min(6, weekday - 1))
    }

    private func dimTotal() -> Int {
        dimRows().reduce(0) { $0 + $1.cents }
    }

    /// 图例百分比的分母恒为**期间总额**（鸿蒙 `activeTotal()`），不是行求和
    private func percentOf(_ cents: Int) -> Int {
        activeTotal() > 0 ? Int((Double(cents) / Double(activeTotal()) * 100).rounded()) : 0
    }

    private func dimMax() -> Int {
        max(1, dimRows().map { $0.cents }.max() ?? 1)
    }

    private func repaySteps() -> [RollingMonth] {
        let src = monthReport?.rolling12Months ?? []
        return Array(src.suffix(6))
    }

    private func repayMax() -> Int {
        max(1, repaySteps().map { $0.totalCents ?? 0 }.max() ?? 1)
    }

    /// 涨跌榜（鸿蒙 `movers`）：**只在月档**、用**上月报**逐项匹配取 before。
    ///
    /// 之前用同一份报文的 `previousCents` 且要求 >0，导致：
    ///   · 上月报白拉了；· 「本期新增分类」（previous=0）被整体过滤掉；
    ///   · 年档/全部档也出数据（鸿蒙只在月档出）。
    private func movers() -> [Mover] {
        guard tier == 0, let prev = prevMonthReport else { return [] }
        var out: [Mover] = []
        for c in categoriesForTier() {
            let before = prev.categories.first { $0.categoryId == c.categoryId }?.cents ?? 0
            let diff = c.cents - before
            if abs(diff) > 0 {
                out.append(Mover(name: c.name, categoryId: c.categoryId,
                                 color: categoryColorOf(c.name, c.color),
                                 now: c.cents, before: before, diff: diff))
            }
        }
        out.sort { abs($0.diff) > abs($1.diff) }
        return Array(out.prefix(6))
    }

    /// 一句话结论（鸿蒙 `conclusion`）
    private func conclusion() -> String {
        let total = activeTotal()
        if total == 0 {
            return "这个期间还没有记录，记一笔之后这里会自动生成结论。"
        }
        let top = categoriesForTier().sorted { $0.cents > $1.cents }.first
        let head = top.map { "头号开销是\($0.name)，占 \(Int((Double($0.cents) / Double(total) * 100).rounded()))%；" } ?? ""
        if let r = deltaRatio() {
            let word = r >= 0 ? "多花 " : "少花 "
            return head + "整体\(word)\(formatYuan(abs(total - prevTotal())))（\(String(format: "%.1f", abs(r * 100)))%）。"
        }
        return head + "这是第一段可对比的期间。"
    }

    // MARK: - ① headCard

    private var headCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 档位 Seg：**胶囊轨道**（鸿蒙有 padding 4 + surface2 底 + 描边）
                HStack(spacing: isCyber ? 0 : 4) {
                    segButton("本月", 0)
                    segButton("本年", 1)
                    segButton("全部", 2)
                }
                .padding(4)
                .background(Color(css: isCyber ? "transparent" : tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )

                // 期间导航（全部档禁用箭头）
                HStack(spacing: 4) {
                    chevronButton("‹") { shift(-1) }
                    Button {
                        calYear = Int(anchorMonth.prefix(4)) ?? 2026
                        calOpen = true
                    } label: {
                        Text(periodLabel())
                            .font(.custom(fontDisplayOf(isCyber), size: 13).weight(.bold))
                            // ⚠ 必须显式给色：不给会用系统默认色，深色主题下黑字黑底
                            .foregroundStyle(Color(css: tokens.ink))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    chevronButton("›") { shift(1) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // 期间支出 + 环比/对比/日均/笔数
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("期间支出")
                        .font(.custom(fontMonoOf(), size: 10.5))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Text(formatYuan(activeTotal()))
                        .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                        .tracking(-0.52)
                        .lineLimit(1)
                        .foregroundStyle(Color(css: tokens.ink))
                }

                FlowRow(spacing: 8) {
                    if let ratio = deltaRatio() {
                        HStack(spacing: 3) {
                            Image(systemName: ratio > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9))
                            Text("\(String(format: "%.1f", abs(ratio) * 100))%")
                                .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                        }
                        .foregroundStyle(Color(css: ratio > 0 ? tokens.danger : tokens.ok))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: ratio > 0 ? tokens.danger : tokens.ok), lineWidth: 1)
                        )
                    }
                    factItem("对比", formatYuan(prevTotal()))
                    factItem("日均", formatYuan(perDayCents()))
                    factItem("笔数", "\(activeCount())")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    private func factItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(css: tokens.ink3))
            Text(value)
                .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(css: tokens.ink2))
        }
    }

    private func segButton(_ title: String, _ value: Int) -> some View {
        Button { applyPeriod(anchorMonth, value) } label: {
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: 10.5).weight(.bold))
                .foregroundStyle(Color(css: tier == value
                                       ? (isCyber ? tokens.accent : tokens.accentInk)
                                       : tokens.ink2))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(tier == value
                            ? (isCyber ? Color(css: tokens.accent).opacity(0.1) : Color(css: tokens.accent))
                            : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
        }
        .buttonStyle(.plain)
    }

    /// 期间箭头：icon-btn 38×38，带底色与描边（鸿蒙 `navChevron`）
    private func chevronButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 38, height: 38)
                .background(Color(css: tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )
        }
        .buttonStyle(.plain)
        .disabled(tier == 2)
        .opacity(tier == 2 ? 0.45 : 1)
    }

    // MARK: - ② composeCard（构成）

    /// 支出构成（鸿蒙 `composeCard`）：标题 + 四维 chip + 三形态可视化 + **全宽虚线图例行**
    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            // card-h：标题 + chips（移动端 card-cap 隐藏，chips 全宽可横滑）
            VStack(alignment: .leading, spacing: 8) {
                Text("支出构成")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        dimChip("分类", "cat")
                        dimChip("支付", "pay")
                        dimChip("记录人", "owner")
                        dimChip("节奏", "week")
                    }
                    .padding(.bottom, 2)
                }
            }

            if dimRows().isEmpty {
                Text("这个期间还没有构成数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 34)
                    .padding(.bottom, 34)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // compose-visual：分类→环图 / 节奏→星期柱 / 其余→条形榜
                    if dim == "cat" {
                        HStack {
                            Spacer(minLength: 0)
                            DonutChart(
                                slices: donutSlices(),
                                tokens: tokens,
                                ringSize: 136,
                                centerLabel: "合计",
                                // 环心恒为**期间总额**（鸿蒙 activeTotal()），不是行求和
                                centerValue: formatYuan(activeTotal()),
                                isCyber: isCyber
                            )
                            Spacer(minLength: 0)
                        }
                    } else if dim == "week" {
                        weekBars
                    } else {
                        dimBars
                    }

                    // compose-list：全宽虚线图例行（9px 色块 / 1fr 名 / 64px 金额 / 32px 百分比）
                    VStack(spacing: 0) {
                        ForEach(Array(dimRows().enumerated()), id: \.element.id) { idx, row in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(css: row.color))
                                    .frame(width: 9, height: 9)
                                Text(row.name)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color(css: tokens.ink))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(formatYuan(row.cents))
                                    .font(.custom(fontMonoOf(), size: 11.5))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(css: tokens.ink))
                                    .frame(width: 64, alignment: .trailing)
                                Text("\(percentOf(row.cents))%")
                                    .font(.custom(fontMonoOf(), size: 10))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(css: tokens.ink3))
                                    .frame(width: 32, alignment: .trailing)
                            }
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) {
                                if idx < dimRows().count - 1 { dashedRule }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    /// 节奏维度：7 根星期柱（柱高 = cents/dimMax * 80，最小 3；容器高 112）
    private var weekBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(dimRows()) { row in
                VStack(spacing: 6) {
                    Text(row.cents > 0 ? formatCompactCents(row.cents) : "")
                        .font(.custom(fontMonoOf(), size: 8.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCyber ? Color.clear : Color(css: tokens.accent))
                        .frame(maxWidth: 30)
                        .frame(height: max(3, CGFloat(Double(row.cents) / Double(dimMax())) * 80))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(css: tokens.line2), lineWidth: isCyber ? 0 : 1)
                        )
                        .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.6)") : .clear,
                                radius: isCyber ? 6 : 0, x: 0, y: isCyber ? -2 : 0)
                    Text(String(row.name.suffix(1)))
                        .font(.custom(fontMonoOf(), size: 9))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 112, alignment: .bottom)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 支付 / 记录人维度：条形排名（62px 名 | 轨道 | 76px 值）
    private var dimBars: some View {
        VStack(spacing: 8) {
            ForEach(dimRows()) { row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.ink2))
                        .lineLimit(1)
                        .frame(width: 62, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .fill(Color(css: tokens.surface3))
                                .frame(height: 10)
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .fill(Color(css: row.color))
                                .frame(width: geo.size.width * CGFloat(Double(row.cents) / Double(dimMax())), height: 10)
                        }
                    }
                    .frame(height: 10)
                    Text(formatYuan(row.cents))
                        .font(.custom(fontMonoOf(), size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Color(css: tokens.ink))
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
    }

    /// 真虚线（鸿蒙 BorderStyle.Dashed）
    private var dashedRule: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0.5))
            p.addLine(to: CGPoint(x: 10_000, y: 0.5))
        }
        .stroke(Color(css: tokens.line), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(height: 1)
    }

    /// 四维 chip（鸿蒙 `dimChip`）：candy 选中是**琥珀底 + line2 描边 + 2px 硬阴影**，
    /// cyber 是 accent 文字 + 半透明绿底 + accent 描边。
    private func dimChip(_ label: String, _ value: String) -> some View {
        let on = dim == value
        let shape = RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
        return Button { dim = value } label: {
            Text(label)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10 : 11.5).weight(.medium))
                .tracking(isCyber ? 0.6 : 0)
                .foregroundStyle(Color(css: on
                                       ? (isCyber ? tokens.accent : tokens.onColor)
                                       : tokens.ink2))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(shape.fill(Color(css: on
                                             ? (isCyber ? "rgba(0,255,136,0.1)" : tokens.amber)
                                             : (isCyber ? "transparent" : tokens.surface))))
                .overlay(shape.stroke(Color(css: on
                                            ? (isCyber ? tokens.accent : tokens.line2)
                                            : tokens.line),
                                      lineWidth: isCyber ? 1 : 2))
                .background {
                    if on && !isCyber {
                        shape.fill(Color(css: tokens.line2)).offset(x: 2, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - ③ moversCard（涨跌榜）

    /// 涨跌榜（鸿蒙 `moversCard`）：30×30 分类徽位 + 名称/对比 + 差额/百分比，底部「一句话结论」
    private var moversCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHead("涨跌榜", "分类环比 · 按差额排序")

            if movers().isEmpty {
                Text("没有可比较的上期数据")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(movers().enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 9) {
                            CatIconView(catName: m.name, iconSize: 17, color: m.color)
                                .frame(width: 30, height: 30)
                                .background(Color(css: mixHex(m.color, tokens.surface, 0.12)))
                                .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: isCyber ? 1 : 9)
                                        .stroke(Color(css: mixHex(m.color, tokens.surface, 0.45)), lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Color(css: tokens.ink))
                                    .lineLimit(1)
                                // 上期为 0 时显示「新增」，不要显示「¥0.00」那种没信息量的对比
                                Text(m.before > 0
                                     ? "\(formatYuan(m.now)) / 上期 \(formatYuan(m.before))"
                                     : "\(formatYuan(m.now)) / 本期新增")
                                    .font(.custom(fontMonoOf(), size: 9.5))
                                    .foregroundStyle(Color(css: tokens.ink3))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(m.diff > 0 ? "+" : "") \(formatYuan(m.diff))")
                                    .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(css: m.diff > 0 ? tokens.danger : tokens.ok))
                                if m.before > 0 {
                                    Text("\(String(format: "%+.0f", Double(m.diff) / Double(m.before) * 100))%")
                                        .font(.custom(fontMonoOf(), size: 9.5))
                                        .monospacedDigit()
                                        .foregroundStyle(Color(css: tokens.ink3))
                                }
                            }
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) {
                            if idx < movers().count - 1 { dashedRule }
                        }
                    }
                }

                // 一句话结论（鸿蒙有，iOS 之前整段缺失）
                Text(conclusion())
                    .font(.system(size: 11))
                    .lineSpacing(4)
                    .foregroundStyle(Color(css: tokens.ink2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .overlay(alignment: .top) { dashedRule }
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    // MARK: - ④ repayCard（还款节奏）

    private var repayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHead("还款节奏", "近 6 个月 · 按账期")

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(repaySteps()) { r in
                    VStack(spacing: 5) {
                        Text((r.totalCents ?? 0) > 0 ? formatCompactCents(r.totalCents ?? 0) : "")
                            .font(.custom(fontMonoOf(), size: 8.5))
                            .foregroundStyle(Color(css: tokens.ink3))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(css: tokens.pink))
                            .frame(height: max(4, CGFloat(Double(r.totalCents ?? 0) / Double(repayMax())) * 64))
                        Text("\(Int(r.month.dropFirst(5).prefix(2)) ?? 0)月")
                            .font(.custom(fontMonoOf(), size: 8.5))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    // MARK: - ⑤ annualBanner（年度报告**唯一**入口）

    /// 年度报告大横幅（**唯一入口**）。
    ///
    /// candy：三停渐变 accent → #A78BFA(65%) → pink，2px line2 描边，5px 硬阴影；
    /// cyber：绿→青淡渐变，1px accent 描边，绿色外发光；
    /// 文字色 cyber 用 accent（#00ff88）、candy 用纯白 —— 用 accentInk 在 cyber 下是
    /// #04220f（近黑深绿），压在绿→青渐变上几乎读不出来。
    private var annualBanner: some View {
        let fg = isCyber ? tokens.accent : "#FFFFFF"
        let shape = RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
        return Button {
            app.annualYear = anchorYear
            app.screen = .annual
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(anchorYear) 年度报告已生成")
                        .font(.custom(fontDisplayOf(isCyber), size: 13.5).weight(.bold))
                        .foregroundStyle(Color(css: fg))
                    Text("年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(css: fg).opacity(0.85))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(css: fg))
            }
            .padding(14)
            .background(
                ZStack {
                    shape.fill(Color(css: tokens.surface))
                    if isCyber {
                        shape.fill(LinearGradient(
                            stops: [
                                .init(color: Color(css: "rgba(0,255,136,0.14)"), location: 0),
                                .init(color: Color(css: "rgba(0,212,255,0.06)"), location: 1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        shape.fill(LinearGradient(
                            stops: [
                                .init(color: Color(css: tokens.accent), location: 0),
                                .init(color: Color(css: "#A78BFA"), location: 0.65),
                                .init(color: Color(css: tokens.pink), location: 1)
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
            )
            .clipShape(shape)
            .overlay(shape.stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                                  lineWidth: isCyber ? 1 : 2))
            .background {
                if !isCyber {
                    shape.fill(Color(css: tokens.line2)).offset(x: 5, y: 5)
                }
            }
            .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.7)") : .clear,
                    radius: isCyber ? 13 : 0, x: 0, y: isCyber ? -10 : 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 共用

    private func cardHead(_ title: String, _ cap: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))
            Spacer(minLength: 0)
            Text(cap)
                .font(.custom(fontMonoOf(), size: 9.5))
                .tracking(1.52)
                .foregroundStyle(Color(css: tokens.ink3))
        }
    }

    // MARK: - 期间月历

    private var periodCalendar: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { calOpen = false }
            VStack(spacing: 10) {
                HStack {
                    Text("选择期间")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button { calOpen = false } label: {
                        Text("关闭").font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Button { calYear -= 1 } label: {
                        Text("‹").font(.system(size: 18))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text("\(calYear) 年")
                        .font(.custom(fontDisplayOf(isCyber), size: 15).weight(.bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button { calYear += 1 } label: {
                        Text("›").font(.system(size: 18))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(1...12, id: \.self) { mm in
                        let key = monthKeyOf(year: calYear, month: mm)
                        let active = key == anchorMonth && tier == 0
                        Button { applyPeriod(key, 0) } label: {
                            Text("\(mm)月")
                                .font(.custom(fontMonoOf(), size: 12))
                                .foregroundStyle(Color(css: active ? tokens.accentInk : tokens.ink2))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Color(css: active ? tokens.accent : tokens.surface2))
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                        .stroke(Color(css: tokens.line), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        applyPeriod(monthKeyOf(year: calYear,
                                               month: Int(anchorMonth.dropFirst(5).prefix(2)) ?? 1), 1)
                    } label: {
                        Text("整年").font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .overlay(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                .stroke(Color(css: tokens.line), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { applyPeriod(currentMonthKey(), 0) } label: {
                        Text("回到本月").font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity).frame(height: 32)
                            .overlay(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                .stroke(Color(css: tokens.line), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(width: 300)
            .card(tokens, isCyber, radius: 16, surface: tokens.bg)
        }
    }
}
