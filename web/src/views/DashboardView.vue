<script setup lang="ts">
/**
 * 概况（原「首页」）：一屏总览，只回答「多少」（横跨月 / 年 / 总）。
 *
 * 铁律（§五 第 3 条 · §6.1）：
 *   1. 概况 DOM 里彻底不出现任何分类名（分类构成整体归报表页）。
 *   2. 概况不再放流水（流水页是唯一的明细出口）。
 *   3. 桌面 hero 底部挂提醒条（popover 展开后能动手），移动端提醒归流水页顶卡。
 *   4. 卡片一律按内容高（.card-grid），最后一行内容离底边 < 40px。
 */
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import { RouterLink, useRouter } from 'vue-router';

import {
  ApiError,
  planTodos as planTodosApi,
  reports as reportsApi,
  type MonthlyReport,
  type PlanTodo,
  type SummaryReport,
  type YearlyReport,
} from '@/api';
import PaymentIcon from '@/components/PaymentIcon.vue';
import { usePlansStore } from '@/stores/plans';
import { useUiStore } from '@/stores/ui';
import {
  currentMonth,
  daysInMonth,
  elapsedDays,
  formatMonthDay,
  formatMonthLabel,
  shiftMonth,
} from '@/utils/dates';
import { adaptiveAmountStyle, formatCompact, formatYuan } from '@/utils/money';
import {
  reminderStateLabel,
  reminderToneOf,
  URGENCY_META,
  urgencyLabel,
  urgencyOfOptional,
} from '@/utils/urgency';

const router = useRouter();
const ui = useUiStore();
const plansStore = usePlansStore();

type Scope = 'month' | 'year' | 'all';

const scope = ref<Scope>('month');
const month = ref(currentMonth());
const year = computed(() => month.value.slice(0, 4));

const monthly = ref<MonthlyReport | null>(null);
const yearly = ref<YearlyReport | null>(null);
const summary = ref<SummaryReport | null>(null);

const loading = ref(true);
const errorMessage = ref<string | null>(null);
const isPopoverOpen = ref(false);

const chipbarRef = ref<HTMLElement | null>(null);

function handleClickOutside(event: MouseEvent): void {
  if (chipbarRef.value && !chipbarRef.value.contains(event.target as Node)) {
    isPopoverOpen.value = false;
  }
}

const heroAmountContainerRef = ref<HTMLElement | null>(null);
const heroAmountTextRef = ref<HTMLElement | null>(null);
const heroCustomFontSizePx = ref<number | null>(null);

let heroResizeObserver: ResizeObserver | null = null;

function adjustHeroFontSize(): void {
  heroCustomFontSizePx.value = null;
  requestAnimationFrame(() => {
    const container = heroAmountContainerRef.value;
    const text = heroAmountTextRef.value;
    if (!container || !text) return;
    const cWidth = container.clientWidth;
    const sWidth = text.scrollWidth;
    if (cWidth > 0 && sWidth > cWidth) {
      const currentSize = parseFloat(window.getComputedStyle(text).fontSize) || 24;
      const targetSize = Math.max(14, Math.floor(currentSize * ((cWidth - 2) / sWidth)));
      heroCustomFontSizePx.value = targetSize;
    }
  });
}

onMounted(() => {
  document.addEventListener('click', handleClickOutside);
  load();

  if (typeof ResizeObserver !== 'undefined' && heroAmountContainerRef.value) {
    heroResizeObserver = new ResizeObserver(() => {
      adjustHeroFontSize();
    });
    heroResizeObserver.observe(heroAmountContainerRef.value);
  }
});

onUnmounted(() => {
  document.removeEventListener('click', handleClickOutside);
  if (heroResizeObserver) {
    heroResizeObserver.disconnect();
    heroResizeObserver = null;
  }
});

async function load(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;

  try {
    // 结算到期的自动入账待办，再并行拉取计划与三档报表
    await plansStore.loadDueTodos();

    const [, monthlyRes, yearlyRes, summaryRes] = await Promise.all([
      plansStore.loadPlans(),
      reportsApi.monthly(month.value),
      reportsApi.yearly(year.value),
      reportsApi.summary(),
    ]);

    monthly.value = monthlyRes.report;
    yearly.value = yearlyRes.report;
    summary.value = summaryRes.report;
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      // 离线静默，不展示报错横幅
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载失败，请重试';
  } finally {
    loading.value = false;
  }
}

watch(month, load);
watch(() => ui.dataVersion, load);

// ---------------------------------------------------------------------------
// 桌面 Hero 指标
// ---------------------------------------------------------------------------

const heroTitle = computed(() => {
  if (scope.value === 'month') return '本月支出';
  if (scope.value === 'year') return '今年支出';
  return '累计支出';
});

const heroTotalCents = computed(() => {
  if (scope.value === 'month') return monthly.value?.totalCents ?? 0;
  if (scope.value === 'year') return yearly.value?.totalCents ?? 0;
  return summary.value?.totalCents ?? 0;
});

const heroFormattedAmount = computed(() => formatYuan(heroTotalCents.value));

const heroAmountStyle = computed(() => {
  if (heroCustomFontSizePx.value !== null) {
    return { fontSize: `${heroCustomFontSizePx.value}px` };
  }
  return adaptiveAmountStyle(heroFormattedAmount.value, 'hero');
});

watch([heroTotalCents, scope], () => {
  adjustHeroFontSize();
});

const isCurrentSelectedMonth = computed(() => month.value === currentMonth());

/** 本月日均 */
const monthElapsed = computed(() => Math.max(1, elapsedDays(month.value)));
const monthTotalDays = computed(() => daysInMonth(month.value));

const dailyAverageCents = computed(() =>
  Math.round((monthly.value?.totalCents ?? 0) / monthElapsed.value),
);

/**
 * 预计月末：已花 ÷ 已过天数 × 当月总天数。
 * 铁律：前 3 天不显示（数据太少，首日误差可达十倍），显示 null。
 */
const estimatedMonthEndCents = computed<number | null>(() => {
  if (monthElapsed.value < 3) return null;
  return Math.round(
    ((monthly.value?.totalCents ?? 0) / monthElapsed.value) * monthTotalDays.value,
  );
});

const monthChangeRatio = computed(() => monthly.value?.change.ratio ?? null);
const monthChangeDelta = computed(() => monthly.value?.change.deltaCents ?? 0);

const yearChangeRatio = computed(() => yearly.value?.yearAgo.change.ratio ?? null);

const yearPeakMonth = computed(() => yearly.value?.peakMonth ?? null);

// ---------------------------------------------------------------------------
// 本月要还与进度对比
// ---------------------------------------------------------------------------

const creditDue = computed(() =>
  (monthly.value?.paymentMethods ?? []).filter((item) => item.type === 'credit'),
);

const creditDueTotalCents = computed(() =>
  creditDue.value.reduce((sum, item) => sum + item.cents, 0),
);

/** 近 3 个月日均消费（分） */
const baselineDailyAvgCents = computed(
  () => monthly.value?.rolling3MonthsDailyAverageCents ?? 0,
);

const dailyCompareRatio = computed<number | null>(() => {
  if (baselineDailyAvgCents.value === 0) return null;
  return (dailyAverageCents.value - baselineDailyAvgCents.value) / baselineDailyAvgCents.value;
});

const progressBarPercent = computed(() => {
  if (baselineDailyAvgCents.value === 0) return 100;
  const ratio = (dailyAverageCents.value / baselineDailyAvgCents.value) * 100;
  return Math.min(200, Math.max(0, Math.round(ratio)));
});

// ---------------------------------------------------------------------------
// 热力图（最近 12 个月滚动）
// ---------------------------------------------------------------------------

const rolling12 = computed(() => monthly.value?.rolling12Months ?? []);

const heatStats = computed(() => {
  const vals = rolling12.value
    .map((item) => item.totalCents)
    .filter((v): v is number => v !== null && v > 0);
  if (vals.length === 0) return { min: 0, max: 1 };
  return { min: Math.min(...vals), max: Math.max(...vals) };
});

function heatCellStyle(val: number | null): Record<string, string> {
  if (val === null || val === 0) return {};
  const { min, max } = heatStats.value;
  const t = (val - min) / (max - min || 1);
  const alpha = (0.14 + t * 0.78).toFixed(2);
  return {
    backgroundColor: `rgb(37 99 235 / ${alpha})`,
    color: '#ffffff',
  };
}

function onHeatCellClick(targetMonth: string): void {
  router.push({ name: 'report', query: { month: targetMonth } });
}

// ---------------------------------------------------------------------------
// 桌面提醒条动作
// ---------------------------------------------------------------------------

const dueTodos = computed(() => plansStore.dueTodos);
const dueTotalAmount = computed(() =>
  dueTodos.value.reduce((acc, t) => acc + t.amountCents, 0),
);

const reminderTone = computed(() => reminderToneOf(dueTodos.value));

async function handleAck(todoId: string): Promise<void> {
  await planTodosApi.ack(todoId);
  ui.markDataChanged();
}

async function handleConfirm(todo: PlanTodo): Promise<void> {
  await plansStore.confirmTodo(todo.id);
  ui.markDataChanged();
}

async function handleSkip(todoId: string): Promise<void> {
  await plansStore.skipTodo(todoId);
  ui.markDataChanged();
}
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+24px)]">
    <!-- 概况一屏总览 -->
    <header class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+20px)] lg:px-6 lg:pt-8">
      <!-- ① Hero 卡片：深蓝质感渐变 + 装饰光晕与水印（与流水顶卡对齐） -->
      <div
        class="relative overflow-hidden rounded-xl bg-gradient-to-br from-[#2563eb] via-[#1d4ed8] to-[#1e40af] p-5 text-on-primary shadow-xs lg:rounded-[14px] lg:p-7"
      >
        <!-- 背景装饰光晕与水印（与流水顶卡一致的品牌设计语言） -->
        <div class="pointer-events-none absolute -right-6 -bottom-10 h-40 w-40 rounded-full bg-white/[0.08] ring-8 ring-white/[0.03]" />
        <div class="pointer-events-none absolute right-16 -top-10 h-32 w-32 rounded-full bg-white/[0.05]" />
        <div
          class="pointer-events-none absolute right-4 top-2 select-none font-sans font-black leading-none text-white/[0.07] text-7xl"
        >
          ¥
        </div>

        <div class="relative z-1">
          <div class="flex items-center justify-between gap-2">
          <!-- 期间切换与标题 -->
          <div class="flex items-center gap-2">
            <button
              v-if="scope === 'month'"
              type="button"
              class="grid h-8 w-8 place-items-center rounded-sm bg-white/15 transition-colors duration-200 hover:bg-white/30"
              aria-label="上个月"
              @click="month = shiftMonth(month, -1)"
            >
              ←
            </button>
            <h1 class="text-sm font-bold opacity-95">
              {{ scope === 'month' ? formatMonthLabel(month) : scope === 'year' ? `${year} 年` : '全部时间' }}
            </h1>
            <button
              v-if="scope === 'month'"
              type="button"
              class="grid h-8 w-8 place-items-center rounded-sm bg-white/15 transition-colors duration-200 hover:bg-white/30 disabled:opacity-30"
              :disabled="isCurrentSelectedMonth"
              aria-label="下个月"
              @click="month = shiftMonth(month, 1)"
            >
              →
            </button>
          </div>

          <!-- 标题行行尾关闭按键（A24），返回流水落地页 -->
          <RouterLink
            :to="{ name: 'ledger' }"
            class="relative grid h-10 w-10 place-items-center rounded-sm bg-white/15 text-sm font-bold text-white transition-colors hover:bg-white/30 after:absolute after:-inset-0.5 after:rounded-sm after:content-['']"
            aria-label="关闭概况，返回流水"
          >
            ✕
          </RouterLink>
        </div>

        <p class="mt-4 text-xs font-semibold tracking-widest opacity-80">
          {{ heroTitle }}
        </p>

        <!-- 自适应金额展示区：根据数字长短和屏幕宽度平滑缩放，永不折行、永不溢出 -->
        <div ref="heroAmountContainerRef" class="mt-2 w-full min-w-0 overflow-hidden">
          <p v-if="loading && heroTotalCents === 0" class="skeleton h-[44px] w-56 rounded-sm lg:h-[52px]" />
          <p
            v-else
            ref="heroAmountTextRef"
            class="font-extrabold leading-none tracking-tight tabular-nums whitespace-nowrap"
            :style="heroAmountStyle"
          >
            {{ heroFormattedAmount }}
          </p>
        </div>

        <!-- 期间比对副标题 -->
        <p class="mt-2 text-xs opacity-85">
          <template v-if="scope === 'month'">
            {{ formatMonthLabel(month) }} ·
            <span v-if="monthChangeRatio !== null">
              较上月
              <b :class="monthChangeRatio > 0 ? 'text-amber-200' : 'text-emerald-200'">
                {{ monthChangeRatio > 0 ? '+' : '' }}{{ (monthChangeRatio * 100).toFixed(1) }}%
              </b>
              （{{ monthChangeDelta >= 0 ? '+' : '' }}{{ formatYuan(monthChangeDelta) }}）
            </span>
            <span v-else>较上月 —</span>
          </template>
          <template v-else-if="scope === 'year'">
            {{ year }} 年 ·
            <span v-if="yearChangeRatio !== null">
              与去年全年
              <b :class="yearChangeRatio > 0 ? 'text-amber-200' : 'text-emerald-200'">
                {{ yearChangeRatio > 0 ? '+' : '' }}{{ (yearChangeRatio * 100).toFixed(1) }}%
              </b>
            </span>
            <span v-else>与去年全年 —</span>
          </template>
          <template v-else>
            跨度 {{ summary?.recordedDays ?? 0 }} 天 · 共记 {{ summary?.years.length ?? 0 }} 年
          </template>
        </p>

        <!-- 3 个子指标，随 tab 切换 -->
        <div class="mt-5 grid grid-cols-3 gap-4 border-t border-white/15 pt-4 text-xs lg:mt-6 lg:gap-8">
          <template v-if="scope === 'month'">
            <div>
              <span class="block opacity-75">日均</span>
              <b class="mt-1 block text-base font-bold">{{ formatCompact(dailyAverageCents) }}</b>
              <span class="mt-0.5 block opacity-60">已过 {{ monthElapsed }} 天</span>
            </div>
            <div>
              <span class="block opacity-75">笔数</span>
              <b class="mt-1 block text-base font-bold">{{ monthly?.count ?? 0 }} 笔</b>
              <span class="mt-0.5 block opacity-60">笔</span>
            </div>
            <div>
              <span class="block opacity-75">预计月末</span>
              <b class="mt-1 block text-base font-bold">
                {{ estimatedMonthEndCents !== null ? formatCompact(estimatedMonthEndCents) : '—' }}
              </b>
              <span class="mt-0.5 block opacity-60">
                {{ estimatedMonthEndCents !== null ? '按当前速度' : '数据太少' }}
              </span>
            </div>
          </template>

          <template v-else-if="scope === 'year'">
            <div>
              <span class="block opacity-75">月均</span>
              <b class="mt-1 block text-base font-bold">
                {{ formatCompact(Math.round((yearly?.totalCents ?? 0) / 12)) }}
              </b>
              <span class="mt-0.5 block opacity-60">12 个月</span>
            </div>
            <div>
              <span class="block opacity-75">笔数</span>
              <b class="mt-1 block text-base font-bold">{{ yearly?.count ?? 0 }} 笔</b>
              <span class="mt-0.5 block opacity-60">笔</span>
            </div>
            <div>
              <span class="block opacity-75">最高月</span>
              <b class="mt-1 block text-base font-bold">
                {{ yearPeakMonth ? formatCompact(yearPeakMonth.totalCents) : '—' }}
              </b>
              <span class="mt-0.5 block opacity-60">
                {{ yearPeakMonth ? `${Number(yearPeakMonth.month.slice(5))} 月` : '—' }}
              </span>
            </div>
          </template>

          <template v-else>
            <div>
              <span class="block opacity-75">月均</span>
              <b class="mt-1 block text-base font-bold">
                {{ formatCompact(summary?.monthlyAverageCents ?? 0) }}
              </b>
              <span class="mt-0.5 block opacity-60">历史月均</span>
            </div>
            <div>
              <span class="block opacity-75">每笔均</span>
              <b class="mt-1 block text-base font-bold">
                {{ formatCompact(summary?.perExpenseAverageCents ?? 0) }}
              </b>
              <span class="mt-0.5 block opacity-60">累计 ÷ 笔数</span>
            </div>
            <div>
              <span class="block opacity-75">最高月</span>
              <b class="mt-1 block text-base font-bold">
                {{ summary?.peakMonth ? formatCompact(summary.peakMonth.totalCents) : '—' }}
              </b>
              <span class="mt-0.5 block opacity-60">
                {{ summary?.peakMonth ? summary.peakMonth.month : '—' }}
              </span>
            </div>
          </template>
        </div>

        <!-- 提醒条（仅桌面渲染）：收起态仅一行，点击向下展开动作面板 -->
        <div
          ref="chipbarRef"
          class="chipbar hidden lg:flex"
          :class="dueTodos.length === 0 ? 'chipbar--clean' : ''"
          :data-open="isPopoverOpen ? 'true' : 'false'"
          tabindex="0"
          @click="isPopoverOpen = !isPopoverOpen"
        >
          <span v-if="dueTodos.length === 0">没有待处理</span>
          <span v-else>{{ dueTodos.length }} 期待处理 · {{ formatYuan(dueTotalAmount) }}</span>

          <span class="chipbar__spacer" />

          <span class="chipbar__hint">
            {{ isPopoverOpen ? '收起详情' : '点击查看详情' }}
            <i
              class="rchev ml-1"
              :class="
                reminderTone === 'late'
                  ? 'rchev--late'
                  : reminderTone === 'manual'
                    ? 'rchev--manual'
                    : 'rchev--none'
              "
            >
              ▾
            </i>
          </span>

          <!-- 桌面 Popover 展开区 -->
          <div
            v-if="dueTodos.length > 0"
            class="popover text-ink"
            @click.stop
          >
            <div class="flex items-center justify-between border-b border-line pb-2">
              <h4 class="text-xs font-bold text-ink">待处理期次</h4>
              <span class="text-xs text-ink-muted">{{ dueTodos.length }} 期待办</span>
            </div>

            <div class="mt-2 divide-y divide-line/60">
              <div
                v-for="item in dueTodos"
                :key="item.id"
                class="flex items-center justify-between gap-3 py-2 text-xs"
              >
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <b class="font-bold tabular-nums text-ink">{{ formatYuan(item.amountCents) }}</b>
                    <span class="truncate text-ink-muted">
                      {{ item.periodSeq }}期 · {{ item.planName }}
                    </span>
                  </div>
                  <div class="mt-0.5 flex items-center gap-2 text-[11px]">
                    <span :class="URGENCY_META[urgencyOfOptional(item.repaymentDate)]">
                      {{ formatMonthDay(item.repaymentDate) }} · {{ urgencyLabel(item.repaymentDate) }}
                    </span>
                    <span class="text-ink-muted">
                      {{ reminderStateLabel(item.willAutoPost) }}
                    </span>
                  </div>
                </div>

                <div class="flex shrink-0 items-center gap-1.5">
                  <template v-if="item.willAutoPost">
                    <button
                      type="button"
                      class="rounded-sm bg-sunken px-2.5 py-1 text-xs font-semibold text-ink transition-colors hover:bg-line"
                      @click="handleAck(item.id)"
                    >
                      确认
                    </button>
                  </template>
                  <template v-else>
                    <button
                      type="button"
                      class="rounded-sm bg-primary-fill px-2.5 py-1 text-xs font-semibold text-on-primary transition-colors hover:opacity-90"
                      @click="handleConfirm(item)"
                    >
                      入账
                    </button>
                    <button
                      type="button"
                      class="rounded-sm bg-sunken px-2 py-1 text-xs font-semibold text-ink-muted transition-colors hover:bg-line"
                      @click="handleSkip(item.id)"
                    >
                      忽略
                    </button>
                  </template>
                </div>
              </div>
            </div>
          </div>
        </div>
        </div>
      </div>

      <!-- 档位切换（本月 / 今年 / 汇总）平铺三列按钮 -->
      <div class="mt-3 grid grid-cols-3 gap-1 rounded-lg bg-sunken p-1 shadow-2xs" role="tablist" aria-label="统计范围">
        <button
          type="button"
          :aria-pressed="scope === 'month'"
          class="rounded-md py-2 text-center text-xs font-semibold transition-all duration-150 cursor-pointer"
          :class="
            scope === 'month'
              ? 'bg-surface text-ink font-bold shadow-2xs'
              : 'text-ink-muted hover:text-ink'
          "
          @click="scope = 'month'"
        >
          本月
        </button>
        <button
          type="button"
          :aria-pressed="scope === 'year'"
          class="rounded-md py-2 text-center text-xs font-semibold transition-all duration-150 cursor-pointer"
          :class="
            scope === 'year'
              ? 'bg-surface text-ink font-bold shadow-2xs'
              : 'text-ink-muted hover:text-ink'
          "
          @click="scope = 'year'"
        >
          今年
        </button>
        <button
          type="button"
          :aria-pressed="scope === 'all'"
          class="rounded-md py-2 text-center text-xs font-semibold transition-all duration-150 cursor-pointer"
          :class="
            scope === 'all'
              ? 'bg-surface text-ink font-bold shadow-2xs'
              : 'text-ink-muted hover:text-ink'
          "
          @click="scope = 'all'"
        >
          汇总
        </button>
      </div>

      <p v-if="errorMessage !== null" class="mt-4 text-center text-sm font-semibold text-danger-text">
        {{ errorMessage }}
      </p>
    </header>

    <main class="mx-auto mt-6 w-full max-w-[var(--content-max)] space-y-6 px-4 lg:px-6">
      <!-- ② 第二行：本月要还 + 支出进度（双列等高卡片） -->
      <section class="grid grid-cols-1 lg:grid-cols-2 gap-3.5 items-stretch" aria-label="当期事实">
        <!-- 本月要还 -->
        <div class="flex flex-col justify-between rounded-lg bg-surface p-5 shadow-none ring-1 ring-line/80 h-full">
          <div>
            <div class="flex items-center justify-between">
              <h2 class="label-cn">本月要还</h2>
              <span class="text-xs text-ink-muted">信用卡账单</span>
            </div>

            <p class="mt-2 text-2xl font-extrabold text-amber-700 dark:text-amber-400">
              {{ formatYuan(creditDueTotalCents) }}
            </p>

            <div v-if="creditDue.length === 0" class="mt-3 text-xs text-ink-muted">
              本月无待还款信用卡
            </div>
            <ul v-else class="mt-3 divide-y divide-line/60 max-h-[160px] overflow-y-auto pr-0.5">
              <li
                v-for="item in creditDue"
                :key="item.paymentMethodId"
                class="flex items-center justify-between py-2 text-xs"
              >
                <PaymentIcon :name="item.name" :size="20" class="mr-2.5" />
                <div class="min-w-0 flex-1">
                  <span class="block truncate font-semibold text-ink">{{ item.name }}</span>
                  <span
                    v-if="item.repaymentDate !== null"
                    class="block text-[11px]"
                    :class="URGENCY_META[urgencyOfOptional(item.repaymentDate)]"
                  >
                    {{ formatMonthDay(item.repaymentDate) }} · {{ urgencyLabel(item.repaymentDate) }} · 已记 {{ item.count }} 笔
                  </span>
                </div>
                <b class="shrink-0 text-sm font-bold tabular-nums text-ink">
                  {{ formatYuan(item.cents) }}
                </b>
              </li>
            </ul>
          </div>

          <p class="mt-3 border-t border-line/60 pt-2 text-xs text-ink-muted">
            <template v-if="creditDue.length > 0">
              共 <b class="font-bold tabular-nums text-ink">{{ creditDue.length }}</b> 笔待还款信用卡
            </template>
            <template v-else>
              全部信用卡账单已结清或无待还
            </template>
          </p>
        </div>

        <!-- 支出进度卡 -->
        <div class="flex flex-col justify-between rounded-lg bg-surface p-5 shadow-none ring-1 ring-line/80 h-full">
          <div>
            <div class="flex items-center justify-between">
              <h2 class="label-cn">本月支出进度</h2>
              <span class="text-xs text-ink-muted">对近 3 个月日均</span>
            </div>

            <p class="mt-2 text-2xl font-extrabold text-ink">
              {{ formatYuan(dailyAverageCents) }}
              <span class="text-xs font-normal text-ink-muted"> / 天</span>
            </p>

            <p class="mt-1 text-xs text-ink-muted">
              本月已过 {{ monthElapsed }} 天 · 已花 {{ formatYuan(monthly?.totalCents ?? 0) }}
            </p>

            <!-- 进度条 -->
            <div class="mt-3.5 h-2 w-full overflow-hidden rounded-full bg-sunken">
              <div
                class="h-full rounded-full transition-all duration-300"
                :class="
                  progressBarPercent > 120
                    ? 'bg-danger-fill'
                    : progressBarPercent > 100
                      ? 'bg-accent-fill'
                      : 'bg-primary-fill'
                "
                :style="{ width: `${Math.min(100, progressBarPercent)}%` }"
              />
            </div>

            <p class="mt-2 text-xs">
              <template v-if="dailyCompareRatio !== null">
                比近 3 个月日均
                <b :class="dailyCompareRatio > 0 ? 'text-danger-text' : 'text-secondary-text'">
                  {{ dailyCompareRatio > 0 ? '高' : '低' }} {{ Math.abs(Math.round(dailyCompareRatio * 100)) }}%
                </b>
              </template>
              <template v-else>
                近 3 个月无参考基准
              </template>
            </p>
          </div>

          <p class="mt-3 border-t border-line/60 pt-2 text-xs text-ink-muted">
            预计月末
            <b class="font-bold tabular-nums text-ink">
              {{ estimatedMonthEndCents !== null ? formatYuan(estimatedMonthEndCents) : '—' }}
            </b>
            <span v-if="estimatedMonthEndCents === null" class="ml-1 text-[11px]">（前 3 天不显示）</span>
          </p>
        </div>
      </section>

      <!-- ③ 第三行：月度支出热力（最近 12 个月滚动，通栏） -->
      <section class="rounded-lg bg-surface p-5 shadow-none ring-1 ring-line/80" aria-label="月度支出热力">
        <div class="flex items-center justify-between">
          <h2 class="label-cn">月度支出热力</h2>
          <span class="text-xs text-ink-muted">最近 12 个月 · 滚动</span>
        </div>

        <div class="heat mt-3.5">
          <div
            v-for="(c, idx) in rolling12"
            :key="c.month"
            class="heat__cell"
            :class="[
              c.totalCents === null || c.totalCents === 0 ? 'heat__cell--empty' : '',
              idx === rolling12.length - 1 ? 'heat__cell--now' : '',
            ]"
            :style="heatCellStyle(c.totalCents)"
            :title="`${c.month} · ${c.totalCents === null ? '无记录' : formatYuan(c.totalCents)}`"
            @click="onHeatCellClick(c.month)"
          >
            <span class="heat__m">{{ Number(c.month.slice(5)) }}月</span>
            <span class="heat__v heat__v--full">
              {{ c.totalCents === null ? '—' : formatCompact(c.totalCents) }}
            </span>
            <span class="heat__v heat__v--short">
              {{ c.totalCents === null ? '—' : formatCompact(c.totalCents) }}
            </span>
          </div>
        </div>
      </section>

      <!-- ④ 第四行：累计条（通栏一行） -->
      <div class="strip" role="region" aria-label="累计数据">
        <span class="strip__label">累计</span>
        <div class="strip__items">
          <span>已记 <b>{{ summary?.recordedDays ?? 0 }}</b> 天</span>
          <span><b>{{ summary?.count ?? 0 }}</b> 笔</span>
          <span>
            平均
            <b>
              {{
                summary && summary.recordedDays > 0
                  ? (summary.count / summary.recordedDays).toFixed(1)
                  : '0.0'
              }}
            </b>
            笔 / 天
          </span>
          <span>首笔 <b>{{ summary?.firstRepaymentDate ?? '—' }}</b></span>
        </div>
      </div>
    </main>
  </div>
</template>
