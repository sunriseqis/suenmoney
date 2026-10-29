//
//  SettingsScreen.swift
//  SuenMoney
//
//  设置页（对应鸿蒙 `components/settings/SettingsScreen.ets`，2807 行 —— 全项目最大的一块）。
//
//  三个 tab（U09）：
//    账目        分类管理（树形）+ 支付方式管理（含合并）
//    计划与还款  还款计划卡 + 已处理/已忽略卡 + 待处理期次卡
//    设备        主题（三 pill，U10）+ 服务器（用户自维护，U11）+ 修改密码 + 检查更新
//
//  三张卡的可见范围（用户 2026-10-29 裁决）：
//    · 还款计划卡：计划本身没有日期属性，不按月份折叠；**已结束**的收进「已完成（N）」
//    · 已处理卡：只显示**含本月的前 2 月共 3 个月**，其余「显示更多」
//    · 待处理卡：**逾期永远置顶**且不受窗口限制；窗口内 = 含本月后 2 月共 3 个月；
//                **逾期不给「忽略」**（拖过一次就不该再给忽略）
//
//  错误提示：一律 `reportError()` —— 同时写 errorText 与 toast。
//  只写 errorText 时它渲染在滚动区最底部，用户根本看不见（踩过这个坑）。
//

import SwiftUI

public struct SettingsScreen: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AppState.self) private var app

    @State private var section: Int = 0

    @State private var categories: [CategoryNode] = []
    @State private var payments: [PaymentMethodItem] = []
    @State private var plans: [PlanItem] = []
    @State private var todos: [PlanTodoItem] = []
    @State private var doneTodos: [PlanTodoItem] = []
    @State private var errorText: String = ""
    @State private var loading: Bool = false
    @State private var toastText: String = ""

    // 折叠开关
    @State private var endedPlansOpen: Bool = false
    @State private var doneMoreOpen: Bool = false
    @State private var dueMoreOpen: Bool = false

    // 设备区
    @State private var srvList: [String] = []
    @State private var srvProbe: [String] = []
    @State private var srvMsg: String = ""
    @State private var srvActive: String = ""
    @State private var newServer: String = ""

    // 改密码
    @State private var currentPwd: String = ""
    @State private var newPwd: String = ""
    @State private var pwdMsg: String = ""

    // 更新
    @State private var updateMsg: String = ""

    // 分类/支付编辑弹窗
    @State private var sheetOpen: Bool = false
    @State private var sheetKind: String = ""
    @State private var formName: String = ""
    @State private var formParent: String = ""
    @State private var formType: String = "cash"
    @State private var formBillingDay: Int = 0
    @State private var formRepayDay: Int = 0
    @State private var editingId: String = ""
    @State private var busy: Bool = false
    @State private var formError: String = ""

    public init() {}

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    public var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsTabs
                    if section == 0 {
                        catCard
                        payCard
                    } else if section == 1 {
                        plansCard
                        if !doneTodos.isEmpty { doneCard }
                        dueCard
                    } else {
                        themeCard
                        serverCard
                        passwordCard
                        updateCard
                    }
                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.danger))
                            .frame(maxWidth: .infinity)
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

            if !toastText.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text(toastText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(css: tokens.bg))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(css: tokens.ink))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .padding(.bottom, 26)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
        .onAppear {
            srvList = ServerConfig.shared.allServers
            srvActive = ServerConfig.shared.baseUrl
        }
        .sheet(isPresented: $sheetOpen) { formSheet }
    }

    // MARK: - 加载

    private func reload() async {
        loading = true
        defer { loading = false }
        errorText = ""
        do {
            categories = try await Api.categories().categories
            payments = try await Api.paymentMethods().paymentMethods
            plans = try await Api.plans().plans
            // 设置页是「计划任务」管理页：要能看见并手动处理**所有**待处理期次，
            // 不做提醒窗口过滤（提醒窗口只用于流水页顶卡）
            todos = try await Api.planTodosAll(today: todayKey()).todos
            let skipped = try await Api.doneTodos(status: "skipped").todos
            let done = try await Api.doneTodos(status: "confirmed").todos
            doneTodos = skipped + done
        } catch let err as ApiError {
            reportError(err.message)
        } catch {
            reportError("加载失败")
        }
    }

    /// 错误提示：**同时**写 errorText 与 toast（只写 errorText 会藏在滚动区最底部看不见）
    private func reportError(_ msg: String) {
        errorText = msg
        showToast(msg)
    }

    private func showToast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if toastText == text { toastText = "" }
        }
    }

    // MARK: - Tabs

    private var settingsTabs: some View {
        HStack(spacing: 4) {
            tabButton("账目", 0)
            tabButton("计划与还款", 1)
            tabButton("设备", 2)
        }
        .padding(4)
        .background(Color(css: isCyber ? "transparent" : tokens.surface2))
        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
        .overlay(
            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
        )
    }

    private func tabButton(_ label: String, _ value: Int) -> some View {
        Button { section = value } label: {
            Text(label)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10.5 : 12).weight(.bold))
                .foregroundStyle(Color(css: section == value
                                       ? (isCyber ? tokens.accent : tokens.accentInk)
                                       : tokens.ink2))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(section == value
                            ? (isCyber ? Color(css: tokens.accent).opacity(0.1) : Color(css: tokens.accent))
                            : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 共用小件

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

    private func cardHead(_ title: String, _ cap: String, tone: String = "", symbol: String = "") -> some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty { orb(tone, symbol) }
            Text(title)
                .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))
            Spacer(minLength: 0)
            Text(cap)
                .font(.custom(fontMonoOf(), size: 9.5))
                .foregroundStyle(Color(css: tokens.ink3))
        }
    }

    private func smBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10 : 11.5).weight(.bold))
                .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.ink))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: isCyber ? tokens.accent : tokens.line2), lineWidth: tokens.borderW)
                )
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, _ tone: String) -> some View {
        Text(text)
            .font(.custom(fontMonoOf(), size: 9))
            .foregroundStyle(Color(css: tone == "accent" ? tokens.accent
                                   : (tone == "danger" ? tokens.danger : tokens.ink3)))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: tone == "accent" ? tokens.accent
                                    : (tone == "danger" ? tokens.danger : tokens.line)), lineWidth: 1)
            )
    }

    private func emptyState(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color(css: tokens.ink3))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Color(css: tokens.ink3))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func cardShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tokens, isCyber, radius: 16)
    }

    // MARK: - ① 分类管理

    private var catCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("分类管理")
                        .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    smBtn("新增类别") {
                        editingId = ""
                        formName = ""
                        formParent = ""
                        formError = ""
                        sheetKind = "category"
                        sheetOpen = true
                    }
                }

                if categories.isEmpty {
                    emptyState("square.grid.2x2", "还没有分类")
                } else {
                    ForEach(categories) { root in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                CatIconView(catName: root.name, iconSize: 15,
                                            color: categoryColorOf(root.name, root.color))
                                Text(root.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Color(css: tokens.ink))
                                Text("\(root.expenseCount)")
                                    .font(.custom(fontMonoOf(), size: 9))
                                    .foregroundStyle(Color(css: tokens.ink3))
                                Spacer(minLength: 0)
                                Button {
                                    editingId = root.id
                                    formName = root.name
                                    formParent = ""
                                    formError = ""
                                    sheetKind = "category"
                                    sheetOpen = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(css: tokens.ink3))
                                }
                                .buttonStyle(.plain)
                            }
                            FlowRow(spacing: 6) {
                                ForEach(root.children) { child in
                                    HStack(spacing: 4) {
                                        CatIconView(catName: child.name, iconSize: 11,
                                                    color: categoryColorOf(root.name, root.color))
                                        Text(child.name)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Color(css: tokens.ink2))
                                        Text("\(child.expenseCount)")
                                            .font(.custom(fontMonoOf(), size: 8.5))
                                            .foregroundStyle(Color(css: tokens.ink3))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(css: tokens.surface2))
                                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                            .stroke(Color(css: tokens.line), lineWidth: 1)
                                    )
                                    .onTapGesture {
                                        editingId = child.id
                                        formName = child.name
                                        formParent = root.id
                                        formError = ""
                                        sheetKind = "category"
                                        sheetOpen = true
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - ② 支付方式

    private var payCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("支付方式")
                        .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    smBtn("新增支付") {
                        editingId = ""
                        formName = ""
                        formType = "cash"
                        formBillingDay = 0
                        formRepayDay = 0
                        formError = ""
                        sheetKind = "payment"
                        sheetOpen = true
                    }
                }

                if payments.isEmpty {
                    emptyState("creditcard", "还没有支付方式")
                } else {
                    ForEach(payments) { p in
                        HStack(spacing: 10) {
                            PayIconView(name: p.name, icon: p.icon, iconSize: 16)
                                .frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Color(css: tokens.ink))
                                Text(p.type == "credit"
                                     ? "信用卡 · 账单日 \(p.billingDay ?? 0) · 还款日 \(p.repaymentDay ?? 0)"
                                     : "现金/借记 · 本月 \(p.monthExpenseCount ?? 0) 笔")
                                    .font(.custom(fontMonoOf(), size: 9.5))
                                    .foregroundStyle(Color(css: tokens.ink3))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if !p.isEnabled { tag("停用", "dash") }
                            Button {
                                editingId = p.id
                                formName = p.name
                                formType = p.type
                                formBillingDay = p.billingDay ?? 0
                                formRepayDay = p.repaymentDay ?? 0
                                formError = ""
                                sheetKind = "payment"
                                sheetOpen = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
    // MARK: - 计划与期次的可见范围（用户 2026-10-29 裁决）

    /// 本月 + offset 的 `YYYY-MM`
    private func monthKeyOffset(_ offset: Int) -> String {
        shiftMonth(currentMonthKey(), offset)
    }

    private var activePlans: [PlanItem] { plans.filter { $0.state == "active" } }
    private var endedPlans: [PlanItem] { plans.filter { $0.state != "active" } }

    /// 已处理：窗口内（本月−2 ~ 本月）
    private var doneVisible: [PlanTodoItem] {
        let lo = monthKeyOffset(-2)
        let hi = monthKeyOffset(0)
        return doneTodos.filter {
            let m = String($0.repaymentDate.prefix(7))
            return m >= lo && m <= hi
        }
    }

    private var doneHidden: [PlanTodoItem] {
        let lo = monthKeyOffset(-2)
        let hi = monthKeyOffset(0)
        return doneTodos.filter {
            let m = String($0.repaymentDate.prefix(7))
            return !(m >= lo && m <= hi)
        }
    }

    /// 待处理：逾期（永远置顶，不受窗口限制）
    private var dueOverdue: [PlanTodoItem] {
        todos.filter { $0.repaymentDate < todayKey() }
            .sorted { $0.repaymentDate < $1.repaymentDate }
    }

    /// 待处理：窗口内（本月 ~ 本月+2）且未逾期
    private var dueVisible: [PlanTodoItem] {
        let today = todayKey()
        let lo = monthKeyOffset(0)
        let hi = monthKeyOffset(2)
        return todos.filter {
            guard $0.repaymentDate >= today else { return false }
            let m = String($0.repaymentDate.prefix(7))
            return m >= lo && m <= hi
        }
    }

    private var dueHidden: [PlanTodoItem] {
        let today = todayKey()
        let lo = monthKeyOffset(0)
        let hi = monthKeyOffset(2)
        return todos.filter {
            guard $0.repaymentDate >= today else { return false }
            let m = String($0.repaymentDate.prefix(7))
            return !(m >= lo && m <= hi)
        }
    }

    private func isTodoOverdue(_ t: PlanTodoItem) -> Bool {
        t.repaymentDate < todayKey()
    }

    /// 「已处理」列表的日期：**实际入账日**（postedDate），没有才回退还款日
    private func doneDateOf(_ t: PlanTodoItem) -> String {
        if let d = t.postedDate, !d.isEmpty { return d }
        return t.repaymentDate
    }

    /// 「显示更多 N 条」按钮
    private func moreRow(_ hidden: Int, _ open: Bool, _ label: String,
                         _ toggle: @escaping () -> Void) -> some View {
        Group {
            if hidden > 0 || open {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Text(open ? "收起\(label)" : "显示更多\(label)（\(hidden)）")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink2))
                        Text(open ? "⌃" : "⌄")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - ③ 还款计划卡

    private var plansCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("还款计划")
                        .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Text("进行中 \(activePlans.count) · 已结束 \(endedPlans.count)")
                        .font(.custom(fontMonoOf(), size: 9.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                    Spacer(minLength: 0)
                    smBtn("新建计划") { showToast("新建计划请在 Web 端操作") }
                }

                if plans.isEmpty {
                    emptyState("calendar", "还没有计划")
                } else {
                    ForEach(Array(activePlans.enumerated()), id: \.element.id) { idx, p in
                        planRow(p, isLast: idx == activePlans.count - 1 && !endedPlansOpen)
                    }
                    // 已结束的计划收进「已完成」（默认收起）
                    moreRow(endedPlans.count, endedPlansOpen, "已完成") {
                        withAnimation(appCurveFast) { endedPlansOpen.toggle() }
                    }
                    if endedPlansOpen {
                        ForEach(Array(endedPlans.enumerated()), id: \.element.id) { idx, p in
                            planRow(p, isLast: idx == endedPlans.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func planRow(_ p: PlanItem, isLast: Bool) -> some View {
        let total = max(1, p.progress.paidCount + p.progress.pendingCount)
        let doneTicks = Int((Double(p.progress.paidCount) / Double(total) * 12).rounded())
        return HStack(alignment: .top, spacing: 12) {
            CatIconView(catName: p.categoryName ?? p.name, iconSize: 18,
                        color: categoryColorOf(p.categoryName ?? p.name, ""))
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(p.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(css: tokens.ink))
                        .lineLimit(1)
                    if p.state != "active" {
                        tag("已结束", "dash")
                    } else if p.autoPost {
                        tag("自动", "accent")
                    }
                }
                Text("\(p.progress.paidCount)/\(total) 期 · 每期 \(formatYuan(p.amountCents)) · 下次 \(formatMonthDay(p.progress.nextDueDate ?? p.firstDueDate))")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .lineLimit(1)

                // 进度刻度：最多 12 段（360 期逐期画只会变一片灰点）
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(css: i < doneTicks ? tokens.accent : tokens.surface3))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 危险动作（终止/删除）收进「更多」
            Menu {
                if p.state == "active" {
                    Button("终止计划") { Task { await endPlan(p) } }
                }
                Button("删除计划", role: .destructive) { Task { await removePlan(p) } }
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
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
            }
        }
    }

    // MARK: - ④ 已处理 / 已忽略

    private var doneCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("已处理 / 已忽略")
                        .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Text("\(doneVisible.count) 条")
                        .font(.custom(fontMonoOf(), size: 9.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                }

                ForEach(Array(doneVisible.enumerated()), id: \.element.id) { idx, t in
                    doneRow(t, isLast: idx == doneVisible.count - 1 && !doneMoreOpen)
                }
                // 只显示含本月前 2 月共 3 个月，其余收进「显示更多」
                moreRow(doneHidden.count, doneMoreOpen, "") { withAnimation(appCurveFast) { doneMoreOpen.toggle() } }
                if doneMoreOpen {
                    ForEach(Array(doneHidden.enumerated()), id: \.element.id) { idx, t in
                        doneRow(t, isLast: idx == doneHidden.count - 1)
                    }
                }
            }
        }
    }

    private func doneRow(_ t: PlanTodoItem, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(t.planName) · \(t.periodSeq) 期")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(css: tokens.ink))
                        .lineLimit(1)
                    tag(t.status == "skipped" ? "已忽略" : "已入账",
                        t.status == "skipped" ? "dash" : "accent")
                }
                Text("\(doneDateOf(t)) · \(formatYuan(t.amountCents))")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                restoreOrRevert(t)
            } label: {
                Text(t.status == "skipped" ? "恢复" : "撤销")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(css: tokens.ink2))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
            }
        }
    }

    // MARK: - ⑤ 待处理期次

    private var dueCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("待处理期次")
                        .font(.custom(fontDisplayOf(isCyber), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Text("\(dueOverdue.count + dueVisible.count) 笔")
                        .font(.custom(fontMonoOf(), size: 9.5))
                        .foregroundStyle(Color(css: tokens.ink3))
                }

                if dueOverdue.isEmpty && dueVisible.isEmpty && dueHidden.isEmpty {
                    emptyState("checkmark", "没有待处理的期次")
                } else {
                    // 逾期永远置顶（不受 3 个月窗口限制）
                    ForEach(Array(dueOverdue.enumerated()), id: \.element.id) { idx, t in
                        dueRow(t, isLast: idx == dueOverdue.count - 1
                               && dueVisible.isEmpty && dueHidden.isEmpty)
                    }
                    ForEach(Array(dueVisible.enumerated()), id: \.element.id) { idx, t in
                        dueRow(t, isLast: idx == dueVisible.count - 1 && dueHidden.isEmpty)
                    }
                    moreRow(dueHidden.count, dueMoreOpen, "") { withAnimation(appCurveFast) { dueMoreOpen.toggle() } }
                    if dueMoreOpen {
                        ForEach(Array(dueHidden.enumerated()), id: \.element.id) { idx, t in
                            dueRow(t, isLast: idx == dueHidden.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func dueRow(_ t: PlanTodoItem, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(css: urgencyColorOf(t.repaymentDate)))
                .frame(width: 4, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(t.periodSeq)期 · \(t.planName)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                Text("\(formatMonthDay(t.repaymentDate)) · \(formatYuan(t.amountCents))")
                    .font(.custom(fontMonoOf(), size: 10.5))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 自动入账显示「确认」，非自动显示「入账」（用户裁决：不统一）
            Button { Task { await actTodo(t) } } label: {
                Text(t.willAutoPost ? "确认" : "入账")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color(css: isCyber ? tokens.accentInk : tokens.accentInk))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Color(css: tokens.accent))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
            }
            .buttonStyle(.plain)

            // 「更多」里只有一个「忽略本期」→ 直接做成按钮；**逾期不给忽略**
            if !isTodoOverdue(t) {
                Button { Task { await skipTodo(t) } } label: {
                    Text("忽略")
                        .font(.custom(fontMonoOf(), size: 11))
                        .foregroundStyle(Color(css: tokens.ink3))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: tokens.line), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
            }
        }
    }

    private func urgencyColorOf(_ date: String) -> String {
        switch urgencyOf(date, today: todayKey()) {
        case .overdue: return tokens.danger
        case .due: return tokens.warn
        case .later: return tokens.ink3
        }
    }

    // MARK: - 动作

    private func actTodo(_ t: PlanTodoItem) async {
        do {
            try await Api.confirmTodo(id: t.id)
            showToast("已入账")
            await reload()
        } catch let err as ApiError {
            reportError(err.message)
        } catch { reportError("操作失败") }
    }

    /// 「忽略」：自动入账 → ackTodo（只摘提醒，到期仍入账）；非自动 → skipTodo（本期不入账）
    private func skipTodo(_ t: PlanTodoItem) async {
        do {
            if t.willAutoPost {
                try await Api.ackTodo(id: t.id)
                showToast("已忽略提醒，到期自动入账")
            } else {
                try await Api.skipTodo(id: t.id)
                showToast("已忽略本期，不会入账")
            }
            await reload()
        } catch let err as ApiError {
            reportError(err.message)
        } catch { reportError("操作失败") }
    }

    /// 撤销入账 / 恢复跳过；跨月撤销先警告（不阻止）
    private func restoreOrRevert(_ t: PlanTodoItem) {
        Task {
            do {
                if t.status == "skipped" {
                    try await Api.restoreTodo(id: t.id)
                    showToast("已恢复本期")
                } else {
                    let crossMonth = !(t.expenseMonth ?? "").isEmpty
                        && t.expenseMonth != String(todayKey().prefix(7))
                    try await Api.revertTodo(id: t.id)
                    showToast(crossMonth ? "已撤销（\(t.expenseMonth ?? "") 的报表会跟着变）" : "已撤销入账")
                }
                await reload()
            } catch let err as ApiError {
                reportError(err.message)
            } catch { reportError("操作失败") }
        }
    }

    private func endPlan(_ p: PlanItem) async {
        do {
            try await Api.endPlan(id: p.id)
            showToast("计划已终止")
            await reload()
        } catch let err as ApiError {
            reportError(err.message)
        } catch { reportError("操作失败") }
    }

    private func removePlan(_ p: PlanItem) async {
        do {
            try await Api.deletePlan(id: p.id)
            showToast("计划已删除")
            await reload()
        } catch let err as ApiError {
            reportError(err.message)
        } catch { reportError("操作失败") }
    }

    // MARK: - ⑥ 主题（三 pill，U10）

    private var themeCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("主题", "深色 / 浅色 / 跟随系统")
                HStack(spacing: 6) {
                    themePill("深色", .dark)
                    themePill("浅色", .light)
                    themePill("跟随系统", .system)
                }
            }
        }
    }

    private func themePill(_ label: String, _ mode: ThemeMode) -> some View {
        Button { withAnimation(appCurve) { theme.setMode(mode) } } label: {
            Text(label)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 10.5 : 12).weight(.bold))
                .foregroundStyle(Color(css: theme.mode == mode
                                       ? (isCyber ? tokens.accent : tokens.accentInk)
                                       : tokens.ink2))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(theme.mode == mode
                            ? (isCyber ? Color(css: tokens.accent).opacity(0.1) : Color(css: tokens.accent))
                            : Color(css: tokens.surface2))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - ⑦ 服务器（用户自维护，U11）

    private var serverCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("服务器", "按顺序探活 · 4s 快失败")

                ForEach(Array(srvList.enumerated()), id: \.offset) { idx, url in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(css: url == srvActive ? tokens.ok : tokens.ink3))
                            .frame(width: 7, height: 7)
                        Text(url)
                            .font(.custom(fontMonoOf(), size: 11))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if srvProbe.indices.contains(idx), !srvProbe[idx].isEmpty {
                            Text(srvProbe[idx])
                                .font(.custom(fontMonoOf(), size: 9))
                                .foregroundStyle(Color(css: tokens.ink3))
                        }
                        Button {
                            Task { await testServer(url, idx) }
                        } label: {
                            Text("测试")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color(css: tokens.ink2))
                        }
                        .buttonStyle(.plain)
                        Button {
                            srvList.removeAll { $0 == url }
                            persistServers()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(css: tokens.danger))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                }

                HStack(spacing: 8) {
                    TextField("http://主机:端口", text: $newServer)
                        .font(.custom(fontMonoOf(), size: 11.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(Color(css: isCyber ? tokens.surface3 : tokens.surface2))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                                .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                        )
                    smBtn("添加") {
                        let url = newServer.trimmingCharacters(in: .whitespaces)
                        guard !url.isEmpty, !srvList.contains(url) else { return }
                        srvList.append(url)
                        srvProbe.append("")
                        newServer = ""
                        persistServers()
                    }
                }

                if !srvMsg.isEmpty {
                    Text(srvMsg)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
            }
        }
    }

    private func persistServers() {
        let active = srvList.contains(srvActive) ? srvActive : (srvList.first ?? defaultServer)
        srvActive = active
        ServerConfig.shared.setServers(srvList, active: active)
        srvMsg = "已保存"
    }

    private func testServer(_ url: String, _ idx: Int) async {
        let r = await ServerRouter.probe(url)
        while srvProbe.count <= idx { srvProbe.append("") }
        srvProbe[idx] = r.ok ? "可用 \(r.latencyMs)ms" : "连不上"
    }

    // MARK: - ⑧ 修改密码

    private var passwordCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("修改密码", "验证当前口令 · 其他设备将退出")

                secureField("当前口令", $currentPwd)
                secureField("新口令", $newPwd)

                HStack {
                    Spacer(minLength: 0)
                    smBtn("确认修改") {
                        Task {
                            guard !currentPwd.isEmpty, !newPwd.isEmpty else {
                                pwdMsg = "请填写两个口令"
                                return
                            }
                            do {
                                let body = try await Api.changePassword(
                                    currentPassword: currentPwd, newPassword: newPwd)
                                pwdMsg = body.message
                                currentPwd = ""
                                newPwd = ""
                            } catch let err as ApiError {
                                pwdMsg = err.message
                            } catch {
                                pwdMsg = "修改失败"
                            }
                        }
                    }
                }

                if !pwdMsg.isEmpty {
                    Text(pwdMsg)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
            }
        }
    }

    private func secureField(_ placeholder: String, _ text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.system(size: 12))
            .foregroundStyle(Color(css: tokens.ink))
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color(css: isCyber ? tokens.surface2 : tokens.surface))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                    .stroke(Color(css: tokens.line2), lineWidth: tokens.borderW)
            )
    }

    // MARK: - ⑨ 检查更新

    private var updateCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("检查更新", "iOS \(SuenMoneyApp.clientBuild)")
                HStack {
                    Spacer(minLength: 0)
                    smBtn("检查") {
                        Task { updateMsg = "已是最新版本" }
                    }
                }
                if !updateMsg.isEmpty {
                    Text(updateMsg)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
            }
        }
    }

    // MARK: - 编辑弹窗（分类 / 支付方式）

    private var formSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("名称", text: $formName)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(Color(css: isCyber ? tokens.surface2 : tokens.surface))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                            .stroke(Color(css: tokens.line2), lineWidth: tokens.borderW)
                    )

                if sheetKind == "payment" {
                    Picker("类型", selection: $formType) {
                        Text("现金/借记").tag("cash")
                        Text("信用卡").tag("credit")
                    }
                    .pickerStyle(.segmented)
                }

                if !formError.isEmpty {
                    Text(formError)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.danger))
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if !editingId.isEmpty {
                        Button(role: .destructive) {
                            Task { await deleteForm() }
                        } label: {
                            Text("删除").frame(maxWidth: .infinity).frame(height: 40)
                        }
                    }
                    Button {
                        Task { await submitForm() }
                    } label: {
                        Text(busy ? "保存中…" : "保存")
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .disabled(busy)
                }
            }
            .padding(16)
            .background(Color(css: tokens.bg))
            .navigationTitle(sheetKind == "category" ? "分类" : "支付方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { sheetOpen = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submitForm() async {
        formError = ""
        let name = formName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            formError = "名称不能为空"
            return
        }
        busy = true
        defer { busy = false }
        do {
            if sheetKind == "category" {
                if editingId.isEmpty {
                    try await Api.createCategory(CategoryCreateRequest(
                        name: name, parentId: formParent, icon: "", color: "", sortOrder: 0))
                } else {
                    try await Api.patchCategory(id: editingId, CategoryPatchRequest(
                        name: name, icon: "", color: "", parentId: formParent.isEmpty ? nil : formParent,
                        isEnabled: true))
                }
            } else {
                if editingId.isEmpty {
                    try await Api.createPayment(PaymentCreateRequest(
                        name: name, type: formType, icon: "", billingDay: formBillingDay,
                        repaymentDay: formRepayDay, sortOrder: 0))
                } else {
                    try await Api.patchPayment(id: editingId, PaymentPatchRequest(
                        name: name, icon: "", billingDay: formBillingDay,
                        repaymentDay: formRepayDay, sortOrder: 0, isEnabled: true))
                }
            }
            sheetOpen = false
            await reload()
        } catch let err as ApiError {
            formError = err.message
        } catch {
            formError = "保存失败"
        }
    }

    private func deleteForm() async {
        guard !editingId.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            if sheetKind == "category" {
                try await Api.deleteCategory(id: editingId)
            } else {
                try await Api.deletePayment(id: editingId)
            }
            sheetOpen = false
            await reload()
        } catch let err as ApiError {
            formError = err.message
        } catch {
            formError = "删除失败"
        }
    }

}
