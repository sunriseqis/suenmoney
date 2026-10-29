//
//  LedgerScreen.swift
//  SuenMoney
//
//  流水页（对应鸿蒙 `components/ledger/LedgerScreen.ets`，2031 行）。
//
//  结构（自上而下）：
//    topHero      眉标 + 大金额 + 环比 + 三事实 + 三入口 + 待办提醒条（可展开）
//    toolbarCard  搜索框（点开高级区：档位 / 期间 / 筛选 / 排序）
//    monthCard    月档：日期分组（今日/昨日/N日 + 日小计）+ 行卡 + 加载更多 / 查看上月
//    yearCard     年档：12 个月格（3 列）+ 点格下钻
//    allCard      全部档：一年一格 + 点格下钻
//
//  两个入口：下拉手势（阈值 60vp，须已在顶部）+ 各屏「记一笔」按钮投递的 createRequest。
//
//  ⚠ iOS 与鸿蒙的差异：
//    - 弹层：`bindSheet` → `.sheet` + `.presentationDetents`
//    - 手势：`PanGesture` → `DragGesture`
//    - 震动：`vibrator` → `UIImpactFeedbackGenerator`
//    - 滚动位置判定：`scroller.currentOffset()` → `ScrollView` + `.onScrollGeometryChange`
//      这里用一个顶部哨兵视图的可见性近似（更稳，不依赖 iOS 18 API）
//

import SwiftUI

// MARK: - 视图模型

struct HeroTodo: Identifiable {
    let id: String
    let planName: String
    let periodSeq: Int
    let amountCents: Int
    let willAutoPost: Bool
    /// 距还款日天数（负=逾期）
    let daysUntil: Int
    /// "pending" 待处理；"skipped" 曾被忽略、现已逾期重现
    let status: String
}

struct LedgerDayGroup: Identifiable {
    let date: String
    let cents: Int
    let rows: [ExpenseItem]

    var id: String { date }
}

public struct LedgerScreen: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var app
    @Environment(NetworkMonitor.self) private var network

    // 档位与锚点
    @State private var tier: Int = 0
    @State private var anchorMonth: String = currentMonthKey()
    @State private var anchorYear: String = String(currentMonthKey().prefix(4))

    // 列表
    @State private var rows: [ExpenseItem] = []
    @State private var monthTotalCents: Int = 0
    @State private var monthCount: Int = 0
    @State private var cursor: String = ""
    @State private var hasMore: Bool = false
    @State private var loading: Bool = false
    @State private var offline: Bool = false

    // 顶卡
    @State private var prevTotalCents: Int = -1
    @State private var creditDueCents: Int = 0
    @State private var heroTodos: [HeroTodo] = []
    @State private var todoOpen: Bool = false
    @State private var highlightId: String = ""

    // 年档 / 全部档
    @State private var yearPoints: [MonthPoint] = []
    @State private var yearTotalCents: Int = 0
    @State private var allYears: [YearPoint] = []
    @State private var allTotalCents: Int = 0

    // 字典
    @State private var categoryNames: [String: CachedCategory] = [:]
    @State private var paymentNames: [String: String] = [:]

    // 搜索与筛选
    @State private var keyword: String = ""
    @State private var filterCategory: String = ""
    @State private var filterPayment: String = ""
    @State private var filterOwner: String = ""
    @State private var sortMode: Int = 0
    @State private var advOpen: Bool = false
    @State private var showFilters: Bool = false
    @State private var rootCategories: [CachedCategory] = []
    @State private var paymentOptions: [CachedCategory] = []
    @State private var ownerOptions: [CachedCategory] = []

    // 抽屉
    @State private var sheetOpen: Bool = false
    @State private var editingRow: ExpenseItem?

    // 期间月历
    @State private var calOpen: Bool = false
    @State private var calYear: Int = Int(currentMonthKey().prefix(4)) ?? 2026

    // 下拉
    @State private var pullProgress: CGFloat = 0
    @State private var atTop: Bool = true
    /// 搜索防抖任务（每次输入取消上一个，避免并发请求乱序覆盖）
    @State private var searchTask: Task<Void, Never>?

    // 提示
    @State private var toastText: String = ""
    @State private var errorText: String = ""
    @State private var pendingSync: Int = 0

    @FocusState private var searchFocused: Bool

    /// 分页大小：与鸿蒙 `PAGE_SIZE = 100` 一致
    private static let pageSize = 100

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    // MARK: - 生命周期

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 顶部哨兵：可见即「已在顶部」（下拉手势的前置条件）
                    Color.clear.frame(height: 0)
                        .onAppear { atTop = true }
                        .onDisappear { atTop = false }

                    topHero
                    toolbarCard
                    if tier == 0 {
                        monthCard
                    } else if tier == 1 {
                        yearCard
                    } else {
                        allCard
                    }
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.danger))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 8)
                // 内容比视口短时（空月份/空年份很常见），ScrollView 会把内容**垂直居中**
                // → 切档/切屏就整页上下跳。给一个「至少占满视口」的下限，永远从顶部开始。
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)

            // 下拉指示器：撑满高度的透明命中层 + 顶对齐（不能挡住列表点击）
            VStack {
                pullIndicator
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            // 期间快选月历
            if calOpen {
                periodCalendar
            }

            // 轻提示（web .toast）：底部居中、2 秒消失
            if !toastText.isEmpty {
                Text(toastText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(css: tokens.bg))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(css: tokens.ink))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                            .stroke(Color(css: tokens.line2), lineWidth: 2)
                    )
                    .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
        .onChange(of: app.createRequest) { _, _ in
            editingRow = nil
            sheetOpen = true
        }
        .gesture(pullGesture)
        .sheet(isPresented: $sheetOpen) {
            ExpenseEditor(editing: editingRow) { savedId in
                sheetOpen = false
                highlightId = savedId
                Task {
                    await reload()
                    // 高亮 1.6s 后淡出（与 Web 同）
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    highlightId = ""
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(isCyber ? 0 : 22)
        }
    }

    // MARK: - 数据加载

    private func reload() async {
        errorText = ""
        loading = true
        defer { loading = false }
        do {
            if categoryNames.isEmpty {
                let cats = try await Api.categories()
                try DictionaryDao.cacheCategories(cats.categories)
                categoryNames = try DictionaryDao.categoryNames()
                let pays = try await Api.paymentMethods()
                try DictionaryDao.cachePayments(pays.paymentMethods)
                paymentNames = try DictionaryDao.paymentNames()

                // 筛选项：分类只列一级（二级归属一级，列出来会重复）；支付列全部；记录人取 users
                rootCategories = categoryNames.values
                    .filter { $0.parentId.isEmpty }
                    .sorted { $0.name < $1.name }
                paymentOptions = pays.paymentMethods.filter { $0.isEnabled }.map {
                    CachedCategory(id: $0.id, name: $0.name, icon: $0.icon, color: "", parentId: "")
                }
                let users = try await Api.users()
                ownerOptions = users.users.map {
                    CachedCategory(id: $0.id, name: $0.displayName, icon: "", color: "", parentId: "")
                }
            }
            offline = false
            await loadTier()
            await loadHeroTodos()
        } catch let err as ApiError {
            if err.kind == .network {
                // 离线 A 档：本地现算
                offline = true
                if categoryNames.isEmpty {
                    categoryNames = (try? DictionaryDao.categoryNames()) ?? [:]
                    paymentNames = (try? DictionaryDao.paymentNames()) ?? [:]
                }
                await loadTier()
                await loadHeroTodos()
            } else {
                errorText = err.message
            }
        } catch {
            errorText = "加载失败"
        }
    }

    private func loadTier() async {
        switch tier {
        case 0: await loadMonth(reset: true)
        case 1: await loadYear()
        default: await loadAll()
        }
    }

    private func loadMonth(reset: Bool) async {
        if offline {
            // 离线：从本地按还款日取数现算
            let local = (try? ExpenseDao.byMonth(anchorMonth)) ?? []
            let total = (try? ExpenseDao.monthTotal(anchorMonth)) ?? LocalMonthTotal(totalCents: 0, count: 0)
            rows = applyLocalFilters(local)
            monthTotalCents = total.totalCents
            monthCount = total.count
            prevTotalCents = 0
            hasMore = false
            return
        }
        do {
            let page = try await Api.expenses(
                month: anchorMonth,
                limit: Self.pageSize,
                cursor: reset ? nil : cursor,
                q: keyword.trimmingCharacters(in: .whitespaces),
                categoryId: filterCategory,
                paymentMethodId: filterPayment,
                ownerId: filterOwner
            )
            try ExpenseDao.cache(page.items)
            rows = reset ? page.items : rows + page.items
            cursor = page.nextCursor ?? ""
            hasMore = page.hasMore

            let report = try await Api.monthlyReport(month: anchorMonth)
            monthTotalCents = report.report.totalCents
            monthCount = report.report.count
            prevTotalCents = report.report.previous.totalCents
            // 本月要还：信用卡类支付方式的还款额（服务端月报已给）
            creditDueCents = report.report.paymentMethods
                .filter { $0.type == "credit" }
                .reduce(0) { $0 + $1.cents }
        } catch let err as ApiError {
            if err.kind == .network {
                offline = true
                await loadMonth(reset: reset)
            } else {
                errorText = err.message
            }
        } catch {
            errorText = "加载失败"
        }
    }

    private func loadYear() async {
        do {
            let body = try await Api.yearlyReport(year: anchorYear)
            yearPoints = body.report.months
            yearTotalCents = body.report.totalCents
            // 年档的「上期」= 去年；不设的话环比会拿月档的上期算
            prevTotalCents = body.report.yearAgo?.totalCents ?? 0
        } catch let err as ApiError {
            if err.kind == .network { offline = true }
            errorText = err.kind == .network ? "" : err.message
        } catch {}
    }

    private func loadAll() async {
        do {
            let body = try await Api.summaryReport()
            allYears = body.report.years
            allTotalCents = body.report.totalCents
            // 全部档没有「上期」，环比胶囊不显示
            prevTotalCents = 0
        } catch let err as ApiError {
            if err.kind == .network { offline = true }
            errorText = err.kind == .network ? "" : err.message
        } catch {}
    }

    /// 提醒列表（**只取该提醒的期次**，不是所有待办）
    private func loadHeroTodos() async {
        do {
            let body = try await Api.planTodos(today: todayKey())
            var list: [HeroTodo] = body.todos.map { t in
                HeroTodo(
                    id: t.id,
                    planName: t.planName,
                    periodSeq: t.periodSeq,
                    amountCents: t.amountCents,
                    willAutoPost: t.willAutoPost,
                    daysUntil: daysUntil(t.repaymentDate, from: todayKey()),
                    status: t.status
                )
            }
            // 按紧急度排序 —— 逾期最前，其余按剩余天数升序
            list.sort { $0.daysUntil < $1.daysUntil }
            heroTodos = list
        } catch {
            heroTodos = []
        }
    }

    // MARK: - 待办动作

    /// 逾期：还款日已过（含被忽略后重现的期次）
    private func todoOverdue(_ t: HeroTodo) -> Bool {
        t.status == "skipped" || t.daysUntil < 0
    }

    /// 待办标签：逾期 / 今天 / 还有N天
    private func todoTag(_ t: HeroTodo) -> String {
        if todoOverdue(t) {
            return t.daysUntil < 0 ? "逾期 \(-t.daysUntil) 天" : "逾期"
        }
        if t.daysUntil == 0 { return "今天" }
        return t.willAutoPost ? "自动 · 还有 \(t.daysUntil) 天" : "还有 \(t.daysUntil) 天"
    }

    /// 「处理」= 立即入账（两种计划同一条路）
    private func processTodo(_ t: HeroTodo) async {
        do {
            try await Api.confirmTodo(id: t.id)
            showToast("已入账")
            await loadHeroTodos()
            await loadTier()
        } catch let err as ApiError {
            showToast(err.message)
        } catch { showToast("操作失败") }
    }

    /// 「忽略」：自动入账 → 只摘提醒（到期仍入账）；非自动 → 本期不提醒也不入账
    private func ignoreTodo(_ t: HeroTodo) async {
        do {
            if t.willAutoPost {
                try await Api.ackTodo(id: t.id)
                showToast("已忽略提醒，到期自动入账")
            } else {
                try await Api.skipTodo(id: t.id)
                showToast("已忽略本期，不会入账")
            }
            await loadHeroTodos()
        } catch let err as ApiError {
            showToast(err.message)
        } catch { showToast("操作失败") }
    }

    private func showToast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toastText == text { toastText = "" }
        }
    }

    // MARK: - 派生值

    /// 当前档位的合计（月档取月报、年档取年报、全部档取汇总）
    private func periodTotalCents() -> Int {
        if tier == 0 { return monthTotalCents }
        if tier == 1 { return yearTotalCents }
        return allTotalCents
    }

    private func applyLocalFilters(_ source: [ExpenseItem]) -> [ExpenseItem] {
        let q = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        return source.filter { row in
            if !q.isEmpty {
                let name = categoryNameOf(row).lowercased()
                if !row.note.lowercased().contains(q) && !name.contains(q) { return false }
            }
            if !filterCategory.isEmpty {
                // 筛选项只列一级分类，但记录可能挂在**二级**分类上 →
                // 必须把二级归到它的父级再比，否则选了一级分类却筛不出二级的记录
                var rootId = row.categoryId
                if let cat = categoryNames[row.categoryId], !cat.parentId.isEmpty {
                    rootId = cat.parentId
                }
                if rootId != filterCategory { return false }
            }
            if !filterPayment.isEmpty && row.paymentMethodId != filterPayment { return false }
            if !filterOwner.isEmpty && row.ownerId != filterOwner { return false }
            return true
        }
    }

    /// 排序后的行（与 Web `sortedItems` / 鸿蒙 `sortedRows` 同规则）
    ///
    /// 按日期时：**同日按 id 倒序** —— 同一天多笔的先后不该随刷新抖动。
    /// 按金额时：金额倒序（退款是负数，按原值比而不是绝对值 —— 鸿蒙就是这么比的）。
    private func sortedRows() -> [ExpenseItem] {
        if sortMode == 1 {
            return rows.sorted { $0.amountCents > $1.amountCents }
        }
        return rows.sorted { a, b in
            if a.spendDate == b.spendDate {
                return a.id > b.id
            }
            return a.spendDate > b.spendDate
        }
    }

    private func dayGroups() -> [LedgerDayGroup] {
        var groups: [LedgerDayGroup] = []
        var index: [String: Int] = [:]
        for row in sortedRows() {
            if let hit = index[row.spendDate] {
                let g = groups[hit]
                groups[hit] = LedgerDayGroup(date: g.date, cents: g.cents + row.amountCents, rows: g.rows + [row])
            } else {
                index[row.spendDate] = groups.count
                groups.append(LedgerDayGroup(date: row.spendDate, cents: row.amountCents, rows: [row]))
            }
        }
        return groups
    }

    /// 组头日期文案（Web formatLedgerDate.dayText）：今日 / 昨日 / N日
    private func dayTextOf(_ date: String) -> String {
        if date == todayKey() { return "今日" }
        if date == yesterdayKey() { return "昨日" }
        return "\(Int(date.dropFirst(8).prefix(2)) ?? 0)日"
    }

    private func categoryNameOf(_ row: ExpenseItem) -> String {
        if !row.categoryName.isEmpty { return row.categoryName }
        return categoryNames[row.categoryId]?.name ?? "—"
    }

    private func categoryColorOf(_ row: ExpenseItem) -> String {
        let explicit = categoryNames[row.categoryId]?.color ?? row.categoryColor
        return categoryColorOf(categoryNameOf(row), explicit)
    }

    /// 期次文案（`3期`），非计划来源返回空串
    private func periodSeqOf(_ row: ExpenseItem) -> String {
        guard row.source == "plan", let seq = row.planPeriodSeq else { return "" }
        return "\(seq)期"
    }

    private func paymentNameOf(_ row: ExpenseItem) -> String {
        if !row.paymentMethodName.isEmpty { return row.paymentMethodName }
        return paymentNames[row.paymentMethodId] ?? "—"
    }

    private func heroAmountSize() -> CGFloat {
        let s = formatYuan(periodTotalCents())
        if s.count <= 8 { return 34 }
        if s.count <= 10 { return 28 }
        return 22
    }

    private func deltaRatio() -> Double? {
        guard prevTotalCents > 0 else { return nil }
        return Double(periodTotalCents() - prevTotalCents) / Double(prevTotalCents)
    }

    /// 日均：**期间总额 / 今天是几号**（与鸿蒙 `perDayCents` 同义）
    ///
    /// 注意不是 `elapsedDaysOf(anchorMonth)` —— 那是概况页的口径（按月算已过天数）。
    /// 流水页顶卡看的是「这个月到今天的日均」，翻到历史月时仍除以今天的日号。
    private func perDayCents() -> Int {
        let day = Calendar.current.component(.day, from: Date())
        return day > 0 ? Int((Double(periodTotalCents()) / Double(day)).rounded()) : 0
    }

    private func periodLabel() -> String {
        if tier == 1 { return "\(anchorYear) 年" }
        if tier == 2 { return "全部" }
        return formatMonthLabel(anchorMonth)
    }

    private func overdueCount() -> Int {
        heroTodos.filter { todoOverdue($0) }.count
    }

    /// 待办条圆点颜色：有逾期→danger；有需手动→warn；否则 accent
    private func todoDotColor() -> String {
        if overdueCount() > 0 { return tokens.danger }
        if heroTodos.contains(where: { !$0.willAutoPost }) { return tokens.warn }
        return tokens.accent
    }

    private func activeFilterCount() -> Int {
        var n = 0
        if !filterCategory.isEmpty { n += 1 }
        if !filterPayment.isEmpty { n += 1 }
        if !filterOwner.isEmpty { n += 1 }
        return n
    }

    private func yearCellMax() -> Int {
        max(1, yearPoints.map { $0.totalCents }.max() ?? 1)
    }

    private func allCellMax() -> Int {
        max(1, allYears.map { $0.totalCents }.max() ?? 1)
    }

    // MARK: - 档位与期间

    private func switchTier(_ v: Int) {
        guard tier != v else { return }
        tier = v
        if v == 1 {
            // Web switchTier('year')：锚点落到该年 1 月
            anchorYear = String(anchorMonth.prefix(4))
            anchorMonth = "\(anchorYear)-01"
        }
        // 显式加载：不用 onChange(tier)+onChange(anchorMonth) 双订阅 ——
        // 那样切到年档会触发两次（先旧档位、再新档位），列表会闪一下
        Task { await loadTier() }
    }

    private func shiftPeriod(_ delta: Int) {
        if tier == 0 {
            anchorMonth = shiftMonth(anchorMonth, delta)
            Task { await loadMonth(reset: true) }
            return
        }
        if tier == 1 {
            anchorYear = String((Int(anchorYear) ?? 2026) + delta)
            anchorMonth = "\(anchorYear)-01"
            Task { await loadYear() }
        }
    }

    private func applyPeriod(_ month: String, _ newTier: Int) {
        anchorMonth = month
        anchorYear = String(month.prefix(4))
        tier = newTier
        calOpen = false
        Task { await loadTier() }
    }

    private func clearFilters() {
        filterCategory = ""
        filterPayment = ""
        filterOwner = ""
        Task { await loadMonth(reset: true) }
    }

    // MARK: - 下拉手势

    private var pullGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard atTop, value.translation.height > 0 else { return }
                let p = min(1, value.translation.height / 60)
                if abs(p - pullProgress) > 0.02 { pullProgress = p }
            }
            .onEnded { value in
                let hit = atTop && value.translation.height > 60
                if hit {
                    withAnimation(.easeOut(duration: 0.12)) { pullProgress = 1 }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
                        editingRow = nil
                        sheetOpen = true
                        withAnimation(.easeOut(duration: 0.16)) { pullProgress = 0 }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.16)) { pullProgress = 0 }
                }
            }
    }

    // MARK: - 顶卡

    private var topHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            // mh-head：眉标 + 大金额 + 环比胶囊
            VStack(alignment: .leading, spacing: 3) {
                Text("\(formatMonthLabel(anchorMonth)) · 本月支出")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.33)
                    .foregroundStyle(Color(css: tokens.ink3))
                HStack(alignment: .bottom, spacing: 2) {
                    Text("¥")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Text(formatYuan(periodTotalCents()).replacingOccurrences(of: "¥", with: ""))
                        .font(.custom(fontDisplayOf(isCyber), size: heroAmountSize()).weight(.heavy))
                        .tracking(isCyber ? 0.38 : -1.33)
                        .lineLimit(1)
                        .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
                }
                if let ratio = deltaRatio() {
                    // delta-pill：文本即语义色（涨=红跌=绿），描边跟文本走
                    Text("\(String(format: "%.1f", ratio * 100))%")
                        .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
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
            .frame(maxWidth: .infinity, alignment: .leading)

            // mh-facts：三事实，上下虚线
            HStack(spacing: 8) {
                heroFact("日均", formatYuan(perDayCents()))
                heroFact("笔数", "\(monthCount) 笔")
                heroFact("本月要还", formatYuan(creditDueCents))
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { dashedLine }
            .overlay(alignment: .bottom) { dashedLine }

            // mh-nav：三入口小按钮
            HStack(spacing: 6) {
                navButton("概况") { app.screen = .dashboard }
                navButton("报表") { app.screen = .report }
                navButton("设置") { app.screen = .settings }
            }

            // hero-todo：待办提醒条（无待办整条不渲染）
            if !heroTodos.isEmpty {
                todoSection
            }
        }
        .padding(14)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 20)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 20))
                .stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                        lineWidth: isCyber ? 1 : 2)
                .opacity(isCyber ? 0.45 : 1)
        )
        .shadow(color: Color(css: cardShadow(tokens, isCyber).color),
                radius: cardShadow(tokens, isCyber).radius / 2,
                x: cardShadow(tokens, isCyber).offsetX,
                y: cardShadow(tokens, isCyber).offsetY)
    }

    private var dashedLine: some View {
        Rectangle()
            .fill(Color(css: tokens.line))
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(css: tokens.line))
            )
    }

    private func heroFact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.custom(fontMonoOf(), size: 9))
                .foregroundStyle(Color(css: tokens.ink3))
            Text(value)
                .font(.custom(fontMonoOf(), size: 11).weight(.bold))
                .foregroundStyle(Color(css: tokens.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func navButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10 : 11.5).weight(.bold))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color(css: tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )
        }
    }

    // MARK: 待办区

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 收起态只给条数 + 箭头（用户 2026-10-29 裁决：金额/逾期数都去掉）
            Button {
                todoOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(css: todoDotColor()))
                        .frame(width: 6, height: 6)
                    Text("\(heroTodos.count) 笔待处理")
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
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // 展开后的待办（每行：上行信息 / 下行金额 + 按钮）
            if todoOpen {
                VStack(spacing: 0) {
                    ForEach(Array(heroTodos.enumerated()), id: \.element.id) { idx, t in
                        todoRow(t, isLast: idx == heroTodos.count - 1)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.top, 10)
    }

    private func todoRow(_ t: HeroTodo, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(css: todoOverdue(t) ? tokens.danger
                                  : (t.willAutoPost ? tokens.warn : tokens.accent)))
                    .frame(width: 4, height: 18)
                Text("\(t.periodSeq)期 · \(t.planName)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(todoTag(t))
                    .font(.custom(fontMonoOf(), size: 9.5).weight(.bold))
                    .foregroundStyle(Color(css: todoOverdue(t) ? tokens.danger
                                          : (t.willAutoPost ? tokens.warn : tokens.ink3)))
            }
            HStack(spacing: 8) {
                Text(formatYuan(t.amountCents))
                    .font(.custom(fontMonoOf(), size: 11).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                // 逾期只给「入账」：已经拖过一次，再给忽略等于无限延期
                if !todoOverdue(t) {
                    pillButton("忽略", filled: false) { Task { await ignoreTodo(t) } }
                }
                pillButton(todoOverdue(t) ? "入账" : "处理", filled: true) {
                    Task { await processTodo(t) }
                }
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
            }
        }
    }

    private func pillButton(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: filled ? .bold : .regular))
                .foregroundStyle(Color(css: filled ? tokens.accentInk : tokens.ink2))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(filled ? Color(css: tokens.accent) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(filled ? Color.clear : Color(css: tokens.line), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 工具栏

    private var toolbarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(css: tokens.ink3))
                    TextField("搜索备注或分类", text: $keyword)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(css: tokens.ink))
                        .focused($searchFocused)
                        .onSubmit { Task { await loadMonth(reset: true) } }
                        .onChange(of: keyword) { _, _ in
                            // 取消上一个防抖任务：不取消的话每敲一个字都排一个请求，
                            // 先发的可能后到，列表会被旧结果覆盖
                            searchTask?.cancel()
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                guard !Task.isCancelled else { return }
                                await loadMonth(reset: true)
                            }
                        }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Color(css: isCyber ? tokens.surface2 : tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                        .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                )

                Button {
                    withAnimation(.easeOut(duration: 0.2)) { advOpen.toggle() }
                } label: {
                    Text(advOpen ? "收起" : "筛选")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Color(css: tokens.surface))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                        )
                }
                .buttonStyle(.plain)
            }

            if advOpen {
                advancedArea
            }
        }
        .padding(14)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private var advancedArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 档位 Seg
            HStack(spacing: 4) {
                segButton("按月", tier == 0) { switchTier(0) }
                segButton("按年", tier == 1) { switchTier(1) }
                segButton("全部", tier == 2) { switchTier(2) }
            }

            // 期间导航
            HStack(spacing: 8) {
                chevronButton("‹") { shiftPeriod(-1) }
                Button {
                    calYear = Int(anchorMonth.prefix(4)) ?? 2026
                    calOpen = true
                } label: {
                    Text(periodLabel())
                        .font(.custom(fontDisplayOf(isCyber), size: 13).weight(.bold))
                        .foregroundStyle(Color(css: tokens.ink))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                chevronButton("›") { shiftPeriod(1) }
            }

            // 筛选
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showFilters.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(activeFilterCount() > 0 ? "筛选 · \(activeFilterCount())" : "筛选")
                        .font(.system(size: 11.5, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color(css: tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showFilters {
                filterGroup("分类", rootCategories, filterCategory) { id in
                    filterCategory = filterCategory == id ? "" : id
                    Task { await loadMonth(reset: true) }
                }
                filterGroup("支付", paymentOptions, filterPayment) { id in
                    filterPayment = filterPayment == id ? "" : id
                    Task { await loadMonth(reset: true) }
                }
                filterGroup("记录人", ownerOptions, filterOwner) { id in
                    filterOwner = filterOwner == id ? "" : id
                    Task { await loadMonth(reset: true) }
                }
                if activeFilterCount() > 0 {
                    Button { clearFilters() } label: {
                        Text("清除")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.danger))
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 排序
            HStack(spacing: 4) {
                segButton("按日期", sortMode == 0) { sortMode = 0 }
                segButton("按金额", sortMode == 1) { sortMode = 1 }
            }
        }
    }

    private func segButton(_ title: String, _ active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10.5 : 12).weight(.bold))
                .foregroundStyle(Color(css: active
                                       ? (isCyber ? tokens.accent : tokens.accentInk)
                                       : tokens.ink2))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(active
                            ? Color(css: isCyber ? tokens.accent.opacity(0.1) : tokens.accent)
                            : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(active && !isCyber ? Color(css: tokens.line2) : Color.clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

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
        .opacity(tier == 2 ? 0.45 : 1)
        .disabled(tier == 2)
    }

    private func filterGroup(_ label: String, _ options: [CachedCategory], _ selected: String,
                             _ onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(css: tokens.ink3))
            FlowRow(spacing: 6) {
                chipButton("全部", selected.isEmpty) { onPick("") }
                ForEach(options, id: \.id) { opt in
                    chipButton(opt.name, selected == opt.id) { onPick(opt.id) }
                }
            }
        }
    }

    private func chipButton(_ title: String, _ active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10 : 11.5))
                .foregroundStyle(Color(css: active
                                       ? (isCyber ? tokens.accent : tokens.onColor)
                                       : tokens.ink2))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(active
                            ? Color(css: isCyber ? tokens.accent.opacity(0.1) : tokens.amber)
                            : Color(css: isCyber ? tokens.surface2 : tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: active && isCyber ? tokens.accent : tokens.line),
                                lineWidth: isCyber ? 1 : 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 月档

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("流水明细")
                    .font(.custom(fontDisplayOf(isCyber), size: 15).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("\(rows.count) 笔 · 合计 \(formatYuan(monthTotalCents))")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            if rows.isEmpty && !loading {
                Text(offline ? "离线：本月没有缓存记录" : "本月还没有记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
            } else {
                ForEach(dayGroups()) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        // date-cap：组头（今日/昨日/N日 + 日小计）
                        HStack(spacing: 8) {
                            Text(dayTextOf(group.date))
                                .font(.custom(fontMonoOf(), size: 9.5).weight(.bold))
                                .foregroundStyle(Color(css: tokens.ink3))
                            Spacer(minLength: 0)
                            Text(formatYuan(group.cents))
                                .font(.custom(fontMonoOf(), size: 9.5))
                                .foregroundStyle(Color(css: tokens.ink3))
                        }
                        .padding(.vertical, 6)

                        ForEach(group.rows) { row in
                            expenseRow(row)
                        }
                    }
                }

                // 列表底部：有更多 → 加载更多；否则 → 查看上月
                if hasMore {
                    Button {
                        Task { await loadMonth(reset: false) }
                    } label: {
                        Text("加载更多")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        shiftPeriod(-1)
                    } label: {
                        Text("‹ 查看上月")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink3))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    /// 流水行：第一行 分类 + 标题(note) + 归属；第二行 支付 · 期数；右侧金额
    private func expenseRow(_ row: ExpenseItem) -> some View {
        HStack(spacing: 10) {
            CatIconView(catName: categoryNameOf(row), iconSize: 19, color: categoryColorOf(row))
                .frame(width: 34, height: 34)
                .background(Color(css: mixHex(categoryColorOf(row), tokens.surface, 0.12)))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color(css: mixHex(categoryColorOf(row), tokens.surface, 0.45)), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(categoryNameOf(row))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(css: tokens.ink))
                        .lineLimit(1)
                    if row.amountCents < 0 {
                        Text("退款")
                            .font(.custom(fontMonoOf(), size: 10).weight(.medium))
                            .foregroundStyle(Color(css: tokens.danger))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                    .stroke(Color(css: tokens.danger), lineWidth: 1)
                            )
                    }
                    if !row.note.isEmpty {
                        Text(row.note)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text(row.ownerName.isEmpty ? "—" : row.ownerName)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(paymentNameOf(row))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                        .lineLimit(1)
                    if !periodSeqOf(row).isEmpty {
                        Text("·").font(.system(size: 10)).foregroundStyle(Color(css: tokens.ink3))
                        Text(periodSeqOf(row))
                            .font(.custom(fontMonoOf(), size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatYuan(row.amountCents))
                    .font(.custom(fontMonoOf(), size: 13).weight(.medium))
                    .foregroundStyle(Color(css: row.amountCents < 0 ? tokens.ok : tokens.ink))
                Text(row.paymentMethodType == "credit"
                     ? "\(String(row.repaymentDate.dropFirst(5))) 还"
                     : "即时")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink2))
            }
        }
        .padding(10)
        .background(highlightId == row.id
                    ? Color(css: mixHex(tokens.accent, tokens.surface, 0.14))
                    : Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                .stroke(Color(css: tokens.line), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editingRow = row
            sheetOpen = true
        }
    }

    // MARK: - 年档

    private var yearCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(anchorYear) 年")
                    .font(.custom(fontDisplayOf(isCyber), size: 15).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("合计 \(formatYuan(yearTotalCents))")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(yearPoints) { point in
                    monthCell(point)
                }
            }
        }
        .padding(14)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func monthCell(_ point: MonthPoint) -> some View {
        let isCurrent = point.month == currentMonthKey()
        let pct = Double(point.totalCents) / Double(yearCellMax())
        return Button {
            // 下钻：点年格 → 切到该月的月档
            applyPeriod(point.month, 0)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("\(Int(point.month.dropFirst(5).prefix(2)) ?? 0)月")
                        .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                    if isCurrent {
                        Text("本月")
                            .font(.custom(fontMonoOf(), size: 8))
                            .foregroundStyle(Color(css: tokens.accent))
                    }
                    Spacer(minLength: 0)
                    Text("\(point.count) 笔")
                        .font(.custom(fontMonoOf(), size: 8.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
                Text(formatYuan(point.totalCents))
                    .font(.custom(fontMonoOf(), size: 12).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // 比例条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(css: tokens.surface3))
                        Capsule()
                            .fill(Color(css: tokens.accent))
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 3)
            }
            .padding(9)
            .background(Color(css: tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: tokens.line), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 全部档

    private var allCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("全部")
                    .font(.custom(fontDisplayOf(isCyber), size: 15).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                Spacer(minLength: 0)
                Text("\(allYears.count) 年 · 合计 \(formatYuan(allTotalCents))")
                    .font(.custom(fontMonoOf(), size: 9.5))
                    .tracking(1.52)
                    .foregroundStyle(Color(css: tokens.ink3))
            }

            if allYears.isEmpty && !loading {
                Text("还没有任何记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(allYears) { point in
                        yearCell(point)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(css: tokens.surface))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func yearCell(_ point: YearPoint) -> some View {
        let pct = Double(point.totalCents) / Double(allCellMax())
        return Button {
            // 全部档点年格 → 切到该年的年档
            anchorYear = point.year
            anchorMonth = "\(point.year)-01"
            tier = 1
            Task { await loadYear() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(point.year)
                        .font(.custom(fontMonoOf(), size: 10.5).weight(.bold))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Spacer(minLength: 0)
                    Text("\(point.count) 笔")
                        .font(.custom(fontMonoOf(), size: 8.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
                Text(formatYuan(point.totalCents))
                    .font(.custom(fontMonoOf(), size: 12).weight(.bold))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(css: tokens.surface3))
                        Capsule()
                            .fill(Color(css: tokens.accent))
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(height: 3)
            }
            .padding(9)
            .background(Color(css: tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: tokens.line), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 期间月历（点期间标签弹出）

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
                        Text("关闭")
                            .font(.system(size: 11))
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

                // 12 格 4 列 3 行：格高 38 + 行距 6 → 126
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(1...12, id: \.self) { mm in
                        let key = monthKeyOf(year: calYear, month: mm)
                        let active = key == anchorMonth && tier == 0
                        Button {
                            applyPeriod(key, 0)
                        } label: {
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
                        Text("整年")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                    .stroke(Color(css: tokens.line), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        applyPeriod(currentMonthKey(), 0)
                    } label: {
                        Text("回到本月")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                    .stroke(Color(css: tokens.line), lineWidth: 1)
                            )
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

    // MARK: - 下拉指示器

    private var pullIndicator: some View {
        Group {
            if pullProgress > 0.01 {
                HStack(spacing: 8) {
                    BrandMark(34 * min(1, pullProgress))
                        .frame(height: 34 * min(1, pullProgress))
                        .clipped()
                    if pullProgress > 0.35 {
                        Text("记一笔")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .opacity(Double((pullProgress - 0.35) / 0.65))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52 * min(1, pullProgress))
                .clipped()
                .opacity(Double(pullProgress))
            }
        }
    }
}

// MARK: - 自动换行容器（筛选胶囊用）

/// SwiftUI 没有内置的 FlowLayout（iOS 16+ 才有 Layout 协议，这里用简易实现）
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
