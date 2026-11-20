//
//  SyncEngine.swift
//  SuenMoney
//
//  同步引擎。
//
//  两件事：
//    1. **推**：把 Outbox 里的离线写入按服务端 `/api/sync/push` 的分组格式批量提交，
//       成功后删队列；失败按 5s/10s/30s 退避重试，3 次仍失败进死信（界面可见）。
//    2. **拉**：`/api/sync/pull?since=cursor` 增量拉变更，写进本地库，游标存 meta 表。
//
//  为什么推送要「分组」而不是逐条 POST：服务端一次事务落库，避免半成功；
//  逐条提交在网络抖动时会出现「这三笔进了、那两笔没进」，用户无法判断该怎么补。
//

import Foundation

private let cursorKey = "sync_cursor"
/// 游标修复版（v2.1.1）的一次性补偿标记：没有这个 key 就先重灌一次全量快照
private let resnapshotKey = "sync_resnapshot_v2"
/// 本地变更后 300ms 防抖再推（连续记账不会每次打一次网络）
private let debounceInterval: TimeInterval = 0.3
/// 单轮同步最多翻多少页（200 条/页 → 上限 1 万条变更）。
/// 设上限只为防止服务端异常导致死循环；正常一轮远达不到。
private let maxPullPages = 50

public struct SyncReport {
    public var pushed: Int = 0
    public var deadLettered: Int = 0
    public var pulled: Int = 0
    public var cursor: Int = 0
    public var error: String = ""
    /// 本次调用因「已有同步在跑」被跳过。
    /// 调用方必须区分它和「同步失败」：跳过时所有计数都是 0、error 也是空，
    /// 不判断就会把「正在同步」误报成「服务器连不上」。
    public var skipped: Bool = false
}

public actor SyncEngine {
    public static let shared = SyncEngine()

    private var debounceTask: Task<Void, Never>?
    private var running = false

    /// 本地变更后调用：300ms 内多次调用只推一次
    public func schedulePush() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = await self?.syncNow()
        }
    }

    /// 完整一轮：先推后拉（推成功后本地才有正确游标语义）
    public func syncNow() async -> SyncReport {
        var report = SyncReport()
        if running {
            report.skipped = true
            return report
        }
        running = true
        defer { running = false }

        do {
            let pushResult = try await push()
            report.pushed = pushResult.pushed
            report.deadLettered = pushResult.dead
            /*
             ⚠ 必须 `pullAll()` 而不是单次 `pull()`。
             一次 pull 只取一页（200 条）；服务端积压更多时，只拉一页就收工
             等于把剩下的变更留在服务端 —— 以前还会因为「游标被覆写成
             latestVersion」而永久跳过它们，现在游标对了，但不翻页同样拉不完。
             */
            let pullResult = try await pullAll()
            report.pulled = pullResult.applied
            report.cursor = pullResult.cursor
        } catch let err as ApiError {
            /*
             令牌失效也要打标记。
             只靠 `AuthStore.refreshMe()` 设置的话，用户在流水页记账（本地入队成功）
             后同步一直 401 失败，界面上却什么都没有 —— 队列永远推不上去，
             用户完全不知道是「登录失效了」。
             */
            if err.kind == .unauthorized {
                await MainActor.run { AuthStore.shared.sessionExpired = true }
            }
            report.error = err.kind == .network ? "离线：稍后自动重试" : err.message
        } catch {
            report.error = error.localizedDescription
        }
        /*
         本地优先之后，屏幕不再等接口返回而是读本地库 —— 所以同步写完之后
         必须发个信号让它们重读，否则界面停在旧数据直到用户手动切页。
         */
        postDataChanged()
        return report
    }

    // MARK: 推

    private struct PushResult {
        var pushed = 0
        var dead = 0
    }

    private func push() async throws -> PushResult {
        let entries = try Outbox.pending()
        var result = PushResult()
        guard !entries.isEmpty else { return result }

        var expenses: [SyncCreateExpense] = []
        var updated: [SyncUpdateExpense] = []
        var deletedIds: [String] = []
        var confirmed: [SyncConfirmTodo] = []
        var skipped: [String] = []
        var acked: [String] = []
        var reverted: [String] = []
        var restored: [String] = []

        /// 与 `expenses` 同序，用来把服务端回传的下标映射回队列条目
        var createEntries: [OutboxEntry] = []

        for entry in entries {
            let p = parsePayload(entry.payload)
            switch entry.action {
            case .createExpense:
                createEntries.append(entry)
                expenses.append(SyncCreateExpense(
                    id: entry.entityId,
                    amountCents: intOf(p["amountCents"]),
                    categoryId: strOf(p["categoryId"]),
                    paymentMethodId: strOf(p["paymentMethodId"]),
                    spendDate: strOf(p["spendDate"]),
                    note: strOf(p["note"])
                ))
            case .updateExpense:
                updated.append(SyncUpdateExpense(
                    id: entry.entityId,
                    amountCents: intOf(p["amountCents"]),
                    categoryId: strOf(p["categoryId"]),
                    paymentMethodId: strOf(p["paymentMethodId"]),
                    spendDate: strOf(p["spendDate"]),
                    note: strOf(p["note"])
                ))
            case .deleteExpense:
                deletedIds.append(entry.entityId)
            case .confirmTodo:
                confirmed.append(SyncConfirmTodo(id: entry.entityId, spendDate: strOf(p["spendDate"])))
            case .skipTodo:
                skipped.append(entry.entityId)
            case .ackTodo:
                acked.append(entry.entityId)
            case .revertTodo:
                reverted.append(entry.entityId)
            case .restoreTodo:
                restored.append(entry.entityId)
            }
        }

        let req = SyncPushRequest(
            expenses: expenses,
            updatedExpenses: updated,
            deletedExpenseIds: deletedIds,
            confirmedTodos: confirmed,
            skippedTodoIds: skipped,
            ackedTodoIds: acked,
            revertedTodoIds: reverted,
            restoredTodoIds: restored
        )

        do {
            let body = try await Api.syncPush(req)
            /*
             服务端对新增支出是**逐条容错**的：坏数据不会 4xx，而是跳过并在
             `failedExpenseIndexes` 里回传下标。只看 HTTP 200 就整批清队列，
             等于把「服务端拒收的那一笔」当成功删掉 —— 本地还在、服务器没有，
             用户以为同步完了。这里按 Web 的语义分流：
             成功项出队，被拒项留在队列里累计重试，超限自然进死信。
             */
            let failed = Set(body.failedExpenseIndexes ?? [])
            var okIds: [String] = []
            // 修改/删除/待办：服务端已逐条容错接收（与 Web 一致，视为已处理）
            for entry in entries where entry.action != .createExpense {
                okIds.append(entry.id)
            }
            for (i, entry) in createEntries.enumerated() {
                if failed.contains(i) {
                    try? Outbox.markFailed(entry.id, error: "服务端拒绝该笔新增")
                    if entry.retryCount + 1 >= outboxMaxRetry {
                        result.dead += 1
                    }
                } else {
                    okIds.append(entry.id)
                }
            }
            try Outbox.remove(okIds)
            result.pushed = okIds.count
            return result
        } catch let err as ApiError {
            // 网络错误：整批不计数（下次一起重发，保证原子性语义）
            if err.kind == .network {
                return result
            }
            // 4xx/5xx：逐条标记，超过上限的会成为死信
            for entry in entries {
                try? Outbox.markFailed(entry.id, error: err.message)
                if entry.retryCount + 1 >= outboxMaxRetry {
                    result.dead += 1
                }
            }
            return result
        }
    }

    // MARK: 拉

    private struct PullResult {
        var applied = 0
        var cursor = 0
        var hasMore = false
    }

    private func pull() async throws -> PullResult {
        let cursor = try readCursor()
        /*
         本地是空的（首装 / 换账号 / 清过库）→ 拉全量快照，而不是从 0 重放变更历史。
         放在 pull 里而不是调用方，是为了让 syncNow / refresh 两条路径都自动覆盖。
         */
        /*
         ⚠ 额外要求 outbox 为空：快照是「先清后灌」，如果本地有还没推上去的记录
           （离线刚记的账），清表会把它删掉 —— 那是真丢数据。
           有未推送项时退回增量 pull，等推送成功后再找机会快照。
         */
        let pendingCount = (try? Outbox.pendingCount()) ?? 0
        /*
         ⚠ 一次性自愈（v2.1.1）：把旧版本因游标跳跃而永久漏掉的记录补回来。

         旧版本把游标写成 `latestVersion`（见下面 `cursorAfter` 的注释），已经在用的
         设备可能从此永久缺掉「另一台设备记的那批账」—— 光修游标不会让它们回来。
         升级后**第一次同步强制重走一次全量快照**补齐，之后不再做（meta 留标记）。

         两个前置条件都是必要的：
           · outbox 必须为空 —— 快照是「先清后灌」，有没推上去的本地账会被冲掉；
           · 快照失败**只试一次**、并立刻留标记 —— 否则服务端还是老版本（没有
             快照接口）时会每次都失败，把日常同步整个卡死。
         */
        if pendingCount == 0 && needsFullResnapshot() {
            do {
                let version = try await SyncStore.bootstrap()
                try writeCursor(version)
                markFullResnapshotDone()
                return PullResult(applied: 0, cursor: version, hasMore: false)
            } catch {
                markFullResnapshotDone()
            }
        }
        if cursor == 0 && ((try? ExpenseDao.count()) ?? 0) == 0 && pendingCount == 0 {
            let version = try await SyncStore.bootstrap()
            try writeCursor(version)
            return PullResult(applied: 0, cursor: version, hasMore: false)
        }
        let body = try await Api.syncPull(since: cursor, limit: 200)
        var applied = 0
        for change in body.changes {
            try applyChange(change.entityType, change.entityId, change.op, change.payload)
            applied += 1
        }
        /*
         ⚠ 游标只能推进到**本页最后一条真正应用过的变更**（`cursorAfter`）。

         曾经的写法是 `writeCursor(body.latestVersion)` —— latestVersion 是服务端
         **全局最新版本**，一页取不完时它远大于本页最后一条。于是：
           第 1 页 (v1..v200) → 游标写成 latestVersion(=500)
           第 2 页 since=500 → 空 → hasMore=false → 收工
         v201..v500 这批变更**永久丢失，且没有任何报错**（`refresh()` 里的翻页
         循环也因此形同虚设）。表现就是「另一台设备记的账，这一台永远看不到，
         但这一台记的账对方都能看到」—— 单向同步，且只发生在落后的一端。
         */
        let next = body.cursorAfter
        try writeCursor(next)
        return PullResult(applied: applied, cursor: next, hasMore: body.hasMore)
    }

    /// 拉取直到追平：一页一页翻，直到服务端说 `hasMore == false`。
    ///
    /// 与 `pull()` 分开的原因：`syncNow` 和 `refresh` 都要「拉完」，而
    /// 「拉一页」是它们共用的原子步骤。以前 `syncNow` 直接调 `pull()`，
    /// 只有 `refresh` 自己写了循环，两条路径行为不一致。
    private func pullAll() async throws -> PullResult {
        var total = PullResult()
        for _ in 0..<maxPullPages {
            let page = try await pull()
            total.applied += page.applied
            total.cursor = page.cursor
            total.hasMore = page.hasMore
            // 本页为空还声称 hasMore：服务端数据异常，停手而不是空转
            if !page.hasMore || page.applied == 0 {
                break
            }
        }
        return total
    }

    /// **拉取一次更新**（冷启动 / 热启动各调一次）：一直翻页到 `hasMore=false`。
    ///
    /// ⚠ 必须与 `syncNow` 共用同一把锁：冷启动时 App 层会触发 syncNow，
    /// 而流水页 `.task` 又触发 refresh —— 并发 pull 会同时读游标、各自应用变更、
    /// 互相覆盖 `sync_cursor`；极端情况下一边走「本地空 → 快照（先清表）」、
    /// 另一边还在 append，数据直接错乱。
    public func refresh() async {
        if running { return }
        running = true
        defer { running = false }
        // 拉失败不抛给调用方（冷启动路径上没有错误提示的位置），但必须拉完所有页
        _ = try? await pullAll()
        postDataChanged()
    }

    /// 本地数据变了：广播给各屏重读
    private func postDataChanged() {
        NotificationCenter.default.post(name: .suenLocalDataChanged, object: nil)
    }

    public func readCursor() throws -> Int {
        let rows = try Db.shared.query("SELECT value FROM meta WHERE key = ?", [cursorKey])
        guard let row = rows.first, let raw = row["value"] as? String else { return 0 }
        return Int(raw) ?? 0
    }

    private func writeCursor(_ value: Int) throws {
        try Db.shared.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [cursorKey, String(value)])
    }

    /// 还没做过「补缺口」的全量重灌（首次升级到 v2.1.1 时为 true）
    private func needsFullResnapshot() -> Bool {
        let rows = (try? Db.shared.query("SELECT value FROM meta WHERE key = ?", [resnapshotKey])) ?? []
        return rows.isEmpty
    }

    private func markFullResnapshotDone() {
        try? Db.shared.run(
            "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [resnapshotKey, "1"])
    }

    /// 应用一条变更。
    ///
    /// 只处理本地有表的五类实体；其余（如 settings）忽略 —— 拉下来没有表可放，
    /// 硬塞会让本地库与契约悄悄分叉。
    private func applyChange(_ entityType: String, _ entityId: String, _ op: String, _ payload: [String: Any]) throws {
        let table = tableOf(entityType)
        guard !table.isEmpty else { return }
        if op == "delete" {
            try Db.shared.run("DELETE FROM \(table) WHERE id = ?", [entityId])
            return
        }

        /*
         ⚠ 分类 / 支付方式**不能**用 REPLACE：那会把本地的 `color` / `icon` 一起覆盖掉。

         这两列在本地是**各端的个性化偏好**（服务端不再存也不再下发），
         每次同步冲一遍的话，用户挑的配色每次都白设。
         所以只更新契约字段（名称/层级/排序/启用），颜色与图标保留本地值。
         */
        if entityType == "category" || entityType == "payment_method" {
            try mergeDictionary(entityType, entityId, payload)
            return
        }

        guard let (sql, args) = bucketOf(entityType, payload) else { return }
        try Db.shared.run(sql, args)
    }

    // MARK: 映射

    private func parsePayload(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func strOf(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    private func intOf(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }

    private func boolOf(_ v: Any?, default def: Bool = false) -> Int {
        if let b = v as? Bool { return b ? 1 : 0 }
        if let n = v as? NSNumber { return n.boolValue ? 1 : 0 }
        return def ? 1 : 0
    }

    private func tableOf(_ entityType: String) -> String {
        switch entityType {
        case "expense": return "expenses"
        case "category": return "categories"
        case "payment_method": return "payment_methods"
        case "plan": return "plans"
        case "plan_todo": return "plan_todos"
        case "user": return "users"
        default: return ""
        }
    }

    /// 服务端 payload（camelCase）→ 本地列（snake_case）
    /*
     ⚠ **两种命名风格并存**，必须都认：

       · `category` / `payment_method` 的 payload 是 camelCase（`parentId` / `sortOrder`）；
       · `expense` / `plan` / `plan_todo` 的 payload 是 **snake_case**（`owner_id` / `amount_cents`）。

     旧实现一律按 camelCase 读，于是每次增量拉取都把本地支出写成
     `owner_id=''`、`amount_cents=0` —— 数据被静默冲成空值。
     与鸿蒙 `SyncEngine.ets` 的 `pick()` 同一套修法。
     */
    private func pick(_ p: [String: Any], _ snake: String, _ camel: String) -> Any? {
        if let v = p[snake], !(v is NSNull) { return v }
        if let v = p[camel], !(v is NSNull) { return v }
        return nil
    }

    private func str2(_ p: [String: Any], _ snake: String, _ camel: String) -> String {
        strOf(pick(p, snake, camel))
    }

    private func int2(_ p: [String: Any], _ snake: String, _ camel: String) -> Int {
        intOf(pick(p, snake, camel))
    }

    private func bool2(_ p: [String: Any], _ snake: String, _ camel: String, default def: Bool) -> Int {
        boolOf(pick(p, snake, camel), default: def)
    }

    /// 字典实体（分类 / 支付方式）的增量合并：只更新契约字段，保留本地 color / icon
    private func mergeDictionary(_ entityType: String, _ id: String, _ p: [String: Any]) throws {
        let existing = try Db.shared.query(
            "SELECT id FROM \(entityType == "category" ? "categories" : "payment_methods") WHERE id = ?",
            [id])
        let isNew = existing.isEmpty

        if entityType == "category" {
            if isNew {
                try Db.shared.run("""
                    INSERT OR REPLACE INTO categories
                      (id, parent_id, name, depth, icon, color, sort_order, is_enabled)
                    VALUES (?,?,?,?, '', '', ?,?)
                    """,
                    [id, str2(p, "parent_id", "parentId"), str2(p, "name", "name"),
                     int2(p, "depth", "depth") == 0 ? 1 : int2(p, "depth", "depth"),
                     int2(p, "sort_order", "sortOrder"),
                     bool2(p, "is_enabled", "isEnabled", default: true)])
            } else {
                try Db.shared.run("""
                    UPDATE categories SET parent_id = ?, name = ?, depth = ?,
                           sort_order = ?, is_enabled = ? WHERE id = ?
                    """,
                    [str2(p, "parent_id", "parentId"), str2(p, "name", "name"),
                     int2(p, "depth", "depth") == 0 ? 1 : int2(p, "depth", "depth"),
                     int2(p, "sort_order", "sortOrder"),
                     bool2(p, "is_enabled", "isEnabled", default: true), id])
            }
            return
        }

        // payment_method
        let type = str2(p, "type", "type")
        if isNew {
            try Db.shared.run("""
                INSERT OR REPLACE INTO payment_methods
                  (id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order)
                VALUES (?,?,?, '', ?,?,?,?)
                """,
                [id, str2(p, "name", "name"), type.isEmpty ? "cash" : type,
                 int2(p, "billing_day", "billingDay"), int2(p, "repayment_day", "repaymentDay"),
                 bool2(p, "is_enabled", "isEnabled", default: true),
                 int2(p, "sort_order", "sortOrder")])
        } else {
            try Db.shared.run("""
                UPDATE payment_methods SET name = ?, type = ?, billing_day = ?,
                       repayment_day = ?, is_enabled = ?, sort_order = ? WHERE id = ?
                """,
                [str2(p, "name", "name"), type.isEmpty ? "cash" : type,
                 int2(p, "billing_day", "billingDay"), int2(p, "repayment_day", "repaymentDay"),
                 bool2(p, "is_enabled", "isEnabled", default: true),
                 int2(p, "sort_order", "sortOrder"), id])
        }
    }

    private func bucketOf(_ entityType: String, _ p: [String: Any]) -> (String, [Any?])? {
        let id = strOf(p["id"])
        guard !id.isEmpty else { return nil }
        let now = ISO8601DateFormatter().string(from: Date())

        switch entityType {
        case "expense":
            return ("""
                INSERT OR REPLACE INTO expenses
                  (id, owner_id, amount_cents, category_id, payment_method_id,
                   spend_date, posting_date, repayment_date, note, source,
                   plan_id, plan_period_seq, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [id, str2(p, "owner_id", "ownerId"), int2(p, "amount_cents", "amountCents"),
                 str2(p, "category_id", "categoryId"), str2(p, "payment_method_id", "paymentMethodId"),
                 str2(p, "spend_date", "spendDate"), str2(p, "posting_date", "postingDate"),
                 str2(p, "repayment_date", "repaymentDate"), str2(p, "note", "note"),
                 str2(p, "source", "source").isEmpty ? "manual" : str2(p, "source", "source"),
                 str2(p, "plan_id", "planId"), int2(p, "plan_period_seq", "planPeriodSeq"),
                 str2(p, "updated_at", "updatedAt").isEmpty ? now : str2(p, "updated_at", "updatedAt")])

        case "category":
            return ("""
                INSERT OR REPLACE INTO categories
                  (id, parent_id, name, depth, icon, color, sort_order, is_enabled)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                // ⚠ 必须走 pick() 双键：snake_case 优先、camelCase 兜底。
                // 曾经这里只读 `p["parentId"]`/`p["sortOrder"]`/`p["isEnabled"]` ——
                // 服务端一旦把字段改成 snake_case，本地会把 sort_order=0、
                // is_enabled=true 之类**静默冲成默认值**，且无任何报错。
                // expense / plan / plan_todo 分支早就用了 str2/int2/bool2，
                // 这里与它们必须同口径。
                [id, str2(p, "parent_id", "parentId"), str2(p, "name", "name"),
                 int2(p, "depth", "depth") == 0 ? 1 : int2(p, "depth", "depth"),
                 str2(p, "icon", "icon"), str2(p, "color", "color"),
                 int2(p, "sort_order", "sortOrder"),
                 bool2(p, "is_enabled", "isEnabled", default: true)])

        case "payment_method":
            return ("""
                INSERT OR REPLACE INTO payment_methods
                  (id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                // ⚠ 同上：必须走 pick() 双键
                [id, str2(p, "name", "name"),
                 str2(p, "type", "type").isEmpty ? "cash" : str2(p, "type", "type"),
                 str2(p, "icon", "icon"),
                 int2(p, "billing_day", "billingDay"), int2(p, "repayment_day", "repaymentDay"),
                 bool2(p, "is_enabled", "isEnabled", default: true),
                 int2(p, "sort_order", "sortOrder")])

        case "user":
            // 用户（显示名/角色）：流水行要显示「记录人」，改了名字就得跟着更新
            return ("""
                INSERT OR REPLACE INTO users (id, display_name, role, updated_at)
                VALUES (?,?,?,?)
                """,
                [id, str2(p, "display_name", "displayName"),
                 str2(p, "role", "role").isEmpty ? "member" : str2(p, "role", "role"),
                 str2(p, "updated_at", "updatedAt").isEmpty ? now : str2(p, "updated_at", "updatedAt")])

        case "plan":
            return ("""
                INSERT OR REPLACE INTO plans
                  (id, name, category_id, payment_method_id, amount_cents, total_amount_cents,
                   purchase_date, first_due_date, remind_days_before, auto_post, source, state, note, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [id, str2(p, "name", "name"), str2(p, "category_id", "categoryId"),
                 str2(p, "payment_method_id", "paymentMethodId"),
                 int2(p, "amount_cents", "amountCents"),
                 int2(p, "total_amount_cents", "totalAmountCents"),
                 str2(p, "purchase_date", "purchaseDate"),
                 str2(p, "first_due_date", "firstDueDate"),
                 int2(p, "remind_days_before", "remindDaysBefore") == 0
                    ? 3 : int2(p, "remind_days_before", "remindDaysBefore"),
                 bool2(p, "auto_post", "autoPost", default: false),
                 str2(p, "source", "source").isEmpty ? "manual" : str2(p, "source", "source"),
                 str2(p, "state", "state").isEmpty ? "active" : str2(p, "state", "state"),
                 str2(p, "note", "note"),
                 str2(p, "updated_at", "updatedAt").isEmpty ? now : str2(p, "updated_at", "updatedAt")])

        case "plan_todo":
            return ("""
                INSERT OR REPLACE INTO plan_todos
                  (id, plan_id, plan_name, period_seq, amount_cents, repayment_date,
                   status, will_auto_post, expense_id, posted_date, ack_at, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [id, str2(p, "plan_id", "planId"),
                 // plan_name 是历史冗余列：payload 不带，留空由读取时 JOIN plans 补
                 str2(p, "plan_name", "planName"),
                 int2(p, "period_seq", "periodSeq"),
                 int2(p, "amount_cents", "amountCents"),
                 str2(p, "repayment_date", "repaymentDate"),
                 str2(p, "status", "status").isEmpty ? "pending" : str2(p, "status", "status"),
                 bool2(p, "will_auto_post", "willAutoPost", default: false),
                 str2(p, "expense_id", "expenseId"),
                 str2(p, "posted_date", "postedDate"),
                 str2(p, "ack_at", "ackAt"),
                 str2(p, "updated_at", "updatedAt").isEmpty ? now : str2(p, "updated_at", "updatedAt")])

        default:
            return nil
        }
    }
}

/// 本地数据变更通知：各屏 `.onReceive` 它来重读本地库
public extension Notification.Name {
    static let suenLocalDataChanged = Notification.Name("suenLocalDataChanged")
}
