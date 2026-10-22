import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  getCachedCategories,
  getCachedExpenses,
  getCachedPaymentMethods,
  getOutboxItems,
  isIdbSupported,
  type OutboxItem,
} from '../src/utils/idb.ts';
import { isUlid, ulid } from '../src/utils/ulid.ts';

describe('客户端离线存储与同步基础机制', () => {
  test('Node CLI 环境下 isIdbSupported 安全判定为 false', () => {
    assert.equal(isIdbSupported(), false);
  });

  test('非浏览器环境下 IndexedDB 驱动安全降级，不抛出未捕获异常', async () => {
    const cats = await getCachedCategories();
    assert.deepEqual(cats, []);

    const pms = await getCachedPaymentMethods();
    assert.deepEqual(pms, []);

    const expenses = await getCachedExpenses();
    assert.deepEqual(expenses, []);

    const outbox = await getOutboxItems();
    assert.deepEqual(outbox, []);
  });

  test('Outbox 离线待发送项结构支持全动作集合（create/update/delete/confirm/skip/ack）', () => {
    const expenseId = ulid();
    const outboxId = ulid();
    const actions: OutboxItem['action'][] = [
      'create_expense',
      'update_expense',
      'delete_expense',
      'confirm_todo',
      'skip_todo',
      'ack_todo',
    ];

    for (const action of actions) {
      const item: OutboxItem = {
        id: outboxId,
        action,
        entityId: expenseId,
        payload: { id: expenseId },
        createdAt: new Date().toISOString(),
        retryCount: 0,
      };
      assert.ok(isUlid(item.id));
      assert.equal(item.action, action);
      assert.equal(item.retryCount, 0);
    }
  });

  test('Outbox 离线待发送项支持修改支出与待办确认的 payload 规范', () => {
    const expenseId = ulid();
    const updateItem: OutboxItem = {
      id: ulid(),
      action: 'update_expense',
      entityId: expenseId,
      payload: {
        id: expenseId,
        amountCents: 5200,
        note: '调整后的聚餐支出',
      },
      createdAt: new Date().toISOString(),
      retryCount: 0,
    };
    assert.equal(updateItem.payload.amountCents, 5200);

    const todoItem: OutboxItem = {
      id: ulid(),
      action: 'confirm_todo',
      entityId: 'todo_123',
      payload: {
        id: 'todo_123',
        spendDate: '2026-09-30',
      },
      createdAt: new Date().toISOString(),
      retryCount: 0,
    };
    assert.equal(todoItem.payload.spendDate, '2026-09-30');
  });
});
