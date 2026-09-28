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
  /** 图标名（见 utils/payment-icons.ts 的登记表）；空字符串表示没设过 */
  icon: string;
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

export interface SubCategoryBucket {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  cents: number;
  count: number;
  ratio: number;
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
  /** 上一期同口径金额（分）。月报比上月、年报比去年；没有则为 0 */
  previousCents: number;
  /** 环比。上期为 0 时为 null —— 与 report.change.ratio 同一套口径，不要各写一套 */
  changeRatio: number | null;
  /** 二级子分类明细，按金额倒序 */
  children?: SubCategoryBucket[];
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

/** 单笔最高。整月没有记录时 largest 为 null */
export interface LargestExpense {
  expenseId: string;
  /** 归并后的一级分类名（与报表其余部分同粒度） */
  categoryName: string;
  cents: number;
  repaymentDate: string;
}

/** 同期对比。ratio 的 null 规则与环比一致 */
export interface ComparedPeriod {
  label: string;
  totalCents: number;
  change: { deltaCents: number; ratio: number | null };
}

export interface DailyRhythmPoint {
  date: string;
  day: number;
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
  /** 同比（去年同月） */
  yearAgo: ComparedPeriod;
  largest: LargestExpense | null;
  categories: CategoryBucket[];
  paymentMethods: PaymentBucket[];
  members: MemberBucket[];
  daily?: DailyRhythmPoint[];
  rolling12Months?: Array<{ month: string; totalCents: number | null; count: number }>;
  average12MonthsCents?: number;
  rolling3MonthsDailyAverageCents?: number;
  nextMonthRepayments?: PaymentBucket[];
  nextMonthDueTotalCents?: number;
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
  /**
   * 该期是否已被摘出「到期自动入账」。
   *
   * 撤销确认、恢复跳过都会把它置为 true —— 否则那一期回到 `pending` 后
   * 会在下次打开首页时被自动入账重新捡走（表现为「撤销按了没用」）。
   * 置上之后就只会等用户手动确认。
   */
  holdAutoPost: boolean;
  /**
   * 这一期现在**还会不会**自动入账。
   *
   * 判据是 `plans.auto_post = 1 AND plan_todos.hold_auto_post = 0` 的**合取** ——
   * 由服务端算好下发（见 `server/src/db/repo/plans.ts` 的 `willAutoPost`）。
   *
   * 它决定界面给哪一种动作：
   *   true  → 只给「确认」（＝我知道了，不改任何业务状态）
   *   false → 给「入账」「忽略」
   * 前端不要自己用 `autoPost && !holdAutoPost` 再拼一遍：这个合取条件一旦
   * 在两处各写一次，迟早只改一处 —— 而它的错法是静默的（账目少一笔）。
   */
  willAutoPost: boolean;
  /** 已点过「确认」的时间；非 null 表示这条提醒已被知悉、不再出现在「该处理了」里 */
  ackAt: string | null;
}

export interface YearlyReport {
  year: string;
  totalCents: number;
  count: number;
  months: Array<{ month: string; totalCents: number; count: number }>;
  /** 同比（去年整年） */
  yearAgo: ComparedPeriod;
  largest?: LargestExpense | null;
  categories: CategoryBucket[];
  members: MemberBucket[];
  average3YearsCents?: number;
  peakMonth?: { month: string; totalCents: number } | null;
}

export interface SummaryReport {
  totalCents: number;
  count: number;
  firstRepaymentDate: string | null;
  lastRepaymentDate: string | null;
  recordedDays: number;
  monthlyAverageCents: number;
  dailyAverageCents: number;
  perExpenseAverageCents: number;
  peakMonth: { month: string; totalCents: number } | null;
  years: Array<{ year: string; totalCents: number; count: number }>;
  categories: CategoryBucket[];
  members: MemberBucket[];
}

// ---- 数据（导出 / 导入 / 备份 / 危险区）------------------------------------

/**
 * 导出范围。
 *
 * 期间一律走**还款日**前缀匹配，与报表同源 —— 这点很重要，
 * 否则「9 月导出的合计」与「9 月报表的合计」会不相等，看起来像丢了数据。
 */
export type ExportScopeKind = 'all' | 'year' | 'month';

export interface PackageCounts {
  members: number;
  categories: number;
  paymentMethods: number;
  plans: number;
  planTodos: number;
  expenses: number;
  /** 其中「因为计划被整条带出」而附带进来的支出数（仅期间范围时可能 > 0） */
  contextExpenses: number;
}

/** 按表统计的写入结果。`skipped` 是导入特有的：那条记录本来就在，于是没动它。 */
export interface TableReport {
  created: number;
  skipped: number;
  overwritten: number;
}

export interface MergeReport {
  /** `merge` = 只补缺（导入）；`restore` = 文件覆盖本地（恢复） */
  mode: 'merge' | 'restore';
  byTable: Record<string, TableReport>;
  created: number;
  skipped: number;
  overwritten: number;
  /** 恢复 / 清空之前自动存的那份全量快照 */
  snapshotPath: string | null;
}

export interface TransferResult {
  report: MergeReport;
  counts: PackageCounts;
  scope: { kind: ExportScopeKind; period: string };
  generatedAt: string;
}

export interface LedgerCounts {
  expenses: number;
  plans: number;
  planTodos: number;
}

export interface LedgerWipeReport {
  removed: LedgerCounts;
  total: number;
  snapshotPath: string | null;
}

export interface DemoResetReport extends LedgerWipeReport {
  seeded: LedgerCounts;
  seederActorId: string;
}

/**
 * 「数据」面板一进来看到的那一片。
 *
 * `resetDemoBlockers` 是**服务端算好的**「现在能不能重置」——
 * 空数组表示可以，非空时里面的每条都是可以直接念给用户听的原话。
 * 不要在前端再判一遍：那个判据（活着的账目里有没有不在演示清单里的 id）
 * 只有服务端知道，前端拼不出来。
 */
export interface DataOverview {
  ledger: LedgerCounts;
  categories: number;
  paymentMethods: number;
  members: number;
  firstRepaymentDate: string | null;
  demoSeededAt: string | null;
  resetDemoBlockers: string[];
  preRestoreDir: string;
}
