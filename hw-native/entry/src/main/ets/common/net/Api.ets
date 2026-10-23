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

// ── 报表 ────────────────────────────────────────────────────────────────────
export interface CategoryBucket {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  cents: number;
  count: number;
  ratio: number;
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
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  members: MemberBucket[];
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
  id: string;
  planId: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  repaymentDate: string;
  willAutoPost: boolean;
  status: string;
}

export interface PlanTodoList {
  settled: number;
  todos: PlanTodoItem[];
}

// ── 同步 ────────────────────────────────────────────────────────────────────
export interface SyncStatusBody {
  latestVersion: number;
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
  static planTodos(today: string): Promise<PlanTodoList> {
    return Api.http().get<PlanTodoList>(`/api/plan-todos?status=pending&today=${today}`);
  }

  static syncStatus(): Promise<SyncStatusBody> {
    return Api.http().get<SyncStatusBody>('/api/sync/status');
  }
}
