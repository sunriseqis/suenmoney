//
//  ExpenseEditor.swift
//  SuenMoney
//
//  记账抽屉（唯一写入入口，对应鸿蒙 `components/expense/ExpenseEditor.ets`，1280 行）。
//
//  结构：
//    标题行（记一笔 / 编辑支出 + 退款 + 分期 + 删除）
//    金额区（大数字 + 跨月预览）
//    字段行（分类 / 支付方式 / 消费日期 / 备注）
//    快捷分类条（5 格，与键盘列宽对齐，U14）
//    数字键盘（左列 C/B/OK + 3×3 数字；OK 键文案 = 「保存」，U07）
//
//  ⚠ iOS 与鸿蒙的差异：
//    - 弹层：内联 `bindSheet` → 本文件内的 `ZStack` 遮罩 + 居中卡片（与鸿蒙同构）
//    - 日期：**自绘日历**（不是系统 DatePicker，用户明确要求过）
//    - 键盘：**自绘**（不是系统键盘）：金额录入用应用自己的数字键盘，与 Web 移动端一致
//

import SwiftUI

public struct ExpenseEditor: View {
    @Environment(ThemeManager.self) private var theme

    /// 非 nil 即编辑已有记录
    public let editing: ExpenseItem?
    public let onSaved: (String) -> Void

    @State private var amountText: String = ""
    @State private var categoryId: String = ""
    @State private var paymentId: String = ""
    @State private var spendDate: String = todayKey()
    @State private var note: String = ""
    @State private var isRefund: Bool = false
    @State private var installment: Bool = false
    @State private var periods: Int = 3
    @State private var saving: Bool = false
    @State private var errorText: String = ""
    @State private var preview: ExpensePreview?

    @State private var categories: [CategoryNode] = []
    @State private var payments: [PaymentMethodItem] = []

    @State private var dateCalOpen: Bool = false
    @State private var dateCalYear: Int = 0
    @State private var dateCalMonth: Int = 0
    @State private var categoryOpen: Bool = false
    @State private var railRootId: String = ""
    @State private var paymentOpen: Bool = false
    /// 删除二次确认（鸿蒙有确认弹窗，iOS 之前点了就删）
    @State private var confirmDeleteOpen: Bool = false

    @FocusState private var noteFocused: Bool
    /// 本月已支出（R107：背景信息，不 await，拿不到显示占位）
    @State private var monthSpentCents: Int?

    public init(editing: ExpenseItem?, onSaved: @escaping (String) -> Void) {
        self.editing = editing
        self.onSaved = onSaved
    }

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    /// 鸿蒙 KEYPAD_KEYS：789B / 456C / 123OK / 00.（OK 跨第 3–4 行）
    private let keypadKeys: [String] = ["7", "8", "9", "B", "4", "5", "6", "C", "1", "2", "3", "OK", "0", "00", "."]
    /// 键盘行距与行高（总高 210、4 行 → 每行 48.75）
    private let keyGap: CGFloat = 5
    private let keyRowHeight: CGFloat = 48.75

    // MARK: - 生命周期

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                amountArea
                fieldRows

                // 分期付款（仅信用卡、非退款时；**编辑态也显示**）
                if isCredit && !isRefund {
                    HStack(spacing: 6) {
                        Text("分期付款")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink2))
                        Spacer(minLength: 0)
                        Toggle("", isOn: $installment)
                            .labelsHidden()
                            .tint(Color(css: tokens.accent))
                    }
                }
                // 退款（分期开启时禁用）
                HStack(spacing: 6) {
                    Text("退款")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.ink2))
                    Spacer(minLength: 0)
                    Toggle("", isOn: $isRefund)
                        .labelsHidden()
                        .tint(Color(css: tokens.accent))
                        .disabled(installment)
                }

                // 键盘上方只保留一行摘要（R107）
                HStack(spacing: 6) {
                    Text("本月已支出")
                        .font(.custom(fontMonoOf(), size: 9))
                        .foregroundStyle(Color(css: tokens.ink3))
                    Text(monthSpentCents.map { formatYuan($0) } ?? "—")
                        .font(.custom(fontMonoOf(), size: 10))
                        .monospacedDigit()
                        .foregroundStyle(Color(css: tokens.ink2))
                    Spacer(minLength: 0)
                }

                // R111：备注聚焦时**折叠数字键盘**，给一条上方辅助保存条
                if noteFocused {
                    HStack(spacing: 8) {
                        Text(formatYuan(isRefund ? -cents : cents))
                            .font(.custom(fontDisplayOf(isCyber), size: 14).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Color(css: tokens.ink))
                        Spacer(minLength: 0)
                        Button { noteFocused = false } label: {
                            Text("收起键盘")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(css: tokens.ink3))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Color(css: tokens.surface2))
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                        }
                        .buttonStyle(.plain)
                        Button { Task { await save() } } label: {
                            Text("保存")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(css: tokens.accentInk))
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Color(css: canSave ? tokens.accent : tokens.surface2))
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSave)
                    }
                    .padding(8)
                    .background(Color(css: tokens.surface2))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                } else {
                    quickBar
                    keypad
                }
                // 错误提示在**键盘之前**（原来在最后，会被安全区裁掉）
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.danger))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(css: tokens.bg))

            // 选择器弹层（遮罩 + 居中卡片）
            if categoryOpen { categoryPicker }
            if paymentOpen { paymentPicker }
            if dateCalOpen { dateCalendar }
        }
        .task {
            await loadDict()
            // 本月已支出：不 await（拿不到就显示 —），别为一行背景信息阻塞抽屉
            Task {
                monthSpentCents = try? await Api.monthlyReport(month: String(todayKey().prefix(7))).report.totalCents
            }
        }
        .onAppear { prefill() }
        .confirmationDialog("删除这笔支出？", isPresented: $confirmDeleteOpen, titleVisibility: .visible) {
            Button("删除", role: .destructive) { confirmDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不可恢复。")
        }
    }

    private func prefill() {
        if let row = editing {
            // 固定两位小数（鸿蒙 `formatCents().replace(/,/g,'')`）：
            // 用 centsToInput 会在整元时返回 "1000"，再按 0 会静默变成 10000
            amountText = formatCents(abs(row.amountCents)).replacingOccurrences(of: ",", with: "")
            categoryId = row.categoryId
            paymentId = row.paymentMethodId
            spendDate = row.spendDate
            note = row.note
            isRefund = row.amountCents < 0
        } else {
            // 沿用上次选择（仍需校验「现在仍然可选」——见 loadDict）
            if let last = LastPick.read() {
                categoryId = last.categoryId
                paymentId = last.paymentMethodId
            }
        }
    }

    // MARK: - 字典

    private func loadDict() async {
        do {
            let cats = try await Api.categories()
            // **保留全量**（含停用）：直接过滤会让停用一级的整棵子树消失，
            // 历史记录回填时 findCategory 返回 nil → 显示「选择分类」
            categories = cats.categories
            let pays = try await Api.paymentMethods()
            payments = pays.paymentMethods.filter { $0.isEnabled }
        } catch {
            // 离线：用本地缓存
            let names = (try? DictionaryDao.categoryNames()) ?? [:]
            let flat: [CategoryNode] = names.values.map {
                CategoryNode(id: $0.id, parentId: $0.parentId.isEmpty ? nil : $0.parentId,
                             name: $0.name, depth: $0.parentId.isEmpty ? 1 : 2,
                             icon: $0.icon, color: $0.color, sortOrder: 0,
                             isEnabled: true, expenseCount: 0, children: [])
            }
            // 离线时也要把二级挂回一级，否则 findCategory / quickCats 都查不到二级
            categories = flat.filter { $0.parentId == nil }.map { root in
                let kids = flat.filter { $0.parentId == root.id }
                return CategoryNode(id: root.id, parentId: nil, name: root.name, depth: 1,
                                    icon: root.icon, color: root.color, sortOrder: root.sortOrder,
                                    isEnabled: root.isEnabled, expenseCount: root.expenseCount,
                                    children: kids)
            }
        }
        // 上次选择可能已被停用 → 清掉。
        // ⚠ 必须用 findCategory 递归查（含二级）：
        //   原来只比顶层数组，导致「记在二级分类上的旧账」打开时被判定无效，
        //   然后被重置成一级 —— 编辑保存就把分类改错了。
        if findCategory(categoryId) == nil { categoryId = "" }
        if !payments.contains(where: { $0.id == paymentId }) { paymentId = "" }
        // 都没选时给第一个可用项，避免保存键永远是灰的
        if categoryId.isEmpty {
            // 默认选**二级**（鸿蒙 `firstRoot.children[0].id`），不是一级
            categoryId = quickCats().first?.id
                ?? categories.first?.children.first?.id
                ?? categories.first?.id
                ?? ""
        }
        if paymentId.isEmpty { paymentId = payments.first?.id ?? "" }
        // 兜底：支付方式不是信用卡时不能残留分期状态
        if findPayment(paymentId)?.type != "credit" { installment = false }
        await refreshPreview()
    }

    /// 快捷分类：遍历**二级**分类，取「启用且有笔数」的前 5（按笔数降序）。
    ///
    /// 之前取的是**一级**前 5 —— 语义完全不同：用户高频记的是「买菜/外卖/打车」这类
    /// 二级，一级只是「餐饮/交通」这种粗分类。
    private func quickCats() -> [CategoryNode] {
        var out: [CategoryNode] = []
        for root in categories {
            for kid in root.children where kid.isEnabled && kid.expenseCount > 0 {
                out.append(kid)
            }
        }
        out.sort { $0.expenseCount > $1.expenseCount }
        return Array(out.prefix(5))
    }

    private func findCategory(_ id: String) -> CategoryNode? {
        for root in categories {
            if root.id == id { return root }
            for child in root.children where child.id == id { return child }
        }
        return nil
    }

    private func findPayment(_ id: String) -> PaymentMethodItem? {
        payments.first { $0.id == id }
    }

    /// 切换支付方式（**所有入口都走它**）。
    /// 关键：切到非信用卡时自动清掉「分期」——否则分期状态会残留，
    /// 且按钮消失后再也无法取消。
    private func setPayment(_ id: String) {
        paymentId = id
        if findPayment(id)?.type != "credit" {
            installment = false
        }
        Task { await refreshPreview() }
    }

    private var categoryName: String {
        findCategory(categoryId)?.name ?? "选择分类"
    }

    private var paymentName: String {
        findPayment(paymentId)?.name ?? "选择支付方式"
    }

    private func catColorOf(_ cat: CategoryNode) -> String {
        if let parent = categories.first(where: { $0.id == cat.parentId }) {
            return categoryColorOf(parent.name, parent.color)
        }
        return categoryColorOf(cat.name, cat.color)
    }

    // MARK: - 金额

    private var cents: Int {
        parseYuanToCents(amountText)
    }

    private var canSave: Bool {
        cents > 0 && !categoryId.isEmpty && !paymentId.isEmpty
    }

    private func press(_ key: String) {
        // OK 就是「保存」（U07）—— 之前它掉进数字分支，按了什么都不会发生
        if key == "OK" {
            if canSave && !saving { Task { await save() } }
            return
        }
        if key == "C" {
            amountText = ""
            return
        }
        if key == "B" {
            if !amountText.isEmpty { amountText.removeLast() }
            return
        }
        if key == "." {
            if !amountText.contains(".") {
                amountText = (amountText.isEmpty ? "0" : amountText) + "."
            }
            return
        }
        if key == "00" {
            // 双零：金额为空时补一个 0，否则追加 00（不能出现前导零）
            if amountText.isEmpty || amountText == "0" {
                amountText = "0"
            } else if !amountText.contains(".") {
                let next = amountText + "00"
                if next.count <= 9 { amountText = next }
            }
            return
        }
        if key.isEmpty { return }
        let next = (amountText == "0" ? "" : amountText) + key
        if next.contains(".") {
            let parts = next.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1 && parts[1].count > 2 { return }
        }
        if next.count > 9 { return }
        amountText = next
    }

    /// 跨月预览：这笔会记在哪个月（服务端算）
    private func refreshPreview() async {
        guard !paymentId.isEmpty else { preview = nil; return }
        preview = try? await Api.previewExpense(spendDate: spendDate, paymentMethodId: paymentId)
    }

    /// 这笔的归属月份是否与消费日期不同（跨月警告）
    private var crossesMonth: Bool {
        guard let p = preview else { return false }
        return String(p.postingDate.prefix(7)) != String(spendDate.prefix(7))
    }

    private var isCredit: Bool {
        findPayment(paymentId)?.type == "credit"
    }

    // MARK: - 保存

    private func save() async {
        errorText = ""
        let value = cents
        guard value > 0 else { errorText = "请输入金额"; return }
        guard !categoryId.isEmpty, !paymentId.isEmpty else {
            errorText = "请选择分类与支付方式"
            return
        }
        saving = true
        defer { saving = false }

        do {
            if let row = editing {
                let patch = ExpensePatchRequest(
                    amountCents: isRefund ? -value : value,
                    categoryId: categoryId,
                    paymentMethodId: paymentId,
                    spendDate: spendDate,
                    note: note
                )
                let body = try await Api.updateExpense(id: row.id, patch)
                onSaved(body.expense.id)
            } else if installment {
                // 分期走计划接口（不是支出接口）：总额 + 期数，服务端生成各期待办
                // 参数顺序必须与 struct 声明一致（memberwise init）
                let planReq = PlanCreateRequest(
                    name: "\(categoryName) 分期",
                    categoryId: categoryId,
                    paymentMethodId: paymentId,
                    source: "installment",
                    amountCents: value / periods,
                    totalAmountCents: value,
                    periods: periods,
                    firstDueDate: spendDate,
                    remindDaysBefore: 3,
                    autoPost: false,
                    note: note,
                    // 分期必须带消费日（服务端按它推算各期账单/还款日）
                    purchaseDate: spendDate
                )
                try await Api.createPlan(planReq)
                onSaved("")
            } else {
                let req = ExpenseCreateRequest(
                    amountCents: isRefund ? -value : value,
                    categoryId: categoryId,
                    paymentMethodId: paymentId,
                    spendDate: spendDate,
                    note: note
                )
                let body = try await Api.createExpense(req)
                // 成功后才记住这次选择（失败的记账不该影响下次默认值）
                LastPick.write(LastPickValue(categoryId: categoryId, paymentMethodId: paymentId))
                onSaved(body.expense.id)
            }
        } catch let err as ApiError {
            if err.kind == .network && editing == nil && !installment {
                // 离线普通记账：进 Outbox，等联网补传
                await enqueueOffline(cents: value)
            } else if err.kind == .network {
                // ⚠ 与鸿蒙的一处**有意差异**：鸿蒙在分期离线时也会入队，
                //    但队列里只有 createExpense 的字段（没有 periods/purchaseDate），
                //    补传后变成一笔**普通支出** —— 用户以为记了分期，实际没记。
                //    iOS 侧宁可明确报错，也不静默降级成错误的账。
                errorText = installment
                    ? "分期需要联网创建（离线无法确定各期还款日）"
                    : "网络不可用，请稍后再试"
            } else {
                errorText = err.message
            }
        } catch {
            errorText = "保存失败"
        }
    }

    /// 离线写入。
    ///
    /// 刻意**不做乐观行**（与鸿蒙同）：本地算不出还款日（账单周期那段逻辑只在服务端），
    /// 硬造一行会让「这个月的合计」先对后错。所以只入队 + 明确告知，
    /// 联网后同步进账，用户看到的是「已排队」而不是「已入账」。
    ///
    /// 回调传 **空串**：调用方据此不做高亮（本地没有这条记录，高亮无处可指）。
    private func enqueueOffline(cents value: Int) async {
        let id = ulid()
        // 用 JSONEncoder 而不是手拼字符串：手拼只转义双引号，
        // note 里出现反斜杠/换行/制表符就会得到非法 JSON，补传时整批失败
        let draft = SyncCreateExpense(
            id: id,
            amountCents: isRefund ? -value : value,
            categoryId: categoryId,
            paymentMethodId: paymentId,
            spendDate: spendDate,
            note: note
        )
        let payload = ApiClient.shared.encode(draft)
        do {
            try Outbox.enqueue(.createExpense, entityId: id, payload: payload)
            // 空串 = 「已排队，但没有可高亮的本地行」
            onSaved("")
        } catch {
            errorText = "离线队列写入失败"
        }
    }

    private func confirmDelete() {
        guard let row = editing else { return }
        Task {
            do {
                try await Api.deleteExpense(id: row.id)
                onSaved("")
            } catch let err as ApiError {
                if err.kind == .network {
                    try? Outbox.enqueue(.deleteExpense, entityId: row.id, payload: "{}")
                    onSaved("")
                } else {
                    errorText = err.message
                }
            } catch {
                errorText = "删除失败"
            }
        }
    }

    // MARK: - 标题行

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(editing == nil ? "记一笔" : "编辑支出")
                .font(.custom(fontDisplayOf(isCyber), size: 16).weight(.bold))
                .foregroundStyle(Color(css: tokens.ink))
            // 退款标记**紧跟标题**（鸿蒙 `Row({space:8})` 内第二项），文案「退款冲销」
            if isRefund {
                Text("退款冲销")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(css: tokens.danger))
            }
            Spacer(minLength: 0)

            toggleChip("退款", isRefund) {
                isRefund.toggle()
                if isRefund { installment = false }   // 退款与分期互斥
            }
            // 分期（仅新建时）
            if editing == nil {
                // **只有信用卡类才显示「分期」**（现金分期没有业务意义）。
                // 之前常驻显示 + 点了报错但不 toggle，用户会觉得"点不掉"。
                if isCredit {
                    toggleChip("分期", installment) {
                        installment.toggle()
                        if installment { isRefund = false }
                    }
                }
            }
            if editing != nil {
                Button { confirmDeleteOpen = true } label: {
                    Text("删除")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color(css: tokens.danger))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                .stroke(Color(css: tokens.danger), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleChip(_ title: String, _ active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color(css: active ? tokens.accentInk : tokens.ink3))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(active ? Color(css: tokens.accent) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                        .stroke(Color(css: active ? tokens.accent : tokens.line), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 金额区

    /// 金额区（鸿蒙）：**右对齐** + 34pt Bold + 空值时显示 `0.00`，¥ 是 18pt ink3。
    /// 之前是左对齐 40pt Heavy + 空值显示 `0` —— 对齐方向、字号、占位三处都不同。
    private var amountArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 鸿蒙这里是 Row 未指定 alignItems → 默认**垂直居中**（不是基线/底部）
            HStack(alignment: .center, spacing: 2) {
                Text(isRefund ? "-¥" : "¥")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(css: tokens.ink3))
                Text(amountText.isEmpty ? "0.00" : amountText)
                    .font(.custom(fontDisplayOf(isCyber), size: 34).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            // 账期预览已移到备注下方独立一行（鸿蒙位置），这里不再重复
            if installment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ForEach([3, 6, 12, 24], id: \.self) { n in
                            Button { periods = n } label: {
                                Text("\(n) 期")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(css: periods == n ? tokens.accentInk : tokens.ink2))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    // 未选是 surface2、无描边（鸿蒙同）
                                    .background(Color(css: periods == n ? tokens.accent : tokens.surface2))
                                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    // 每期金额独立整行，带「约」字
                    Text("每期约 \(formatYuan(cents / max(1, periods)))")
                        .font(.custom(fontMonoOf(), size: 9))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 字段行

    private var fieldRows: some View {
        VStack(spacing: 6) {
            fieldRow(label: "分类", value: categoryName) { openCategoryPicker() }
            fieldRow(label: "消费日期", value: dateShort(spendDate)) {
                dateCalYear = Int(spendDate.prefix(4)) ?? 2026
                dateCalMonth = Int(spendDate.dropFirst(5).prefix(2)) ?? 1
                dateCalOpen = true
            }
            fieldRow(label: "支付方式", value: paymentName) { paymentOpen = true }

            // 账期预览（鸿蒙：备注下方独立一行，**所有支付方式都显示**）
            HStack(spacing: 4) {
                if let p = preview {
                    if crossesMonth {
                        Text("这笔会记在").font(.system(size: 10)).foregroundStyle(Color(css: tokens.accent))
                        Text(monthLabelCN(p.postingDate)).font(.system(size: 10)).foregroundStyle(Color(css: tokens.accent))
                        Text("（还款日 \(dateShort(p.repaymentDate))）").font(.system(size: 10)).foregroundStyle(Color(css: tokens.accent))
                    } else {
                        Text("还款日 \(p.repaymentDate)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                } else {
                    Text("账期未取到")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(css: tokens.ink3))
                }
                Spacer(minLength: 0)
                Text(formatYuan(isRefund ? -cents : cents))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color(css: tokens.ink2))
            }
            .frame(maxWidth: .infinity)
            // 备注：**整行输入框，无左标签**（鸿蒙同）；聚焦时 2px #5DB8FF 焦点环；
            // placeholder 必须显式给色，否则深色底上几乎不可见
            TextField("", text: $note,
                      prompt: Text("备注（选填）").foregroundStyle(Color(css: tokens.ink3)))
                .font(.system(size: 12))
                .foregroundStyle(Color(css: tokens.ink))
                .focused($noteFocused)
                .padding(.horizontal, 9)
                .frame(height: 36)
                .background(Color(css: fieldBgOf(tokens.surface, tokens.surface2, isCyber)))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                        .stroke(Color(css: noteFocused ? focusRing : outlineStrongOf(isCyber)),
                                lineWidth: noteFocused ? 2 : fieldBorderWOf(tokens.borderW, isCyber))
                )
        }
    }

    /// 字段行（鸿蒙 `fieldRow`）：**label 在上、value 在下两行竖排**，无固定高、无描边
    /// padding 10、bg surface2、radius rMd → 行高约 53
    private func fieldRow(label: String, value: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(css: tokens.ink3))
                    Text(value)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color(css: tokens.ink))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("›")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            .padding(10)
            .background(Color(css: tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
        }
        .buttonStyle(.plain)
    }

    /// `YYYY-MM-DD` → `2026 年 11 月`（鸿蒙 `monthLabel`）
    private func monthLabelCN(_ date: String) -> String {
        let y = Int(date.prefix(4)) ?? 2026
        let m = Int(date.dropFirst(5).prefix(2)) ?? 1
        return "\(y) 年 \(m) 月"
    }

    private func dateShort(_ date: String) -> String {
        "\(Int(date.dropFirst(5).prefix(2)) ?? 0)月\(Int(date.dropFirst(8).prefix(2)) ?? 0)日"
    }

    // MARK: - 快捷分类条（5 格，与键盘列宽对齐，U14）

    /// 快捷分类条：**5 格与键盘列宽对齐**（第 1 格 54 对齐支付列，后 4 格对齐 7/8/9/B）
    private var quickBar: some View {
        HStack(spacing: 0) {
            if let first = quickAt(0) {
                quickCell(first).frame(width: 54).padding(.trailing, 6)
            } else {
                Color.clear.frame(width: 54).padding(.trailing, 6)
            }
            // 与键盘同一条物理分割线
            Rectangle().fill(Color(css: tokens.line)).frame(width: 1, height: 40)
            HStack(spacing: 5) {
                ForEach(1..<5, id: \.self) { i in
                    if let cat = quickAt(i) {
                        quickCell(cat)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .padding(.leading, 6)
        }
    }

    private func quickCell(_ cat: CategoryNode) -> some View {
        let on = categoryId == cat.id
        let shape = RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11))
        return Button {
            categoryId = cat.id
            Task { await refreshPreview() }
        } label: {
            HStack(spacing: 4) {
                CatIconView(catName: cat.name, iconSize: 13,
                            color: on ? tokens.accentInk : catColorOf(cat))
                Text(cat.name)
                    .font(.custom(fontDisplayOf(isCyber), size: 10.5).weight(.bold))
                    .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink2))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(shape.fill(Color(css: on ? tokens.accent : tokens.surface)))
            .overlay(shape.stroke(Color(css: on ? tokens.accent : tokens.line), lineWidth: 1))
            .background {
                if !isCyber { shape.fill(Color(css: tokens.line)).offset(x: 2, y: 2) }
            }
        }
        .buttonStyle(.plain)
    }

    private func quickAt(_ i: Int) -> CategoryNode? {
        let list = quickCats()
        return i < list.count ? list[i] : nil
    }

    // MARK: - 数字键盘（左列 54vp + 3×3 数字）

    /// 键盘：**左列 54vp 支付快捷列 + 1vp 竖线 + 4×4 数字网格**（保存键跨第 3–4 行第 4 列）。
    ///
    /// 之前是「C/B/保存 塞进左列 + 3×3 数字」，列数与结构都不同 —— 这是抽屉里最显眼的结构差异。
    private var keypad: some View {
        HStack(spacing: 0) {
            // 左：支付快捷列（前 4 个 + 常驻「更多」）
            VStack(spacing: 6) {
                ForEach(Array(payments.prefix(4)), id: \.id) { p in
                    Button {
                        setPayment(p.id)
                    } label: {
                        HStack(spacing: 4) {
                            PayIconView(name: p.name, icon: p.icon, iconSize: 13,
                                        tinted: paymentId != p.id)
                            Text(shortName(p.name))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color(css: paymentId == p.id ? tokens.accentInk : tokens.ink2))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 7)
                        .background(Color(css: paymentId == p.id ? tokens.accent : tokens.surface))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                                .stroke(Color(css: tokens.line), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                // 「更多」常驻：支付方式不足 4 个时它是打开完整列表的唯一入口
                Button { paymentOpen = true } label: {
                    Text("更多")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(css: tokens.ink3))
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                        .background(Color(css: tokens.surface3))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 54)
            .frame(maxHeight: .infinity)
            .padding(.trailing, 6)

            // 支付列与数字区之间的物理分割线（鸿蒙 `Divider().vertical`）
            Rectangle().fill(Color(css: tokens.line)).frame(width: 1, height: 210)

            // 右：4×4，顺序 789B / 456C / 123+OK / 00.+OK
            //
            // SwiftUI 的 Grid 不支持跨行，所以后两行手工拼。
            // ⚠ 每行**必须给固定高度**：只写 maxHeight:.infinity 时 HStack 内没有
            // 高度参照，keyCell 会塌到最小 —— 表现就是「保存键把下面两行挤扁了」。
            // 总高 210、4 行、行距 5 → 每行 (210 - 5*3) / 4 = 48.75
            VStack(spacing: keyGap) {
                HStack(spacing: keyGap) { keyCell("7"); keyCell("8"); keyCell("9"); keyCell("B") }
                    .frame(height: keyRowHeight)
                HStack(spacing: keyGap) { keyCell("4"); keyCell("5"); keyCell("6"); keyCell("C") }
                    .frame(height: keyRowHeight)
                // 第 3–4 行必须**按列**拆，不能「左边一坨 + 右边保存」：
                // HStack 会把两个子视图各分一半宽度 → 保存键宽成 2 倍、1/2/3 被压到 1/6。
                // 改成 4 个等宽列，每列是「两个格子竖排」，第 4 列就是跨两行的保存键。
                HStack(spacing: keyGap) {
                    VStack(spacing: keyGap) { keyCell("1"); keyCell("0") }
                    VStack(spacing: keyGap) { keyCell("2"); keyCell("00") }
                    VStack(spacing: keyGap) { keyCell("3"); keyCell(".") }
                    keyCell("OK")
                }
                .frame(height: keyRowHeight * 2 + keyGap)
            }
            .frame(height: 210)
            .padding(.leading, 6)
        }
        .frame(height: 210)
    }

    /// 键帽（鸿蒙 `keypad` 里的 Button）
    /// 字号分档：保存 14 / 清空 13 / 其余 19；candy 有 2px 硬阴影；
    /// 不可保存时保存键用 surface2 底 + ink3 字（否则 candy 下看不出禁用态）。
    private func keyCell(_ key: String) -> some View {
        let isOK = key == "OK"
        let shape = RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11))
        let fontSize: CGFloat = isOK ? 14 : (key == "C" ? 13 : 19)
        return Button { press(key) } label: {
            Text(key == "B" ? "←" : (key == "C" ? "清空" : (isOK ? "保存" : key)))
                .font(.custom(fontDisplayOf(isCyber), size: fontSize).weight(.bold))
                .foregroundStyle(Color(css: isOK
                                       ? (canSave ? tokens.accentInk : tokens.ink3)
                                       : tokens.ink))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(shape.fill(Color(css: isOK
                                             ? (canSave ? tokens.accent : tokens.surface2)
                                             : tokens.surface)))
                .overlay(shape.stroke(Color(css: tokens.line), lineWidth: 1))
                .background {
                    if !isCyber { shape.fill(Color(css: tokens.line)).offset(x: 2, y: 2) }
                }
        }
        .buttonStyle(.plain)
    }

    private func shortName(_ name: String) -> String {
        // 与鸿蒙 shortName 同：超长截断到 2 字（左列只有 54vp 宽）
        name.count <= 2 ? name : String(name.prefix(2))
    }

    private func keyButton(_ title: String, isAccent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom(fontMonoOf(), size: title.count > 1 ? 13 : 18).weight(.bold))
                .foregroundStyle(Color(css: isAccent ? tokens.accentInk : tokens.ink))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isAccent ? Color(css: tokens.accent) : Color(css: tokens.surface))
                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11)))
                .overlay(
                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11))
                        .stroke(Color(css: tokens.line), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(isAccent == false && false)
    }

    // MARK: - 分类弹窗

    /// 分类弹窗（鸿蒙 `catPickerSheet`）：**左侧一级 rail（88 宽）+ 右侧 3 列网格**
    /// 打开分类弹窗时把 rail 定位到当前选中分类的父级
    private func openCategoryPicker() {
        if let cur = findCategory(categoryId) {
            railRootId = cur.parentId ?? cur.id
        } else {
            railRootId = categories.first?.id ?? ""
        }
        categoryOpen = true
    }

    private var categoryPicker: some View {
        pickerSheet(title: "选择分类", close: { categoryOpen = false }) {
            HStack(alignment: .top, spacing: 8) {
                // 左：一级 rail
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(categories) { root in
                            let on = railRootId == root.id
                            Button {
                                railRootId = root.id     // 只切 rail，不改 categoryId
                            } label: {
                                HStack(spacing: 4) {
                                    CatIconView(catName: root.name, iconSize: 13,
                                                color: on ? tokens.ink : tokens.ink2)
                                    Text(root.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(css: on ? tokens.ink : tokens.ink2))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                                .background(Color(css: on ? tokens.surface2 : "transparent"))
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 88)
                .frame(maxHeight: 160)

                // 右：当前一级下的二级，3 列网格
                let kids = railChildrenForPicker()
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(kids) { kid in
                            let on = categoryId == kid.id
                            Button {
                                categoryId = kid.id
                                categoryOpen = false
                                Task { await refreshPreview() }
                            } label: {
                                Text(kid.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(css: on ? tokens.accentInk : tokens.ink2))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(6)
                                    .background(Color(css: on ? tokens.accent : tokens.surface2))
                                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 6)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
    }

    /// 弹窗里当前 rail 下的二级（没有二级就用一级自己）
    private func railChildrenForPicker() -> [CategoryNode] {
        guard let root = categories.first(where: { $0.id == railRootId }) else {
            return categories.first?.children ?? []
        }
        return root.children.isEmpty ? [root] : root.children
    }

    // MARK: - 支付弹窗

    /// 支付弹窗（鸿蒙 `payPickerSheet`）：**行式列表**，信用卡显示账单日/还款日
    private var paymentPicker: some View {
        pickerSheet(title: "选择支付方式", close: { paymentOpen = false }) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(payments) { p in
                        let on = paymentId == p.id
                        Button {
                            setPayment(p.id)
                            paymentOpen = false
                        } label: {
                            HStack {
                                Text(p.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(css: on ? tokens.ink : tokens.ink2))
                                Spacer(minLength: 0)
                                if p.type == "credit" {
                                    // 账单周期信息：用户据此判断本期归属
                                    Text("\(p.billingDay ?? 0) 日账单 · \(p.repaymentDay ?? 0) 日还")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(css: tokens.ink3))
                                }
                            }
                            .padding(8)
                            .background(Color(css: on ? tokens.surface2 : tokens.surface))
                            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    private func pickChip(_ name: String, _ color: String, _ active: Bool,
                          _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                CatIconView(catName: name, iconSize: 13, color: active ? tokens.accentInk : color)
                Text(name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(css: active ? tokens.accentInk : tokens.ink))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(active ? Color(css: tokens.accent) : Color(css: tokens.surface2))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm))
                    .stroke(Color(css: tokens.line), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// 通用弹窗外壳：遮罩 + 居中卡片
    private func pickerSheet<Content: View>(title: String, close: @escaping () -> Void,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Text("关闭")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .buttonStyle(.plain)
                }
                content()
            }
            .padding(14)
            .frame(width: 320)
            .card(tokens, isCyber, radius: 16, surface: tokens.bg, shadow: false)
        }
    }

    // MARK: - 自绘日历（不是系统 DatePicker）

    private var dateCalendar: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { dateCalOpen = false }
            VStack(spacing: 10) {
                HStack {
                    Text("消费日期")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button { dateCalOpen = false } label: {
                        Text("关闭")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button { shiftDateMonth(-1) } label: {
                        Text("‹").font(.system(size: 18))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Text("\(dateCalYear) 年 \(dateCalMonth) 月")
                        .font(.custom(fontDisplayOf(isCyber), size: 14).weight(.bold))
                        .foregroundStyle(Color(css: tokens.ink))
                    Spacer(minLength: 0)
                    Button { shiftDateMonth(1) } label: {
                        Text("›").font(.system(size: 18))
                            .foregroundStyle(Color(css: tokens.ink2))
                            .frame(width: 34, height: 30)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 2) {
                    ForEach(weekdays, id: \.self) { w in
                        Text(w)
                            .font(.custom(fontMonoOf(), size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                            .frame(maxWidth: .infinity)
                    }
                }

                // 6×7 日格
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(Array(dayCells().enumerated()), id: \.offset) { _, d in
                        if d == 0 {
                            Color.clear.frame(height: 34)
                        } else {
                            let key = dateKeyOf(year: dateCalYear, month: dateCalMonth, day: d)
                            Button {
                                spendDate = key
                                dateCalOpen = false
                                Task { await refreshPreview() }
                            } label: {
                                Text("\(d)")
                                    .font(.custom(fontMonoOf(), size: 12.5))
                                    .foregroundStyle(Color(css: spendDate == key ? tokens.accentInk : tokens.ink))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(spendDate == key ? Color(css: tokens.accent) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rSm)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 240)
            }
            .padding(14)
            .frame(width: 330)
            .card(tokens, isCyber, radius: 16, surface: tokens.bg, shadow: false)
        }
    }

    /// 日历格：前置留白用 0 表示
    private func dayCells() -> [Int] {
        var out: [Int] = []
        // Calendar 的 weekday：1=周日 … 7=周六；这里要 0 起的列偏移
        let lead = firstWeekday(year: dateCalYear, month: dateCalMonth) - 1
        for _ in 0..<max(0, lead) { out.append(0) }
        for d in 1...daysInMonth(year: dateCalYear, month: dateCalMonth) { out.append(d) }
        while out.count % 7 != 0 { out.append(0) }
        return out
    }

    private func shiftDateMonth(_ delta: Int) {
        var m = dateCalMonth + delta
        var y = dateCalYear
        if m < 1 { m = 12; y -= 1 }
        else if m > 12 { m = 1; y += 1 }
        dateCalMonth = m
        dateCalYear = y
    }
}
