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
        .task { await load() }
        .onAppear {
            // 其它屏下钻过来时带的月份（概况热力格 / 年报月柱）
            if !app.pickMonth.isEmpty {
                anchorMonth = app.pickMonth
                tier = 0
                app.pickMonth = ""
                Task { await load() }
            }
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
        if tier == 1 { return ratioOf(yearReport?.yearAgo?.changeRatio) }
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

    /// 构成数据源：分类 / 支付 / 记录人
    private func dimRows() -> [(id: String, name: String, cents: Int, color: String)] {
        if tier == 0, let r = monthReport {
            switch dim {
            case "pay":
                return r.paymentMethods.map {
                    ($0.paymentMethodId, $0.name, $0.cents, chartColor(tokens, slotOf("", $0.paymentMethodId)))
                }
            case "owner":
                return r.members.map {
                    ($0.ownerId, $0.name, $0.cents, chartColor(tokens, slotOf("", $0.ownerId)))
                }
            default:
                return r.categories.map {
                    ($0.categoryId, $0.name, $0.cents, chartColor(tokens, slotOf($0.color, $0.categoryId)))
                }
            }
        }
        if tier == 1, let r = yearReport {
            switch dim {
            case "pay":
                return (r.paymentMethods ?? []).map {
                    ($0.paymentMethodId, $0.name, $0.cents, chartColor(tokens, slotOf("", $0.paymentMethodId)))
                }
            case "owner":
                return (r.members ?? []).map {
                    ($0.ownerId, $0.name, $0.cents, chartColor(tokens, slotOf("", $0.ownerId)))
                }
            default:
                return (r.categories ?? []).map {
                    ($0.categoryId, $0.name, $0.cents, chartColor(tokens, slotOf($0.color, $0.categoryId)))
                }
            }
        }
        if tier == 2, let r = summary {
            return (r.categories ?? []).map {
                ($0.categoryId, $0.name, $0.cents, chartColor(tokens, slotOf($0.color, $0.categoryId)))
            }
        }
        return []
    }

    private func dimTotal() -> Int {
        dimRows().reduce(0) { $0 + $1.cents }
    }

    private func donutSlices() -> [DonutSliceView] {
        dimRows().filter { $0.cents > 0 }.map {
            DonutSliceView(id: $0.id, value: $0.cents, color: $0.color)
        }
    }

    private func repaySteps() -> [RollingMonth] {
        let src = monthReport?.rolling12Months ?? []
        return Array(src.suffix(6))
    }

    private func repayMax() -> Int {
        max(1, repaySteps().map { $0.totalCents ?? 0 }.max() ?? 1)
    }

    /// 涨跌榜：分类环比按差额排序（上期有数据才有意义）
    private func movers() -> [CategoryBucket] {
        let cats: [CategoryBucket]
        if tier == 0 {
            cats = monthReport?.categories ?? []
        } else if tier == 1 {
            cats = yearReport?.categories ?? []
        } else {
            cats = summary?.categories ?? []
        }
        return cats
            .filter { $0.previousCents != nil && ($0.previousCents ?? 0) > 0 }
            .sorted { abs(Double($0.cents - ($0.previousCents ?? 0)))
                    > abs(Double($1.cents - ($1.previousCents ?? 0))) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - ① headCard

    private var headCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // 档位 Seg
                HStack(spacing: isCyber ? 0 : 4) {
                    segButton("本月", 0)
                    segButton("本年", 1)
                    segButton("全部", 2)
                }
                .padding(4)
                .background(Color(css: isCyber ? .clear : tokens.surface2))
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
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func factItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(css: tokens.ink3))
            Text(value)
                .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
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
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tier == value
                            ? Color(css: isCyber ? tokens.accent.opacity(0.1) : tokens.accent)
                            : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
        }
        .buttonStyle(.plain)
    }

    private func chevronButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(tier == 2)
        .opacity(tier == 2 ? 0.45 : 1)
    }

    // MARK: - ② composeCard（构成）

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHead("支出构成", "环图 · 前 4 类 + 其他")

            // 维度切换
            HStack(spacing: 6) {
                dimChip("分类", "cat")
                dimChip("支付", "pay")
                dimChip("记录人", "owner")
            }

            HStack(spacing: 14) {
                DonutChart(
                    slices: donutSlices(),
                    tokens: tokens,
                    ringSize: 136,
                    centerLabel: "合计",
                    centerValue: formatYuan(dimTotal()),
                    isCyber: isCyber
                )

                // 明细条（前 5 项）
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(dimRows().sorted { $0.cents > $1.cents }.prefix(5).enumerated()), id: \.element.id) { _, row in
                        HStack(spacing: 6) {
                            Circle().fill(Color(css: row.color)).frame(width: 6, height: 6)
                            Text(row.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(css: tokens.ink2))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(formatYuan(row.cents))
                                .font(.custom(fontMonoOf(), size: 10))
                                .foregroundStyle(Color(css: tokens.ink))
                            Text(dimTotal() > 0 ? "\(Int((Double(row.cents) / Double(dimTotal()) * 100).rounded()))%" : "0%")
                                .font(.custom(fontMonoOf(), size: 9.5))
                                .foregroundStyle(Color(css: tokens.ink3))
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func dimChip(_ label: String, _ value: String) -> some View {
        Button { dim = value } label: {
            Text(label)
                .font(.system(size: 10.5, weight: dim == value ? .bold : .regular))
                .foregroundStyle(Color(css: dim == value ? tokens.accentInk : tokens.ink2))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(dim == value ? Color(css: tokens.accent) : Color(css: tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - ③ moversCard（涨跌榜）

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
                ForEach(Array(movers().enumerated()), id: \.element.id) { idx, cat in
                    let prev = cat.previousCents ?? 0
                    let delta = cat.cents - prev
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color(css: tokens.ink))
                                .lineLimit(1)
                            Text("\(formatYuan(cat.cents)) / 上期 \(formatYuan(prev))")
                                .font(.custom(fontMonoOf(), size: 9.5))
                                .foregroundStyle(Color(css: tokens.ink3))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(delta > 0 ? "+" : "")\(formatYuan(delta))")
                                .font(.custom(fontMonoOf(), size: 11).weight(.bold))
                                .foregroundStyle(Color(css: delta > 0 ? tokens.danger : tokens.ok))
                            if let ratio = ratioOf(cat.changeRatio) {
                                Text("\(String(format: "%+.0f", ratio * 100))%")
                                    .font(.custom(fontMonoOf(), size: 9.5))
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                        }
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        if idx < movers().count - 1 {
                            Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
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
                            .fill(Color(css: tokens.accent))
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
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    // MARK: - ⑤ annualBanner（年度报告**唯一**入口）

    private var annualBanner: some View {
        Button {
            app.screen = .annual
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(anchorYear) 年度报告已生成")
                        .font(.custom(fontDisplayOf(isCyber), size: 13.5).weight(.bold))
                        .foregroundStyle(Color(css: tokens.accentInk))
                    Text("年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color(css: tokens.accentInk).opacity(0.8))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(css: tokens.accentInk))
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color(css: tokens.accent),
                             Color(css: mixHex(tokens.accent, tokens.surface, 0.55))],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
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
            .background(Color(css: tokens.bg))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
            )
        }
    }
}
