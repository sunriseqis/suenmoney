//
//  Api.swift
//  SuenMoney
//
//  24 条路径的客户端封装（与鸿蒙 `common/net/Api.ets` 逐方法对应）。
//
//  只做「拼路径 + 调 ApiClient」，不含业务规则。
//  返回值凡是服务端会回对象但调用方不关心的，统一用 `EmptyReply`（解码一个空结构），
//  因为 URLSession 拿到的可能是 `{}` 也可能是 `{todo:...}` —— 用空结构最宽容。
//

import Foundation

/// 服务端「返回了 JSON 但调用方不关心内容」的占位
public struct EmptyReply: Decodable {
    public init() {}
}

public enum Api {

    private static var http: ApiClient { ApiClient.shared }

    // MARK: 鉴权（4）

    public static func health() async throws -> HealthBody {
        try await http.request("/api/health", RequestOptions(method: .get, withAuth: false))
    }

    public static func login(username: String, password: String) async throws -> LoginBody {
        try await http.request(
            "/api/auth/login",
            RequestOptions(method: .post,
                           body: http.encode(LoginRequest(username: username, password: password)),
                           withAuth: false)
        )
    }

    public static func me() async throws -> UserSummary {
        try await http.get("/api/auth/me")
    }

    /// 修改自己的口令：验证当前口令，成功后其他设备全部退出
    public static func changePassword(currentPassword: String, newPassword: String) async throws -> ChangePasswordBody {
        try await http.post(
            "/api/auth/me/password",
            ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
        )
    }

    // MARK: 字典（4）

    public static func categories() async throws -> CategoryList {
        try await http.get("/api/categories")
    }

    public static func paymentMethods() async throws -> PaymentMethodList {
        try await http.get("/api/payment-methods")
    }

    public static func users() async throws -> UserList {
        try await http.get("/api/users")
    }

    // MARK: 支出（5）

    /// 流水列表。检索条件交给服务端，**排序在本地做** —— 服务端不提供 sort 参数，
    /// 而「按金额」只是在当前页内重排，与 Web 的实现一致。
    public static func expenses(
        month: String,
        limit: Int,
        cursor: String? = nil,
        q: String = "",
        categoryId: String = "",
        paymentMethodId: String = "",
        ownerId: String = ""
    ) async throws -> ExpensePage {
        var path = "/api/expenses?month=\(month)&limit=\(limit)"
        if let c = cursor, !c.isEmpty {
            path += "&cursor=\(enc(c))"
        }
        if !q.isEmpty {
            path += "&q=\(enc(q))"
        }
        if !categoryId.isEmpty {
            path += "&categoryId=\(enc(categoryId))"
        }
        if !paymentMethodId.isEmpty {
            path += "&paymentMethodId=\(enc(paymentMethodId))"
        }
        if !ownerId.isEmpty {
            path += "&ownerId=\(enc(ownerId))"
        }
        return try await http.get(path)
    }

    /// 账期预览：这笔会记在哪个月（服务端算，不在客户端重实现账单周期）
    public static func previewExpense(spendDate: String, paymentMethodId: String) async throws -> ExpensePreview {
        // 预览只需要日期与支付方式；其余字段服务端忽略
        let body = ExpenseCreateRequest(
            amountCents: 0,
            categoryId: "",
            paymentMethodId: paymentMethodId,
            spendDate: spendDate,
            note: ""
        )
        return try await http.request(
            "/api/expenses/preview",
            RequestOptions(method: .post, body: http.encode(body))
        )
    }

    public static func createExpense(_ req: ExpenseCreateRequest) async throws -> ExpenseCreateBody {
        try await http.post("/api/expenses", req)
    }

    public static func updateExpense(id: String, _ req: ExpensePatchRequest) async throws -> ExpenseCreateBody {
        try await http.patch("/api/expenses/\(id)", req)
    }

    public static func deleteExpense(id: String) async throws {
        try await http.delete("/api/expenses/\(id)")
    }

    // MARK: 报表（3）

    public static func monthlyReport(month: String) async throws -> MonthlyReportBody {
        try await http.get("/api/reports/monthly?month=\(month)")
    }

    public static func yearlyReport(year: String) async throws -> YearlyReportBody {
        try await http.get("/api/reports/yearly?year=\(year)")
    }

    public static func summaryReport() async throws -> SummaryReportBody {
        try await http.get("/api/reports/summary")
    }

    // MARK: 计划与待办（5）

    public static func plans() async throws -> PlanList {
        try await http.get("/api/plans")
    }

    /// 提醒列表（流水页顶卡）：**只取该提醒的期次**，不是所有待办。
    ///
    /// 服务端 `reminderToday` 口径 = 进入提醒窗口（固定提前 3 天）的 pending，
    /// 加上「被忽略但已逾期的非自动入账期次」（逾期重现）。
    /// 传 today 才会触发服务端「到期自动入账」结算。
    public static func planTodos(today: String) async throws -> PlanTodoList {
        try await http.get("/api/plan-todos?reminderToday=\(today)&today=\(today)")
    }

    /// 全部 pending 待办（设置页「待处理期次」用，不做提醒窗口过滤）
    public static func planTodosAll(today: String) async throws -> PlanTodoList {
        try await http.get("/api/plan-todos?status=pending&today=\(today)")
    }

    /// 入账（手动确认）：可带 spendDate，但报表月份归属仍按还款日，不受影响
    public static func confirmTodo(id: String, spendDate: String = "") async throws {
        let body = spendDate.isEmpty ? "{}" : http.encode(TodoConfirmRequest(spendDate: spendDate))
        _ = try await http.requestVoid(
            "/api/plan-todos/\(id)/confirm",
            RequestOptions(method: .post, body: body)
        )
    }

    /// 确认（自动入账型待办）：只摘提醒，到期仍自动入账
    public static func ackTodo(id: String) async throws {
        _ = try await http.requestVoid(
            "/api/plan-todos/\(id)/ack",
            RequestOptions(method: .post, body: "{}")
        )
    }

    /// 忽略本期（非自动入账型）：不提醒也不入账
    public static func skipTodo(id: String) async throws {
        _ = try await http.requestVoid(
            "/api/plan-todos/\(id)/skip",
            RequestOptions(method: .post, body: "{}")
        )
    }

    // MARK: 分类写操作

    public static func createCategory(_ req: CategoryCreateRequest) async throws {
        _ = try await http.requestVoid("/api/categories", RequestOptions(method: .post, body: http.encode(req)))
    }

    public static func patchCategory(id: String, _ req: CategoryPatchRequest) async throws {
        _ = try await http.requestVoid("/api/categories/\(id)", RequestOptions(method: .patch, body: http.encode(req)))
    }

    public static func deleteCategory(id: String) async throws {
        try await http.delete("/api/categories/\(id)")
    }

    // MARK: 支付方式写操作

    public static func createPayment(_ req: PaymentCreateRequest) async throws {
        _ = try await http.requestVoid("/api/payment-methods", RequestOptions(method: .post, body: http.encode(req)))
    }

    public static func patchPayment(id: String, _ req: PaymentPatchRequest) async throws {
        _ = try await http.requestVoid("/api/payment-methods/\(id)", RequestOptions(method: .patch, body: http.encode(req)))
    }

    public static func mergePayment(id: String, intoId: String) async throws {
        _ = try await http.requestVoid(
            "/api/payment-methods/\(id)/merge",
            RequestOptions(method: .post, body: http.encode(PaymentMergeRequest(intoId: intoId)))
        )
    }

    public static func deletePayment(id: String) async throws {
        try await http.delete("/api/payment-methods/\(id)")
    }

    // MARK: 计划写操作

    public static func createPlan(_ req: PlanCreateRequest) async throws {
        _ = try await http.requestVoid("/api/plans", RequestOptions(method: .post, body: http.encode(req)))
    }

    public static func endPlan(id: String) async throws {
        _ = try await http.requestVoid("/api/plans/\(id)/end", RequestOptions(method: .post, body: "{}"))
    }

    public static func deletePlan(id: String) async throws {
        try await http.delete("/api/plans/\(id)")
    }

    // MARK: 用户管理

    public static func createUser(_ req: UserCreateRequest) async throws {
        _ = try await http.requestVoid("/api/users", RequestOptions(method: .post, body: http.encode(req)))
    }

    public static func patchUser(id: String, _ req: UserPatchRequest) async throws {
        _ = try await http.requestVoid("/api/users/\(id)", RequestOptions(method: .patch, body: http.encode(req)))
    }

    // MARK: 同步

    public static func syncPush(_ req: SyncPushRequest) async throws -> SyncPushBody {
        try await http.request(
            "/api/sync/push",
            // 批量推送可能很久，读超时放宽到 20s
            RequestOptions(method: .post, body: http.encode(req), readTimeout: 20)
        )
    }

    public static func syncPull(since: Int, limit: Int) async throws -> SyncPullBody {
        try await http.get("/api/sync/pull?since=\(since)&limit=\(limit)")
    }

    public static func syncStatus() async throws -> SyncStatusBody {
        try await http.get("/api/sync/status")
    }

    /// 撤销入账（该期次回到待办，软删对应支出）
    public static func revertTodo(id: String) async throws {
        _ = try await http.requestVoid("/api/plan-todos/\(id)/revert", RequestOptions(method: .post, body: "{}"))
    }

    /// 恢复被跳过的期次（恢复后不再当场自动入账）
    public static func restoreTodo(id: String) async throws {
        _ = try await http.requestVoid("/api/plan-todos/\(id)/restore", RequestOptions(method: .post, body: "{}"))
    }

    /// 已处理期次（confirmed / skipped）
    public static func doneTodos(status: String) async throws -> PlanTodoList {
        try await http.get("/api/plan-todos?status=\(status)")
    }

    // MARK: 工具

    private static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }
}
