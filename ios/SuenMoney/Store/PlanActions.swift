//
//  PlanActions.swift
//  SuenMoney
//
//  待办动作：**本地先写 + 入队 + 触发同步**（与鸿蒙 `PlanActions.ets` 同构）。
//
//  ## 顺序不能反
//
//  先写本地再入队。反过来的话，本地写失败会留下「服务端会执行、本地状态没变」
//  的动作 —— 界面与服务端长期不一致。本地写失败直接抛错，队列不动。
//
//  ## 失败补偿
//
//  回推成功后由 `SyncEngine` 的 pull 把服务端的权威状态拉回来覆盖本地，
//  所以这里不需要复杂的回滚逻辑。
//

import Foundation

public enum PlanActions {
    /// 入账（手动确认）。`spendDate` 为空时按还款日入账（与服务端一致）
    public static func confirm(id: String, spendDate: String = "") async throws {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let posted = spendDate.isEmpty ? String(today) : spendDate
        try PlanDao.setStatus(id: id, status: "confirmed", postedDate: posted)
        try Outbox.enqueue(.confirmTodo, entityId: id,
                           payload: "{\"id\":\"\(id)\",\"spendDate\":\"\(spendDate)\"}")
        SyncEngine.shared.schedulePush()
    }

    /// 跳过本期（「这次别提醒我」；逾期后非自动入账的还会重现）
    public static func skip(id: String) async throws {
        try PlanDao.setStatus(id: id, status: "skipped")
        try Outbox.enqueue(.skipTodo, entityId: id, payload: "{\"id\":\"\(id)\"}")
        SyncEngine.shared.schedulePush()
    }

    /// 我知道了（摘掉提醒，不改期次状态）
    public static func ack(id: String) async throws {
        try PlanDao.setAck(id: id)
        try Outbox.enqueue(.ackTodo, entityId: id, payload: "{\"id\":\"\(id)\"}")
        SyncEngine.shared.schedulePush()
    }

    /// 撤销确认（confirmed → pending，服务端会顺带软删生成的支出）
    public static func revert(id: String) async throws {
        try PlanDao.setStatus(id: id, status: "pending", clearPosting: true)
        try Outbox.enqueue(.revertTodo, entityId: id, payload: "{\"id\":\"\(id)\"}")
        SyncEngine.shared.schedulePush()
    }

    /// 恢复跳过（skipped → pending）
    public static func restore(id: String) async throws {
        try PlanDao.setStatus(id: id, status: "pending")
        try Outbox.enqueue(.restoreTodo, entityId: id, payload: "{\"id\":\"\(id)\"}")
        SyncEngine.shared.schedulePush()
    }
}
