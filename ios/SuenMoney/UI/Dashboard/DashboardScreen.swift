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
    /// 距还款日天数（负=逾期）—— 排序用，鸿蒙 `daysUntil`
    let daysUntil: Int
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
                    .background {
                        // toast 的硬阴影：4px 4px 0 rgba(0,0,0,0.18)
                        Capsule().fill(Color(css: "rgba(0,0,0,0.18)")).offset(x: 4, y: 4)
                    }
                    .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await load() }
    }

    // MARK: - 加载

    /// 三个报表**都拉**（与鸿蒙 `load()` 同构）。
    ///
    /// 不能只拉当前档位：三块卡各自依赖不同数据源 ——
    /// 热力格要 `monthly.rolling12Months`、累计卡要 `summary`、年档指标要 `yearly`。
    /// 只拉当前档位的话，切到年档时热力格会变空（它就是靠 monthly 画的）。
    /// 单个失败置 nil、不清其他（Web 同策略）。
    private func load() async {
        loading = true
        defer { loading = false }
        errorText = ""

        var m: MonthlyReport?
        var y: YearlyReport?
        var s: SummaryReport?
        m = try? await Api.monthlyReport(month: anchorMonth).report
        y = try? await Api.yearlyReport(year: anchorYear).report
        s = try? await Api.summaryReport().report

        monthReport = m
        yearReport = y
        summary = s

        if m == nil && y == nil && s == nil {
            errorText = "报表加载失败，请检查网络后重试"
        }
        await loadTodos()
    }

    private func loadTodos() async {
        do {
            let body = try await Api.planTodos(today: todayKey())
            todos = body.todos.map {
                DashTodo(id: $0.id, planName: $0.planName, periodSeq: $0.periodSeq,
                         amountCents: $0.amountCents, repaymentDate: $0.repaymentDate,
                         willAutoPost: $0.willAutoPost,
                         daysUntil: daysUntil($0.repaymentDate, from: todayKey()))
            }
            // 逾期（负数）最前，其余按剩余天数升序
            todos.sort { $0.daysUntil < $1.daysUntil }
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

    /// 环比：**直接用服务端字段**（鸿蒙口径），不要本地重算。
    /// 本地除法在「上期为 0 但服务端给了 ratio」时会把胶囊整条吞掉。
    private func deltaRatio() -> Double? {
        if tier == 0 { return ratioOf(monthReport?.change.ratio) }
        if tier == 1 { return ratioOf(yearReport?.yearAgo?.change?.ratio) }
        return nil
    }

    private func dueTotalCents() -> Int { todos.reduce(0) { $0 + $1.amountCents } }

    private func compareLabel() -> String {
        tier == 0 ? "较上月" : (tier == 1 ? "较去年" : "较上一段")
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
            let perDay = Int((Double(total) / Double(max(1, elapsed))).rounded())
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
    /// 比例区间与鸿蒙一致：**18% 起步**（`(18 + pct*82)/100`），
    /// 不是 25% —— 最低档的色差会明显不同。
    private func heatColor(_ cents: Int) -> String {
        if cents <= 0 { return tokens.surface3 }
        let pct = min(1.0, Double(cents) / Double(rolling12Max()))
        return mixHex(tokens.accent, tokens.surface3, (18 + pct * 82) / 100)
    }

    private func overdueCount() -> Int {
        todos.filter { $0.daysUntil < 0 }.count
    }

    /// 待办动作：自动入账型 → ackTodo（只摘提醒，到期结算）；非自动 → confirmTodo（立即入账）
    private func todoAction(_ t: DashTodo, _ kind: String) async {
        do {
            if kind == "ack" {
                try await Api.ackTodo(id: t.id)
                showToast("已确认并自动入账")
            } else if kind == "confirm" {
                try await Api.confirmTodo(id: t.id)
                showToast("已手动入账")
            } else {
                try await Api.skipTodo(id: t.id)
                showToast("已忽略这笔待办")
            }
            await load()
        } catch let err as ApiError {
            showToast(err.message)
        } catch {
            showToast("操作失败，请重试")
        }
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
        // 鸿蒙是 spacing 0 + 逐段 margin（todo 10 / amount 8-4 / metrics 16 / stack 14 / legend 9）
        VStack(alignment: .leading, spacing: 0) {
            // hero-eyebrow：期间 Seg + period-nav
            HStack(spacing: 8) {
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

            // hero-todo：待办条在**大金额之上**（鸿蒙「最紧急的先说」）
            if !todos.isEmpty { todoBar }

            // 大金额 + 环比（鸿蒙 amount top 8 / bottom 4）
            VStack(alignment: .leading, spacing: 3) {
                Color.clear.frame(height: 0)
                HStack(alignment: .bottom, spacing: 4) {
                    Text("¥")
                        .font(.system(size: heroSize() * 0.5, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Text(formatYuan(totalCents()).replacingOccurrences(of: "¥", with: ""))
                        .font(.custom(fontDisplayOf(isCyber), size: heroSize()).weight(.black))
                        .tracking(isCyber ? 1.14 : -1.33)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
                }
                HStack(spacing: 8) {
                    if let ratio = deltaRatio() {
                        HStack(spacing: 3) {
                            Image(systemName: ratio > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text("\(String(format: "%.1f", abs(ratio) * 100))%")
                                .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Color(css: ratio > 0 ? tokens.danger : tokens.ok))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: ratio > 0 ? tokens.danger : tokens.ok),
                                        lineWidth: isCyber ? 1 : 1.5)
                        )
                    }
                    Text("\(compareLabel()) \(formatYuan(prevCents()))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(css: tokens.ink2))
                }
            }

            // hero-metrics：**数值在上、标签在下**（鸿蒙 metricCell）
            HStack(spacing: 10) {
                let labels = metricLabels()
                let values = metricValues()
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(values.indices.contains(i) ? values[i] : "—")
                            .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 18 : 21).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color(css: tokens.ink))
                            .lineLimit(1)
                        Text(label)
                            .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false),
                                          size: isCyber ? 9.5 : 10.5))
                            .tracking(isCyber ? 1.14 : 0.42)
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 4)
            .overlay(alignment: .top) { dashedRule }

            // 构成：一条堆叠占比条（高 9）+ 下方换行图例（鸿蒙口径）
            if !composeRows().isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(composeRows()) { row in
                                Rectangle()
                                    .fill(Color(css: row.color))
                                    .frame(width: geo.size.width * Double(row.cents) / Double(max(1, composeTotal())))
                            }
                        }
                    }
                    .frame(height: 9)
                    .background(Color(css: tokens.surface3))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                            .stroke(Color(css: tokens.line), lineWidth: 1)
                    )
                    .padding(.top, 14)

                    FlowRow(spacing: 6) {
                        ForEach(composeRows()) { row in
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(css: row.color))
                                    .frame(width: 8, height: 8)
                                Text(row.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(css: tokens.ink2))
                                Text("\(percentOf(row.cents))%")
                                    .font(.custom(fontMonoOf(), size: 11).weight(.medium))
                                    .foregroundStyle(Color(css: tokens.ink2))
                            }
                            .padding(.trailing, 8)
                        }
                    }
                    .padding(.top, 9)
                }
                .padding(.top, 14)
            }

            // 展开的待办列表在**卡片最底部**（鸿蒙位置：图例之后）
            if todoOpen && !todos.isEmpty { todoListBlock }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // candy 主卡是 2px 深墨描边（line2），不是普通卡片的浅灰 line
        .card(tokens, isCyber, radius: 16, border: isCyber ? tokens.line : tokens.line2)
    }

    /// 展开后的待办列表（独立块，位置在卡片底部）
    private var todoListBlock: some View {
        VStack(spacing: 0) {
            ForEach(Array(todos.enumerated()), id: \.element.id) { idx, t in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(css: urgencyColorOf(t)))
                        .frame(width: 4, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(t.periodSeq)期 · \(t.planName)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink))
                            .lineLimit(1)
                        // 「自动 / 需手动」是「确认 vs 入账」动作的依据
                        Text(t.willAutoPost ? "自动" : "需手动")
                            .font(.custom(fontMonoOf(), size: 10).weight(.bold))
                            .foregroundStyle(Color(css: urgencyColorOf(t)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(formatYuan(t.amountCents))
                        .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color(css: tokens.ink))

                    Button {
                        Task { await todoAction(t, t.willAutoPost ? "ack" : "confirm") }
                    } label: {
                        Text(t.willAutoPost ? "确认" : "入账")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.accentInk))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .background(Color(css: tokens.accent))
                            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                    .stroke(Color(css: isCyber ? tokens.line : "transparent"), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("忽略本期") { Task { await todoAction(t, "skip") } }
                    } label: {
                        Text("更多")
                            .font(.custom(fontMonoOf(), size: 11))
                            .foregroundStyle(Color(css: tokens.ink3))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                    .stroke(Color(css: tokens.line), lineWidth: 1)
                            )
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    if idx < todos.count - 1 {
                        Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .padding(.top, 4)
    }

    /// hero-todo 提醒条：圆点 + 「N 笔待办」+ 合计金额 + 「N 笔逾期」+ 展开箭头
    private var todoBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(appCurveFast) { todoOpen.toggle() } } label: {
                HStack(spacing: 8) {
                    Circle().fill(Color(css: todoDotColor())).frame(width: 6, height: 6)
                    Text("\(todos.count) 笔待办")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(css: tokens.ink))
                    Text(formatYuan(dueTotalCents()))
                        .font(.custom(fontMonoOf(), size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Color(css: tokens.ink2))
                    if overdueCount() > 0 {
                        Text("\(overdueCount()) 笔逾期")
                            .font(.custom(fontMonoOf(), size: 10).weight(.bold))
                            .foregroundStyle(Color(css: tokens.danger))
                    }
                    Spacer(minLength: 0)
                    Text(todoOpen ? "⌃" : "⌄")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(css: tokens.ink2))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(css: tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

        }
        .padding(.top, 10)
    }

    private func heroSize() -> CGFloat {
        let s = formatYuan(totalCents())
        if s.count <= 8 { return 34 }
        if s.count <= 10 { return 28 }
        return 22
    }

    /// 真虚线（鸿蒙 BorderStyle.Dashed）。用 Path 画，不能用「实心矩形 + 虚线描边」叠。
    private var dashedRule: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0.5))
            p.addLine(to: CGPoint(x: 10_000, y: 0.5))
        }
        .stroke(Color(css: tokens.line), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(height: 1)
    }

    private func segButton(_ title: String, _ value: Int) -> some View {
        Button {
            // 切到年档时锚点归到该年 1 月（鸿蒙 `switchTier(1)`）
            applyPeriod(value == 1 ? "\(anchorYear)-01" : anchorMonth, value)
        } label: {
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10.5 : 12).weight(.bold))
                .foregroundStyle(Color(css: tier == value
                                       ? (isCyber ? tokens.accent : tokens.accentInk)
                                       : tokens.ink2))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(tier == value
                            ? (isCyber ? Color(css: tokens.accent).opacity(0.1) : Color(css: tokens.accent))
                            : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tier == value && !isCyber ? tokens.line2 : "transparent"),
                                lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    /// 期间箭头 30×30（鸿蒙 `periodChevron`），candy 有 surface 底 + 描边
    private func chevron(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 16))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 30, height: 30)
                .background(Color(css: isCyber ? "transparent" : tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )
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
                        .padding(.top, 7)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color(css: tokens.surface2))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 7)))
                        .overlay(
                            // 当月格高亮：candy line2 描边、cyber accent 描边
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 7))
                                .stroke(Color(css: cell.month == currentMonthKey()
                                              ? (isCyber ? tokens.accent : tokens.line2)
                                              : tokens.line),
                                        lineWidth: 1)
                        )
                        .background {
                            if cell.month == currentMonthKey() && !isCyber {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(css: tokens.line2)).offset(x: 2, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // footer：近 12 个月合计 + 打开报表（鸿蒙有，iOS 之前整块缺失）
            HStack(spacing: 10) {
                Text("近 12 个月合计")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink2))
                Text(formatYuan(rolling12Total()))
                    .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Button { app.screen = .report } label: {
                    Text("打开报表")
                        .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: 11.5).weight(.bold))
                        .foregroundStyle(Color(css: tokens.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { dashedRule }
            .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tokens, isCyber, radius: 16)
    }

    private func rolling12Total() -> Int {
        rolling12().reduce(0) { $0 + ($1.totalCents ?? 0) }
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
        .card(tokens, isCyber, radius: 16)
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
    /// 悬浮圆图标（鸿蒙 `.orb`）：34×34、图标 16。
    /// candy：**实色底（tone）+ 2px line2 描边 + 2px 硬阴影**；
    /// cyber：透明底 + 1px accent 描边 + 绿色外发光。
    private func orb(_ tone: String, _ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCyber ? 1 : 17)
        return Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.line2))
            .frame(width: 34, height: 34)
            .background(shape.fill(Color(css: isCyber ? "transparent" : tone)))
            .overlay(
                shape.stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                             lineWidth: isCyber ? 1 : 2)
            )
            .background {
                if !isCyber {
                    shape.fill(Color(css: tokens.line2)).offset(x: 2, y: 2)
                }
            }
            .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.4)") : .clear,
                    radius: isCyber ? 5 : 0, x: 0, y: isCyber ? -2 : 0)
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
            .card(tokens, isCyber, radius: 16, surface: tokens.bg, shadow: false)
        }
    }
}
