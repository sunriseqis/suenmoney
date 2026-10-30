//
//  AnnualScreen.swift
//  SuenMoney
//
//  年度报告（对应鸿蒙 `components/report/AnnualScreen.ets`，724 行）。
//
//  结构：
//    yearBar       ‹ 2026 年 › + 返回报表（点年份文字弹「年份快选」）
//    overviewCard  {year} 年度全貌：总额 / 笔数 / 月均 / 同比 四格
//    monthsCard    12 个月走势（按还款日归属，点柱下钻到报表）
//    peakCard      最高支出月
//    largestCard   单笔最贵
//    topCatCard    支出最多的分类
//
//  ⚠ 年份快选用 `summaryReport.years`（**真实有数据的年份**），不是凭空列 12 个。
//

import SwiftUI

struct YearOption: Identifiable {
    let year: String
    let totalCents: Int
    let count: Int

    var id: String { year }
}

public struct AnnualScreen: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var app

    @State private var year: String = String(Calendar.current.component(.year, from: Date()))
    @State private var yearCalOpen: Bool = false
    @State private var yearOptions: [YearOption] = []
    @State private var report: YearlyReport?
    @State private var loading: Bool = true
    @State private var errorText: String = ""

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    yearBar
                    overviewCard
                    monthsCard
                    HStack(alignment: .top, spacing: 16) {
                        peakCard
                        largestCard
                    }
                    if let top = topCat() {
                        topCatCard(top)
                    }
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

            if yearCalOpen { yearPicker }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // 报表屏可能带了年份过来（鸿蒙 AppStorage('annualYear')）
            if !app.annualYear.isEmpty, app.annualYear != year {
                year = app.annualYear
            }
            await load()
        }
    }

    // MARK: - 加载

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            report = try await Api.yearlyReport(year: year).report
        } catch let err as ApiError {
            errorText = err.message
            report = nil
        } catch {
            report = nil
        }
    }

    /// 打开年份快选：拉 summaryReport 拿「真实有数据的年份」（降序），补上当前选中的年份
    private func openYearPicker() async {
        yearCalOpen = true
        var out: [YearOption] = []
        if let s = try? await Api.summaryReport().report {
            out = s.years.map { YearOption(year: $0.year, totalCents: $0.totalCents, count: $0.count) }
        }
        if !out.contains(where: { $0.year == year }) {
            out.append(YearOption(year: year, totalCents: 0, count: 0))
        }
        out.sort { $0.year > $1.year }
        yearOptions = out
    }

    // MARK: - 派生值

    private func months() -> [MonthPoint] { report?.months ?? [] }

    private func monthsMax() -> Int {
        max(1, months().map { $0.totalCents }.max() ?? 1)
    }

    private func count() -> Int { report?.count ?? 0 }

    private func total() -> Int { report?.totalCents ?? 0 }

    /// 空月数（全年 12 个月里支出为 0 的月数）
    private func quietMonths() -> Int {
        months().filter { $0.totalCents == 0 }.count
    }

    private func yearAgoCents() -> Int { report?.yearAgo?.totalCents ?? 0 }

    private func topCat() -> CategoryBucket? {
        (report?.categories ?? []).filter { $0.cents > 0 }.max { $0.cents < $1.cents }
    }

    /// 同比：`ratioOf` 归一（NaN → nil → 不显示）
    private func yearDelta() -> Double? {
        ratioOf(report?.yearAgo?.change?.ratio)
    }

    // MARK: - 年份条

    private var yearBar: some View {
        HStack(spacing: 10) {
            chevronBtn("‹") {
                year = String((Int(year) ?? 2026) - 1)
                Task { await load() }
            }
            Button {
                Task { await openYearPicker() }
            } label: {
                Text("\(year) 年")
                    .font(.custom(fontMonoOf(), size: 15).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
            }
            .buttonStyle(.plain)
            chevronBtn("›") {
                year = String((Int(year) ?? 2026) + 1)
                Task { await load() }
            }
            Spacer(minLength: 0)
            Button {
                app.screen = .report
            } label: {
                Text("返回报表")
                    .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 11 : 11.5).weight(.bold))
                    .tracking(isCyber ? 1.54 : 0)
                    .foregroundStyle(Color(css: tokens.ink2))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                            .stroke(Color(css: isCyber ? tokens.line : "transparent"), lineWidth: tokens.borderW)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .card(tokens, isCyber, radius: 16)
    }

    private func chevronBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 38, height: 38)
                .background(Color(css: isCyber ? "transparent" : tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 年度全貌

    private var overviewCard: some View {
        // 鸿蒙是 Column() 无间距 + 逐段 margin（header 13 / hero 8-4 / metrics 16+14）
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // orb：日历
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.accentInk))
                    .frame(width: 34, height: 34)
                    .background(Color(css: isCyber ? "transparent" : tokens.accent))
                    .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 17))
                    .overlay(
                        RoundedRectangle(cornerRadius: isCyber ? 1 : 17)
                            .stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                                    lineWidth: isCyber ? 1 : 2)
                    )
                    // candy 贴纸硬投影 / cyber 上投绿光
                    .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.4)") : .clear,
                            radius: isCyber ? 5 : 0, x: 0, y: isCyber ? -2 : 0)
                    .background {
                        if !isCyber {
                            RoundedRectangle(cornerRadius: 17)
                                .fill(Color(css: tokens.line2)).offset(x: 2, y: 2)
                        }
                    }

                Text("\(year) 年度全貌")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("\(months().count) 个月 · \(count()) 笔")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            // 大金额：¥ 独立成段（0.5 倍字号 + ink2），数字按长度自适应 34/28/22
            // 鸿蒙 hero 有 margin top 8 / bottom 4
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.system(size: heroSize() * 0.5, weight: .bold))
                    .foregroundStyle(Color(css: tokens.ink2))
                Text(formatYuan(total()).replacingOccurrences(of: "¥", with: ""))
                    .font(.custom(fontDisplayOf(isCyber), size: heroSize()).weight(.heavy))
                    .tracking(isCyber ? 0.4 : -1.33)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // hero-delta：环比胶囊 + 去年
            HStack(spacing: 8) {
                if let ratio = yearDelta() {
                    Text("\(String(format: "%.1f", ratio * 100))%")
                        .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                        .foregroundStyle(Color(css: ratio > 0 ? tokens.danger : tokens.ok))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: ratio > 0 ? tokens.danger : tokens.ok), lineWidth: isCyber ? 1 : 1.5)
                        )
                }
                Text("去年 \(formatYuan(yearAgoCents()))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(css: tokens.ink2))
            }

            // hero-metrics：月均 / 单笔均值 / 空月（与鸿蒙 statCell 三项一致）
            HStack(spacing: 10) {
                statCell("月均", formatYuan(Int((Double(total()) / 12).rounded())))
                statCell("单笔均值", formatYuan(count() > 0 ? Int((Double(total()) / Double(count())).rounded()) : 0))
                statCell("空月", "\(quietMonths()) 个月")
            }
            .padding(.top, 14)
            .overlay(alignment: .top) {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(css: tokens.line))
                    .frame(height: 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // candy 顶卡是 2px 深墨描边（line2），不是普通卡片的浅灰 line
        .card(tokens, isCyber, radius: 16, border: isCyber ? tokens.line : tokens.line2)
    }

    private func heroSize() -> CGFloat {
        let s = formatYuan(total()).replacingOccurrences(of: "¥", with: "")
        if s.count <= 8 { return 34 }
        if s.count <= 10 { return 28 }
        return 22
    }

    /// 三段统计（鸿蒙 `statCell`）：**值在上（21/18 display Bold）、标签在下（10.5/9.5）、
    /// 裸列无底色无内距**。之前做成灰底 chip + 标签在上，版式完全不同。
    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 18 : 21).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color(css: tokens.ink))
                .lineLimit(1)
            Text(label)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 9.5 : 10.5))
                .tracking(isCyber ? 1.14 : 0.42)
                .foregroundStyle(Color(css: tokens.ink3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 12 个月走势

    private var monthsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Text("12 个月走势")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("按还款日归属")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            if months().isEmpty {
                Text("这一年还没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(months()) { m in
                        Button {
                            // 下钻：写 pickMonth，报表消费它（空月也如实停在那个月）
                            app.pickMonth = m.month
                            app.screen = .report
                        } label: {
                            VStack(spacing: 4) {
                                // 仅上两角 3（web `border-radius:3px 3px 0 0`）
                                UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0,
                                                       bottomTrailingRadius: 0, topTrailingRadius: 3)
                                    // 0 支出的月份用 surface3（灰柱），否则「空月」看不出来
                                    .fill(Color(css: m.totalCents > 0
                                                ? mixHex(tokens.accent, tokens.surface, 0.75)
                                                : tokens.surface3))
                                    .frame(height: max(4, (Double(m.totalCents) / Double(monthsMax()) * 100).rounded()))
                                Text("\(Int(m.month.dropFirst(5).prefix(2)) ?? 0)")
                                    .font(.custom(fontMonoOf(), size: 9.5))
                                    .monospacedDigit()
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 140, alignment: .bottom)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    // MARK: - 最高支出月 / 单笔最贵

    private var peakCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最高支出月")
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))
                .padding(.bottom, 13)

            if let peak = report?.peakMonth {
                Text(formatMonthLabel(peak.month))
                    .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                Text(formatYuan(peak.totalCents))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink2))
                    .padding(.top, 4)
            } else {
                Text("没有数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    private var largestCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("单笔最贵")
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))
                .padding(.bottom, 13)

            if let big = report?.largest {
                Text(formatYuan(big.cents))
                    .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                Text("\(big.categoryName) · \(big.repaymentDate)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink2))
                    .lineLimit(1)
                    .padding(.top, 4)
            } else {
                Text("没有数据")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    // MARK: - 支出最多的分类

    private func topCatCard(_ cat: CategoryBucket) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Text("支出最多的分类")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("全年")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            // 鸿蒙这里只有「名称 / 金额 / 百分比」三个 Text，没有图标块
            HStack(spacing: 0) {
                Text(cat.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatYuan(cat.cents))
                    .font(.custom(fontMonoOf(), size: 12).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
                // 本地算（鸿蒙同）：服务端 ratio 缺失时也能出数；四舍五入不是截断
                Text("\(total() > 0 ? Int((Double(cat.cents) / Double(total()) * 100).rounded()) : 0)%")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink2))
                    .padding(.leading, 10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    // MARK: - 年份快选

    private var yearPicker: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { yearCalOpen = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("选择年份")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button { yearCalOpen = false } label: {
                        Text("关闭").font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .buttonStyle(.plain)
                }

                if yearOptions.isEmpty {
                    Text("加载中…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.ink3))
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(yearOptions) { opt in
                            Button {
                                year = opt.year
                                yearCalOpen = false
                                Task { await load() }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(opt.year)
                                        .font(.custom(fontMonoOf(), size: 14).weight(.bold))
                                        .foregroundStyle(Color(css: year == opt.year ? tokens.accentInk : tokens.ink))
                                    Text(opt.count > 0 ? "\(opt.count) 笔" : "无数据")
                                        .font(.custom(fontMonoOf(), size: 9.5))
                                        .foregroundStyle(Color(css: year == opt.year ? tokens.accentInk : tokens.ink3))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color(css: year == opt.year ? tokens.accent : tokens.surface2))
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                        .stroke(Color(css: year == opt.year ? tokens.accent : tokens.line), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 320)
            .card(tokens, isCyber, radius: 16, surface: tokens.bg, shadow: false)
        }
    }
}
