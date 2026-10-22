/**
 * 本地草稿存取的单元测试。
 *
 * 这些函数错起来**不会报错，只会静默丢数据**：写失败被吞掉、读失败返回 null、
 * 过期不清理—— 界面表现是「偶尔不恢复」，事后极难定位。
 * 所以这里覆盖的是存储形状、过期边界、脏数据容错与上下文隔离四类。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  clearDraft,
  DRAFT_TTL_MS,
  draftKey,
  isDraftMeaningful,
  readDraft,
  writeDraft,
  type DraftStorage,
} from '../src/utils/draft.ts';

/** 内存版 storage：既是浏览器 localStorage 的替身，也是「存储抛异常」的注入点。 */
function fakeStorage(): DraftStorage & { map: Map<string, string>; failOnWrite?: boolean } {
  const map = new Map<string, string>();
  return {
    map,
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => {
      map.set(key, value);
    },
    removeItem: (key) => {
      map.delete(key);
    },
  };
}

describe('draftKey', () => {
  test('按用途与上下文分桶，两个上下文互不覆盖', () => {
    assert.equal(draftKey('expense', 'new'), 'suenmoney:draft:expense:new');
    assert.notEqual(draftKey('expense', 'new'), draftKey('expense', 'edit:01ABC'));
  });
});

describe('readDraft / writeDraft', () => {
  test('写入后能原样读回', () => {
    const storage = fakeStorage();
    writeDraft('expense', 'new', { totalCents: 1234, note: '菜' }, { storage, now: 1000 });

    assert.deepEqual(readDraft('expense', 'new', { storage, now: 1000 }), {
      totalCents: 1234,
      note: '菜',
    });
  });

  test('不同上下文的草稿互不干扰', () => {
    const storage = fakeStorage();
    writeDraft('expense', 'new', { totalCents: 100 }, { storage, now: 1000 });
    writeDraft('expense', 'edit:01ABC', { totalCents: 200 }, { storage, now: 1000 });

    assert.deepEqual(readDraft('expense', 'new', { storage, now: 1000 }), { totalCents: 100 });
    assert.deepEqual(readDraft('expense', 'edit:01ABC', { storage, now: 1000 }), { totalCents: 200 });
  });

  test('没有草稿时返回 null', () => {
    assert.equal(readDraft('expense', 'new', { storage: fakeStorage() }), null);
  });

  test('超过 24 小时视为过期，且过期数据被清掉', () => {
    const storage = fakeStorage();
    writeDraft('expense', 'new', { totalCents: 100 }, { storage, now: 0 });

    // 恰好 24 小时整：还在有效期内（边界含等号，避免同一秒既生又死）
    assert.deepEqual(readDraft('expense', 'new', { storage, now: DRAFT_TTL_MS }), { totalCents: 100 });

    writeDraft('expense', 'new', { totalCents: 100 }, { storage, now: 0 });
    assert.equal(readDraft('expense', 'new', { storage, now: DRAFT_TTL_MS + 1 }), null);
    assert.equal(storage.getItem(draftKey('expense', 'new')), null);
  });

  test('脏数据（非法 JSON / 版本不符 / 结构缺字段）一律当没有，并清掉坏条目', () => {
    const storage = fakeStorage();

    storage.setItem(draftKey('expense', 'new'), '{{{不是 JSON');
    assert.equal(readDraft('expense', 'new', { storage }), null);
    assert.equal(storage.getItem(draftKey('expense', 'new')), null);

    storage.setItem(draftKey('expense', 'new'), JSON.stringify({ v: 999, savedAt: Date.now(), data: {} }));
    assert.equal(readDraft('expense', 'new', { storage }), null);

    storage.setItem(draftKey('expense', 'new'), JSON.stringify({ v: 1, data: {} }));
    assert.equal(readDraft('expense', 'new', { storage }), null);
  });

  test('storage 为 null（Node / 隐私模式）时读写都安全退化，不抛异常', () => {
    writeDraft('expense', 'new', { totalCents: 1 }, { storage: null });
    assert.equal(readDraft('expense', 'new', { storage: null }), null);
    clearDraft('expense', 'new', { storage: null });
  });

  test('storage 抛异常（配额满 / 隐私模式）时不外泄异常', () => {
    const hostile: DraftStorage = {
      getItem: () => {
        throw new Error('denied');
      },
      setItem: () => {
        throw new Error('QuotaExceeded');
      },
      removeItem: () => {
        throw new Error('denied');
      },
    };

    writeDraft('expense', 'new', { totalCents: 1 }, { storage: hostile });
    assert.equal(readDraft('expense', 'new', { storage: hostile }), null);
    clearDraft('expense', 'new', { storage: hostile });
  });
});

describe('clearDraft', () => {
  test('清除后读不到，提交成功后调用它才不会弹出已入账的草稿', () => {
    const storage = fakeStorage();
    writeDraft('expense', 'new', { totalCents: 100 }, { storage, now: 0 });
    clearDraft('expense', 'new', { storage });
    assert.equal(readDraft('expense', 'new', { storage, now: 0 }), null);
  });
});

describe('isDraftMeaningful', () => {
  test('空表单不算“有东西”，否则每次打开记账都会弹一次无意义的恢复提示', () => {
    assert.equal(isDraftMeaningful(null), false);
    assert.equal(isDraftMeaningful({ totalCents: 0, note: '' }), false);
    assert.equal(isDraftMeaningful({ totalCents: 0, note: '   ' }), false);
  });

  test('有金额 / 有备注 / 改过分类或支付方式才算', () => {
    assert.equal(isDraftMeaningful({ totalCents: 1 }), true);
    assert.equal(isDraftMeaningful({ note: '菜' }), true);
    assert.equal(isDraftMeaningful({ categoryChanged: true }), true);
    assert.equal(isDraftMeaningful({ paymentMethodChanged: true }), true);
  });
});