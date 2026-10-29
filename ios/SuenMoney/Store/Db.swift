//
//  Db.swift
//  SuenMoney
//
//  本地库（SQLite3）。
//
//  设计依据 docs/plan/2026-10-21-客户端全原生化方案.md §七「离线契约」：
//    表名与 Web 的 IndexedDB 完全同名，**列名用 snake_case**，与同步快照一致 ——
//    这样「本地算出来的」和「服务端下发/上传的」是同一套字段，不需要中间的映射层。
//    映射层是最容易悄悄错位的地方（改一边忘一边），所以干脆不设。
//
//  七张表：meta / categories / payment_methods / expenses / plans / plan_todos / outbox
//  另加三个索引：expenses(repayment_date)、plan_todos(status)、outbox(created_at)。
//
//  金额一律 INTEGER（整数分）；日期一律 TEXT（YYYY-MM-DD）；布尔一律 INTEGER(0/1)。
//

import Foundation
import SQLite3

/// SQLite 的 `SQLITE_TRANSIENT`：让 SQLite 自己复制绑定进去的字符串。
/// Swift 里不能直接写这个宏，标准做法是转成一个函数指针。
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DbError: Error, LocalizedError {
    case notOpen
    case sql(String)

    public var errorDescription: String? {
        switch self {
        case .notOpen: return "Db.open() 尚未调用"
        case .sql(let m): return m
        }
    }
}

/// 极简 SQLite 封装：只提供本项目需要的 execute / query 两种形态。
public final class Db {
    public static let shared = Db()

    /// 表结构版本，改表时 +1 并在 migrate 里补分支
    public static let schemaVersion = 1

    private var handle: OpaquePointer?

    private init() {}

    /// 打开（首次会创建）并迁移到当前表结构版本
    public func open(path: String? = nil) throws {
        if handle != nil { return }

        let filePath: String
        if let p = path {
            filePath = p
        } else {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            filePath = dir.appendingPathComponent("suenmoney.db").path
        }

        var db: OpaquePointer?
        guard sqlite3_open(filePath, &db) == SQLITE_OK, let opened = db else {
            throw DbError.sql("无法打开数据库：\(filePath)")
        }
        handle = opened

        // WAL：读不阻塞写（同步在后台写、列表在前台读）
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")

        for sql in Db.createTables {
            try execute(sql)
        }
        for sql in Db.createIndexes {
            try execute(sql)
        }
        try run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
                ["schema_version", String(Db.schemaVersion)])
    }

    public func close() {
        if let h = handle {
            sqlite3_close(h)
            handle = nil
        }
    }

    // MARK: 执行

    /// 执行不取结果的语句
    public func execute(_ sql: String) throws {
        guard let h = handle else { throw DbError.notOpen }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(h, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DbError.sql("SQL 失败：\(message)\n\(sql)")
        }
    }

    /// 带参数的写（INSERT / UPDATE / DELETE）
    public func run(_ sql: String, _ args: [Any?] = []) throws {
        guard let h = handle else { throw DbError.notOpen }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, args)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DbError.sql("执行失败：\(String(cString: sqlite3_errmsg(h)))\n\(sql)")
        }
    }

    /// 查询：返回每行「列名 → 值」
    public func query(_ sql: String, _ args: [Any?] = []) throws -> [[String: Any]] {
        guard handle != nil else { throw DbError.notOpen }
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, args)

        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_NULL:
                    row[name] = nil
                default:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// 单值查询（COUNT / SUM 这类）
    public func scalarInt(_ sql: String, _ args: [Any?] = []) throws -> Int {
        let rows = try query(sql, args)
        guard let first = rows.first, let value = first.values.first else { return 0 }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    // MARK: 内部

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let h = handle else { throw DbError.notOpen }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(h, sql, -1, &stmt, nil) != SQLITE_OK {
            throw DbError.sql("准备失败：\(String(cString: sqlite3_errmsg(h)))\n\(sql)")
        }
        guard let s = stmt else { throw DbError.sql("准备失败：\(sql)") }
        return s
    }

    private func bind(_ stmt: OpaquePointer, _ args: [Any?]) throws {
        for (index, arg) in args.enumerated() {
            let pos = Int32(index + 1)
            switch arg {
            case nil:
                sqlite3_bind_null(stmt, pos)
            case let v as Int:
                sqlite3_bind_int64(stmt, pos, Int64(v))
            case let v as Bool:
                sqlite3_bind_int64(stmt, pos, v ? 1 : 0)
            case let v as Double:
                sqlite3_bind_double(stmt, pos, v)
            case let v as String:
                sqlite3_bind_text(stmt, pos, v, -1, sqliteTransient)
            default:
                sqlite3_bind_text(stmt, pos, String(describing: arg!), -1, sqliteTransient)
            }
        }
    }

    // MARK: 建表语句（IF NOT EXISTS，可反复执行）

    private static let createTables: [String] = [
        """
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY,
          parent_id TEXT,
          name TEXT NOT NULL,
          depth INTEGER NOT NULL DEFAULT 1,
          icon TEXT NOT NULL DEFAULT '',
          color TEXT NOT NULL DEFAULT '',
          sort_order INTEGER NOT NULL DEFAULT 0,
          is_enabled INTEGER NOT NULL DEFAULT 1
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS payment_methods (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          icon TEXT NOT NULL DEFAULT '',
          billing_day INTEGER,
          repayment_day INTEGER,
          is_enabled INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS expenses (
          id TEXT PRIMARY KEY,
          owner_id TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,
          category_id TEXT NOT NULL,
          payment_method_id TEXT NOT NULL,
          spend_date TEXT NOT NULL,
          posting_date TEXT NOT NULL,
          repayment_date TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          source TEXT NOT NULL DEFAULT 'manual',
          updated_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS plans (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          category_id TEXT NOT NULL,
          payment_method_id TEXT NOT NULL,
          amount_cents INTEGER NOT NULL,
          total_amount_cents INTEGER,
          purchase_date TEXT,
          first_due_date TEXT NOT NULL,
          remind_days_before INTEGER NOT NULL DEFAULT 3,
          auto_post INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'manual',
          state TEXT NOT NULL DEFAULT 'active',
          note TEXT NOT NULL DEFAULT '',
          updated_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS plan_todos (
          id TEXT PRIMARY KEY,
          plan_id TEXT NOT NULL,
          plan_name TEXT NOT NULL,
          period_seq INTEGER NOT NULL,
          amount_cents INTEGER NOT NULL,
          repayment_date TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          will_auto_post INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS outbox (
          id TEXT PRIMARY KEY,
          action TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at TEXT NOT NULL,
          retry_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT
        )
        """
    ]

    private static let createIndexes: [String] = [
        "CREATE INDEX IF NOT EXISTS idx_expenses_repayment ON expenses(repayment_date)",
        "CREATE INDEX IF NOT EXISTS idx_todos_status ON plan_todos(status)",
        "CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at)"
    ]

    /// 期望的表与列（自检用，与上面的建表语句一一对应）
    public static let expectedTables: [(name: String, columns: [String])] = [
        ("meta", ["key", "value"]),
        ("categories", ["id", "parent_id", "name", "depth", "icon", "color", "sort_order", "is_enabled"]),
        ("payment_methods", ["id", "name", "type", "icon", "billing_day", "repayment_day", "is_enabled", "sort_order"]),
        ("expenses", ["id", "owner_id", "amount_cents", "category_id", "payment_method_id", "spend_date", "posting_date", "repayment_date", "note", "source", "updated_at"]),
        ("plans", ["id", "name", "category_id", "payment_method_id", "amount_cents", "total_amount_cents", "purchase_date", "first_due_date", "remind_days_before", "auto_post", "source", "state", "note", "updated_at"]),
        ("plan_todos", ["id", "plan_id", "plan_name", "period_seq", "amount_cents", "repayment_date", "status", "will_auto_post", "updated_at"]),
        ("outbox", ["id", "action", "entity_id", "payload", "created_at", "retry_count", "last_error"])
    ]

    /// 表结构自检：返回「表(列,列,…)」多行文本，可直接贴进验收包
    public func schemaReport() throws -> String {
        var lines: [String] = []
        for table in Db.expectedTables {
            let rows = try query("PRAGMA table_info(\(table.name))")
            let cols = rows.compactMap { $0["name"] as? String }
            lines.append("\(table.name)(\(cols.joined(separator: ",")))")
        }
        return lines.joined(separator: "\n")
    }
}
