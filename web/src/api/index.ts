/**
 * 接口封装。
 *
 * 刻意放在一个文件里而不是按资源拆成 5 个：总共 20 来个方法，拆开之后
 * 「某个接口在哪个文件」就成了需要翻找的问题，收益不抵成本。
 * 真正需要拆的是类型（`types.ts`），因为它的体积会随功能持续增长。
 */
import { downloadFile, request } from './client';
import type {
  Category,
  DataOverview,
  DemoResetReport,
  Expense,
  ExpensePage,
  ExportScopeKind,
  LedgerWipeReport,
  MonthlyReport,
  PaymentMethod,
  PaymentMethodType,
  Plan,
  PlanSource,
  PlanTodo,
  PlanTodoStatus,
  SnapshotInfo,
  TransferResult,
  SummaryReport,
  User,
  UserRole,
  WebdavConfig,
  WebdavStatus,
  YearlyReport,
} from './types';

export * from './client';
export type * from './types';
export * as updateApi from './update';

// ---- 认证 -----------------------------------------------------------------

export const auth = {
  /** 首次初始化。仅在系统里一个用户都没有时可用，之后永久 403 */
  status: () => request<{ needsSetup: boolean }>('/api/auth/status'),

  setup: (username: string, displayName: string, password: string) =>
    request<{ token: string; expiresAt: string; user: User }>('/api/auth/setup', {
      method: 'POST',
      body: { username, displayName, password },
    }),

  login: (username: string, password: string, deviceLabel = '') =>
    request<{ token: string; expiresAt: string; user: User }>('/api/auth/login', {
      method: 'POST',
      body: { username, password, deviceLabel },
    }),

  logout: () => request<void>('/api/auth/logout', { method: 'POST' }),

  me: () => request<{ user: User }>('/api/auth/me'),

  /** 修改自己的显示名（自助，无需管理员） */
  updateMe: (displayName: string) =>
    request<{ user: User }>('/api/auth/me', { method: 'PATCH', body: { displayName } }),

  /** 修改自己的密码：验证当前口令，成功后其他设备全部退出 */
  changePassword: (currentPassword: string, newPassword: string) =>
    request<{ revoked: number; message: string }>('/api/auth/me/password', {
      method: 'POST',
      body: { currentPassword, newPassword },
    }),

  sessions: () =>
    request<{
      sessions: Array<{
        id: string;
        deviceLabel: string;
        createdAt: string;
        lastSeenAt: string;
        expiresAt: string;
        current: boolean;
      }>;
    }>('/api/auth/sessions'),

  revokeOthers: () =>
    request<{ revoked: number }>('/api/auth/sessions/revoke-others', { method: 'POST' }),
};

// ---- 账号 -----------------------------------------------------------------

export const users = {
  list: () => request<{ users: User[] }>('/api/users'),

  create: (input: { username: string; displayName: string; password: string; role?: UserRole }) =>
    request<{ user: User }>('/api/users', { method: 'POST', body: input }),

  update: (id: string, input: { displayName?: string; role?: UserRole; password?: string }) =>
    request<{ user: User }>(`/api/users/${id}`, { method: 'PATCH', body: input }),
};

// ---- 分类 -----------------------------------------------------------------

export const categories = {
  list: () => request<{ categories: Category[] }>('/api/categories'),

  create: (input: { name: string; parentId?: string | null; icon?: string; color?: string }) =>
    request<{ category: Category }>('/api/categories', { method: 'POST', body: input }),

  update: (
    id: string,
    input: {
      name?: string;
      /** 移动分类。只允许**同深度**（二级在一级之间平移）；传 null 会被服务端拒绝 */
      parentId?: string | null;
      icon?: string;
      color?: string;
      sortOrder?: number;
      isEnabled?: boolean;
    },
  ) => request<{ category: Category }>(`/api/categories/${id}`, { method: 'PATCH', body: input }),

  remove: (id: string) => request<{ ok: true }>(`/api/categories/${id}`, { method: 'DELETE' }),
};

// ---- 支付方式 -------------------------------------------------------------

export const paymentMethods = {
  list: () => request<{ paymentMethods: PaymentMethod[] }>('/api/payment-methods'),

  create: (input: {
    name: string;
    type: PaymentMethodType;
    icon?: string;
    billingDay?: number;
    repaymentDay?: number;
    sortOrder?: number;
  }) => request<{ paymentMethod: PaymentMethod }>('/api/payment-methods', { method: 'POST', body: input }),

  update: (
    id: string,
    input: {
      name?: string;
      icon?: string;
      billingDay?: number;
      repaymentDay?: number;
      sortOrder?: number;
      isEnabled?: boolean;
    },
  ) => request<{ paymentMethod: PaymentMethod }>(`/api/payment-methods/${id}`, { method: 'PATCH', body: input }),

  remove: (id: string) => request<{ ok: true }>(`/api/payment-methods/${id}`, { method: 'DELETE' }),

  merge: (
    id: string,
    input: {
      targetId: string;
      deleteSource?: boolean;
    },
  ) =>
    request<{
      movedExpenses: number;
      movedPlans: number;
      sourceDeleted: boolean;
    }>(`/api/payment-methods/${id}/merge`, { method: 'POST', body: input }),
};

// ---- 支出 -----------------------------------------------------------------

export interface ExpenseQuery {
  month?: string;
  by?: 'spend_date' | 'repayment_date';
  from?: string;
  to?: string;
  categoryId?: string;
  paymentMethodId?: string;
  ownerId?: string;
  q?: string;
  limit?: number;
  cursor?: string;
}

export const expenses = {
  list: (query: ExpenseQuery = {}) => request<ExpensePage>('/api/expenses', { query: { ...query } }),

  get: (id: string) => request<{ expense: Expense }>(`/api/expenses/${id}`),

  /**
   * 预览入账日与还款日（不落库）。
   *
   * 用途：记账抽屉在用户选完支付方式与日期后，立刻告诉他「这笔会记在哪个月」。
   * 没有这个提示，用户会看到「刚记完本月还是 0」而以为保存失败 ——
   * 因为信用卡的还款日很可能落在下个月。
   *
   * 刻意做成一次请求而不是在前端重算：账单周期是整个项目最容易「看着对、
   * 少数情况下错一个月」的逻辑，两份实现迟早漂移，而且漂移方式是安静地算错。
   */
  preview: (input: { spendDate: string; paymentMethodId: string }) =>
    request<{ postingDate: string; repaymentDate: string }>('/api/expenses/preview', {
      method: 'POST',
      body: input,
    }),

  create: (input: {
    amountCents: number;
    categoryId: string;
    paymentMethodId: string;
    spendDate: string;
    note?: string;
  }) => request<{ expense: Expense }>('/api/expenses', { method: 'POST', body: input }),

  update: (
    id: string,
    input: {
      amountCents?: number;
      categoryId?: string;
      paymentMethodId?: string;
      spendDate?: string;
      note?: string;
    },
  ) => request<{ expense: Expense }>(`/api/expenses/${id}`, { method: 'PATCH', body: input }),

  remove: (id: string) => request<void>(`/api/expenses/${id}`, { method: 'DELETE' }),

  batchCreate: (
    items: Array<{
      amountCents: number;
      categoryId: string;
      paymentMethodId: string;
      spendDate: string;
      note?: string;
    }>,
  ) =>
    request<{ createdCount: number; expenseIds: string[] }>('/api/expenses/batch', {
      method: 'POST',
      body: { items },
    }),

  /** 把某分类下的全部记录转移到另一个分类（停用分类前用） */
  transfer: (fromCategoryId: string, toCategoryId: string) =>
    request<{ moved: number }>('/api/expenses/transfer', {
      method: 'POST',
      body: { fromCategoryId, toCategoryId },
    }),
};

// ---- 报表 -----------------------------------------------------------------

// ---- 计划与待办 -----------------------------------------------------------

export interface PlanCreateInput {
  name: string;
  categoryId: string;
  paymentMethodId: string;
  source: PlanSource;
  /** 手动计划：每期金额 */
  amountCents?: number;
  /** 分期：消费原价总额 */
  totalAmountCents?: number;
  purchaseDate?: string;
  periods: number;
  firstDueDate: string;
  remindDaysBefore?: number;
  autoPost?: boolean;
  note?: string;
  /** 是否在创建后立即确认第一期（用于记账抽屉顺手分期：创建计划同时首期直接入账） */
  confirmFirst?: boolean;
  confirmSpendDate?: string;
}

export interface PlanUpdateInput {
  name?: string;
  categoryId?: string;
  paymentMethodId?: string;
  amountCents?: number;
  firstDueDate?: string;
  remindDaysBefore?: number;
  autoPost?: boolean;
  note?: string;
  /** 从「最后一期已确认期 + 1」起还要多少期。不传则维持当前剩余期数 */
  remainingPeriods?: number;
}

export const plans = {
  list: () => request<{ plans: Plan[] }>('/api/plans'),

  get: (id: string) => request<{ plan: Plan; todos: PlanTodo[] }>(`/api/plans/${id}`),

  create: (input: PlanCreateInput) =>
    request<{ plan: Plan }>('/api/plans', { method: 'POST', body: input }),

  update: (id: string, input: PlanUpdateInput) =>
    request<{ plan: Plan }>(`/api/plans/${id}`, { method: 'PATCH', body: input }),

  end: (id: string) => request<{ plan: Plan }>(`/api/plans/${id}/end`, { method: 'POST' }),
  delete: (id: string) => request<void>(`/api/plans/${id}`, { method: 'DELETE' }),
};

export interface PlanTodoQuery {
  /** 传了才会先结算到期的自动入账待办 */
  today?: string;
  planId?: string;
  status?: PlanTodoStatus;
  /** 只返回提醒日已到的（含逾期） */
  remindBefore?: string;
  from?: string;
  to?: string;
  /**
   * 排除已点过「确认」的期次。
   *
   * 「该处理了」列表传 true；计划详情**不要传** ——
   * 那里那一期仍然是 `pending`，用户得看得见自己确认过什么。
   */
  hideAcked?: boolean;
  limit?: number;
}

export const planTodos = {
  list: (query: PlanTodoQuery = {}) =>
    request<{ settled: number; todos: PlanTodo[] }>('/api/plan-todos', { query: { ...query } }),

  /** spendDate 是「实际哪天付的」，可选；不影响报表月份归属 */
  confirm: (id: string, spendDate?: string) =>
    request<{ todo: PlanTodo; expenseId: string }>(`/api/plan-todos/${id}/confirm`, {
      method: 'POST',
      body: spendDate === undefined ? {} : { spendDate },
    }),

  skip: (id: string) =>
    request<{ todo: PlanTodo }>(`/api/plan-todos/${id}/skip`, { method: 'POST', body: {} }),

  /**
   * 「我知道了」—— 确认一条**会自动入账**的提醒。
   *
   * 与 `confirm` 不是同义词，别混用：
   *   · `confirm` 生成那笔支出（`pending → confirmed`）；
   *   · `ack` **什么业务状态都不改**，只让这条从「该处理了」里消失，
   *     到还款日照旧自动入账。
   *
   * 用错了不会报错 —— 只会让账目静默地少一笔（误用 ack 当成入账）
   * 或提前一笔（误用 confirm 当成知悉）。判据是 `todo.willAutoPost`。
   */
  ack: (id: string) =>
    request<{ todo: PlanTodo }>(`/api/plan-todos/${id}/ack`, { method: 'POST', body: {} }),

  /**
   * 撤销一次确认：该期生成的支出被软删，待办回到 `pending` 且不再自动入账。
   *
   * 返回被撤掉的那条支出 id，调用方可以用它做提示（「已撤销 ¥X 的入账」）。
   */
  revert: (id: string) =>
    request<{ todo: PlanTodo; expenseId: string }>(`/api/plan-todos/${id}/revert`, {
      method: 'POST',
      body: {},
    }),

  /** 恢复一个被跳过的期次（`skipped → pending`）。 */
  restore: (id: string) =>
    request<{ todo: PlanTodo }>(`/api/plan-todos/${id}/restore`, { method: 'POST', body: {} }),
};

export const reports = {
  /**
   * 月度报表。
   *
   * `month` 必须传：服务端不会推算「当前是几月」—— 它常年跑 UTC，
   * 而「今天」只对客户端所在时区有意义。所以由这里按本地日期算好再传。
   */
  monthly: (month: string, ownerId?: string) =>
    request<{ report: MonthlyReport }>('/api/reports/monthly', { query: { month, ownerId } }),

  yearly: (year: string, ownerId?: string) =>
    request<{ report: YearlyReport }>('/api/reports/yearly', { query: { year, ownerId } }),

  summary: (ownerId?: string) =>
    request<{ report: SummaryReport }>('/api/reports/summary', { query: { ownerId } }),
};

// ---- 数据 -----------------------------------------------------------------

/** 导出 / 备份的范围。`period` 在 `all` 时**不要传** —— 服务端会明确拒绝它。 */
export interface DataScopeQuery {
  scope: ExportScopeKind;
  period?: string;
}

export const data = {
  /** 概览：现在库里有什么、存档在哪、重置演示数据能不能按 */
  overview: () => request<{ overview: DataOverview }>('/api/data/overview'),

  /**
   * 导出数据包（JSON，**能再导回来**）。
   *
   * 与 `exportCsv` 是同一份数据的两种投影，不是两个功能：
   * JSON 负责往返，CSV 负责「人能看懂、能核对」。
   */
  exportPackage: (query: DataScopeQuery) => downloadFile('/api/export', { ...query }),

  /** 导出对账表（CSV，Excel 直接打开）。 */
  exportCsv: (query: DataScopeQuery) => downloadFile('/api/export/expenses.csv', { ...query }),

  /** 备份**始终全量**，没有范围参数 —— 它只服务「一键恢复」。 */
  backup: () => downloadFile('/api/backup'),

  /** 导入 = 合并去重，不覆盖。同一份文件按两次也不会多出记录。 */
  import: (pkg: unknown) => request<TransferResult>('/api/import', { method: 'POST', body: pkg }),

  /** 恢复 = 文件覆盖本地，且**不删除**本地多出来的记录。只接受 backup 信封。 */
  restore: (pkg: unknown) =>
    request<TransferResult>('/api/backup/restore', { method: 'POST', body: pkg }),

  /**
   * 清空全部**账目**（支出 / 计划 / 待办），保留分类 / 支付方式 / 账号。
   *
   * `confirm` 是字面量而不是布尔：服务端要求调用方把动作名写出来，
   * 免得一个手滑的请求就把全家的账清掉。
   */
  wipe: () =>
    request<{ report: LedgerWipeReport }>('/api/data/wipe', {
      method: 'POST',
      body: { confirm: 'wipe' },
    }),

  /** 重置演示数据。日期相对 `today` 现算，所以「今天」必须由客户端给。 */
  resetDemo: (today: string) =>
    request<{ report: DemoResetReport }>('/api/data/reset-demo', {
      method: 'POST',
      body: { confirm: 'reset-demo', today },
    }),
};

export const snapshots = {
  /** 获取运维数据库物理快照列表 */
  list: () => request<{ snapshots: SnapshotInfo[] }>('/api/snapshots'),

  /** 触发一次即时 VACUUM INTO 物理快照 */
  create: () => request<{ snapshot: SnapshotInfo }>('/api/snapshots', { method: 'POST' }),

  /** 下载指定快照文件（.sqlite） */
  download: (filename: string) => downloadFile(`/api/snapshots/${encodeURIComponent(filename)}`),

  /** 删除指定快照文件 */
  remove: (filename: string) =>
    request<{ success: boolean }>(`/api/snapshots/${encodeURIComponent(filename)}`, {
      method: 'DELETE',
    }),
};

export const webdavBackup = {
  /** 获取 WebDAV 配置及备份状态 */
  get: () => request<{ config: WebdavConfig | null; status: WebdavStatus }>('/api/backup/webdav'),

  /** 保存 WebDAV 配置 */
  save: (payload: { url: string; username: string; password?: string; path?: string; isEnabled?: boolean }) =>
    request<{ ok: boolean; config: WebdavConfig }>('/api/backup/webdav', {
      method: 'PUT',
      body: payload,
    }),

  /** 测试 WebDAV 连通性与写入权限 */
  test: (payload: { url?: string; username?: string; password?: string; path?: string }) =>
    request<{ ok: boolean; message: string }>('/api/backup/webdav/test', {
      method: 'POST',
      body: payload,
    }),

  /** 立即执行一次 WebDAV 备份 */
  run: () =>
    request<{ ok: boolean; filename: string; sizeBytes: number; uploadedAt: string }>('/api/backup/webdav/run', {
      method: 'POST',
    }),
};

// ---- 移动端与离线增量同步 -------------------------------------------------

export interface PullChangesResult {
  changes: Array<{
    version: number;
    entityType: 'expense' | 'category' | 'payment_method' | 'plan' | 'plan_todo';
    entityId: string;
    op: 'upsert' | 'delete';
    actorId: string | null;
    payload: Record<string, unknown>;
    deviceId: string | null;
    createdAt: string;
  }>;
  latestVersion: number;
  hasMore: boolean;
}

export interface SyncPushInput {
  expenses?: Array<{
    id?: string;
    amountCents: number;
    categoryId: string;
    paymentMethodId: string;
    spendDate: string;
    note?: string;
  }>;
  updatedExpenses?: Array<{
    id: string;
    amountCents?: number;
    categoryId?: string;
    paymentMethodId?: string;
    spendDate?: string;
    note?: string;
  }>;
  deletedExpenseIds?: string[];
  confirmedTodos?: Array<{
    id: string;
    spendDate?: string;
  }>;
  skippedTodoIds?: string[];
  ackedTodoIds?: string[];
  /** 撤销确认（confirmed → pending） */
  revertedTodoIds?: string[];
  /** 恢复跳过（skipped → pending） */
  restoredTodoIds?: string[];
  deviceId?: string;
}

export interface SyncPushResult {
  pushedExpensesCount: number;
  updatedExpensesCount: number;
  deletedExpensesCount: number;
  confirmedTodosCount: number;
  skippedTodosCount: number;
  ackedTodosCount: number;
  revertedTodosCount: number;
  restoredTodosCount: number;
  expenseIds: string[];
  /** 被服务端拒绝的新增支出条目在请求 expenses 数组中的下标（0 起） */
  failedExpenseIndexes: number[];
  latestVersion: number;
}

export const sync = {
  /** 增量拉取变更集 */
  pull: (since: number = 0, limit: number = 200) =>
    request<PullChangesResult>('/api/sync/pull', { query: { since, limit } }),

  /** 离线变更补偿推送 */
  push: (input: SyncPushInput) =>
    request<SyncPushResult>('/api/sync/push', { method: 'POST', body: input }),

  /** 获取服务端当前同步版本号 */
  status: () =>
    request<{ latestVersion: number }>('/api/sync/status'),
};

