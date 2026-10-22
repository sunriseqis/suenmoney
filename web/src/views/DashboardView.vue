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
import {
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  CreditCard,
  Layers,
  Plus,
  ReceiptText,
  TrendingDown,
  TrendingUp,
  TriangleAlert,
} from '@lucide/vue';
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
import type { CategoryBucket } from '@/api/types';
import PaymentIcon from '@/components/PaymentIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import {
  currentMonth,
  daysInMonth,
  elapsedDays,
  formatMonthDay,
  formatMonthLabel,
  shiftMonth,
} from '@/utils/dates';
import { getCachedExpenses } from '@/utils/idb';
import { createLatestGuard } from '@/utils/latest-request';
import { adaptiveAmountStyle, formatCompact, formatYuan } from '@/utils/money';
import {
  buildMonthlyReportFallback,
  buildSummaryReportFallback,
  buildYearlyReportFallback,
} from '@/utils/offline-stats';
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
const dict = useDictionariesStore();
const syncStore = useSyncStore();

type Scope = 'month' | 'year' | 'all';

const scope = ref<Scope>('month');
const month = ref(currentMonth());
const year = computed(() => month.value.slice(0, 4));

const monthly = ref<MonthlyReport | null>(null);
const yearly = ref<YearlyReport | null>(null);
const summary = ref<SummaryReport | null>(null);

const loading = ref(true);
const errorMessage = ref<string | null>(null);

/**
 * 「只认最新一次」守卫。
 *
 * 概况有多个刷新触发源（切月、切档、ui.dataVersion、网络恢复），
 * 慢网下先发的请求可能后到并**覆盖**后发请求拿到的新数据 ——
 * 用户看到 hero 金额「跳回去」，还会以为是自己记错了。
 * 发请求前取序号，回来时不是最新就整段丢弃（含 loading 收尾，交给最新那次）。
 */
const loadGuard = createLatestGuard();

/**
 * 是否处于「离线本地口径」：最近一次请求因网络不可达（status 0）失败。
 * 为 true 时 monthly/yearly/summary 展示的是本地缓存流水聚合的结果。
 */
const isOffline = ref(false);
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
  const token = loadGuard.begin();
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

    // 期间又发生了刷新（切月/ 记了一笔 / 网络恢复）：这一份已经是旧数据，整段丢弃。
    if (!loadGuard.isLatest(token)) return;

    monthly.value = monthlyRes.report;
    yearly.value = yearlyRes.report;
    summary.value = summaryRes.report;
    isOffline.value = false;
  } catch (error) {
    if (!loadGuard.isLatest(token)) return;
    if (error instanceof ApiError && error.status === 0) {
      // 离线：在线报表不可用，改用本地缓存流水聚合的报表。
      // 这样离线记一笔后 ui.dataVersion 变化触发重算，hero 数字立刻刷新。
      isOffline.value = true;
      await loadOfflineReports();
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载失败，请重试';
  } finally {
    // loading 也判序号：被丢弃的旧请求提前关掉加载态，界面会在数据还没到时就不转了。
    if (loadGuard.isLatest(token)) loading.value = false;
  }
}

/**
 * 用本地缓存流水构造报表形状的对象，塞回原来的 monthly/yearly/summary ref，
 * 使模板里既有的字段绑定（hero、本月要还、热力图…）无需改造即可消费。
 */
async function loadOfflineReports(): Promise<void> {
  const cached = await getCachedExpenses();
  monthly.value = buildMonthlyReportFallback(cached, month.value);
  yearly.value = buildYearlyReportFallback(cached, year.value);
  summary.value = buildSummaryReportFallback(cached);
}

watch(month, load);
watch(() => ui.dataVersion, load);

// 网络恢复后重新拉服务端数据：服务端是权威，用在线口径覆盖本地回退。
watch(
  () => syncStore.isOnline,
  (online) => {
    if (online) void load();
  },
);

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

// ── 原型模板：期间控件与档位映射 ──────────────────────────────────────────
const SCOPE_OPTIONS = [
  { value: 'month', label: '本月' },
  { value: 'year', label: '本年' },
  { value: 'all', label: '全部' },
] as const;

/** 当前档位的环比（月=较上月 / 年=较去年 / 全部=None） */
const activeChangeRatio = computed<number | null>(() => {
  if (scope.value === 'month') return monthChangeRatio.value;
  if (scope.value === 'year') return yearChangeRatio.value;
  return null;
});

/** 当前档位笔数 */
const activeCount = computed(() => {
  if (scope.value === 'month') return monthly.value?.count ?? 0;
  if (scope.value === 'year') return yearly.value?.count ?? 0;
  return summary.value?.count ?? 0;
});

/** 期间标签（原型 hero 顶行） */
const periodLabel = computed(() => {
  if (scope.value === 'month') return formatMonthLabel(month.value);
  if (scope.value === 'year') return `${year.value} 年`;
  return '全部记录';
});

function shiftBack(): void {
  if (scope.value === 'month') month.value = shiftMonth(month.value, -1);
  else if (scope.value === 'year') month.value = `${Number(year.value) - 1}-01`;
}

function shiftForward(): void {
  if (scope.value === 'month') month.value = shiftMonth(month.value, 1);
  else if (scope.value === 'year') month.value = `${Number(year.value) + 1}-01`;
}

// ---------------------------------------------------------------------------
// 原型（同账）概况页派生数据
// ---------------------------------------------------------------------------

/** 当前档位对应的分类构成 */
const activeCategories = computed<CategoryBucket[]>(() => {
  if (scope.value === 'month') return monthly.value?.categories ?? [];
  if (scope.value === 'year') return yearly.value?.categories ?? [];
  return summary.value?.categories ?? [];
});

/** 堆叠条：前 4 类 + 「其他」 */
const composeRows = computed(() => {
  const rows = activeCategories.value
    .filter((c) => c.cents > 0)
    .slice()
    .sort((a, b) => b.cents - a.cents);
  const top = rows.slice(0, 4).map((c) => ({
    id: c.categoryId,
    name: c.name,
    cents: c.cents,
    color: `var(--chart-${((dict.colorOf(c.categoryId, c.name, c.color) - 1) % 8) + 1})`,
  }));
  const restCents = rows.slice(4).reduce((a, c) => a + c.cents, 0);
  if (restCents > 0) top.push({ id: '__rest', name: '其他', cents: restCents, color: 'var(--ink-3)' });
  return top;
});

const summaryTotalCents = computed(() => summary.value?.totalCents ?? 0);
const summaryCount = computed(() => summary.value?.count ?? 0);
const summaryMonthlyAvg = computed(() => summary.value?.monthlyAverageCents ?? 0);
const summarySpanMonths = computed(() => Math.max(1, Math.round((summary.value?.recordedDays ?? 0) / 30)));

/** 进行中计划 × 每期金额 = 本月计划固定还款 */
const planMonthlyCents = computed(() => plansStore.activePlans.reduce((a, p) => a + p.amountCents, 0));
const activePlanCount = computed(() => plansStore.activePlans.length);
const progressPct = computed(() => progressBarPercent.value);

/** 本月已入账的计划金额 = 计划总额 − 本月仍待还 */
const planPaidCents = computed(() => {
  const nowMonth = currentMonth();
  const stillDue = plansStore.dueTodos
    .filter((t) => t.repaymentDate.slice(0, 7) === nowMonth)
    .reduce((a, t) => a + t.amountCents, 0);
  return Math.max(0, planMonthlyCents.value - stillDue);
});

const rolling12TotalCents = computed(() => rolling12.value.reduce((a, c) => a + (c.totalCents ?? 0), 0));

/** 构成条百分比 */
function percentOf(cents: number): number {
  const total = composeRows.value.reduce((a, r) => a + r.cents, 0);
  return total > 0 ? Math.round((cents / total) * 100) : 0;
}

/** 热力格点色（原型用 color-mix 按占比混强调色） */
function heatDotColor(cents: number | null): string {
  if (cents === null || cents === 0) return 'var(--surface-3)';
  const max = heatStats.value.max;
  const pct = max > 0 ? Math.min(1, cents / max) : 0;
  return `color-mix(in srgb, var(--accent) ${Math.round(18 + pct * 82)}%, var(--surface-3))`;
}

/** 待办紧急度 → 原型三档 class（late / soon / calm） */
function urgencyLevel(date: string | null): 'late' | 'soon' | 'calm' {
  if (date === null) return 'calm';
  const days = daysUntil(date);
  if (days < 0) return 'late';
  if (days <= 3) return 'soon';
  return 'calm';
}

function daysUntil(date: string): number {
  const now = new Date();
  const a = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const t = new Date(`${date}T00:00:00`);
  const b = Date.UTC(t.getFullYear(), t.getMonth(), t.getDate());
  return Math.round((b - a) / 86_400_000);
}

const dueTodos = computed(() => plansStore.dueTodos);

/** 逾期笔数（提醒条文案：有逾期就先说逾期） */
const overdueCount = computed(
  () => dueTodos.value.filter((t) => daysUntil(t.repaymentDate) < 0).length,
);
const dueTotalAmount = computed(() =>
  dueTodos.value.reduce((acc, t) => acc + t.amountCents, 0),
);

/**
 * 模板重写（原型骨架）后，以下几个派生量暂时没有引用点：
 * 自适应字号（原型用 CSS clamp）、环比差值文案、日均对比、热力格内联样式
 * （原型改用 color-mix 的 heat-dot）。**保留代码**，等交互态补齐时会再用上，
 * 用 void 显式声明「有意保留」，比删掉再找回安全。
 */
void [
  heroAmountStyle,
  monthChangeDelta,
  dailyCompareRatio,
  heatCellStyle,
  heroTitle,
  // 以下为待办/还款文案的旧实现，原型改用 urgencyLevel + urgencyLabel
  URGENCY_META,
  urgencyOfOptional,
  reminderStateLabel,
  reminderToneOf,
  formatMonthDay,
  PaymentIcon,
];

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
  <div class="overview-grid">
    <!-- ══════ ① 本期主卡（原型 og-hero：期间控件 + 大金额 + 环比 + 三指标 + 构成条）══════ -->
    <section class="card card--pop og-hero">
      <div class="hero-eyebrow">
        <div class="seg" role="tablist" aria-label="期间">
          <button
            v-for="opt in SCOPE_OPTIONS"
            :key="opt.value"
            type="button"
            role="tab"
            class="seg-btn"
            :class="{ 'is-on': scope === opt.value }"
            :aria-selected="scope === opt.value"
            @click="scope = opt.value"
          >
            {{ opt.label }}
          </button>
        </div>
        <span class="spacer" style="margin-left: auto" />
        <div v-if="scope !== 'all'" class="period-nav">
          <button type="button" class="icon-btn" aria-label="上一期间" @click="shiftBack">
            <ChevronLeft :size="16" />
          </button>
          <span class="mono tiny" style="min-width: 92px; text-align: center">{{ periodLabel }}</span>
          <button
            type="button"
            class="icon-btn"
            aria-label="下一期间"
            :disabled="scope === 'month' && isCurrentSelectedMonth"
            @click="shiftForward"
          >
            <ChevronRight :size="16" />
          </button>
        </div>
        <span v-else class="tag tag--dash">全部记录</span>
      </div>

      <div class="hero-amt">
        <span class="cur">¥</span>{{ heroFormattedAmount }}
      </div>

      <div class="hero-delta">
        <span v-if="activeChangeRatio !== null" class="delta-pill" :class="activeChangeRatio > 0 ? 'neg' : 'pos'">
          <component :is="activeChangeRatio > 0 ? TrendingUp : TrendingDown" :size="11" />
          {{ (activeChangeRatio * 100).toFixed(1) }}%
        </span>
        <span v-else class="delta-pill pos">—</span>
        <span>较{{ scope === 'month' ? '上月' : scope === 'year' ? '去年' : '上一段' }}</span>
        <span v-if="isOffline" class="muted tiny">· 离线数据</span>
      </div>

      <div class="hero-metrics">
        <div class="stat">
          <span class="stat-v">{{ scope === 'month' ? formatYuan(dailyAverageCents) : formatYuan(summaryMonthlyAvg) }}</span>
          <span class="stat-l">{{ scope === 'month' ? '日均支出' : '月均支出' }}</span>
        </div>
        <div class="stat">
          <span class="stat-v">{{ activeCount }} 笔</span>
          <span class="stat-l">笔数</span>
        </div>
        <div class="stat">
          <span class="stat-v">
            {{ scope === 'month'
              ? (estimatedMonthEndCents !== null ? formatYuan(estimatedMonthEndCents) : '—')
              : (yearPeakMonth ? formatMonthLabel(yearPeakMonth.month) : '—') }}
          </span>
          <span class="stat-l">{{ scope === 'month' ? '预计月末' : '最高月' }}</span>
        </div>
      </div>

      <div class="og-hero-foot">
        <div class="stack-bar" role="img" aria-label="支出构成堆叠条">
          <span
            v-for="row in composeRows"
            :key="row.id"
            :style="{ flex: row.cents, background: row.color }"
          />
        </div>
        <div class="compose-legend">
          <span v-for="row in composeRows" :key="row.id" class="cl-item">
            <i class="cl-dot" :style="{ background: row.color }" />
            {{ row.name }}
            <b class="mono" style="font-weight: 600">{{ percentOf(row.cents) }}%</b>
          </span>
        </div>
        <div class="toolbar" style="margin-top: 14px">
          <span class="desktop-only">
            <button type="button" class="btn btn--primary" @click="ui.openCreate()">
              <Plus :size="14" :stroke-width="2.4" />记一笔
            </button>
          </span>
          <RouterLink :to="{ name: 'ledger' }" class="btn btn--ghost">
            <ReceiptText :size="14" />查看流水
          </RouterLink>
          <span class="tiny muted mono" style="margin-left: auto">
            {{ isOffline ? '离线数据 · 联网后自动校准' : '已与服务器同步' }}
          </span>
        </div>
      </div>
    </section>

    <!-- ══════ ② 待办与要还（原型 og-todo：提醒条 + 本月要还 + 待办提醒）══════ -->
    <section class="card og-todo og-card">
      <!-- 提醒条：**没有待办时整条不渲染** —— 空提醒条常驻只会变成噪音。
           有待办才出现，且默认收起，点一下才展开动作面板。 -->
      <button
        v-if="dueTodos.length > 0"
        type="button"
        class="alert-strip"
        :aria-expanded="isPopoverOpen"
        @click="isPopoverOpen = !isPopoverOpen"
      >
        <TriangleAlert :size="15" />
        <span>{{ overdueCount > 0 ? `${overdueCount} 笔已逾期` : `${dueTodos.length} 笔待处理` }} · {{ formatYuan(dueTotalAmount) }}</span>
        <span class="spacer" style="margin-left: auto" />
        <component :is="isPopoverOpen ? ChevronUp : ChevronDown" :size="13" />
      </button>

      <div v-if="isPopoverOpen && dueTodos.length > 0" class="alert-pop" style="margin-top: 8px">
        <div v-for="item in dueTodos" :key="item.id" class="alert-item">
          <i class="todo-mark" :class="`is-${urgencyLevel(item.repaymentDate)}`" style="height: 18px; width: 3px" />
          <span style="min-width: 0; flex: 1 1 auto">{{ item.planName }} · {{ item.periodSeq }} 期</span>
          <span class="urgency" :class="`urgency--${urgencyLevel(item.repaymentDate)}`">
            {{ urgencyLabel(item.repaymentDate) }}
          </span>
          <div class="row-end">
            <button
              v-if="item.willAutoPost"
              type="button"
              class="btn btn--ghost btn--sm"
              @click="handleAck(item.id)"
            >
              确认
            </button>
            <template v-else>
              <button type="button" class="btn btn--ghost btn--sm" @click="handleConfirm(item)">入账</button>
              <button type="button" class="btn btn--ghost btn--sm" @click="handleSkip(item.id)">忽略</button>
            </template>
          </div>
        </div>
        <div v-if="dueTodos.length" class="split" style="border-top: 1px dashed var(--line); padding-top: 8px">
          <span class="tiny muted">
            待办合计 <b class="mono" style="color: var(--ink)">{{ formatYuan(dueTotalAmount) }}</b>
          </span>
          <RouterLink
            :to="{ name: 'settings' }"
            class="btn btn--ghost btn--sm"
            style="margin-left: auto"
          >
            全部待办
          </RouterLink>
        </div>
      </div>

      <div class="og-card-body">
        <div class="card-h card-h--tight">
          <span class="card-t">本月要还</span>
          <span class="card-cap">信用卡 · {{ creditDue.length }} 张</span>
        </div>
        <div v-if="creditDue.length === 0" class="empty">
          <CreditCard :size="18" />本月没有信用卡账单
        </div>
        <div v-for="item in creditDue" v-else :key="item.paymentMethodId" class="due-row">
          <span class="due-card-badge"><CreditCard :size="15" /></span>
          <div style="min-width: 0; flex: 1 1 auto">
            <div style="font-size: 12px; font-weight: 600">{{ item.name }}</div>
            <div class="tiny muted">{{ item.count }} 笔</div>
          </div>
          <div class="row-end">
            <div class="row-amt">{{ formatYuan(item.cents) }}</div>
          </div>
        </div>
      </div>

      <!-- 待办提醒：同样无待办时整块隐藏，让卡片只剩「本月要还」 -->
      <div v-if="dueTodos.length > 0" class="og-sub">
        <div class="card-h card-h--tight">
          <span class="card-t">待办提醒</span>
          <span class="card-cap">{{ dueTodos.length }} 笔待处理</span>
        </div>
        <div v-for="item in dueTodos.slice(0, 3)" :key="item.id" class="og-todo-row">
          <span class="todo-mark" :class="`is-${urgencyLevel(item.repaymentDate)}`" />
          <span class="og-todo-t">{{ item.planName }} · {{ item.periodSeq }} 期</span>
          <span class="urgency" :class="`urgency--${urgencyLevel(item.repaymentDate)}`">
            {{ urgencyLabel(item.repaymentDate) }}
          </span>
          <b class="mono tiny">{{ formatYuan(item.amountCents) }}</b>
        </div>
      </div>

      <div class="og-card-foot">
        <span class="tiny muted">
          合计应还 <b class="mono" style="color: var(--ink)">{{ formatYuan(creditDueTotalCents) }}</b>
        </span>
        <RouterLink :to="{ name: 'settings' }" class="btn btn--ghost btn--sm">全部待办</RouterLink>
      </div>
    </section>

    <!-- ══════ ③ 月度支出热力（原型 og-heat）══════ -->
    <section class="card og-heat og-card">
      <div class="card-h">
        <span class="orb" style="background: var(--amber); color: #1E293B"><CalendarDays :size="16" /></span>
        <span class="card-t">月度支出热力</span>
        <span class="card-cap">近 12 个月 · 点击下钻</span>
      </div>
      <div class="og-card-body">
        <div class="heat-grid">
          <button
            v-for="cell in rolling12"
            :key="cell.month"
            type="button"
            class="heat-cell"
            :class="{ 'is-now': cell.month === month }"
            :title="`${cell.month} ${formatYuan(cell.totalCents ?? 0)}`"
            @click="onHeatCellClick(cell.month)"
          >
            <span class="heat-m">{{ Number(cell.month.slice(5, 7)) }}月</span>
            <span class="heat-v">{{ formatCompact(cell.totalCents ?? 0) }}</span>
            <span class="heat-dot" :style="{ background: heatDotColor(cell.totalCents) }" />
          </button>
        </div>
      </div>
      <div class="og-card-foot">
        <span class="tiny muted">
          近 12 个月合计
          <b class="mono" style="color: var(--ink)">{{ formatYuan(rolling12TotalCents) }}</b>
        </span>
        <RouterLink :to="{ name: 'report' }" class="btn btn--ghost btn--sm">打开报表</RouterLink>
      </div>
    </section>

    <!-- ══════ ④ 累计与跨度（原型 og-cum）══════ -->
    <section class="card og-cum og-card">
      <div class="card-h">
        <span class="orb" style="background: var(--mint); color: #1E293B"><Layers :size="16" /></span>
        <span class="card-t">累计与跨度</span>
        <span class="card-cap">全部历史口径</span>
      </div>
      <div class="og-card-body">
        <div style="display: flex; flex-direction: column; gap: 10px">
          <div class="kv"><span class="tiny muted">历史累计</span><b>{{ formatYuan(summaryTotalCents) }}</b></div>
          <div class="kv"><span class="tiny muted">记录笔数</span><b>{{ summaryCount }} 笔</b></div>
          <div class="kv"><span class="tiny muted">记录跨度</span><b>{{ summarySpanMonths }} 个月 · {{ summary?.years.length ?? 0 }} 年</b></div>
          <div class="kv"><span class="tiny muted">月均支出</span><b>{{ formatYuan(summaryMonthlyAvg) }}</b></div>
          <div class="kv"><span class="tiny muted">单笔均值</span><b>{{ formatYuan(summary?.perExpenseAverageCents ?? 0) }}</b></div>
        </div>
      </div>
    </section>

    <!-- ══════ ⑤ 还款进度（原型 og-progress）══════ -->
    <section class="card og-progress og-card">
      <div class="card-h">
        <span class="card-t">还款进度</span>
        <span class="card-cap">进行中计划 {{ activePlanCount }} 个</span>
        <span style="margin-left: auto">
          <RouterLink :to="{ name: 'settings' }" class="btn btn--ghost btn--sm">
            管理计划<ChevronRight :size="12" />
          </RouterLink>
        </span>
      </div>
      <div class="op-row">
        <div class="op-main">
          <div class="split" style="align-items: baseline; gap: 8px">
            <span class="op-num">{{ formatYuan(planPaidCents) }}</span>
            <span class="tiny muted">/ {{ formatYuan(planMonthlyCents) }}</span>
            <span class="mono tiny muted" style="margin-left: auto">{{ progressPct.toFixed(0) }}%</span>
          </div>
          <div style="margin-top: 8px">
            <div class="bar">
              <span
                class="bar-fill"
                :style="{
                  width: `${Math.min(100, progressPct)}%`,
                  background: progressPct > 120 ? 'var(--danger)' : progressPct > 100 ? 'var(--warn)' : 'var(--accent)',
                }"
              />
            </div>
            <div class="progress-line">
              <span>本月计划固定还款</span><span>已入账 {{ formatYuan(planPaidCents) }}</span>
            </div>
          </div>
        </div>
        <div class="op-stats">
          <div class="stat"><span class="stat-v">{{ activePlanCount }}</span><span class="stat-l">进行中计划</span></div>
          <div class="stat"><span class="stat-v">{{ dueTodos.length }}</span><span class="stat-l">待处理待办</span></div>
          <div class="stat"><span class="stat-v">{{ formatYuan(dueTotalAmount) }}</span><span class="stat-l">待办金额</span></div>
        </div>
      </div>
    </section>
  </div>
</template>
