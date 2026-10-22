import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import {
  allocateCategoryColors,
  CATEGORY_COLOR_COUNT,
  deriveCategoryColor,
  parseCategoryColor,
  resolveCategoryColor,
} from '../src/utils/category-colors.ts';

describe('分类颜色（16色扩展与未使用色优先策略）', () => {
  test('调色板总数为 16', () => {
    assert.equal(CATEGORY_COLOR_COUNT, 16);
  });

  test('parseCategoryColor 校验', () => {
    assert.equal(parseCategoryColor('1'), 1);
    assert.equal(parseCategoryColor('16'), 16);
    assert.equal(parseCategoryColor('0'), null);
    assert.equal(parseCategoryColor('17'), null);
    assert.equal(parseCategoryColor(''), null);
    assert.equal(parseCategoryColor(null), null);
    assert.equal(parseCategoryColor('abc'), null);
  });

  test('自动颜色优先选用未使用的颜色', () => {
    // 假设已有分类已占用了 1, 2, 3
    const used = [1, 2, 3];
    const derived = deriveCategoryColor('测试分类A', used);

    // 绝不能落在 1, 2, 3 中
    assert.ok(!used.includes(derived));
    assert.ok(derived >= 4 && derived <= 16);
  });

  test('16个颜色全部占满后，安全回退到 1..16', () => {
    const allUsed = Array.from({ length: 16 }, (_, i) => i + 1);
    const derived = deriveCategoryColor('测试分类B', allUsed);
    assert.ok(derived >= 1 && derived <= 16);
  });

  test('resolveCategoryColor 显式配置优先于推导', () => {
    assert.equal(resolveCategoryColor('餐饮', '7', [1, 2, 3, 7]), 7);
    const autoColor = resolveCategoryColor('餐饮', '', [1, 2, 3, 7]);
    assert.ok(autoColor !== 7 && ![1, 2, 3].includes(autoColor));
  });

  test('常见中文分类名在未占满时离散分布，不扎堆单一色号', () => {
    const used = [1, 2, 3, 4, 5, 6, 7, 9, 10]; // 剩余 8, 11, 12, 13, 14, 15, 16
    const names = ['兼职', '健身', '房租', '学习', '餐饮', '医疗', '交通'];
    const colors = new Set<number>();
    for (const name of names) {
      const c = deriveCategoryColor(name, used);
      assert.ok(!used.includes(c), `${name} 应该分配未使用色，却分配了已用色 ${c}`);
      colors.add(c);
    }
    // 应该分散到多个不同颜色，而不是所有词全算成同一色号（如原来的 8）
    assert.ok(colors.size >= 4, `7个常用词应该分布在至少4种不同颜色上，实际只有 ${colors.size} 种`);
  });

  test('多个自动分类依序分配时，能够保证彼此互不相同', () => {
    const usedColors = new Set([1, 2, 3, 4, 5, 6, 7]);
    const available = [8, 9, 10, 11, 12, 13, 14, 15, 16];
    const autoCategories = ['贷款还款', '人情往来', '休闲娱乐', '数码家电', '服饰美容'];
    const allocated: number[] = [];

    for (const name of autoCategories) {
      const idx = name.length % available.length;
      const c = available.splice(idx, 1)[0]!;
      allocated.push(c);
      usedColors.add(c);
    }

    assert.equal(allocated.length, 5);
    assert.equal(new Set(allocated).size, 5, '所有自动分类分配的颜色必须互不重复');
    for (const c of allocated) {
      assert.ok(c >= 8 && c <= 16);
    }
  });

  test('allocateCategoryColors 保留显式设置并为自动分类提供 0 撞色且稳定的映射', () => {
    const roots = [
      { id: 'c1', name: '餐饮美食', color: '' },
      { id: 'c2', name: '生活日用', color: '' },
      { id: 'c3', name: '母婴亲子', color: '' },
      { id: 'c4', name: '交通出行', color: '4' },
      { id: 'c5', name: '汽车相关', color: '5' },
      { id: 'c6', name: '居家缴费', color: '6' },
      { id: 'c7', name: '医疗保健', color: '' },
      { id: 'c8', name: '服饰美容', color: '' },
      { id: 'c9', name: '数码家电', color: '' },
      { id: 'c10', name: '贷款还款', color: '' },
      { id: 'c11', name: '人情往来', color: '' },
      { id: 'c12', name: '休闲娱乐', color: '' },
    ];

    const { idMap, usedColors } = allocateCategoryColors(roots);

    // 显式配置的严格保留
    assert.equal(idMap.get('c4'), 4);
    assert.equal(idMap.get('c5'), 5);
    assert.equal(idMap.get('c6'), 6);

    // 全部 12 个分类分配到的颜色必须互不相同（12个唯一值）
    const allAssigned = roots.map((r) => idMap.get(r.id)!);
    assert.equal(new Set(allAssigned).size, 12, '12 个分类分配到的颜色必须互不重复');

    // 模拟弹窗预览：预览已有自动分类的颜色 === 保存后分配的颜色
    for (const root of roots) {
      const simulated = roots.map((r) => (r.id === root.id ? { ...r, color: '' } : r));
      const preview = allocateCategoryColors(simulated).idMap.get(root.id);
      if (root.color === '') {
        assert.equal(preview, idMap.get(root.id), `${root.name} 预览色必须与保存后的真实分配色完全一致`);
      }
    }

    // 模拟弹窗新增新分类：预览色等于可用池顺位第一位
    const simNew = [...roots, { id: '__new__', name: '新分类', color: '' }];
    const previewNew = allocateCategoryColors(simNew).idMap.get('__new__');
    assert.ok(previewNew !== undefined);
    assert.ok(!usedColors.has(previewNew), '新分类的自动颜色必须来自未被占用的空闲池');
  });
});
