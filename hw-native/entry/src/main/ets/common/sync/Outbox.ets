/**
 * 离线写入队列（H7 · B 档）。
 *
 * 语义照 Web 的 `web/src/utils/idb.ts` + `web/src/stores/sync.ts`，不重新发明：
 *   - 八种动作：create/update/delete_expense、confirm/skip/ack/revert/restore_todo
 *   - 重试 3 次，退避 5s / 10s / 30s
 *   - 超限进死信，**界面上必须可见**（静默丢弃是最坏的：用户以为记上了）
 *
 * 为什么队列而不是「失败就重发」：断网可能持续很久，内存里的重试会在杀进程后丢光；
 * 落库才能保证「关掉 App 再打开，那三笔还在队列里」。
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from '../store/Db';

export type OutboxAction =
  | 'create_expense'
  | 'update_expense'
  | 'delete_expense'
  | 'confirm_todo'
  | 'skip_todo'
  | 'ack_todo'
  | 'revert_todo'
  | 'restore_todo';

/** 重试上限与退避（毫秒）。与 Web 的 OUTBOX_MAX_RETRY / 5s·10s·30s 一致 */
export const OUTBOX_MAX_RETRY = 3;
export const OUTBOX_BACKOFF_MS: number[] = [5000, 10000, 30000];

export interface OutboxEntry {
  id: string;
  action: OutboxAction;
  entityId: string;
  /** JSON 字符串（原样回放给服务端） */
  payload: string;
  createdAt: string;
  retryCount: number;
  lastError: string;
}

export class Outbox {
  /** 入队（id 用时间戳 + 计数，避免依赖 crypto） */
  static async enqueue(action: OutboxAction, entityId: string, payload: string): Promise<void> {
    const store = Db.get();
    const bucket: relationalStore.ValuesBucket = {
      'id': `${Date.now()}-${Math.round(Math.random() * 1e6)}`,
      'action': action,
      'entity_id': entityId,
      'payload': payload,
      'created_at': new Date().toISOString(),
      'retry_count': 0,
      'last_error': ''
    };
    await store.insert('outbox', bucket);
  }

  /** 待发送（按入队顺序，保证同一实体的操作不乱序） */
  static async pending(): Promise<OutboxEntry[]> {
    return Outbox.query('retry_count < ?', [OUTBOX_MAX_RETRY]);
  }

  /** 死信：重试用尽，必须让用户看见 */
  static async deadLetters(): Promise<OutboxEntry[]> {
    return Outbox.query('retry_count >= ?', [OUTBOX_MAX_RETRY]);
  }

  static async pendingCount(): Promise<number> {
    return (await Outbox.pending()).length;
  }

  /** 成功回放后删除 */
  static async remove(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const store = Db.get();
    for (const id of ids) {
      await store.executeSql('DELETE FROM outbox WHERE id = ?', [id]);
    }
  }

  /** 失败：重试计数 +1 并记下原因（到上限后自然成为死信） */
  static async markFailed(id: string, error: string): Promise<void> {
    const store = Db.get();
    await store.executeSql(
      'UPDATE outbox SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id]
    );
  }

  /** 死信重投：清零计数（用户点「重试」时） */
  static async retryDeadLetters(): Promise<void> {
    const store = Db.get();
    await store.executeSql('UPDATE outbox SET retry_count = 0, last_error = ? WHERE retry_count >= ?', ['', OUTBOX_MAX_RETRY]);
  }

  private static async query(where: string, args: relationalStore.ValueType[]): Promise<OutboxEntry[]> {
    const store = Db.get();
    const rs = await store.querySql(`SELECT * FROM outbox WHERE ${where} ORDER BY created_at ASC`, args);
    const out: OutboxEntry[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        action: rs.getString(rs.getColumnIndex('action')) as OutboxAction,
        entityId: rs.getString(rs.getColumnIndex('entity_id')),
        payload: rs.getString(rs.getColumnIndex('payload')),
        createdAt: rs.getString(rs.getColumnIndex('created_at')),
        retryCount: rs.getLong(rs.getColumnIndex('retry_count')),
        lastError: rs.getString(rs.getColumnIndex('last_error'))
      });
    }
    rs.close();
    return out;
  }
}
