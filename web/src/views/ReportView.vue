<script setup lang="ts">
/**
 * 报表页：统计（结构 + 对照 + 精度）。
 *
 * 铁律（§五 第 3 条 · §6.3 · A17）：
 *   1. 分类唯一的家 —— 一级构成、二级下钻、排行、涨跌榜全在这里。
 *   2. 环图中心不显示合计（显示分类数，总量属于概况 hero）。
 *   3. 换档即换块：月 8 块 · 年 7 块 · 汇总 5 块。
 *   4. 卡片一律按内容高（.card-grid），并排卡片高度平衡。
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, RouterLink } from 'vue-router';
import { Sparkles } from '@lucide/vue';

import {
  ApiError,
  reports as reportsApi,
  type CategoryBucket,
  type MonthlyReport,
  type PaymentMethodType,
  type SummaryReport,
  type YearlyReport,
} from '@/api';
import PaymentIcon from '@/components/PaymentIcon.vue';
import PeriodPicker from '@/components/PeriodPicker.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import { categoryColorVar } from '@/utils/category-colors';
import { currentMonth, elapsedDays, formatMonthDay, formatMonthLabel } from '@/utils/dates';
import { buildDonutArcs, DONUT_RADIUS } from '@/utils/donut';
import { getCachedExpenses } from '@/utils/idb';
import { formatCompact, formatYuan } from '@/utils/money';
import {
  buildMonthlyReportFallback,
  buildSummaryReportFallback,
  buildYearlyReportFallback,
} from '@/utils/offline-stats';

const route = useRoute();
const ui = useUiStore();
const dict = useDictionariesStore();
const syncStore = useSyncStore();

type Scope = 'month' | 'year' | 'all';

const scope = ref<Scope>('month');
const month = ref(currentMonth());
const year = ref(String(new Date().getFullYear()));

// 路由查询参数同步
if (typeof route.query.month === 'string' && route.query.month) {
  scope.value = 'month';
  month.value = route.query.month;
} else if (typeof route.query.year === 'string' && route.query.year) {
  scope.value = 'year';
  year.value = route.query.year;
} else if (route.query.scope === 'all') {
  scope.value = 'all';
}

const monthly = ref<MonthlyReport | null>(null);
const yearly = ref<YearlyReport | null>(null);
const summary = ref<SummaryReport | null>(null);

const loading = ref(true);
const errorMessage = ref<string | null>(null);

/**
 * 是否处于「离线本地口径」：最近一次请求因网络不可达（status 0）失败。
 * 为 true 时下面几个 computed 展示的是本地缓存流水聚合的结果。
 */
const isOffline = ref(false);

// 展开的二级分类集合
const expandedCategoryIds = ref<Set<string>>(new Set());

// 按天节奏中被选中的点
const selectedDailyPoint = ref<{ day: number; date: string; cents: number; count: number } | null>(null);

async function load(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  selectedDailyPoint.value = null;

  try {
    if (scope.value === 'month') {
      const res = await reportsApi.monthly(month.value);
      monthly.value = res.report;
    } else if (scope.value === 'year') {
      const res = await reportsApi.yearly(year.value);
      yearly.value = res.report;
    } else {
      const res = await reportsApi.summary();
      summary.value = res.report;
    }
    isOffline.value = false;
  } catch (error) {
    if (error instanceof ApiError && error.status === 0) {
      // 离线：在线报表不可用，改用本地缓存流水聚合的报表。
      // 这样离线记一笔后，ui.dataVersion 变化触发重算，分类/支付/总额立刻刷新。
      isOffline.value = true;
      await loadOfflineReports();
      return;
    }
    errorMessage.value = error instanceof ApiError ? error.message : '加载报表失败，请重试';
  } finally {
    loading.value = false;
  }
}

/**
 * 用本地缓存流水构造报表形状的对象，塞回原来的 monthly/yearly/summary ref，
 * 使模板里既有的字段绑定（分类构成、支付统计、总额、笔数…）无需改造即可消费。
 */
async function loadOfflineReports(): Promise<void> {
  const cached = await getCachedExpenses();
  monthly.value = buildMonthlyReportFallback(cached, month.value);
  yearly.value = buildYearlyReportFallback(cached, year.value);
  summary.value = buildSummaryReportFallback(cached);
}

onMounted(() => {
  dict.load();
  load();
});
watch([scope, month, year], load);
watch(() => ui.dataVersion, load);

// 网络恢复后重新拉服务端数据：服务端是权威，用在线口径覆盖本地回退。
watch(
  () => syncStore.isOnline,
  (online) => {
    if (online) void load();
  },
);

// ---------------------------------------------------------------------------
// 基础统计与分类构成
// ---------------------------------------------------------------------------

const totalCents = computed(() => {
  if (scope.value === 'month') return monthly.value?.totalCents ?? 0;
  if (scope.value === 'year') return yearly.value?.totalCents ?? 0;
  return summary.value?.totalCents ?? 0;
});

const currentTotalCount = computed(() => {
  if (scope.value === 'month') return monthly.value?.count ?? 0;
  if (scope.value === 'year') return yearly.value?.count ?? 0;
  return summary.value?.count ?? 0;
});

const categories = computed<CategoryBucket[]>(() => {
  if (scope.value === 'month') return monthly.value?.categories ?? [];
  if (scope.value === 'year') return yearly.value?.categories ?? [];
  return summary.value?.categories ?? [];
});

const periodLabel = computed(() => {
  if (scope.value === 'month') return formatMonthLabel(month.value);
  if (scope.value === 'year') return `${year.value} 年`;
  return '全部汇总';
});

const allSpanLabel = computed(() => {
  if (!summary.value) return '全部历史记录';
  const s = summary.value;
  if (!s.firstRepaymentDate) return '全部历史记录';
  const yearsCount = s.years.length;
  return `${s.firstRepaymentDate} 至 ${s.lastRepaymentDate} · 共 ${s.recordedDays} 天（${yearsCount} 年）`;
});

/** 环图弧段（中心显示分类数，不显示合计） */
const donutArcs = computed(() =>
  buildDonutArcs(
    categories.value.map((item) => ({
      id: item.categoryId,
      ratio: item.ratio,
      color: categoryColorVar(dict.colorOf(item.categoryId, item.name, item.color)),
    })),
  ),
);

function toggleExpand(categoryId: string): void {
  const next = new Set(expandedCategoryIds.value);
  if (next.has(categoryId)) {
    next.delete(categoryId);
  } else {
    next.add(categoryId);
  }
  expandedCategoryIds.value = next;
}

// ---------------------------------------------------------------------------
// 对照（Block 4）：月档 4 项，年档 4 项，汇总档隐藏
// ---------------------------------------------------------------------------

function ratioText(ratio: number | null): string {
  if (ratio === null) return '—';
  const percent = ratio * 100;
  if (Math.abs(percent) < 0.5) return '持平';
  return `${percent > 0 ? '+' : ''}${percent.toFixed(0)}%`;
}

function ratioTone(ratio: number | null): string {
  if (ratio === null || Math.abs(ratio * 100) < 0.5) return 'text-ink-muted';
  return ratio > 0 ? 'text-danger-text' : 'text-secondary-text';
}

interface Metric {
  label: string;
  value: string;
  hint: string;
  tone: string;
}

const comparisonMetrics = computed<Metric[]>(() => {
  if (scope.value === 'month') {
    const data = monthly.value;
    if (!data) return [];

    const avg12 = data.average12MonthsCents ?? 0;
    const avgRatio = avg12 > 0 ? (data.totalCents - avg12) / avg12 : null;

    return [
      {
        label: '较上月',
        value: ratioText(data.change.ratio),
        hint: `上月 ${formatCompact(data.previous.totalCents)}`,
        tone: ratioTone(data.change.ratio),
      },
      {
        label: '去年同月',
        value: ratioText(data.yearAgo.change.ratio),
        hint: `去年同期 ${formatCompact(data.yearAgo.totalCents)}`,
        tone: ratioTone(data.yearAgo.change.ratio),
      },
      {
        label: '近 12 个月均值',
        value: formatCompact(avg12),
        hint: avg12 > 0 ? `比均值 ${ratioText(avgRatio)}` : '历史暂无数据',
        tone: ratioTone(avgRatio),
      },
      {
        label: '单笔最高',
        value: data.largest ? formatCompact(data.largest.cents) : '—',
        hint: data.largest ? `${data.largest.categoryName} · ${formatMonthDay(data.largest.repaymentDate)}` : '本月无记录',
        tone: 'text-ink',
      },
    ];
  }

  if (scope.value === 'year') {
    const data = yearly.value;
    if (!data) return [];

    const avg3Y = data.average3YearsCents ?? 0;
    const avg3YRatio = avg3Y > 0 ? (data.totalCents - avg3Y) / avg3Y : null;

    return [
      {
        label: '较去年',
        value: ratioText(data.yearAgo.change.ratio),
        hint: `去年 ${formatCompact(data.yearAgo.totalCents)}`,
        tone: ratioTone(data.yearAgo.change.ratio),
      },
      {
        label: '近 3 年均值',
        value: formatCompact(avg3Y),
        hint: avg3Y > 0 ? `比均值 ${ratioText(avg3YRatio)}` : '历史暂无数据',
        tone: ratioTone(avg3YRatio),
      },
      {
        label: '最高月',
        value: data.peakMonth && data.peakMonth.totalCents > 0 ? `${Number(data.peakMonth.month.slice(5))} 月` : '—',
        hint: data.peakMonth && data.peakMonth.totalCents > 0 ? formatCompact(data.peakMonth.totalCents) : '各月均 0',
        tone: 'text-ink',
      },
      {
        label: '单笔最高',
        value: data.largest ? formatCompact(data.largest.cents) : '—',
        hint: data.largest ? `${data.largest.categoryName} · ${formatMonthDay(data.largest.repaymentDate)}` : '本年无记录',
        tone: 'text-ink',
      },
    ];
  }

  return [];
});

// ---------------------------------------------------------------------------
// 期内节奏（Block 3）
// ---------------------------------------------------------------------------

const dailyList = computed(() => monthly.value?.daily ?? []);
const maxDailyCents = computed(() => Math.max(1, ...dailyList.value.map((d) => d.cents)));

const monthElapsed = computed(() => Math.max(1, elapsedDays(month.value)));
const dailyAverageCents = computed(() => Math.round((monthly.value?.totalCents ?? 0) / monthElapsed.value));

function selectDailyPoint(point: { day: number; date: string; cents: number; count: number }): void {
  if (selectedDailyPoint.value?.day === point.day) {
    selectedDailyPoint.value = null;
  } else {
    selectedDailyPoint.value = point;
  }
}

const maxMonthCents = computed(() =>
  Math.max(1, ...(yearly.value?.months ?? []).map((m) => m.totalCents)),
);

const maxYearCents = computed(() =>
  Math.max(1, ...(summary.value?.years ?? []).map((y) => y.totalCents)),
);

function jumpToMonth(targetMonth: string): void {
  scope.value = 'month';
  month.value = targetMonth;
}

function jumpToYear(targetYear: string): void {
  scope.value = 'year';
  year.value = targetYear;
}

// ---------------------------------------------------------------------------
// 涨跌榜（Block 5）：月档较上月、年档较去年，汇总档隐藏
// 阈值：±¥50 或 ±3% 取较高者
// ---------------------------------------------------------------------------

interface MoverItem {
  categoryId: string;
  name: string;
  color?: string | null;
  cents: number;
  previousCents: number;
  deltaCents: number;
  changeRatio: number | null;
  reason: string;
  isNew: boolean;
}

const movers = computed<MoverItem[]>(() => {
  if (scope.value === 'all') return [];

  const list: MoverItem[] = [];

  for (const item of categories.value) {
    const prev = item.previousCents ?? 0;
    const delta = item.cents - prev;
    const isNew = prev === 0 && item.cents > 0;

    // 判据：变化额绝对值 >= ¥50 (5000分) 或 变化比率 >= 3%
    const ratioMeet = item.changeRatio !== null && Math.abs(item.changeRatio) >= 0.03;
    const deltaMeet = Math.abs(delta) >= 5000;

    if (!isNew && !ratioMeet && !deltaMeet) continue;

    let reason = '';
    if (isNew) {
      reason = scope.value === 'month' ? '本月独有支出' : '本年独有支出';
    } else if (delta > 0) {
      reason = `较上期增加 ${formatYuan(delta)}`;
    } else if (delta < 0) {
      reason = `较上期减少 ${formatYuan(Math.abs(delta))}`;
    } else {
      reason = '持平';
    }

    list.push({
      categoryId: item.categoryId,
      name: item.name,
      color: item.color,
      cents: item.cents,
      previousCents: prev,
      deltaCents: delta,
      changeRatio: item.changeRatio,
      reason,
      isNew,
    });
  }

  return list.sort((a, b) => Math.abs(b.deltaCents) - Math.abs(a.deltaCents)).slice(0, 6);
});

// ---------------------------------------------------------------------------
// 还款节奏（Block 6）：仅月档显示，年档与汇总档隐藏
// ---------------------------------------------------------------------------

function toShare(cents: number): number {
  return totalCents.value === 0 ? 0 : cents / totalCents.value;
}

const paymentRows = computed(() => {
  const source = monthly.value?.paymentMethods ?? [];
  return source.map((item) => ({
    key: item.paymentMethodId,
    name: item.name,
    cents: item.cents,
    count: item.count,
    share: toShare(item.cents),
    type: item.type as PaymentMethodType,
    repaymentDate: item.repaymentDate,
  }));
});

const nextMonthRepayments = computed(() => monthly.value?.nextMonthRepayments ?? []);
const nextMonthRepaymentsTotalCents = computed(() =>
  nextMonthRepayments.value.reduce((acc, item) => acc + item.cents, 0),
);

// ---------------------------------------------------------------------------
// 本期洞察（Block 7）：规则生成
// ---------------------------------------------------------------------------

const insights = computed<string[]>(() => {
  if (scope.value === 'month') {
    const data = monthly.value;
    if (!data) return [];
    const list: string[] = [];

    // 规则 1: 单笔最大支出
    if (data.largest && data.largest.cents > 0) {
      list.push(
        `单笔最大支出为【${data.largest.categoryName}】${formatYuan(data.largest.cents)}，记于 ${formatMonthDay(data.largest.repaymentDate)}。`,
      );
    } else {
      list.push('本月暂无单笔大额支出记录。');
    }

    // 规则 2: 环比最大涨幅项
    const risingCats = categories.value
      .map((c) => ({ name: c.name, delta: c.cents - (c.previousCents ?? 0) }))
      .filter((c) => c.delta > 0)
      .sort((a, b) => b.delta - a.delta);

    const topRising = risingCats[0];
    if (topRising && topRising.delta > 0) {
      list.push(
        `【${topRising.name}】较上月增加 ${formatYuan(topRising.delta)}，为本月支出增幅最大的分类。`,
      );
    } else {
      list.push('本月各分类支出整体受控，未见明显环比激增项。');
    }

    // 规则 3: 日均消费 vs 3 个月基线，或下月待还
    const r3Avg = data.rolling3MonthsDailyAverageCents;
    if (typeof r3Avg === 'number' && r3Avg > 0) {
      const diffRatio = (dailyAverageCents.value - r3Avg) / r3Avg;
      const percentStr = Math.abs(Math.round(diffRatio * 100));
      if (Math.abs(diffRatio) < 0.05) {
        list.push(`本月日均支出 ${formatYuan(dailyAverageCents.value)}，与近 3 个月日均水平持平。`);
      } else {
        list.push(
          `本月日均支出 ${formatYuan(dailyAverageCents.value)}，较近 3 个月日均（${formatYuan(r3Avg)}）${diffRatio > 0 ? '偏高' : '偏低'} ${percentStr}%。`,
        );
      }
    } else if (nextMonthRepaymentsTotalCents.value > 0) {
      list.push(
        `下月已有 ${formatYuan(nextMonthRepaymentsTotalCents.value)} 信用卡账单待还，请注意流动资金安排。`,
      );
    } else {
      list.push(`本月共记录 ${data.count} 笔支出，总计 ${formatYuan(data.totalCents)}。`);
    }

    return list;
  }

  if (scope.value === 'year') {
    const data = yearly.value;
    if (!data) return [];
    const list: string[] = [];

    // 规则 1: 峰值月份
    if (data.peakMonth && data.peakMonth.totalCents > 0) {
      const peakM = Number(data.peakMonth.month.slice(5));
      list.push(
        `年度支出峰值在 ${peakM} 月，单月支出 ${formatYuan(data.peakMonth.totalCents)}。`,
      );
    } else {
      list.push('本年各月份消费节奏平缓，暂无突出峰值。');
    }

    // 规则 2: 年度第一大分类
    const topYearCat = categories.value[0];
    if (topYearCat) {
      list.push(
        `年度第一大支出为【${topYearCat.name}】，共 ${formatYuan(topYearCat.cents)}，占全年支出的 ${(topYearCat.ratio * 100).toFixed(0)}%。`,
      );
    }

    // 规则 3: 同比变化
    if (data.yearAgo.totalCents > 0) {
      const delta = data.yearAgo.change.deltaCents;
      const ratioStr = data.yearAgo.change.ratio !== null
        ? `（${data.yearAgo.change.ratio > 0 ? '+' : ''}${(data.yearAgo.change.ratio * 100).toFixed(0)}%）`
        : '';
      list.push(
        `全年总支出较去年同期 ${delta >= 0 ? '增加' : '减少'} ${formatYuan(Math.abs(delta))}${ratioStr}。`,
      );
    } else {
      list.push(`本年累计完成 ${data.count} 笔支出记录。`);
    }

    return list;
  }

  // 汇总档
  const data = summary.value;
  if (!data) return [];
  const list: string[] = [];

  if (data.firstRepaymentDate) {
    list.push(
      `自 ${data.firstRepaymentDate} 至今累计记录 ${data.recordedDays} 天（跨越 ${data.years.length} 年），共计沉淀 ${data.count} 笔真实账目。`,
    );
  } else {
    list.push(`累计记录 ${data.count} 笔支出。`);
  }

  const topSumCat = categories.value[0];
  if (topSumCat) {
    list.push(
      `历史支出最多的分类为【${topSumCat.name}】，累计花费 ${formatYuan(topSumCat.cents)}，占全部支出的 ${(topSumCat.ratio * 100).toFixed(0)}%。`,
    );
  }

  return list;
});

// ---------------------------------------------------------------------------
// 按记录人（Block 8）
// ---------------------------------------------------------------------------

const memberRows = computed(() => {
  const source =
    scope.value === 'month'
      ? monthly.value?.members
      : scope.value === 'year'
        ? yearly.value?.members
        : summary.value?.members;

  return (source ?? []).map((item) => ({
    key: item.ownerId,
    name: item.name,
    cents: item.cents,
    count: item.count,
    share: toShare(item.cents),
  }));
});
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+32px)]">
    <!-- ① 顶栏：三档切换 + 期间选择器（去掉大数字，总量归概况 hero） -->
    <header class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+16px)] lg:px-6 lg:pt-8">
      <div class="relative flex flex-col items-center gap-3">
        <!-- 窄屏关闭按键（A24），返回流水落地页 -->
        <RouterLink
          :to="{ name: 'ledger' }"
          class="absolute right-0 top-0 grid h-10 w-10 place-items-center rounded-sm text-sm font-bold text-ink-muted transition-colors hover:bg-sunken hover:text-ink after:absolute after:-inset-0.5 after:rounded-sm after:content-[''] lg:hidden"
          aria-label="关闭报表，返回流水"
        >
          ✕
        </RouterLink>

        <!-- 档位切换（换档 = 换整组块） -->
        <div class="pill-tabs" role="tablist">
          <button
            type="button"
            :aria-pressed="scope === 'month'"
            :data-active="scope === 'month'"
            class="pill-tab"
            @click="scope = 'month'"
          >
            本月
          </button>
          <button
            type="button"
            :aria-pressed="scope === 'year'"
            :data-active="scope === 'year'"
            class="pill-tab"
            @click="scope = 'year'"
          >
            今年
          </button>
          <button
            type="button"
            :aria-pressed="scope === 'all'"
            :data-active="scope === 'all'"
            class="pill-tab"
            @click="scope = 'all'"
          >
            汇总
          </button>
        </div>

        <!-- 期间选择器 -->
        <div class="flex justify-center">
          <PeriodPicker
            v-if="scope === 'month'"
            v-model:month="month"
            align="center"
            :label="periodLabel"
          />
          <PeriodPicker
            v-else-if="scope === 'year'"
            v-model:year="year"
            mode="year"
            align="center"
            :label="periodLabel"
          />
          <div v-else class="text-sm font-semibold text-ink-muted">
            {{ allSpanLabel }}
          </div>
        </div>
      </div>

      <p v-if="errorMessage !== null" class="mt-3 text-center text-sm text-danger-text">
        {{ errorMessage }}
      </p>
      <p v-if="isOffline" class="mt-3 text-center text-xs text-ink-muted">
        离线数据，联网后自动校准
      </p>
    </header>

    <main class="mx-auto mt-6 w-full max-w-[var(--content-max)] space-y-4 px-4 lg:px-6">
      <!-- 骨架屏 -->
      <div v-if="loading && categories.length === 0" class="space-y-4">
        <div class="skeleton h-24 rounded-md" />
        <div class="skeleton h-64 rounded-md" />
      </div>

      <template v-else>
        <!-- 年度报告横幅入口 (仅在 year 档显示) -->
        <RouterLink
          v-if="scope === 'year'"
          :to="{ name: 'annual-summary', query: { year } }"
          class="flex items-center justify-between rounded-md bg-gradient-to-r from-primary/10 via-subtle to-subtle p-4 border border-primary/20 hover:border-primary/50 transition-colors"
        >
          <div class="flex items-center gap-2.5">
            <Sparkles class="h-4 w-4 text-primary" />
            <span class="text-xs font-bold text-ink">查看 {{ year }} 年度生活与财务总结报告</span>
          </div>
          <span class="text-xs font-semibold text-primary">进入报告 →</span>
        </RouterLink>

        <!-- ④ 对照（Comparison）：月档 / 年档显示，汇总档隐藏 -->
        <section
          v-if="scope !== 'all' && comparisonMetrics.length > 0"
          class="rounded-md border border-line/50 bg-subtle p-4"
          aria-label="对照指标"
        >
          <h2 class="label-cn">对照</h2>
          <div class="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4 lg:gap-4">
            <div
              v-for="item in comparisonMetrics"
              :key="item.label"
              class="rounded-sm bg-canvas/60 p-3 min-w-0"
            >
              <span class="block text-xs text-ink-muted">{{ item.label }}</span>
              <b class="mt-1 block truncate text-base font-bold tracking-tight" :class="item.tone">
                {{ item.value }}
              </b>
              <span class="mt-0.5 block truncate text-[11px] text-ink-muted">{{ item.hint }}</span>
            </div>
          </div>
        </section>

        <!-- ② 分类构成：环图 + 可展开二级的明细表（中心显示分类数，不显示合计） -->
        <section
          v-if="categories.length > 0"
          class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5"
          aria-label="分类构成"
        >
          <div class="flex items-center justify-between">
            <h2 class="label-cn">分类构成</h2>
            <span class="text-xs text-ink-muted">共 {{ categories.length }} 个分类 · {{ currentTotalCount }} 笔</span>
          </div>

          <div class="mt-4 flex flex-col items-center gap-6 lg:grid lg:grid-cols-[200px_minmax(0,1fr)] lg:items-start lg:gap-8">
            <!-- 环图 -->
            <div class="relative flex h-[140px] w-[140px] shrink-0 items-center justify-center justify-self-center">
              <svg
                width="140"
                height="140"
                viewBox="0 0 42 42"
                class="block"
                role="img"
                :aria-label="`支出构成，共 ${categories.length} 个分类`"
              >
                <circle
                  cx="21"
                  cy="21"
                  :r="DONUT_RADIUS"
                  fill="none"
                  stroke="var(--border)"
                  stroke-width="6"
                />
                <circle
                  v-for="arc in donutArcs"
                  :key="arc.id"
                  cx="21"
                  cy="21"
                  :r="DONUT_RADIUS"
                  fill="none"
                  :stroke="arc.color"
                  stroke-width="6"
                  :stroke-dasharray="`${arc.percent} ${100 - arc.percent}`"
                  :stroke-dashoffset="arc.offset"
                />
              </svg>

              <!-- 中心只显示分类数，不显示合计金额 -->
              <div class="pointer-events-none absolute inset-0 flex flex-col items-center justify-center text-center">
                <b class="block text-sm font-bold tracking-tight text-ink leading-tight">
                  {{ categories.length }} 个分类
                </b>
                <span class="mt-0.5 text-[11px] text-ink-muted">
                  {{ scope === 'month' ? '本月' : scope === 'year' ? '全年' : '历史' }}
                </span>
              </div>
            </div>

            <!-- 分类列表与二级展开 -->
            <ul class="@container w-full min-w-0">
              <li
                class="hidden pb-2 text-[11px] font-bold tracking-wider text-ink-muted @min-[560px]:grid @min-[560px]:grid-cols-[minmax(0,1fr)_76px_52px_104px] @min-[560px]:gap-x-3"
              >
                <span>分类</span>
                <span class="text-right">{{ scope === 'year' ? '较去年' : scope === 'month' ? '较上月' : '笔数' }}</span>
                <span class="text-right">占比</span>
                <span class="text-right">金额</span>
              </li>

              <template v-for="item in categories" :key="item.categoryId">
                <!-- 一级分类行 -->
                <li
                  class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1 border-b border-line/60 py-2.5 last:border-b-0 @min-[560px]:grid-cols-[minmax(0,1fr)_76px_52px_104px]"
                >
                  <span class="flex min-w-0 items-center gap-2">
                    <span
                      class="h-2.5 w-2.5 shrink-0 rounded-[3px]"
                      :style="{
                        background: categoryColorVar(dict.colorOf(item.categoryId, item.name, item.color)),
                      }"
                      aria-hidden="true"
                    />
                    <span class="min-w-0 truncate text-sm font-semibold text-ink">{{ item.name }}</span>

                    <!-- 二级分类展开按钮 -->
                    <button
                      v-if="item.children && item.children.length > 0"
                      type="button"
                      class="ml-1 flex items-center gap-0.5 rounded px-1.5 py-0.5 text-[11px] text-ink-muted transition-colors hover:bg-sunken hover:text-ink"
                      :title="expandedCategoryIds.has(item.categoryId) ? '收起二级分类' : '展开二级分类'"
                      @click="toggleExpand(item.categoryId)"
                    >
                      <span
                        class="inline-block transition-transform duration-200"
                        :class="{ 'rotate-90': expandedCategoryIds.has(item.categoryId) }"
                      >
                        ▸
                      </span>
                      <span>{{ item.children.length }}</span>
                    </button>
                  </span>

                  <span class="shrink-0 text-right text-sm font-bold text-ink tabular-nums @min-[560px]:order-4">
                    {{ formatYuan(item.cents) }}
                  </span>

                  <!-- 对照列（汇总档显示笔数） -->
                  <span
                    v-if="scope !== 'all'"
                    class="shrink-0 text-right text-xs font-semibold tabular-nums @min-[560px]:order-2"
                    :class="ratioTone(item.changeRatio)"
                  >
                    {{ ratioText(item.changeRatio) }}
                  </span>
                  <span
                    v-else
                    class="shrink-0 text-right text-xs text-ink-muted tabular-nums @min-[560px]:order-2"
                  >
                    {{ item.count }} 笔
                  </span>

                  <span class="shrink-0 text-right text-xs text-ink-muted tabular-nums @min-[560px]:order-3">
                    {{ (item.ratio * 100).toFixed(item.ratio < 0.01 ? 1 : 0) }}%
                  </span>
                </li>

                <!-- 二级分类展开项 -->
                <template v-if="expandedCategoryIds.has(item.categoryId) && item.children && item.children.length > 0">
                  <li
                    v-for="sub in item.children"
                    :key="sub.categoryId"
                    class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-0.5 rounded-sm bg-sunken/40 py-2 pl-7 pr-3 text-xs border-b border-line/30 last:border-b-0 @min-[560px]:grid-cols-[minmax(0,1fr)_76px_52px_104px]"
                  >
                    <span class="flex min-w-0 items-center gap-1.5 text-ink-muted">
                      <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-line" aria-hidden="true" />
                      <span class="truncate">{{ sub.name }}</span>
                    </span>

                    <span class="shrink-0 text-right font-semibold text-ink tabular-nums @min-[560px]:order-4">
                      {{ formatYuan(sub.cents) }}
                    </span>

                    <span class="shrink-0 text-right text-[11px] text-ink-muted tabular-nums @min-[560px]:order-2">
                      {{ sub.count }} 笔
                    </span>

                    <span class="shrink-0 text-right text-[11px] text-ink-muted tabular-nums @min-[560px]:order-3">
                      {{ (sub.ratio * 100).toFixed(0) }}%
                    </span>
                  </li>
                </template>
              </template>
            </ul>
          </div>
        </section>

        <!-- ③ 期内节奏（Period Rhythm）：月档天折线/柱 · 年档月柱 · 汇总档年柱 -->
        <section class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5" aria-label="期内节奏">
          <div class="flex items-center justify-between">
            <h2 class="label-cn">期内节奏</h2>
            <span class="text-xs text-ink-muted">
              {{ scope === 'month' ? '逐日消费分布（点击可看单日快照）' : scope === 'year' ? '每月消费分布（点击可下钻）' : '各年消费分布' }}
            </span>
          </div>

          <!-- 月档：按天柱状图与单日快照 -->
          <div v-if="scope === 'month'" class="mt-4">
            <div class="flex h-28 items-end gap-[2px] sm:gap-1">
              <button
                v-for="d in dailyList"
                :key="d.day"
                type="button"
                class="group relative flex h-full flex-1 items-end justify-center rounded-t-sm"
                :title="`${formatMonthDay(d.date)}: ${formatYuan(d.cents)}`"
                @click="selectDailyPoint(d)"
              >
                <span
                  class="w-full rounded-t-sm transition-all duration-200"
                  :class="[
                    selectedDailyPoint?.day === d.day
                      ? 'bg-accent'
                      : d.cents > 0
                        ? 'bg-primary/80 group-hover:bg-primary'
                        : 'bg-line/40 group-hover:bg-line',
                  ]"
                  :style="{
                    height: `${Math.max(d.cents > 0 ? 6 : 2, (d.cents / maxDailyCents) * 100)}%`,
                  }"
                />
              </button>
            </div>

            <div class="mt-2 flex justify-between px-0.5 text-[10px] text-ink-muted">
              <span>1日</span>
              <span>5日</span>
              <span>10日</span>
              <span>15日</span>
              <span>20日</span>
              <span>25日</span>
              <span>{{ dailyList.length }}日</span>
            </div>

            <!-- 点击某天展开的单日快照 -->
            <div
              v-if="selectedDailyPoint"
              class="mt-3 flex flex-wrap items-center justify-between gap-2 rounded-sm bg-sunken px-3.5 py-2.5 text-xs animate-in fade-in"
            >
              <div class="flex items-center gap-2">
                <b class="font-bold text-ink">{{ formatMonthDay(selectedDailyPoint.date) }}</b>
                <span class="text-ink">支出 <b class="tabular-nums">{{ formatYuan(selectedDailyPoint.cents) }}</b></span>
                <span class="text-ink-muted">（{{ selectedDailyPoint.count }} 笔）</span>
              </div>
              <div class="flex items-center gap-3 text-ink-muted">
                <span>占本月 <b class="tabular-nums">{{ ((selectedDailyPoint.cents / (monthly?.totalCents || 1)) * 100).toFixed(1) }}%</b></span>
                <span v-if="dailyAverageCents > 0">
                  是日均 <b class="tabular-nums">{{ (selectedDailyPoint.cents / dailyAverageCents).toFixed(1) }}×</b>
                </span>
                <button
                  type="button"
                  class="text-[11px] text-ink-muted hover:text-ink"
                  @click="selectedDailyPoint = null"
                >
                  ✕
                </button>
              </div>
            </div>
          </div>

          <!-- 年档：12 个月柱状图 -->
          <div v-else-if="scope === 'year'" class="mt-4">
            <div class="flex h-28 items-end gap-1.5 sm:gap-2">
              <button
                v-for="m in yearly?.months"
                :key="m.month"
                type="button"
                class="group relative flex h-full flex-1 flex-col items-center justify-end"
                :title="`${m.month}: ${formatYuan(m.totalCents)}`"
                @click="jumpToMonth(m.month)"
              >
                <span
                  class="w-full rounded-t-sm bg-primary/75 transition-all duration-200 group-hover:bg-primary"
                  :style="{
                    height: `${Math.max(m.totalCents > 0 ? 6 : 2, (m.totalCents / maxMonthCents) * 100)}%`,
                  }"
                />
                <span class="mt-1.5 text-[10px] text-ink-muted group-hover:font-bold group-hover:text-ink">
                  {{ Number(m.month.slice(5)) }}月
                </span>
              </button>
            </div>
          </div>

          <!-- 汇总档：各年份柱状图 -->
          <div v-else class="mt-4">
            <div class="mx-auto flex h-28 max-w-lg items-end gap-3 sm:gap-4">
              <button
                v-for="y in summary?.years"
                :key="y.year"
                type="button"
                class="group relative flex h-full flex-1 flex-col items-center justify-end"
                :title="`${y.year}年: ${formatYuan(y.totalCents)}`"
                @click="jumpToYear(y.year)"
              >
                <span
                  class="w-full rounded-t-sm bg-primary/75 transition-all duration-200 group-hover:bg-primary"
                  :style="{
                    height: `${Math.max(y.totalCents > 0 ? 8 : 2, (y.totalCents / maxYearCents) * 100)}%`,
                  }"
                />
                <span class="mt-1.5 text-xs text-ink-muted group-hover:font-bold group-hover:text-ink">
                  {{ y.year }}年
                </span>
              </button>
            </div>
          </div>
        </section>

        <!-- 卡片并排区 1：涨跌榜（⑤）与 还款节奏（⑥）—— 汇总档隐藏，月档并排 -->
        <div
          v-if="scope === 'month'"
          class="card-grid grid-cols-1 lg:grid-cols-2"
        >
          <!-- ⑤ 涨跌榜（月档较上月） -->
          <section class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5" aria-label="涨跌榜">
            <div class="flex items-center justify-between">
              <h2 class="label-cn">涨跌榜</h2>
              <span class="text-xs text-ink-muted">较上月变化显著项</span>
            </div>

            <p v-if="movers.length === 0" class="py-6 text-center text-xs text-ink-muted">
              本月分类支出整体平稳，未见大幅涨跌
            </p>

            <ul v-else class="mt-3 divide-y divide-line/40">
              <li
                v-for="item in movers"
                :key="item.categoryId"
                class="flex items-center justify-between gap-3 py-2 text-xs"
              >
                <div class="min-w-0 flex-1">
                  <div class="flex items-center gap-2">
                    <span
                      class="h-2 w-2 shrink-0 rounded-full"
                      :style="{
                        background: categoryColorVar(dict.colorOf(item.categoryId, item.name, item.color)),
                      }"
                      aria-hidden="true"
                    />
                    <b class="truncate text-ink">{{ item.name }}</b>
                  </div>
                  <span class="mt-0.5 block truncate text-[11px] text-ink-muted">
                    {{ item.reason }}
                  </span>
                </div>

                <div class="shrink-0 text-right">
                  <span
                    class="font-bold tabular-nums"
                    :class="item.deltaCents > 0 ? 'text-danger-text' : 'text-secondary-text'"
                  >
                    {{ item.deltaCents > 0 ? '+' : '' }}{{ formatYuan(item.deltaCents) }}
                  </span>
                  <span class="block text-[11px] text-ink-muted tabular-nums">
                    本期 {{ formatCompact(item.cents) }}
                  </span>
                </div>
              </li>
            </ul>
          </section>

          <!-- ⑥ 还款节奏（本月刷卡 + 下月要还） -->
          <section class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5" aria-label="还款节奏">
            <div class="flex items-center justify-between">
              <h2 class="label-cn">还款节奏</h2>
              <span class="text-xs text-ink-muted">各方式支出与下月应还</span>
            </div>

            <!-- 下月信用卡待还高亮栏 -->
            <div
              v-if="nextMonthRepayments.length > 0"
              class="mt-3 rounded-sm bg-sunken p-3"
            >
              <div class="flex items-center justify-between text-xs">
                <span class="font-bold text-ink">下月应还信用卡</span>
                <b class="font-bold text-ink tabular-nums">{{ formatYuan(nextMonthRepaymentsTotalCents) }}</b>
              </div>
              <ul class="mt-2 space-y-1.5">
                <li
                  v-for="card in nextMonthRepayments"
                  :key="card.paymentMethodId"
                  class="flex items-center justify-between text-[11px]"
                >
                  <span class="inline-flex items-center gap-1.5 text-ink-muted">
                    <PaymentIcon :name="card.name" :size="13" />
                    <span>{{ card.name }} · {{ formatMonthDay(card.repaymentDate || '') }} 到期</span>
                  </span>
                  <span class="font-medium text-ink tabular-nums">{{ formatYuan(card.cents) }}</span>
                </li>
              </ul>
            </div>

            <!-- 本月各方式支出明细 -->
            <ul class="mt-3 divide-y divide-line/40">
              <li
                v-for="row in paymentRows"
                :key="row.key"
                class="flex items-center justify-between gap-3 py-2 text-xs"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <PaymentIcon :name="row.name" :size="16" />
                  <span class="truncate font-medium text-ink">{{ row.name }}</span>
                </span>

                <div class="flex shrink-0 items-center gap-3">
                  <span class="h-1.5 w-16 overflow-hidden rounded-full bg-sunken">
                    <span
                      class="block h-full rounded-full bg-primary"
                      :style="{ width: `${row.share * 100}%` }"
                    />
                  </span>
                  <span class="w-16 text-right font-bold text-ink tabular-nums">
                    {{ formatYuan(row.cents) }}
                  </span>
                </div>
              </li>
            </ul>
          </section>
        </div>

        <!-- 年档的涨跌榜（通栏或独立） -->
        <section
          v-else-if="scope === 'year'"
          class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5"
          aria-label="涨跌榜"
        >
          <div class="flex items-center justify-between">
            <h2 class="label-cn">涨跌榜</h2>
            <span class="text-xs text-ink-muted">较去年变化显著项</span>
          </div>

          <p v-if="movers.length === 0" class="py-6 text-center text-xs text-ink-muted">
            本年分类支出整体平稳，未见大幅涨跌
          </p>

          <ul v-else class="mt-3 grid grid-cols-1 gap-2 md:grid-cols-2">
            <li
              v-for="item in movers"
              :key="item.categoryId"
              class="flex items-center justify-between gap-3 rounded-sm bg-canvas/60 p-2.5 text-xs"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <span
                    class="h-2 w-2 shrink-0 rounded-full"
                    :style="{
                      background: categoryColorVar(dict.colorOf(item.categoryId, item.name, item.color)),
                    }"
                    aria-hidden="true"
                  />
                  <b class="truncate text-ink">{{ item.name }}</b>
                </div>
                <span class="mt-0.5 block truncate text-[11px] text-ink-muted">
                  {{ item.reason }}
                </span>
              </div>

              <div class="shrink-0 text-right">
                <span
                  class="font-bold tabular-nums"
                  :class="item.deltaCents > 0 ? 'text-danger-text' : 'text-secondary-text'"
                >
                  {{ item.deltaCents > 0 ? '+' : '' }}{{ formatYuan(item.deltaCents) }}
                </span>
                <span class="block text-[11px] text-ink-muted tabular-nums">
                  本期 {{ formatCompact(item.cents) }}
                </span>
              </div>
            </li>
          </ul>
        </section>

        <!-- 卡片并排区 2：本期洞察（⑦）与 按记录人（⑧） -->
        <div class="card-grid grid-cols-1 lg:grid-cols-2">
          <!-- ⑦ 本期洞察 -->
          <section class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5" aria-label="本期洞察">
            <h2 class="label-cn">本期洞察</h2>
            <ul class="mt-3 space-y-2.5">
              <li
                v-for="(text, idx) in insights"
                :key="idx"
                class="flex items-start gap-2.5 text-xs leading-relaxed text-ink"
              >
                <span class="mt-0.5 grid h-4 w-4 shrink-0 place-items-center rounded-full bg-sunken text-[10px] font-bold text-ink-muted">
                  {{ idx + 1 }}
                </span>
                <span>{{ text }}</span>
              </li>
            </ul>
          </section>

          <!-- ⑧ 按记录人 -->
          <section class="rounded-md border border-line/50 bg-subtle p-4 lg:p-5" aria-label="按记录人">
            <h2 class="label-cn">按记录人</h2>
            <ul class="mt-3 divide-y divide-line/40">
              <li
                v-for="row in memberRows"
                :key="row.key"
                class="flex items-center justify-between gap-3 py-2 text-xs"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <span class="grid h-6 w-6 shrink-0 place-items-center rounded-sm bg-sunken text-[11px] font-bold text-ink-muted">
                    {{ row.name.slice(0, 1) }}
                  </span>
                  <span class="truncate font-semibold text-ink">{{ row.name }}</span>
                </span>

                <div class="flex shrink-0 items-center gap-3">
                  <span class="h-1.5 w-16 overflow-hidden rounded-full bg-sunken">
                    <span
                      class="block h-full rounded-full bg-primary"
                      :style="{ width: `${row.share * 100}%` }"
                    />
                  </span>
                  <span class="text-xs text-ink-muted tabular-nums">{{ row.count }} 笔</span>
                  <span class="w-16 text-right font-bold text-ink tabular-nums">
                    {{ formatYuan(row.cents) }}
                  </span>
                </div>
              </li>
            </ul>
          </section>
        </div>
      </template>

      <!-- 空记录提示 -->
      <p
        v-if="!loading && categories.length === 0"
        class="py-16 text-center text-sm text-ink-muted"
      >
        {{ periodLabel }}还没有记录
      </p>
    </main>
  </div>
</template>
