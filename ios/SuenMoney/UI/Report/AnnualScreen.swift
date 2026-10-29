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
        .task { await load() }
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

    private func topCat() -> CategoryBucket? {
        (report?.categories ?? []).filter { $0.cents > 0 }.max { $0.cents < $1.cents }
    }

    /// 同比：`ratioOf` 归一（NaN → nil → 不显示）
    private func yearDelta() -> Double? {
        ratioOf(report?.yearAgo?.changeRatio)
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
                    .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: 11.5).weight(.bold))
                    .tracking(isCyber ? 1.54 : 0)
                    .foregroundStyle(Color(css: tokens.ink2))
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                            .stroke(Color(css: isCyber ? tokens.line : .clear), lineWidth: tokens.borderW)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func chevronBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 20))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 38, height: 38)
                .background(Color(css: isCyber ? .clear : tokens.surface))
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
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                // orb：日历
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.accentInk))
                    .frame(width: 34, height: 34)
                    .background(Color(css: isCyber ? .clear : tokens.accent))
                    .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 17))
                    .overlay(
                        RoundedRectangle(cornerRadius: isCyber ? 1 : 17)
                            .stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                                    lineWidth: isCyber ? 1 : 2)
                    )

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

            // 大金额
            VStack(alignment: .leading, spacing: 2) {
                Text("全年支出")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink2))
                Text(formatYuan(report?.totalCents ?? 0))
                    .font(.custom(fontDisplayOf(isCyber), size: 34).weight(.heavy))
                    .tracking(-0.68)
                    .lineLimit(1)
                    .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
            }

            // 四格统计
            HStack(spacing: 8) {
                statCell("笔数", "\(count())")
                statCell("月均", formatYuan(report?.average3YearsCents ?? 0))
                statCell("同比", yearDelta().map { "\(String(format: "%+.0f", $0 * 100))%" } ?? "—")
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

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.custom(fontMonoOf(), size: 9))
                .foregroundStyle(Color(css: tokens.ink3))
            Text(value)
                .font(.custom(fontMonoOf(), size: 12).weight(.bold))
                .foregroundStyle(Color(css: tokens.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(css: tokens.surface2))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
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
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(css: m.month == currentMonthKey() ? tokens.accent : tokens.accent.opacity(0.55)))
                                    .frame(height: max(4, CGFloat(Double(m.totalCents) / Double(monthsMax())) * 100))
                                Text("\(Int(m.month.dropFirst(5).prefix(2)) ?? 0)月")
                                    .font(.custom(fontMonoOf(), size: 8.5))
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 130, alignment: .bottom)
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

    // MARK: - 最高支出月 / 单笔最贵

    private var peakCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("最高支出月")
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))

            if let peak = report?.peakMonth {
                Text(formatMonthLabel(peak.month))
                    .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(formatYuan(peak.totalCents))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink2))
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
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private var largestCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("单笔最贵")
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))

            if let big = report?.largest {
                Text(formatYuan(big.cents))
                    .font(.custom(fontDisplayOf(isCyber), size: 26).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(big.categoryName) · \(formatMonthDay(big.repaymentDate))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink2))
                    .lineLimit(2)
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
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
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
                Text("\(cat.count) 笔")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            HStack(spacing: 10) {
                CatIconView(catName: cat.name, iconSize: 18,
                            color: chartColor(tokens, slotOf(cat.color, cat.categoryId)))
                    .frame(width: 34, height: 34)
                    .background(Color(css: mixHex(chartColor(tokens, slotOf(cat.color, cat.categoryId)),
                                                 tokens.surface, 0.14)))
                    .clipShape(RoundedRectangle(cornerRadius: isCyber ? 0 : 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(css: tokens.ink))
                    Text(formatYuan(cat.cents))
                        .font(.custom(fontMonoOf(), size: 11))
                        .foregroundStyle(Color(css: tokens.ink2))
                }
                Spacer(minLength: 0)
                Text("\(Int((ratioOf(cat.ratio) ?? 0) * 100))%")
                    .font(.custom(fontMonoOf(), size: 13).weight(.bold))
                    .foregroundStyle(Color(css: tokens.accent))
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
            .background(Color(css: tokens.bg))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
            )
        }
    }
}
