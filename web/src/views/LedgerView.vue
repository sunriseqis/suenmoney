<script setup lang="ts">
/**
 * 流水（原型 `views/Ledger.jsx`）。
 *
 * 三档三形态（用户裁决过，不是可选项）：
 *   按月   → 逐笔明细表（按消费日分组，带日小计）
 *   按年   → 12 个月格日历
 *   全部   → 一年一格
 *
 * 数据来源分两路：
 *   · 明细列表 `/api/expenses`（游标分页，每段 100 笔）
 *   · 档位汇总 `/api/reports/{monthly,yearly,summary}`（合计、构成、日历格）
 * 两条路各司其职，不互相推算 —— 前端自己按明细累加会与报表口径漂移。
 */
import { CalendarDays, ChevronLeft, ChevronRight, Filter, Search, SlidersHorizontal, X } from '@lucide/vue';
import { computed, onMounted, ref, watch } from 'vue';

import { expenses as expensesApi, reports, users as usersApi, type Expense, type MonthlyReport, type SummaryReport, type YearlyReport } from '@/api';
import CompositionCard from '@/components/CompositionCard.vue';
import PCatIcon from '@/components/PCatIcon.vue';
import PPayIcon from '@/components/PPayIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useUiStore } from '@/stores/ui';
import { PBtn, PCard, PChip, PEmpty, PIconBtn, PInput, PSeg, PTag } from '@/ui';
import { currentMonth, formatLedgerDate, formatMonthDay, formatMonthLabel, shiftMonth, todayLocal } from '@/utils/dates';
import { formatYuan } from '@/utils/money';

const ui = useUiStore();
const dict = useDictionariesStore();
const plans = usePlansStore();

type Tier = 'month' | 'year' | 'all';

const TIER_OPTIONS = [
  { value: 'month', label: '按月' },
  { value: 'year', label: '按年' },
  { value: 'all', label: '全部' },
] as const;

const tier = ref<Tier>('month');
const anchor = ref(currentMonth()); // 月档用 'YYYY-MM'，年档/全部用年份
const query = ref('');
const filterCat = ref('');
const filterPay = ref('');
const filterOwner = ref('');
const sortBy = ref<'date' | 'amount'>('date');
const showFilters = ref(false);
/** 窄屏：工具栏高级控件默认收起（原型 .ledger-toolbar.is-open 控制） */
const advOpen = ref(false);

const items = ref<Expense[]>([]);
const cursor = ref<string | null>(null);
const hasMore = ref(false);
const loading = ref(false);
const loadingMore = ref(false);

const monthReport = ref<MonthlyReport | null>(null);
const yearReport = ref<YearlyReport | null>(null);
const summaryReport = ref<SummaryReport | null>(null);
const members = ref<Array<{ id: string; name: string }>>([]);

const today = todayLocal();
const PAGE = 100;

/** 四维构成：分类 / 支付 / 记录人 / 节奏（周） */
const compositionDimensions = computed(() => {
  const rep = monthReport.value;
  const color = (i: number) => `var(--chart-${(i % 8) + 1})`;

  const byCategory = (rep?.categories ?? []).map((c) => ({
    name: c.name,
    cents: c.cents,
    color: `var(--chart-${((dict.colorOf(c.categoryId, c.name, c.color) - 1) % 8) + 1})`,
  }));

  const byPayment = (rep?.paymentMethods ?? []).map((p, i) => ({
    name: p.name,
    cents: p.cents,
    color: color(i),
  }));

  const byOwner = (rep?.members ?? []).map((m, i) => ({
    name: m.name,
    cents: m.cents,
    color: color(i + 3),
  }));

  // 节奏：按「第几周」把日分布聚合（第 1 周 = 1–7 日，依此类推）
  const weeks = new Map<number, number>();
  for (const d of rep?.daily ?? []) {
    const day = Number(d.date.slice(8, 10));
    const week = Math.min(5, Math.ceil(day / 7));
    weeks.set(week, (weeks.get(week) ?? 0) + d.cents);
  }
  const byRhythm = [...weeks.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([week, cents], i) => ({ name: `第 ${week} 周`, cents, color: color(i + 1) }));

  return [
    { key: 'cat', label: '分类', buckets: byCategory },
    { key: 'pay', label: '支付', buckets: byPayment },
    { key: 'owner', label: '记录人', buckets: byOwner },
    { key: 'rhythm', label: '节奏', buckets: byRhythm },
  ];
});

/** 触底「查看上月」：本月已加载完时给一个明确的下一步 */
function goPrevMonth(): void {
  anchor.value = shiftMonth(anchor.value, -1);
}



const filterCount = computed(
  () => (filterCat.value ? 1 : 0) + (filterPay.value ? 1 : 0) + (filterOwner.value ? 1 : 0),
);

const yearOfAnchor = computed(() => anchor.value.slice(0, 4));

/** 期间标签（原型 period-label） */
const periodLabel = computed(() => {
  if (tier.value === 'month') return formatMonthLabel(anchor.value);
  if (tier.value === 'year') return `${yearOfAnchor.value} 年`;
  return '全部记录';
});

/** 当期合计（用报表口径；无报表时退回明细累加） */
const periodTotalCents = computed(() => {
  if (tier.value === 'month') return monthReport.value?.totalCents ?? sum(items.value);
  if (tier.value === 'year') return yearReport.value?.totalCents ?? sum(items.value);
  return summaryReport.value?.totalCents ?? sum(items.value);
});

/** 上期合计（环比用） */
const prevTotalCents = computed(() => {
  if (tier.value === 'month') return monthReport.value?.previous.totalCents ?? 0;
  if (tier.value === 'year') return yearReport.value?.yearAgo.totalCents ?? 0;
  return 0;
});

const deltaRatio = computed<number | null>(() => {
  if (tier.value === 'month') return monthReport.value?.change.ratio ?? null;
  if (tier.value === 'year') return yearReport.value?.yearAgo.change.ratio ?? null;
  return null;
});

/** 移动端顶部卡：本月要还 */
const creditDueCents = computed(() =>
  (monthReport.value?.paymentMethods ?? [])
    .filter((p) => p.type === 'credit')
    .reduce((a, p) => a + p.cents, 0),
);

const perDayCents = computed(() => {
  const days = Math.max(1, Number(today.slice(8, 10)));
  return Math.round((monthReport.value?.totalCents ?? 0) / days);
});

/** 下一个待办（移动端顶部卡只显示最近一笔） */
const nextTodo = computed(() => plans.dueTodos[0] ?? null);

/** 年档：12 个月格 */
const monthCells = computed(() => {
  const y = yearOfAnchor.value;
  const months = monthReport.value?.rolling12Months ?? [];
  return Array.from({ length: 12 }, (_, i) => {
    const key = `${y}-${String(i + 1).padStart(2, '0')}`;
    const hit = months.find((m) => m.month === key);
    return { key, label: `${i + 1}月`, cents: hit?.totalCents ?? 0, count: hit?.count ?? 0 };
  });
});

const monthCellMax = computed(() => Math.max(1, ...monthCells.value.map((c) => c.cents)));

/** 全部档：一年一格 */
const yearCells = computed(() => summaryReport.value?.years ?? []);

/** 支付方式图标：Expense 上没有 icon 字段，按 paymentMethodId 查字典 */
function paymentIconOf(id: string): string {
  return dict.findPaymentMethod(id)?.icon ?? '';
}

function sum(rows: Expense[]): number {
  return rows.reduce((a, r) => a + r.amountCents, 0);
}


/** 明细查询参数 */
function listQuery() {
  const base: Record<string, unknown> = { limit: PAGE };
  if (tier.value === 'month') base['month'] = anchor.value;
  else if (tier.value === 'year') {
    base['from'] = `${yearOfAnchor.value}-01-01`;
    base['to'] = `${yearOfAnchor.value}-12-31`;
  }
  if (query.value.trim()) base['q'] = query.value.trim();
  if (filterCat.value) base['categoryId'] = filterCat.value;
  if (filterPay.value) base['paymentMethodId'] = filterPay.value;
  if (filterOwner.value) base['ownerId'] = filterOwner.value;
  return base;
}

async function reload(): Promise<void> {
  loading.value = true;
  cursor.value = null;
  try {
    const page = await expensesApi.list(listQuery() as never);
    items.value = page.items;
    cursor.value = page.nextCursor;
    hasMore.value = page.hasMore;
  } catch {
    items.value = [];
    hasMore.value = false;
  } finally {
    loading.value = false;
  }
}

async function loadMore(): Promise<void> {
  if (!hasMore.value || cursor.value === null || loadingMore.value) return;
  loadingMore.value = true;
  try {
    const page = await expensesApi.list({ ...listQuery(), cursor: cursor.value } as never);
    items.value = [...items.value, ...page.items];
    cursor.value = page.nextCursor;
    hasMore.value = page.hasMore;
  } finally {
    loadingMore.value = false;
  }
}

async function reloadReports(): Promise<void> {
  try {
    monthReport.value = (await reports.monthly(anchor.value)).report;
  } catch {
    monthReport.value = null;
  }
  if (tier.value === 'year') {
    try {
      yearReport.value = (await reports.yearly(yearOfAnchor.value)).report;
    } catch {
      yearReport.value = null;
    }
  }
  try {
    summaryReport.value = (await reports.summary()).report;
  } catch {
    summaryReport.value = null;
  }
}

function shift(delta: number): void {
  if (tier.value === 'all') return;
  if (tier.value === 'month') anchor.value = shiftMonth(anchor.value, delta);
  else anchor.value = `${Number(yearOfAnchor.value) + delta}-01`;
}

function switchTier(next: string): void {
  tier.value = next as Tier;
  if (next === 'year') anchor.value = `${yearOfAnchor.value}-01`;
  void reload();
  void reloadReports();
}

function openAdvOnNarrow(): void {
  if (typeof window !== 'undefined' && window.matchMedia('(max-width: 860px)').matches) advOpen.value = true;
}

function clearFilters(): void {
  filterCat.value = '';
  filterPay.value = '';
  filterOwner.value = '';
  query.value = '';
}

function drillMonth(month: string): void {
  tier.value = 'month';
  anchor.value = month;
  void reload();
  void reloadReports();
}

const sortedItems = computed(() => {
  const arr = items.value.slice();
  if (sortBy.value === 'amount') arr.sort((a, b) => b.amountCents - a.amountCents);
  else arr.sort((a, b) => (a.spendDate === b.spendDate ? (a.id < b.id ? 1 : -1) : a.spendDate < b.spendDate ? 1 : -1));
  return arr;
});

/** 排序影响分组顺序，所以分组用排序后的列表重算 */
const groupedSorted = computed(() => {
  const map = new Map<string, Expense[]>();
  for (const row of sortedItems.value) {
    const list = map.get(row.spendDate);
    if (list) list.push(row);
    else map.set(row.spendDate, [row]);
  }
  return [...map.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([date, rows]) => ({ date, rows, cents: sum(rows) }));
});

watch([query, filterCat, filterPay, filterOwner], () => {
  void reload();
});

watch(anchor, () => {
  if (tier.value === 'month') void reload();
  void reloadReports();
});

onMounted(async () => {
  await Promise.all([dict.load().catch(() => undefined), plans.loadPlans().catch(() => undefined)]);
  try {
    members.value = (await usersApi.list()).users.map((u) => ({ id: u.id, name: u.displayName }));
  } catch {
    members.value = [];
  }
  await Promise.all([reload(), reloadReports()]);
});
</script>

<template>
  <div class="stack">
    <!-- ════════ 移动端顶部卡（原型 mobile-hero）：本月支出 + 要还 + 最近待办 ════════ -->
    <div class="mobile-hero mobile-only">
      <div class="mh-head">
        <span class="mh-eyebrow">{{ formatMonthLabel(anchor) }} · 本月支出</span>
        <div class="mh-amt"><span class="cur">¥</span>{{ formatYuan(periodTotalCents).replace('¥', '') }}</div>
        <div class="mh-delta">
          <span v-if="deltaRatio !== null" class="delta-pill" :class="deltaRatio > 0 ? 'neg' : 'pos'">
            {{ (deltaRatio * 100).toFixed(1) }}%
          </span>
          <span>较上月 {{ formatYuan(prevTotalCents) }}</span>
        </div>
      </div>
      <div class="mh-facts">
        <div class="mh-fact"><span>日均</span><b>{{ formatYuan(perDayCents) }}</b></div>
        <div class="mh-fact"><span>笔数</span><b>{{ monthReport?.count ?? items.length }} 笔</b></div>
        <div class="mh-fact"><span>本月要还</span><b>{{ formatYuan(creditDueCents) }}</b></div>
      </div>
      <button v-if="nextTodo" type="button" class="mh-plan" @click="$router.push({ name: 'settings' })">
        <span class="mh-plan-ic"><CalendarDays :size="14" /></span>
        <span class="mh-plan-txt">
          <b>{{ nextTodo.planName }} · {{ nextTodo.periodSeq }} 期</b>
          <span>{{ plans.dueTodos.length }} 笔待处理 · {{ formatMonthDay(nextTodo.repaymentDate) }}</span>
        </span>
        <span class="mh-plan-amt">{{ formatYuan(nextTodo.amountCents) }}</span>
        <ChevronRight :size="13" />
      </button>
      <div class="mh-nav">
        <button type="button" class="mh-btn" @click="$router.push({ name: 'dashboard' })">
          概况
        </button>
        <button type="button" class="mh-btn" @click="$router.push({ name: 'report' })">
          报表
        </button>
        <button type="button" class="mh-btn" @click="$router.push({ name: 'settings' })">
          设置
        </button>
      </div>
    </div>

    <!-- ════════ 工具栏（原型 ledger-toolbar）════════ -->
    <PCard>
      <div class="ledger-toolbar" :class="{ 'is-open': advOpen }">
        <div class="lt-search" @click="openAdvOnNarrow">
          <div class="search-wrap">
            <Search class="ic" :size="15" />
            <PInput v-model="query" class="input--search" placeholder="搜索备注或分类" />
          </div>
          <button v-if="advOpen" type="button" class="btn btn--ghost btn--sm lt-collapse" @click.stop="advOpen = false">
            收起
          </button>
        </div>

        <div class="lt-adv">
          <PSeg :options="TIER_OPTIONS" :value="tier" label="流水档位" @change="switchTier" />
          <div class="period-nav">
            <PIconBtn :icon="ChevronLeft" label="上一期间" :disabled="tier === 'all'" @click="shift(-1)" />
            <span class="period-label">{{ periodLabel }}</span>
            <PIconBtn :icon="ChevronRight" label="下一期间" :disabled="tier === 'all'" @click="shift(1)" />
          </div>
          <PBtn size="sm" :variant="filterCount ? 'primary' : ''" :icon="Filter" @click="showFilters = !showFilters">
            筛选{{ filterCount ? ` · ${filterCount}` : '' }}
          </PBtn>
          <div class="seg" style="margin-left: auto">
            <button type="button" class="seg-btn" :class="{ 'is-on': sortBy === 'date' }" @click="sortBy = 'date'">按日期</button>
            <button type="button" class="seg-btn" :class="{ 'is-on': sortBy === 'amount' }" @click="sortBy = 'amount'">按金额</button>
          </div>
        </div>
      </div>

      <div class="ledger-sum">
        <span class="mono">{{ periodLabel }}</span>
        <span class="ls-sep">·</span>
        <span>{{ items.length }} 笔</span>
        <span class="ls-sep">·</span>
        <span>合计 <b>{{ formatYuan(periodTotalCents) }}</b></span>
        <span v-if="filterCount || query" class="tiny muted" style="margin-left: auto">已筛选</span>
      </div>

      <div v-if="showFilters" class="filter-row">
        <div class="filter-group">
          <span class="filter-l">分类</span>
          <PChip :active="!filterCat" @click="filterCat = ''">全部</PChip>
          <PChip
            v-for="c in dict.rootCategories"
            :key="c.id"
            :active="filterCat === c.id"
            @click="filterCat = filterCat === c.id ? '' : c.id"
          >
            {{ c.name }}
          </PChip>
        </div>
        <div class="filter-group">
          <span class="filter-l">支付</span>
          <PChip
            v-for="p in dict.usablePaymentMethods"
            :key="p.id"
            :active="filterPay === p.id"
            @click="filterPay = filterPay === p.id ? '' : p.id"
          >
            {{ p.name }}
          </PChip>
        </div>
        <div class="filter-group">
          <span class="filter-l">记录人</span>
          <PChip
            v-for="u in members"
            :key="u.id"
            :active="filterOwner === u.id"
            @click="filterOwner = filterOwner === u.id ? '' : u.id"
          >
            {{ u.name }}
          </PChip>
          <PBtn v-if="filterCount || query" size="sm" variant="ghost" :icon="X" @click="clearFilters">清除</PBtn>
        </div>
      </div>
    </PCard>

    <!-- ════════ 构成（四维，贴住工具栏：先看结构再看明细）════════ -->
    <PCard v-if="tier === 'month'">
      <CompositionCard :total-cents="periodTotalCents" :dimensions="compositionDimensions" />
    </PCard>

    <!-- ════════ 月档：明细表 + 移动行卡 ════════ -->
    <PCard v-if="tier === 'month'">
      <div class="card-h">
        <span class="card-t">流水明细</span>
        <span class="card-cap">{{ items.length }} 笔 · 合计 {{ formatYuan(periodTotalCents) }}</span>
      </div>

      <PEmpty v-if="loading" :icon="Search">加载中…</PEmpty>
      <PEmpty v-else-if="groupedSorted.length === 0" :icon="Search">没有符合条件的流水</PEmpty>

      <template v-else>
        <!-- 桌面表格 -->
        <table class="tbl desktop-only">
          <thead>
            <tr>
              <th style="width: 104px">消费日期</th>
              <th style="width: 170px">分类</th>
              <th>备注</th>
              <th style="width: 110px">账期</th>
              <th style="width: 82px">记录人</th>
              <th style="width: 110px">支付方式</th>
              <th style="width: 104px" class="th-r">金额</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="g in groupedSorted" :key="g.date">
              <tr style="cursor: default" aria-hidden="true">
                <td colspan="7" style="padding: 12px 10px 6px; border-bottom: 0">
                  <div class="date-cap" style="padding: 0">
                    {{ formatLedgerDate(g.date, today).dayText }}
                    <span class="sum mono">{{ formatYuan(g.cents) }}</span>
                  </div>
                </td>
              </tr>
              <tr v-for="row in g.rows" :key="row.id" @click="ui.openEdit(row)">
                <td class="mono tiny muted">{{ row.spendDate.slice(5) }}</td>
                <td>
                  <div class="cat-cell">
                    <PCatIcon
                      :category-id="row.categoryId"
                      :name="row.categoryName"
                      :icon="row.categoryIcon"
                      :color="row.parentCategoryColor ?? row.categoryColor"
                      :size="30"
                    />
                    <div class="cat-txt">
                      <div class="cat-name">{{ row.categoryName }}</div>
                      <div class="cat-sub">{{ row.parentCategoryName ?? '' }}</div>
                    </div>
                  </div>
                </td>
                <td>
                  <div class="split" style="gap: 6px">
                    <span>{{ row.note || '—' }}</span>
                    <PTag v-if="row.amountCents < 0" tone="danger">退款</PTag>
                  </div>
                </td>
                <td class="mono tiny">
                  <span v-if="row.paymentMethodType === 'credit'">
                    {{ row.repaymentDate.slice(5) }} <span class="muted">还</span>
                  </span>
                  <span v-else class="muted">即时</span>
                </td>
                <td class="tiny muted">{{ row.ownerName }}</td>
                <td>
                  <span class="split" style="gap: 6px">
                    <PPayIcon :name="row.paymentMethodName" :icon="paymentIconOf(row.paymentMethodId)" :size="14" />
                    <span class="tiny">{{ row.paymentMethodName }}</span>
                  </span>
                </td>
                <td class="td-r mono" :class="row.amountCents < 0 ? 'pos' : ''">{{ formatYuan(row.amountCents) }}</td>
              </tr>
            </template>
          </tbody>
        </table>

        <!-- 移动行卡 -->
        <div class="m-list mobile-only">
          <div v-for="g in groupedSorted" :key="g.date">
            <div class="date-cap">
              {{ formatLedgerDate(g.date, today).dayText }}
              <span class="sum mono">{{ formatYuan(g.cents) }}</span>
            </div>
            <button
              v-for="row in g.rows"
              :key="row.id"
              type="button"
              class="m-row"
              @click="ui.openEdit(row)"
            >
              <PCatIcon
                :category-id="row.categoryId"
                :name="row.categoryName"
                :icon="row.categoryIcon"
                :color="row.parentCategoryColor ?? row.categoryColor"
                :size="34"
              />
              <span class="m-row-main">
                <span class="m-row-t">
                  <span>{{ row.categoryName }}</span>
                  <PTag v-if="row.amountCents < 0" tone="danger">退款</PTag>
                </span>
                <span class="m-row-s">
                  <span>{{ row.note || '—' }}</span>
                  <span>·</span>
                  <span>{{ row.paymentMethodName }}</span>
                  <span>·</span>
                  <span>{{ row.ownerName }}</span>
                </span>
              </span>
              <span class="row-end">
                <span class="row-amt" :class="row.amountCents < 0 ? 'pos' : ''">{{ formatYuan(row.amountCents) }}</span>
                <span class="tiny muted mono" style="display: block">
                  {{ row.paymentMethodType === 'credit' ? `${row.repaymentDate.slice(5)} 还` : '即时' }}
                </span>
              </span>
            </button>
          </div>
        </div>

        <div v-if="hasMore" style="margin-top: 14px; text-align: center">
          <PBtn :disabled="loadingMore" @click="loadMore">{{ loadingMore ? '加载中…' : '加载更多' }}</PBtn>
        </div>
        <div v-else-if="items.length > 0" style="margin-top: 14px; text-align: center">
          <PBtn variant="ghost" :icon="ChevronLeft" @click="goPrevMonth">查看上月</PBtn>
        </div>
      </template>
    </PCard>

    <!-- ════════ 年档：12 月格 ════════ -->
    <PCard v-else-if="tier === 'year'">
      <div class="card-h">
        <span class="card-t">{{ yearOfAnchor }} 年</span>
        <span class="card-cap">合计 {{ formatYuan(periodTotalCents) }}</span>
      </div>
      <div class="cal-year-grid">
        <button
          v-for="cell in monthCells"
          :key="cell.key"
          type="button"
          class="year-cell"
          :style="{ borderColor: cell.key === currentMonth() ? 'var(--line-2)' : '' }"
          @click="drillMonth(cell.key)"
        >
          <div class="split" style="gap: 5px">
            <span class="y-m">{{ cell.label }}</span>
            <PTag v-if="cell.key === currentMonth()" tone="accent">本月</PTag>
            <span style="margin-left: auto" class="tiny muted mono">{{ cell.count }} 笔</span>
          </div>
          <div class="y-v">{{ formatYuan(cell.cents) }}</div>
          <div class="bar" style="height: 5px; margin-top: 2px">
            <span class="bar-fill" :style="{ width: `${Math.round((cell.cents / monthCellMax) * 100)}%` }" />
          </div>
        </button>
      </div>
    </PCard>

    <!-- ════════ 全部档：一年一格 ════════ -->
    <PCard v-else>
      <div class="card-h">
        <span class="card-t">全部记录</span>
        <span class="card-cap">{{ yearCells.length }} 年 · 合计 {{ formatYuan(periodTotalCents) }}</span>
      </div>
      <PEmpty v-if="yearCells.length === 0" :icon="SlidersHorizontal">还没有任何记录</PEmpty>
      <div class="cal-year-grid" v-else>
        <button
          v-for="y in yearCells"
          :key="y.year"
          type="button"
          class="year-cell"
          @click="drillMonth(`${y.year}-01`)"
        >
          <div class="split" style="gap: 5px">
            <span class="y-m">{{ y.year }}</span>
            <span style="margin-left: auto" class="tiny muted mono">{{ y.count }} 笔</span>
          </div>
          <div class="y-v">{{ formatYuan(y.totalCents) }}</div>
          <div class="bar" style="height: 5px; margin-top: 2px">
            <span
              class="bar-fill"
              :style="{ width: `${Math.round((y.totalCents / Math.max(1, ...yearCells.map((c) => c.totalCents))) * 100)}%` }"
            />
          </div>
        </button>
      </div>
    </PCard>
  </div>
</template>

<style scoped>
/* 搜索框：图标绝对定位在框内左侧（原型 .search-wrap .ic），
   输入框左侧留出图标宽度 —— 否则图标和输入内容会挤在一起 */
@media (max-width: 860px) {
  .lt-adv {
    gap: 8px;
  }
  .period-label {
    min-width: 76px;
  }
}
</style>
