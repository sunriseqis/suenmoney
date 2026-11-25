/**
 * 接口定义（照 docs/api-native-contract.md 的 24 条路径，字段名不改）。
 *
 * 只放「类型 + 方法」，不放业务规则：金额怎么算、账期怎么归属都在服务端，
 * 客户端只负责搬运与展示。这样两端（iOS/鸿蒙）对着同一份契约写，不会各偏一半。
 */
import { ApiClient } from './ApiClient';

// ── 通用 ────────────────────────────────────────────────────────────────────
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
  /** 计划来源的记录属于哪个计划（本地表 plan_id 用；服务端一直有下发） */
  planId?: string | null;
}

export interface ExpensePreview {
  postingDate: string;
  repaymentDate: string;
}

/** `GET /api/update/check` 里 latest 字段（服务端缓存好的产物） */
export interface UpdateArtifact {
  fileName: string;
  versionName: string;
  versionCode: number;
  size: number;
  sha256: string | null;
}

/** 当前版本（ArkTS 禁止内联对象字面量作类型，必须单独声明） */
export interface UpdateVersionRef {
  versionName: string;
  versionCode: number;
}

/** `GET /api/update/check` 的返回 */
export interface UpdateCheckReply {
  available: boolean;
  current: UpdateVersionRef;
  latest: UpdateArtifact | null;
  downloadPath: string;
  downloadToken: string;
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
  /** 服务端不返回此字段（实测），保留可选以对齐契约与 iOS */
  ratio?: number | null;
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
  yearAgo?: YearAgoCompare;
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
  /**
   * 「我知道了」摘除时间。
   *
   * ⚠ 必须落地：提醒窗口的 SQL 里有 `ack_at IS NULL` 条件，
   *   不同步它的话，用户点过「我知道了」的期次会在每次快照后重新冒出来。
   */
  ackAt?: string | null;
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
  /**
   * 被服务端逐条拒绝的**新增**支出下标（对应请求 `expenses` 数组的位置）。
   *
   * 服务端对新增是容错的：坏数据（关联了已失效分类/支付方式）不会让整批 4xx，
   * 而是跳过并回传下标。客户端必须按它分流，否则那一笔服务端没入库、
   * 本地却以为同步成功把队列清了 —— 静默丢数据。
   */
  failedExpenseIndexes?: number[];
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

/** 冷启动全量快照（`GET /api/sync/snapshot`） */
export interface SyncSnapshotBody {
  version: number;
  /** 用户（id + 显示名）：流水行显示「记录人」用 */
  users: UserSummary[];
  categories: CategoryNode[];
  paymentMethods: PaymentMethodItem[];
  expenses: ExpenseItem[];
  plans: PlanItem[];
  planTodos: PlanTodoItem[];
}

export interface SyncPullBody {
  changes: SyncChange[];
  /**
   * 下一次 since 该传的值 = 本页最后一条变更的版本号。
   *
   * ⚠ 不要拿 `latestVersion` 当游标：它是全局最新版本，一页取不完时远大于本页
   * 最后一条，用它覆写游标会把「本页之后、最新之前」的变更全部跳掉 ——
   * 那批记录**永久丢失且不报错**（v2.1.1 修的就是这个）。
   * 可选：老服务端不返回该字段时，客户端退化为「本页最后一条的 version」。
   */
  nextSince?: number;
  latestVersion: number;
  hasMore: boolean;
}

// ── 设置类写操作的请求体 ────────────────────────────────────────────────────
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

  // ── 更新通道（对齐 suenmusic：服务端从 GitHub Releases 拉产物到本地，客户端从本地下载）──

  /**
   * 检查更新。**只读服务端本地缓存** —— 服务端不会为了这次请求去上游下载。
   * `force=true` 只让服务端在后台刷一次，然后立即返回当前结论。
   */
  static checkUpdate(platform: string, versionName: string, versionCode: number,
                     force: boolean): Promise<UpdateCheckReply> {
    const q = `?platform=${platform}&version_name=${encodeURIComponent(versionName)}`
      + `&version_code=${versionCode}${force ? '&force=1' : ''}`;
    return Api.http().get<UpdateCheckReply>(`/api/update/check${q}`);
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

  static syncPush(req: SyncPushRequest): Promise<SyncPushBody> {
    const o = Api.http().options('POST');
    o.readTimeoutMs = 20000;
    o.body = JSON.stringify(req);
    return Api.http().request<SyncPushBody>('/api/sync/push', o);
  }

  /** 冷启动全量快照：一次拿齐当前状态，之后只走增量 */
  static syncSnapshot(): Promise<SyncSnapshotBody> {
    return Api.http().get<SyncSnapshotBody>('/api/sync/snapshot');
  }

  static syncPull(since: number, limit: number): Promise<SyncPullBody> {
    return Api.http().get<SyncPullBody>(`/api/sync/pull?since=${since}&limit=${limit}`);
  }
}
