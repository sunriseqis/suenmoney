<script setup lang="ts">
/**
 * 一条提醒 = **一行**，动作靠左右滑（窄屏）或按钮（桌面）。
 *
 * ## 为什么改成手势
 *
 * 第九次修正之后这一行仍然是「文字显示不全」，而原因不是字太多 ——
 * 是**动作按钮太多**：两个按钮（「入账」「忽略」）占掉约 110px，
 * 剩下的宽度才轮到文字，于是计划名被截、状态词被压。
 * 用户给的解法是换交互：**左滑确认 / 入账，右滑忽略**。
 * 按钮一撤，整行宽度就只剩信息，文案反而可以写回完整。
 *
 * ## 三类动作的判据是 `willAutoPost`，不是「计划开没开自动入账」
 *
 * | 这一期现在会不会自动入账 | 主操作 | 点了之后 |
 * |---|---|---|
 * | **会** | `确认` | 只记「我知道了」，**不改任何业务状态**，到还款日照旧自动入账 |
 * | **不会** | `入账` | 生成那笔支出（`confirmTodo`） |
 * | （不会，次操作） | `忽略` | 这一期不记（`skipTodo`） |
 *
 * 判据由服务端算好下发（`todo.willAutoPost`），这里不自己拼 ——
 * 只看计划那一级会判错，而且错法静默：给一个「确认」，用户点了以为没事，
 * 那笔账却永远不入。
 *
 * ## 阈值的取法
 *
 * `TRIGGER = 72px`。太短会误触（滑动列表时手指横向飘一下就够了），
 * 太长则要甩两下才生效。越过阈值时底层那条提示会**点亮并换词**
 * （「忽略」→「松手忽略」），所以阈值不需要靠猜 —— 用户看得见。
 *
 * 竖向滚动不受影响：`touch-action: pan-y` 让浏览器接管竖向，
 * 横向的 pointermove 才交给我们；真滚起来时浏览器会发 `pointercancel`，
 * 那时重置即可。
 */
import { computed, ref } from 'vue';

import { ApiError, type PlanTodo } from '@/api';
import { usePlansStore } from '@/stores/plans';
import { formatYuan } from '@/utils/money';
import {
  URGENCY_META,
  reminderActionOf,
  reminderPrimaryLabel,
  reminderStateLabel,
  urgencyLabel,
  urgencyOf,
  type ReminderDone,
} from '@/utils/urgency';

const props = defineProps<{ todo: PlanTodo }>();
const emit = defineEmits<{ acted: [payload: { kind: ReminderDone; todo: PlanTodo }] }>();

const plansStore = usePlansStore();

/** 越过它就算一次有效的滑动 */
const TRIGGER = 72;
/** 拖动上限：比阈值多留一点余量，手感上「还能再推一点」 */
const MAX = 108;

const busy = ref(false);
const errorMessage = ref<string | null>(null);

const action = computed(() => reminderActionOf(props.todo.willAutoPost));
const primaryLabel = computed(() => reminderPrimaryLabel(action.value));
const stateLabel = computed(() => reminderStateLabel(props.todo.willAutoPost));
const urgency = computed(() => urgencyOf(props.todo.repaymentDate));

/* ---- 逾期确认：先选实际付款日 ----------------------------------------- */

const choosingDate = ref(false);
const chosenDate = ref('');

/* ---- 左右滑 ------------------------------------------------------------ */

const offsetX = ref(0);
const dragging = ref(false);
/** 抬手回弹期间才加 transition；跟手期间加过渡会「追不上手指」 */
const settling = ref(false);

let startX = 0;
let startY = 0;
/** 方向还没判定为 none 之前不动位移，避免手指的轻微抖动被当成滑动 */
let axis: 'none' | 'x' | 'y' = 'none';
let activeId: number | null = null;

const armedPrimary = computed(() => offsetX.value <= -TRIGGER);
const armedIgnore = computed(() => offsetX.value >= TRIGGER);

function settle(): void {
  dragging.value = false;
  settling.value = true;
  axis = 'none';
  activeId = null;
  offsetX.value = 0;
}

function onPointerDown(event: PointerEvent): void {
  // 鼠标不走手势：桌面本来就有按钮，而鼠标拖拽会与文本选区打架
  if (event.pointerType === 'mouse' || busy.value) return;

  activeId = event.pointerId;
  startX = event.clientX;
  startY = event.clientY;
  axis = 'none';
  settling.value = false;
  dragging.value = true;
}

function onPointerMove(event: PointerEvent): void {
  if (!dragging.value || event.pointerId !== activeId) return;

  const dx = event.clientX - startX;
  const dy = event.clientY - startY;

  if (axis === 'none') {
    // 8px 之内不认方向：这一段既可能是一次点击，也可能只是一次按压
    if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;

    axis = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y';

    // 判定为竖向：这一行退出本次手势，交给浏览器滚动
    if (axis === 'y') {
      settle();
      return;
    }
  }

  offsetX.value = Math.max(-MAX, Math.min(MAX, dx));
}

function onPointerUp(event: PointerEvent): void {
  if (!dragging.value || event.pointerId !== activeId) return;

  const dx = offsetX.value;
  settle();

  // 没过阈值 = 用户只是划了一下又收回，不执行任何动作
  if (dx <= -TRIGGER) {
    void run('primary');
    return;
  }
  if (dx >= TRIGGER) void run('ignore');
}

/* ---- 三个动作 ---------------------------------------------------------- */

function report(error: unknown, fallback: string): void {
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
}

async function ack(): Promise<void> {
  if (busy.value) return;
  errorMessage.value = null;
  busy.value = true;
  try {
    await plansStore.ackTodo(props.todo.id);
    emit('acted', { kind: 'ack', todo: props.todo });
  } catch (error) {
    report(error, '确认失败');
  } finally {
    busy.value = false;
  }
}

async function confirm(spendDate?: string): Promise<void> {
  if (busy.value) return;
  errorMessage.value = null;
  busy.value = true;
  try {
    await plansStore.confirmTodo(props.todo.id, spendDate);
    choosingDate.value = false;
    emit('acted', { kind: 'confirm', todo: props.todo });
  } catch (error) {
    report(error, '入账失败');
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
    emit('acted', { kind: 'skip', todo: props.todo });
  } catch (error) {
    report(error, '忽略失败');
  } finally {
    busy.value = false;
  }
}

/**
 * 滑动落下来的主操作。
 *
 * 「入账」在**逾期**时有一处例外的规矩：桌面点按钮会先弹「实际付款日」，
 * 而滑动没有第二次交互的机会，所以它直接按**计划的还款日**入账 ——
 * 那也正是默认值（`confirmTodo` 不传 spendDate 时用的就是还款日），
 * 因此两者不会产生两套账。
 */
function run(kind: 'primary' | 'ignore'): void {
  if (kind === 'ignore') {
    void skip();
    return;
  }
  if (action.value === 'ack') {
    void ack();
    return;
  }
  void confirm(undefined);
}

/** 桌面按钮：逾期的「入账」要先问日期 */
function onPrimaryClick(): void {
  if (action.value === 'ack') {
    void ack();
    return;
  }
  if (urgency.value === 'overdue') {
    choosingDate.value = true;
    chosenDate.value = props.todo.repaymentDate;
    return;
  }
  void confirm(undefined);
}
</script>

<template>
  <li class="reminder-swipe overflow-hidden">
    <!--
      底层提示。两侧各一条，行本体滑开多少就露出多少 ——
      **只作反馈、不接收点击**（动作已经由手势完成了）。
    -->
    <span
      class="reminder-swipe__behind reminder-swipe__behind--ignore"
      :data-armed="armedIgnore || undefined"
      aria-hidden="true"
    >
      {{ armedIgnore ? '松手忽略' : '忽略' }}
    </span>
    <span
      class="reminder-swipe__behind reminder-swipe__behind--primary"
      :data-armed="armedPrimary || undefined"
      aria-hidden="true"
    >
      {{ armedPrimary ? `松手${primaryLabel}` : primaryLabel }}
    </span>

    <div
      class="reminder-swipe__surface"
      :data-settling="settling || undefined"
      :style="{ transform: `translateX(${offsetX}px)` }"
      @pointerdown="onPointerDown"
      @pointermove="onPointerMove"
      @pointerup="onPointerUp"
      @pointercancel="settle"
    >
      <!-- 一行：金额 → 期次 · 计划名 → 多急 → 要不要你动手 → 动作 -->
      <div class="reminder-row pop-in">
        <span class="reminder-row__amt text-base">{{ formatYuan(todo.amountCents) }}</span>

        <span class="reminder-row__plan text-sm">
          {{ todo.periodSeq }}期 · {{ todo.planName }}
        </span>

        <span class="reminder-row__when" :class="URGENCY_META[urgency]">
          {{ urgencyLabel(todo.repaymentDate) }}
        </span>

        <span class="reminder-row__state">{{ stateLabel }}</span>

        <!--
          动作按钮：桌面（≥1024px）常驻；窄屏退出排版但留在无障碍树里，
          键盘 Tab 进来时会浮出来（见 base.css 的 .reminder-acts）。
        -->
        <span class="reminder-acts">
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm bg-primary-fill px-3 py-1.5 text-xs font-bold text-on-primary"
            @click="onPrimaryClick"
          >
            {{ primaryLabel }}
          </button>
          <button
            v-if="action === 'decide'"
            type="button"
            :disabled="busy"
            class="rounded-sm px-3 py-1.5 text-xs font-semibold text-ink-muted hover:bg-canvas hover:text-ink"
            @click="skip"
          >
            忽略
          </button>
        </span>
      </div>

      <!-- 逾期确认：只记录「哪天实际付的」，不改报表月份归属 -->
      <div v-if="choosingDate" class="border-t border-line bg-canvas px-3 py-2.5">
        <label class="label-cn" :for="`posted-${todo.id}`">实际付款日</label>
        <div class="mt-1.5 flex items-center gap-2">
          <input
            :id="`posted-${todo.id}`"
            v-model="chosenDate"
            type="date"
            class="min-w-0 flex-1 rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
          />
          <button
            type="button"
            :disabled="busy"
            class="shrink-0 rounded-sm bg-primary-fill px-3.5 py-2 text-sm font-bold text-on-primary"
            @click="confirm(chosenDate)"
          >
            入账
          </button>
          <button
            type="button"
            class="shrink-0 rounded-sm px-3 py-2 text-sm font-semibold text-ink-muted hover:text-ink"
            @click="choosingDate = false"
          >
            取消
          </button>
        </div>
      </div>

      <p v-if="errorMessage !== null" class="border-t border-line px-3 py-2 text-xs font-semibold text-danger-text">
        {{ errorMessage }}
      </p>
    </div>
  </li>
</template>
