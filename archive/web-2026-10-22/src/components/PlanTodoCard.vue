<script setup lang="ts">
/**
 * 待办卡片：确认入账 / 更多（跳过）。
 *
 * 仪表盘与计划页都要用，所以抽成组件 —— 两处各写一遍的话，
 * 「逾期时要先选实际付款日」这种细节迟早只在一边生效。
 *
 * 逾期才让选日期：没逾期时按还款日直接入账，少一次交互。
 * 选日期只影响记录上的实际付款日，**不改报表月份归属**（归属以计划里的还款日为准）。
 *
 * 配色由 utils/urgency.ts 统一决定，本组件不自己挑颜色 ——
 * 否则「本月待还」与这里很快就会出现两套紧急度口径。
 *
 * ## 这一版补的是「身份物」与「动作收敛」
 *
 * **身份物**：分类图标 + 期次 + 分期进度刻度 + 下次还款日。
 * 之前卡片上只有「名字 + 第几期 + 金额」，而同一屏的流水行有分类图标、
 * 有日期有备注 —— 待办卡看起来像另一个产品塞进来的组件。
 *
 * **动作**：「主按钮 + 更多菜单」，不再平铺两个同权重的按钮。
 * 「跳过」是低频动作，而且它改的是「这一期怎么算」，不是「今天要付多少」——
 * 语义不同权重，平铺等于把误触的代价做得和正常操作一样低。
 *
 * > 注：第三轮返工后「跳过」**已经可以恢复**（计划详情里点「恢复」，
 * > 见 PlansPanel 的期次行）。所以这里收敛动作的理由是「低频 + 语义不同权重」，
 * > **不再是「不可逆」** —— 旧注释写的是「不可逆（跳过的期次不会回到待办列表）」，
 * > 那句从这一轮起不成立了，留着会让人以为恢复功能不存在。
 */
import { MoreHorizontal } from '@lucide/vue';
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';

import { ApiError, type PlanTodo } from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { formatMonthDay } from '@/utils/dates';
import { formatCompact, formatYuan } from '@/utils/money';
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
const dict = useDictionariesStore();

const busy = ref(false);
const errorMessage = ref<string | null>(null);
const choosingDate = ref(false);
const chosenDate = ref('');

const urgency = computed(() => urgencyOf(props.todo.repaymentDate));
const overdue = computed(() => urgency.value === 'overdue');
const dueLabel = computed(() => urgencyLabel(props.todo.repaymentDate));

const plan = computed(
  () => plansStore.plans.find((item) => item.id === props.todo.planId) ?? null,
);

/**
 * 进度刻度最多画 12 段。
 *
 * 段数本身就是信息（12 期一眼看得出还剩几格），但 30 年的房贷有 360 期，
 * 逐期画出来只会变成一片灰点。超过 12 期时压缩成 12 格、按比例取整填充，
 * **精确数字始终由右边那行文字给出**，刻度只负责「一眼看出进度」。
 */
const TICK_LIMIT = 12;

const meter = computed(() => {
  const current = plan.value;
  if (current === null) return null;

  const { progress } = current;
  const total = progress.paidCount + progress.pendingCount;
  if (total <= 0) return null;

  const ticks = Math.min(total, TICK_LIMIT);
  const filled =
    ticks === total ? progress.paidCount : Math.round((progress.paidCount / total) * ticks);

  return {
    ticks,
    filled,
    text:
      current.source === 'installment'
        ? `已付 ${progress.paidCount} / ${total} 期 · 原价 ${formatCompact(
            current.totalAmountCents ?? 0,
          )}`
        : `已还 ${progress.paidCount} / ${total} 期 · 剩余 ${formatCompact(progress.pendingCents)}`,
  };
});

/* ---- 「更多」菜单 ------------------------------------------------------ */

const menuOpen = ref(false);
const menuRef = ref<HTMLElement | null>(null);

/**
 * 点卡片外面就收起菜单。
 *
 * 用 pointerdown 而不是 click：click 要等手指抬起，期间菜单还是开着的，
 * 落在别的卡片上的那一下会先被当成「点卡片」。监听挂在 document 上而不是
 * 用一个全屏透明层 —— 卡片自己有 hover 位移（transform），那会让 fixed
 * 元素改成相对卡片定位并被裁掉。
 */
function onDocumentPointerDown(event: PointerEvent): void {
  const el = menuRef.value;
  if (el !== null && event.target instanceof Node && !el.contains(event.target)) {
    menuOpen.value = false;
  }
}

watch(menuOpen, (open) => {
  if (open) document.addEventListener('pointerdown', onDocumentPointerDown);
  else document.removeEventListener('pointerdown', onDocumentPointerDown);
});

onUnmounted(() => document.removeEventListener('pointerdown', onDocumentPointerDown));

onMounted(() => {
  // 分类图标是卡片的身份物，但字典可能还没被任何页面拉过 —— 首页本身不需要它
  // （流水行的图标由接口直接给出）。load() 内部有 loaded 标记，不会重复请求。
  // 失败时静默退回「其他」的兜底图标，不该因为一个图标让整页报错。
  void dict.load().catch(() => undefined);
});

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

async function skipFromMenu(): Promise<void> {
  menuOpen.value = false;
  await skip();
}
</script>

<template>
  <!--
    卡片**不能** overflow-hidden：左侧色条靠它裁圆角，但「更多」菜单也会被它裁掉。
    所以圆角改由色条自己带（rounded-l-md），菜单得以溢出卡片显示。
  -->
  <div
    class="pop-in relative rounded-md bg-surface py-3 pr-3.5 pl-[18px] transition-transform duration-200 lg:hover:-translate-y-0.5"
    :class="URGENCY_CARD[urgency]"
  >
    <!-- 紧急度唯一的着色位置。纯装饰：紧急程度已由下面的文字表达，避免读屏重复播报 -->
    <span
      class="absolute inset-y-0 left-0 w-1 rounded-l-md"
      :class="URGENCY_BAR[urgency]"
      aria-hidden="true"
    />

    <!-- 身份物：分类图标 + 计划名 + 期次 + 还款日 -->
    <div class="flex items-start gap-2.5">
      <span class="grid h-[34px] w-[34px] shrink-0 place-items-center rounded-sm bg-canvas">
        <CategoryIcon :category-id="todo.categoryId" :size="17" />
      </span>

      <div class="min-w-0 flex-1">
        <p class="flex items-baseline gap-1.5">
          <span class="min-w-0 truncate text-sm font-bold">{{ todo.planName }}</span>
          <span class="shrink-0 text-xs font-normal text-ink-muted">
            第 {{ todo.periodSeq }} 期
          </span>
        </p>
        <p class="mt-0.5 truncate text-xs" :class="URGENCY_META[urgency]">
          {{ formatMonthDay(todo.repaymentDate) }} 还款 · {{ dueLabel }}
        </p>
      </div>
    </div>

    <!-- 分期进度刻度：段数本身就是信息，所以宁可画格子也不画一根条 -->
    <div v-if="meter !== null" class="mt-2.5 flex items-center gap-2">
      <span class="flex shrink-0 gap-[3px]" aria-hidden="true">
        <span
          v-for="n in meter.ticks"
          :key="n"
          class="h-2.5 w-1 rounded-[2px]"
          :class="n <= meter.filled ? 'bg-primary' : 'bg-line'"
        />
      </span>
      <span class="min-w-0 truncate text-xs text-ink-muted">{{ meter.text }}</span>
    </div>

    <p v-if="errorMessage !== null" class="mt-2 text-xs font-semibold text-danger-text">
      {{ errorMessage }}
    </p>

    <!-- 逾期：先选实际付款日 -->
    <div v-if="choosingDate" class="mt-3 rounded-sm bg-canvas p-3">
      <label class="label-cn" :for="`posted-${todo.id}`">实际付款日</label>
      <input
        :id="`posted-${todo.id}`"
        v-model="chosenDate"
        type="date"
        class="mt-1 w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
      />
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

    <div v-else class="mt-3 flex items-center gap-2">
      <span class="shrink-0 text-base font-bold">{{ formatYuan(todo.amountCents) }}</span>

      <span class="ml-auto flex shrink-0 items-center gap-1">
        <button
          type="button"
          :disabled="busy"
          class="rounded-sm px-3.5 py-2 text-sm font-bold transition-transform duration-200 active:scale-95 disabled:opacity-40"
          :class="URGENCY_ACTION.primary"
          @click="start"
        >
          确认入账
        </button>

        <!-- 「更多」：跳过这类低频动作收在这里；它不再是不可逆的，所以顺带说明可恢复 -->
        <div ref="menuRef" class="relative">
          <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-sm text-ink-muted transition-colors duration-200 hover:bg-canvas hover:text-ink"
            aria-haspopup="menu"
            :aria-expanded="menuOpen"
            :aria-label="`「${todo.planName}」第 ${todo.periodSeq} 期更多操作`"
            @click="menuOpen = !menuOpen"
          >
            <MoreHorizontal :size="18" aria-hidden="true" />
          </button>

          <div
            v-if="menuOpen"
            role="menu"
            class="absolute right-0 top-full z-[var(--z-sticky)] mt-1 w-48 overflow-hidden rounded-md border border-line bg-surface py-1"
          >
            <button
              type="button"
              role="menuitem"
              :disabled="busy"
              class="block w-full px-3 py-2 text-left text-sm text-ink-muted transition-colors duration-200 hover:bg-canvas hover:text-ink disabled:opacity-40"
              @click="skipFromMenu"
            >
              跳过这一期
            </button>
          </div>
        </div>
      </span>
    </div>
  </div>
</template>
