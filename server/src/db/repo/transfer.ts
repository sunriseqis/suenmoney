/**
 * 数据的导出 / 导入 / 备份 / 恢复。
 *
 * ## 为什么单独一个文件
 *
 * 它横跨所有聚合（成员 / 分类 / 支付方式 / 计划 / 待办 / 支出），
 * 塞进任何一个现有 repo 都会得到「分类 repo 里躺着计划表的 SQL」。
 *
 * ## 四条铁律（改这个文件之前先读）
 *
 * 1. **写入必须走 `db/sync.ts`**：每次写入都要 `recordChange` 落 `changes`
 *    + 递增 `rev`。直接灌表在功能上「看起来能用」，但其他设备永远同步不到，
 *    而且**不报错** —— 正是 `decisions.md`「写入只有一个入口」那条的由来。
 * 2. **成员（users）永远不导入**。导出里带成员是为了把「记录人」这个名字还原出来，
 *    导入不会新建账号：那会造出一批**没有可用口令**的僵尸账号。缺失的成员
 *    一律 409 并列出名字，让用户先去「家庭与账号」把人建好 —— 见 `requireMembers`。
 * 3. **导入 = 只补缺，恢复 = 文件覆盖本地**。这两个不是同一个函数的两个参数：
 *    导入可重复执行且绝不动现有数据，恢复则让文件说了算。恢复必须先自动存档。
 * 4. **恢复不做删除**。它只把备份里的东西写回去；本地多出来的记录保留。
 *    「删掉本地有、备份里没有的记录」比「写回旧数据」危险得多，
 *    不该藏在一个叫「恢复」的按钮后面。
 */
import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DatabaseSync, SQLInputValue } from 'node:sqlite';

import { config } from '../../config.ts';
import { badRequest, conflict } from '../../lib/http-error.ts';
import { inTransaction, recordChange, type EntityType } from '../sync.ts';

// ---------------------------------------------------------------------------
// 列清单
// ---------------------------------------------------------------------------

/**
 * 每张表参与导出的列，**显式列出而不是 `SELECT *`**。
 *
 * 两个理由：`SELECT *` 会把以后新增的内部列（比如某个调试用的标记）自动泄漏进
 * 导出文件；而显式清单让「导出格式变了」这件事在 diff 里看得见。
 */
const MEMBER_COLUMNS = [
  'id', 'username', 'display_name', 'role', 'created_at', 'updated_at',
  'deleted_at', 'rev', 'device_id',
] as const;

const CATEGORY_COLUMNS = [
  'id', 'parent_id', 'name', 'depth', 'icon', 'color', 'sort_order', 'is_enabled',
  'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id',
] as const;

const PAYMENT_COLUMNS = [
  'id', 'name', 'type', 'billing_day', 'repayment_day', 'is_enabled', 'sort_order',
  'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id',
] as const;

const PLAN_COLUMNS = [
  'id', 'owner_id', 'name', 'category_id', 'payment_method_id', 'amount_cents',
  'total_amount_cents', 'purchase_date', 'first_due_date', 'remind_days_before',
  'auto_post', 'source', 'state', 'note', 'created_at', 'updated_at', 'deleted_at',
  'rev', 'device_id',
] as const;

const TODO_COLUMNS = [
  'id', 'plan_id', 'period_seq', 'amount_cents', 'posting_date', 'repayment_date',
  'remind_date', 'status', 'posted_date', 'confirmed_by', 'confirmed_at', 'expense_id',
  'hold_auto_post', 'ack_at', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id',
] as const;

const EXPENSE_COLUMNS = [
  'id', 'owner_id', 'amount_cents', 'category_id', 'payment_method_id', 'spend_date',
  'posting_date', 'repayment_date', 'note', 'source', 'plan_id', 'plan_period_seq',
  'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id',
] as const;

/** 表名 → 列清单 + changes 里的 entity_type。写入路径靠这张表驱动。 */
const TABLES = {
  categories: { entity: 'category', columns: CATEGORY_COLUMNS },
  payment_methods: { entity: 'payment_method', columns: PAYMENT_COLUMNS },
  plans: { entity: 'plan', columns: PLAN_COLUMNS },
  plan_todos: { entity: 'plan_todo', columns: TODO_COLUMNS },
  expenses: { entity: 'expense', columns: EXPENSE_COLUMNS },
} as const satisfies Record<string, { entity: EntityType; columns: readonly string[] }>;

type TableName = keyof typeof TABLES;

// ---------------------------------------------------------------------------
// 信封
// ---------------------------------------------------------------------------

/** `suenmoney-export` = 可按范围导出，导入只补缺；`suenmoney-backup` = 始终全量，可覆盖恢复。 */
export type PackageFormat = 'suenmoney-export' | 'suenmoney-backup';

export const PACKAGE_VERSION = 1;

export type ScopeKind = 'all' | 'year' | 'month';

export interface ExportScope {
  kind: ScopeKind;
  /** `year` 时为 `YYYY`，`month` 时为 `YYYY-MM`，`all` 时为空串 */
  period: string;
}

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

export type Row = Record<string, unknown>;

export interface PackageData {
  members: Row[];
  categories: Row[];
  paymentMethods: Row[];
  plans: Row[];
  planTodos: Row[];
  expenses: Row[];
}

export interface ExportPackage {
  format: PackageFormat;
  version: number;
  generatedAt: string;
  scope: ExportScope;
  counts: PackageCounts;
  data: PackageData;
}

// ---------------------------------------------------------------------------
// 范围
// ---------------------------------------------------------------------------

/**
 * 解析并校验导出范围。
 *
 * 期间一律是**前缀匹配 `repayment_date`**（`'YYYY-MM'` / `'YYYY'`），
 * 与 `reports.ts` 的聚合口径同源。**不能改用消费日 `spend_date` 去筛** ——
 * 那样「9 月导出的合计」与「9 月报表的合计」会不相等，
 * 而这种不一致看起来像丢数据，排查方向会完全跑偏。
 */
export function parseScope(kindRaw: unknown, periodRaw: unknown): ExportScope {
  const kind = kindRaw === undefined || kindRaw === '' ? 'all' : String(kindRaw);
  if (kind !== 'all' && kind !== 'year' && kind !== 'month') {
    throw badRequest('scope 只能是 all / year / month');
  }

  if (kind === 'all') {
    // 给了 period 就明说它被忽略了，而不是静默丢掉 —— 静默会让调用方以为筛选生效了
    if (periodRaw !== undefined && String(periodRaw).trim() !== '') {
      throw badRequest('scope=all 不接受 period');
    }
    return { kind, period: '' };
  }

  const period = String(periodRaw ?? '').trim();
  const pattern = kind === 'year' ? /^\d{4}$/ : /^\d{4}-(0[1-9]|1[0-2])$/;
  if (!pattern.test(period)) {
    throw badRequest(
      kind === 'year' ? 'scope=year 需要 period=YYYY' : 'scope=month 需要 period=YYYY-MM',
    );
  }

  return { kind, period };
}

/** 期间的文件名片段，`all` 时返回 `all`。 */
function scopeSlug(scope: ExportScope): string {
  return scope.kind === 'all' ? 'all' : scope.period;
}

/** 建议的文件名。带上导出日期，方便同时留几份不互相覆盖。 */
export function packageFileName(pkg: ExportPackage, extension: string): string {
  const stamp = pkg.generatedAt.slice(0, 10).replace(/-/g, '');
  return `suenmoney-${pkg.format === 'suenmoney-backup' ? 'backup' : 'export'}-${scopeSlug(pkg.scope)}-${stamp}.${extension}`;
}

// ---------------------------------------------------------------------------
// 导出
// ---------------------------------------------------------------------------

function selectRows(
  db: DatabaseSync,
  sql: string,
  params: readonly SQLInputValue[] = [],
): Row[] {
  return db.prepare(sql).all(...params) as unknown as Row[];
}

function allRows(db: DatabaseSync, table: TableName): Row[] {
  return selectRows(db, `SELECT ${TABLES[table].columns.join(', ')} FROM ${table}`);
}

function rowsByIds(db: DatabaseSync, table: TableName, ids: readonly string[]): Row[] {
  if (ids.length === 0) return [];
  const placeholders = ids.map(() => '?').join(', ');
  return selectRows(
    db,
    `SELECT ${TABLES[table].columns.join(', ')} FROM ${table} WHERE id IN (${placeholders})`,
    ids,
  );
}

/**
 * 打一个自包含的数据包。
 *
 * **软删的行也带上**（墓碑）。导出文件是一份快照，「这行长什么样」与
 * 「它已经被删了」都是快照的一部分：少了墓碑，另一台设备在恢复之后
 * 仍然以为那条记录活着，而它不会因为「没出现在备份里」而被纠正。
 *
 * 期间范围下，计划**整条带出、不裁剪**：一条计划只要有任何期次落在期间内，
 * 就把它的全部期次一起带上。否则 12 期房贷按年导出会只剩「12 期里的 5 期」，
 * 导入后「已还 N 期 / 剩余 / 预计结清」全部错位 —— 计划的进度是相对于
 * 计划整体算的，不是相对于某一年。
 */
export function buildPackage(
  db: DatabaseSync,
  scope: ExportScope,
  format: PackageFormat,
): ExportPackage {
  const inRange = scope.kind !== 'all';
  const prefix = inRange ? scope.period : '';

  // 成员 / 分类 / 支付方式没有时间维度，一律全量 —— 这样任意一份导出
  // 都能单独解释它自己引用的每一个 id。
  //
  // 成员**不含 password_hash**：导出文件是会被随手存进网盘的东西，
  // 口令哈希不该跟着走。代价见 `requireMembers` —— 导入不建账号。
  const memberRows = selectRows(db, `SELECT ${MEMBER_COLUMNS.join(', ')} FROM users`);
  const categories = allRows(db, 'categories');
  const paymentMethods = allRows(db, 'payment_methods');

  // 期间内的计划（整条）与全部期次
  const planIds = inRange
    ? selectRows(
        db,
        `SELECT DISTINCT plan_id AS id FROM plan_todos WHERE repayment_date LIKE ? || '%'`,
        [prefix],
      ).map((row) => String(row['id']))
    : null;

  const plans = planIds === null ? allRows(db, 'plans') : rowsByIds(db, 'plans', planIds);

  /**
   * 期次：期间范围时**不做任何裁剪**。
   *
   * 这里刻意不按 `repayment_date` 再筛一遍 —— 「计划整条带出」的意思就是
   * 全部期次，只筛掉期间外的期次会让进度错位（同上面那段论证）。
   */
  const planTodos =
    planIds === null
      ? allRows(db, 'plan_todos')
      : planIds.length === 0
        ? []
        : selectRows(
            db,
            `SELECT ${TODO_COLUMNS.join(', ')} FROM plan_todos WHERE plan_id IN (${planIds
              .map(() => '?')
              .join(', ')})`,
            planIds,
          );

  // 期间内的支出
  const expenses = inRange
    ? selectRows(
        db,
        `SELECT ${EXPENSE_COLUMNS.join(', ')} FROM expenses WHERE repayment_date LIKE ? || '%'`,
        [prefix],
      )
    : allRows(db, 'expenses');

  /**
   * 已入账、但支出落在期间外的期次，那笔支出也要带上（标 `context: true`）。
   *
   * 不带就会出现「期次显示已入账，但找不到对应账目」—— 而 `plan_todos.expense_id`
   * 是指向 `expenses(id)` 的**立即检查**外键，导入时会直接撞
   * `FOREIGN KEY constraint failed`，报出一句和「少了条支出」毫无关系的错。
   */
  const included = new Set(expenses.map((row) => String(row['id'])));
  const referenced = [
    ...new Set(
      planTodos
        .map((row) => row['expense_id'])
        .filter((id): id is string => typeof id === 'string' && id !== ''),
    ),
  ].filter((id) => !included.has(id));

  const contextExpenses = rowsByIds(db, 'expenses', referenced).map((row) => ({
    ...row,
    /** 不是因为它落在期间内才被带出的，而是因为它是一条被带出的期次的账目 */
    context: true,
  }));

  const data: PackageData = {
    members: memberRows,
    categories,
    paymentMethods,
    plans,
    planTodos,
    expenses: [...expenses, ...contextExpenses],
  };

  return {
    format,
    version: PACKAGE_VERSION,
    generatedAt: new Date().toISOString(),
    scope,
    counts: {
      members: data.members.length,
      categories: data.categories.length,
      paymentMethods: data.paymentMethods.length,
      plans: data.plans.length,
      planTodos: data.planTodos.length,
      expenses: data.expenses.length,
      contextExpenses: contextExpenses.length,
    },
    data,
  };
}

// ---------------------------------------------------------------------------
// CSV（对账用）
// ---------------------------------------------------------------------------

/**
 * CSV 单元格转义。
 *
 * - 含 `,` `"` 换行的一律加引号并把内部的 `"` 翻倍
 * - **以 `= + - @` 开头的值前面补一个单引号**：备注是可以随意输入的，
 *   而 Excel 会把 `=1+1` 当公式执行。导出文件是给人打开的，
 *   这一条防的是「别人给我发了个账本，我打开就被执行了」。
 */
function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  const guarded = /^[=+\-@]/.test(text) ? `'${text}` : text;
  return /[",\r\n]/.test(guarded) ? `"${guarded.replace(/"/g, '""')}"` : guarded;
}

function csvLine(cells: readonly unknown[]): string {
  return cells.map(csvCell).join(',');
}

const CSV_HEADER = [
  '消费日', '入账日', '还款日', '金额', '分类', '二级分类',
  '支付方式', '记录人', '备注', '来源', '计划', '期次',
] as const;

/**
 * 把数据包摊平成一张对账表。
 *
 * 只导出**未删除**的支出：这张表是拿去和报表核对的，而报表的合计不含墓碑。
 * 带上墓碑会让人对不上账，且看起来像「报表多算了/少算了」。
 *
 * 金额用元、保留两位小数 —— 分是内部存储单位，给人看的表里不该出现。
 */
export function toExpenseCsv(pkg: ExportPackage): string {
  const live = pkg.data.expenses.filter((row) => row['deleted_at'] === null);

  const categoryById = new Map(pkg.data.categories.map((row) => [String(row['id']), row]));
  const paymentById = new Map(pkg.data.paymentMethods.map((row) => [String(row['id']), row]));
  const memberById = new Map(pkg.data.members.map((row) => [String(row['id']), row]));
  const planById = new Map(pkg.data.plans.map((row) => [String(row['id']), row]));

  const lines = [csvLine(CSV_HEADER)];

  /**
   * 按还款日排序 —— 与报表、流水页的顺序一致。
   * 不排的话行序就是数据库的返回顺序，同一份数据导两次可能不一样，
   * 用户会以为「怎么跟上次不一样，是不是漏了」。
   */
  const sorted = [...live].sort((a, b) => {
    const left = String(a['repayment_date']);
    const right = String(b['repayment_date']);
    return left === right ? String(a['id']).localeCompare(String(b['id'])) : left.localeCompare(right);
  });

  for (const row of sorted) {
    const category = categoryById.get(String(row['category_id']));
    const parent =
      category !== undefined && category['parent_id'] !== null
        ? categoryById.get(String(category['parent_id']))
        : undefined;

    lines.push(
      csvLine([
        row['spend_date'],
        row['posting_date'],
        row['repayment_date'],
        (Number(row['amount_cents']) / 100).toFixed(2),
        parent !== undefined ? parent['name'] : (category?.['name'] ?? ''),
        parent !== undefined ? category?.['name'] : '',
        paymentById.get(String(row['payment_method_id']))?.['name'] ?? '',
        memberById.get(String(row['owner_id']))?.['display_name'] ?? '',
        row['note'],
        row['source'] === 'plan' ? '计划生成' : '手动记录',
        row['plan_id'] === null ? '' : (planById.get(String(row['plan_id']))?.['name'] ?? ''),
        row['plan_period_seq'] ?? '',
      ]),
    );
  }

  // \r\n + BOM：Excel 认这两个。只给 \n 的话老版本 Excel 会把整张表读成一行。
  return `\uFEFF${lines.join('\r\n')}\r\n`;
}

// ---------------------------------------------------------------------------
// 校验
// ---------------------------------------------------------------------------

function isRowArray(value: unknown): value is Row[] {
  return Array.isArray(value) && value.every((item) => item !== null && typeof item === 'object');
}

/**
 * 校验一个上传的包。
 *
 * 逐项检查而不是「用到了再说」：导入是**覆盖性**的写操作，
 * 一个结构不对的文件应当在写下第一行之前就被拒掉，
 * 而不是写到一半炸在某个 `undefined` 上 —— 那时已经改了一部分数据，
 * 而事务外的错误处理只能告诉你「失败了」，说不清改到哪儿了。
 */
export function validatePackage(value: unknown): ExportPackage {
  if (value === null || typeof value !== 'object') {
    throw badRequest('不是有效的 JSON 对象');
  }

  const pkg = value as Partial<ExportPackage>;

  if (pkg.format !== 'suenmoney-export' && pkg.format !== 'suenmoney-backup') {
    throw badRequest('不是 SuenMoney 的数据包（format 字段不匹配）');
  }
  if (pkg.version !== PACKAGE_VERSION) {
    throw badRequest(`数据包版本不支持：${String(pkg.version)}（本服务端支持 ${PACKAGE_VERSION}）`);
  }
  if (pkg.scope === null || typeof pkg.scope !== 'object') {
    throw badRequest('数据包缺少 scope');
  }
  if (pkg.data === null || typeof pkg.data !== 'object') {
    throw badRequest('数据包缺少 data');
  }

  const data = pkg.data as Partial<PackageData>;
  for (const key of ['members', 'categories', 'paymentMethods', 'plans', 'planTodos', 'expenses'] as const) {
    if (!isRowArray(data[key])) {
      throw badRequest(`数据包的 data.${key} 不是数组`);
    }
  }

  return {
    format: pkg.format,
    version: pkg.version,
    generatedAt: typeof pkg.generatedAt === 'string' ? pkg.generatedAt : new Date().toISOString(),
    scope: {
      kind: (pkg.scope as ExportScope).kind,
      period: String((pkg.scope as ExportScope).period ?? ''),
    },
    counts: pkg.counts ?? emptyCounts(),
    data: {
      members: data.members!,
      categories: data.categories!,
      paymentMethods: data.paymentMethods!,
      plans: data.plans!,
      planTodos: data.planTodos!,
      expenses: data.expenses!,
    },
  };
}

function emptyCounts(): PackageCounts {
  return {
    members: 0,
    categories: 0,
    paymentMethods: 0,
    plans: 0,
    planTodos: 0,
    expenses: 0,
    contextExpenses: 0,
  };
}

// ---------------------------------------------------------------------------
// 导入 / 恢复
// ---------------------------------------------------------------------------

export interface TableReport {
  created: number;
  skipped: number;
  overwritten: number;
}

export interface MergeReport {
  /** 写入模式：`merge` 只补缺，`restore` 文件覆盖本地 */
  mode: 'merge' | 'restore';
  byTable: Record<TableName, TableReport>;
  created: number;
  skipped: number;
  overwritten: number;
  /** 恢复前自动存档的快照路径（仅 restore） */
  snapshotPath: string | null;
}

interface MergeOptions {
  /** true = 文件覆盖本地（恢复）；false = 只补缺（导入） */
  overwrite: boolean;
  /** 写快照的函数，由 http 层注入 —— repo 层不直接碰文件系统路径策略 */
  snapshot?: (() => string | null) | undefined;
}

/**
 * 数据包引用的成员必须已经存在。
 *
 * 检查 `owner_id`（计划、支出）与 `confirmed_by`（待办）两个外键来源。
 * 少了这一步，导入会在第一条引用未知用户的记录上撞外键，
 * 报出一句 `FOREIGN KEY constraint failed` —— 完全看不出
 * 「你少建了一个家庭成员账号」。
 *
 * 按 id 查而不是按 username：id 是 ULID，改过用户名的人也认得出来。
 * **包含软删的成员**：历史记录必须继续引用那个已经不用的账号。
 */
function requireMembers(db: DatabaseSync, pkg: ExportPackage): void {
  const referenced = new Set<string>();

  for (const row of pkg.data.plans) {
    if (typeof row['owner_id'] === 'string') referenced.add(row['owner_id']);
  }
  for (const row of pkg.data.expenses) {
    if (typeof row['owner_id'] === 'string') referenced.add(row['owner_id']);
  }
  for (const row of pkg.data.planTodos) {
    if (typeof row['confirmed_by'] === 'string' && row['confirmed_by'] !== '') {
      referenced.add(row['confirmed_by']);
    }
  }

  const missing: string[] = [];
  for (const id of referenced) {
    const found = db.prepare('SELECT 1 AS x FROM users WHERE id = ?').get(id);
    if (found === undefined) {
      const inPackage = pkg.data.members.find((row) => String(row['id']) === id);
      const name = inPackage === undefined ? id : `${String(inPackage['display_name'])}（${id}）`;
      missing.push(name);
    }
  }

  if (missing.length > 0) {
    throw conflict(
      `数据包里引用了本系统里不存在的成员：${missing.join('、')}。`
        + '请先在「家庭与账号」里建好这些账号再导入 —— 导入不会替你创建账号'
        + '（否则会造出一批没有可用口令的账号）。',
    );
  }
}

function coerce(value: unknown): string | number | null {
  if (value === undefined || value === null) return null;
  if (typeof value === 'bigint') return Number(value);
  if (typeof value === 'number' || typeof value === 'string') return value;
  // 布尔（JSON 里常见）落库为 0/1 —— SQLite 没有布尔类型，其他 repo 也是这么存的
  if (typeof value === 'boolean') return value ? 1 : 0;
  throw badRequest(`字段值类型不支持：${typeof value}`);
}

/**
 * 写一行，并**通过 `db/sync.ts` 记录变更**。
 *
 * `INSERT ... ON CONFLICT(id) DO UPDATE` 一句话覆盖两种情形；
 * 之所以还要先 `SELECT 1`，是为了把「新建」与「覆盖」分开报告 ——
 * 用户需要知道这次导入到底改了多少东西，而不是只看到「成功」。
 */
function writeRow(
  db: DatabaseSync,
  table: TableName,
  row: Row,
  actorId: string,
  overwrite: boolean,
): 'created' | 'skipped' | 'overwritten' {
  const id = row['id'];
  if (typeof id !== 'string' || id === '') {
    throw badRequest(`${table} 里有一行缺少 id`);
  }

  const exists = db.prepare(`SELECT 1 AS x FROM ${table} WHERE id = ?`).get(id) !== undefined;
  if (exists && !overwrite) return 'skipped';

  const { entity, columns } = TABLES[table];
  const values = columns.map((column) => coerce(row[column]));

  const assignments = columns
    .filter((column) => column !== 'id')
    .map((column) => `${column} = excluded.${column}`)
    .join(', ');

  db.prepare(
    `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})
     ON CONFLICT(id) DO UPDATE SET ${assignments}`,
  ).run(...values);

  const snapshot: Record<string, unknown> = {};
  columns.forEach((column, index) => {
    snapshot[column] = values[index];
  });

  recordChange(db, {
    entityType: entity,
    entityId: id,
    op: snapshot['deleted_at'] === null ? 'upsert' : 'delete',
    actorId,
    payload: snapshot,
    deviceId: typeof snapshot['device_id'] === 'string' ? snapshot['device_id'] : null,
  });

  return exists ? 'overwritten' : 'created';
}

/**
 * 合并一个数据包。
 *
 * **顺序不能换**：外键是立即检查的。
 *   categories → payment_methods → plans → expenses → plan_todos
 * 支出必须早于待办：`plan_todos.expense_id` 指向 `expenses(id)`。
 * 计划必须早于支出：`expenses.plan_id` 指向 `plans(id)`。
 * 分类必须早于支出与计划：两者都有 `category_id`。
 */
export function mergePackage(
  db: DatabaseSync,
  pkg: ExportPackage,
  actorId: string,
  options: MergeOptions,
): MergeReport {
  const { overwrite } = options;

  const byTable: Record<TableName, TableReport> = {
    categories: { created: 0, skipped: 0, overwritten: 0 },
    payment_methods: { created: 0, skipped: 0, overwritten: 0 },
    plans: { created: 0, skipped: 0, overwritten: 0 },
    plan_todos: { created: 0, skipped: 0, overwritten: 0 },
    expenses: { created: 0, skipped: 0, overwritten: 0 },
  };

  requireMembers(db, pkg);

  let snapshotPath: string | null = null;

  inTransaction(db, () => {
    // 冒烟：先抓一份当前全量存档。恢复是覆盖性的，这一步是它的安全网 ——
    // 而且要**在事务里、在第一次写入之前**做，否则存档存的可能已经是半改过的状态。
    if (options.snapshot !== undefined) {
      snapshotPath = options.snapshot();
    }

    const write = (table: TableName, rows: readonly Row[]): void => {
      for (const row of rows) {
        const outcome = writeRow(db, table, row, actorId, overwrite);
        byTable[table][outcome] += 1;
      }
    };

    write('categories', pkg.data.categories);
    write('payment_methods', pkg.data.paymentMethods);
    write('plans', pkg.data.plans);
    write('expenses', pkg.data.expenses);
    write('plan_todos', pkg.data.planTodos);
  });

  const totals = Object.values(byTable).reduce(
    (acc, item) => ({
      created: acc.created + item.created,
      skipped: acc.skipped + item.skipped,
      overwritten: acc.overwritten + item.overwritten,
    }),
    { created: 0, skipped: 0, overwritten: 0 },
  );

  return {
    mode: overwrite ? 'restore' : 'merge',
    byTable,
    ...totals,
    snapshotPath,
  };
}

// ---------------------------------------------------------------------------
// 自动存档
// ---------------------------------------------------------------------------

/**
 * 「恢复前存档」落在哪个目录。
 *
 * 快照**落磁盘**，不塞进 `settings` 表：它是「万一恢复了不该恢复的东西」
 * 的那条救命稻草，必须能在**应用本身已经不能用**的时候取出来 ——
 * 一个 `data/backups/pre-restore/*.json` 用文本编辑器就能看，
 * 也能直接喂回恢复接口；塞进表里的话，只有能跑起来的应用才读得到它，
 * 而那正是它最可能帮不上忙的时候。
 *
 * 也不该同步进客户端：快照属于「服务端的存档」，不是家庭数据。
 *
 * 导出成函数而不是让调用方各自拼一遍路径：维护性动作（`maintenance.ts`
 * 的清空 / 重置）也要把同一句话告诉用户，两处各拼一次迟早会漂移 ——
 * 而漂移的表现是**用户照着界面上的路径去找，找不到救命的那份文件**。
 */
export function preRestoreDir(): string {
  return join(config.backupDir, 'pre-restore');
}

/** 写一份「恢复前」存档，返回文件路径。落在同一个事务里，失败即整体回滚。 */
export function writePreRestoreSnapshot(db: DatabaseSync): string {
  const pkg = buildPackage(db, { kind: 'all', period: '' }, 'suenmoney-backup');
  const dir = preRestoreDir();
  mkdirSync(dir, { recursive: true });

  // 文件名里的冒号在部分文件系统上不合法，用短横线
  const stamp = pkg.generatedAt.replace(/[:.]/g, '-');
  const path = join(dir, `pre-restore-${stamp}.json`);
  writeFileSync(path, JSON.stringify(pkg, null, 2), 'utf8');

  pruneSnapshots();
  return path;
}

/** 只留最近 `backupKeep` 份，按文件名（= 时间戳）排序。 */
function pruneSnapshots(): void {
  const dir = preRestoreDir();
  const files = readdirSync(dir)
    .filter((name) => name.startsWith('pre-restore-') && name.endsWith('.json'))
    .sort((a, b) => a.localeCompare(b, 'en'));

  for (const name of files.slice(0, Math.max(0, files.length - config.backupKeep))) {
    rmSync(join(dir, name), { force: true });
  }
}
