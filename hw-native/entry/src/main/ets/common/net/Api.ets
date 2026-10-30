/**
 * 接口定义（照 docs/api-native-contract.md 的 24 条路径，字段名不改）。
 *
 * 只放「类型 + 方法」，不放业务规则：金额怎么算、账期怎么归属都在服务端，
 * 客户端只负责搬运与展示。这样两端（iOS/鸿蒙）对着同一份契约写，不会各偏一半。
 */
import { ApiClient } from './ApiClient';

// ── 通用 ────────────────────────────────────────────────────────────────────
export interface HealthBody {
  ok: boolean;
  service: string;
  version: string;
}

export interface LoginRequest {
  username: string;
  password: string;
}

export interface LoginBody {
  token: string;
  expiresAt: string;
  user: UserSummary;
}

export interface UserSummary {
  id: string;
  username: string;
  displayName: string;
  role: string;
}

/** POST /api/auth/me/password 响应：被退出登录的设备数 */
export interface ChangePasswordBody {
  revoked: number;
  message: string;
}

/** POST /api/auth/me/password 请求体 */
export interface ChangePasswordRequest {
  currentPassword: string;
  newPassword: string;
}

// ── 字典 ────────────────────────────────────────────────────────────────────
export interface CategoryNode {
  id: string;
  parentId: string | null;
  name: string;
  depth: number;
  icon: string;
  color: string;
  sortOrder: number;
  isEnabled: boolean;
  expenseCount: number;
  children: CategoryNode[];
}

export interface CategoryList {
  categories: CategoryNode[];
}

export interface PaymentMethodItem {
  /** 本月笔数（R139 设置页「本月 N 笔」）；expenseCount 是全历史 */
  monthExpenseCount?: number;
  id: string;
  name: string;
  type: string; // 'credit' | 'cash'
  icon: string;
  billingDay: number | null;
  repaymentDay: number | null;
  isEnabled: boolean;
  sortOrder: number;
  expenseCount: number;
}

export interface PaymentMethodList {
  paymentMethods: PaymentMethodItem[];
}

export interface UserList {
  users: UserSummary[];
}

// ── 支出 ────────────────────────────────────────────────────────────────────
export interface ExpenseItem {
  id: string;
  ownerId: string;
  ownerName: string;
  amountCents: number;
  categoryId: string;
  categoryName: string;
  categoryIcon: string;
  categoryColor: string;
  parentCategoryColor: string | null;
  parentCategoryName: string | null;
  paymentMethodId: string;
  paymentMethodName: string;
  paymentMethodType: string;
  spendDate: string;
  postingDate: string;
  repaymentDate: string;
  note: string;
  source: string;
  /**
   * 计划来源的记录属于第几期（服务端一直有下发，之前接口漏声明导致被丢弃）。
   * 流水条目要显示「京东分期 · iPhone · 3期」，历史记录也能靠它补全。
   */
  planPeriodSeq?: number | null;
}

export interface ExpensePage {
  items: ExpenseItem[];
  nextCursor: string | null;
  hasMore: boolean;
}

export interface ExpensePreview {
  postingDate: string;
  repaymentDate: string;
}

export interface ExpenseCreateRequest {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
}

export interface ExpenseCreateBody {
  expense: ExpenseItem;
}

/** 编辑用：所有字段可选（服务端按传入字段更新） */
export interface ExpensePatchRequest {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
}

// ── 报表 ────────────────────────────────────────────────────────────────────
export interface CategoryBucket {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  cents: number;
  count: number;
  ratio: number;
  /** 上期同分类金额（无上期时为 0 / 缺省） */
  previousCents?: number;
  /** 环比（上期为 0 时服务端给 null） */
  changeRatio?: number | null;
  children?: CategoryBucket[];
}

export interface MonthChange {
  deltaCents: number;
  ratio: number | null;
}

export interface MonthPointRef {
  month: string;
  totalCents: number;
}

/** 去年同月（R83 对照四格用） */
/**
 * 同比（月报与年报**同构**：`{label, totalCents, change:{deltaCents, ratio}}`）
 *
 * ⚠ 原来声明成扁平的 `changeCents` / `changeRatio` 与服务端实际返回不符，
 * 运行期取到 undefined → 年档恒无环比胶囊、结论恒走「第一段可对比」。
 */
export interface YearAgoCompare {
  label: string;
  totalCents: number;
  change?: MonthChange;
}

export interface YearAgoRef {
  label: string;
  totalCents: number;
}

export interface LargestExpense {
  expenseId: string;
  categoryName: string;
  cents: number;
  repaymentDate: string;
}

export interface DailyPoint {
  date: string;
  day: number;
  cents: number;
  count: number;
}

export interface PaymentBucket {
  paymentMethodId: string;
  name: string;
  type: string;
  cents: number;
  count: number;
  repaymentDate: string | null;
}

export interface MemberBucket {
  ownerId: string;
  name: string;
  cents: number;
  count: number;
  ratio: number;
}

export interface RollingMonth {
  month: string;
  totalCents: number | null;
  count: number;
}

export interface MonthlyReport {
  month: string;
  totalCents: number;
  count: number;
  previous: MonthPointRef;
  change: MonthChange;
  /** 去年同月（服务端返回；缺省视为 0） */
  yearAgo?: YearAgoRef;
  largest: LargestExpense | null;
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  members: MemberBucket[];
  daily: DailyPoint[];
  rolling12Months: RollingMonth[];
}

export interface MonthlyReportBody {
  report: MonthlyReport;
}

export interface MonthPoint {
  month: string;
  totalCents: number;
  count: number;
}

export interface YearlyReport {
  year: string;
  totalCents: number;
  count: number;
  months: MonthPoint[];
  peakMonth: MonthPoint | null;
  /** 服务端年维度聚合（与月报同口径；R76 年档块集合用） */
  categories?: CategoryBucket[];
  paymentMethods?: PaymentBucket[];
  members?: MemberBucket[];
  yearAgo?: YearAgoCompare;
  largest?: LargestExpense | null;
  average3YearsCents?: number;
}

export interface YearlyReportBody {
  report: YearlyReport;
}

export interface YearPoint {
  year: string;
  totalCents: number;
  count: number;
}

export interface SummaryReport {
  totalCents: number;
  count: number;
  recordedDays: number;
  monthlyAverageCents: number;
  years: YearPoint[];
  /** 首笔日期（服务端提供则显示，缺省显示 —） */
  firstDate?: string;
  /** 单笔均值（服务端 /api/reports/summary 下发，与 Web SummaryReport 一致） */
  perExpenseAverageCents?: number;
  /** 全部分类聚合（概况页构成条用） */
  categories?: CategoryBucket[];
  members?: MemberBucket[];
}

export interface SummaryReportBody {
  report: SummaryReport;
}

// ── 计划与待办 ──────────────────────────────────────────────────────────────
export interface PlanProgress {
  paidCount: number;
  paidCents: number;
  pendingCount: number;
  pendingCents: number;
  nextDueDate: string | null;
  expectedEndDate: string | null;
}

export interface PlanItem {
  id: string;
  name: string;
  categoryId: string;
  /** 分类名与图标名（服务端随计划下发；缺省时按 id 查本地字典）*/
  categoryName?: string;
  categoryIcon?: string;
  paymentMethodId: string;
  amountCents: number;
  firstDueDate: string;
  autoPost: boolean;
  source: string;
  state: string;
  progress: PlanProgress;
}

export interface PlanList {
  plans: PlanItem[];
}

export interface PlanTodoItem {
  /** 该期入账后对应支出的所属月份（YYYY-MM）；未入账时为空 —— R126 跨月撤销警告用 */
  expenseMonth?: string;
  expenseId?: string | null;
  id: string;
  planId: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  repaymentDate: string;
  willAutoPost: boolean;
  status: string;
  /** 实际入账日（已入账时有值）；设置页「已处理」按它显示，而不是还款日 */
  postedDate?: string | null;
}

export interface UserCreateRequest {
  username: string;
  displayName: string;
  password: string;
  role: string;
}

export interface UserPatchRequest {
  displayName: string;
  role: string;
}

export interface PaymentMergeRequest {
  intoId: string;
}

export interface TodoConfirmRequest {
  spendDate: string;
}

export interface PlanTodoList {
  settled: number;
  todos: PlanTodoItem[];
}

// ── 同步 ────────────────────────────────────────────────────────────────────
export interface SyncCreateExpense {
  id: string;
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
}

export interface SyncUpdateExpense {
  id: string;
  amountCents?: number;
  categoryId?: string;
  paymentMethodId?: string;
  spendDate?: string;
  note?: string;
}

export interface SyncConfirmTodo {
  id: string;
  spendDate: string;
}

export interface SyncPushRequest {
  expenses: SyncCreateExpense[];
  updatedExpenses: SyncUpdateExpense[];
  deletedExpenseIds: string[];
  confirmedTodos: SyncConfirmTodo[];
  skippedTodoIds: string[];
  ackedTodoIds: string[];
  revertedTodoIds: string[];
  restoredTodoIds: string[];
}

export interface SyncPushBody {
  pushedExpensesCount: number;
  updatedExpensesCount: number;
  deletedExpensesCount: number;
  latestVersion: number;
}

export interface SyncChange {
  version: number;
  entityType: string;
  entityId: string;
  op: string;
  actorId: string;
  payload: object;
  deviceId: string;
  createdAt: string;
}

export interface SyncPullBody {
  changes: SyncChange[];
  latestVersion: number;
  hasMore: boolean;
}

export interface SyncStatusBody {
  latestVersion: number;
}

// ── 设置类写操作的请求体 ────────────────────────────────────────────────────
export interface CategoryCreateRequest {
  name: string;
  parentId: string;
  icon: string;
  color: string;
  sortOrder: number;
}

export interface CategoryPatchRequest {
  name: string;
  icon: string;
  color: string;
  parentId: string | null;
  isEnabled: boolean;
}

export interface PaymentCreateRequest {
  name: string;
  type: string;
  icon: string;
  billingDay: number;
  repaymentDay: number;
  sortOrder: number;
}

export interface PaymentPatchRequest {
  name: string;
  icon: string;
  billingDay: number;
  repaymentDay: number;
  sortOrder: number;
  isEnabled: boolean;
}

export interface PlanCreateRequest {
  name: string;
  categoryId: string;
  paymentMethodId: string;
  source: string;
  amountCents: number;
  totalAmountCents: number;
  periods: number;
  firstDueDate: string;
  remindDaysBefore: number;
  autoPost: boolean;
  note: string;
  /**
   * 消费日（`source === 'installment'` 时**必填**）。
   * 服务端要按它推算各期账单/还款日；之前接口漏了这个字段，
   * 记账页建分期必然报「分期必须提供消费日」。
   */
  purchaseDate?: string;
}

/** 24 条路径的客户端封装（H0 阶段先落只读 + 登录，写操作随 H3 接） */
export class Api {
  private static http(): ApiClient {
    return ApiClient.get();
  }

  static health(): Promise<HealthBody> {
    const o = Api.http().options('GET');
    o.withAuth = false;
    return Api.http().request<HealthBody>('/api/health', o);
  }

  static login(username: string, password: string): Promise<LoginBody> {
    const o = Api.http().options('POST');
    o.withAuth = false;
    const body: LoginRequest = { username: username, password: password };
    o.body = JSON.stringify(body);
    return Api.http().request<LoginBody>('/api/auth/login', o);
  }

  static me(): Promise<UserSummary> {
    return Api.http().get<UserSummary>('/api/auth/me');
  }

  /** 修改自己的口令：验证当前口令，成功后其他设备全部退出（web auth.changePassword） */
  static changePassword(currentPassword: string, newPassword: string): Promise<ChangePasswordBody> {
    const body: ChangePasswordRequest = {
      currentPassword: currentPassword,
      newPassword: newPassword
    };
    return Api.http().post<ChangePasswordBody>('/api/auth/me/password', body);
  }

  static categories(): Promise<CategoryList> {
    return Api.http().get<CategoryList>('/api/categories');
  }

  static paymentMethods(): Promise<PaymentMethodList> {
    return Api.http().get<PaymentMethodList>('/api/payment-methods');
  }

  static users(): Promise<UserList> {
    return Api.http().get<UserList>('/api/users');
  }

  /**
   * 流水列表。检索条件交给服务端（q / categoryId / paymentMethodId / ownerId），
   * **排序在本地做** —— 服务端不提供 sort 参数，而「按金额」只是在当前页内重排，
   * 与 Web 的实现一致（Web 也是在拿到的一页里排）。
   */
  static expenses(
    month: string,
    limit: number,
    cursor: string | null,
    q: string = '',
    categoryId: string = '',
    paymentMethodId: string = '',
    ownerId: string = ''
  ): Promise<ExpensePage> {
    let path = `/api/expenses?month=${month}&limit=${limit}`;
    if (cursor !== null && cursor !== '') {
      path += `&cursor=${encodeURIComponent(cursor)}`;
    }
    if (q !== '') {
      path += `&q=${encodeURIComponent(q)}`;
    }
    if (categoryId !== '') {
      path += `&categoryId=${encodeURIComponent(categoryId)}`;
    }
    if (paymentMethodId !== '') {
      path += `&paymentMethodId=${encodeURIComponent(paymentMethodId)}`;
    }
    if (ownerId !== '') {
      path += `&ownerId=${encodeURIComponent(ownerId)}`;
    }
    return Api.http().get<ExpensePage>(path);
  }

  /** 账期预览：这笔会记在哪个月（服务端算，不在客户端重实现账单周期） */
  static previewExpense(spendDate: string, paymentMethodId: string): Promise<ExpensePreview> {
    const o = Api.http().options('POST');
    const body: ExpenseCreateRequest = {
      amountCents: 0,
      categoryId: '',
      paymentMethodId: paymentMethodId,
      spendDate: spendDate,
      note: ''
    };
    // 预览只需要日期与支付方式；其余字段服务端忽略
    o.body = JSON.stringify(body);
    return Api.http().request<ExpensePreview>('/api/expenses/preview', o);
  }

  static createExpense(req: ExpenseCreateRequest): Promise<ExpenseCreateBody> {
    const o = Api.http().options('POST');
    o.body = JSON.stringify(req);
    return Api.http().request<ExpenseCreateBody>('/api/expenses', o);
  }

  static updateExpense(id: string, req: ExpensePatchRequest): Promise<ExpenseCreateBody> {
    const o = Api.http().options('PATCH');
    o.body = JSON.stringify(req);
    return Api.http().request<ExpenseCreateBody>(`/api/expenses/${id}`, o);
  }

  static deleteExpense(id: string): Promise<void> {
    const o = Api.http().options('DELETE');
    return Api.http().request<void>(`/api/expenses/${id}`, o);
  }

  static monthlyReport(month: string): Promise<MonthlyReportBody> {
    return Api.http().get<MonthlyReportBody>(`/api/reports/monthly?month=${month}`);
  }

  static yearlyReport(year: string): Promise<YearlyReportBody> {
    return Api.http().get<YearlyReportBody>(`/api/reports/yearly?year=${year}`);
  }

  static summaryReport(): Promise<SummaryReportBody> {
    return Api.http().get<SummaryReportBody>('/api/reports/summary');
  }

  static plans(): Promise<PlanList> {
    return Api.http().get<PlanList>('/api/plans');
  }

  /** 传 today 才会触发服务端「到期自动入账」结算 */
  /**
   * 提醒列表（流水页顶卡）：**只取该提醒的期次**，不是所有待办。
   *
   * 服务端 `reminderToday` 口径 = 进入提醒窗口（还款日 − remind_days_before，默认 3 天）
   * 的 pending，加上「被忽略但已逾期的非自动入账期次」（逾期重现）。
   * 计划详情/设置页要看全部待办，走 planTodosAll。
   */
  static planTodos(today: string): Promise<PlanTodoList> {
    return Api.http().get<PlanTodoList>(`/api/plan-todos?reminderToday=${today}&today=${today}`);
  }

  /** 全部 pending 待办（设置页「待处理期次」用，不做提醒窗口过滤） */
  static planTodosAll(today: string): Promise<PlanTodoList> {
    return Api.http().get<PlanTodoList>(`/api/plan-todos?status=pending&today=${today}`);
  }

  /** 入账（手动确认）：可带 spendDate，但报表月份归属仍按还款日，不受影响 */
  static confirmTodo(id: string, spendDate: string = ''): Promise<object> {
    const o = Api.http().options('POST');
    if (spendDate === '') {
      o.body = '{}';
    } else {
      const body: TodoConfirmRequest = { spendDate: spendDate };
      o.body = JSON.stringify(body);
    }
    return Api.http().request<object>(`/api/plan-todos/${id}/confirm`, o);
  }

  /** 确认（自动入账型待办） */
  static ackTodo(id: string): Promise<object> {
    const o = Api.http().options('POST');
    o.body = '{}';
    return Api.http().request<object>(`/api/plan-todos/${id}/ack`, o);
  }

  /** 忽略本期（不可逆：跳过的期次不会回到待办） */
  static skipTodo(id: string): Promise<object> {
    const o = Api.http().options('POST');
    o.body = '{}';
    return Api.http().request<object>(`/api/plan-todos/${id}/skip`, o);
  }

  // ── 分类 ──
  static createCategory(req: CategoryCreateRequest): Promise<object> {
    const o = Api.http().options('POST');
    o.body = JSON.stringify(req);
    return Api.http().request<object>('/api/categories', o);
  }

  static patchCategory(id: string, req: CategoryPatchRequest): Promise<object> {
    const o = Api.http().options('PATCH');
    o.body = JSON.stringify(req);
    return Api.http().request<object>(`/api/categories/${id}`, o);
  }

  static deleteCategory(id: string): Promise<void> {
    const o = Api.http().options('DELETE');
    return Api.http().request<void>(`/api/categories/${id}`, o);
  }

  // ── 支付方式 ──
  static createPayment(req: PaymentCreateRequest): Promise<object> {
    const o = Api.http().options('POST');
    o.body = JSON.stringify(req);
    return Api.http().request<object>('/api/payment-methods', o);
  }

  static patchPayment(id: string, req: PaymentPatchRequest): Promise<object> {
    const o = Api.http().options('PATCH');
    o.body = JSON.stringify(req);
    return Api.http().request<object>(`/api/payment-methods/${id}`, o);
  }

  static mergePayment(id: string, intoId: string): Promise<object> {
    const o = Api.http().options('POST');
    const body: PaymentMergeRequest = { intoId: intoId };
    o.body = JSON.stringify(body);
    return Api.http().request<object>(`/api/payment-methods/${id}/merge`, o);
  }

  static deletePayment(id: string): Promise<void> {
    const o = Api.http().options('DELETE');
    return Api.http().request<void>(`/api/payment-methods/${id}`, o);
  }

  // ── 计划 ──
  static createPlan(req: PlanCreateRequest): Promise<object> {
    const o = Api.http().options('POST');
    o.body = JSON.stringify(req);
    return Api.http().request<object>('/api/plans', o);
  }

  static endPlan(id: string): Promise<object> {
    const o = Api.http().options('POST');
    o.body = '{}';
    return Api.http().request<object>(`/api/plans/${id}/end`, o);
  }

  static deletePlan(id: string): Promise<void> {
    const o = Api.http().options('DELETE');
    return Api.http().request<void>(`/api/plans/${id}`, o);
  }

  static createUser(req: UserCreateRequest): Promise<object> {
    const o = Api.http().options('POST');
    o.body = JSON.stringify(req);
    return Api.http().request<object>('/api/users', o);
  }

  static patchUser(id: string, req: UserPatchRequest): Promise<object> {
    const o = Api.http().options('PATCH');
    o.body = JSON.stringify(req);
    return Api.http().request<object>(`/api/users/${id}`, o);
  }

  static syncPush(req: SyncPushRequest): Promise<SyncPushBody> {
    const o = Api.http().options('POST');
    o.readTimeoutMs = 20000;
    o.body = JSON.stringify(req);
    return Api.http().request<SyncPushBody>('/api/sync/push', o);
  }

  static syncPull(since: number, limit: number): Promise<SyncPullBody> {
    return Api.http().get<SyncPullBody>(`/api/sync/pull?since=${since}&limit=${limit}`);
  }

  /** 撤销入账（该期次回到待办，软删对应支出） */
  static revertTodo(id: string): Promise<object> {
    const o = Api.http().options('POST');
    o.body = '{}';
    return Api.http().request<object>(`/api/plan-todos/${id}/revert`, o);
  }

  /** 恢复被跳过的期次（恢复后不再当场自动入账） */
  static restoreTodo(id: string): Promise<object> {
    const o = Api.http().options('POST');
    o.body = '{}';
    return Api.http().request<object>(`/api/plan-todos/${id}/restore`, o);
  }

  /** 已处理期次（confirmed / skipped） */
  static doneTodos(status: string): Promise<PlanTodoList> {
    return Api.http().get<PlanTodoList>(`/api/plan-todos?status=${status}`);
  }

  static syncStatus(): Promise<SyncStatusBody> {
    return Api.http().get<SyncStatusBody>('/api/sync/status');
  }
}
