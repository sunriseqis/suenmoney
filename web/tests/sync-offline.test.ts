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

  test('Outbox 离线待发送项结构符合协议规范', () => {
    const expenseId = ulid();
    const outboxId = ulid();
    const item: OutboxItem = {
      id: outboxId,
      action: 'create_expense',
      entityId: expenseId,
      payload: {
        id: expenseId,
        amountCents: 2500,
        categoryId: 'cat_food',
        paymentMethodId: 'pm_wechat',
        spendDate: '2026-09-29',
        note: '工作午餐',
      },
      createdAt: new Date().toISOString(),
      retryCount: 0,
    };

    assert.ok(isUlid(item.id));
    assert.ok(isUlid(item.entityId));
    assert.equal(item.action, 'create_expense');
    assert.equal(item.payload.amountCents, 2500);
    assert.equal(item.retryCount, 0);
  });
});
