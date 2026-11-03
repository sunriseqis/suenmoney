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
import { SyncStore } from '../store/SyncStore';
import { ExpenseDao } from '../store/ExpenseDao';
import { Outbox, OutboxEntry, OUTBOX_MAX_RETRY } from './Outbox';

const CURSOR_KEY = 'sync_cursor';
/** 本地数据版本：同步写完 +1，各屏订阅它重新读本地库 */
export const DATA_VERSION_KEY = 'localDataVersion';
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

  /**
   * **拉取一次更新**（冷启动 / 热启动各调一次）。
   *
   * - 本地是空的（首装 / 换账号 / 清过库）→ 拉全量快照，游标记成快照点；
   * - 否则 → 增量 pull，翻页直到 `hasMore=false`。
   *
   * 只负责「拉」。推送由 `syncNow()` 负责（它先推后拉）。
   */
  static async refresh(): Promise<number> {
    // 增量可能有多页：一直翻到 hasMore=false，否则一次启动只同步 200 条
    let last = await SyncEngine.readCursor();
    for (let i = 0; i < 50; i++) {
      const result = await SyncEngine.pull();
      last = result.cursor;
      if (!result.hasMore) {
        break;
      }
    }
    return last;
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
      /*
       * 广播「本地数据版本」。
       *
       * 本地优先之后，屏幕不再等接口返回，而是读本地库 —— 所以同步写完之后
       * 必须有个信号让它们重读，否则界面停留在旧数据直到用户手动切页。
       * 各屏用 `@StorageLink(DATA_VERSION_KEY)` 订阅并 reload。
       */
      const prev: number = AppStorage.get<number>(DATA_VERSION_KEY) ?? 0;
      AppStorage.setOrCreate<number>(DATA_VERSION_KEY, prev + 1);
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
    /*
     * 本地是空的（首装 / 换账号 / 清过库）→ 拉全量快照，而不是从 0 重放变更历史。
     * 放在 pull 里而不是调用方，是为了让 syncNow / refresh 两条路径都自动覆盖。
     */
    if (cursor === 0 && (await ExpenseDao.count()) === 0) {
      const version = await SyncStore.bootstrap();
      await SyncEngine.writeCursor(version);
      return { applied: 0, cursor: version, hasMore: false };
    }
    const body: SyncPullBody = await Api.syncPull(cursor, 200);
    let applied = 0;
    for (const change of body.changes) {
      await SyncEngine.applyChange(change.entityType, change.entityId, change.op, change.payload);
      applied += 1;
    }
    const next = body.latestVersion;
    await SyncEngine.writeCursor(next);
    return { applied: applied, cursor: next, hasMore: body.hasMore };
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
  hasMore: boolean;
}

function parsePayload(raw: string): Record<string, Object> {
  try {
    return JSON.parse(raw) as Record<string, Object>;
  } catch (e) {
    return {};
  }
}

function tableOf(entityType: string): string {
  if (entityType === 'user') {
    return 'users';
  }
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

/**
 * 服务端 payload → 本地列。
 *
 * ⚠ **两种命名风格并存**，必须都认：
 *   · `category` / `payment_method` 的 payload 是 camelCase（`parentId` / `sortOrder`）；
 *   · `expense` / `plan` / `plan_todo` 的 payload 是 **snake_case**（`owner_id` / `amount_cents`）。
 *
 * 旧实现一律按 camelCase 读，于是每次增量拉取都把本地支出写成
 * `owner_id=''`、`amount_cents=0` —— 数据被静默冲成空值。这里统一用 `pick()`
 * 双键兼容，服务端以后改风格也不会再炸。
 */
function pick(p: Record<string, Object>, snake: string, camel: string, fallback: Object): Object {
  const a = p[snake];
  if (a !== undefined && a !== null) {
    return a;
  }
  const b = p[camel];
  if (b !== undefined && b !== null) {
    return b;
  }
  return fallback;
}

function str(p: Record<string, Object>, snake: string, camel: string, fallback: string = ''): string {
  return String(pick(p, snake, camel, fallback));
}

function num(p: Record<string, Object>, snake: string, camel: string, fallback: number = 0): number {
  return Number(pick(p, snake, camel, fallback));
}

function bool(p: Record<string, Object>, snake: string, camel: string, fallback: boolean = false): boolean {
  return pick(p, snake, camel, fallback) === true;
}

function toBucket(entityType: string, payload: object): relationalStore.ValuesBucket | null {
  const p = payload as Record<string, Object>;
  if (entityType === 'user') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'display_name': str(p, 'display_name', 'displayName'),
      'role': str(p, 'role', 'role', 'member'),
      'updated_at': str(p, 'updated_at', 'updatedAt')
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'expense') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'owner_id': str(p, 'owner_id', 'ownerId'),
      'amount_cents': num(p, 'amount_cents', 'amountCents'),
      'category_id': str(p, 'category_id', 'categoryId'),
      'payment_method_id': str(p, 'payment_method_id', 'paymentMethodId'),
      'spend_date': str(p, 'spend_date', 'spendDate'),
      'posting_date': str(p, 'posting_date', 'postingDate'),
      'repayment_date': str(p, 'repayment_date', 'repaymentDate'),
      'note': str(p, 'note', 'note'),
      'source': str(p, 'source', 'source', 'manual'),
      'updated_at': str(p, 'updated_at', 'updatedAt', new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'category') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'parent_id': str(p, 'parent_id', 'parentId'),
      'name': str(p, 'name', 'name'),
      'depth': num(p, 'depth', 'depth', 1),
      'icon': str(p, 'icon', 'icon'),
      'color': str(p, 'color', 'color'),
      'sort_order': num(p, 'sort_order', 'sortOrder'),
      'is_enabled': bool(p, 'is_enabled', 'isEnabled', true) ? 1 : 0
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'payment_method') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'name': str(p, 'name', 'name'),
      'type': str(p, 'type', 'type', 'cash'),
      'icon': str(p, 'icon', 'icon'),
      'billing_day': num(p, 'billing_day', 'billingDay'),
      'repayment_day': num(p, 'repayment_day', 'repaymentDay'),
      'is_enabled': bool(p, 'is_enabled', 'isEnabled', true) ? 1 : 0,
      'sort_order': num(p, 'sort_order', 'sortOrder')
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'plan') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'name': str(p, 'name', 'name'),
      'category_id': str(p, 'category_id', 'categoryId'),
      'payment_method_id': str(p, 'payment_method_id', 'paymentMethodId'),
      'amount_cents': num(p, 'amount_cents', 'amountCents'),
      'total_amount_cents': num(p, 'total_amount_cents', 'totalAmountCents'),
      'purchase_date': str(p, 'purchase_date', 'purchaseDate'),
      'first_due_date': str(p, 'first_due_date', 'firstDueDate'),
      'remind_days_before': num(p, 'remind_days_before', 'remindDaysBefore', 3),
      'auto_post': bool(p, 'auto_post', 'autoPost') ? 1 : 0,
      'source': str(p, 'source', 'source', 'manual'),
      'state': str(p, 'state', 'state', 'active'),
      'note': str(p, 'note', 'note'),
      'updated_at': str(p, 'updated_at', 'updatedAt', new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  if (entityType === 'plan_todo') {
    const bucket: relationalStore.ValuesBucket = {
      'id': str(p, 'id', 'id'),
      'plan_id': str(p, 'plan_id', 'planId'),
      // plan_name 是冗余列：服务端 payload 不带它，读取时一律 JOIN plans 取真名
      'plan_name': str(p, 'plan_name', 'planName'),
      'period_seq': num(p, 'period_seq', 'periodSeq'),
      'amount_cents': num(p, 'amount_cents', 'amountCents'),
      'repayment_date': str(p, 'repayment_date', 'repaymentDate'),
      'status': str(p, 'status', 'status', 'pending'),
      'will_auto_post': bool(p, 'will_auto_post', 'willAutoPost') ? 1 : 0,
      'expense_id': str(p, 'expense_id', 'expenseId'),
      'posted_date': str(p, 'posted_date', 'postedDate'),
      'updated_at': str(p, 'updated_at', 'updatedAt', new Date().toISOString())
    };
    return String(bucket['id']) === '' ? null : bucket;
  }
  return null;
}
