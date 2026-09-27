import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { planTodos as planTodosApi, plans as plansApi, type Plan, type PlanTodo } from '@/api';
import { todayLocal } from '@/utils/dates';

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
    plans.value = (await plansApi.list()).plans;
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
    const result = await planTodosApi.list({
      today,
      status: 'pending',
      remindBefore: today,
    });

    dueTodos.value = result.todos;
    return result.settled;
  }

  async function refresh(): Promise<number> {
    loading.value = true;
    error.value = null;

    try {
      const settled = await loadDueTodos();
      await loadPlans();
      return settled;
    } catch (err) {
      error.value = err instanceof Error ? err.message : '计划数据加载失败';
      throw err;
    } finally {
      loading.value = false;
    }
  }

  async function confirmTodo(todoId: string, spendDate?: string): Promise<void> {
    await planTodosApi.confirm(todoId, spendDate);
    await refresh();
  }

  async function skipTodo(todoId: string): Promise<void> {
    await planTodosApi.skip(todoId);
    await refresh();
  }

  async function endPlan(planId: string): Promise<void> {
    await plansApi.end(planId);
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
    endPlan,
  };
});
