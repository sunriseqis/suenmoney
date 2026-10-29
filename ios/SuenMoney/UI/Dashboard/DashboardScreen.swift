//
//  DashboardScreen.swift
//  SuenMoney
//
//  概况页（对应鸿蒙 `components/dashboard/DashboardScreen.ets`，1212 行）。
//
//  三块（自 web 的「概况」三卡）：
//    ogHero  期间 Seg（本月/本年/全部）+ 期间导航 + 大金额 + 环比 + 三指标 + 构成条 + 待办
//    ogHeat  月度支出热力（近 12 个月，移动 4 列，点格下钻到报表）
//    ogCum   累计与跨度（5 行 kv）
//
//  ⚠ iOS 与鸿蒙的差异：`Grid` → `LazyVGrid`；`sys.symbol` → SF Symbols；
//  下钻靠写 `AppState.pickMonth` 再切屏（与鸿蒙写 AppStorage 同构）。
//

import SwiftUI

struct DashTodo: Identifiable {
    let id: String
    let planName: String
    let periodSeq: Int
    let amountCents: Int
    let repaymentDate: String
    let willAutoPost: Bool
}

struct ComposeRow: Identifiable {
    let id: String
    let name: String
    let cents: Int
    let color: String
}

public struct DashboardScreen: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var app

    @State private var tier: Int = 0
    @State private var anchorMonth: String = currentMonthKey()
    @State private var todoOpen: Bool = false

    @State private var monthReport: MonthlyReport?
    @State private var yearReport: YearlyReport?
    @State private var summary: SummaryReport?
    @State private var todos: [DashTodo] = []
    @State private var loading: Bool = true
    @State private var errorText: String = ""
    @State private var toastText: String = ""

    @State private var calOpen: Bool = false
    @State private var calYear: Int = Int(currentMonthKey().prefix(4)) ?? 2026

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }
    private var anchorYear: String { String(anchorMonth.prefix(4)) }

    // MARK: - 生命周期

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(css: tokens.danger))
                            .frame(maxWidth: .infinity)
                    }
                    ogHero
                    ogHeat
                    ogCum
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

            if !toastText.isEmpty {
                Text(toastText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(css: tokens.bg))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(css: tokens.ink))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    // MARK: - 加载

    private func load() async {
        loading = true
        defer { loading = false }
        errorText = ""
        do {
            if tier == 0 {
                monthReport = try await Api.monthlyReport(month: anchorMonth).report
            } else if tier == 1 {
                yearReport = try await Api.yearlyReport(year: anchorYear).report
            } else {
                summary = try await Api.summaryReport().report
            }
            // 累计卡始终要 summary
            if summary == nil || tier != 2 {
                summary = try await Api.summaryReport().report
            }
            await loadTodos()
        } catch let err as ApiError {
            errorText = err.message
        } catch {
            errorText = "加载失败"
        }
    }

    private func loadTodos() async {
        do {
            let body = try await Api.planTodos(today: todayKey())
            todos = body.todos.map {
                DashTodo(id: $0.id, planName: $0.planName, periodSeq: $0.periodSeq,
                         amountCents: $0.amountCents, repaymentDate: $0.repaymentDate,
                         willAutoPost: $0.willAutoPost)
            }
        } catch {
            todos = []
        }
    }

    private func applyPeriod(_ month: String, _ newTier: Int) {
        anchorMonth = month
        tier = newTier
        calOpen = false
        Task { await load() }
    }

    private func showToast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastText == text { toastText = "" }
        }
    }

    // MARK: - 派生值

    private func totalCents() -> Int {
        if tier == 0 { return monthReport?.totalCents ?? 0 }
        if tier == 1 { return yearReport?.totalCents ?? 0 }
        return summary?.totalCents ?? 0
    }

    private func prevCents() -> Int {
        if tier == 0 { return monthReport?.previous.totalCents ?? 0 }
        if tier == 1 { return yearReport?.yearAgo?.totalCents ?? 0 }
        return 0
    }

    /// 环比：上期为 0 或字段缺失时返回 nil（**不能**返回 NaN → 界面会显示 `NaN%`）
    private func deltaRatio() -> Double? {
        let prev = prevCents()
        guard prev > 0 else { return nil }
        let ratio = Double(totalCents() - prev) / Double(prev)
        return ratio.isFinite ? ratio : nil
    }

    private func countOf() -> Int {
        if tier == 0 { return monthReport?.count ?? 0 }
        if tier == 1 { return yearReport?.count ?? 0 }
        return summary?.count ?? 0
    }

    private func periodLabel() -> String {
        if tier == 1 { return "\(anchorYear) 年" }
        return formatMonthLabel(anchorMonth)
    }

    private func metricLabels() -> [String] {
        if tier == 0 { return ["日均支出", "笔数", "预计月末"] }
        if tier == 1 { return ["月均支出", "笔数", "最高月"] }
        return ["月均支出", "笔数", "记录跨度"]
    }

    private func metricValues() -> [String] {
        let monthAvg = summary?.monthlyAverageCents ?? 0
        if tier == 0 {
            let total = totalCents()
            let elapsed = max(1, elapsedDaysOf(anchorMonth))
            let days = daysInMonth(year: Int(anchorMonth.prefix(4)) ?? 2026,
                                   month: Int(anchorMonth.dropFirst(5).prefix(2)) ?? 1)
            let perDay = total / elapsed
            let projected = Int((Double(total) / Double(elapsed) * Double(days)).rounded())
            return [formatYuan(perDay), "\(countOf()) 笔", formatYuan(projected)]
        }
        if tier == 1 {
            let peak = yearReport?.peakMonth
            return [formatYuan(monthAvg), "\(countOf()) 笔",
                    peak.map { formatMonthLabel($0.month) } ?? "—"]
        }
        let span = max(1, Int(((Double(summary?.recordedDays ?? 0)) / 30).rounded()))
        return [formatYuan(monthAvg), "\(countOf()) 笔", "\(span) 个月"]
    }

    /// 构成：前 4 类 + 其他（颜色走 chart 8 槽，与 Web dict.colorOf 同口径）
    private func composeRows() -> [ComposeRow] {
        var cats: [CategoryBucket] = []
        if tier == 0 {
            cats = monthReport?.categories ?? []
        } else if tier == 1 {
            cats = yearReport?.categories ?? []
        } else {
            cats = summary?.categories ?? []
        }
        let sorted = cats.filter { $0.cents > 0 }.sorted { $0.cents > $1.cents }
        var out: [ComposeRow] = sorted.prefix(4).map {
            ComposeRow(id: $0.categoryId, name: $0.name, cents: $0.cents,
                       color: chartColor(tokens, slotOf($0.color, $0.categoryId)))
        }
        let rest = sorted.dropFirst(4).reduce(0) { $0 + $1.cents }
        if rest > 0 {
            out.append(ComposeRow(id: "__rest", name: "其他", cents: rest, color: tokens.ink3))
        }
        return out
    }

    private func composeTotal() -> Int {
        composeRows().reduce(0) { $0 + $1.cents }
    }

    private func percentOf(_ cents: Int) -> Int {
        let total = composeTotal()
        return total > 0 ? Int((Double(cents) / Double(total) * 100).rounded()) : 0
    }

    private func rolling12() -> [RollingMonth] {
        monthReport?.rolling12Months ?? []
    }

    private func rolling12Max() -> Int {
        max(1, rolling12().map { $0.totalCents ?? 0 }.max() ?? 1)
    }

    /// 热力色：按占最大值比例在 surface3 → accent 之间混
    private func heatColor(_ cents: Int) -> String {
        if cents <= 0 { return tokens.surface3 }
        let ratio = min(1.0, Double(cents) / Double(rolling12Max()))
        return mixHex(tokens.accent, tokens.surface3, 0.25 + ratio * 0.75)
    }

    private func overdueCount() -> Int {
        todos.filter { $0.repaymentDate < todayKey() }.count
    }

    private func todoDotColor() -> String {
        if overdueCount() > 0 { return tokens.danger }
        if todos.contains(where: { !$0.willAutoPost }) { return tokens.warn }
        return tokens.accent
    }

    private func urgencyColorOf(_ t: DashTodo) -> String {
        switch urgencyOf(t.repaymentDate, today: todayKey()) {
        case .overdue: return tokens.danger
        case .due: return tokens.warn
        case .later: return tokens.ink3
        }
    }

    // MARK: - ① 顶卡

    private var ogHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            // hero-eyebrow：期间 Seg + period-nav
            HStack(spacing: 8) {
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

                if tier != 2 {
                    HStack(spacing: 4) {
                        chevron("‹") { shift(-1) }
                        Button {
                            calYear = Int(anchorMonth.prefix(4)) ?? 2026
                            calOpen = true
                        } label: {
                            Text(periodLabel())
                                .font(.custom(fontMonoOf(), size: 10.5))
                                .foregroundStyle(Color(css: tokens.ink2))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        chevron("›") { shift(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text("全部记录")
                        .font(.custom(fontMonoOf(), size: 10).weight(.medium))
                        .foregroundStyle(Color(css: tokens.ink2))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(css: tokens.surface2))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: tokens.line), lineWidth: 1)
                        )
                }
            }

            // 大金额 + 环比
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .bottom, spacing: 2) {
                    Text("¥")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Text(formatYuan(totalCents()).replacingOccurrences(of: "¥", with: ""))
                        .font(.custom(fontDisplayOf(isCyber), size: heroSize()).weight(.heavy))
                        .tracking(isCyber ? 0.38 : -1.33)
                        .lineLimit(1)
                        .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
                }
                if let ratio = deltaRatio() {
                    HStack(spacing: 3) {
                        Image(systemName: ratio > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9))
                        Text("\(String(format: "%.1f", abs(ratio) * 100))%")
                            .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                    }
                    .foregroundStyle(Color(css: ratio > 0 ? tokens.danger : tokens.ok))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                            .stroke(Color(css: ratio > 0 ? tokens.danger : tokens.ok), lineWidth: 1)
                    )
                }
            }

            // 三指标
            HStack(spacing: 8) {
                let labels = metricLabels()
                let values = metricValues()
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    VStack(spacing: 3) {
                        Text(label)
                            .font(.custom(fontMonoOf(), size: 9))
                            .foregroundStyle(Color(css: tokens.ink3))
                        Text(values.indices.contains(i) ? values[i] : "—")
                            .font(.custom(fontMonoOf(), size: 12).weight(.bold))
                            .foregroundStyle(Color(css: tokens.ink))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { dashed }
            .overlay(alignment: .bottom) { dashed }

            // 构成条
            if !composeRows().isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(composeRows()) { row in
                        HStack(spacing: 6) {
                            Circle().fill(Color(css: row.color)).frame(width: 6, height: 6)
                            Text(row.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(css: tokens.ink2))
                                .frame(width: 52, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(css: tokens.surface3))
                                    Capsule()
                                        .fill(Color(css: row.color))
                                        .frame(width: geo.size.width * Double(percentOf(row.cents)) / 100)
                                }
                            }
                            .frame(height: 5)
                            Text("\(percentOf(row.cents))%")
                                .font(.custom(fontMonoOf(), size: 9.5))
                                .foregroundStyle(Color(css: tokens.ink3))
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }

            // 待办
            if !todos.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button { todoOpen.toggle() } label: {
                        HStack(spacing: 8) {
                            Circle().fill(Color(css: todoDotColor())).frame(width: 6, height: 6)
                            Text("\(todos.count) 笔待处理")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color(css: tokens.ink))
                            Spacer(minLength: 0)
                            Text(todoOpen ? "⌃" : "⌄")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(css: tokens.ink3))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(css: tokens.surface2))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                    }
                    .buttonStyle(.plain)

                    if todoOpen {
                        VStack(spacing: 0) {
                            ForEach(Array(todos.enumerated()), id: \.element.id) { idx, t in
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(css: urgencyColorOf(t)))
                                        .frame(width: 4, height: 18)
                                    Text("\(t.periodSeq)期 · \(t.planName)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(css: tokens.ink))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(urgencyLabel(t.repaymentDate, today: todayKey()))
                                        .font(.custom(fontMonoOf(), size: 9.5))
                                        .foregroundStyle(Color(css: urgencyColorOf(t)))
                                }
                                .padding(.vertical, 5)
                                .overlay(alignment: .bottom) {
                                    if idx < todos.count - 1 {
                                        Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.top, 8)
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

    private func heroSize() -> CGFloat {
        let s = formatYuan(totalCents())
        if s.count <= 8 { return 34 }
        if s.count <= 10 { return 28 }
        return 22
    }

    private var dashed: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(Color(css: tokens.line))
            .frame(height: 1)
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

    private func chevron(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 15))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
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

    // MARK: - ② 月度支出热力

    private var ogHeat: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                orb("#FBBF24", "calendar")
                Text("月度支出热力")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("近 12 个月 · 点击下钻")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            // 移动端 4 列（views.css:994），gap 5
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 4), spacing: 5) {
                ForEach(rolling12()) { cell in
                    Button {
                        // 下钻：写 pickMonth，报表在 aboutToAppear 消费它
                        app.pickMonth = cell.month
                        app.screen = .report
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(Int(cell.month.dropFirst(5).prefix(2)) ?? 0)月")
                                .font(.custom(fontMonoOf(), size: 9))
                                .foregroundStyle(Color(css: tokens.ink3))
                            Text((cell.totalCents ?? 0) > 0 ? formatCompactCents(cell.totalCents ?? 0) : "—")
                                .font(.custom(fontMonoOf(), size: 10).weight(.bold))
                                .foregroundStyle(Color(css: tokens.ink))
                                .lineLimit(1)
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .fill(Color(css: heatColor(cell.totalCents ?? 0)))
                                .frame(height: 4)
                        }
                        .padding(.horizontal, 3)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(Color(css: tokens.surface2))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                .stroke(Color(css: tokens.line), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
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

    // MARK: - ③ 累计与跨度

    private var ogCum: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                orb("#34D399", "banknote")
                Text("累计与跨度")
                    .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                    .tracking(isCyber ? 1.25 : 0)
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("全部历史口径")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            VStack(spacing: 0) {
                kvRow("历史累计", formatYuan(summary?.totalCents ?? 0))
                kvRow("记录笔数", "\(summary?.count ?? 0) 笔")
                kvRow("记录跨度", "\(max(1, Int(((Double(summary?.recordedDays ?? 0)) / 30).rounded()))) 个月 · \(summary?.years.count ?? 0) 年")
                kvRow("月均支出", formatYuan(summary?.monthlyAverageCents ?? 0))
                kvRow("单笔均值", formatYuan(summary?.perExpenseAverageCents ?? 0))
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

    private func kvRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(css: tokens.ink2))
            Spacer(minLength: 0)
            Text(value)
                .font(.custom(fontMonoOf(), size: 12).weight(.medium))
                .foregroundStyle(Color(css: tokens.ink))
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color(css: tokens.line))
                .frame(height: 1)
        }
    }

    /// 悬浮圆图标（web .orb）：candy 贴纸感；cyber 切角线框
    private func orb(_ tone: String, _ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(css: tone))
            .frame(width: 26, height: 26)
            .background(Color(css: mixHex(tone, tokens.surface, 0.14)))
            .clipShape(RoundedRectangle(cornerRadius: isCyber ? 0 : 9))
            .overlay(
                RoundedRectangle(cornerRadius: isCyber ? 0 : 9)
                    .stroke(Color(css: mixHex(tone, tokens.surface, 0.45)), lineWidth: 1)
            )
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
