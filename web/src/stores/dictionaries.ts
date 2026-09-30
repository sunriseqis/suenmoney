import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { categories as categoriesApi, paymentMethods as paymentMethodsApi } from '@/api';
import type { Category, PaymentMethod } from '@/api/types';
import {
  allocateCategoryColors,
  deriveCategoryColor,
  parseCategoryColor,
} from '@/utils/category-colors';
import {
  getCachedCategories,
  getCachedPaymentMethods,
  saveCachedCategories,
  saveCachedPaymentMethods,
} from '@/utils/idb';

/**
 * 共享字典：分类与支付方式。
 *
 * 这两份数据被记账抽屉、流水筛选、报表页、设置页同时用到，所以集中缓存 ——
 * 既避免每次打开抽屉都重新拉一遍，也保证「刚在设置页新建的分类」
 * 立刻出现在记账的选择列表里（同一个 store 实例 = 同一份真相）。
 *
 * 注意列表里**包含已停用的项**：历史记录还要靠它显示分类名与支付方式名，
 * 只是它们不会被放进「新记账」的选择列表。
 */
export const useDictionariesStore = defineStore('dictionaries', () => {
  const categories = ref<Category[]>([]);
  const paymentMethods = ref<PaymentMethod[]>([]);
  const loading = ref(false);
  const loaded = ref(false);
  const error = ref<string | null>(null);

  /** 一级分类（仅启用的），按服务端给出的 sortOrder 顺序 */
  const rootCategories = computed(() => categories.value.filter((item) => item.isEnabled));

  /** 可用于新记账的支付方式 */
  const usablePaymentMethods = computed(() =>
    paymentMethods.value.filter((item) => item.isEnabled),
  );

  /**
   * 取某个一级分类下「实际可选」的分类。
   *
   * 有子分类就以子分类为准（一二级都可选会让用户困惑：选了「餐饮」到底
   * 记在哪？）；没有任何子分类时，一级分类自己就是可选项 —— 比如「其他」。
   */
  function selectableChildren(root: Category): Category[] {
    const enabled = root.children.filter((item) => item.isEnabled);
    return enabled.length > 0 ? enabled : [root];
  }

  function findCategory(id: string | null): Category | null {
    if (id === null) return null;
    for (const root of categories.value) {
      if (root.id === id) return root;
      for (const child of root.children) {
        if (child.id === id) return child;
      }
    }
    return null;
  }

  function findPaymentMethod(id: string | null): PaymentMethod | null {
    if (id === null) return null;
    return paymentMethods.value.find((item) => item.id === id) ?? null;
  }

  /**
   * 一级分类全局颜色分配表。
   *
   * 核心规则：
   * 1. 显式指定的色号（1..16）优先保留并占位。
   * 2. 未指定（即「自动」）的一级分类，依序从 1..16 中挑选尚未被占用的色号。
   *    严格保证每一个自动分类分配到互不相同的空闲色号，直到 16 色用尽。
   * 3. 二级分类自动继承对应一级分类的颜色。
   */
  const categoryColorMap = computed(() => {
    const roots = categories.value.filter((c) => c.parentId === null);
    const { idMap, usedColors, availablePool } = allocateCategoryColors(roots);
    const nameMap = new Map<string, number>();

    for (const root of roots) {
      const rootColor = idMap.get(root.id) ?? 1;
      nameMap.set(root.name, rootColor);
      for (const child of root.children) {
        idMap.set(child.id, rootColor);
        nameMap.set(child.name, rootColor);
      }
    }

    return { idMap, nameMap, usedColors, availablePool };
  });

  /** 一级分类已占用的颜色号（用于推导时避开重复色） */
  const usedRootColors = computed(() => categoryColorMap.value.usedColors);

  /**
   * 获取某个分类的最终解析颜色（1..16）。
   * 优先顺序：显式设置值 > 分类 ID 全局映射 > 分类名称全局映射 > 可用池空闲色 > 散列兜底。
   */
  function colorOf(categoryId?: string | null, name?: string | null, explicitColor?: string | null): number {
    const explicit = parseCategoryColor(explicitColor);
    if (explicit !== null) return explicit;

    if (categoryId && categoryColorMap.value.idMap.has(categoryId)) {
      return categoryColorMap.value.idMap.get(categoryId)!;
    }

    if (name && categoryColorMap.value.nameMap.has(name)) {
      return categoryColorMap.value.nameMap.get(name)!;
    }

    if (categoryColorMap.value.availablePool.length > 0) {
      return categoryColorMap.value.availablePool[0]!;
    }

    return name ? deriveCategoryColor(name) : 1;
  }

  /**
   * 为新建或编辑中的分类计算其选择「自动」时应当分配的颜色。
   * 严格复用 allocateCategoryColors 进行纯函数式模拟：
   * 保证「弹窗中选定自动显示的颜色 === 保存后列表中渲染的颜色」，且各分类互不冲突。
   */
  function previewAutoColor(editingCategoryId?: string | null, draftName?: string): number {
    const roots = categories.value.filter((c) => c.parentId === null);

    if (editingCategoryId) {
      // 编辑已有分类：模拟如果该分类设为「自动（color: ''）」时系统会分配的颜色
      const simulatedRoots = roots.map((r) =>
        r.id === editingCategoryId ? { ...r, color: '' } : r,
      );
      const { idMap } = allocateCategoryColors(simulatedRoots);
      return idMap.get(editingCategoryId) ?? 1;
    }

    // 新建分类：模拟向当前分类列表中追加一条自动分类时分配的颜色
    const simulatedRoots = [
      ...roots,
      { id: '__draft_new__', name: draftName ?? '', color: '' },
    ];
    const { idMap } = allocateCategoryColors(simulatedRoots);
    return idMap.get('__draft_new__') ?? 1;
  }

  /**
   * 某个分类的「视觉身份」：图标 + 颜色。
   *
   * 规则：二级分类用**自己的图标**，但**颜色跟一级走** —— 用户给「餐饮」选的紫
   * 要落在它所有子分类上。合并成一处返回，是因为这条规则一旦在某个视图里漏掉，
   * 表现只是「这一页的颜色跟别处不一样」，不报错、也不容易被发现。
   *
   * 聚合结果（报表的分类桶）没有完整 Category 对象，那种场景继续走
   * `CategoryIcon` 的 name/color 入参，不用这里。
   */
  function visualOf(id: string | null): {
    name: string;
    icon: string;
    color: string;
    /** 参与颜色推导的名字 */
    colorName: string;
    /** 解析出的统一色号 (1..16) */
    colorIndex: number;
  } | null {
    const self = findCategory(id);
    if (self === null) return null;

    const source = self.parentId === null ? self : (findCategory(self.parentId) ?? self);
    const colorIndex = colorOf(source.id, source.name, source.color);
    return {
      name: self.name,
      icon: self.icon || source.icon,
      color: source.color,
      colorName: source.name,
      colorIndex,
    };
  }

  async function load(force = false): Promise<void> {
    if (loaded.value && !force) return;
    if (loading.value) return;

    // 离线优先：如果当前内存为空，先从 IndexedDB 瞬间填充，实现 0ms 秒开呈现
    if (categories.value.length === 0 || paymentMethods.value.length === 0) {
      try {
        const [cachedCats, cachedPms] = await Promise.all([
          getCachedCategories(),
          getCachedPaymentMethods(),
        ]);
        if (cachedCats.length > 0 && categories.value.length === 0) {
          categories.value = cachedCats;
        }
        if (cachedPms.length > 0 && paymentMethods.value.length === 0) {
          paymentMethods.value = cachedPms;
        }
        if (cachedCats.length > 0 || cachedPms.length > 0) {
          loaded.value = true;
        }
      } catch {
        // 忽略本地缓存读取异常
      }
    }

    loading.value = true;
    error.value = null;

    try {
      // 两个请求互不依赖，并行发出
      const [categoryResult, methodResult] = await Promise.all([
        categoriesApi.list(),
        paymentMethodsApi.list(),
      ]);
      categories.value = categoryResult.categories;
      paymentMethods.value = methodResult.paymentMethods;
      loaded.value = true;

      // 异步持久化到本地 IndexedDB
      void saveCachedCategories(categoryResult.categories);
      void saveCachedPaymentMethods(methodResult.paymentMethods);
    } catch (err) {
      // 如果本地已经有可用缓存，静默降级，不阻断界面使用
      if (categories.value.length > 0 && paymentMethods.value.length > 0) {
        return;
      }
      error.value = err instanceof Error ? err.message : '字典数据加载失败';
      throw err;
    } finally {
      loading.value = false;
    }
  }

  return {
    categories,
    paymentMethods,
    loading,
    loaded,
    error,
    rootCategories,
    usedRootColors,
    categoryColorMap,
    colorOf,
    previewAutoColor,
    usablePaymentMethods,
    selectableChildren,
    findCategory,
    findPaymentMethod,
    visualOf,
    load,
  };
});
