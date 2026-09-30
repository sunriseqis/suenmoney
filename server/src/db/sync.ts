/**
 * 同步写入层 —— 所有实体写入的**唯一入口**。
 *
 * 之所以要有这么一层：增量同步依赖「每一次写入都在 changes 表里留下一条
 * 带全局版本号的记录」。如果允许各路由直接 `INSERT INTO expenses ...`，
 * 那么迟早会有人忘记写 changes，而**忘记写不会报错** —— 表现是
 * 「手机上这笔账莫名其妙不出现」，且只在别的设备上复现，极难排查。
 *
 * 因此约定：路由层不许直接拼 INSERT/UPDATE，一律走这里。
 */
import type { DatabaseSync } from 'node:sqlite';
import { nextSyncVersion } from './index.ts';

/** 参与同步的实体类型。改动这里要同步更新客户端的应用逻辑。 */
export type EntityType =
  | 'user'
  | 'category'
  | 'payment_method'
  | 'plan'
  | 'plan_todo'
  | 'expense'
  | 'plan_revision';

export interface ChangeInput {
  entityType: EntityType;
  entityId: string;
  op: 'upsert' | 'delete';
  /** 谁触发的这次变更（计划生成的记录以计划所有者为 actor） */
  actorId: string | null;
  /** 变更后的实体快照 */
  payload: Record<string, unknown>;
  deviceId: string | null;
}

/**
 * 分配版本号并写入变更日志。必须在事务内调用（见 `inTransaction`）。
 */
export function recordChange(db: DatabaseSync, input: ChangeInput): number {
  const version = nextSyncVersion(db);

  db.prepare(
    `INSERT INTO changes (version, entity_type, entity_id, op, actor_id, payload, device_id, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    version,
    input.entityType,
    input.entityId,
    input.op,
    input.actorId ?? null,
    JSON.stringify(input.payload),
    input.deviceId ?? null,
    new Date().toISOString(),
  );

  return version;
}

/**
 * 当前事务深度。
 *
 * SQLite **不支持嵌套事务** —— 在事务里再执行 `BEGIN` 会直接抛
 * `cannot start a transaction within a transaction`。而组合操作必然会出现嵌套：
 * 「确认计划待办」要在一个事务里既改待办状态、又插入支出记录，
 * 而插入支出记录本身也是走 `inTransaction` 的。
 *
 * 所以这里做成**可重入**的：已经处于事务中时直接执行，由最外层负责提交或回滚。
 * 单进程单连接下这个深度计数是安全的。
 */
let transactionDepth = 0;

/**
 * 在写事务里执行一段逻辑（可重入）。
 *
 * 用 `BEGIN IMMEDIATE` 而不是裸 `BEGIN`：后者是延迟事务，会先以读锁开始，
 * 等到第一次写入时才尝试升级为写锁 —— 两个并发请求同时走到这一步就会
 * 互相等待并触发 SQLITE_BUSY。IMMEDIATE 一开始就拿写锁，行为可预期。
 */
export function inTransaction<T>(db: DatabaseSync, fn: () => T): T {
  if (transactionDepth > 0) return fn();

  db.exec('BEGIN IMMEDIATE');
  transactionDepth += 1;

  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  } finally {
    transactionDepth -= 1;
  }
}

/** 当前最大的同步版本号 = 服务端最新状态。新设备首次同步的起点。 */
export function currentSyncVersion(db: DatabaseSync): number {
  const row = db.prepare('SELECT value FROM sync_sequence WHERE id = 1').get();
  return row === undefined ? 0 : Number(row['value']);
}
