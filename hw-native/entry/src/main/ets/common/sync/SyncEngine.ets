/**
 * 同步引擎（H7）。
 *
 * 两件事：
 *   1. **推**：把 Outbox 里的离线写入按服务端 `/api/sync/push` 的分组格式批量提交，
 *      成功后删队列；失败按 5s/10s/30s 退避重试，3 次仍失败进死信（界面可见）。
 *   2. **拉**：`/api/sync/pull?since=cursor` 增量拉变更，写进本地库，游标存 meta 表。
 *
 * 为什么推送要「分组」而不是逐条 POST：服务端一次事务落库，避免半成功；
 * 逐条提交在网络抖动时会出现「这三笔进了、那两笔没进」，用户无法判断该怎么补。
 */
import { relationalStore } from '@kit.ArkData';

import { Api, SyncPullBody, SyncPushRequest, SyncUpdateExpense } from '../net/Api';
import { ApiError } from '../net/ApiError';
import { Db } from '../store/Db';
import { Outbox, OutboxEntry, OUTBOX_MAX_RETRY } from './Outbox';

const CURSOR_KEY = 'sync_cursor';
/** 本地变更后 300ms 防抖再推（连续记账不会每次打一次网络） */
const DEBOUNCE_MS = 300;

export interface SyncReport {
  pushed: number;
  deadLettered: number;
  pulled: number;
  cursor: number;
  error: string;
}

export class SyncEngine {
  private static timer: number = -1;
  private static running: boolean = false;

  /** 本地变更后调用：300ms 内多次调用只推一次 */
  static schedulePush(): void {
    if (SyncEngine.timer !== -1) {
      clearTimeout(SyncEngine.timer);
    }
    SyncEngine.timer = setTimeout(() => {
      SyncEngine.timer = -1;
      SyncEngine.syncNow();
    }, DEBOUNCE_MS);
  }

  /** 完整一轮：先推后拉（推成功后本地才有正确游标语义） */
  static async syncNow(): Promise<SyncReport> {
    const report: SyncReport = { pushed: 0, deadLettered: 0, pulled: 0, cursor: 0, error: '' };
    if (SyncEngine.running) {
      return report;
    }
    SyncEngine.running = true;
    try {
      const pushResult = await SyncEngine.push();
      report.pushed = pushResult.pushed;
      report.deadLettered = pushResult.dead;
      const pullResult = await SyncEngine.pull();
      report.pulled = pullResult.applied;
      report.cursor = pullResult.cursor;
    } catch (e) {
      const err = e as ApiError;
      report.error = err.kind === 'network' ? '离线：稍后自动重试' : err.message;
    } finally {
      SyncEngine.running = false;
    }
    return report;
  }

  /** 推：分组提交 */
  static async push(): Promise<PushResult> {
    const entries: OutboxEntry[] = await Outbox.pending();
    const result: PushResult = { pushed: 0, dead: 0 };
    if (entries.length === 0) {
      return result;
    }

    const req: SyncPushRequest = {
      expenses: [],
      updatedExpenses: [],
      deletedExpenseIds: [],
      confirmedTodos: [],
      skippedTodoIds: [],
      ackedTodoIds: [],
      revertedTodoIds: [],
      restoredTodoIds: []
    };

    for (const entry of entries) {
      const payload = parsePayload(entry.payload);
      if (entry.action === 'create_expense') {
        req.expenses.push({
          id: entry.entityId,
          amountCents: Number(payload['amountCents'] ?? 0),
          categoryId: String(payload['categoryId'] ?? ''),
          paymentMethodId: String(payload['paymentMethodId'] ?? ''),
          spendDate: String(payload['spendDate'] ?? ''),
          note: String(payload['note'] ?? '')
        });
      } else if (entry.action === 'update_expense') {
        // ArkTS 不支持结构类型转换：逐字段显式构造
        const upd: SyncUpdateExpense = {
          id: entry.entityId,
          amountCents: Number(payload['amountCents'] ?? 0),
          categoryId: String(payload['categoryId'] ?? ''),
          paymentMethodId: String(payload['paymentMethodId'] ?? ''),
          spendDate: String(payload['spendDate'] ?? ''),
          note: String(payload['note'] ?? '')
        };
        req.updatedExpenses.push(upd);
      } else if (entry.action === 'delete_expense') {
        req.deletedExpenseIds.push(entry.entityId);
      } else if (entry.action === 'confirm_todo') {
        req.confirmedTodos.push({ id: entry.entityId, spendDate: String(payload['spendDate'] ?? '') });
      } else if (entry.action === 'skip_todo') {
        req.skippedTodoIds.push(entry.entityId);
      } else if (entry.action === 'ack_todo') {
        req.ackedTodoIds.push(entry.entityId);
      } else if (entry.action === 'revert_todo') {
        req.revertedTodoIds.push(entry.entityId);
      } else if (entry.action === 'restore_todo') {
        req.restoredTodoIds.push(entry.entityId);
      }
    }

    try {
      await Api.syncPush(req);
      await Outbox.remove(entries.map((e: OutboxEntry): string => e.id));
      result.pushed = entries.length;
      return result;
    } catch (e) {
      const err = e as ApiError;
      // 网络错误：整批不计数（下次一起重发，保证原子性语义）
      if (err.kind === 'network') {
        return result;
      }
      // 4xx/5xx：逐条标记，超过上限的会成为死信
      for (const entry of entries) {
        await Outbox.markFailed(entry.id, err.message);
        if (entry.retryCount + 1 >= OUTBOX_MAX_RETRY) {
          result.dead += 1;
        }
      }
      return result;
    }
  }

  /** 拉：增量应用到本地 */
  static async pull(): Promise<PullResult> {
    const cursor = await SyncEngine.readCursor();
    const body: SyncPullBody = await Api.syncPull(cursor, 200);
    let applied = 0;
    for (const change of body.changes) {
      await SyncEngine.applyChange(change.entityType, change.entityId, change.op, change.payload);
      applied += 1;
    }
    const next = body.latestVersion;
    await SyncEngine.writeCursor(next);
    return { applied: applied, cursor: next };
  }

  static async readCursor(): Promise<number> {
    const store = Db.get();
    const rs = await store.querySql('SELECT value FROM meta WHERE key = ?', [CURSOR_KEY]);
    let value = 0;
    if (rs.goToFirstRow()) {
      value = Number(rs.getString(rs.getColumnIndex('value'))) || 0;
    }
    rs.close();
    return value;
  }

  private static async writeCursor(value: number): Promise<void> {
    const store = Db.get();
    await store.executeSql('INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)', [CURSOR_KEY, String(value)]);
  }

  /**
   * 应用一条变更。
   *
   * 只处理本地有表的五类实体；其余（如 settings）忽略 —— 拉下来没有表可放，
   * 硬塞会让本地库与契约悄悄分叉。
   */
  private static async applyChange(entityType: string, entityId: string, op: string, payload: object): Promise<void> {
    const store = Db.get();
    const table = tableOf(entityType);
    if (table === '') {
      return;
    }
    if (op === 'delete') {
      await store.executeSql(`DELETE FROM ${table} WHERE id = ?`, [entityId]);
      return;
    }
    const bucket = toBucket(entityType, payload);
    if (bucket === null) {
      return;
    }
    await store.insert(table, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }
}

interface PushResult {
  pushed: number;
  dead: number;
}

interface PullResult {
  applied: number;
  cursor: number;
}

function parsePayload(raw: string): Record<string, Object> {
  try {
    return JSON.parse(raw) as Record<string, Object>;
  } catch (e) {
    return {};
  }
}

function tableOf(entityType: string): string {
  if (entityType === 'expense') {
    return 'expenses';
  }
  if (entityType === 'category') {
    return 'categories';
  }
  if (entityType === 'payment_method') {
    return 'payment_methods';
  }
  if (entityType === 'plan') {
    return 'plans';
  }
  if (entityType === 'plan_todo') {
    return 'plan_todos';
  }
  return '';
}

/** 服务端 payload（camelCase）→ 本地列（snake_case） */
function toBucket(entityType: string, payload: object): relationalStore.ValuesBucket | null {
  const p = payload as Record<string, Object>;
  if (entityType === 'expense') {
    const bucket: relationalStore.ValuesBucket = {
      'id': String(p['id'] ?? ''),
      'owner_id': String(p['ownerId'] ?? ''),
      'amount_cents': Number(p['amountCents'] ?? 0),
      'category_id': String(p['categoryId'] ?? ''),
      'payment_method_id': String(p['paymentMethodId'] ?? ''),
      'spend_date': String(p['spendDate'] ?? ''),
      'posting_date': String(p['postingDate'] ?? ''),
      'repayment_date': String(p['repaymentDate'] ?? ''),
      'note': String(p['note'] ?? ''),
      'source': String(p['source'] ?? 'manual'),
      'updated_at': String(p['updatedAt'] ?? new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'category') {
    const bucket: relationalStore.ValuesBucket = {
      'id': String(p['id'] ?? ''),
      'parent_id': p['parentId'] === null || p['parentId'] === undefined ? '' : String(p['parentId']),
      'name': String(p['name'] ?? ''),
      'depth': Number(p['depth'] ?? 1),
      'icon': String(p['icon'] ?? ''),
      'color': String(p['color'] ?? ''),
      'sort_order': Number(p['sortOrder'] ?? 0),
      'is_enabled': p['isEnabled'] === false ? 0 : 1
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'payment_method') {
    const bucket: relationalStore.ValuesBucket = {
      'id': String(p['id'] ?? ''),
      'name': String(p['name'] ?? ''),
      'type': String(p['type'] ?? 'cash'),
      'icon': String(p['icon'] ?? ''),
      'billing_day': Number(p['billingDay'] ?? 0),
      'repayment_day': Number(p['repaymentDay'] ?? 0),
      'is_enabled': p['isEnabled'] === false ? 0 : 1,
      'sort_order': Number(p['sortOrder'] ?? 0)
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'plan') {
    const bucket: relationalStore.ValuesBucket = {
      'id': String(p['id'] ?? ''),
      'name': String(p['name'] ?? ''),
      'category_id': String(p['categoryId'] ?? ''),
      'payment_method_id': String(p['paymentMethodId'] ?? ''),
      'amount_cents': Number(p['amountCents'] ?? 0),
      'total_amount_cents': Number(p['totalAmountCents'] ?? 0),
      'purchase_date': String(p['purchaseDate'] ?? ''),
      'first_due_date': String(p['firstDueDate'] ?? ''),
      'remind_days_before': Number(p['remindDaysBefore'] ?? 3),
      'auto_post': p['autoPost'] === true ? 1 : 0,
      'source': String(p['source'] ?? 'manual'),
      'state': String(p['state'] ?? 'active'),
      'note': String(p['note'] ?? ''),
      'updated_at': String(p['updatedAt'] ?? new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'plan_todo') {
    const bucket: relationalStore.ValuesBucket = {
      'id': String(p['id'] ?? ''),
      'plan_id': String(p['planId'] ?? ''),
      'plan_name': String(p['planName'] ?? ''),
      'period_seq': Number(p['periodSeq'] ?? 0),
      'amount_cents': Number(p['amountCents'] ?? 0),
      'repayment_date': String(p['repaymentDate'] ?? ''),
      'status': String(p['status'] ?? 'pending'),
      'will_auto_post': p['willAutoPost'] === true ? 1 : 0,
      'updated_at': String(p['updatedAt'] ?? new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  return null;
}
