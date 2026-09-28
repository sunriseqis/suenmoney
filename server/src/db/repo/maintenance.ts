/**
 * 维护性动作：**清空账目**与**重置演示数据**。
 *
 * ## 为什么它们合在一个文件里
 *
 * 两个动作共享三件事，而且这三件事都**必须一样**，分开写迟早会漂移：
 *
 * 1. **先存档再做**。两份都是不可逆的，存档是唯一的回头路。
 * 2. **写入走 `db/sync.ts`**。清空是「软删 + 逐行 `recordChange`」，
 *    不是 `DELETE FROM` —— 后者其他设备永远同步不到，而且不报错。
 * 3. **配置不动**。分类 / 支付方式 / 账号没有时间维度，
 *    删掉它们会让系统当场不可用（记账时没有分类可选），
 *    而它们也不是「账目」。所以「清空」清的只是**账目**。
 *
 * ## 危险区的两个按钮，代价不对称
 *
 * | 按钮 | 代价 | 需要的前置条件 |
 * |---|---|---|
 * | 清空账目 | 不可逆，但**用户自己能理解**「我把账清空了」 | 无 |
 * | 重置演示数据 | 不可逆，且**会把真数据换成假数据** | 库里必须**只有**演示数据 |
 *
 * 后者的前置条件不是谨慎过头：一个叫「重置」的按钮，最容易被理解成
 * 「把我的数据整理一下」。若库里已经有真实账目而它照跑，
 * 用户会丢掉全部真实数据、换来一堆 2026 年的假账单 —— 而且他以为自己在「重置」。
 *
 * 判据落在**上一次种子留下的 id 清单**上（存在 `settings.demo_seed`）：
 * 活着的账目里只要有一条不在清单里，就拒绝并说清有几条。
 */
import type { DatabaseSync } from 'node:sqlite';

import { isDateString } from '../../domain/billing-cycle.ts';
import { badRequest, conflict } from '../../lib/http-error.ts';
import { inTransaction, recordChange, type EntityType } from '../sync.ts';
import { seedDemoData, type DemoCounts } from './demo.ts';
import { preRestoreDir } from './transfer.ts';

/**
 * 账目类表 —— 「清空」指的就是这三张。
 *
 * 顺序是**期次 → 支出 → 计划**：先清叶子再清父级，读起来与依赖方向一致
 * （软删不触发外键，但顺序错的文件在将来改成硬删时会静默埋雷）。
 */
const LEDGER_TABLES = [
  { table: 'plan_todos', entity: 'plan_todo', label: '计划期次' },
  { table: 'expenses', entity: 'expense', label: '支出' },
  { table: 'plans', entity: 'plan', label: '计划' },
] as const satisfies ReadonlyArray<{ table: string; entity: EntityType; label: string }>;

/** 上一次「重置演示数据」留下的凭据：灌了哪些 id、什么时候灌的。 */
const DEMO_MARKER_KEY = 'demo_seed';

// ---------------------------------------------------------------------------
// settings 表（不是同步实体，直写）
// ---------------------------------------------------------------------------

/**
 * `settings` 不参与同步（它不在 `EntityType` 里），所以这里的读写不走
 * `recordChange` —— 它不是「家庭数据」，是**这一台服务端自己的状态**。
 * 把它同步出去反而会让另一台设备以为「演示数据已经灌过了」。
 */
function readSetting(db: DatabaseSync, key: string): string | null {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key) as
    | { value: string }
    | undefined;
  return row === undefined ? null : row.value;
}

function writeSetting(db: DatabaseSync, key: string, value: string): void {
  db.prepare(
    `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  ).run(key, value, new Date().toISOString());
}

interface DemoMarker {
  seededAt: string;
  ids: string[];
}

function readDemoMarker(db: DatabaseSync): DemoMarker | null {
  const raw = readSetting(db, DEMO_MARKER_KEY);
  if (raw === null) return null;

  try {
    const parsed = JSON.parse(raw) as Partial<DemoMarker>;
    if (!Array.isArray(parsed.ids)) return null;
    return { seededAt: String(parsed.seededAt ?? ''), ids: parsed.ids.map(String) };
  } catch {
    // 手工改坏了一个内部标记，不该让整个设置页打不开。
    // 当作「没有标记」处理：结果是重置被拒（更保守的那一侧）。
    return null;
  }
}

function clearDemoMarker(db: DatabaseSync): void {
  db.prepare('DELETE FROM settings WHERE key = ?').run(DEMO_MARKER_KEY);
}

// ---------------------------------------------------------------------------
// 概览
// ---------------------------------------------------------------------------

export interface DataOverview {
  /** 活着的账目条数 */
  ledger: DemoCounts;
  categories: number;
  paymentMethods: number;
  members: number;
  /** 最早那笔账的**还款日** —— 与报表口径同源，不用 `spend_date` */
  firstRepaymentDate: string | null;
  /** 上一次灌演示数据的时间；从未灌过为 null */
  demoSeededAt: string | null;
  /** 「重置演示数据」现在能不能按，以及不能按时该对用户说什么（空数组 = 可以） */
  resetDemoBlockers: string[];
  /** 恢复前存档落在哪 —— 出事了去哪儿找回来说清楚 */
  preRestoreDir: string;
}

function countLive(db: DatabaseSync, table: string): number {
  const row = db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE deleted_at IS NULL`).get() as
    | { n: number }
    | undefined;
  return Number(row?.n ?? 0);
}

function liveLedgerIds(db: DatabaseSync, table: string): string[] {
  const rows = db
    .prepare(`SELECT id FROM ${table} WHERE deleted_at IS NULL`)
    .all() as Array<{ id: string }>;
  return rows.map((row) => row.id);
}

/**
 * 「重置演示数据」现在不能按的原因。空数组 = 可以按。
 *
 * 这一条**只写一次**，被三处用到：概览接口回报、重置接口自己判定、
 * 以及将来若要让按钮置灰 —— 三处必须是同一句话，否则界面上说的
 * 和接口拒绝的理由会不一样（那种差异最难解释）。
 */
function demoBlockers(db: DatabaseSync): string[] {
  const marker = readDemoMarker(db);
  const seeded = new Set(marker?.ids ?? []);

  const blockers: string[] = [];
  for (const target of LEDGER_TABLES) {
    const extra = liveLedgerIds(db, target.table).filter((id) => !seeded.has(id)).length;
    if (extra > 0) blockers.push(`${target.label} ${extra} 条`);
  }
  return blockers;
}

export function dataOverview(db: DatabaseSync): DataOverview {
  const first = db
    .prepare('SELECT MIN(repayment_date) AS d FROM expenses WHERE deleted_at IS NULL')
    .get() as { d: string | null } | undefined;

  return {
    ledger: {
      expenses: countLive(db, 'expenses'),
      plans: countLive(db, 'plans'),
      planTodos: countLive(db, 'plan_todos'),
    },
    categories: countLive(db, 'categories'),
    paymentMethods: countLive(db, 'payment_methods'),
    members: countLive(db, 'users'),
    firstRepaymentDate: first?.d ?? null,
    demoSeededAt: readDemoMarker(db)?.seededAt ?? null,
    resetDemoBlockers: demoBlockers(db),
    preRestoreDir: preRestoreDir(),
  };
}

// ---------------------------------------------------------------------------
// 清空
// ---------------------------------------------------------------------------

/**
 * 软删一张表里所有活着的行，并**逐行**落 `changes`。
 *
 * 用 `SELECT *` 而不是显式列清单是有意的：payload 要的是
 * **改动那一行的完整快照**，少写一列，别的设备就会拿到一个缺字段的实体，
 * 而且不报错。导出那边用显式清单，是因为它要固定的是**文件格式**。
 */
function softDeleteAll(
  db: DatabaseSync,
  target: (typeof LEDGER_TABLES)[number],
  actorId: string,
  now: string,
): number {
  const rows = db
    .prepare(`SELECT * FROM ${target.table} WHERE deleted_at IS NULL`)
    .all() as Array<Record<string, unknown>>;
  if (rows.length === 0) return 0;

  const update = db.prepare(
    `UPDATE ${target.table} SET deleted_at = ?, updated_at = ?, rev = rev + 1 WHERE id = ?`,
  );

  for (const row of rows) {
    const id = String(row['id']);
    update.run(now, now, id);

    recordChange(db, {
      entityType: target.entity,
      entityId: id,
      op: 'delete',
      actorId,
      payload: { ...row, deleted_at: now, updated_at: now, rev: Number(row['rev']) + 1 },
      deviceId: typeof row['device_id'] === 'string' ? row['device_id'] : null,
    });
  }

  return rows.length;
}

export interface LedgerWipeReport {
  removed: { expenses: number; plans: number; planTodos: number };
  total: number;
  /** 动手之前自动存的那份全量快照；调用方没注入存档函数时为 null */
  snapshotPath: string | null;
}

interface MaintenanceOptions {
  /** 存档函数由 http 层注入 —— repo 层不碰文件系统路径策略（与 transfer.ts 一致） */
  snapshot?: (() => string | null) | undefined;
}

/** 空实现，只为让两个入口的默认参数写法一致。 */
function noSnapshot(): string | null {
  return null;
}

/**
 * 清空全部账目（支出 / 计划 / 待办）。
 *
 * **保留**分类、支付方式、账号：它们是配置，删掉会让记账当场没法用，
 * 而且它们本来就不是「账」。
 */
export function wipeLedger(
  db: DatabaseSync,
  actorId: string,
  options: MaintenanceOptions = {},
): LedgerWipeReport {
  const now = new Date().toISOString();
  const snapshot = options.snapshot ?? noSnapshot;
  const removed = { expenses: 0, plans: 0, planTodos: 0 };
  let snapshotPath: string | null = null;

  inTransaction(db, () => {
    // 存档要在**第一次写入之前**、且在事务里 —— 否则存下来的可能已经是半改过的状态
    snapshotPath = snapshot();

    removed.planTodos = softDeleteAll(db, LEDGER_TABLES[0], actorId, now);
    removed.expenses = softDeleteAll(db, LEDGER_TABLES[1], actorId, now);
    removed.plans = softDeleteAll(db, LEDGER_TABLES[2], actorId, now);

    // 账目清光了，演示数据的 id 清单也就失效了。留着会让**下一次重置**
    // 拿一份过期清单当准入依据 —— 而那时库里已经一条不剩，
    // 本该判定为「可以直接灌」。
    clearDemoMarker(db);
  });

  return {
    removed,
    total: removed.expenses + removed.plans + removed.planTodos,
    snapshotPath,
  };
}

// ---------------------------------------------------------------------------
// 重置演示数据
// ---------------------------------------------------------------------------

export interface DemoResetReport extends LedgerWipeReport {
  /** 这次灌进去了多少 */
  seeded: DemoCounts;
  seederActorId: string;
}

/**
 * 清掉旧的演示数据，再灌一份新的（日期相对 `today` 现算）。
 *
 * `today` 必须由客户端给：服务端从不自己推算业务日期。
 */
export function resetDemoData(
  db: DatabaseSync,
  actorId: string,
  today: string,
  options: MaintenanceOptions = {},
): DemoResetReport {
  if (!isDateString(today)) {
    throw badRequest(`today 必须是 YYYY-MM-DD，收到：${today}`);
  }

  const blockers = demoBlockers(db);
  if (blockers.length > 0) {
    throw conflict(
      `库里已经有不是演示数据的东西（${blockers.join('、')}），拒绝重置。`
        + '「重置演示数据」会把这些换成一份假账单，而且不可逆 —— '
        + '如果你确实是想清空，请用「清空账目数据」。',
    );
  }

  const now = new Date().toISOString();
  const snapshot = options.snapshot ?? noSnapshot;
  const removed = { expenses: 0, plans: 0, planTodos: 0 };
  let snapshotPath: string | null = null;
  let seeded: DemoCounts = { expenses: 0, plans: 0, planTodos: 0 };

  inTransaction(db, () => {
    snapshotPath = snapshot();

    removed.planTodos = softDeleteAll(db, LEDGER_TABLES[0], actorId, now);
    removed.expenses = softDeleteAll(db, LEDGER_TABLES[1], actorId, now);
    removed.plans = softDeleteAll(db, LEDGER_TABLES[2], actorId, now);
    clearDemoMarker(db);

    const result = seedDemoData(db, actorId, today);
    seeded = result.counts;

    // 凭据写在**同一次事务**里：种子成功而凭据没写下，下一次重置就会
    // 因为「清单是空的」而被自己拒绝 —— 一个只在第二次点击时才出现的 bug。
    writeSetting(db, DEMO_MARKER_KEY, JSON.stringify({ seededAt: now, ids: result.ids }));
  });

  return {
    removed,
    total: removed.expenses + removed.plans + removed.planTodos,
    snapshotPath,
    seeded,
    seederActorId: actorId,
  };
}
