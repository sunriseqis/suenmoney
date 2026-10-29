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
/// 本地变更后 300ms 防抖再推（连续记账不会每次打一次网络）
private let debounceInterval: TimeInterval = 0.3

public struct SyncReport {
    public var pushed: Int = 0
    public var deadLettered: Int = 0
    public var pulled: Int = 0
    public var cursor: Int = 0
    public var error: String = ""
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
        if running { return report }
        running = true
        defer { running = false }

        do {
            let pushResult = try await push()
            report.pushed = pushResult.pushed
            report.deadLettered = pushResult.dead
            let pullResult = try await pull()
            report.pulled = pullResult.applied
            report.cursor = pullResult.cursor
        } catch let err as ApiError {
            report.error = err.kind == .network ? "离线：稍后自动重试" : err.message
        } catch {
            report.error = error.localizedDescription
        }
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

        for entry in entries {
            let p = parsePayload(entry.payload)
            switch entry.action {
            case .createExpense:
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
            _ = try await Api.syncPush(req)
            try Outbox.remove(entries.map { $0.id })
            result.pushed = entries.count
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
    }

    private func pull() async throws -> PullResult {
        let cursor = try readCursor()
        let body = try await Api.syncPull(since: cursor, limit: 200)
        var applied = 0
        for change in body.changes {
            try applyChange(change.entityType, change.entityId, change.op, change.payload)
            applied += 1
        }
        try writeCursor(body.latestVersion)
        return PullResult(applied: applied, cursor: body.latestVersion)
    }

    public func readCursor() throws -> Int {
        let rows = try Db.shared.query("SELECT value FROM meta WHERE key = ?", [cursorKey])
        guard let row = rows.first, let raw = row["value"] as? String else { return 0 }
        return Int(raw) ?? 0
    }

    private func writeCursor(_ value: Int) throws {
        try Db.shared.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", [cursorKey, String(value)])
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
        default: return ""
        }
    }

    /// 服务端 payload（camelCase）→ 本地列（snake_case）
    private func bucketOf(_ entityType: String, _ p: [String: Any]) -> (String, [Any?])? {
        let id = strOf(p["id"])
        guard !id.isEmpty else { return nil }
        let now = ISO8601DateFormatter().string(from: Date())

        switch entityType {
        case "expense":
            return ("""
                INSERT OR REPLACE INTO expenses
                  (id, owner_id, amount_cents, category_id, payment_method_id,
                   spend_date, posting_date, repayment_date, note, source, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)
                """,
                [id, strOf(p["ownerId"]), intOf(p["amountCents"]), strOf(p["categoryId"]),
                 strOf(p["paymentMethodId"]), strOf(p["spendDate"]), strOf(p["postingDate"]),
                 strOf(p["repaymentDate"]), strOf(p["note"]),
                 strOf(p["source"]).isEmpty ? "manual" : strOf(p["source"]),
                 strOf(p["updatedAt"]).isEmpty ? now : strOf(p["updatedAt"])])

        case "category":
            return ("""
                INSERT OR REPLACE INTO categories
                  (id, parent_id, name, depth, icon, color, sort_order, is_enabled)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [id, strOf(p["parentId"]), strOf(p["name"]),
                 intOf(p["depth"]) == 0 ? 1 : intOf(p["depth"]),
                 strOf(p["icon"]), strOf(p["color"]), intOf(p["sortOrder"]),
                 boolOf(p["isEnabled"], default: true)])

        case "payment_method":
            return ("""
                INSERT OR REPLACE INTO payment_methods
                  (id, name, type, icon, billing_day, repayment_day, is_enabled, sort_order)
                VALUES (?,?,?,?,?,?,?,?)
                """,
                [id, strOf(p["name"]),
                 strOf(p["type"]).isEmpty ? "cash" : strOf(p["type"]),
                 strOf(p["icon"]), intOf(p["billingDay"]), intOf(p["repaymentDay"]),
                 boolOf(p["isEnabled"], default: true), intOf(p["sortOrder"])])

        case "plan":
            return ("""
                INSERT OR REPLACE INTO plans
                  (id, name, category_id, payment_method_id, amount_cents, total_amount_cents,
                   purchase_date, first_due_date, remind_days_before, auto_post, source, state, note, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                [id, strOf(p["name"]), strOf(p["categoryId"]), strOf(p["paymentMethodId"]),
                 intOf(p["amountCents"]), intOf(p["totalAmountCents"]), strOf(p["purchaseDate"]),
                 strOf(p["firstDueDate"]),
                 intOf(p["remindDaysBefore"]) == 0 ? 3 : intOf(p["remindDaysBefore"]),
                 boolOf(p["autoPost"]),
                 strOf(p["source"]).isEmpty ? "manual" : strOf(p["source"]),
                 strOf(p["state"]).isEmpty ? "active" : strOf(p["state"]),
                 strOf(p["note"]),
                 strOf(p["updatedAt"]).isEmpty ? now : strOf(p["updatedAt"])])

        case "plan_todo":
            return ("""
                INSERT OR REPLACE INTO plan_todos
                  (id, plan_id, plan_name, period_seq, amount_cents, repayment_date,
                   status, will_auto_post, updated_at)
                VALUES (?,?,?,?,?,?,?,?,?)
                """,
                [id, strOf(p["planId"]), strOf(p["planName"]), intOf(p["periodSeq"]),
                 intOf(p["amountCents"]), strOf(p["repaymentDate"]),
                 strOf(p["status"]).isEmpty ? "pending" : strOf(p["status"]),
                 boolOf(p["willAutoPost"]),
                 strOf(p["updatedAt"]).isEmpty ? now : strOf(p["updatedAt"])])

        default:
            return nil
        }
    }
}
