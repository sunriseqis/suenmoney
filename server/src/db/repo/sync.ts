import type { DatabaseSync } from 'node:sqlite';

import type { EntityType } from '../sync.ts';
import { inTransaction } from '../sync.ts';
import {
  batchCreateExpenses,
  softDeleteExpense,
  updateExpense,
  type BatchExpenseItem,
} from './expenses.ts';
import { ackTodo, confirmTodo, restoreSkippedTodo, revertTodoConfirm, skipTodo } from './plans.ts';

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

export interface BatchUpdateExpenseItem {
  id: string;
  amountCents?: number | undefined;
  categoryId?: string | undefined;
  paymentMethodId?: string | undefined;
  spendDate?: string | undefined;
  note?: string | undefined;
}

export interface BatchConfirmTodoItem {
  id: string;
  spendDate?: string | undefined;
}

export interface SyncPushInput {
  expenses?: BatchExpenseItem[] | undefined;
  updatedExpenses?: BatchUpdateExpenseItem[] | undefined;
  deletedExpenseIds?: string[] | undefined;
  confirmedTodos?: BatchConfirmTodoItem[] | undefined;
  skippedTodoIds?: string[] | undefined;
  ackedTodoIds?: string[] | undefined;
  /** 撤销确认（confirmed → pending，撤掉生成的支出） */
  revertedTodoIds?: string[] | undefined;
  /** 恢复跳过（skipped → pending） */
  restoredTodoIds?: string[] | undefined;
}

export interface SyncPushResult {
  pushedExpensesCount: number;
  updatedExpensesCount: number;
  deletedExpensesCount: number;
  confirmedTodosCount: number;
  skippedTodosCount: number;
  ackedTodosCount: number;
  revertedTodosCount: number;
  restoredTodosCount: number;
  expenseIds: string[];
  /** 新增支出中被服务端拒绝的条目在 input.expenses 里的下标（0 起），客户端据此做重试/死信隔离 */
  failedExpenseIndexes: number[];
  latestVersion: number;
}

/**
 * 客户端离线数据补偿推送：
 * 在单一事务中批量写入离线期间产生的新增、修改、删除支出以及计划待办状态，并返回确认指标与最新全局版本号。
 */
export function pushChanges(
  db: DatabaseSync,
  input: SyncPushInput,
  actorId: string,
  deviceId?: string | null,
): SyncPushResult {
  let createdCount = 0;
  let updatedExpensesCount = 0;
  let deletedExpensesCount = 0;
  let confirmedTodosCount = 0;
  let skippedTodosCount = 0;
  let ackedTodosCount = 0;
  let revertedTodosCount = 0;
  let restoredTodosCount = 0;
  let expenseIds: string[] = [];
  const failedExpenseIndexes: number[] = [];

  inTransaction(db, () => {
    // 1. 新增支出：逐条校验入库。
    //    整批一个事务是「毒丸」温床 —— 单条坏数据（如关联了云端已失效的分类）
    //    会把整批回滚，且客户端没有重试剔除逻辑，该条将永久卡死 Outbox 队列头。
    //    这里单条失败只记录下标并跳过，其余条目正常入库，由客户端对失败项做死信隔离。
    if (input.expenses && input.expenses.length > 0) {
      for (const [index, item] of input.expenses.entries()) {
        try {
          const res = batchCreateExpenses(db, { items: [item] }, actorId, deviceId);
          createdCount += res.createdCount;
          expenseIds.push(...res.expenseIds);
        } catch {
          failedExpenseIndexes.push(index);
        }
      }
    }

    // 2. 批量修改支出
    if (input.updatedExpenses && input.updatedExpenses.length > 0) {
      for (const item of input.updatedExpenses) {
        try {
          updateExpense(db, item.id, {
            actorId,
            amountCents: item.amountCents,
            categoryId: item.categoryId,
            paymentMethodId: item.paymentMethodId,
            spendDate: item.spendDate,
            note: item.note,
            deviceId: deviceId ?? null,
          });
          updatedExpensesCount++;
        } catch {
          // 忽略如已被删除或已被他人修改等异常，保证批量同步幂等且不因个别条目阻断
        }
      }
    }

    // 3. 批量删除支出
    if (input.deletedExpenseIds && input.deletedExpenseIds.length > 0) {
      for (const id of input.deletedExpenseIds) {
        try {
          softDeleteExpense(db, id, actorId);
          deletedExpensesCount++;
        } catch {
          // 忽略已被删除或不存在的记录
        }
      }
    }

    // 4. 批量确认待办
    if (input.confirmedTodos && input.confirmedTodos.length > 0) {
      for (const item of input.confirmedTodos) {
        try {
          confirmTodo(db, item.id, actorId, item.spendDate);
          confirmedTodosCount++;
        } catch {
          // 忽略已被确认或跳过的待办
        }
      }
    }

    // 5. 批量跳过待办
    if (input.skippedTodoIds && input.skippedTodoIds.length > 0) {
      for (const id of input.skippedTodoIds) {
        try {
          skipTodo(db, id, actorId);
          skippedTodosCount++;
        } catch {
          // 忽略异常
        }
      }
    }

    // 6. 批量知晓待办（ack）
    if (input.ackedTodoIds && input.ackedTodoIds.length > 0) {
      for (const id of input.ackedTodoIds) {
        try {
          ackTodo(db, id, actorId);
          ackedTodosCount++;
        } catch {
          // 忽略异常
        }
      }
    }

    // 7. 批量撤销确认（confirmed → pending，同时软删生成的支出）
    if (input.revertedTodoIds && input.revertedTodoIds.length > 0) {
      for (const id of input.revertedTodoIds) {
        try {
          revertTodoConfirm(db, id, actorId);
          revertedTodosCount++;
        } catch {
          // 忽略：待办可能已在别的设备被撤销 / 状态已变
        }
      }
    }

    // 8. 批量恢复跳过（skipped → pending）
    if (input.restoredTodoIds && input.restoredTodoIds.length > 0) {
      for (const id of input.restoredTodoIds) {
        try {
          restoreSkippedTodo(db, id, actorId);
          restoredTodosCount++;
        } catch {
          // 忽略：待办可能已被恢复 / 状态已变
        }
      }
    }
  });

  return {
    pushedExpensesCount: createdCount,
    updatedExpensesCount,
    deletedExpensesCount,
    confirmedTodosCount,
    skippedTodosCount,
    ackedTodosCount,
    revertedTodosCount,
    restoredTodosCount,
    expenseIds,
    failedExpenseIndexes,
    latestVersion: currentSyncVersion(db),
  };
}
