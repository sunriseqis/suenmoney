//
//  Outbox.swift
//  SuenMoney
//
//  离线写入队列（B 档）。
//
//  语义照 Web 的 `web/src/utils/idb.ts` + `web/src/stores/sync.ts`，不重新发明：
//    - 八种动作：create/update/delete_expense、confirm/skip/ack/revert/restore_todo
//    - 重试 3 次，退避 5s / 10s / 30s
//    - 超限进死信，**界面上必须可见**（静默丢弃是最坏的：用户以为记上了）
//
//  为什么队列而不是「失败就重发」：断网可能持续很久，内存里的重试会在杀进程后丢光；
//  落库才能保证「关掉 App 再打开，那三笔还在队列里」。
//

import Foundation

public enum OutboxAction: String {
    case createExpense = "create_expense"
    case updateExpense = "update_expense"
    case deleteExpense = "delete_expense"
    case confirmTodo = "confirm_todo"
    case skipTodo = "skip_todo"
    case ackTodo = "ack_todo"
    case revertTodo = "revert_todo"
    case restoreTodo = "restore_todo"
}

/// 重试上限与退避（秒）。与 Web 的 OUTBOX_MAX_RETRY / 5s·10s·30s 一致
public let outboxMaxRetry = 3
public let outboxBackoff: [TimeInterval] = [5, 10, 30]

public struct OutboxEntry {
    public let id: String
    public let action: OutboxAction
    public let entityId: String
    /// JSON 字符串（原样回放给服务端）
    public let payload: String
    public let createdAt: String
    public let retryCount: Int
    public let lastError: String
}

public enum Outbox {
    /// 入队
    public static func enqueue(_ action: OutboxAction, entityId: String, payload: String) throws {
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0..<1_000_000))"
        try Db.shared.run("""
            INSERT INTO outbox (id, action, entity_id, payload, created_at, retry_count, last_error)
            VALUES (?,?,?,?,?,?,?)
            """,
            [id, action.rawValue, entityId, payload, ISO8601DateFormatter().string(from: Date()), 0, ""])
    }

    /// 待发送（按入队顺序，保证同一实体的操作不乱序）
    public static func pending() throws -> [OutboxEntry] {
        try query("retry_count < ?", [outboxMaxRetry])
    }

    /// 死信：重试用尽，必须让用户看见
    public static func deadLetters() throws -> [OutboxEntry] {
        try query("retry_count >= ?", [outboxMaxRetry])
    }

    public static func pendingCount() throws -> Int {
        try pending().count
    }

    /// 成功回放后删除
    public static func remove(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            try Db.shared.run("DELETE FROM outbox WHERE id = ?", [id])
        }
    }

    /// 失败：重试计数 +1 并记下原因（到上限后自然成为死信）
    public static func markFailed(_ id: String, error: String) throws {
        try Db.shared.run(
            "UPDATE outbox SET retry_count = retry_count + 1, last_error = ? WHERE id = ?",
            [error, id])
    }

    /// 死信重投：清零计数（用户点「重试」时）
    public static func retryDeadLetters() throws {
        try Db.shared.run(
            "UPDATE outbox SET retry_count = 0, last_error = ? WHERE retry_count >= ?",
            ["", outboxMaxRetry])
    }

    private static func query(_ whereClause: String, _ args: [Any?]) throws -> [OutboxEntry] {
        let rows = try Db.shared.query(
            "SELECT * FROM outbox WHERE \(whereClause) ORDER BY created_at ASC", args)
        return rows.map { row in
            OutboxEntry(
                id: row["id"] as? String ?? "",
                action: OutboxAction(rawValue: row["action"] as? String ?? "") ?? .createExpense,
                entityId: row["entity_id"] as? String ?? "",
                payload: row["payload"] as? String ?? "{}",
                createdAt: row["created_at"] as? String ?? "",
                retryCount: row["retry_count"] as? Int ?? 0,
                lastError: row["last_error"] as? String ?? ""
            )
        }
    }
}
