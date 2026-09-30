import type { DatabaseSync } from 'node:sqlite';

import type { EntityType } from '../sync.ts';
import { batchCreateExpenses, type BatchExpenseItem } from './expenses.ts';

export interface ChangeItem {
  version: number;
  entityType: EntityType;
  entityId: string;
  op: 'upsert' | 'delete';
  actorId: string | null;
  payload: Record<string, unknown>;
  deviceId: string | null;
  createdAt: string;
}

export interface PullChangesResult {
  changes: ChangeItem[];
  latestVersion: number;
  hasMore: boolean;
}

/**
 * 获取当前全局单调自增的最新版本号（来自 sync_sequence）
 */
export function currentSyncVersion(db: DatabaseSync): number {
  const row = db.prepare('SELECT value FROM sync_sequence WHERE id = 1').get() as
    | { value: number | string }
    | undefined;
  return row ? Number(row.value) : 0;
}

/**
 * 增量拉取变更：
 * 客户端传入 sinceVersion，获取其后发生的所有实体变更，按全局版本号严格递增排序。
 */
export function pullChanges(
  db: DatabaseSync,
  sinceVersion: number = 0,
  limit: number = 200,
): PullChangesResult {
  const safeLimit = Math.min(Math.max(1, limit), 500);
  const latestVersion = currentSyncVersion(db);

  const rows = db
    .prepare(
      `SELECT version, entity_type, entity_id, op, actor_id, payload, device_id, created_at
       FROM changes
       WHERE version > ?
       ORDER BY version ASC
       LIMIT ?`,
    )
    .all(sinceVersion, safeLimit) as Array<{
      version: number | string;
      entity_type: string;
      entity_id: string;
      op: string;
      actor_id: string | null;
      payload: string;
      device_id: string | null;
      created_at: string;
    }>;

  const changes: ChangeItem[] = rows.map((r) => {
    let parsedPayload: Record<string, unknown> = {};
    try {
      parsedPayload = JSON.parse(r.payload) as Record<string, unknown>;
    } catch {
      parsedPayload = {};
    }
    return {
      version: Number(r.version),
      entityType: r.entity_type as EntityType,
      entityId: r.entity_id,
      op: r.op as 'upsert' | 'delete',
      actorId: r.actor_id,
      payload: parsedPayload,
      deviceId: r.device_id,
      createdAt: r.created_at,
    };
  });

  const hasMore =
    changes.length === safeLimit && changes[changes.length - 1]!.version < latestVersion;

  return {
    changes,
    latestVersion,
    hasMore,
  };
}

export interface SyncPushInput {
  expenses?: BatchExpenseItem[];
}

export interface SyncPushResult {
  pushedExpensesCount: number;
  expenseIds: string[];
  latestVersion: number;
}

/**
 * 客户端离线数据补偿推送：
 * 在单一事务中批量写入离线期间新增的支出记录，并返回确认的 id 与最新全局版本号。
 */
export function pushChanges(
  db: DatabaseSync,
  input: SyncPushInput,
  actorId: string,
  deviceId?: string | null,
): SyncPushResult {
  let createdCount = 0;
  let expenseIds: string[] = [];

  if (input.expenses && input.expenses.length > 0) {
    const res = batchCreateExpenses(db, { items: input.expenses }, actorId, deviceId);
    createdCount = res.createdCount;
    expenseIds = res.expenseIds;
  }

  return {
    pushedExpensesCount: createdCount,
    expenseIds,
    latestVersion: currentSyncVersion(db),
  };
}
