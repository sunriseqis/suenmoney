import { defineStore } from 'pinia';
import { ref } from 'vue';

import type { Expense } from '@/api/types';
import { useSyncStore } from './sync';

/**
 * 全局界面状态。
 *
 * 目前只有一个职责：**记账抽屉的开关**。
 *
 * 为什么放在 store 而不是 App.vue 的局部状态：底部导航栏（在 App.vue 里）
 * 和流水列表（在 LedgerView 里）都要能打开它，而其中一个在另一个的渲染树
 * 之外。用 store 比一层层往上传事件简洁得多。
 */
export const useUiStore = defineStore('ui', () => {
  const sheetOpen = ref(false);
  /** 非空 = 编辑该记录；为空 = 新建 */
  const editingExpense = ref<Expense | null>(null);

  /**
   * 数据版本号。记账抽屉保存成功后自增。
   *
   * 视图监听它来决定要不要重新拉数据 —— 各页面之间的刷新时机不同
   * （仪表盘要刷新报表与流水、流水页只刷新列表），所以这里只发信号，
   * 由每个视图决定刷新什么，而不是由抽屉去挨个通知。
   */
  const dataVersion = ref(0);

  function openCreate(): void {
    editingExpense.value = null;
    sheetOpen.value = true;
  }

  function openEdit(expense: Expense): void {
    editingExpense.value = expense;
    sheetOpen.value = true;
  }

  function closeSheet(): void {
    sheetOpen.value = false;
    editingExpense.value = null;
  }

  function markDataChanged(): void {
    dataVersion.value += 1;
    try {
      const syncStore = useSyncStore();
      syncStore.scheduleSync(300);
    } catch {
      // 忽略 Pinia 未就绪阶段的调用
    }
  }

  return {
    sheetOpen,
    editingExpense,
    dataVersion,
    openCreate,
    openEdit,
    closeSheet,
    markDataChanged,
  };
});
