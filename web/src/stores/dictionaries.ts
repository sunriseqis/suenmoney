import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { categories as categoriesApi, paymentMethods as paymentMethodsApi } from '@/api';
import type { Category, PaymentMethod } from '@/api/types';

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
  } | null {
    const self = findCategory(id);
    if (self === null) return null;

    const source = self.parentId === null ? self : (findCategory(self.parentId) ?? self);
    return { name: self.name, icon: self.icon, color: source.color, colorName: source.name };
  }

  async function load(force = false): Promise<void> {
    if (loaded.value && !force) return;
    if (loading.value) return;

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
    } catch (err) {
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
    usablePaymentMethods,
    selectableChildren,
    findCategory,
    findPaymentMethod,
    visualOf,
    load,
  };
});
