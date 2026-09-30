<script setup lang="ts">
/**
 * 流水页：浏览 + 查找（A13~A15 · A20~A21 · A26~A29 · §6.2 · §6.6）。
 *
 * 铁律：
 *   1. 移动端单页化：
 *      - 移动端置顶顶卡（本月支出 + 处理提醒，有逾期吸顶，点击向下展开明细动作）
 *      - 控制行（期间选择靠左 + 三个二级页入口靠右：概况 · 报表 · 设置，随滚动滚走）
 *      - 搜索独占一行
 *   2. 三种档位三种形态：
 *      - 月档：流水列表（无组头，纯扁平，每段 100 笔）
 *      - 年档：12 个月格日历（一格一月，4 档深浅）
 *      - 全部档：一格一年日历（一格一年，4 档深浅）
 *   3. 日历两个动作：点一下选中切换下方概况卡，再点或按「进入」才下钻（年→月，月→流水）。
 *   4. 流水行「一行一项」：主名与副信息同行，单行不折行；窄屏账期让位；行内日期支持最远到 2 天简化显示（今日星期一 / 昨日星期日 / 26日星期六）。
 *   5. 合计仅在有筛选或搜索时展示金额，无筛选时仅展示笔数。
 */
import { computed, onMounted, ref, watch } from 'vue';
import { RouterLink, useRoute } from 'vue-router';

import {
  ApiError,
  expenses as expensesApi,
  planTodos as planTodosApi,
  reports as reportsApi,
  type Expense,
  type MonthlyReport,
  type PlanTodo,
  type SummaryReport,
  type YearlyReport,
} from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import ChipButton from '@/components/ChipButton.vue';
import PaymentIcon from '@/components/PaymentIcon.vue';
import PeriodPicker from '@/components/PeriodPicker.vue';
import ReportCalendar, { type CalendarCell } from '@/components/ReportCalendar.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import { categoryColorVar } from '@/utils/category-colors';
import { getCachedExpenses, saveCachedExpenses } from '@/utils/idb';
import {
  currentMonth,
  daysInMonth,
  elapsedDays,
  formatLedgerDate,
  formatMonthDay,
  formatMonthLabel,
  shiftMonth,
  todayLocal,
} from '@/utils/dates';
import { adaptiveAmountStyle, formatCents, formatCompact, formatYuan } from '@/utils/money';
import {
  reminderStateLabel,
  reminderToneOf,
  URGENCY_META,
  urgencyLabel,
  urgencyOfOptional,
} from '@/utils/urgency';

const route = useRoute();
const ui = useUiStore();
const dict = useDictionariesStore();
const plansStore = usePlansStore();
const syncStore = useSyncStore();

type Scope = 'month' | 'year' | 'all';
type SortBy = 'date_desc' | 'amount_desc';

const scope = ref<Scope>('month');
const month = ref(currentMonth());
const year = ref(String(new Date().getFullYear()));

// 路由参数同步
if (typeof route.query.month === 'string' && route.query.month) {
  scope.value = 'month';
  month.value = route.query.month;
} else if (typeof route.query.year === 'string' && route.query.year) {
  scope.value = 'year';
  year.value = route.query.year;
} else if (route.query.scope === 'all') {
  scope.value = 'all';
}

const previousMonth = computed(() => shiftMonth(month.value, -1));
const previousMonthLabel = computed(() => formatMonthLabel(previousMonth.value));

function goToPreviousMonth(): void {
  month.value = previousMonth.value;
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

const categoryId = ref<string | null>(null);
const paymentMethodId = ref<string | null>(null);
const keyword = ref('');
/** 搜索激活：任何档位输入关键词都会切换为跨期流水列表（月=当月 / 年=全年 / 全部=全库） */
const isSearchActive = computed(() => keyword.value.trim() !== '');
const sortBy = ref<SortBy>('date_desc');
const isFilterExpanded = ref(false);
const hasChipFilter = computed(() => categoryId.value !== null || paymentMethodId.value !== null);

// 月档流水数据
const items = ref<Expense[]>([]);
const nextCursor = ref<string | null>(null);
const hasMore = ref(false);
const loading = ref(false);
const loadingMore = ref(false);
const errorMessage = ref<string | null>(null);

// 顶卡数据（移动端）
const currentMonthTotalCents = ref(0);
const isTopCardExpanded = ref(false);
const currentMonthlyReport = ref<MonthlyReport | null>(null);

const topCardTitle = computed(() => {
  if (scope.value === 'month') {
    return month.value === currentMonth() ? '本月支出' : `${formatMonthLabel(month.value)}支出`;
  }
  if (scope.value === 'year') {
    return `${year.value} 年支出`;
  }
  return '全部时间支出';
});

const displayTotalCents = computed(() => {
  if (scope.value === 'year') {
    return yearlyReportData.value?.totalCents ?? 0;
  }
  if (scope.value === 'all') {
    return summaryReportData.value?.totalCents ?? 0;
  }
  return currentMonthTotalCents.value;
});

const displayCount = computed(() => {
  if (scope.value === 'month') {
    return currentMonthlyReport.value?.count ?? 0;
  }
  if (scope.value === 'year') {
    return yearlyReportData.value?.count ?? 0;
  }
  return summaryReportData.value?.count ?? 0;
});

const monthChangeRatio = computed(() => currentMonthlyReport.value?.change.ratio ?? null);
const monthChangeDelta = computed(() => currentMonthlyReport.value?.change.deltaCents ?? 0);

const monthTotalDays = computed(() => daysInMonth(scope.value === 'month' ? month.value : currentMonth()));

const currentMonthElapsed = computed(() =>
  Math.max(1, elapsedDays(scope.value === 'month' ? month.value : currentMonth())),
);

const dailyAverageCents = computed(() => {
  const total = displayTotalCents.value;
  return Math.round(total / currentMonthElapsed.value);
});

const estimatedMonthEndCents = computed<number | null>(() => {
  if (scope.value !== 'month') return null;
  if (currentMonthElapsed.value < 3) return null;
  return Math.round((displayTotalCents.value / currentMonthElapsed.value) * monthTotalDays.value);
});

const largestExpense = computed(() => currentMonthlyReport.value?.largest ?? null);

const dueTodos = computed(() => plansStore.dueTodos);
const dueTotalAmount = computed(() =>
  dueTodos.value.reduce((acc, t) => acc + t.amountCents, 0),
);
const hasOverdue = computed(() =>
  dueTodos.value.some((t) => urgencyOfOptional(t.repaymentDate) === 'overdue'),
);
const reminderTone = computed(() => reminderToneOf(dueTodos.value));

async function handleAck(todoId: string): Promise<void> {
  await planTodosApi.ack(todoId);
  await plansStore.loadDueTodos();
  ui.markDataChanged();
}

async function handleConfirm(todo: PlanTodo): Promise<void> {
  await plansStore.confirmTodo(todo.id);
  await plansStore.loadDueTodos();
  ui.markDataChanged();
}

async function handleSkip(todoId: string): Promise<void> {
  await plansStore.skipTodo(todoId);
  await plansStore.loadDueTodos();
  ui.markDataChanged();
}

// 年档与汇总档数据
const yearlyReportData = ref<YearlyReport | null>(null);
const summaryReportData = ref<SummaryReport | null>(null);

// 日历选中项
const selectedCalendarKey = ref<string | null>(null);
const selectedMonthReport = ref<MonthlyReport | null>(null);
const selectedYearReport = ref<YearlyReport | null>(null);
const loadingCard = ref(false);

const PAGE_SIZE = 100;
const today = todayLocal();

// ---------------------------------------------------------------------------
// 月档：流水加载
// ---------------------------------------------------------------------------

async function fetchPage(cursor: string | null): Promise<void> {
  try {
    // 搜索范围随档位：月=当月，年=全年，全部=全库历史
    const base = {
      by: 'spend_date' as const,
      categoryId: categoryId.value ?? undefined,
      paymentMethodId: paymentMethodId.value ?? undefined,
      q: keyword.value.trim() === '' ? undefined : keyword.value.trim(),
      limit: PAGE_SIZE,
      cursor: cursor ?? undefined,
    };
    const page = await expensesApi.list(
      scope.value === 'month'
        ? { ...base, month: month.value }
        : scope.value === 'year'
          ? { ...base, from: `${year.value}-01-01`, to: `${year.value}-12-31` }
          : base,
    );

    if (cursor === null) {
      // 检查本地是否有尚未同步至服务端的离线待发记录，融合展示在顶部
      const cached = await getCachedExpenses(month.value);
      const existingIds = new Set(page.items.map((i) => i.id));
      const pendingLocal = cached.filter(
        (c) => (c as { isOfflinePending?: boolean }).isOfflinePending && !existingIds.has(c.id),
      );
      items.value = [...pendingLocal, ...page.items];
      if (page.items.length > 0) {
        void saveCachedExpenses(page.items);
      }
    } else {
      items.value = [...items.value, ...page.items];
    }

    nextCursor.value = page.nextCursor;
    hasMore.value = page.hasMore;
  } catch (error) {
    // 离线容灾：如果网络断开且为首屏加载，优先从本地 IndexedDB 恢复展示
    if (cursor === null) {
      const cached = await getCachedExpenses(month.value);
      if (cached.length > 0) {
        items.value = cached;
        nextCursor.value = null;
        hasMore.value = false;
        return;
      }
    }
    if (error instanceof ApiError && error.status === 0) {
      items.value = [];
      nextCursor.value = null;
      hasMore.value = false;
      return;
    }
    throw error;
  }
}

async function reloadList(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  try {
    await fetchPage(null);
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      // 离线状态静默降级，不展示错误横幅
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载失败';
  } finally {
    loading.value = false;
  }
}

async function loadMore(): Promise<void> {
  if (!hasMore.value || loadingMore.value || nextCursor.value === null) return;
  loadingMore.value = true;
  try {
    await fetchPage(nextCursor.value);
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载更多失败';
  } finally {
    loadingMore.value = false;
  }
}

// ---------------------------------------------------------------------------
// 年档 & 全部档：日历与概况卡数据加载
// ---------------------------------------------------------------------------

async function loadYearData(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  try {
    const res = await reportsApi.yearly(year.value);
    yearlyReportData.value = res.report;

    const currentM = currentMonth();
    const candidateMonth = currentM.startsWith(year.value) ? currentM : `${year.value}-01`;
    selectedCalendarKey.value = candidateMonth;
    await loadSelectedMonthDetail(candidateMonth);
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      // 离线静默
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载年档日历失败';
  } finally {
    loading.value = false;
  }
}

async function loadSelectedMonthDetail(m: string): Promise<void> {
  loadingCard.value = true;
  try {
    const res = await reportsApi.monthly(m);
    selectedMonthReport.value = res.report;
  } catch {
    selectedMonthReport.value = null;
  } finally {
    loadingCard.value = false;
  }
}

async function loadSummaryData(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  try {
    const res = await reportsApi.summary();
    summaryReportData.value = res.report;

    const years = res.report.years;
    const latestYear = years.length > 0 ? years[years.length - 1]?.year : year.value;
    if (latestYear) {
      selectedCalendarKey.value = latestYear;
      await loadSelectedYearDetail(latestYear);
    }
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载汇总日历失败';
  } finally {
    loading.value = false;
  }
}

async function loadSelectedYearDetail(y: string): Promise<void> {
  loadingCard.value = true;
  try {
    const res = await reportsApi.yearly(y);
    selectedYearReport.value = res.report;
  } catch {
    selectedYearReport.value = null;
  } finally {
    loadingCard.value = false;
  }
}

async function loadTopCardData(): Promise<void> {
  try {
    const targetM = scope.value === 'month' ? month.value : currentMonth();
    const [mRes] = await Promise.all([
      reportsApi.monthly(targetM),
      plansStore.loadDueTodos(),
    ]);
    currentMonthlyReport.value = mRes.report;
    currentMonthTotalCents.value = mRes.report.totalCents;
  } catch {
    // 静默兜底
  }
}

async function refresh(): Promise<void> {
  loadTopCardData();
  if (scope.value === 'month' || isSearchActive.value) {
    // 搜索激活时即使处于年/全部档也展示跨期列表，日历暂不加载
    await reloadList();
  } else if (scope.value === 'year') {
    await loadYearData();
  } else {
    await loadSummaryData();
  }
}

onMounted(async () => {
  await dict.load();
  await refresh();
});

watch([scope, month, year], refresh);
watch([categoryId, paymentMethodId], () => {
  if (scope.value === 'month' || isSearchActive.value) reloadList();
});
watch(() => ui.dataVersion, refresh);

let searchTimer: ReturnType<typeof setTimeout> | undefined;
watch(keyword, () => {
  if (searchTimer !== undefined) clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    if (scope.value === 'month' || keyword.value.trim() !== '') {
      void reloadList();
    } else {
      // 关键词清空：从跨期搜索列表回到年/全部日历视图
      void refresh();
    }
  }, 300);
});

// ---------------------------------------------------------------------------
// 排序与筛选汇总
// ---------------------------------------------------------------------------

const sortedItems = computed(() => {
  if (sortBy.value === 'amount_desc') {
    return [...items.value].sort((a, b) => b.amountCents - a.amountCents);
  }
  return items.value;
});

const isFilterActive = computed(
  () => categoryId.value !== null || paymentMethodId.value !== null || keyword.value.trim() !== '',
);

const loadedTotal = computed(() =>
  items.value.reduce((sum, item) => sum + item.amountCents, 0),
);

// ---------------------------------------------------------------------------
// 日历与下钻交互
// ---------------------------------------------------------------------------

const yearCalendarCells = computed<CalendarCell[]>(() => {
  return (yearlyReportData.value?.months ?? []).map((m) => ({
    key: m.month,
    label: `${Number(m.month.slice(5))}月`,
    amountCents: m.totalCents,
    count: m.count,
  }));
});

const allCalendarCells = computed<CalendarCell[]>(() => {
  return (summaryReportData.value?.years ?? []).map((y) => ({
    key: y.year,
    label: `${y.year}年`,
    amountCents: y.totalCents,
    count: y.count,
  }));
});

async function onCalendarSelect(key: string): Promise<void> {
  selectedCalendarKey.value = key;
  if (scope.value === 'year') {
    await loadSelectedMonthDetail(key);
  } else if (scope.value === 'all') {
    await loadSelectedYearDetail(key);
  }
}

function onCalendarDrill(key: string): void {
  if (scope.value === 'year') {
    month.value = key;
    scope.value = 'month';
  } else if (scope.value === 'all') {
    year.value = key;
    scope.value = 'year';
  }
}

// ---------------------------------------------------------------------------
// 账期计算（A13 · A27）
// ---------------------------------------------------------------------------

function billingGraceDays(spendDate: string, repaymentDate: string): number {
  const [y1, m1, d1] = spendDate.split('-').map(Number);
  const [y2, m2, d2] = repaymentDate.split('-').map(Number);
  if (!y1 || !m1 || !d1 || !y2 || !m2 || !d2) return 0;
  const utc1 = Date.UTC(y1, m1 - 1, d1);
  const utc2 = Date.UTC(y2, m2 - 1, d2);
  return Math.max(0, Math.round((utc2 - utc1) / (24 * 60 * 60 * 1000)));
}
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+28px)]">
    <!-- 头部容器 -->
    <header class="bg-canvas px-4 pt-[calc(var(--safe-top)+12px)] pb-3 lg:px-6">
      <div class="mx-auto w-full max-w-[var(--content-max)] space-y-3">
        <!-- ===================================================================
             移动端顶卡（A20 · §6.6 三）：本月支出 + 处理提醒，逾期吸顶
             =================================================================== -->
        <div
          class="lg:hidden"
          :class="[hasOverdue ? 'sticky top-[calc(var(--safe-top)+8px)] z-[var(--z-sticky)]' : '']"
        >
          <!-- 支出 Hero 卡（始终全宽，背景深色质感，内嵌小巧提醒胶囊） -->
          <div
            class="relative overflow-hidden rounded-xl bg-gradient-to-br from-[#2563eb] via-[#1d4ed8] to-[#1e40af] p-4 text-on-primary shadow-xs"
          >
            <!-- 背景装饰光晕与水印（消除纯白与空白感，赋予质感） -->
            <div class="pointer-events-none absolute -right-6 -bottom-10 h-32 w-32 rounded-full bg-white/[0.08] ring-8 ring-white/[0.03]" />
            <div class="pointer-events-none absolute right-10 -top-8 h-24 w-24 rounded-full bg-white/[0.05]" />
            <div
              class="pointer-events-none absolute right-4 top-2 select-none font-sans font-black leading-none text-white/[0.07] text-6xl"
            >
              ¥
            </div>

            <!-- 卡片内容区 -->
            <div class="relative z-1">
              <!-- 顶栏：标题 + 内嵌小巧提醒胶囊 -->
              <div class="flex items-center justify-between gap-2">
                <div class="flex items-center gap-1.5 text-xs font-medium text-white/85 truncate">
                  <span class="inline-block h-1.5 w-1.5 rounded-full bg-emerald-300 shrink-0" />
                  <span class="truncate">{{ topCardTitle }}</span>
                </div>

                <!-- 缩小并包在卡片内部的提醒胶囊 -->
                <button
                  v-if="dueTodos.length > 0"
                  type="button"
                  class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-[11px] font-semibold transition-all cursor-pointer shrink-0 shadow-2xs"
                  :class="hasOverdue ? 'bg-red-500 text-white ring-1 ring-white/30' : 'bg-white/20 text-white hover:bg-white/30'"
                  @click="isTopCardExpanded = !isTopCardExpanded"
                >
                  <span
                    class="inline-block h-1.5 w-1.5 rounded-full shrink-0"
                    :class="hasOverdue ? 'bg-white animate-pulse' : (reminderTone === 'manual' ? 'bg-amber-300' : 'bg-emerald-300')"
                  />
                  <span>{{ hasOverdue ? '待办逾期' : `${dueTodos.length} 期待处理` }}</span>
                  <span class="font-bold tabular-nums">¥{{ formatCents(dueTotalAmount) }}</span>
                  <span
                    class="text-[9px] transition-transform duration-200"
                    :class="isTopCardExpanded ? 'rotate-180' : ''"
                  >
                    ▾
                  </span>
                </button>
              </div>

              <!-- 中间：大金额展示（自适应缩放） -->
              <div class="mt-2.5 min-w-0 overflow-hidden">
                <div class="flex items-baseline gap-0.5 whitespace-nowrap">
                  <span class="text-sm font-bold text-white/80 shrink-0">¥</span>
                  <span
                    class="font-extrabold tracking-tight tabular-nums text-white font-sans whitespace-nowrap"
                    :style="adaptiveAmountStyle(formatCents(displayTotalCents), 'card')"
                  >
                    {{ formatCents(displayTotalCents) }}
                  </span>
                </div>
              </div>

              <!-- 期间环比与亮点说明 -->
              <div class="mt-1 flex items-center justify-between text-xs text-white/85">
                <div class="truncate">
                  <span v-if="scope === 'month' && monthChangeRatio !== null" class="inline-flex items-center gap-1">
                    <span class="opacity-80">较上月</span>
                    <b :class="monthChangeRatio > 0 ? 'text-amber-200' : 'text-emerald-200'">
                      {{ monthChangeRatio > 0 ? '+' : '' }}{{ (monthChangeRatio * 100).toFixed(1) }}%
                    </b>
                    <span class="opacity-70 text-[11px]">
                      （{{ monthChangeDelta >= 0 ? '+' : '' }}{{ formatYuan(monthChangeDelta) }}）
                    </span>
                  </span>
                  <span v-else-if="scope === 'month'" class="opacity-70 text-[11px]">
                    首月记录
                  </span>
                  <span v-else-if="scope === 'year'" class="opacity-80">
                    {{ year }} 全年支出汇总
                  </span>
                  <span v-else class="opacity-80">
                    全量历史支出汇总
                  </span>
                </div>

                <div v-if="scope === 'month' && largestExpense" class="text-[11px] opacity-75 truncate max-w-[150px] shrink-0 text-right">
                  最高: {{ largestExpense.categoryName }} {{ formatCompact(largestExpense.cents) }}
                </div>
              </div>

              <!-- 底部：3 列结构化指标格（充实信息，消灭空洞感） -->
              <div class="mt-3 grid grid-cols-3 gap-2 border-t border-white/15 pt-2.5 text-xs text-white/90">
                <!-- 栏位 1: 日均 (月) / 月均 (年) -->
                <div>
                  <span class="block text-[11px] opacity-70">
                    {{ scope === 'month' ? '日均支出' : '月均支出' }}
                  </span>
                  <b class="mt-0.5 block text-sm font-bold tabular-nums">
                    <template v-if="scope === 'month'">
                      {{ formatYuan(dailyAverageCents) }}
                    </template>
                    <template v-else-if="scope === 'year'">
                      {{ formatYuan(Math.round(displayTotalCents / 12)) }}
                    </template>
                    <template v-else>
                      {{ formatCompact(summaryReportData?.monthlyAverageCents ?? 0) }}
                    </template>
                  </b>
                  <span class="mt-0.5 block text-[10px] opacity-60">
                    <template v-if="scope === 'month'">
                      已过 {{ currentMonthElapsed }} 天
                    </template>
                    <template v-else-if="scope === 'year'">
                      全年 12 个月
                    </template>
                    <template v-else>
                      历史月均
                    </template>
                  </span>
                </div>

                <!-- 栏位 2: 预计月末 (月) / 最高月 (年) -->
                <div>
                  <span class="block text-[11px] opacity-70">
                    {{ scope === 'month' ? '预计月末' : (scope === 'year' ? '最高支出月' : '历史最高月') }}
                  </span>
                  <b class="mt-0.5 block text-sm font-bold tabular-nums">
                    <template v-if="scope === 'month'">
                      {{ estimatedMonthEndCents !== null ? formatYuan(estimatedMonthEndCents) : '—' }}
                    </template>
                    <template v-else-if="scope === 'year'">
                      {{ yearlyReportData?.peakMonth ? formatCompact(yearlyReportData.peakMonth.totalCents) : '—' }}
                    </template>
                    <template v-else>
                      {{ summaryReportData?.peakMonth ? formatCompact(summaryReportData.peakMonth.totalCents) : '—' }}
                    </template>
                  </b>
                  <span class="mt-0.5 block text-[10px] opacity-60">
                    <template v-if="scope === 'month'">
                      {{ estimatedMonthEndCents !== null ? '按当前速度' : '数据积累中' }}
                    </template>
                    <template v-else-if="scope === 'year'">
                      {{ yearlyReportData?.peakMonth ? `${Number(yearlyReportData.peakMonth.month.slice(5))} 月` : '—' }}
                    </template>
                    <template v-else>
                      {{ summaryReportData?.peakMonth ? summaryReportData.peakMonth.month : '—' }}
                    </template>
                  </span>
                </div>

                <!-- 栏位 3: 交易笔数 / 单笔均 -->
                <div>
                  <span class="block text-[11px] opacity-70">
                    {{ scope === 'month' ? '交易笔数' : (scope === 'year' ? '年度笔数' : '总笔数') }}
                  </span>
                  <b class="mt-0.5 block text-sm font-bold tabular-nums">
                    {{ displayCount }} 笔
                  </b>
                  <span class="mt-0.5 block text-[10px] opacity-60">
                    <template v-if="scope === 'month'">
                      {{ displayCount > 0 ? `笔均 ${formatCompact(Math.round(displayTotalCents / displayCount))}` : '暂无交易' }}
                    </template>
                    <template v-else-if="scope === 'year'">
                      {{ displayCount > 0 ? `笔均 ${formatCompact(Math.round(displayTotalCents / displayCount))}` : '—' }}
                    </template>
                    <template v-else>
                      {{ `均 ${formatCompact(summaryReportData?.perExpenseAverageCents ?? 0)}/笔` }}
                    </template>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!--
            同步状态条（提醒卡区域常驻承载，用户裁决）：
            只由「待同步条目存在」驱动 —— 队列为空时即使离线也不显示（不制造焦虑）；
            离线时提示记录先存本机、恢复联网自动上传；在线待同步可点击立即推；
            同步成功后队列清空自动消失。无到期待办时它单独成条，有则位于展开明细上方。
          -->
          <button
            v-if="syncStore.hasPending || syncStore.isSyncing"
            type="button"
            class="mt-2 flex w-full items-center gap-1.5 rounded-lg px-3 py-1.5 text-left text-[11px] font-medium transition-colors lg:hidden"
            :class="syncStore.isSyncing
              ? 'bg-sunken text-primary-text'
              : 'bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300'"
            :title="syncStore.isSyncing
              ? '正在与服务器同步'
              : syncStore.isOnline
                ? '点击立即同步到服务器'
                : '当前离线：记录先存在本机，恢复联网后自动同步'"
            :disabled="syncStore.isSyncing || !syncStore.isOnline"
            @click="syncStore.runSync()"
          >
            <span
              class="inline-block h-1.5 w-1.5 shrink-0 rounded-full"
              :class="syncStore.isSyncing ? 'animate-pulse bg-primary' : syncStore.isOnline ? 'bg-amber-500' : 'bg-amber-500'"
            />
            <span class="truncate">
              <template v-if="syncStore.isSyncing">同步中…</template>
              <template v-else-if="syncStore.isOnline">
                待同步 {{ syncStore.pendingCount }} 条，点击立即上传
              </template>
              <template v-else>
                离线中 · {{ syncStore.pendingCount }} 条记录已存本机，联网后自动同步
              </template>
            </span>
          </button>

          <!-- 顶卡向下展开的待办明细与动作层（§6.5 三·补） -->
          <div
            v-if="isTopCardExpanded && dueTodos.length > 0"
            class="mt-2 divide-y divide-line/40 rounded-xl border border-line/60 bg-surface p-3 animate-in fade-in shadow-xs"
          >
            <div
              v-for="item in dueTodos"
              :key="item.id"
              class="flex items-center justify-between gap-2 py-2 text-xs"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-1.5">
                  <b class="tabular-nums font-bold text-ink">{{ formatYuan(item.amountCents) }}</b>
                  <span class="truncate text-ink-muted">{{ item.periodSeq }}期 · {{ item.planName }}</span>
                </div>
                <div class="mt-0.5 flex items-center gap-1.5 text-[11px]">
                  <span :class="URGENCY_META[urgencyOfOptional(item.repaymentDate)]">
                    {{ formatMonthDay(item.repaymentDate) }} · {{ urgencyLabel(item.repaymentDate) }}
                  </span>
                  <span class="text-ink-muted">
                    {{ reminderStateLabel(item.willAutoPost) }}
                  </span>
                </div>
              </div>

              <!-- 动作按钮 -->
              <div class="flex shrink-0 items-center gap-1">
                <template v-if="item.willAutoPost">
                  <button
                    type="button"
                    class="rounded-xs bg-sunken px-2 py-1 text-xs font-semibold text-ink hover:bg-line"
                    @click="handleAck(item.id)"
                  >
                    确认
                  </button>
                </template>
                <template v-else>
                  <button
                    type="button"
                    class="rounded-xs bg-primary px-2 py-1 text-xs font-semibold text-on-primary hover:opacity-90"
                    @click="handleConfirm(item)"
                  >
                    入账
                  </button>
                  <button
                    type="button"
                    class="rounded-xs bg-sunken px-2 py-1 text-xs font-semibold text-ink-muted hover:bg-line hover:text-ink"
                    @click="handleSkip(item.id)"
                  >
                    忽略
                  </button>
                </template>
              </div>
            </div>
          </div>
        </div>

        <!-- ===================================================================
             移动端控制行（A21 · §6.6 二·补）：期间靠左 + 三个入口靠右（随滚动滚走）
             =================================================================== -->
        <div class="flex items-center justify-between gap-2 lg:hidden">
          <div class="flex items-center gap-2">
            <PeriodPicker
              v-if="scope === 'month'"
              v-model:month="month"
              :label="formatMonthLabel(month)"
            />
            <PeriodPicker
              v-else-if="scope === 'year'"
              v-model:year="year"
              mode="year"
              :label="`${year} 年`"
            />
            <span v-else class="text-sm font-bold text-ink">全部记录</span>
          </div>

          <!-- 三个二级页入口（概况 · 报表 · 设置） -->
          <div class="flex items-center gap-2 text-xs font-semibold text-ink-muted">
            <RouterLink :to="{ name: 'dashboard' }" class="hover:text-ink">概况</RouterLink>
            <span>·</span>
            <RouterLink :to="{ name: 'report' }" class="hover:text-ink">报表</RouterLink>
            <span>·</span>
            <RouterLink :to="{ name: 'settings' }" class="hover:text-ink">设置</RouterLink>
          </div>
        </div>

        <!-- 移动端档位切换小药丸（月 / 年 / 全部） -->
        <div class="flex items-center justify-between lg:hidden pt-0.5">
          <div class="pill-tabs" role="tablist">
            <button
              type="button"
              :aria-pressed="scope === 'month'"
              :data-active="scope === 'month'"
              class="pill-tab"
              @click="scope = 'month'"
            >
              按月
            </button>
            <button
              type="button"
              :aria-pressed="scope === 'year'"
              :data-active="scope === 'year'"
              class="pill-tab"
              @click="scope = 'year'"
            >
              按年
            </button>
            <button
              type="button"
              :aria-pressed="scope === 'all'"
              :data-active="scope === 'all'"
              class="pill-tab"
              @click="scope = 'all'"
            >
              全部
            </button>
          </div>

          <!-- 仅月档显示的排序与筛选开关 -->
          <div v-if="scope === 'month'" class="flex items-center rounded-sm bg-sunken p-0.5 text-xs">
            <button
              type="button"
              class="rounded-xs px-2 py-0.5 text-[11px] font-medium transition-colors"
              :class="sortBy === 'date_desc' ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
              @click="sortBy = 'date_desc'"
            >
              最新
            </button>
            <button
              type="button"
              class="rounded-xs px-2 py-0.5 text-[11px] font-medium transition-colors"
              :class="sortBy === 'amount_desc' ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
              @click="sortBy = 'amount_desc'"
            >
              最贵
            </button>
            <button
              type="button"
              class="inline-flex items-center gap-1 rounded-xs px-2 py-0.5 text-[11px] font-medium transition-colors"
              :class="isFilterExpanded ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
              @click="isFilterExpanded = !isFilterExpanded"
            >
              <span>筛选</span>
              <span v-if="hasChipFilter" class="inline-block h-1.5 w-1.5 rounded-full bg-primary" />
            </button>
          </div>
        </div>

        <!-- 移动端搜索行（独占撑满，A21）：任何档位均可搜索，年/全部档为跨期搜索 -->
        <div class="lg:hidden">
          <input
            v-model="keyword"
            type="search"
            :placeholder="scope === 'month' ? '搜索分类或备注…' : scope === 'year' ? `搜索 ${year} 年流水…` : '搜索全部流水…'"
            class="w-full rounded-sm bg-sunken px-3 py-2 text-xs text-ink placeholder:text-ink-muted focus:ring-1 focus:ring-primary"
          />
        </div>

        <!-- ===================================================================
             桌面端顶栏控制（≥1024px）：期间选择 + 三档 Tabs + 搜索 + 排序
             =================================================================== -->
        <div class="hidden lg:flex lg:flex-wrap lg:items-center lg:justify-between lg:gap-3">
          <div class="flex items-center gap-3">
            <PeriodPicker
              v-if="scope === 'month'"
              v-model:month="month"
              :label="formatMonthLabel(month)"
            />
            <PeriodPicker
              v-else-if="scope === 'year'"
              v-model:year="year"
              mode="year"
              :label="`${year} 年`"
            />
            <span v-else class="text-sm font-bold text-ink">全部记录</span>

            <!-- 三档 Pill Tabs -->
            <div class="pill-tabs" role="tablist">
              <button
                type="button"
                :aria-pressed="scope === 'month'"
                :data-active="scope === 'month'"
                class="pill-tab"
                @click="scope = 'month'"
              >
                按月
              </button>
              <button
                type="button"
                :aria-pressed="scope === 'year'"
                :data-active="scope === 'year'"
                class="pill-tab"
                @click="scope = 'year'"
              >
                按年
              </button>
              <button
                type="button"
                :aria-pressed="scope === 'all'"
                :data-active="scope === 'all'"
                class="pill-tab"
                @click="scope = 'all'"
              >
                全部
              </button>
            </div>
          </div>

          <!-- 搜索与排序（搜索任何档位可用；排序仅月档列表有意义） -->
          <div class="flex items-center gap-2">
            <input
              v-model="keyword"
              type="search"
              :placeholder="scope === 'month' ? '搜索分类或备注…' : scope === 'year' ? `搜索 ${year} 年流水…` : '搜索全部流水…'"
              class="w-64 rounded-sm bg-sunken px-3 py-1.5 text-xs text-ink placeholder:text-ink-muted focus:ring-1 focus:ring-primary"
            />

            <div v-if="scope === 'month'" class="flex items-center rounded-sm bg-sunken p-0.5 text-xs">
              <button
                type="button"
                class="rounded-xs px-2.5 py-1 text-xs font-medium transition-colors"
                :class="sortBy === 'date_desc' ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
                @click="sortBy = 'date_desc'"
              >
                最新
              </button>
              <button
                type="button"
                class="rounded-xs px-2.5 py-1 text-xs font-medium transition-colors"
                :class="sortBy === 'amount_desc' ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
                @click="sortBy = 'amount_desc'"
              >
                最贵
              </button>
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-xs px-2.5 py-1 text-xs font-medium transition-colors"
                :class="isFilterExpanded ? 'bg-canvas text-ink shadow-xs font-semibold' : 'text-ink-muted'"
                @click="isFilterExpanded = !isFilterExpanded"
              >
                <span>筛选</span>
                <span v-if="hasChipFilter" class="inline-block h-1.5 w-1.5 rounded-full bg-primary" />
              </button>
            </div>
          </div>
        </div>

        <!-- 仅月档且展开时显示的筛选 Chips -->
        <template v-if="scope === 'month' && isFilterExpanded">
          <div class="flex flex-col gap-1.5 pt-1 animate-in fade-in">
            <div class="no-scrollbar flex gap-1.5 overflow-x-auto pb-1 lg:flex-wrap lg:overflow-visible lg:pb-0">
              <ChipButton :active="categoryId === null" @click="categoryId = null">全部分类</ChipButton>
              <ChipButton
                v-for="root in dict.rootCategories"
                :key="root.id"
                :active="categoryId === root.id"
                @click="categoryId = categoryId === root.id ? null : root.id"
              >
                <span class="inline-flex items-center gap-1.5">
                  <CategoryIcon :category-id="root.id" :size="13" />
                  <span>{{ root.name }}</span>
                </span>
              </ChipButton>
            </div>

            <div class="no-scrollbar flex gap-1.5 overflow-x-auto pb-1 lg:flex-wrap lg:overflow-visible lg:pb-0">
              <ChipButton :active="paymentMethodId === null" @click="paymentMethodId = null">
                全部方式
              </ChipButton>
              <ChipButton
                v-for="method in dict.paymentMethods"
                :key="method.id"
                :active="paymentMethodId === method.id"
                @click="paymentMethodId = paymentMethodId === method.id ? null : method.id"
              >
                <span class="inline-flex items-center gap-1.5">
                  <PaymentIcon :name="method.name" :icon="method.icon" :size="14" />
                  <span>{{ method.name }}</span>
                </span>
              </ChipButton>
            </div>
          </div>
        </template>

        <!-- 合计行：只有在有筛选时才展示金额，无筛选时仅展示笔数（§6.2 ③） -->
        <div v-if="scope === 'month' || isSearchActive" class="flex items-center justify-between text-xs text-ink-muted pt-0.5">
          <span>
            <template v-if="isFilterActive">
              筛选结果 <b>{{ items.length }}</b> 笔 · 合计 <b class="text-ink tabular-nums">{{ formatYuan(loadedTotal) }}</b>
            </template>
            <template v-else>
              共 {{ items.length }} 笔记录
            </template>
          </span>

          <button
            v-if="isFilterActive"
            type="button"
            class="text-xs text-primary hover:underline"
            @click="categoryId = null; paymentMethodId = null; keyword = '';"
          >
            清除筛选
          </button>
        </div>
      </div>
    </header>

    <main class="mx-auto mt-4 w-full max-w-[var(--content-max)] px-4 lg:px-6">
      <p v-if="errorMessage !== null" class="py-4 text-center text-sm text-danger-text">{{ errorMessage }}</p>
      <p v-else-if="loading" class="py-12 text-center text-sm text-ink-muted">加载中…</p>

      <!-- =====================================================================
           流水列表（无组头，一行一项，每段 100 笔）：
           月档常规展示；年/全部档输入搜索关键词时切换为跨期搜索结果
           ===================================================================== -->
      <template v-else-if="scope === 'month' || isSearchActive">
        <p v-if="items.length === 0" class="py-16 text-center text-sm text-ink-muted">
          {{ isFilterActive ? '没有符合筛选条件的记录' : scope === 'month' ? '本月还没有流水记录' : '没有符合条件的流水记录' }}
        </p>

        <template v-else>
          <!-- 桌面表格视图（加列用满宽度） -->
          <table class="hidden w-full lg:table" aria-label="流水明细">
            <thead>
              <tr class="border-b border-line text-left text-[11px] tracking-wider text-ink-muted">
                <th class="py-2 pr-3 font-bold">日期</th>
                <th class="py-2 pr-3 font-bold">分类</th>
                <th class="py-2 pr-3 font-bold">备注</th>
                <th class="py-2 pr-3 font-bold">支付方式</th>
                <th class="py-2 pr-3 font-bold">账期</th>
                <th class="py-2 pr-3 font-bold">记录人</th>
                <th class="py-2 text-right font-bold">金额</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in sortedItems"
                :key="row.id"
                class="cursor-pointer border-b border-line/50 transition-colors duration-150 hover:bg-sunken"
                @click="ui.openEdit(row)"
              >
                <td
                  class="whitespace-nowrap py-2.5 pr-3 align-middle"
                  :title="`${row.spendDate} · ${formatLedgerDate(row.spendDate, today).full}`"
                >
                  <span class="block text-sm font-semibold text-ink">
                    {{ formatLedgerDate(row.spendDate, today).dayText }}
                  </span>
                  <span class="block text-[11px] text-ink-muted">
                    {{ formatLedgerDate(row.spendDate, today).weekdayText }}
                  </span>
                </td>

                <td class="py-2.5 pr-3 align-middle">
                  <span class="flex items-center gap-2">
                    <CategoryIcon
                      :name="row.categoryName"
                      :icon="row.categoryIcon"
                      :color="row.parentCategoryColor ?? row.categoryColor"
                      :color-name="row.parentCategoryName ?? row.categoryName"
                      :size="18"
                    />
                    <span class="truncate text-sm font-medium text-ink">
                      {{
                        row.parentCategoryName === null
                          ? row.categoryName
                          : `${row.parentCategoryName} · ${row.categoryName}`
                      }}
                    </span>
                  </span>
                </td>

                <td class="max-w-[240px] truncate py-2.5 pr-3 text-xs text-ink-muted">
                  {{ row.note === '' ? '—' : row.note }}
                </td>

                <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-ink-muted">
                  <span class="inline-flex items-center gap-1.5">
                    <PaymentIcon :name="row.paymentMethodName" :size="13" />
                    <span>{{ row.paymentMethodName }}</span>
                  </span>
                </td>

                <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-ink-muted">
                  <template v-if="billingGraceDays(row.spendDate, row.repaymentDate) > 0">
                    {{ billingGraceDays(row.spendDate, row.repaymentDate) }} 天账期
                  </template>
                  <template v-else>—</template>
                </td>

                <td class="whitespace-nowrap py-2.5 pr-3 text-xs text-ink-muted">
                  {{ row.ownerName }}
                </td>

                <td
                  class="whitespace-nowrap py-2.5 text-right text-sm font-bold tabular-nums"
                  :class="row.amountCents < 0 ? 'text-danger-text' : 'text-ink'"
                >
                  {{ formatYuan(row.amountCents) }}
                </td>
              </tr>
            </tbody>
          </table>

          <!-- 移动端 / 窄屏：双行紧凑布局（主行：分类全名 + 金额；次行：支付方式 + 完整备注 + 账期） -->
          <ul class="divide-y divide-line/40 lg:hidden">
            <li v-for="row in sortedItems" :key="row.id">
              <button
                type="button"
                class="flex w-full items-center gap-3 py-2.5 px-1 text-left transition-colors duration-150 active:bg-sunken"
                @click="ui.openEdit(row)"
              >
                <!-- 日期格：最远支持 2 天简化显示（今日星期一 / 昨日星期日 / 26日星期六） -->
                <span
                  class="w-11 shrink-0 text-center leading-tight whitespace-nowrap"
                  :title="`${row.spendDate} · ${formatLedgerDate(row.spendDate, today).full}`"
                >
                  <span class="block text-xs font-bold text-ink">
                    {{ formatLedgerDate(row.spendDate, today).dayText }}
                  </span>
                  <span class="block text-[10px] text-ink-muted">
                    {{ formatLedgerDate(row.spendDate, today).weekdayText }}
                  </span>
                </span>

                <!-- 图标 -->
                <span class="shrink-0 text-ink-muted">
                  <CategoryIcon
                    :name="row.categoryName"
                    :icon="row.categoryIcon"
                    :color="row.parentCategoryColor ?? row.categoryColor"
                    :color-name="row.parentCategoryName ?? row.categoryName"
                    :size="20"
                  />
                </span>

                <!-- 中间与右侧主体区：上下双行分层 -->
                <div class="flex min-w-0 flex-1 flex-col justify-center gap-0.5">
                  <!-- 主行：分类名（左） + 金额（右） -->
                  <div class="flex items-baseline justify-between gap-2">
                    <span class="truncate text-sm font-medium text-ink">
                      {{ row.parentCategoryName === null ? row.categoryName : `${row.parentCategoryName} · ${row.categoryName}` }}
                    </span>
                    <span
                      class="shrink-0 text-sm font-bold tabular-nums text-right whitespace-nowrap"
                      :class="row.amountCents < 0 ? 'text-danger-text' : 'text-ink'"
                    >
                      {{ formatYuan(row.amountCents) }}
                    </span>
                  </div>

                  <!-- 副信息行：支付方式 + 备注 + 账期/记录人 -->
                  <div class="flex items-center justify-between gap-2 text-xs text-ink-muted">
                    <div class="flex items-center gap-1.5 min-w-0 flex-1 overflow-hidden">
                      <span class="inline-flex items-center gap-1 shrink-0">
                        <PaymentIcon :name="row.paymentMethodName" :size="12" />
                        <span>{{ row.paymentMethodName }}</span>
                      </span>
                      <template v-if="row.note">
                        <span class="text-ink-muted/40 shrink-0">·</span>
                        <span class="truncate text-ink-muted/90">{{ row.note }}</span>
                      </template>
                    </div>

                    <span
                      v-if="billingGraceDays(row.spendDate, row.repaymentDate) > 0"
                      class="shrink-0 text-[11px] text-ink-muted/80 whitespace-nowrap"
                    >
                      {{ billingGraceDays(row.spendDate, row.repaymentDate) }}天账期
                    </span>
                    <span
                      v-else-if="row.ownerName"
                      class="shrink-0 text-[11px] text-ink-muted/70 whitespace-nowrap"
                    >
                      {{ row.ownerName }}
                    </span>
                  </div>
                </div>
              </button>
            </li>
          </ul>

          <!-- 加载更多 / 查看上月 -->
          <button
            v-if="hasMore"
            type="button"
            :disabled="loadingMore"
            class="mt-4 w-full rounded-sm bg-sunken py-3 text-xs font-semibold text-ink transition-colors hover:bg-line disabled:opacity-50"
            @click="loadMore"
          >
            {{ loadingMore ? '加载中…' : '加载更多' }}
          </button>
          <div v-else-if="items.length > 0" class="mt-8 flex flex-col items-center gap-2 pb-6">
            <p class="text-xs text-ink-muted">{{ scope === 'month' ? '已显示本月全部记录' : '已显示范围内全部记录' }}</p>
            <button
              v-if="scope === 'month'"
              type="button"
              class="inline-flex items-center gap-1.5 rounded-md border border-line bg-surface px-4 py-2 text-xs font-semibold text-ink shadow-sm transition-colors hover:bg-sunken active:scale-95"
              @click="goToPreviousMonth"
            >
              <span>查看上月（{{ previousMonthLabel }}）</span>
              <span aria-hidden="true">→</span>
            </button>
          </div>
        </template>
      </template>

      <!-- =====================================================================
           年档：12 个月格日历 + 选中月概况卡（A26 · §6.3.3）
           ===================================================================== -->
      <template v-else-if="scope === 'year'">
        <div class="space-y-4">
          <!-- 12 格日历 -->
          <ReportCalendar
            mode="year"
            :items="yearCalendarCells"
            :selected-key="selectedCalendarKey"
            @select="onCalendarSelect"
            @drill="onCalendarDrill"
          />

          <!-- 选中月的下方概况卡 -->
          <section
            v-if="selectedCalendarKey"
            class="rounded-md border border-line/60 bg-subtle p-4 lg:p-5"
          >
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-sm font-bold text-ink">
                  {{ formatMonthLabel(selectedCalendarKey) }} 概况
                </h3>
                <span class="text-xs text-ink-muted">点击日历格切换，点击下方按钮或再次点击日历格查看明细</span>
              </div>

              <!-- 下钻按钮 -->
              <button
                type="button"
                class="rounded-sm bg-primary px-3 py-1.5 text-xs font-semibold text-on-primary transition-opacity hover:opacity-90"
                @click="onCalendarDrill(selectedCalendarKey)"
              >
                进入流水列表 →
              </button>
            </div>

            <!-- 数据项 -->
            <div v-if="loadingCard" class="py-6 text-center text-xs text-ink-muted">
              加载中…
            </div>
            <div v-else-if="selectedMonthReport" class="mt-4 space-y-4">
              <div class="grid grid-cols-3 gap-3">
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">本月支出</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ formatYuan(selectedMonthReport.totalCents) }}
                  </b>
                </div>
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">记账笔数</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ selectedMonthReport.count }} 笔
                  </b>
                </div>
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">日均消费</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ formatYuan(Math.round(selectedMonthReport.totalCents / daysInMonth(selectedCalendarKey))) }}
                  </b>
                </div>
              </div>

              <!-- 分类分布 TOP 5 -->
              <div v-if="selectedMonthReport.categories.length > 0">
                <span class="block text-xs font-semibold text-ink-muted mb-2">主要支出分类</span>
                <ul class="space-y-1.5">
                  <li
                    v-for="cat in selectedMonthReport.categories.slice(0, 5)"
                    :key="cat.categoryId"
                    class="flex items-center justify-between text-xs"
                  >
                    <span class="flex items-center gap-2">
                      <span
                        class="h-2 w-2 rounded-xs"
                        :style="{ background: categoryColorVar(dict.colorOf(cat.categoryId, cat.name, cat.color)) }"
                      />
                      <span class="text-ink">{{ cat.name }}</span>
                    </span>
                    <div class="flex items-center gap-3">
                      <span class="text-ink-muted tabular-nums">{{ (cat.ratio * 100).toFixed(0) }}%</span>
                      <span class="font-bold text-ink tabular-nums">{{ formatYuan(cat.cents) }}</span>
                    </div>
                  </li>
                </ul>
              </div>
            </div>
          </section>
        </div>
      </template>

      <!-- =====================================================================
           全部档（汇总）：一格一年日历 + 选中年概况卡（A26 · §6.3.3）
           ===================================================================== -->
      <template v-else>
        <div class="space-y-4">
          <!-- 全部年份日历 -->
          <ReportCalendar
            mode="all"
            :items="allCalendarCells"
            :selected-key="selectedCalendarKey"
            @select="onCalendarSelect"
            @drill="onCalendarDrill"
          />

          <!-- 选中年的下方概况卡 -->
          <section
            v-if="selectedCalendarKey"
            class="rounded-md border border-line/60 bg-subtle p-4 lg:p-5"
          >
            <div class="flex items-center justify-between">
              <div>
                <h3 class="text-sm font-bold text-ink">
                  {{ selectedCalendarKey }} 年概况
                </h3>
                <span class="text-xs text-ink-muted">点击年份切换，点击下方按钮或再次点击日历格下钻到该年月历</span>
              </div>

              <!-- 下钻按钮 -->
              <button
                type="button"
                class="rounded-sm bg-primary px-3 py-1.5 text-xs font-semibold text-on-primary transition-opacity hover:opacity-90"
                @click="onCalendarDrill(selectedCalendarKey)"
              >
                进入年度日历 →
              </button>
            </div>

            <!-- 数据项 -->
            <div v-if="loadingCard" class="py-6 text-center text-xs text-ink-muted">
              加载中…
            </div>
            <div v-else-if="selectedYearReport" class="mt-4 space-y-4">
              <div class="grid grid-cols-3 gap-3">
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">全年支出</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ formatYuan(selectedYearReport.totalCents) }}
                  </b>
                </div>
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">记账笔数</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ selectedYearReport.count }} 笔
                  </b>
                </div>
                <div class="rounded-sm bg-canvas/60 p-3">
                  <span class="block text-xs text-ink-muted">月均消费</span>
                  <b class="mt-1 block text-base font-bold text-ink tabular-nums">
                    {{ formatYuan(Math.round(selectedYearReport.totalCents / 12)) }}
                  </b>
                </div>
              </div>

              <!-- 分类分布 TOP 5 -->
              <div v-if="selectedYearReport.categories.length > 0">
                <span class="block text-xs font-semibold text-ink-muted mb-2">年度主要支出分类</span>
                <ul class="space-y-1.5">
                  <li
                    v-for="cat in selectedYearReport.categories.slice(0, 5)"
                    :key="cat.categoryId"
                    class="flex items-center justify-between text-xs"
                  >
                    <span class="flex items-center gap-2">
                      <span
                        class="h-2 w-2 rounded-xs"
                        :style="{ background: categoryColorVar(dict.colorOf(cat.categoryId, cat.name, cat.color)) }"
                      />
                      <span class="text-ink">{{ cat.name }}</span>
                    </span>
                    <div class="flex items-center gap-3">
                      <span class="text-ink-muted tabular-nums">{{ (cat.ratio * 100).toFixed(0) }}%</span>
                      <span class="font-bold text-ink tabular-nums">{{ formatYuan(cat.cents) }}</span>
                    </div>
                  </li>
                </ul>
              </div>
            </div>
          </section>
        </div>
      </template>
    </main>
  </div>
</template>
