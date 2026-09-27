/** 与服务端 `src/http/*.ts` 的响应形状一一对应。改服务端时记得同步改这里。 */

export type UserRole = 'admin' | 'member';

export interface User {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
}

export interface Category {
  id: string;
  parentId: string | null;
  name: string;
  /** 1 = 一级，2 = 二级。最多两级 */
  depth: number;
  icon: string;
  color: string;
  sortOrder: number;
  isEnabled: boolean;
  /** 该分类下的记录数，用于「停用前先转移」的提示 */
  expenseCount: number;
  children: Category[];
}

export type PaymentMethodType = 'cash' | 'credit';

export interface PaymentMethod {
  id: string;
  name: string;
  type: PaymentMethodType;
  /** 账单日 / 入账日。仅信用类有值 */
  billingDay: number | null;
  /** 还款日。仅信用类有值 */
  repaymentDay: number | null;
  isEnabled: boolean;
  sortOrder: number;
  expenseCount: number;
}

export interface Expense {
  id: string;
  ownerId: string;
  ownerName: string;
  amountCents: number;
  categoryId: string;
  categoryName: string;
  /** 图标名；空字符串表示该分类没设图标（前端会按分类名兜底猜一个） */
  categoryIcon: string;
  /** 分类色号（'1'–'8'）；空字符串表示没设过，由前端按分类名推导 */
  categoryColor: string;
  /** 二级分类才有：父分类的色号。子分类没设颜色时沿用父分类的 */
  parentCategoryColor: string | null;
  parentCategoryName: string | null;
  paymentMethodId: string;
  paymentMethodName: string;
  paymentMethodType: PaymentMethodType;
  /** 消费日 'YYYY-MM-DD' */
  spendDate: string;
  /** 入账日，由服务端按账单周期算出 */
  postingDate: string;
  /** 还款日 —— **报表的月份归属以此为准** */
  repaymentDate: string;
  note: string;
  source: 'manual' | 'plan';
  planId: string | null;
  planPeriodSeq: number | null;
  createdAt: string;
  updatedAt: string;
}

export interface ExpensePage {
  items: Expense[];
  nextCursor: string | null;
  hasMore: boolean;
}

export interface CategoryBucket {
  categoryId: string;
  name: string;
  /** 图标名；空字符串表示该分类没设图标（前端会按分类名兜底猜一个） */
  icon: string;
  color: string;
  cents: number;
  count: number;
  /** 0–1，总额为 0 时统一为 0 */
  ratio: number;
}

export interface PaymentBucket {
  paymentMethodId: string;
  name: string;
  type: PaymentMethodType;
  cents: number;
  count: number;
  /** 该支付方式本月的还款日（仅信用类有值） */
  repaymentDate: string | null;
}

export interface MemberBucket {
  ownerId: string;
  name: string;
  cents: number;
  count: number;
}

export interface MonthlyReport {
  month: string;
  totalCents: number;
  count: number;
  previous: { month: string; totalCents: number };
  /** 上期为 0 时 ratio 为 null —— 算不出有意义的百分比 */
  change: { deltaCents: number; ratio: number | null };
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  members: MemberBucket[];
}

// ---- 计划与待办 -----------------------------------------------------------

export type PlanSource = 'manual' | 'installment';
export type PlanState = 'active' | 'ended';
export type PlanTodoStatus = 'pending' | 'confirmed' | 'skipped' | 'cancelled';

/** 进度完全由待办派生，服务端不存冗余计数 */
export interface PlanProgress {
  /** 已确认的期数 */
  paidCount: number;
  paidCents: number;
  /** 未执行的期数 */
  pendingCount: number;
  pendingCents: number;
  /** 下一个待支付日；没有未执行待办时为 null */
  nextDueDate: string | null;
  /** 预计结清日 */
  expectedEndDate: string | null;
}

export interface Plan {
  id: string;
  ownerId: string;
  name: string;
  categoryId: string;
  paymentMethodId: string;
  /** 当前每期金额 */
  amountCents: number;
  /** 仅分期：消费原价（历史快照，改金额时不动） */
  totalAmountCents: number | null;
  purchaseDate: string | null;
  firstDueDate: string;
  remindDaysBefore: number;
  autoPost: boolean;
  source: PlanSource;
  state: PlanState;
  note: string;
  progress: PlanProgress;
  createdAt: string;
  updatedAt: string;
}

export interface PlanTodo {
  id: string;
  planId: string;
  planName: string;
  categoryId: string;
  paymentMethodId: string;
  periodSeq: number;
  amountCents: number;
  postingDate: string;
  repaymentDate: string;
  remindDate: string;
  status: PlanTodoStatus;
  /** 实际付款日（确认时可选填），不影响报表归属 */
  postedDate: string | null;
  confirmedBy: string | null;
  confirmedAt: string | null;
  expenseId: string | null;
}

export interface YearlyReport {
  year: string;
  totalCents: number;
  count: number;
  months: Array<{ month: string; totalCents: number; count: number }>;
  categories: CategoryBucket[];
  members: MemberBucket[];
}
