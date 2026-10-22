<script setup lang="ts">
/**
 * 提醒条：一叠「要处理」的期次，收起时只占一行。
 *
 * ## 收起态只说一件事：**要不要我动手**
 *
 * 标题行右端那**一个染色的箭头**是整个提醒条的编码（`A25`）：
 *
 *   `--late`（红）  这一叠里有逾期
 *   `--manual`（黄）这一叠里有「不会自动入账」的，等你做决定
 *   `--none`（灰）  全都会自动入账，你什么都不用做
 *
 * 而**展开之后不再重复标记** —— 每条的紧急度由它自己的文字颜色说
 * （「明天到期」琥珀 /「逾期29天」红 /「10月2日到期」灰）。
 * 收起态答「要不要动手」，展开态答「具体哪条、多急」，各管一个层次。
 *
 * ## 默认收不收起，看屏幕
 *
 * 窄屏默认收起：首屏最贵的位置要留给「本月支出」，提醒一行足够。
 * 桌面默认展开：屏幕够高，而且鼠标点开一次就为了看明细，收起反而多一步。
 *
 * ## 撤销
 *
 * 滑动是**一次完成**的动作，没有第二次确认的机会，所以误触必须有退路：
 * 「入账」与「忽略」各留一条「撤销」（走 `revert` / `restore`）。
 * 「确认」（ack）不需要 —— 它不产生任何账目，没有东西可以被撤回来。
 */
import { computed, onUnmounted, ref } from 'vue';

import type { PlanTodo } from '@/api';
import ReminderRow from '@/components/ReminderRow.vue';
import { usePlansStore } from '@/stores/plans';
import { formatYuan } from '@/utils/money';
import { REMINDER_CHEV, reminderToneOf, type ReminderDone } from '@/utils/urgency';

const props = defineProps<{ todos: PlanTodo[] }>();
const emit = defineEmits<{ changed: [] }>();

const plansStore = usePlansStore();

/** 桌面默认展开、窄屏默认收起（见文件头） */
const expanded = ref(window.matchMedia('(min-width: 1024px)').matches);

const tone = computed(() => reminderToneOf(props.todos));

/* ---- 撤销 -------------------------------------------------------------- */

/** 只装**会改账目**的那两个动作；`ack` 不进这里 */
const undoable = ref<{ kind: Exclude<ReminderDone, 'ack'>; todo: PlanTodo } | null>(null);
const undoError = ref<string | null>(null);

let undoTimer: ReturnType<typeof setTimeout> | undefined;

function clearUndo(): void {
  undoable.value = null;
  undoError.value = null;
  if (undoTimer !== undefined) clearTimeout(undoTimer);
}

function onActed(payload: { kind: ReminderDone; todo: PlanTodo }): void {
  if (undoTimer !== undefined) clearTimeout(undoTimer);

  if (payload.kind === 'ack') {
    // 不产生账目，没有需要撤销的东西
    undoable.value = null;
  } else {
    undoable.value = { kind: payload.kind, todo: payload.todo };
    // 8 秒：够看清一句话，又不至于一直占着位置
    undoTimer = setTimeout(clearUndo, 8000);
  }

  undoError.value = null;
  emit('changed');
}

async function undo(): Promise<void> {
  const item = undoable.value;
  if (item === null) return;

  undoError.value = null;

  try {
    if (item.kind === 'confirm') await plansStore.revertTodo(item.todo.id);
    else await plansStore.restoreTodo(item.todo.id);

    clearUndo();
    emit('changed');
  } catch (error) {
    undoError.value = error instanceof Error ? error.message : '撤销失败';
  }
}

onUnmounted(() => {
  if (undoTimer !== undefined) clearTimeout(undoTimer);
});

/** 撤销条上那句话：说清「刚才发生了什么」，否则用户不知道自己在撤什么 */
const undoLabel = computed(() => {
  const item = undoable.value;
  if (item === null) return '';
  return item.kind === 'confirm'
    ? `已入账 ${formatYuan(item.todo.amountCents)}`
    : `已忽略 ${item.todo.periodSeq}期 · ${item.todo.planName}`;
});
</script>

<template>
  <section aria-label="处理提醒">
    <!--
      标题行。整行可点：收起态只有这一行高，点哪儿都该展开 ——
      让用户对着 12px 的字去瞄一个箭头，是没必要的精确度要求。
    -->
    <button
      type="button"
      class="reminder-head"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <span>处理提醒</span>
      <span aria-hidden="true">{{ todos.length }}</span>
      <span
        class="reminder-head__chev"
        :class="[REMINDER_CHEV[tone], expanded ? '' : 'reminder-head__chev--collapsed']"
        aria-hidden="true"
        >▾</span
      >
    </button>

    <!-- 撤销：8 秒后自行消失 -->
    <p
      v-if="undoable !== null"
      class="mt-2 flex items-center gap-2 rounded-sm bg-sunken px-3 py-2 text-xs"
    >
      <span class="min-w-0 flex-1 truncate text-ink-muted">{{ undoLabel }}</span>
      <button
        type="button"
        class="shrink-0 font-bold text-primary-text"
        @click="undo"
      >
        撤销
      </button>
    </p>

    <p v-if="undoError !== null" class="mt-2 text-xs font-semibold text-danger-text">
      {{ undoError }}
    </p>

    <!--
      展开区。空数组时**整块不出现**（这是收起态以外的第二层保护）：
      调用方已经用 `v-if` 挡了一次，这里再挡一次是因为
      「0 条时提醒条还在、只是没内容」比「整条消失」更像一个 bug。
    -->
    <ul v-if="expanded && todos.length > 0" class="mt-2 space-y-1">
      <ReminderRow
        v-for="todo in todos"
        :key="todo.id"
        :todo="todo"
        @acted="onActed"
      />
    </ul>
  </section>
</template>
