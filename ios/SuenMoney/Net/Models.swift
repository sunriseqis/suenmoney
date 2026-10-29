//
//  Models.swift
//  SuenMoney
//
//  接口模型（照 docs/api-native-contract.md 的 24 条路径，字段名不改）。
//
//  只放「类型」，不放业务规则：金额怎么算、账期怎么归属都在服务端，
//  客户端只负责搬运与展示。这样两端（iOS/鸿蒙）对着同一份契约写，不会各偏一半。
//
//  解码策略：**可能缺失的字段一律 Optional**。服务端在「无数据」时经常直接不带
//  某个键（而不是给 null/0），用非可选 + 默认值会在解码阶段整条失败 —— 这正是
//  鸿蒙端 `NaN%` 那个 bug 的来源。
//

import Foundation

// MARK: - 通用

public struct HealthBody: Decodable {
    public let ok: Bool
    public let service: String
    public let version: String
}

public struct LoginRequest: Encodable {
    public let username: String
    public let password: String
}

public struct LoginBody: Decodable {
    public let token: String
    public let expiresAt: String
    public let user: UserSummary
}

public struct UserSummary: Decodable, Identifiable, Hashable {
    public let id: String
    public let username: String
    public let displayName: String
    public let role: String
}

/// POST /api/auth/me/password 响应：被退出登录的设备数
public struct ChangePasswordBody: Decodable {
    public let revoked: Int
    public let message: String
}

public struct ChangePasswordRequest: Encodable {
    public let currentPassword: String
    public let newPassword: String
}

// MARK: - 字典

public struct CategoryNode: Decodable, Identifiable {
    public let id: String
    public let parentId: String?
    public let name: String
    public let depth: Int
    public let icon: String
    public let color: String
    public let sortOrder: Int
    public let isEnabled: Bool
    public let expenseCount: Int
    public let children: [CategoryNode]

    public init(id: String, parentId: String?, name: String, depth: Int, icon: String,
                color: String, sortOrder: Int, isEnabled: Bool, expenseCount: Int,
                children: [CategoryNode]) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.depth = depth
        self.icon = icon
        self.color = color
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.expenseCount = expenseCount
        self.children = children
    }
}

public struct CategoryList: Decodable {
    public let categories: [CategoryNode]
}

public struct PaymentMethodItem: Decodable, Identifiable {
    /// 本月笔数（R139 设置页「本月 N 笔」）；expenseCount 是全历史
    public let monthExpenseCount: Int?
    public let id: String
    public let name: String
    /// "credit" | "cash"
    public let type: String
    public let icon: String
    public let billingDay: Int?
    public let repaymentDay: Int?
    public let isEnabled: Bool
    public let sortOrder: Int
    public let expenseCount: Int
}

public struct PaymentMethodList: Decodable {
    public let paymentMethods: [PaymentMethodItem]
}

public struct UserList: Decodable {
    public let users: [UserSummary]
}

// MARK: - 支出

public struct ExpenseItem: Decodable, Identifiable, Hashable {
    public let id: String
    public let ownerId: String
    public let ownerName: String
    public let amountCents: Int
    public let categoryId: String
    public let categoryName: String
    public let categoryIcon: String
    public let categoryColor: String
    public let parentCategoryColor: String?
    public let parentCategoryName: String?
    public let paymentMethodId: String
    public let paymentMethodName: String
    public let paymentMethodType: String
    public let spendDate: String
    public let postingDate: String
    public let repaymentDate: String
    public let note: String
    public let source: String
    /// 计划来源的记录属于第几期。流水条目显示「· 3期」用它，历史记录也能补全。
    public let planPeriodSeq: Int?

    public init(id: String, ownerId: String, ownerName: String, amountCents: Int,
                categoryId: String, categoryName: String, categoryIcon: String, categoryColor: String,
                parentCategoryColor: String?, parentCategoryName: String?,
                paymentMethodId: String, paymentMethodName: String, paymentMethodType: String,
                spendDate: String, postingDate: String, repaymentDate: String,
                note: String, source: String, planPeriodSeq: Int?) {
        self.id = id
        self.ownerId = ownerId
        self.ownerName = ownerName
        self.amountCents = amountCents
        self.categoryId = categoryId
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        self.parentCategoryColor = parentCategoryColor
        self.parentCategoryName = parentCategoryName
        self.paymentMethodId = paymentMethodId
        self.paymentMethodName = paymentMethodName
        self.paymentMethodType = paymentMethodType
        self.spendDate = spendDate
        self.postingDate = postingDate
        self.repaymentDate = repaymentDate
        self.note = note
        self.source = source
        self.planPeriodSeq = planPeriodSeq
    }
}

public struct ExpensePage: Decodable {
    public let items: [ExpenseItem]
    public let nextCursor: String?
    public let hasMore: Bool
}

public struct ExpensePreview: Decodable {
    public let postingDate: String
    public let repaymentDate: String
}

public struct ExpenseCreateRequest: Encodable {
    public let amountCents: Int
    public let categoryId: String
    public let paymentMethodId: String
    public let spendDate: String
    public let note: String
}

public struct ExpenseCreateBody: Decodable {
    public let expense: ExpenseItem
}

/// 编辑用（服务端按传入字段更新）
public struct ExpensePatchRequest: Encodable {
    public let amountCents: Int
    public let categoryId: String
    public let paymentMethodId: String
    public let spendDate: String
    public let note: String
}

// MARK: - 报表

public struct CategoryBucket: Decodable, Identifiable {
    public let categoryId: String
    public let name: String
    public let icon: String
    public let color: String
    public let cents: Int
    public let count: Int
    public let ratio: Double
    /// 上期同分类金额（无上期时为 0 / 缺省）
    public let previousCents: Int?
    /// 环比（上期为 0 时服务端给 null）
    public let changeRatio: Double?
    public let children: [CategoryBucket]?

    public var id: String { categoryId }
}

public struct MonthChange: Decodable {
    public let deltaCents: Int
    public let ratio: Double?
}

public struct MonthPointRef: Decodable {
    public let month: String
    public let totalCents: Int
}

/// 同比（月报与年报**同构**：`{label, totalCents, change:{deltaCents, ratio}}`）
///
/// 原来写成平铺的 `changeCents` / `changeRatio` 是错的 —— 服务端实际返回嵌套结构，
/// 解码会直接失败（年报页整页空白）。
public struct YearAgoCompare: Decodable {
    public let label: String
    public let totalCents: Int
    public let change: MonthChange?
}

public struct LargestExpense: Decodable {
    public let expenseId: String
    public let categoryName: String
    public let cents: Int
    public let repaymentDate: String
}

public struct DailyPoint: Decodable, Identifiable {
    public let date: String
    public let day: Int
    public let cents: Int
    public let count: Int

    public var id: String { date }
}

public struct PaymentBucket: Decodable, Identifiable {
    public let paymentMethodId: String
    public let name: String
    public let type: String
    public let cents: Int
    public let count: Int
    public let repaymentDate: String?

    public var id: String { paymentMethodId }
}

public struct MemberBucket: Decodable, Identifiable {
    public let ownerId: String
    public let name: String
    public let cents: Int
    public let count: Int
    /// ⚠ 服务端**不返回**这个字段（实测）。声明为必需会让整个 MonthlyReport 解码失败 ——
    /// Swift 的 Codable 是严格的，而 ArkTS 的 interface 不做运行时校验，所以鸿蒙端没暴露这个问题。
    public let ratio: Double?

    public var id: String { ownerId }
}

public struct RollingMonth: Decodable, Identifiable {
    public let month: String
    public let totalCents: Int?
    public let count: Int

    public var id: String { month }
}

public struct MonthlyReport: Decodable {
    public let month: String
    public let totalCents: Int
    public let count: Int
    public let previous: MonthPointRef
    public let change: MonthChange
    /// 去年同月（与年报同构，带 change）
    public let yearAgo: YearAgoCompare?
    public let largest: LargestExpense?
    public let categories: [CategoryBucket]
    public let paymentMethods: [PaymentBucket]
    public let members: [MemberBucket]
    public let daily: [DailyPoint]
    public let rolling12Months: [RollingMonth]
}

public struct MonthlyReportBody: Decodable {
    public let report: MonthlyReport
}

public struct MonthPoint: Decodable, Identifiable {
    public let month: String
    public let totalCents: Int
    public let count: Int

    public var id: String { month }
}

public struct YearlyReport: Decodable {
    public let year: String
    public let totalCents: Int
    public let count: Int
    public let months: [MonthPoint]
    public let peakMonth: MonthPoint?
    /// 服务端年维度聚合（与月报同口径；R76 年档块集合用）
    public let categories: [CategoryBucket]?
    public let paymentMethods: [PaymentBucket]?
    public let members: [MemberBucket]?
    public let yearAgo: YearAgoCompare?
    public let largest: LargestExpense?
    public let average3YearsCents: Int?
}

public struct YearlyReportBody: Decodable {
    public let report: YearlyReport
}

public struct YearPoint: Decodable, Identifiable {
    public let year: String
    public let totalCents: Int
    public let count: Int

    public var id: String { year }
}

public struct SummaryReport: Decodable {
    public let totalCents: Int
    public let count: Int
    public let recordedDays: Int
    public let monthlyAverageCents: Int
    public let years: [YearPoint]
    /// 首笔日期（服务端提供则显示，缺省显示 —）
    public let firstDate: String?
    /// 单笔均值
    public let perExpenseAverageCents: Int?
    /// 全部分类聚合（概况页构成条用）
    public let categories: [CategoryBucket]?
    public let members: [MemberBucket]?
}

public struct SummaryReportBody: Decodable {
    public let report: SummaryReport
}

// MARK: - 计划与待办

public struct PlanProgress: Decodable {
    public let paidCount: Int
    public let paidCents: Int
    public let pendingCount: Int
    public let pendingCents: Int
    public let nextDueDate: String?
    public let expectedEndDate: String?
}

public struct PlanItem: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let categoryId: String
    /// 分类名与图标名（服务端随计划下发；缺省时按 id 查本地字典）
    public let categoryName: String?
    public let categoryIcon: String?
    public let paymentMethodId: String
    public let amountCents: Int
    public let firstDueDate: String
    public let autoPost: Bool
    public let source: String
    public let state: String
    public let progress: PlanProgress
}

public struct PlanList: Decodable {
    public let plans: [PlanItem]
}

public struct PlanTodoItem: Decodable, Identifiable {
    /// 该期入账后对应支出的所属月份（YYYY-MM）；未入账时为空 —— R126 跨月撤销警告用
    public let expenseMonth: String?
    public let expenseId: String?
    public let id: String
    public let planId: String
    public let planName: String
    public let periodSeq: Int
    public let amountCents: Int
    public let repaymentDate: String
    public let willAutoPost: Bool
    public let status: String
    /// 实际入账日（已入账时有值）；设置页「已处理」按它显示，而不是还款日
    public let postedDate: String?
}

public struct PlanTodoList: Decodable {
    public let settled: Int
    public let todos: [PlanTodoItem]
}

public struct TodoConfirmRequest: Encodable {
    public let spendDate: String
}

// MARK: - 用户管理

public struct UserCreateRequest: Encodable {
    public let username: String
    public let displayName: String
    public let password: String
    public let role: String
}

public struct UserPatchRequest: Encodable {
    public let displayName: String
    public let role: String
}

public struct PaymentMergeRequest: Encodable {
    public let intoId: String
}

// MARK: - 同步

public struct SyncCreateExpense: Encodable {
    public let id: String
    public let amountCents: Int
    public let categoryId: String
    public let paymentMethodId: String
    public let spendDate: String
    public let note: String
}

public struct SyncUpdateExpense: Encodable {
    public let id: String
    public let amountCents: Int?
    public let categoryId: String?
    public let paymentMethodId: String?
    public let spendDate: String?
    public let note: String?
}

public struct SyncConfirmTodo: Encodable {
    public let id: String
    public let spendDate: String
}

public struct SyncPushRequest: Encodable {
    public let expenses: [SyncCreateExpense]
    public let updatedExpenses: [SyncUpdateExpense]
    public let deletedExpenseIds: [String]
    public let confirmedTodos: [SyncConfirmTodo]
    public let skippedTodoIds: [String]
    public let ackedTodoIds: [String]
    public let revertedTodoIds: [String]
    public let restoredTodoIds: [String]
}

public struct SyncPushBody: Decodable {
    public let pushedExpensesCount: Int
    public let updatedExpensesCount: Int
    public let deletedExpensesCount: Int
    public let latestVersion: Int
}

public struct SyncChange: Decodable {
    public let version: Int
    public let entityType: String
    public let entityId: String
    public let op: String
    public let actorId: String
    public let deviceId: String
    public let createdAt: String
    /// 变更体（服务端各实体结构不同，用原始字典接，由 SyncEngine 按 entityType 映射）
    public let payload: [String: Any]

    private enum CodingKeys: String, CodingKey {
        case version, entityType, entityId, op, actorId, deviceId, createdAt, payload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        entityType = try c.decode(String.self, forKey: .entityType)
        entityId = try c.decode(String.self, forKey: .entityId)
        op = try c.decode(String.self, forKey: .op)
        actorId = try c.decode(String.self, forKey: .actorId)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        // payload 是任意 JSON 对象：先解成通用容器再转字典
        if let nested = try? c.decode(AnyJSON.self, forKey: .payload),
           case let .object(dict) = nested {
            payload = dict
        } else {
            payload = [:]
        }
    }
}

/// 任意 JSON 值的通用容器（只用于 payload 这种结构不定的字段）
public enum AnyJSON: Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: Any])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([AnyJSON].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: AnyJSON].self) {
            self = .object(o.mapValues { $0.anyValue })
        } else {
            self = .null
        }
    }

    public var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map { $0.anyValue }
        case .object(let o): return o
        }
    }
}

public struct SyncPullBody: Decodable {
    public let changes: [SyncChange]
    public let latestVersion: Int
    public let hasMore: Bool
}

public struct SyncStatusBody: Decodable {
    public let latestVersion: Int
}

// MARK: - 设置类写操作的请求体

public struct CategoryCreateRequest: Encodable {
    public let name: String
    public let parentId: String
    public let icon: String
    public let color: String
    public let sortOrder: Int
}

public struct CategoryPatchRequest: Encodable {
    public let name: String
    public let icon: String
    public let color: String
    public let parentId: String?
    public let isEnabled: Bool
}

public struct PaymentCreateRequest: Encodable {
    public let name: String
    public let type: String
    public let icon: String
    public let billingDay: Int
    public let repaymentDay: Int
    public let sortOrder: Int
}

public struct PaymentPatchRequest: Encodable {
    public let name: String
    public let icon: String
    public let billingDay: Int
    public let repaymentDay: Int
    public let sortOrder: Int
    public let isEnabled: Bool
}

public struct PlanCreateRequest: Encodable {
    public let name: String
    public let categoryId: String
    public let paymentMethodId: String
    public let source: String
    public let amountCents: Int
    public let totalAmountCents: Int
    public let periods: Int
    public let firstDueDate: String
    public let remindDaysBefore: Int
    public let autoPost: Bool
    public let note: String
    /// 消费日（`source == "installment"` 时**必填**）。
    /// 服务端要按它推算各期账单/还款日；鸿蒙端曾因漏传此字段导致建分期必然失败。
    public let purchaseDate: String?
}
