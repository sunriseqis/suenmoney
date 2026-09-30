/**
 * 计划（房贷 / 免息分期）与其待办。
 *
 * 计划与待办放在同一个文件里，不拆成两个 repo：它们是**一个聚合**——
 * 待办永远依附于某个计划，任何对待办的写入都要读计划（分类、支付方式、
 * 提醒天数）。拆开只会得到一个双向依赖的循环引用。
 *
 * 核心规则（详见 docs/decisions.md 第二节）：
 *   · 房贷与分期是同一个模型：期数有限 = 分期，可续 = 房贷
 *   · 创建时**一次性生成全部期待办**，每期有独立状态
 *   · 改计划 = 删掉未执行的待办 → 从「最后一期已确认期 + 1」重新生成
 *   · 待办确认的幂等键 = `(plan_id, period_seq)` 唯一约束 + 条件更新
 */
import type { DatabaseSync } from 'node:sqlite';

import {
  addMonthsToDate,
  computeRemindDate,
  parseDate,
  resolvePostingDate,
  type PaymentCycle,
} from '../../domain/billing-cycle.ts';
import { splitInstallment } from '../../domain/installment.ts';
import { badRequest, conflict, forbidden, notFound } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange } from '../sync.ts';
import { requireUsableCategory } from './categories.ts';
import { insertPlanExpense, findExpenseRow, toSyncExpense, type ExpenseRow } from './expenses.ts';
import { requireUsablePaymentMethod, toPaymentCycle } from './payment-methods.ts';

export type PlanSource = 'manual' | 'installment';
export type PlanState = 'active' | 'ended';
export type PlanTodoStatus = 'pending' | 'confirmed' | 'skipped' | 'cancelled';

export interface PlanRow {
  id: string;
  owner_id: string;
  name: string;
  category_id: string;
  payment_method_id: string;
  amount_cents: number;
  total_amount_cents: number | null;
  purchase_date: string | null;
  first_due_date: string;
  remind_days_before: number;
  auto_post: number;
  source: PlanSource;
  state: PlanState;
  note: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
}

export interface PlanTodoRow {
  id: string;
  plan_id: string;
  period_seq: number;
  amount_cents: number;
  posting_date: string;
  repayment_date: string;
  remind_date: string;
  status: PlanTodoStatus;
  posted_date: string | null;
  confirmed_by: string | null;
  confirmed_at: string | null;
  expense_id: string | null;
  /**
   * 「本期不再自动入账」。见 `002_plan_todo_hold_auto_post.sql`。
   * 1 表示这一期被用户显式摘出自动入账，只能手动确认。
   */
  hold_auto_post: number;
  /**
   * 「我知道了」的时间戳。见 `003_plan_todo_ack.sql`。
   * 非空 = 用户已确认过这条提醒；**不改 `status`**，只把这条从「该处理了」里摘掉。
   */
  ack_at: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
}

/** 进度：已付 / 剩余。全部由待办派生，计划表不存冗余计数。 */
export interface PlanProgress {
  paidCount: number;
  paidCents: number;
  pendingCount: number;
  pendingCents: number;
  /** 下一个待支付日；没有未执行待办时为 null */
  nextDueDate: string | null;
  /** 预计结清日 */
  expectedEndDate: string | null;
}

export interface PlanApi {
  id: string;
  ownerId: string;
  name: string;
  categoryId: string;
  paymentMethodId: string;
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

export interface PlanTodoApi {
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
  postedDate: string | null;
  confirmedBy: string | null;
  confirmedAt: string | null;
  expenseId: string | null;
  /** 是否已从自动入账中摘出（撤销 / 恢复跳过后为 true，见 migration 002） */
  holdAutoPost: boolean;
  /**
   * 这一期现在**还会不会**自动入账。
   *
   * 判据不是「计划有没有开自动入账」，而是两者的合取 ——
   * `plans.auto_post = 1 AND plan_todos.hold_auto_post = 0`。
   * 只看计划那一级会判错，而且错得很隐蔽：界面会给一个「确认」按钮，
   * 用户点了以为没事，那笔账却永远不入，且不报错。
   *
   * 由服务端算好下发，不在前端拼 —— 否则这个合取条件会在每处界面各写一遍。
   */
  willAutoPost: boolean;
  /** 已确认过这条提醒的时间；非 null 表示用户已经「知道了」（见 migration 003） */
  ackAt: string | null;
}

const PLAN_COLUMNS = `id, owner_id, name, category_id, payment_method_id, amount_cents,
                      total_amount_cents, purchase_date, first_due_date, remind_days_before,
                      auto_post, source, state, note, created_at, updated_at, deleted_at, rev, device_id`;

const TODO_COLUMNS = `id, plan_id, period_seq, amount_cents, posting_date, repayment_date,
                      remind_date, status, posted_date, confirmed_by, confirmed_at, expense_id,
                      hold_auto_post, ack_at, created_at, updated_at, deleted_at, rev, device_id`;

const nowIso = (): string => new Date().toISOString();

export function toSyncPlan(row: PlanRow): Record<string, unknown> {
  return {
    id: row.id,
    owner_id: row.owner_id,
    name: row.name,
    category_id: row.category_id,
    payment_method_id: row.payment_method_id,
    amount_cents: row.amount_cents,
    total_amount_cents: row.total_amount_cents,
    purchase_date: row.purchase_date,
    first_due_date: row.first_due_date,
    remind_days_before: row.remind_days_before,
    auto_post: row.auto_post === 1,
    source: row.source,
    state: row.state,
    note: row.note,
    updated_at: row.updated_at,
    deleted_at: row.deleted_at,
    rev: row.rev,
  };
}

export function toSyncTodo(row: PlanTodoRow): Record<string, unknown> {
  return {
    id: row.id,
    plan_id: row.plan_id,
    period_seq: row.period_seq,
    amount_cents: row.amount_cents,
    posting_date: row.posting_date,
    repayment_date: row.repayment_date,
    remind_date: row.remind_date,
    status: row.status,
    posted_date: row.posted_date,
    confirmed_by: row.confirmed_by,
    confirmed_at: row.confirmed_at,
    expense_id: row.expense_id,
    hold_auto_post: row.hold_auto_post,
    ack_at: row.ack_at,
    updated_at: row.updated_at,
    deleted_at: row.deleted_at,
    rev: row.rev,
  };
}

function toTodoApi(row: PlanTodoRow, plan: PlanRow): PlanTodoApi {
  return {
    id: row.id,
    planId: row.plan_id,
    planName: plan.name,
    categoryId: plan.category_id,
    paymentMethodId: plan.payment_method_id,
    periodSeq: row.period_seq,
    amountCents: row.amount_cents,
    postingDate: row.posting_date,
    repaymentDate: row.repayment_date,
    remindDate: row.remind_date,
    status: row.status,
    postedDate: row.posted_date,
    confirmedBy: row.confirmed_by,
    confirmedAt: row.confirmed_at,
    expenseId: row.expense_id,
    holdAutoPost: row.hold_auto_post === 1,
    willAutoPost: plan.auto_post === 1 && row.hold_auto_post === 0,
    ackAt: row.ack_at,
  };
}

// ---------------------------------------------------------------------------
// 读取
// ---------------------------------------------------------------------------

export function findPlanRow(db: DatabaseSync, id: string): PlanRow | null {
  const row = db.prepare(`SELECT ${PLAN_COLUMNS} FROM plans WHERE id = ? AND deleted_at IS NULL`).get(id);
  return (row as unknown as PlanRow | undefined) ?? null;
}

export function requireOwnPlan(db: DatabaseSync, id: string, actorId: string): PlanRow {
  const row = findPlanRow(db, id);
  if (row === null) throw notFound(`计划不存在：${id}`);
  // 与支出同一条规则：只能改自己创建的。这也是离线冲突不会发生的前提。
  if (row.owner_id !== actorId) throw forbidden('只能修改自己创建的计划');
  return row;
}

/** 进度完全由待办派生 —— 不存冗余计数，就不会出现「计数与明细对不上」。 */
export function planProgressOf(db: DatabaseSync, planId: string): PlanProgress {
  const row = db
    .prepare(
      `SELECT
         SUM(CASE WHEN status = 'confirmed' THEN 1 ELSE 0 END) AS paid_count,
         SUM(CASE WHEN status = 'confirmed' THEN amount_cents ELSE 0 END) AS paid_cents,
         SUM(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending_count,
         SUM(CASE WHEN status = 'pending'   THEN amount_cents ELSE 0 END) AS pending_cents,
         MIN(CASE WHEN status = 'pending'   THEN repayment_date END) AS next_due,
         MAX(CASE WHEN status = 'pending'   THEN repayment_date END) AS end_date
       FROM plan_todos WHERE plan_id = ? AND deleted_at IS NULL`,
    )
    .get(planId);

  return {
    paidCount: row === undefined ? 0 : Number(row['paid_count'] ?? 0),
    paidCents: row === undefined ? 0 : Number(row['paid_cents'] ?? 0),
    pendingCount: row === undefined ? 0 : Number(row['pending_count'] ?? 0),
    pendingCents: row === undefined ? 0 : Number(row['pending_cents'] ?? 0),
    nextDueDate: row === undefined || row['next_due'] === null ? null : String(row['next_due']),
    expectedEndDate: row === undefined || row['end_date'] === null ? null : String(row['end_date']),
  };
}

function toPlanApi(db: DatabaseSync, row: PlanRow): PlanApi {
  return {
    id: row.id,
    ownerId: row.owner_id,
    name: row.name,
    categoryId: row.category_id,
    paymentMethodId: row.payment_method_id,
    amountCents: row.amount_cents,
    totalAmountCents: row.total_amount_cents,
    purchaseDate: row.purchase_date,
    firstDueDate: row.first_due_date,
    remindDaysBefore: row.remind_days_before,
    autoPost: row.auto_post === 1,
    source: row.source,
    state: row.state,
    note: row.note,
    progress: planProgressOf(db, row.id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function listPlans(db: DatabaseSync): PlanApi[] {
  const rows = db
    .prepare(
      `SELECT ${PLAN_COLUMNS} FROM plans WHERE deleted_at IS NULL
        ORDER BY CASE state WHEN 'active' THEN 0 ELSE 1 END, created_at, rowid`,
    )
    .all() as unknown as PlanRow[];

  return rows.map((row) => toPlanApi(db, row));
}

export function findPlan(db: DatabaseSync, id: string): PlanApi | null {
  const row = findPlanRow(db, id);
  return row === null ? null : toPlanApi(db, row);
}

export interface TodoFilter {
  planId?: string | undefined;
  status?: PlanTodoStatus | undefined;
  /** 只返回提醒日已到的（即「该处理了」，含逾期） */
  remindBefore?: string | undefined;
  /** 只看某个还款日区间 */
  from?: string | undefined;
  to?: string | undefined;
  /**
   * 排除已被「我知道了」摘掉的期次。
   *
   * **默认 false**（照样返回）：「该处理了」列表要传 true，而计划详情不能传 ——
   * 详情里那一期仍然是 `pending`、也仍然要显示，用户得能看见自己确认过什么。
   */
  hideAcked?: boolean | undefined;
  limit?: number | undefined;
  orderBy?: 'repayment_date' | 'period_seq' | undefined;
}

export function listTodos(db: DatabaseSync, filter: TodoFilter = {}): PlanTodoApi[] {
  const where: string[] = ['deleted_at IS NULL'];
  const params: Array<string | number> = [];

  if (filter.planId !== undefined) {
    where.push('plan_id = ?');
    params.push(filter.planId);
  }
  if (filter.status !== undefined) {
    where.push('status = ?');
    params.push(filter.status);
  }
  if (filter.remindBefore !== undefined) {
    where.push('remind_date <= ?');
    params.push(filter.remindBefore);
  }
  if (filter.from !== undefined) {
    where.push('repayment_date >= ?');
    params.push(filter.from);
  }
  if (filter.to !== undefined) {
    where.push('repayment_date <= ?');
    params.push(filter.to);
  }
  if (filter.hideAcked === true) {
    where.push('ack_at IS NULL');
  }

  const limit = Math.min(Math.max(filter.limit ?? 200, 1), 500);
  const orderClause =
    filter.orderBy === 'period_seq' || filter.planId !== undefined
      ? 'period_seq ASC'
      : 'repayment_date, period_seq';

  const todos = db
    .prepare(
      `SELECT ${TODO_COLUMNS} FROM plan_todos
        WHERE ${where.join(' AND ')}
        ORDER BY ${orderClause}
        LIMIT ?`,
    )
    .all(...params, limit) as unknown as PlanTodoRow[];

  if (todos.length === 0) return [];

  // 涉及的计划一次查完，避免每条待办各查一次（N+1）
  const planIds = [...new Set(todos.map((todo) => todo.plan_id))];
  const placeholders = planIds.map(() => '?').join(', ');
  const plans = new Map<string, PlanRow>();

  for (const row of db
    .prepare(`SELECT ${PLAN_COLUMNS} FROM plans WHERE deleted_at IS NULL AND id IN (${placeholders})`)
    .all(...planIds) as unknown as PlanRow[]) {
    plans.set(row.id, row);
  }

  // 计划已被删除的待办直接不返回 —— 它们已经无从展示了
  return todos
    .filter((todo) => plans.has(todo.plan_id))
    .map((todo) => toTodoApi(todo, plans.get(todo.plan_id)!));
}

export function findTodoRow(db: DatabaseSync, id: string): PlanTodoRow | null {
  const row = db
    .prepare(`SELECT ${TODO_COLUMNS} FROM plan_todos WHERE id = ? AND deleted_at IS NULL`)
    .get(id);
  return (row as unknown as PlanTodoRow | undefined) ?? null;
}

// ---------------------------------------------------------------------------
// 生成待办
// ---------------------------------------------------------------------------

/**
 * 为一组期序生成待办。
 *
 * 还款日**从首期日递推**（`first_due_date + (period_seq - 1) 个月`），
 * 而不是「上一期 + 1 个月」逐级累加 —— 后者会把「1/31 → 2/28」的月末钳制
 * 一路传染下去，让之后每一期都变成 28 号。
 */
function generateTodos(
  db: DatabaseSync,
  plan: PlanRow,
  cycle: PaymentCycle,
  fromSeq: number,
  amounts: readonly number[],
  actorId: string,
): number {
  const insert = db.prepare(
    `INSERT INTO plan_todos (id, plan_id, period_seq, amount_cents, posting_date, repayment_date,
                             remind_date, status, posted_date, confirmed_by, confirmed_at, expense_id,
                             created_at, updated_at, deleted_at, rev, device_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', NULL, NULL, NULL, NULL, ?, ?, NULL, 1, ?)`,
  );

  const timestamp = nowIso();

  for (const [index, amount] of amounts.entries()) {
    const periodSeq = fromSeq + index;
    const repaymentDate = addMonthsToDate(plan.first_due_date, periodSeq - 1);

    const row: PlanTodoRow = {
      id: ulid(),
      plan_id: plan.id,
      period_seq: periodSeq,
      amount_cents: amount,
      posting_date: resolvePostingDate(repaymentDate, cycle),
      repayment_date: repaymentDate,
      remind_date: computeRemindDate(repaymentDate, plan.remind_days_before),
      status: 'pending',
      posted_date: null,
      confirmed_by: null,
      confirmed_at: null,
      expense_id: null,
      // 新建的期待办一律参与自动入账；摘出是用户显式动作
      hold_auto_post: 0,
      // 新建的期待办一律「未确认」—— 它还没被摆到用户面前过
      ack_at: null,
      created_at: timestamp,
      updated_at: timestamp,
      deleted_at: null,
      rev: 1,
      device_id: plan.device_id,
    };

    insert.run(
      row.id,
      row.plan_id,
      row.period_seq,
      row.amount_cents,
      row.posting_date,
      row.repayment_date,
      row.remind_date,
      row.created_at,
      row.updated_at,
      row.device_id,
    );

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: row.id,
      op: 'upsert',
      actorId,
      payload: toSyncTodo(row),
      deviceId: row.device_id,
    });
  }

  return amounts.length;
}

/**
 * 删除该计划全部未执行的待办（仅 pending），并发出 delete 变更。
 *
 * 注意不能顺带删 skipped：跳过是用户显式执行过的历史期次（宽限期等场景），
 * lastExecutedSeq 依赖它推算下一期期序；调息重算若把它删了，
 * 期序会回缩、已跳过月份的待办会被重新生成，时间轴倒流。
 * 需要连同 skipped 一起清掉的调用方（如 deletePlan）会另行软删除。
 */
function deletePendingTodos(db: DatabaseSync, planId: string, actorId: string): number {
  const rows = db
    .prepare(
      `SELECT ${TODO_COLUMNS} FROM plan_todos
        WHERE plan_id = ? AND deleted_at IS NULL AND status = 'pending'`,
    )
    .all(planId) as unknown as PlanTodoRow[];

  if (rows.length === 0) return 0;

  const timestamp = nowIso();
  const remove = db.prepare('DELETE FROM plan_todos WHERE id = ?');

  for (const row of rows) {
    remove.run(row.id);
    recordChange(db, {
      entityType: 'plan_todo',
      entityId: row.id,
      op: 'delete',
      actorId,
      payload: { ...toSyncTodo(row), deleted_at: timestamp },
      deviceId: row.device_id,
    });
  }

  return rows.length;
}

/** 最后一期「已执行」的期序（确认或跳过都算执行过）。没有则返回 0。 */
function lastExecutedSeq(db: DatabaseSync, planId: string): number {
  const row = db
    .prepare(
      `SELECT MAX(period_seq) AS seq FROM plan_todos
        WHERE plan_id = ? AND deleted_at IS NULL AND status IN ('confirmed', 'skipped')`,
    )
    .get(planId);
  return row === undefined || row['seq'] === null ? 0 : Number(row['seq']);
}

// ---------------------------------------------------------------------------
// 创建 / 修改 / 终止
// ---------------------------------------------------------------------------

export interface CreatePlanInput {
  name: string;
  categoryId: string;
  paymentMethodId: string;
  source: PlanSource;
  /** 手动计划：每期金额 */
  amountCents?: number | undefined;
  /** 分期：消费原价总额 */
  totalAmountCents?: number | undefined;
  /** 分期：消费日 */
  purchaseDate?: string | undefined;
  /** 期数。全部一次生成，所以必填 */
  periods: number;
  firstDueDate: string;
  remindDaysBefore?: number | undefined;
  autoPost?: boolean | undefined;
  note?: string | undefined;
  ownerId: string;
  /** 是否在创建后立即确认第一期（用于记账抽屉顺手分期：创建计划同时首期直接入账） */
  confirmFirst?: boolean | undefined;
  confirmSpendDate?: string | undefined;
}

export function createPlan(db: DatabaseSync, input: CreatePlanInput): PlanApi {
  const name = input.name.trim();
  if (name === '') throw badRequest('计划名称不能为空');
  if (name.length > 40) throw badRequest('计划名称不能超过 40 个字');

  const remindDaysBefore = input.remindDaysBefore ?? 3;
  if (!Number.isInteger(remindDaysBefore) || remindDaysBefore < 0 || remindDaysBefore > 60) {
    throw badRequest('提前提醒天数必须在 0–60 之间');
  }

  parseDate(input.firstDueDate);

  const category = requireUsableCategory(db, input.categoryId);
  const method = requireUsablePaymentMethod(db, input.paymentMethodId);
  const cycle = toPaymentCycle(method);

  // 每期金额：分期按「原价 ÷ 期数」拆（最后一期补足差额），手动则各期相同
  let amounts: number[];
  let totalAmountCents: number | null = null;
  let purchaseDate: string | null = null;

  if (input.source === 'installment') {
    const total = input.totalAmountCents;
    if (total === undefined) throw badRequest('分期必须提供消费原价总额');
    if (input.purchaseDate === undefined) throw badRequest('分期必须提供消费日');
    parseDate(input.purchaseDate);

    amounts = splitInstallment(total, input.periods);
    totalAmountCents = total;
    purchaseDate = input.purchaseDate;
  } else {
    const amount = input.amountCents;
    if (amount === undefined) throw badRequest('必须提供每期金额');
    if (!Number.isInteger(amount) || amount <= 0) throw badRequest('每期金额必须是正整数（单位：分）');
    if (!Number.isInteger(input.periods) || input.periods < 1 || input.periods > 600) {
      throw badRequest('期数必须在 1–600 之间');
    }
    amounts = Array.from({ length: input.periods }, () => amount);
  }

  const timestamp = nowIso();
  const plan: PlanRow = {
    id: ulid(),
    owner_id: input.ownerId,
    name,
    category_id: category.id,
    payment_method_id: method.id,
    amount_cents: amounts[0]!,
    total_amount_cents: totalAmountCents,
    purchase_date: purchaseDate,
    first_due_date: input.firstDueDate,
    remind_days_before: remindDaysBefore,
    auto_post: (input.autoPost ?? false) ? 1 : 0,
    source: input.source,
    state: 'active',
    note: (input.note ?? '').trim(),
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: null,
  };

  inTransaction(db, () => {
    db.prepare(
      `INSERT INTO plans (id, owner_id, name, category_id, payment_method_id, amount_cents,
                          total_amount_cents, purchase_date, first_due_date, remind_days_before,
                          auto_post, source, state, note, created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, NULL, 1, NULL)`,
    ).run(
      plan.id,
      plan.owner_id,
      plan.name,
      plan.category_id,
      plan.payment_method_id,
      plan.amount_cents,
      plan.total_amount_cents,
      plan.purchase_date,
      plan.first_due_date,
      plan.remind_days_before,
      plan.auto_post,
      plan.source,
      plan.note,
      plan.created_at,
      plan.updated_at,
    );

    recordChange(db, {
      entityType: 'plan',
      entityId: plan.id,
      op: 'upsert',
      actorId: input.ownerId,
      payload: toSyncPlan(plan),
      deviceId: null,
    });

    generateTodos(db, plan, cycle, 1, amounts, input.ownerId);

    if (input.confirmFirst) {
      const firstTodo = db
        .prepare(
          `SELECT id FROM plan_todos
            WHERE plan_id = ? AND period_seq = 1 AND deleted_at IS NULL`,
        )
        .get(plan.id) as { id: string } | undefined;
      if (firstTodo !== undefined) {
        confirmTodo(
          db,
          firstTodo.id,
          input.ownerId,
          input.confirmSpendDate ?? purchaseDate ?? input.firstDueDate,
        );
      }
    }
  });

  return toPlanApi(db, plan);
}

export interface UpdatePlanInput {
  name?: string | undefined;
  categoryId?: string | undefined;
  paymentMethodId?: string | undefined;
  /** 新的每期金额 */
  amountCents?: number | undefined;
  firstDueDate?: string | undefined;
  remindDaysBefore?: number | undefined;
  autoPost?: boolean | undefined;
  note?: string | undefined;
  /**
   * 重新生成的期数（从「最后一期已确认期 + 1」开始算）。
   * 不传则维持当前的剩余期数。
   */
  remainingPeriods?: number | undefined;
  actorId: string;
}

/**
 * 改计划（LPR 调整、提前还款都走这里）。
 *
 * 语义：**删掉未执行的待办 → 从「最后一期已执行期 + 1」重新生成**。
 * 已确认的历史期待办与支出记录原地不动。
 *
 * 为什么是「删除」而不是「标记作废」：作废会占住 `period_seq`，
 * 让重新生成的期序必须跳过一堆空洞，界面上「第 25 期」这种说法会变得难以解释。
 * 追溯由 `plan_revisions` 承担 —— 它记录了「本次删了几期、又生成了几期、参数从什么改成什么」，
 * 比留一堆不可见的作废行更有用。
 */
export function updatePlan(db: DatabaseSync, id: string, input: UpdatePlanInput): PlanApi {
  const existing = requireOwnPlan(db, id, input.actorId);

  const name = input.name === undefined ? existing.name : input.name.trim();
  if (name === '') throw badRequest('计划名称不能为空');
  if (name.length > 40) throw badRequest('计划名称不能超过 40 个字');

  const remindDaysBefore = input.remindDaysBefore ?? existing.remind_days_before;
  if (!Number.isInteger(remindDaysBefore) || remindDaysBefore < 0 || remindDaysBefore > 60) {
    throw badRequest('提前提醒天数必须在 0–60 之间');
  }

  const categoryId = input.categoryId ?? existing.category_id;
  const paymentMethodId = input.paymentMethodId ?? existing.payment_method_id;
  const amountCents = input.amountCents ?? existing.amount_cents;
  const firstDueDate = input.firstDueDate ?? existing.first_due_date;

  if (!Number.isInteger(amountCents) || amountCents <= 0) {
    throw badRequest('每期金额必须是正整数（单位：分）');
  }

  parseDate(firstDueDate);

  const category = requireUsableCategory(db, categoryId);
  const method = requireUsablePaymentMethod(db, paymentMethodId);
  const cycle = toPaymentCycle(method);

  const timestamp = nowIso();
  const next: PlanRow = {
    ...existing,
    name,
    category_id: category.id,
    payment_method_id: method.id,
    amount_cents: amountCents,
    first_due_date: firstDueDate,
    remind_days_before: remindDaysBefore,
    auto_post: (input.autoPost ?? existing.auto_post === 1) ? 1 : 0,
    note: input.note === undefined ? existing.note : input.note.trim(),
    updated_at: timestamp,
    rev: existing.rev + 1,
  };

  // 不传 remainingPeriods 就沿用当前剩余期数 —— 只改金额的场景（LPR 调整）不必再填一次
  const currentPending = db
    .prepare(
      "SELECT COUNT(*) AS n FROM plan_todos WHERE plan_id = ? AND deleted_at IS NULL AND status = 'pending'",
    )
    .get(id);
  const remainingPeriods = input.remainingPeriods ?? (currentPending === undefined ? 0 : Number(currentPending['n']));

  if (!Number.isInteger(remainingPeriods) || remainingPeriods < 0 || remainingPeriods > 600) {
    throw badRequest('剩余期数必须在 0–600 之间');
  }

  let cancelled = 0;
  let regenerated = 0;

  inTransaction(db, () => {
    cancelled = deletePendingTodos(db, id, input.actorId);
    const fromSeq = lastExecutedSeq(db, id) + 1;

    if (remainingPeriods > 0) {
      const amounts = Array.from({ length: remainingPeriods }, () => amountCents);
      regenerated = generateTodos(db, next, cycle, fromSeq, amounts, input.actorId);
    }

    db.prepare(
      `UPDATE plans SET name = ?, category_id = ?, payment_method_id = ?, amount_cents = ?,
                        first_due_date = ?, remind_days_before = ?, auto_post = ?, note = ?,
                        updated_at = ?, rev = ?
        WHERE id = ?`,
    ).run(
      next.name,
      next.category_id,
      next.payment_method_id,
      next.amount_cents,
      next.first_due_date,
      next.remind_days_before,
      next.auto_post,
      next.note,
      next.updated_at,
      next.rev,
      next.id,
    );

    db.prepare(
      `INSERT INTO plan_revisions (id, plan_id, changed_by, prev_amount_cents, prev_first_due_date,
                                   prev_remind_days_before, prev_auto_post, prev_state,
                                   cancelled_todo_count, regenerated_todo_count, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      ulid(),
      id,
      input.actorId,
      existing.amount_cents,
      existing.first_due_date,
      existing.remind_days_before,
      existing.auto_post,
      existing.state,
      cancelled,
      regenerated,
      next.note,
      timestamp,
    );

    recordChange(db, {
      entityType: 'plan',
      entityId: next.id,
      op: 'upsert',
      actorId: input.actorId,
      payload: toSyncPlan(next),
      deviceId: next.device_id,
    });
  });

  return toPlanApi(db, next);
}

/** 终止计划：作废未执行的待办，已确认的历史保留。 */
export function endPlan(db: DatabaseSync, id: string, actorId: string): PlanApi {
  const existing = requireOwnPlan(db, id, actorId);
  const timestamp = nowIso();

  const next: PlanRow = {
    ...existing,
    state: 'ended',
    updated_at: timestamp,
    rev: existing.rev + 1,
  };

  let cancelled = 0;

  inTransaction(db, () => {
    cancelled = deletePendingTodos(db, id, actorId);

    db.prepare('UPDATE plans SET state = ?, updated_at = ?, rev = ? WHERE id = ?').run(
      next.state,
      next.updated_at,
      next.rev,
      id,
    );

    db.prepare(
      `INSERT INTO plan_revisions (id, plan_id, changed_by, prev_amount_cents, prev_first_due_date,
                                   prev_remind_days_before, prev_auto_post, prev_state,
                                   cancelled_todo_count, regenerated_todo_count, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)`,
    ).run(
      ulid(),
      id,
      actorId,
      existing.amount_cents,
      existing.first_due_date,
      existing.remind_days_before,
      existing.auto_post,
      existing.state,
      cancelled,
      '终止计划',
      timestamp,
    );

    recordChange(db, {
      entityType: 'plan',
      entityId: next.id,
      op: 'upsert',
      actorId,
      payload: toSyncPlan(next),
      deviceId: next.device_id,
    });
  });

  return toPlanApi(db, next);
}

/**
 * 删除计划：
 * 1. 物理删除未执行的待办（pending），skipped 落入下一步软删除；
 * 2. 软删除其余待办（skipped / confirmed，记录墓碑变更）；
 * 3. 软删除计划本身（记录墓碑变更）；
 * 4. 历史已生成的支出保持不变。
 */
export function deletePlan(db: DatabaseSync, id: string, actorId: string): void {
  const existing = requireOwnPlan(db, id, actorId);
  const timestamp = nowIso();

  inTransaction(db, () => {
    // 1. 删除未执行的待办
    deletePendingTodos(db, id, actorId);

    // 2. 软删除已确认的待办
    const remainingTodos = db
      .prepare(`SELECT ${TODO_COLUMNS} FROM plan_todos WHERE plan_id = ? AND deleted_at IS NULL`)
      .all(id) as unknown as PlanTodoRow[];

    for (const todo of remainingTodos) {
      const nextTodo: PlanTodoRow = {
        ...todo,
        deleted_at: timestamp,
        updated_at: timestamp,
        rev: todo.rev + 1,
      };
      db.prepare('UPDATE plan_todos SET deleted_at = ?, updated_at = ?, rev = ? WHERE id = ?').run(
        nextTodo.deleted_at,
        nextTodo.updated_at,
        nextTodo.rev,
        todo.id,
      );
      recordChange(db, {
        entityType: 'plan_todo',
        entityId: todo.id,
        op: 'delete',
        actorId,
        payload: { ...toSyncTodo(nextTodo), deleted_at: timestamp },
        deviceId: nextTodo.device_id,
      });
    }

    // 3. 软删除计划本身
    const nextPlan: PlanRow = {
      ...existing,
      deleted_at: timestamp,
      updated_at: timestamp,
      rev: existing.rev + 1,
    };

    db.prepare('UPDATE plans SET deleted_at = ?, updated_at = ?, rev = ? WHERE id = ?').run(
      nextPlan.deleted_at,
      nextPlan.updated_at,
      nextPlan.rev,
      id,
    );

    recordChange(db, {
      entityType: 'plan',
      entityId: id,
      op: 'delete',
      actorId,
      payload: { ...toSyncPlan(nextPlan), deleted_at: timestamp },
      deviceId: nextPlan.device_id,
    });
  });
}

// ---------------------------------------------------------------------------
// 待办确认
// ---------------------------------------------------------------------------

export interface ConfirmTodoResult {
  todo: PlanTodoApi;
  expenseId: string;
}

/**
 * 确认一期待办 → 生成一条支出记录。
 *
 * 幂等的实现分两层，缺一不可：
 *   1. `(plan_id, period_seq)` 唯一索引 —— 防止同一期被插入两次
 *   2. `UPDATE ... WHERE status = 'pending'` + 检查 `changes` —— 防止同一行被改两次
 * 两个人各自离线点了同一笔房贷的确认，谁先写入谁成功，后到的收到「已被家人确认」。
 *
 * **记录人 = 点确认的人**（不是计划的所有者）：家庭里谁操作谁负责，
 * 而且这条规则让「两人离线各点一次」有一个确定的归属。
 */
export function confirmTodo(
  db: DatabaseSync,
  todoId: string,
  actorId: string,
  spendDate?: string | undefined,
): ConfirmTodoResult {
  const todo = findTodoRow(db, todoId);
  if (todo === null) throw notFound(`待办不存在：${todoId}`);

  const plan = findPlanRow(db, todo.plan_id);
  if (plan === null) throw notFound('待办所属的计划已被删除');

  if (todo.status === 'confirmed') throw conflict('这一期已经确认过了');
  if (todo.status !== 'pending') throw conflict(`这一期已作废（${todo.status}），无法确认`);

  /**
   * `spendDate` 是「实际哪天付的」，**不影响报表月份归属**。
   *
   * 归属仍以待办的还款日为准：这笔钱在计划里就是那天该付的，
   * 隔了几天才补点确认不该把它挪到别的月份去 —— 否则「忘记点确认」
   * 会莫名其妙地改变历史报表。逾期确认时允许改的只是记录上的实际付款日。
   */
  const finalSpendDate = spendDate ?? todo.repayment_date;
  parseDate(finalSpendDate);

  const expenseId = ulid();
  const timestamp = nowIso();

  const expenseRow: ExpenseRow = {
    id: expenseId,
    owner_id: actorId,
    amount_cents: todo.amount_cents,
    category_id: plan.category_id,
    payment_method_id: plan.payment_method_id,
    spend_date: finalSpendDate,
    posting_date: todo.posting_date,
    repayment_date: todo.repayment_date,
    note: plan.name,
    source: 'plan',
    plan_id: plan.id,
    plan_period_seq: todo.period_seq,
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: null,
  };

  let updated: PlanTodoRow | null = null;

  inTransaction(db, () => {
    /**
     * 顺序不能反：**先插支出记录，再回头把它的 id 写进待办**。
     *
     * `plan_todos.expense_id` 有外键指向 `expenses(id)`，且外键是立即检查的 ——
     * 先更新待办会当场撞上 `FOREIGN KEY constraint failed`，因为那条支出还不存在。
     *
     * 「先插支出」不会破坏幂等：整个函数在一个事务里，
     * 下面条件更新没命中时会抛异常，事务回滚会把刚插入的支出一起撤掉。
     */
    insertPlanExpense(db, expenseRow, actorId);

    const info = db
      .prepare(
        `UPDATE plan_todos
            SET status = 'confirmed', posted_date = ?, confirmed_by = ?, confirmed_at = ?,
                expense_id = ?, updated_at = ?, rev = rev + 1
          WHERE id = ? AND status = 'pending' AND deleted_at IS NULL`,
      )
      .run(finalSpendDate, actorId, timestamp, expenseId, timestamp, todoId);

    if (Number(info.changes) !== 1) {
      // 条件更新没命中 = 有人抢先确认了；抛异常让上面那条支出一起回滚
      throw conflict('这一期已被家人确认');
    }

    updated = {
      ...todo,
      status: 'confirmed',
      posted_date: finalSpendDate,
      confirmed_by: actorId,
      confirmed_at: timestamp,
      expense_id: expenseId,
      updated_at: timestamp,
      rev: todo.rev + 1,
    };

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: todoId,
      op: 'upsert',
      actorId,
      payload: toSyncTodo(updated),
      deviceId: null,
    });
  });

  if (updated === null) throw new Error('确认后读取失败，数据库状态异常');
  return { todo: toTodoApi(updated, plan), expenseId };
}

/** 跳过某一期（这个月没有这笔支出，比如房租免了一个月）。 */
export function skipTodo(db: DatabaseSync, todoId: string, actorId: string): PlanTodoApi {
  const todo = findTodoRow(db, todoId);
  if (todo === null) throw notFound(`待办不存在：${todoId}`);

  const plan = findPlanRow(db, todo.plan_id);
  if (plan === null) throw notFound('待办所属的计划已被删除');

  if (todo.status !== 'pending') throw conflict(`这一期不是待确认状态（${todo.status}）`);

  const timestamp = nowIso();

  inTransaction(db, () => {
    const info = db
      .prepare(
        `UPDATE plan_todos SET status = 'skipped', updated_at = ?, rev = rev + 1
          WHERE id = ? AND status = 'pending' AND deleted_at IS NULL`,
      )
      .run(timestamp, todoId);

    if (Number(info.changes) !== 1) throw conflict('这一期刚被处理过，请刷新后重试');

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: todoId,
      op: 'upsert',
      actorId,
      payload: toSyncTodo({ ...todo, status: 'skipped', updated_at: timestamp, rev: todo.rev + 1 }),
      deviceId: null,
    });
  });

  return toTodoApi({ ...todo, status: 'skipped', updated_at: timestamp }, plan);
}

/**
 * 「我知道了」：确认一条**会自动入账**的提醒。
 *
 * 它是三类动作里唯一**不改业务状态**的一个 —— 只把 `ack_at` 写上，
 * 让这一条从「该处理了」里消失，同时保持 `status = 'pending'`，
 * 到还款日 `settleAutoPost` 照旧把它入账。
 *
 * 为什么必须有它（而不是让用户按「入账」）：这类期次的账**本来就会自动生成**，
 * 让用户提前手动入账只会让支出日期与计划不符；而按「忽略」又会走 `skipTodo`，
 * 把这一期从自动入账的范围里摘掉 —— 那是**偷偷关掉自动入账**。
 * 用户要的只是「别提醒我」，不是「别记账」。
 *
 * 幂等：`ack_at IS NULL` 是条件的一部分，重复点不会推进任何东西，
 * 也不会把第一次的时间戳覆盖掉（「什么时候看到的」不该被第二次点击改写）。
 * 已经确认过再点不报错，直接返回当前状态 —— 两个人各自点一次是常见情形。
 */
export function ackTodo(db: DatabaseSync, todoId: string, actorId: string): PlanTodoApi {
  const todo = findTodoRow(db, todoId);
  if (todo === null) throw notFound(`待办不存在：${todoId}`);

  const plan = findPlanRow(db, todo.plan_id);
  if (plan === null) throw notFound('待办所属的计划已被删除');

  if (todo.status !== 'pending') throw conflict(`这一期不是待确认状态（${todo.status}）`);

  // 已经确认过：直接返回，不覆盖第一次的时间戳
  if (todo.ack_at !== null) return toTodoApi(todo, plan);

  const timestamp = nowIso();
  const updated: PlanTodoRow = { ...todo, ack_at: timestamp, updated_at: timestamp, rev: todo.rev + 1 };

  inTransaction(db, () => {
    const info = db
      .prepare(
        `UPDATE plan_todos SET ack_at = ?, updated_at = ?, rev = rev + 1
          WHERE id = ? AND status = 'pending' AND ack_at IS NULL AND deleted_at IS NULL`,
      )
      .run(timestamp, timestamp, todoId);

    // 没命中说明并发里已经有人确认过了 —— 与上面那个提前返回等价，不算失败
    if (Number(info.changes) !== 1) return;

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: todoId,
      op: 'upsert',
      actorId,
      payload: toSyncTodo(updated),
      deviceId: null,
    });
  });

  return toTodoApi(findTodoRow(db, todoId) ?? updated, plan);
}

/**
 * 恢复一个被跳过的期次（`skipped → pending`）。
 *
 * 跳过同样要可逆：用户可能手滑跳过了这一期，或者「这个月免了」后来又发现要付。
 *
 * **必须置 `hold_auto_post = 1`**：被跳过的期次通常已经到期甚至过期，
 * 恢复成 `pending` 的那个瞬间它就满足 `repayment_date <= today`，
 * 若还在自动入账计划里，会被 `settleAutoPost` 当场入账 ——
 * 用户看到的是「一按恢复，它直接变成已付」，又一次「按了没用」。
 * 恢复的语义是「把它放回待办列表等我处理」，不是「立刻替我付款」。
 *
 * **并且要清掉 `ack_at`**：被恢复的期次是「要用户做决定」的那一类，
 * 它必须重新出现在「该处理了」里。不清的话，一度被确认过的期次
 * 在恢复后**再也不会提醒** —— 看起来就像「恢复按钮没反应」。
 */
export function restoreSkippedTodo(db: DatabaseSync, todoId: string, actorId: string): PlanTodoApi {
  const todo = findTodoRow(db, todoId);
  if (todo === null) throw notFound(`待办不存在：${todoId}`);

  const plan = findPlanRow(db, todo.plan_id);
  if (plan === null) throw notFound('待办所属的计划已被删除');

  if (todo.status !== 'skipped') throw conflict(`这一期不是已跳过状态（${todo.status}），无法恢复`);

  const timestamp = nowIso();
  let updated: PlanTodoRow | null = null;

  inTransaction(db, () => {
    const info = db
      .prepare(
        `UPDATE plan_todos
            SET status = 'pending', hold_auto_post = 1, ack_at = NULL,
                updated_at = ?, rev = rev + 1
          WHERE id = ? AND status = 'skipped' AND deleted_at IS NULL`,
      )
      .run(timestamp, todoId);

    if (Number(info.changes) !== 1) throw conflict('这一期刚被处理过，请刷新后重试');

    updated = {
      ...todo,
      status: 'pending',
      hold_auto_post: 1,
      ack_at: null,
      updated_at: timestamp,
      rev: todo.rev + 1,
    };

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: todoId,
      op: 'upsert',
      actorId,
      payload: toSyncTodo(updated),
      deviceId: null,
    });
  });

  if (updated === null) throw new Error('恢复后读取失败，数据库状态异常');
  return toTodoApi(updated, plan);
}

export interface RevertTodoResult {
  todo: PlanTodoApi;
  /** 被撤销的那条支出记录 id（已软删）。 */
  expenseId: string;
}

/**
 * 撤销一次确认（`confirmed → pending`）。
 *
 * 现状是确认入账后**没有任何反悔路径**：点错了日期、点错了一期、
 * 或者自动入账在前一天把还没付的房贷算进去了，用户只能去删那条支出 ——
 * 而 `softDeleteExpense` 会当场拒绝（「这条记录由计划生成」），
 * 于是用户被卡在一个既不能改也不能删的状态里。
 *
 * 三件事必须在**同一个事务**里完成，否则会留下「支出没了但待办还显示已付」
 * 或反过来「待办回待办了但支出还挂在报表里」的半截状态：
 *   1. 给生成的支出打墓碑（软删 + `op: 'delete'` 变更），而不是物理删除 ——
 *      同步层靠变更日志做增量，物理删除会让其他设备永远不知道它没了。
 *   2. 待办回 `pending`，清空 `posted_date / confirmed_by / confirmed_at / expense_id`。
 *   3. 置 `hold_auto_post = 1`：**没有这一步，撤销在自动入账的计划上是假的** ——
 *      回到 pending 的下一瞬间就会被 `settleAutoPost` 重新入账。
 *
 * 不做物理删除待办、也不留期序空洞（见 `docs/decision.md`）：
 * 进度是相对计划整体算的，删掉一期会让「已还 N 期 / 剩余 M 期 / 预计结清」全部错位。
 * 回 `pending` 保留位置，只是把它压住，用户可以再确认回来。
 *
 * 权限与「确认」对称：确认是家庭共同事务，两人都能做；撤销是它的逆操作，
 * 也两人都能做。这不是放松 —— 撤销本身可逆（再确认一次就回来了），
 * 而它唯一的破坏性动作（软删支出）留下的墓碑同样可以通过重新确认覆盖。
 */
export function revertTodoConfirm(db: DatabaseSync, todoId: string, actorId: string): RevertTodoResult {
  const todo = findTodoRow(db, todoId);
  if (todo === null) throw notFound(`待办不存在：${todoId}`);

  const plan = findPlanRow(db, todo.plan_id);
  if (plan === null) throw notFound('待办所属的计划已被删除');

  if (todo.status !== 'confirmed') {
    throw conflict(`这一期不是已确认状态（${todo.status}），无法撤销`);
  }
  if (todo.expense_id === null) {
    // schema 的 `status = 'confirmed' → expense_id NOT NULL` 保证不该发生，
    // 走到这里只可能是数据被外部改过；给一条能自查的错误，而不是静默成功
    throw conflict('这一期没有关联的支出记录，无法撤销');
  }

  const expenseId = todo.expense_id;
  // 支出可能已被别处软删（并发撤销、或恢复导入覆盖）；那时只需把待办拉回 pending
  const expense = findExpenseRow(db, expenseId);
  const timestamp = nowIso();
  let updated: PlanTodoRow | null = null;

  inTransaction(db, () => {
    if (expense !== null) {
      const tombstone: ExpenseRow = {
        ...expense,
        deleted_at: timestamp,
        updated_at: timestamp,
        rev: expense.rev + 1,
      };

      db.prepare('UPDATE expenses SET deleted_at = ?, updated_at = ?, rev = ? WHERE id = ?').run(
        timestamp,
        timestamp,
        tombstone.rev,
        expenseId,
      );

      recordChange(db, {
        entityType: 'expense',
        entityId: expenseId,
        op: 'delete',
        actorId,
        payload: toSyncExpense(tombstone),
        deviceId: expense.device_id,
      });
    }

    const info = db
      .prepare(
        `UPDATE plan_todos
            SET status = 'pending', posted_date = NULL, confirmed_by = NULL, confirmed_at = NULL,
                expense_id = NULL, hold_auto_post = 1, ack_at = NULL,
                updated_at = ?, rev = rev + 1
          WHERE id = ? AND status = 'confirmed' AND deleted_at IS NULL`,
      )
      .run(timestamp, todoId);

    if (Number(info.changes) !== 1) throw conflict('这一期刚被处理过，请刷新后重试');

    updated = {
      ...todo,
      status: 'pending',
      posted_date: null,
      confirmed_by: null,
      confirmed_at: null,
      expense_id: null,
      hold_auto_post: 1,
      ack_at: null,
      updated_at: timestamp,
      rev: todo.rev + 1,
    };

    recordChange(db, {
      entityType: 'plan_todo',
      entityId: todoId,
      op: 'upsert',
      actorId,
      payload: toSyncTodo(updated),
      deviceId: null,
    });
  });

  if (updated === null) throw new Error('撤销后读取失败，数据库状态异常');
  return { todo: toTodoApi(updated, plan), expenseId };
}

/**
 * 结算到期的自动入账待办。
 *
 * 在客户端打开仪表盘时触发（`today` 由客户端按本地时区传入）。
 * **服务端没有定时任务**，这是刻意的：定时任务要处理服务器停机期间的补生成、
 * 时区、以及「跑了两遍」的幂等 —— 而幂等已经由待办的状态机天然保证了。
 *
 * 自动入账没有「操作人」，所以记录人取计划的所有者。
 *
 * `hold_auto_post = 0` 这个条件是**撤销与恢复跳过的前提**，不是可选过滤：
 * 被撤销的期次会回到 `pending`，它在自动入账的计划里到期即满足其余所有条件，
 * 少了这一条就会在用户下次打开首页时被立刻重新入账 —— 表现为「撤销按了没用」，
 * 且不报错。同理，恢复跳过的期次几乎总是已到期的，恢复的那一刻就会被当场入账。
 */
export function settleAutoPost(db: DatabaseSync, today: string): number {
  parseDate(today);

  const rows = db
    .prepare(
      `SELECT t.id AS id, p.owner_id AS owner_id
         FROM plan_todos t JOIN plans p ON p.id = t.plan_id
        WHERE t.status = 'pending' AND t.deleted_at IS NULL AND t.hold_auto_post = 0
          AND p.deleted_at IS NULL AND p.state = 'active' AND p.auto_post = 1
          AND t.repayment_date <= ?
        ORDER BY t.repayment_date, t.period_seq`,
    )
    .all(today) as unknown as Array<{ id: string; owner_id: string }>;

  let settled = 0;

  for (const row of rows) {
    try {
      // 自动入账以计划所有者作为记录人 —— 它没有「点确认的人」
      confirmTodo(db, String(row.id), String(row.owner_id));
      settled += 1;
    } catch {
      // 已被并发处理（例如两个设备同时打开首页），跳过即可
    }
  }

  return settled;
}
