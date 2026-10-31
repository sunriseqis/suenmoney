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
import { randomBytes } from 'node:crypto';
import { mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { DatabaseSync, SQLInputValue } from 'node:sqlite';

import { config } from '../../config.ts';
import { badRequest, conflict } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange, type EntityType } from '../sync.ts';
import { createUserWithId } from './users.ts';

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
  'id', 'username', 'display_name', 'password_hash', 'role',
  'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id',
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
  // 成员**含 password_hash**：JSON 备份 = 整个数据库（含账号与口令），
  // 导入即覆盖 —— 恢复出来的机器能直接用原来的口令登录。
  //
  // 代价必须说清：这个文件等同于「整库 + 登录凭据」。所以
  //   · 本地导出/导入只在管理员手里流转；
  //   · 推到 WebDAV 时必须先口令加密（见 lib/backup-crypto.ts，产物后缀 .mn）。
  // 明文 JSON 不进任何远端存储。
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

/**
 * 最小 CSV 解析：支持双引号包裹、引号内逗号/换行、`""` 转义。
 *
 * 不引第三方库：只服务本系统自己导出的表 + 常见的 Excel 另存为 CSV，
 * 这两种格式用不到 RFC4180 以外的扩展（分隔符变体、注释行等）。
 */
function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i]!;
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { cell += '"'; i += 1; }
        else inQuotes = false;
      } else {
        cell += ch;
      }
      continue;
    }
    if (ch === '"') { inQuotes = true; continue; }
    if (ch === ',') { row.push(cell); cell = ''; continue; }
    if (ch === '\r') continue;
    if (ch === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; continue; }
    cell += ch;
  }
  if (cell !== '' || row.length > 0) { row.push(cell); rows.push(row); }

  return rows.filter((r) => r.some((c) => c.trim() !== ''));
}

function csvLine(cells: readonly unknown[]): string {
  return cells.map(csvCell).join(',');
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
  /** 备份里的账号被覆盖写入的数量（**含口令**） */
  membersRestored: number;
  /** 本地有、备份里没有的账号：恢复后被软删除 */
  membersRemoved: Array<{ id: string; username: string; displayName: string }>;
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
/**
 * 导入导出包时，把所有成员引用改成**当前操作者**（「谁导入就归谁」）。
 *
 * 导出包不含「原机器的成员」这层语义 —— 它只是某个期间的流水。
 * 如果这里也要求目标库认识那些 ULID，用户就永远没法把 A 机器导出的账
 * 导进 B 机器的自己名下。
 *
 * `confirmed_by` 清空而不是指向操作者：它是「谁确认入账」的历史事实，
 * 换个账号导入后不该被冒认成自己确认的。
 */
function remapMembersToActor(pkg: ExportPackage, actorId: string): void {
  for (const row of pkg.data.plans) {
    if (typeof row['owner_id'] === 'string') row['owner_id'] = actorId;
  }
  for (const row of pkg.data.expenses) {
    if (typeof row['owner_id'] === 'string') row['owner_id'] = actorId;
  }
  for (const row of pkg.data.planTodos) {
    // ⚠ 不能清成空串：`confirmed_by TEXT REFERENCES users(id)` 是**外键**，
    //   空串不是 NULL，会被当成一个 user id 去查，直接 FOREIGN KEY 失败。
    //   而且 DDL 里还有 `CHECK (status <> 'confirmed' OR confirmed_by IS NOT NULL)`，
    //   清空会让已确认的期次连 CHECK 都过不去。
    //   语义上也该指向导入者 —— 「谁导入就归谁」。
    if (typeof row['confirmed_by'] === 'string' && row['confirmed_by'] !== '') {
      row['confirmed_by'] = actorId;
    }
  }
}

/** 恢复备份后的成员变化（供响应里回给管理员） */
export interface MemberRestoreResult {
  /** 备份里的账号被写入（覆盖）的数量，**含口令** */
  restored: number;
  /** 本地有、但备份里没有的账号：软删除（净效果 = 只剩备份里的账号） */
  removed: Array<{ id: string; username: string; displayName: string }>;
}

/**
 * 恢复备份时的成员处理：**整库覆盖**。
 *
 * JSON 备份 = 整个数据库（含 `password_hash`），所以恢复出来的机器
 * 用**原来的口令**就能登录 —— 这是「换机器 / 重装 / 换 NAS」最省事的路径。
 *
 * 具体做法：
 *   1. 备份里的账号按 id 写入（`ON CONFLICT DO UPDATE`），**password_hash 一起覆盖**；
 *   2. 本地有、备份里没有的账号 → **软删除**（`deleted_at` 置当前时间，不再能登录，
 *      但它作为外键目标的行还在，`plan_todos.confirmed_by` 等引用不会断）。
 *
 * 为什么软删而不是物理删：`users` 被 `sessions` / `plans.owner_id` /
 * `plan_todos.confirmed_by` 外键引用，物理删要在事务里 `PRAGMA defer_foreign_keys`
 * 并级联清会话，一个环节出错就是半截状态。软删达到同样的净效果，风险小得多。
 */
function restoreUsers(db: DatabaseSync, pkg: ExportPackage): MemberRestoreResult {
  const backupIds = new Set(pkg.data.members.map((m) => String(m['id'] ?? '')).filter((x) => x !== ''));
  const now = new Date().toISOString();

  let restored = 0;
  for (const row of pkg.data.members) {
    const id = String(row['id'] ?? '');
    if (id === '') continue;
    const username = String(row['username'] ?? '').trim().toLowerCase();
    if (username === '') continue;

    db.prepare(
      `INSERT INTO users (id, username, display_name, password_hash, role,
                          created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         username      = excluded.username,
         display_name  = excluded.display_name,
         password_hash = excluded.password_hash,
         role          = excluded.role,
         updated_at    = excluded.updated_at,
         deleted_at    = excluded.deleted_at,
         rev           = users.rev + 1,
         device_id     = excluded.device_id`,
    ).run(
      id,
      username,
      String(row['display_name'] ?? username),
      String(row['password_hash'] ?? ''),
      String(row['role'] ?? 'member') === 'admin' ? 'admin' : 'member',
      String(row['created_at'] ?? now),
      String(row['updated_at'] ?? now),
      row['deleted_at'] === null || row['deleted_at'] === undefined ? null : String(row['deleted_at']),
      Number(row['rev'] ?? 1),
      row['device_id'] === undefined ? null : (row['device_id'] as string | null),
    );
    restored += 1;
  }

  // 备份里没有的本地账号 → 软删除
  const locals = db
    .prepare('SELECT id, username, display_name FROM users WHERE deleted_at IS NULL')
    .all() as Array<Record<string, unknown>>;
  const removed: Array<{ id: string; username: string; displayName: string }> = [];
  for (const u of locals) {
    const id = String(u['id']);
    if (backupIds.has(id)) continue;
    db.prepare('UPDATE users SET deleted_at = ?, updated_at = ?, rev = rev + 1 WHERE id = ?')
      .run(now, now, id);
    removed.push({ id, username: String(u['username']), displayName: String(u['display_name']) });
  }

  return { restored, removed };
}

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

  try {
    db.prepare(
      `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})
       ON CONFLICT(id) DO UPDATE SET ${assignments}`,
    ).run(...values);
  } catch (err) {
    /**
     * 外键失败在 SQLite 里只给一句 `FOREIGN KEY constraint failed`，
     * 既不说哪张表、也不说缺什么 —— 用户看到的只有「服务器内部错误」。
     * 这里补上「哪张表、哪一行」，才能查得下去。
     */
    const message = err instanceof Error ? err.message : String(err);
    if (/constraint failed|FOREIGN KEY|NOT NULL|CHECK/i.test(message)) {
      const refs = columns
        .filter((c) => c.endsWith('_id') && c !== 'id')
        .map((c) => `${c}=${String(row[c] ?? '')}`)
        .join(', ');
      throw badRequest(
        `导入 ${table} 的记录 ${id} 失败：${message}。`
          + `（引用字段：${refs}）`,
      );
    }
    throw err;
  }

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

  /**
   * 成员处理：JSON 备份 = 整个数据库，导入即**整库覆盖**。
   * 备份里的账号连同 `password_hash` 一起写回；本地多出来的账号软删除。
   * 见 `restoreUsers`。
   */
  let memberRestore: MemberRestoreResult = { restored: 0, removed: [] };

  if (overwrite) {
    // 恢复备份 = 整库覆盖（含账号与口令），见 restoreUsers
    memberRestore = restoreUsers(db, pkg);
  }

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
    membersRestored: memberRestore.restored,
    membersRemoved: memberRestore.removed,
  };
}

// ---------------------------------------------------------------------------
// 流水 CSV（用户级）
// ---------------------------------------------------------------------------

/** 导出与导入共用这一份列名 —— 两套列名会导致「自己导出的文件自己认不出来」。 */
const CSV_HEADER = [
  '消费日期', '入账日期', '还款日', '金额', '一级分类', '二级分类',
  '支付方式', '记录人', '备注', '来源', '计划', '期次',
] as const;

/**
 * 导出流水 CSV。
 *
 * `ownerId` 非空 → 只导这个人的（非管理员走这条：a 只能导出 a 的）。
 * 传 `null` = 全部（仅管理员）。
 */
export function buildExpensesCsv(db: DatabaseSync, ownerId: string | null): string {
  const base = `SELECT e.*, p.name AS pay_name, u.display_name AS owner_name, pl.name AS plan_name
                FROM expenses e
                LEFT JOIN payment_methods p ON p.id = e.payment_method_id
                LEFT JOIN users u ON u.id = e.owner_id
                LEFT JOIN plans pl ON pl.id = e.plan_id
                WHERE e.deleted_at IS NULL`;
  // 按还款日排序 —— 与报表、流水页一致；不排的话同一份数据导两次行序可能不同
  const order = ' ORDER BY e.repayment_date ASC, e.id ASC';
  const rows = (ownerId === null
    ? db.prepare(base + order).all()
    : db.prepare(`${base} AND e.owner_id = ?${order}`).all(ownerId)) as Array<Record<string, unknown>>;

  const catById = new Map<string, Record<string, unknown>>();
  for (const c of db.prepare('SELECT id, name, parent_id FROM categories').all() as Array<Record<string, unknown>>) {
    catById.set(String(c['id']), c);
  }

  const lines = [csvLine([...CSV_HEADER])];
  for (const r of rows) {
    const cat = catById.get(String(r['category_id']));
    const parent = cat?.['parent_id'] !== null && cat?.['parent_id'] !== undefined
      ? catById.get(String(cat['parent_id']))
      : undefined;
    lines.push(csvLine([
      String(r['spend_date'] ?? ''),
      String(r['posting_date'] ?? ''),
      String(r['repayment_date'] ?? ''),
      (Number(r['amount_cents'] ?? 0) / 100).toFixed(2),
      parent !== undefined ? String(parent['name']) : String(cat?.['name'] ?? ''),
      parent !== undefined ? String(cat?.['name'] ?? '') : '',
      String(r['pay_name'] ?? ''),
      String(r['owner_name'] ?? ''),
      String(r['note'] ?? ''),
      r['source'] === 'plan' ? '计划生成' : '手动记录',
      String(r['plan_name'] ?? ''),
      r['plan_period_seq'] === null || r['plan_period_seq'] === undefined ? '' : String(r['plan_period_seq']),
    ]));
  }

  // \r\n + BOM：Excel 认这两个。只给 \n 的话老版本 Excel 会把整张表读成一行。
  return `\uFEFF${lines.join('\r\n')}\r\n`;
}

export interface CsvImportReport {
  created: number;
  skipped: number;
  /** 跳过原因（最多 5 条明细，便于界面提示） */
  problems: Array<{ line: number; reason: string }>;
}

/**
 * 导入流水 CSV —— **不看归属，谁导入就归谁**。
 *
 * 分类/支付方式按**名字**匹配已有数据；匹配不到就跳过该行并报告原因，
 * 而不是自动建分类（那会顺着一个拼错的名字长出一堆垃圾分类）。
 * 计划相关列忽略：CSV 是流水快照，不重建分期关系。
 */
export function importExpensesCsv(
  db: DatabaseSync,
  csvText: string,
  actorId: string,
  ownerId: string,
): CsvImportReport {
  const records = parseCsv(csvText.replace(/^\uFEFF/, ''));
  const report: CsvImportReport = { created: 0, skipped: 0, problems: [] };
  if (records.length === 0) return report;

  const header = records[0]!.map((h) => h.trim());
  const idx = (name: string): number => header.indexOf(name);
  const iDate = idx('消费日期');
  const iPost = idx('入账日期');
  const iRepay = idx('还款日');
  const iAmount = idx('金额');
  const iCat1 = idx('一级分类');
  const iCat2 = idx('二级分类');
  const iPay = idx('支付方式');
  const iNote = idx('备注');

  if (iDate < 0 || iAmount < 0) {
    return { created: 0, skipped: 0, problems: [{ line: 1, reason: '缺少必需列：消费日期 / 金额' }] };
  }

  const payByName = new Map<string, string>();
  for (const p of db.prepare('SELECT id, name FROM payment_methods WHERE deleted_at IS NULL').all() as Array<Record<string, unknown>>) {
    payByName.set(String(p['name']).trim(), String(p['id']));
  }

  const catRows = db.prepare('SELECT id, name, parent_id FROM categories WHERE deleted_at IS NULL').all() as Array<Record<string, unknown>>;
  const catById = new Map<string, Record<string, unknown>>();
  for (const c of catRows) catById.set(String(c['id']), c);
  const catByName = new Map<string, string>();
  for (const c of catRows) {
    const parentId = c['parent_id'];
    if (parentId === null || parentId === undefined) {
      catByName.set(String(c['name']).trim(), String(c['id']));
    } else {
      const parent = catById.get(String(parentId));
      catByName.set(String(c['name']).trim(), String(c['id']));
      catByName.set(`${String(parent?.['name'] ?? '')} / ${String(c['name']).trim()}`, String(c['id']));
    }
  }

  const now = new Date().toISOString();
  const insert = db.prepare(
    `INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                           spend_date, posting_date, repayment_date, note, source,
                           plan_id, plan_period_seq, created_at, updated_at, deleted_at, rev, device_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', NULL, NULL, ?, ?, NULL, 1, NULL)`,
  );

  for (let i = 1; i < records.length; i++) {
    const cells = records[i]!;
    const line = i + 1;
    const spendDate = (cells[iDate] ?? '').trim();
    const amountRaw = (cells[iAmount] ?? '').trim().replace(/,/g, '');
    const cents = Math.round(Number(amountRaw) * 100);

    if (!/^\d{4}-\d{2}-\d{2}$/.test(spendDate)) {
      report.skipped += 1;
      if (report.problems.length < 5) report.problems.push({ line, reason: `消费日期不是 YYYY-MM-DD：'${spendDate}'` });
      continue;
    }
    if (!Number.isFinite(cents) || cents === 0) {
      report.skipped += 1;
      if (report.problems.length < 5) report.problems.push({ line, reason: `金额无法识别：'${amountRaw}'` });
      continue;
    }

    const leaf = iCat2 >= 0 ? (cells[iCat2] ?? '').trim() : '';
    const root = iCat1 >= 0 ? (cells[iCat1] ?? '').trim() : '';
    const categoryId = (leaf !== '' ? catByName.get(`${root} / ${leaf}`) : undefined)
      ?? (leaf !== '' ? catByName.get(leaf) : undefined)
      ?? (root !== '' ? catByName.get(root) : undefined);

    const payName = iPay >= 0 ? (cells[iPay] ?? '').trim() : '';
    const paymentId = payByName.get(payName);

    if (categoryId === undefined) {
      report.skipped += 1;
      if (report.problems.length < 5) report.problems.push({ line, reason: `分类不存在：'${root}${leaf ? ' / ' + leaf : ''}'` });
      continue;
    }
    if (paymentId === undefined) {
      report.skipped += 1;
      if (report.problems.length < 5) report.problems.push({ line, reason: `支付方式不存在：'${payName}'` });
      continue;
    }

    const postingDate = iPost >= 0 && /^\d{4}-\d{2}-\d{2}$/.test((cells[iPost] ?? '').trim())
      ? String(cells[iPost]).trim() : spendDate;
    const repaymentDate = iRepay >= 0 && /^\d{4}-\d{2}-\d{2}$/.test((cells[iRepay] ?? '').trim())
      ? String(cells[iRepay]).trim() : postingDate;

    insert.run(
      ulid(), ownerId, cents, categoryId, paymentId,
      spendDate, postingDate, repaymentDate,
      iNote >= 0 ? String(cells[iNote] ?? '') : '',
      now, now,
    );
    report.created += 1;
  }

  return report;
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

/**
 * 写一份「恢复前」存档，返回文件路径。
 *
 * 写入失败时**不中断恢复**，而是退到私有目录再试一次；仍然失败就返回 `null`
 * 并由调用方把警告带给用户。
 *
 * 为什么不让它抛：快照是**安全网**，不是恢复的前提条件。飞牛套件里
 * `SUENMONEY_BACKUP_DIR` 可能指向数据共享目录，而该目录对套件进程未必可写（
 * 权限/只读卷/路径不存在）。让「安全网写不进去」直接变成「恢复做不了」，
 * 等于把可恢复的场景变成不可恢复 —— 顺序反了。
 *
 * 但也不能静默：`null` 会被冒泡到响应里，界面必须明确告诉用户
 * 「这次没留下恢复前存档」。
 */
export function writePreRestoreSnapshot(db: DatabaseSync): string | null {
  const pkg = buildPackage(db, { kind: 'all', period: '' }, 'suenmoney-backup');

  // 文件名里的冒号在部分文件系统上不合法，用短横线
  const stamp = pkg.generatedAt.replace(/[:.]/g, '-');
  const name = `pre-restore-${stamp}.json`;

  const candidates = [preRestoreDir(), join(config.dbPath, '..', 'backups', 'pre-restore')];

  for (const dir of candidates) {
    try {
      mkdirSync(dir, { recursive: true });
      const path = join(dir, name);
      writeFileSync(path, JSON.stringify(pkg, null, 2), 'utf8');
      pruneSnapshotsAt(dir);
      return path;
    } catch {
      // 下一个候选
    }
  }

  return null;
}

/** 只留最近 `backupKeep` 份，按文件名（= 时间戳）排序。 */
function pruneSnapshotsAt(dir: string): void {
  let files: string[];
  try {
    files = readdirSync(dir);
  } catch {
    return;
  }
  files = files
    .filter((name) => name.startsWith('pre-restore-') && name.endsWith('.json'))
    .sort((a, b) => a.localeCompare(b, 'en'));

  for (const name of files.slice(0, Math.max(0, files.length - config.backupKeep))) {
    rmSync(join(dir, name), { force: true });
  }
}
