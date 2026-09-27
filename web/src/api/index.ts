/**
 * 接口封装。
 *
 * 刻意放在一个文件里而不是按资源拆成 5 个：总共 20 来个方法，拆开之后
 * 「某个接口在哪个文件」就成了需要翻找的问题，收益不抵成本。
 * 真正需要拆的是类型（`types.ts`），因为它的体积会随功能持续增长。
 */
import { request } from './client';
import type {
  Category,
  Expense,
  ExpensePage,
  MonthlyReport,
  PaymentMethod,
  PaymentMethodType,
  Plan,
  PlanSource,
  PlanTodo,
  PlanTodoStatus,
  User,
  UserRole,
  YearlyReport,
} from './types';

export * from './client';
export type * from './types';

// ---- 认证 -----------------------------------------------------------------

export const auth = {
  /** 首次初始化。仅在系统里一个用户都没有时可用，之后永久 403 */
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
    input: { name?: string; icon?: string; color?: string; sortOrder?: number; isEnabled?: boolean },
  ) => request<{ category: Category }>(`/api/categories/${id}`, { method: 'PATCH', body: input }),
};

// ---- 支付方式 -------------------------------------------------------------

export const paymentMethods = {
  list: () => request<{ paymentMethods: PaymentMethod[] }>('/api/payment-methods'),

  create: (input: {
    name: string;
    type: PaymentMethodType;
    billingDay?: number;
    repaymentDay?: number;
    sortOrder?: number;
  }) => request<{ paymentMethod: PaymentMethod }>('/api/payment-methods', { method: 'POST', body: input }),

  update: (
    id: string,
    input: {
      name?: string;
      billingDay?: number;
      repaymentDay?: number;
      sortOrder?: number;
      isEnabled?: boolean;
    },
  ) => request<{ paymentMethod: PaymentMethod }>(`/api/payment-methods/${id}`, { method: 'PATCH', body: input }),
};

// ---- 支出 -----------------------------------------------------------------

export interface ExpenseQuery {
  month?: string;
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
};
