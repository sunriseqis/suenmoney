<script setup lang="ts">
/**
 * 待办卡片：确认入账 / 跳过。
 *
 * 仪表盘与计划页都要用，所以抽成组件 —— 两处各写一遍的话，
 * 「逾期时要先选实际付款日」这种细节迟早只在一边生效。
 *
 * 逾期才让选日期：没逾期时按还款日直接入账，少一次交互。
 * 选日期只影响记录上的实际付款日，**不改报表月份归属**（归属以计划里的还款日为准）。
 *
 * 配色由 utils/urgency.ts 统一决定，本组件不自己挑颜色 ——
 * 否则「本月待还」与这里很快就会出现两套紧急度口径。
 */
import { computed, ref } from 'vue';

import { ApiError, type PlanTodo } from '@/api';
import { usePlansStore } from '@/stores/plans';
import { formatMonthDay } from '@/utils/dates';
import { formatYuan } from '@/utils/money';
import {
  URGENCY_ACTION,
  URGENCY_BAR,
  URGENCY_CARD,
  URGENCY_META,
  urgencyLabel,
  urgencyOf,
} from '@/utils/urgency';

const props = defineProps<{ todo: PlanTodo }>();
const emit = defineEmits<{ changed: [] }>();

const plansStore = usePlansStore();

const busy = ref(false);
const errorMessage = ref<string | null>(null);
const choosingDate = ref(false);
const chosenDate = ref('');

const urgency = computed(() => urgencyOf(props.todo.repaymentDate));
const overdue = computed(() => urgency.value === 'overdue');
const dueLabel = computed(() => urgencyLabel(props.todo.repaymentDate));

function report(error: unknown, fallback: string): void {
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
}

function start(): void {
  errorMessage.value = null;

  if (!overdue.value) {
    void confirm(undefined);
    return;
  }

  choosingDate.value = true;
  chosenDate.value = props.todo.repaymentDate;
}

async function confirm(spendDate: string | undefined): Promise<void> {
  if (busy.value) return;

  errorMessage.value = null;
  busy.value = true;

  try {
    await plansStore.confirmTodo(props.todo.id, spendDate);
    choosingDate.value = false;
    emit('changed');
  } catch (error) {
    report(error, '确认失败');
  } finally {
    busy.value = false;
  }
}

async function skip(): Promise<void> {
  if (busy.value) return;

  errorMessage.value = null;
  busy.value = true;

  try {
    await plansStore.skipTodo(props.todo.id);
    emit('changed');
  } catch (error) {
    report(error, '跳过失败');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div
    class="pop-in @container relative overflow-hidden rounded-md px-3.5 py-3 transition-transform duration-200 lg:hover:-translate-y-0.5"
    :class="URGENCY_CARD[urgency]"
  >
    <!--
      紧急度唯一的着色位置。纯装饰：紧急程度已经由下面的「已逾期 N 天」文字
      表达，所以对读屏器隐藏，避免重复播报。
    -->
    <span class="absolute inset-y-0 left-0 w-1" :class="URGENCY_BAR[urgency]" aria-hidden="true" />

    <div class="flex flex-col @min-[420px]:flex-row @min-[420px]:items-center @min-[420px]:gap-6">
      <div class="min-w-0 flex-1">
        <div class="flex items-baseline gap-3">
      <span class="min-w-0 flex-1">
        <span class="block truncate text-sm font-bold">
          {{ todo.planName }}
          <span class="font-normal">第 {{ todo.periodSeq }} 期</span>
        </span>
        <span class="block truncate text-xs" :class="URGENCY_META[urgency]">
          {{ formatMonthDay(todo.repaymentDate) }} 还款 · {{ dueLabel }}
        </span>
      </span>
      <span class="shrink-0 text-lg font-bold">{{ formatYuan(todo.amountCents) }}</span>
    </div>

    <p v-if="errorMessage !== null" class="mt-2 text-xs font-semibold text-danger-text">
      {{ errorMessage }}
    </p>

    <!-- 逾期：先选实际付款日 -->
    <div v-if="choosingDate" class="mt-2.5 rounded-sm bg-canvas p-3">
      <label class="label-cn" :for="`posted-${todo.id}`">实际付款日</label>
      <input
        :id="`posted-${todo.id}`"
        v-model="chosenDate"
        type="date"
        class="mt-1 w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
      />
      <p class="mt-1 text-xs leading-relaxed text-ink-muted">
        只记录「哪天实际付的」。这笔账仍算在
        {{ formatMonthDay(todo.repaymentDate) }} 所属的月份 ——
        补点确认不该挪动已经过去的报表。
      </p>
      <div class="mt-2.5 flex gap-2">
        <button
          type="button"
          :disabled="busy"
          class="flex-1 rounded-sm bg-primary-fill py-2 text-sm font-bold text-on-primary disabled:opacity-40"
          @click="confirm(chosenDate)"
        >
          确认入账
        </button>
        <button
          type="button"
          class="rounded-sm bg-surface px-3.5 py-2 text-sm font-semibold text-ink"
          @click="choosingDate = false"
        >
          取消
        </button>
      </div>
    </div>

          </div>

      <!--
        操作行限宽（max-w-sm = 384px ≈ 手机卡片的自然宽度）：
        只有 1 条待办时卡片是整行 ~1100px，不限宽的话 flex-1 的主按钮
        会变成 1000px 宽的怪东西。
        布局按**容器宽度**切换（@container + @min-[420px]），不能按视口（lg）：
        同一屏会同时存在两种卡宽 —— 3 张并排时每张只有 349px，
        1 张时是整行 1072px。用 lg 判断的话 3 张并排的窄卡会被塞进
        一行布局，标题和按钮全部挤断（实测踩过）。
        卡片 ≥420px：信息在左、操作在右；<420px：操作竖排在下 ——
        手机卡片和窄卡都走这条，而下方正是拇指的位置。
        注意不能让操作行自由伸缩：flex-1 在内容自适应的容器里会塌缩成 0，
        所以容器定宽 max-w-sm，让 flex-1 在这 384px 里拉伸。
      -->
      <div
        v-if="!choosingDate"
        class="mt-2.5 flex max-w-sm gap-2 @min-[420px]:mt-0 @min-[420px]:shrink-0"
      >
      <button
        type="button"
        :disabled="busy"
        class="flex-1 rounded-sm py-2 text-sm font-bold transition-transform duration-200 active:scale-95 disabled:opacity-40"
        :class="URGENCY_ACTION.primary"
        @click="start"
      >
        确认入账
      </button>
      <button
        type="button"
        :disabled="busy"
        class="rounded-sm px-3.5 py-2 text-sm font-semibold transition-colors duration-200 disabled:opacity-40"
        :class="URGENCY_ACTION.ghost"
        @click="skip"
      >
        跳过
      </button>
      </div>
    </div>
  </div>
</template>
