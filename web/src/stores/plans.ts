import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { ApiError, planTodos as planTodosApi, plans as plansApi, type Plan, type PlanTodo } from '@/api';
import {
  getCachedPlans,
  getCachedPlanTodos,
  isIdbSupported,
  saveCachedPlans,
  saveCachedPlanTodos,
} from '@/utils/idb';
import { todayLocal } from '@/utils/dates';
import { useSyncStore } from './sync';
import { useUiStore } from './ui';

/**
 * 计划与其待办。
 *
 * 仪表盘与计划页共用同一份数据 —— 因为「该处理了」的待办会出现在两处，
 * 各自维护一份必然会出现在首页确认完、切到计划页还显示未确认的情况。
 */
export const usePlansStore = defineStore('plans', () => {
  const plans = ref<Plan[]>([]);

  /**
   * 提醒日已到的待办（含逾期）。
   *
   * 「已到提醒日」而不是「全部待办」：房贷 30 年有 360 期，
   * 把没到提醒时间的都铺出来只会淹没真正需要现在处理的那几条。
   */
  const dueTodos = ref<PlanTodo[]>([]);

  const loading = ref(false);
  const error = ref<string | null>(null);

  const activePlans = computed(() => plans.value.filter((plan) => plan.state === 'active'));
  const endedPlans = computed(() => plans.value.filter((plan) => plan.state === 'ended'));

  async function loadPlans(): Promise<void> {
    try {
      const result = await plansApi.list();
      plans.value = result.plans;
      void saveCachedPlans(result.plans);
    } catch (err) {
      if (isIdbSupported()) {
        const cached = await getCachedPlans();
        if (cached.length > 0) {
          plans.value = cached;
          return;
        }
      }
      if (err instanceof ApiError && err.status === 0) {
        return;
      }
      throw err;
    }
  }

  /**
   * 拉取「该处理了」的待办。
   *
   * ⚠️ 这个调用**不只是读**：传 `today` 会让服务端先把到期的自动入账待办结算掉，
   * 所以它可能顺带产生新的支出记录。返回值里的 `settled` 就是这次结算了几笔，
   * 调用方据此决定要不要刷新报表。
   */
  async function loadDueTodos(): Promise<number> {
    const today = todayLocal();
    try {
      const result = await planTodosApi.list({
        today,
        status: 'pending',
        remindBefore: today,
        /**
         * 已点过「确认」的期次不再占位置。
         * 这是 `ack_at` 唯一的可见效果 —— 它不改任何业务状态（见 migration 003）。
         */
        hideAcked: true,
      });

      dueTodos.value = result.todos;
      void saveCachedPlanTodos(result.todos);
      return result.settled;
    } catch (err) {
      if (isIdbSupported()) {
        const cached = await getCachedPlanTodos('pending');
        if (cached.length > 0) {
          dueTodos.value = cached;
          return 0;
        }
      }
      if (err instanceof ApiError && err.status === 0) {
        return 0;
      }
      throw err;
    }
  }

  async function refresh(): Promise<number> {
    loading.value = true;
    error.value = null;

    try {
      const settled = await loadDueTodos();
      await loadPlans();
      return settled;
    } catch (err) {
      // 若已有缓存数据，网络异常时平滑静默，不红字阻断页面
      if (dueTodos.value.length > 0 || plans.value.length > 0) {
        return 0;
      }
      if (err instanceof ApiError && err.status === 0) {
        return 0;
      }
      error.value = err instanceof Error ? err.message : '计划数据加载失败';
      throw err;
    } finally {
      loading.value = false;
    }
  }

  async function confirmTodo(todoId: string, spendDate?: string): Promise<void> {
    const syncStore = useSyncStore();
    const ui = useUiStore();

    if (!syncStore.isOnline) {
      await syncStore.confirmOfflineTodo(todoId, spendDate);
      dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
      ui.markDataChanged();
      return;
    }

    try {
      await planTodosApi.confirm(todoId, spendDate);
      await refresh();
      ui.markDataChanged();
    } catch (err) {
      if (err instanceof ApiError && err.status === 0) {
        await syncStore.confirmOfflineTodo(todoId, spendDate);
        dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
        ui.markDataChanged();
        return;
      }
      throw err;
    }
  }

  async function skipTodo(todoId: string): Promise<void> {
    const syncStore = useSyncStore();
    const ui = useUiStore();

    if (!syncStore.isOnline) {
      await syncStore.skipOfflineTodo(todoId);
      dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
      ui.markDataChanged();
      return;
    }

    try {
      await planTodosApi.skip(todoId);
      await refresh();
      ui.markDataChanged();
    } catch (err) {
      if (err instanceof ApiError && err.status === 0) {
        await syncStore.skipOfflineTodo(todoId);
        dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
        ui.markDataChanged();
        return;
      }
      throw err;
    }
  }

  /**
   * 「我知道了」—— 只对 `willAutoPost === true` 的期次用。
   *
   * 它不产生任何账目，所以刷新之后那一条只是从列表里消失，
   * 报表数字**不该变**。若发现报表跟着变了，说明调用点用错了接口。
   */
  async function ackTodo(todoId: string): Promise<void> {
    const syncStore = useSyncStore();
    const ui = useUiStore();

    if (!syncStore.isOnline) {
      await syncStore.ackOfflineTodo(todoId);
      dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
      ui.markDataChanged();
      return;
    }

    try {
      await planTodosApi.ack(todoId);
      await refresh();
      ui.markDataChanged();
    } catch (err) {
      if (err instanceof ApiError && err.status === 0) {
        await syncStore.ackOfflineTodo(todoId);
        dueTodos.value = dueTodos.value.filter((t) => t.id !== todoId);
        ui.markDataChanged();
        return;
      }
      throw err;
    }
  }

  /** 撤销一次确认：撤掉该期的入账（支出软删），待办回到待办列表。离线可逆。 */
  async function revertTodo(todoId: string): Promise<void> {
    const syncStore = useSyncStore();
    const ui = useUiStore();

    if (!syncStore.isOnline) {
      await syncStore.revertOfflineTodo(todoId);
      await refresh();
      ui.markDataChanged();
      return;
    }

    try {
      await planTodosApi.revert(todoId);
      await refresh();
      ui.markDataChanged();
    } catch (err) {
      if (err instanceof ApiError && err.status === 0) {
        await syncStore.revertOfflineTodo(todoId);
        await refresh();
        ui.markDataChanged();
        return;
      }
      throw err;
    }
  }

  /** 恢复一个被跳过的期次。离线可逆。 */
  async function restoreTodo(todoId: string): Promise<void> {
    const syncStore = useSyncStore();
    const ui = useUiStore();

    if (!syncStore.isOnline) {
      await syncStore.restoreOfflineTodo(todoId);
      await refresh();
      ui.markDataChanged();
      return;
    }

    try {
      await planTodosApi.restore(todoId);
      await refresh();
      ui.markDataChanged();
    } catch (err) {
      if (err instanceof ApiError && err.status === 0) {
        await syncStore.restoreOfflineTodo(todoId);
        await refresh();
        ui.markDataChanged();
        return;
      }
      throw err;
    }
  }

  async function endPlan(planId: string): Promise<void> {
    await plansApi.end(planId);
    await refresh();
  }

  async function deletePlan(planId: string): Promise<void> {
    await plansApi.delete(planId);
    await refresh();
  }

  return {
    plans,
    dueTodos,
    loading,
    error,
    activePlans,
    endedPlans,
    refresh,
    loadPlans,
    loadDueTodos,
    confirmTodo,
    skipTodo,
    ackTodo,
    revertTodo,
    restoreTodo,
    endPlan,
    deletePlan,
  };
});
