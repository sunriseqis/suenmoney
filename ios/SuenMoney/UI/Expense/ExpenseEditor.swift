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
    @State private var paymentOpen: Bool = false

    @FocusState private var noteFocused: Bool

    public init(editing: ExpenseItem?, onSaved: @escaping (String) -> Void) {
        self.editing = editing
        self.onSaved = onSaved
    }

    private var tokens: ThemeTokens { theme.tokens }
    private var isCyber: Bool { theme.isCyber }

    private let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
    private let keypadKeys: [String] = ["C", "B", "OK", "7", "8", "9", "4", "5", "6", "1", "2", "3", "0", ".", ""]

    // MARK: - 生命周期

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                titleRow
                amountArea
                fieldRows
                quickBar
                keypad
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.danger))
                        .frame(maxWidth: .infinity)
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
        .task { await loadDict() }
        .onAppear { prefill() }
    }

    private func prefill() {
        if let row = editing {
            amountText = centsToInput(abs(row.amountCents))
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
            categories = cats.categories.filter { $0.isEnabled }
            let pays = try await Api.paymentMethods()
            payments = pays.paymentMethods.filter { $0.isEnabled }
        } catch {
            // 离线：用本地缓存
            let names = (try? DictionaryDao.categoryNames()) ?? [:]
            categories = names.values.map {
                CategoryNode(id: $0.id, parentId: $0.parentId.isEmpty ? nil : $0.parentId,
                             name: $0.name, depth: $0.parentId.isEmpty ? 1 : 2,
                             icon: $0.icon, color: $0.color, sortOrder: 0,
                             isEnabled: true, expenseCount: 0, children: [])
            }
        }
        // 上次选择可能已被停用 → 清掉
        if !categories.contains(where: { $0.id == categoryId }) { categoryId = "" }
        if !payments.contains(where: { $0.id == paymentId }) { paymentId = "" }
        // 都没选时给第一个可用项，避免保存键永远是灰的
        if categoryId.isEmpty { categoryId = quickCats().first?.id ?? categories.first?.id ?? "" }
        if paymentId.isEmpty { paymentId = payments.first?.id ?? "" }
        await refreshPreview()
    }

    /// 快捷分类：一级分类取前 5（Web 同）
    private func quickCats() -> [CategoryNode] {
        Array(categories.filter { $0.parentId == nil || $0.parentId?.isEmpty == true }.prefix(5))
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
            Spacer(minLength: 0)

            // 退款冲销
            toggleChip("退款", isRefund) { isRefund.toggle() }
            // 分期（仅新建时）
            if editing == nil {
                toggleChip("分期", installment) {
                    installment.toggle()
                }
            }
            if editing != nil {
                Button { confirmDelete() } label: {
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

    private var amountArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(isRefund ? "-¥" : "¥")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(css: isRefund ? tokens.danger : tokens.ink2))
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.custom(fontDisplayOf(isCyber), size: 40).weight(.heavy))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            // 账期预览：信用卡要显示「账单月 · 还款日」
            if let p = preview, isCredit {
                Text(crossesMonth
                     ? "记入 \(String(p.postingDate.prefix(7))) · \(String(p.repaymentDate.dropFirst(5))) 还（跨月）"
                     : "\(String(p.postingDate.prefix(7))) 账单 · \(String(p.repaymentDate.dropFirst(5))) 还")
                    .font(.custom(fontMonoOf(), size: 10))
                    .foregroundStyle(Color(css: crossesMonth ? tokens.warn : tokens.ink3))
            }
            if installment {
                HStack(spacing: 6) {
                    Text("分")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(css: tokens.ink3))
                    ForEach([3, 6, 12, 24], id: \.self) { n in
                        Button { periods = n } label: {
                            Text("\(n) 期")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color(css: periods == n ? tokens.accentInk : tokens.ink2))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(periods == n ? Color(css: tokens.accent) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rPill))
                                        .stroke(Color(css: tokens.line), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if cents > 0 {
                        Text("每期 \(formatYuan(cents / periods))")
                            .font(.custom(fontMonoOf(), size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 字段行

    private var fieldRows: some View {
        VStack(spacing: 6) {
            fieldRow(label: "分类", value: categoryName) { categoryOpen = true }
            fieldRow(label: "支付方式", value: paymentName) { paymentOpen = true }
            fieldRow(label: "消费日期", value: dateShort(spendDate)) {
                dateCalYear = Int(spendDate.prefix(4)) ?? 2026
                dateCalMonth = Int(spendDate.dropFirst(5).prefix(2)) ?? 1
                dateCalOpen = true
            }
            // 备注：cyber 下 surface 贴 bg 看不出边界 → surface2；placeholder 必须显式给色
            HStack(spacing: 8) {
                Text("备注")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(width: 56, alignment: .leading)
                TextField("备注（选填）", text: $note)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink))
                    .focused($noteFocused)
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(Color(css: isCyber ? tokens.surface2 : tokens.surface))
                    .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
                    .overlay(
                        RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                            .stroke(Color(css: tokens.line2), lineWidth: tokens.borderW)
                    )
            }
        }
    }

    private func fieldRow(label: String, value: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(css: tokens.ink3))
                    .frame(width: 56, alignment: .leading)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(css: tokens.ink))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("›")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(css: tokens.ink3))
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color(css: isCyber ? tokens.surface2 : tokens.surface))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, tokens.rMd))
                    .stroke(Color(css: tokens.line2), lineWidth: tokens.borderW)
            )
        }
        .buttonStyle(.plain)
    }

    private func dateShort(_ date: String) -> String {
        "\(Int(date.dropFirst(5).prefix(2)) ?? 0)月\(Int(date.dropFirst(8).prefix(2)) ?? 0)日"
    }

    // MARK: - 快捷分类条（5 格，与键盘列宽对齐，U14）

    private var quickBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                if let cat = quickAt(i) {
                    Button {
                        categoryId = cat.id
                        Task { await refreshPreview() }
                    } label: {
                        HStack(spacing: 4) {
                            CatIconView(catName: cat.name, iconSize: 13,
                                        color: categoryId == cat.id ? tokens.accentInk : catColorOf(cat))
                            Text(cat.name)
                                .font(.custom(fontDisplayOf(isCyber), size: 10.5).weight(.bold))
                                .foregroundStyle(Color(css: categoryId == cat.id ? tokens.accentInk : tokens.ink2))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(categoryId == cat.id ? Color(css: tokens.accent) : Color(css: tokens.surface))
                        .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11)))
                        .overlay(
                            RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 11))
                                .stroke(Color(css: categoryId == cat.id ? tokens.accent : tokens.line), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func quickAt(_ i: Int) -> CategoryNode? {
        let list = quickCats()
        return i < list.count ? list[i] : nil
    }

    // MARK: - 数字键盘（左列 54vp + 3×3 数字）

    private var keypad: some View {
        HStack(alignment: .top, spacing: 5) {
            // 左列：C / B / OK
            VStack(spacing: 5) {
                keyButton("C") { press("C") }
                keyButton("B") { press("B") }
                keyButton("保存", isAccent: canSave) { press("OK") }
            }
            .frame(width: 54)

            // 3×3 数字 + 底行 0 / .
            VStack(spacing: 5) {
                ForEach([["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]], id: \.self) { rowKeys in
                    HStack(spacing: 5) {
                        ForEach(rowKeys, id: \.self) { k in
                            keyButton(k) { press(k) }
                        }
                    }
                }
                HStack(spacing: 5) {
                    keyButton("0") { press("0") }
                    keyButton(".") { press(".") }
                    // 右下角留空（与 Web 键盘一致）
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
            }
        }
        .frame(height: 210)
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

    private var categoryPicker: some View {
        pickerSheet(title: "选择分类", close: { categoryOpen = false }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categories) { root in
                        Text(root.name)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(css: tokens.ink3))
                        FlowRow(spacing: 6) {
                            pickChip(root.name, catColorOf(root), categoryId == root.id) {
                                categoryId = root.id
                                categoryOpen = false
                                Task { await refreshPreview() }
                            }
                            ForEach(root.children) { child in
                                pickChip(child.name, catColorOf(child), categoryId == child.id) {
                                    categoryId = child.id
                                    categoryOpen = false
                                    Task { await refreshPreview() }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - 支付弹窗

    private var paymentPicker: some View {
        pickerSheet(title: "选择支付方式", close: { paymentOpen = false }) {
            ScrollView {
                FlowRow(spacing: 6) {
                    ForEach(payments) { p in
                        Button {
                            paymentId = p.id
                            paymentOpen = false
                            Task { await refreshPreview() }
                        } label: {
                            HStack(spacing: 5) {
                                PayIconView(name: p.name, icon: p.icon, iconSize: 14)
                                Text(p.name)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color(css: paymentId == p.id ? tokens.accentInk : tokens.ink))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(paymentId == p.id ? Color(css: tokens.accent) : Color(css: tokens.surface2))
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
            .frame(maxHeight: 300)
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
            .background(Color(css: tokens.bg))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
            )
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
            .background(Color(css: tokens.bg))
            .clipShape(RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16)))
            .overlay(
                RoundedRectangle(cornerRadius: radiusOf(tokens, isCyber, 16))
                    .stroke(Color(css: tokens.line), lineWidth: tokens.borderW)
            )
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
