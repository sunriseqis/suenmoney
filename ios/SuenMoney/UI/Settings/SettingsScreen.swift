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

/// 分类图标选项（鸿蒙 `CAT_ICON_OPTIONS` 24 项 + 「自动」）—— SF Symbols 等价映射
let catIconOptions: [(name: String, label: String, symbol: String)] = [
    ("utensils", "餐饮", "fork.knife"),
    ("shopping-basket", "买菜", "cart.fill"),
    ("shopping-cart", "购物", "bag.fill"),
    ("car-front", "打车", "car.fill"),
    ("bus", "公交", "tram.fill"),
    ("fuel", "加油", "fuelpump.fill"),
    ("house", "居住", "house.fill"),
    ("zap", "水电", "bolt.fill"),
    ("hand-coins", "红包", "banknote.fill"),
    ("stethoscope", "医疗", "cross.case.fill"),
    ("pill", "药品", "pills.fill"),
    ("gamepad-2", "娱乐", "gamecontroller.fill"),
    ("film", "电影", "film.fill"),
    ("dumbbell", "健身", "dumbbell.fill"),
    ("book-open", "书籍", "book.fill"),
    ("graduation-cap", "教育", "graduationcap.fill"),
    ("gift", "礼物", "gift.fill"),
    ("cat", "宠物", "pawprint.fill"),
    ("smartphone", "话费", "phone.fill"),
    ("laptop", "电脑", "desktopcomputer"),
    ("shirt", "服饰", "tshirt.fill"),
    ("credit-card", "信用卡", "creditcard.fill"),
    ("wallet", "钱包", "wallet.pass.fill"),
    ("circle-ellipsis", "其他", "doc.text")
]

/// 设置弹层的三种形态。
/// 用 enum + `.sheet(item:)` 而不是 `String` + `.sheet(isPresented:)`：
/// 后者在「同一次 body 更新里同时改 kind 与 isPresented」时，
/// sheet 内容会拿到**旧值**（实测表现为表单只剩「名称」）。
enum SheetKind: String, Identifiable {
    case category, payment, plan
    var id: String { rawValue }
}

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
    @State private var sheetKind: SheetKind?
    @State private var formName: String = ""
    @State private var formParent: String = ""
    @State private var formType: String = "cash"
    /// 编辑时保留的原始字段 —— 表单暂时没有图标/颜色选择器，
    /// 但**绝不能因此把已有值清空**（鸿蒙会原样带回）。
    @State private var formIcon: String = ""
    @State private var formColor: String = ""
    @State private var formEnabled: Bool = true
    @State private var formSortOrder: Int = 0
    /// 分类管理左侧选中的一级分类（鸿蒙 `railRootId`）
    @State private var railRootId: String = ""
    /// 计划表单的每期金额（元文本，提交时转分）
    @State private var planAmountText: String = ""
    @State private var formBillingDay: Int = 0
    @State private var formRepayDay: Int = 0
    @State private var editingId: String = ""
    @State private var busy: Bool = false
    @State private var formError: String = ""
    /// 跨月撤销的二次确认（鸿蒙 R126：撤销跨月入账要先说明「那个月的报表会变」）
    @State private var revertWarnText: String = ""
    @State private var pendingRevertId: String = ""
    @State private var revertWarnOpen: Bool = false

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
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: tokens.line2), lineWidth: 2)
                        )
                        .background {
                            Capsule().fill(Color(css: "rgba(0,0,0,0.18)")).offset(x: 4, y: 4)
                        }
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
        // 用 `.sheet(item:)`：内容直接拿 kind 参数，不依赖 body 时序
        .sheet(item: $sheetKind) { kind in formSheet(kind) }
        .alert("撤销跨月入账？", isPresented: $revertWarnOpen) {
            Button("仍要撤销", role: .destructive) {
                let id = pendingRevertId
                Task {
                    do {
                        try await Api.revertTodo(id: id)
                        showToast("已撤销入账")
                        await reload()
                    } catch let err as ApiError { reportError(err.message) } catch { reportError("撤销失败") }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(revertWarnText)
        }
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
            reportError(err.kind == .network ? "离线：设置项需要联网" : err.message)
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

    /// 页签：**下划线形态**（鸿蒙 `stab`）—— 底部 3px accent 下划线 + 整条 1px line 底线。
    /// 之前做成胶囊分段，形态完全不同。
    private var settingsTabs: some View {
        HStack(spacing: 4) {
            tabButton("账目", 0)
            tabButton("计划与还款", 1)
            tabButton("设备", 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(css: tokens.line)).frame(height: 1)
        }
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

    /// 悬浮圆图标（鸿蒙 `orb`）：34×34、图标 16。
    /// candy = 实色底(tone) + 2px line2 描边 + 2px 硬阴影；cyber = 透明底 + accent 描边 + 绿光。
    private func orb(_ tone: String, _ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: isCyber ? 1 : 17)
        return Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(Color(css: isCyber ? tokens.accent : tokens.line2))
            .frame(width: 34, height: 34)
            .background(shape.fill(Color(css: isCyber ? "transparent" : tone)))
            .overlay(shape.stroke(Color(css: isCyber ? tokens.accent : tokens.line2),
                                  lineWidth: isCyber ? 1 : 2))
            .background {
                if !isCyber { shape.fill(Color(css: tokens.line2)).offset(x: 2, y: 2) }
            }
            .shadow(color: isCyber ? Color(css: "rgba(0,255,136,0.4)") : .clear,
                    radius: isCyber ? 5 : 0, x: 0, y: isCyber ? -2 : 0)
    }

    /// 卡片标题（鸿蒙 `cardHead`）：cyber 用 mono / candy 用**正文族**（不是 Outfit 标题族）
    private func cardHead(_ title: String, _ cap: String, tone: String = "", symbol: String = "") -> some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty { orb(tone, symbol) }
            Text(title)
                .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 12.5 : 15).weight(.bold))
                .tracking(isCyber ? 1.25 : 0)
                .foregroundStyle(Color(css: tokens.ink))
            Spacer(minLength: 0)
            Text(cap)
                .font(.custom(fontMonoOf(), size: 9.5))
                .tracking(1.52)
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

    /// 标签（鸿蒙 `tag`）：10pt medium mono、**胶囊**、虚线/实线描边、surface2 底
    private func tag(_ text: String, _ tone: String) -> some View {
        let color = tone == "accent" ? tokens.accent : (tone == "warn" ? tokens.warn : tokens.ink2)
        let outline = tone == "accent" ? tokens.accent : (tone == "warn" ? tokens.warn : tokens.line)
        return Text(text)
            .font(.custom(fontMonoOf(), size: 10).weight(.medium))
            .foregroundStyle(Color(css: color))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(css: tone.isEmpty || tone == "dash" ? tokens.surface2 : "transparent"))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
            .overlay(
                Capsule().stroke(Color(css: outline), lineWidth: 1)
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

    // MARK: - ① 分类管理（一级 rail + 二级列表，鸿蒙 `catCard`）

    private var railRoot: CategoryNode? {
        categories.first { $0.id == railRootId }
    }

    private var railChildren: [CategoryNode] {
        guard let root = railRoot else { return [] }
        return root.children.isEmpty ? [root] : root.children
    }

    /// 二级分类的颜色跟随一级
    private func parentColor() -> String {
        guard let root = railRoot else { return tokens.accent }
        return categoryColorOf(root.name, root.color)
    }

    private var catCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                // card-h：orb + 标题 + 「新增类别」
                HStack(spacing: 10) {
                    orb(tokens.accent, "tag")
                    Text("分类管理")
                        .font(.custom(isCyber ? fontMonoOf() : fontBodyOf(false), size: isCyber ? 12.5 : 15).weight(.bold))
                        .tracking(isCyber ? 1.25 : 0)
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    smBtn("新增类别") { openCatCreate() }
                }
                .padding(.bottom, 3)

                // 左侧一级导航（移动端：横排换行）
                FlowRow(spacing: 4) {
                    ForEach(categories) { root in
                        let on = railRootId == root.id
                        Button {
                            withAnimation(appCurveFast) { railRootId = root.id }
                        } label: {
                            HStack(spacing: 8) {
                                CatIconView(catName: root.name, iconSize: 18,
                                            color: categoryColorOf(root.name, root.color))
                                Text(root.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color(css: on ? tokens.ink : tokens.ink2))
                                    .lineLimit(1)
                                Text("\(root.children.count)")
                                    .font(.custom(fontMonoOf(), size: 10))
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Color(css: on ? tokens.surface2 : "transparent"))
                            .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: isCyber ? 1 : 9)
                                    .stroke(Color(css: on
                                                  ? (isCyber ? tokens.accent : tokens.line2)
                                                  : "transparent"),
                                            lineWidth: on ? tokens.borderW : 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 右侧：当前一级下的二级分类
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text(railRoot.map { "\($0.name) · 分类" } ?? "分类")
                            .font(.custom(fontMonoOf(), size: 10.5))
                            .foregroundStyle(Color(css: tokens.ink3))
                        Spacer(minLength: 0)
                        inlineAction("新增分类") { openCatCreateChild() }
                        inlineAction("编辑类别") {
                            if let root = railRoot { openCatEdit(root) }
                        }
                        inlineAction("删除") {
                            if let root = railRoot { Task { await removeCat(root) } }
                        }
                    }

                    if railChildren.isEmpty {
                        emptyState("tag", "这个一级分类下还没有二级分类")
                    } else {
                        ForEach(railChildren) { kid in
                            HStack(spacing: 8) {
                                // 二级颜色跟随一级，图标按二级自己的名字
                                CatIconView(catName: kid.name, iconSize: 26, color: parentColor())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(kid.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(Color(css: tokens.ink))
                                            .lineLimit(1)
                                        if !kid.isEnabled { tag("已停用", "warn") }
                                    }
                                    Text("\(kid.expenseCount) 笔引用")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color(css: tokens.ink3))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                iconBtn("square.and.pencil") { openCatEdit(kid) }
                                iconBtn("trash") { Task { await removeCat(kid) } }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(css: isCyber ? "transparent" : tokens.surface))
                            .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: isCyber ? 1 : 10)
                                    .stroke(Color(css: tokens.line), lineWidth: 1)
                            )
                        }
                    }

                    Text("分类与支付方式均为软删除：已有流水引用时拒绝删除，只能停用。")
                        .font(.system(size: 11))
                        .lineSpacing(4)
                        .foregroundStyle(Color(css: tokens.ink3))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inlineAction(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(Color(css: tokens.ink2))
        }
        .buttonStyle(.plain)
    }

    /// 34×34 图标按钮（鸿蒙 `iconBtn`）
    private func iconBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Color(css: tokens.ink2))
                .frame(width: 34, height: 34)
                .background(Color(css: isCyber ? "transparent" : tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: isCyber ? 1 : 17))
                .overlay(
                    RoundedRectangle(cornerRadius: isCyber ? 1 : 17)
                        .stroke(Color(css: isCyber ? "rgba(0,255,136,0.55)" : tokens.line),
                                lineWidth: tokens.borderW)
                )
        }
        .buttonStyle(.plain)
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
                    smBtn("新增支付") { openPayCreate() }
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
                                openPayEdit(p)
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
                    smBtn("新建计划") { openPlanCreate() }
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

    /// 入账动作要按计划类型分流：
    /// 自动入账型走 `ackTodo`（只摘提醒，到期由服务端结算），
    /// 非自动型才走 `confirmTodo`（立即生成支出）。
    /// 之前一律 confirmTodo —— 等于把「自动入账」的计划提前手动入账了。
    private func actTodo(_ t: PlanTodoItem) async {
        do {
            if t.willAutoPost {
                try await Api.ackTodo(id: t.id)
                showToast("已确认并自动入账")
            } else {
                try await Api.confirmTodo(id: t.id)
                showToast("已手动入账")
            }
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
                    // 跨月撤销：先弹确认（鸿蒙 R126），说明「哪个月的报表会变」
                    if let month = t.expenseMonth, !month.isEmpty,
                       month != String(todayKey().prefix(7)) {
                        revertWarnText = "这笔 \(formatYuan(t.amountCents)) 记在 \(month)，撤销后 \(month) 的报表会跟着变。"
                        pendingRevertId = t.id
                        revertWarnOpen = true
                        return
                    }
                    try await Api.revertTodo(id: t.id)
                    showToast("已撤销入账")
                }
                await reload()
            } catch let err as ApiError {
                reportError(err.message)
            } catch { reportError("操作失败") }
        }
    }

    private func mergePayment(_ from: PaymentMethodItem, into: PaymentMethodItem) async {
        do {
            try await Api.mergePayment(id: from.id, intoId: into.id)
            showToast("已并入「\(into.name)」")
            await reload()
        } catch let err as ApiError {
            reportError(err.message)
        } catch { reportError("合并失败") }
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
                cardHead("主题", "深色 / 浅色 / 跟随系统", tone: tokens.accent, symbol: "paintpalette")
                HStack(spacing: 6) {
                    themePill("水果硬糖", .light)
                    themePill("赛博朋克", .dark)
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

    /// 服务器卡（鸿蒙 `serverCard`）：**地址行内可编辑** + 逐条探活 + 显式保存 + 「生效」标记
    private var serverCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("服务器", "按顺序探活 · 4s 快失败", tone: tokens.sky, symbol: "server.rack")

                if srvList.isEmpty {
                    emptyState("server.rack", "还没有服务器，点下面「添加服务器」")
                } else {
                    ForEach(Array(srvList.enumerated()), id: \.offset) { idx, url in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(css: url == srvActive ? tokens.ok : tokens.ink3))
                                .frame(width: 7, height: 7)
                            // 行内可编辑（原来只能看）
                            TextField("http://主机:端口", text: Binding(
                                get: { srvList[idx] },
                                set: { srvList[idx] = $0 }
                            ))
                            .font(.custom(fontMonoOf(), size: 11))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .foregroundStyle(Color(css: tokens.ink2))
                            .padding(.horizontal, 8)
                            .frame(height: 32)
                            .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
                            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                                    .stroke(Color(css: outlineStrongOf(isCyber)),
                                            lineWidth: fieldBorderWOf(tokens.borderW, isCyber))
                            )

                            if url == srvActive {
                                Text("生效")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color(css: tokens.accent))
                            }
                            if srvProbe.indices.contains(idx), !srvProbe[idx].isEmpty {
                                Text(srvProbe[idx])
                                    .font(.custom(fontMonoOf(), size: 9))
                                    .foregroundStyle(Color(css: tokens.ink3))
                            }
                            Button {
                                Task { await testServers() }
                            } label: {
                                Text("测试")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color(css: tokens.ink2))
                            }
                            .buttonStyle(.plain)
                            Button {
                                srvList.remove(at: idx)
                                if srvProbe.indices.contains(idx) { srvProbe.remove(at: idx) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(css: tokens.danger))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 5)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        if !newServer.trimmingCharacters(in: .whitespaces).isEmpty {
                            srvList.append(newServer.trimmingCharacters(in: .whitespaces))
                            srvProbe.append("")
                            newServer = ""
                        }
                    } label: {
                        Text("+ 添加服务器")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                            )
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Button {
                        Task { await testServers() }
                    } label: {
                        Text("全部测试")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
                            )
                    }
                    .buttonStyle(.plain)
                    Button {
                        saveServers()
                    } label: {
                        Text("保存并生效")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Color(css: tokens.accentInk))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color(css: tokens.accent))
                            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                    }
                    .buttonStyle(.plain)
                }

                if !srvMsg.isEmpty {
                    Text(srvMsg)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
            }
        }
    }

    /// 逐条探活（鸿蒙 testServers）
    private func testServers() async {
        var results = [String](repeating: "", count: srvList.count)
        for (i, url) in srvList.enumerated() {
            let r = await ServerRouter.probe(url)
            results[i] = r.ok ? "可用 \(r.latencyMs)ms" : "连不上"
        }
        srvProbe = results
    }

    /// 显式保存（鸿蒙 saveServers）：至少一个地址，按顺序探活选第一个可用的生效
    private func saveServers() {
        let cleaned = srvList.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            srvMsg = "至少填一个地址"
            return
        }
        srvList = cleaned
        Task {
            let chosen = await ServerRouter.choose(cleaned)
            if chosen.isEmpty {
                srvMsg = "所有地址都连不上"
            } else {
                srvActive = chosen
                srvMsg = "已保存，当前生效：\(chosen)"
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
                cardHead("修改密码", "验证当前口令 · 其他设备将退出", tone: tokens.warn, symbol: "lock")

                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("当前口令")
                    secureField("当前口令", $currentPwd)
                }
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("新口令（至少 8 位）")
                    secureField("至少 8 位", $newPwd)
                }
                Text("改口令后其他设备会被退出登录。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(css: tokens.ink3))

                HStack {
                    Spacer(minLength: 0)
                    smBtn("确认修改") {
                        Task {
                            guard !currentPwd.isEmpty, !newPwd.isEmpty else {
                                pwdMsg = "请填写两个口令"
                                return
                            }
                            // 鸿蒙同：新口令至少 8 位
                            guard newPwd.count >= 8 else {
                                pwdMsg = "新口令至少 8 位"
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

    /// 日期号输入（1–28，避免 2 月溢出）
    private func dayField(_ label: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(css: tokens.ink3))
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(fontMonoOf(), size: 13))
                .foregroundStyle(Color(css: tokens.ink))
                .padding(.horizontal, 9)
                .frame(height: 34)
                .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                        .stroke(Color(css: outlineStrongOf(isCyber)),
                                lineWidth: fieldBorderWOf(tokens.borderW, isCyber))
                )
        }
        .frame(maxWidth: .infinity)
    }

    private func secureField(_ placeholder: String, _ text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .font(.system(size: 12))
            .foregroundStyle(Color(css: tokens.ink))
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                    .stroke(Color(css: outlineStrongOf(isCyber)), lineWidth: fieldBorderWOf(tokens.borderW, isCyber))
            )
    }

    // MARK: - ⑨ 检查更新

    private var updateCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("检查更新", "iOS \(SuenMoneyApp.clientBuild)", tone: tokens.mint, symbol: "arrow.triangle.2.circlepath")
                HStack {
                    Spacer(minLength: 0)
                    smBtn("检查") {
                        Task {
                            // 之前这里直接写「已是最新版本」，根本没发请求 —— 谎报。
                            // 与鸿蒙一致：探 /api/health，显示服务端版本与连通性。
                            updateMsg = "检查中…"
                            do {
                                let h = try await Api.health()
                                updateMsg = "服务端 v\(h.version) · 连接正常"
                            } catch let err as ApiError {
                                updateMsg = err.message
                            } catch {
                                updateMsg = "检查失败"
                            }
                        }
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

    /// 设置弹层：分类 / 支付方式 / 新建计划 三种形态共用（鸿蒙 `settingsSheet`）
    private func formSheet(_ kind: SheetKind) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // 名称
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel(kind == .plan ? "计划名称" : "名称")
                        plainField("请输入名称", $formName)
                    }

                    if kind == .category {
                        // 归属类别（二级分类可改父级）
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("归属类别")
                            Picker("归属类别", selection: $formParent) {
                                Text("（一级分类）").tag("")
                                ForEach(categories.filter { $0.parentId == nil || $0.parentId?.isEmpty == true }) { root in
                                    Text(root.name).tag(root.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(css: tokens.accent))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // 图标选择器（24 项 + 自动）
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("图标")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                                iconOption("", "自动", "wand.and.stars")
                                ForEach(Array(catIconOptions.enumerated()), id: \.offset) { _, opt in
                                    iconOption(opt.name, opt.label, opt.symbol)
                                }
                            }
                        }

                        // 颜色选择器（16 色，只对一级显示）
                        if formParent.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                fieldLabel("颜色")
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                                    colorOption("")
                                    ForEach(Array(categoryColors.enumerated()), id: \.offset) { i, hex in
                                        colorOption("\(i + 1)", hex: hex)
                                    }
                                }
                            }
                        }
                    }

                    if kind == .payment {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("类型")
                            Picker("类型", selection: $formType) {
                                Text("现金/借记").tag("cash")
                                Text("信用卡").tag("credit")
                            }
                            .pickerStyle(.segmented)
                        }
                        // 信用卡才有账单日 / 还款日
                        if formType == "credit" {
                            HStack(spacing: 10) {
                                dayField("账单日", $formBillingDay)
                                dayField("还款日", $formRepayDay)
                            }
                        }
                        // 支付图标选择器（10 项 + 自动）
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("图标")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                                payIconOption("")
                                ForEach(payOptions, id: \.id) { opt in
                                    payIconOption(opt.id.rawValue)
                                }
                            }
                        }
                    }

                    if kind == .plan {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("分类")
                            Picker("分类", selection: $formParent) {
                                ForEach(categories.filter { $0.parentId == nil || $0.parentId?.isEmpty == true }) { root in
                                    Text(root.name).tag(root.id)
                                    ForEach(root.children) { kid in
                                        Text("  \(kid.name)").tag(kid.id)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(css: tokens.accent))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("支付方式")
                            Picker("支付方式", selection: $formIcon) {
                                ForEach(payments) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color(css: tokens.accent))
                        }
                        HStack(spacing: 10) {
                            dayField("期数", $formBillingDay)
                            dayField("提前提醒(天)", $formRepayDay)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            fieldLabel("每期金额（元）")
                            plainField("0.00", $planAmountText)
                                .keyboardType(.decimalPad)
                        }
                        // 到期自动入账开关
                        HStack(spacing: 8) {
                            Text("到期自动入账")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(css: tokens.ink))
                            Spacer(minLength: 0)
                            Toggle("", isOn: $formEnabled)
                                .labelsHidden()
                                .tint(Color(css: tokens.accent))
                        }
                    }

                    if !formError.isEmpty {
                        Text(formError)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.danger))
                    }

                    HStack(spacing: 10) {
                        if !editingId.isEmpty && kind != .plan {
                            Button(role: .destructive) {
                                Task { await deleteForm() }
                            } label: {
                                Text("删除").frame(maxWidth: .infinity).frame(height: 40)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button {
                            Task { await submitForm() }
                        } label: {
                            Text(busy ? "保存中…" : "保存")
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color(css: tokens.bg))
            .navigationTitle(sheetTitle(kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { sheetKind = nil }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(css: tokens.bg))
    }

    private func sheetTitle(_ kind: SheetKind) -> String {
        switch kind {
        case .category: return editingId.isEmpty ? "新增分类" : "编辑分类"
        case .payment: return editingId.isEmpty ? "新增支付方式" : "编辑支付方式"
        case .plan: return "新建计划"
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(css: tokens.ink3))
    }

    private func plainField(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 13))
            .foregroundStyle(Color(css: tokens.ink))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                    .stroke(Color(css: outlineStrongOf(isCyber)),
                            lineWidth: fieldBorderWOf(tokens.borderW, isCyber))
            )
    }

    private func iconOption(_ value: String, _ label: String, _ symbol: String) -> some View {
        let on = formIcon == value
        return Button {
            formIcon = value
        } label: {
            VStack(spacing: 2) {
                Image(systemName: value.isEmpty ? symbol : (catIconOptions.first { $0.name == value }?.symbol ?? symbol))
                    .font(.system(size: 15))
                    .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink2))
                Text(label)
                    .font(.system(size: 7.5))
                    .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink3))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(Color(css: on ? tokens.accent : tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: on ? tokens.accent : tokens.line), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorOption(_ value: String, hex: String = "") -> some View {
        let on = formColor == value
        return Button {
            formColor = value
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(css: hex.isEmpty ? tokens.ink3 : hex))
                .frame(height: 30)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(css: on ? tokens.ink : tokens.line),
                                lineWidth: on ? 2.5 : 1)
                )
                .overlay {
                    if hex.isEmpty {
                        Text("自动")
                            .font(.system(size: 7.5))
                            .foregroundStyle(Color(css: tokens.bg))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func payIconOption(_ value: String) -> some View {
        let on = formIcon == value
        let opt = payOptions.first { $0.id.rawValue == value }
        return Button {
            formIcon = value
        } label: {
            Group {
                if let o = opt {
                    if o.svg {
                        Image(o.res).renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink2))
                    } else {
                        Image(systemName: o.res)
                            .font(.system(size: 16))
                            .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink2))
                    }
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink3))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color(css: on ? tokens.accent : tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: on ? tokens.accent : tokens.line), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 打开表单（鸿蒙 openCatCreate / openCatCreateChild / openCatEdit / …）

    private func openCatCreate() {
        formError = ""
        editingId = ""
        formName = ""
        formParent = categories.first?.id ?? ""
        formIcon = ""
        formColor = ""
        formEnabled = true
        formSortOrder = 0
        sheetKind = .category
    }

    private func openCatCreateChild() {
        formError = ""
        editingId = ""
        formName = ""
        formParent = railRootId
        formIcon = ""
        formColor = ""
        formEnabled = true
        formSortOrder = 0
        sheetKind = .category
    }

    private func openCatEdit(_ cat: CategoryNode) {
        formError = ""
        editingId = cat.id
        formName = cat.name
        formParent = cat.parentId ?? ""
        formIcon = cat.icon
        formColor = cat.color
        formEnabled = cat.isEnabled
        formSortOrder = cat.sortOrder
        sheetKind = .category
    }

    private func openPayCreate() {
        formError = ""
        editingId = ""
        formName = ""
        formType = "cash"
        formIcon = ""
        formBillingDay = 0
        formRepayDay = 0
        formSortOrder = 0
        formEnabled = true
        sheetKind = .payment
    }

    private func openPayEdit(_ p: PaymentMethodItem) {
        formError = ""
        editingId = p.id
        formName = p.name
        formType = p.type
        formIcon = p.icon
        formBillingDay = p.billingDay ?? 0
        formRepayDay = p.repaymentDay ?? 0
        formSortOrder = p.sortOrder
        formEnabled = p.isEnabled
        sheetKind = .payment
    }

    /// 新建计划：复用 form* 状态（formIcon 存 paymentMethodId、formBillingDay 存期数）
    private func openPlanCreate() {
        formError = ""
        editingId = ""
        formName = ""
        formParent = categories.first?.id ?? ""
        formIcon = payments.first?.id ?? ""
        formBillingDay = 3      // 期数
        formRepayDay = 3        // 提前提醒天数
        formEnabled = false     // 到期自动入账
        planAmountText = ""
        sheetKind = .plan
    }

    private func removeCat(_ cat: CategoryNode) async {
        do {
            try await Api.deleteCategory(id: cat.id)
            showToast("分类已删除")
            await reload()
        } catch let err as ApiError {
            reportError(err.message.contains("引用")
                        ? "该分类已有流水引用，请改为停用"
                        : err.message)
        } catch { reportError("删除失败") }
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
            if sheetKind == .category {
                let isRoot = formParent.isEmpty
                if editingId.isEmpty {
                    try await Api.createCategory(CategoryCreateRequest(
                        name: name, parentId: formParent,
                        icon: formIcon, color: formColor, sortOrder: formSortOrder))
                    showToast("分类已新增")
                } else {
                    // 二级分类不写颜色（跟随一级）；停用态原样带回 ——
                    // 之前这里写死 `icon: ""` / `color: ""` / `isEnabled: true`，
                    // 用户一编辑就把图标和颜色清空、把停用的分类重新启用。
                    try await Api.patchCategory(id: editingId, CategoryPatchRequest(
                        name: name, icon: formIcon,
                        color: isRoot ? formColor : "",
                        parentId: isRoot ? nil : formParent,
                        isEnabled: formEnabled))
                    showToast("分类已更新")
                }
            } else if sheetKind == .plan {
                // 新建计划：每期金额 × 期数 = 总额；首期还款日默认今天 + 1 个月
                let perCents = parseYuanToCents(planAmountText)
                guard perCents > 0 else {
                    formError = "请填写每期金额"
                    busy = false
                    return
                }
                guard formBillingDay >= 1, formBillingDay <= 600 else {
                    formError = "期数需在 1–600 之间"
                    busy = false
                    return
                }
                guard !formParent.isEmpty, !formIcon.isEmpty else {
                    formError = "请选择分类与支付方式"
                    busy = false
                    return
                }
                let firstDue = shiftMonth(String(todayKey().prefix(7)), 1) + "-01"
                try await Api.createPlan(PlanCreateRequest(
                    name: name,
                    categoryId: formParent,
                    paymentMethodId: formIcon,
                    source: "manual",
                    amountCents: perCents,
                    totalAmountCents: perCents * formBillingDay,
                    periods: formBillingDay,
                    firstDueDate: firstDue,
                    remindDaysBefore: max(1, formRepayDay),
                    autoPost: formEnabled,
                    note: "",
                    purchaseDate: nil
                ))
                showToast("计划已创建")
            } else {
                if editingId.isEmpty {
                    try await Api.createPayment(PaymentCreateRequest(
                        name: name, type: formType, icon: formIcon, billingDay: formBillingDay,
                        repaymentDay: formRepayDay, sortOrder: formSortOrder))
                    showToast("支付方式已新增")
                } else {
                    try await Api.patchPayment(id: editingId, PaymentPatchRequest(
                        name: name, icon: formIcon, billingDay: formBillingDay,
                        repaymentDay: formRepayDay, sortOrder: formSortOrder, isEnabled: formEnabled))
                    showToast("支付方式已更新")
                }
            }
            sheetKind = nil
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
            if sheetKind == .category {
                try await Api.deleteCategory(id: editingId)
            } else {
                try await Api.deletePayment(id: editingId)
            }
            sheetKind = nil
            await reload()
        } catch let err as ApiError {
            // 软删除：被流水引用时服务端拒绝，给可执行建议
            formError = err.message.contains("引用") || err.status == 409
                ? "该\(sheetKind == .category ? "分类" : "支付方式")已有流水引用，请改为停用"
                : err.message
        } catch {
            formError = "删除失败"
        }
    }

}
