import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { decidePlacement, type PlacementInput } from '../src/utils/category-placement.ts';

function input(over: Partial<PlacementInput> = {}): PlacementInput {
  return {
    parent: '',
    child: '',
    knownChildToParent: new Map(),
    knownRoots: new Set(),
    knownChildren: new Set(),
    ...over,
  };
}

describe('decidePlacement', () => {
  test('只有二级名，且已知是某一级下的二级 → existing 认领', () => {
    const r = decidePlacement(
      input({ parent: '堂食外卖', knownChildren: new Set(['堂食外卖']) }),
    );
    assert.deepEqual(r, { kind: 'existing', categoryName: '堂食外卖' });
  });

  test('叶子名有父级证据 → createChild 挂到证据给出的父下', () => {
    const r = decidePlacement(
      input({
        parent: '日用百货',
        knownChildToParent: new Map([['日用百货', '生活日用']]),
      }),
    );
    assert.deepEqual(r, { kind: 'createChild', parentName: '生活日用', childName: '日用百货' });
  });

  test('完全陌生名 → createRoot 兜底', () => {
    const r = decidePlacement(input({ parent: '从没见过的名字' }));
    assert.deepEqual(r, { kind: 'createRoot', name: '从没见过的名字' });
  });

  test('同时有一级与二级 → createChild', () => {
    const r = decidePlacement(input({ parent: '餐饮美食', child: '堂食外卖' }));
    assert.deepEqual(r, { kind: 'createChild', parentName: '餐饮美食', childName: '堂食外卖' });
  });

  test('已知一级不被误判为二级 → existing', () => {
    // 名字同时在 knownRoots 与被污染的 knownChildToParent 里时，应优先认领为已有分类
    const r = decidePlacement(
      input({
        parent: '餐饮美食',
        knownRoots: new Set(['餐饮美食']),
        knownChildToParent: new Map([['餐饮美食', '别的父']]),
      }),
    );
    assert.deepEqual(r, { kind: 'existing', categoryName: '餐饮美食' });
  });

  test('只有 child（parent 为空）且有父级证据 → createChild', () => {
    const r = decidePlacement(
      input({
        child: '堂食外卖',
        knownChildToParent: new Map([['堂食外卖', '餐饮美食']]),
      }),
    );
    assert.deepEqual(r, { kind: 'createChild', parentName: '餐饮美食', childName: '堂食外卖' });
  });
});
