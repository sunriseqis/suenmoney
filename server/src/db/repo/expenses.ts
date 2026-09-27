import type { DatabaseSync } from 'node:sqlite';

import { resolveExpenseDates } from '../../domain/billing-cycle.ts';
import { badRequest, forbidden, notFound } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange } from '../sync.ts';
import { requireUsableCategory } from './categories.ts';
import { requireUsablePaymentMethod, toPaymentCycle } from './payment-methods.ts';

/**
 * 单笔支出的上限：10 亿元（1e11 分）。
 *
 * 这不是业务规则，而是**输入防呆**：键盘上多按几个 0 会得到一个天文数字，
 * 而它会立刻把月度总额、分类占比、环比全部污染成无意义的数字。
 * 记账应用里「金额打错一笔，整月报表失去参考价值」是真实且高频的挫败。
 */
const MAX_AMOUNT_CENTS = 100_000_000_000;

/** 备注上限。超出多半是粘贴了一整段文本，不该进账本。 */
const MAX_NOTE_LENGTH = 200;

export interface ExpenseRow {
  id: string;
  owner_id: string;
  amount_cents: number;
  category_id: string;
  payment_method_id: string;
  spend_date: string;
  posting_date: string;
  repayment_date: string;
  note: string;
  source: 'manual' | 'plan';
  plan_id: string | null;
  plan_period_seq: number | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
}

/** 列表查询会额外 JOIN 出这些展示字段，省掉客户端的 N+1 查询 */
export interface ExpenseRowJoined extends ExpenseRow {
  owner_name: string;
  category_name: string;
  /** 二级分类的图标名；分类没设图标时是空字符串，由前端按名字兜底 */
  category_icon: string;
  /** 分类色号（'1'–'8'）；空字符串表示没设过，由前端按分类名推导 */
  category_color: string;
  /** 二级分类才有：父分类（一级）的色号；一级分类本身是 null */
  parent_category_color: string | null;
  parent_category_name: string | null;
  payment_method_name: string;
  payment_method_type: 'cash' | 'credit';
}

export interface Expense {
  id: string;
  ownerId: string;
  ownerName: string;
  amountCents: number;
  categoryId: string;
  categoryName: string;
  /** 图标名（见前端 utils/icons.ts 的登记表）；空字符串表示该分类没设图标 */
  categoryIcon: string;
  /** 分类色号（'1'–'8'）；空字符串表示没设过，由前端按分类名推导 */
  categoryColor: string;
  /** 二级分类才有：父分类（一级）的色号；一级分类本身是 null */
  parentCategoryColor: string | null;
  parentCategoryName: string | null;
  paymentMethodId: string;
  paymentMethodName: string;
  paymentMethodType: 'cash' | 'credit';
  spendDate: string;
  postingDate: string;
  repaymentDate: string;
  note: string;
  source: 'manual' | 'plan';
  planId: string | null;
  planPeriodSeq: number | null;
  createdAt: string;
  updatedAt: string;
}

const COLUMNS = `e.id, e.owner_id, e.amount_cents, e.category_id, e.payment_method_id,
                 e.spend_date, e.posting_date, e.repayment_date, e.note, e.source,
                 e.plan_id, e.plan_period_seq, e.created_at, e.updated_at,
                 e.deleted_at, e.rev, e.device_id`;

const JOINS = `JOIN users u ON u.id = e.owner_id
               LEFT JOIN categories c ON c.id = e.category_id
               LEFT JOIN categories p ON p.id = c.parent_id
               JOIN payment_methods m ON m.id = e.payment_method_id`;

/**
 * 列表与详情共用的展示列。
 *
 * 抽成常量而不是在两处 SQL 里各写一遍：一旦漂移，就会出现
 * 「流水列表有图标、编辑抽屉里没有」这种只在某条路径下暴露的差异，
 * 而它不会报错、测试也不一定覆盖到。
 */
const DISPLAY_COLUMNS = `${COLUMNS},
                         u.display_name AS owner_name,
                         c.name AS category_name,
                         c.icon AS category_icon,
                         c.color AS category_color,
                         p.color AS parent_category_color,
                         p.name AS parent_category_name,
                         m.name AS payment_method_name,
                         m.type AS payment_method_type`;

const nowIso = (): string => new Date().toISOString();

export function toApi(row: ExpenseRowJoined): Expense {
  return {
    id: row.id,
    ownerId: row.owner_id,
    ownerName: row.owner_name,
    amountCents: row.amount_cents,
    categoryId: row.category_id,
    categoryName: row.category_name,
    categoryIcon: row.category_icon,
    categoryColor: row.category_color,
    parentCategoryColor: row.parent_category_color,
    parentCategoryName: row.parent_category_name,
    paymentMethodId: row.payment_method_id,
    paymentMethodName: row.payment_method_name,
    paymentMethodType: row.payment_method_type,
    spendDate: row.spend_date,
    postingDate: row.posting_date,
    repaymentDate: row.repayment_date,
    note: row.note,
    source: row.source,
    planId: row.plan_id,
    planPeriodSeq: row.plan_period_seq,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * 同步给客户端的快照。
 *
 * 用**扁平的下划线字段名**而不是 API 的驼峰名：客户端拿到后是直接 upsert
 * 进本地表，字段名与本地表列名一致可以少一层映射，也少一处可能写错的地方。
 */
export function toSyncExpense(row: ExpenseRow): Record<string, unknown> {
  return {
    id: row.id,
    owner_id: row.owner_id,
    amount_cents: row.amount_cents,
    category_id: row.category_id,
    payment_method_id: row.payment_method_id,
    spend_date: row.spend_date,
    posting_date: row.posting_date,
    repayment_date: row.repayment_date,
    note: row.note,
    source: row.source,
    plan_id: row.plan_id,
    plan_period_seq: row.plan_period_seq,
    updated_at: row.updated_at,
    deleted_at: row.deleted_at,
    rev: row.rev,
    device_id: row.device_id,
  };
}

function validateAmount(amountCents: number): void {
  if (!Number.isInteger(amountCents) || amountCents === 0) {
    throw badRequest('金额必须是非零整数（单位：分）');
  }
  if (Math.abs(amountCents) > MAX_AMOUNT_CENTS) {
    throw badRequest('金额超出上限（10 亿元），请检查是否多输了 0');
  }
}

function validateNote(note: string): string {
  const trimmed = note.trim();
  if (trimmed.length > MAX_NOTE_LENGTH) {
    throw badRequest(`备注不能超过 ${MAX_NOTE_LENGTH} 个字`);
  }
  return trimmed;
}

export function findExpenseRow(db: DatabaseSync, id: string): ExpenseRow | null {
  const row = db
    .prepare(`SELECT ${COLUMNS} FROM expenses e WHERE e.id = ? AND e.deleted_at IS NULL`)
    .get(id);
  return (row as unknown as ExpenseRow | undefined) ?? null;
}

export function findExpense(db: DatabaseSync, id: string): Expense | null {
  const row = db
    .prepare(`SELECT ${DISPLAY_COLUMNS}
               FROM expenses e ${JOINS}
              WHERE e.id = ? AND e.deleted_at IS NULL`)
    .get(id);
  return row === undefined ? null : toApi(row as unknown as ExpenseRowJoined);
}

/** 取一条记录并断言当前用户有权修改它。 */
export function requireOwnExpense(db: DatabaseSync, id: string, actorId: string): ExpenseRow {
  const row = findExpenseRow(db, id);
  if (row === null) throw notFound(`支出记录不存在：${id}`);

  /**
   * 权限是「只能改自己记录的账」—— 这条规则同时是**离线冲突的消解机制**：
   * 每条记录只有一个写入者，两个人各自离线修改的就永远是不同记录，
   * 编辑冲突在结构上不存在，只剩同一人两台设备的极端情况由 LWW 兜底。
   */
  if (row.owner_id !== actorId) {
    throw forbidden('只能修改自己记录的支出');
  }

  return row;
}

export interface ListExpensesFilter {
  /** 'YYYY-MM'，按还款日所在月份过滤 */
  month?: string | undefined;
  from?: string | undefined;
  to?: string | undefined;
  categoryId?: string | undefined;
  paymentMethodId?: string | undefined;
  ownerId?: string | undefined;
  /** 备注模糊搜索 */
  keyword?: string | undefined;
  limit?: number | undefined;
  /** 键集分页游标，格式 `${repayment_date}|${id}` */
  cursor?: string | undefined;
}

export interface ListExpensesResult {
  items: Expense[];
  nextCursor: string | null;
  hasMore: boolean;
}

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

/**
 * 流水分页查询。
 *
 * 用**键集分页**（`(repayment_date, id)` 元组比较）而不是 OFFSET：
 * OFFSET 在深翻页时要求 SQLite 扫描并丢弃前面所有行，而且并发写入会让
 * 分页结果错位（第二页重复或漏掉记录）。键集分页两个问题都没有。
 */
export function listExpenses(
  db: DatabaseSync,
  filter: ListExpensesFilter,
): ListExpensesResult {
  const where: string[] = ['e.deleted_at IS NULL'];
  const params: Array<string | number> = [];

  if (filter.month !== undefined) {
    where.push("e.repayment_date LIKE ? || '%'");
    params.push(filter.month);
  }
  if (filter.from !== undefined) {
    where.push('e.repayment_date >= ?');
    params.push(filter.from);
  }
  if (filter.to !== undefined) {
    where.push('e.repayment_date <= ?');
    params.push(filter.to);
  }
  if (filter.categoryId !== undefined) {
    // 给一级分类时连带它的二级分类一起算 —— 用户点「餐饮」时想看的是全部餐饮
    where.push(
      `(e.category_id = ? OR e.category_id IN (SELECT id FROM categories WHERE parent_id = ?))`,
    );
    params.push(filter.categoryId, filter.categoryId);
  }
  if (filter.paymentMethodId !== undefined) {
    where.push('e.payment_method_id = ?');
    params.push(filter.paymentMethodId);
  }
  if (filter.ownerId !== undefined) {
    where.push('e.owner_id = ?');
    params.push(filter.ownerId);
  }
  if (filter.keyword !== undefined && filter.keyword !== '') {
    // LIKE 里的 % 与 _ 是通配符，用户搜「50%」时不该被当成模式
    const escaped = filter.keyword.replace(/[\\%_]/g, (char) => `\\${char}`);
    where.push("e.note LIKE '%' || ? || '%' ESCAPE '\\'");
    params.push(escaped);
  }

  if (filter.cursor !== undefined) {
    const [cursorDate, cursorId] = filter.cursor.split('|');
    if (cursorDate !== undefined && cursorId !== undefined) {
      // 不要用 SQLite 的行值比较 (a,b) < (c,d)：语义虽对，但写法在跨版本时
      // 容易踩到解析差异。展开成等价的显式条件，行为一目了然。
      where.push('(e.repayment_date < ? OR (e.repayment_date = ? AND e.id < ?))');
      params.push(cursorDate, cursorDate, cursorId);
    }
  }

  const limit = Math.min(Math.max(filter.limit ?? DEFAULT_LIMIT, 1), MAX_LIMIT);

  // 多取一条用来判断还有没有下一页，比再发一次 COUNT 查询便宜
  const rows = db
    .prepare(
      `SELECT ${DISPLAY_COLUMNS}
         FROM expenses e ${JOINS}
        WHERE ${where.join(' AND ')}
        ORDER BY e.repayment_date DESC, e.id DESC
        LIMIT ?`,
    )
    .all(...params, limit + 1) as unknown as ExpenseRowJoined[];

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const last = page.at(-1);

  return {
    items: page.map(toApi),
    nextCursor: hasMore && last !== undefined ? `${last.repayment_date}|${last.id}` : null,
    hasMore,
  };
}

/**
 * 只算日期、不落库。
 *
 * 存在的意义：记账抽屉要在用户选完支付方式与日期后立刻告诉他
 * **「这笔会记在哪个月」**。没有这个提示，用户会看到「刚记完本月还是 0」
 * 而以为保存失败 —— 因为信用卡的还款日很可能落在下个月。
 *
 * 之所以做成服务端接口而不是在前端再实现一遍账单周期：那段逻辑是整个项目
 * 最容易「看着对、少数情况下错一个月」的地方，两份实现迟早会漂移，
 * 而漂移的方式是**安静地算错**。宁可多一次请求。
 */
export function previewExpenseDates(
  db: DatabaseSync,
  input: { spendDate: string; paymentMethodId: string },
): { postingDate: string; repaymentDate: string } {
  const method = requireUsablePaymentMethod(db, input.paymentMethodId);
  return resolveExpenseDates(input.spendDate, toPaymentCycle(method));
}

export interface CreateExpenseInput {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  /** 消费日 'YYYY-MM-DD'。由客户端按本地时区判定后传入，服务端不推算。 */
  spendDate: string;
  note?: string | undefined;
  ownerId: string;
  deviceId?: string | null;
}

/**
 * 新建支出。
 *
 * 这里是「配置」与「算法」的汇合点：支付方式只描述事实（账单日几号、
 * 还款日几号），由 `domain/billing-cycle` 把消费日映射成入账日与还款日，
 * 再**冗余落库** —— 报表要按 repayment_date 聚合，必须能走索引。
 */
export function createExpense(db: DatabaseSync, input: CreateExpenseInput): Expense {
  validateAmount(input.amountCents);
  const note = validateNote(input.note ?? '');

  const category = requireUsableCategory(db, input.categoryId);
  const method = requireUsablePaymentMethod(db, input.paymentMethodId);

  const { postingDate, repaymentDate } = resolveExpenseDates(
    input.spendDate,
    toPaymentCycle(method),
  );

  const timestamp = nowIso();
  const row: ExpenseRow = {
    id: ulid(),
    owner_id: input.ownerId,
    amount_cents: input.amountCents,
    category_id: category.id,
    payment_method_id: method.id,
    spend_date: input.spendDate,
    posting_date: postingDate,
    repayment_date: repaymentDate,
    note,
    source: 'manual',
    plan_id: null,
    plan_period_seq: null,
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: input.deviceId ?? null,
  };

  insertExpense(db, row, input.ownerId);

  const created = findExpense(db, row.id);
  if (created === null) throw new Error('写入后读取失败，数据库状态异常');
  return created;
}

/** 计划生成支出时复用（source='plan'）。 */
export function insertPlanExpense(db: DatabaseSync, row: ExpenseRow, actorId: string): void {
  insertExpense(db, row, actorId);
}

function insertExpense(db: DatabaseSync, row: ExpenseRow, actorId: string): void {
  inTransaction(db, () => {
    db.prepare(
      `INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                             spend_date, posting_date, repayment_date, note, source,
                             plan_id, plan_period_seq, created_at, updated_at,
                             deleted_at, rev, device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)`,
    ).run(
      row.id,
      row.owner_id,
      row.amount_cents,
      row.category_id,
      row.payment_method_id,
      row.spend_date,
      row.posting_date,
      row.repayment_date,
      row.note,
      row.source,
      row.plan_id,
      row.plan_period_seq,
      row.created_at,
      row.updated_at,
      row.rev,
      row.device_id,
    );

    recordChange(db, {
      entityType: 'expense',
      entityId: row.id,
      op: 'upsert',
      actorId,
      payload: toSyncExpense(row),
      deviceId: row.device_id,
    });
  });
}

export interface UpdateExpenseInput {
  amountCents?: number | undefined;
  categoryId?: string | undefined;
  paymentMethodId?: string | undefined;
  spendDate?: string | undefined;
  note?: string | undefined;
  actorId: string;
  deviceId?: string | null;
}

export function updateExpense(db: DatabaseSync, id: string, input: UpdateExpenseInput): Expense {
  const existing = requireOwnExpense(db, id, input.actorId);

  /**
   * 计划生成的记录只允许改备注。
   *
   * 金额与日期来自计划和它的待办；独立修改会让「已还多少期」「剩余未付」
   * 这些派生指标与台账对不上，而且**没有任何机制能发现这种不一致** ——
   * 报表会安静地算错。要改就走计划本身（改计划会作废旧待办并重算）。
   * 备注是纯附加信息，改了不产生任何联动。
   */
  const touchesCore =
    input.amountCents !== undefined ||
    input.categoryId !== undefined ||
    input.paymentMethodId !== undefined ||
    input.spendDate !== undefined;

  if (existing.source === 'plan' && touchesCore) {
    throw forbidden('这条记录由计划生成，金额与日期请在计划里修改；此处只能改备注');
  }

  const amountCents = input.amountCents ?? existing.amount_cents;
  validateAmount(amountCents);

  const categoryId = input.categoryId ?? existing.category_id;
  const paymentMethodId = input.paymentMethodId ?? existing.payment_method_id;
  const spendDate = input.spendDate ?? existing.spend_date;
  const note = input.note === undefined ? existing.note : validateNote(input.note);

  const category = requireUsableCategory(db, categoryId);
  const method = requireUsablePaymentMethod(db, paymentMethodId);

  // 改了消费日或支付方式就必须重算账单日期：否则一笔 9 日的账被改成 11 日
  // 之后，还款日还停在原处，月份归属就错了。
  const { postingDate, repaymentDate } = resolveExpenseDates(spendDate, toPaymentCycle(method));

  const next: ExpenseRow = {
    ...existing,
    amount_cents: amountCents,
    category_id: category.id,
    payment_method_id: method.id,
    spend_date: spendDate,
    posting_date: postingDate,
    repayment_date: repaymentDate,
    note,
    updated_at: nowIso(),
    rev: existing.rev + 1,
    device_id: input.deviceId ?? existing.device_id,
  };

  inTransaction(db, () => {
    db.prepare(
      `UPDATE expenses
          SET amount_cents = ?, category_id = ?, payment_method_id = ?,
              spend_date = ?, posting_date = ?, repayment_date = ?, note = ?,
              updated_at = ?, rev = ?, device_id = ?
        WHERE id = ?`,
    ).run(
      next.amount_cents,
      next.category_id,
      next.payment_method_id,
      next.spend_date,
      next.posting_date,
      next.repayment_date,
      next.note,
      next.updated_at,
      next.rev,
      next.device_id,
      next.id,
    );

    recordChange(db, {
      entityType: 'expense',
      entityId: next.id,
      op: 'upsert',
      actorId: input.actorId,
      payload: toSyncExpense(next),
      deviceId: next.device_id,
    });
  });

  const updated = findExpense(db, id);
  if (updated === null) throw new Error('更新后读取失败，数据库状态异常');
  return updated;
}

/**
 * 软删除。
 *
 * 绝不物理删除：其他设备的本地副本里还有这条记录，物理删除后它会在下次
 * 同步时被「复活」。墓碑（deleted_at + 一条 op='delete' 的变更）才是正确做法。
 */
export function softDeleteExpense(db: DatabaseSync, id: string, actorId: string): void {
  const existing = requireOwnExpense(db, id, actorId);

  if (existing.source === 'plan') {
    throw forbidden('这条记录由计划生成，请在计划里作废该期，而不是直接删除');
  }

  const timestamp = nowIso();
  const next: ExpenseRow = { ...existing, deleted_at: timestamp, updated_at: timestamp, rev: existing.rev + 1 };

  inTransaction(db, () => {
    db.prepare('UPDATE expenses SET deleted_at = ?, updated_at = ?, rev = ? WHERE id = ?').run(
      timestamp,
      timestamp,
      next.rev,
      id,
    );

    recordChange(db, {
      entityType: 'expense',
      entityId: id,
      op: 'delete',
      actorId,
      payload: toSyncExpense(next),
      deviceId: existing.device_id,
    });
  });
}

/**
 * 把某分类下的全部支出转移到另一个分类。
 *
 * 用途：停用一个分类之前要把记录腾空（分类是共享字典，且历史记录不能失去
 * 分类维度 —— 那会让报表里出现一块「未分类」黑洞，还会随同步扩散到所有设备）。
 *
 * 逐条更新并逐条记录变更，而不是一条 UPDATE 了事：同步层是按实体粒度
 * 记录变更的，批量 UPDATE 会导致客户端拿到「不知道哪些记录变了」。
 */
export function transferExpenses(
  db: DatabaseSync,
  fromCategoryId: string,
  toCategoryId: string,
  actorId: string,
): number {
  const target = requireUsableCategory(db, toCategoryId);
  const rows = db
    .prepare(`SELECT ${COLUMNS} FROM expenses e WHERE e.category_id = ? AND e.deleted_at IS NULL`)
    .all(fromCategoryId) as unknown as ExpenseRow[];

  if (rows.length === 0) return 0;

  const timestamp = nowIso();

  inTransaction(db, () => {
    for (const row of rows) {
      const next: ExpenseRow = {
        ...row,
        category_id: target.id,
        updated_at: timestamp,
        rev: row.rev + 1,
      };

      db.prepare('UPDATE expenses SET category_id = ?, updated_at = ?, rev = ? WHERE id = ?').run(
        target.id,
        timestamp,
        next.rev,
        row.id,
      );

      recordChange(db, {
        entityType: 'expense',
        entityId: row.id,
        op: 'upsert',
        actorId,
        payload: toSyncExpense(next),
        deviceId: row.device_id,
      });
    }
  });

  return rows.length;
}
