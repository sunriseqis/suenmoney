<script setup lang="ts">
/**
 * 报表（原型 `views/Report.jsx`）。
 *
 * 三档（本月/本年/全部）共用一套卡片：构成环图 + 明细、期内节奏、涨跌榜、
 * 还款节奏、本期洞察。所有数字来自 `/api/reports/*`，涨跌榜是「本期 vs 上期」
 * 两张报表的差值（两边都是服务端口径，不是前端累加）。
 */
import { ChartPie, ChevronLeft, ChevronRight, Sparkles, TrendingDown, TrendingUp } from '@lucide/vue';
import { computed, onMounted, ref, watch } from 'vue';

import { reports, type CategoryBucket, type MonthlyReport, type SummaryReport, type YearlyReport } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import PCatIcon from '@/components/PCatIcon.vue';
import { PBtn, PCard, PChip, PDonut, PEmpty, PIconBtn, PSeg } from '@/ui';
import { currentMonth, formatMonthLabel, shiftMonth, todayLocal } from '@/utils/dates';
import { formatCompact, formatYuan } from '@/utils/money';

const dict = useDictionariesStore();
const today = todayLocal();

type Tier = 'month' | 'year' | 'all';
const TIERS = [
  { value: 'month', label: '本月' },
  { value: 'year', label: '本年' },
  { value: 'all', label: '全部' },
] as const;

const tier = ref<Tier>('month');
const anchor = ref(currentMonth());

const monthReport = ref<MonthlyReport | null>(null);
const prevMonthReport = ref<MonthlyReport | null>(null);
const yearReport = ref<YearlyReport | null>(null);
const summaryReport = ref<SummaryReport | null>(null);
const loading = ref(true);

const currentYear = computed(() => anchor.value.slice(0, 4));

/** 当前档位的主报表（三档共用卡片） */
const activeTotal = computed(() => {
  if (tier.value === 'month') return monthReport.value?.totalCents ?? 0;
  if (tier.value === 'year') return yearReport.value?.totalCents ?? 0;
  return summaryReport.value?.totalCents ?? 0;
});

const activeCount = computed(() => {
  if (tier.value === 'month') return monthReport.value?.count ?? 0;
  if (tier.value === 'year') return yearReport.value?.count ?? 0;
  return summaryReport.value?.count ?? 0;
});

const prevTotal = computed(() => {
  if (tier.value === 'month') return monthReport.value?.previous.totalCents ?? 0;
  if (tier.value === 'year') return yearReport.value?.yearAgo.totalCents ?? 0;
  return 0;
});

const deltaRatio = computed<number | null>(() => {
  if (tier.value === 'month') return monthReport.value?.change.ratio ?? null;
  if (tier.value === 'year') return yearReport.value?.yearAgo.change.ratio ?? null;
  return null;
});

const periodLabel = computed(() => {
  if (tier.value === 'month') return formatMonthLabel(anchor.value);
  if (tier.value === 'year') return `${currentYear.value} 年`;
  return '全部记录';
});

const categories = computed<CategoryBucket[]>(() => {
  if (tier.value === 'month') return monthReport.value?.categories ?? [];
  if (tier.value === 'year') return yearReport.value?.categories ?? [];
  return summaryReport.value?.categories ?? [];
});

/** 环图数据：前 7 类 + 其他 */
const donutData = computed(() => {
  const rows = categories.value.filter((c) => c.cents > 0).slice().sort((a, b) => b.cents - a.cents);
  const top = rows.slice(0, 7).map((c) => ({
    name: c.name,
    value: c.cents,
    color: `var(--chart-${((dict.colorOf(c.categoryId, c.name, c.color) - 1) % 8) + 1})`,
  }));
  const rest = rows.slice(7).reduce((a, c) => a + c.cents, 0);
  if (rest > 0) top.push({ name: '其他', value: rest, color: 'var(--ink-3)' });
  return top;
});

/** 涨跌榜：本期 vs 上期（月档才有上期明细；年档对比去年同分类不可得，降级为本期内部排名） */
const movers = computed(() => {
  const prev = prevMonthReport.value;
  if (tier.value !== 'month' || prev === null) return [];
  const before = new Map(prev.categories.map((c) => [c.categoryId, c.cents]));
  return categories.value
    .map((c) => ({ name: c.name, categoryId: c.categoryId, now: c.cents, before: before.get(c.categoryId) ?? 0 }))
    .map((c) => ({ ...c, diff: c.now - c.before }))
    .filter((c) => Math.abs(c.diff) > 0)
    .sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff))
    .slice(0, 6);
});


/** 四维切换（原型：分类 / 支付 / 记录人 / 节奏） */
const DIMS = [
  { value: 'cat', label: '分类' },
  { value: 'pay', label: '支付' },
  { value: 'owner', label: '记录人' },
  { value: 'week', label: '节奏' },
] as const;

const dim = ref<'cat' | 'pay' | 'owner' | 'week'>('cat');

const perDayCents = computed(() => {
  if (tier.value !== 'month') return activeCount.value > 0 ? Math.round(activeTotal.value / Math.max(1, activeCount.value)) : 0;
  const elapsed = Math.max(1, Number(today.slice(8, 10)));
  return Math.round(activeTotal.value / elapsed);
});

/** 当前维度下的行（分类直接用环形数据，其余用条形） */
const dimRows = computed(() => {
  if (dim.value === 'cat') return donutData.value.map((d) => ({ name: d.name, cents: d.value, color: d.color }));
  if (dim.value === 'pay') {
    return (monthReport.value?.paymentMethods ?? [])
      .map((p, i) => ({ name: p.name, cents: p.cents, color: `var(--chart-${(i % 8) + 1})` }))
      .filter((r) => r.cents > 0)
      .sort((a, b) => b.cents - a.cents);
  }
  if (dim.value === 'owner') {
    return (monthReport.value?.members ?? [])
      .map((m, i) => ({ name: m.name, cents: m.cents, color: `var(--chart-${((i + 3) % 8) + 1})` }))
      .filter((r) => r.cents > 0)
      .sort((a, b) => b.cents - a.cents);
  }
  // 节奏：按「星期几」聚合（原型同款：周日 → 周六）
  const WD = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  const byWeekday = [0, 0, 0, 0, 0, 0, 0];
  for (const d of monthReport.value?.daily ?? []) {
    const day = new Date(`${d.date}T00:00:00`).getDay();
    byWeekday[day] = (byWeekday[day] ?? 0) + d.cents;
  }
  return WD.map((name, i) => ({ name, cents: byWeekday[i] ?? 0, color: 'var(--accent)' }));
});

const dimMax = computed(() => Math.max(1, ...dimRows.value.map((r) => r.cents)));

/** 还款节奏：取近 6 个月（月报的 rolling12Months 尾部） */
const repaySteps = computed(() => (monthReport.value?.rolling12Months ?? []).slice(-6).map((m) => ({ month: m.month, cents: m.totalCents ?? 0 })));
const repayMax = computed(() => Math.max(1, ...repaySteps.value.map((r) => r.cents)));

/** 一句话结论（原型 .report-note 的口径） */
const conclusion = computed(() => {
  if (activeTotal.value === 0) return '这个期间还没有记录，记一笔之后这里会自动生成结论。';
  const top = categories.value.slice().sort((a, b) => b.cents - a.cents)[0];
  const head = top ? `头号开销是${top.name}，占 ${Math.round((top.cents / activeTotal.value) * 100)}%；` : '';
  const tail =
    deltaRatio.value === null
      ? '这是第一段可对比的期间。'
      : `整体${deltaRatio.value >= 0 ? '多花 ' : '少花 '}${formatYuan(Math.abs(activeTotal.value - prevTotal.value))}（${Math.abs(deltaRatio.value * 100).toFixed(1)}%）。`;
  return head + tail;
});

function shift(delta: number): void {
  if (tier.value === 'all') return;
  if (tier.value === 'month') anchor.value = shiftMonth(anchor.value, delta);
  else anchor.value = `${Number(currentYear.value) + delta}-01`;
}

function switchTier(next: string): void {
  tier.value = next as Tier;
  if (next === 'year') anchor.value = `${currentYear.value}-01`;
  void load();
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    const [m, p, y, s] = await Promise.all([
      reports.monthly(anchor.value.slice(0, 7)).catch(() => null),
      reports.monthly(shiftMonth(anchor.value.slice(0, 7), -1)).catch(() => null),
      reports.yearly(currentYear.value).catch(() => null),
      reports.summary().catch(() => null),
    ]);
    monthReport.value = m?.report ?? null;
    prevMonthReport.value = p?.report ?? null;
    yearReport.value = y?.report ?? null;
    summaryReport.value = s?.report ?? null;
  } finally {
    loading.value = false;
  }
}

watch(anchor, () => void load());
onMounted(() => void load());
</script>

<template>
  <div class="stack">
    <!-- ═══════ ① 页头（原型 .report-head：紧凑事实条，不是 hero）═══════ -->
    <PCard class="report-head">
      <div class="toolbar">
        <PSeg :options="TIERS" :value="tier" label="报表档位" @change="switchTier" />
        <div class="period-nav">
          <PIconBtn :icon="ChevronLeft" label="上一期间" :disabled="tier === 'all'" @click="shift(-1)" />
          <span class="period-label">{{ periodLabel }}</span>
          <PIconBtn :icon="ChevronRight" label="下一期间" :disabled="tier === 'all'" @click="shift(1)" />
        </div>
        <span style="margin-left: auto" />
        <PBtn
          size="sm"
          variant="ghost"
          :icon="Sparkles"
          @click="$router.push({ name: 'annual-summary', query: { year: currentYear } })"
        >
          {{ currentYear }} 年度报告
        </PBtn>
      </div>

      <div class="report-facts">
        <div class="rf-main">
          <span class="tiny muted mono">期间支出</span>
          <b class="rf-num">{{ formatYuan(activeTotal) }}</b>
        </div>
        <div class="rf-items">
          <span v-if="deltaRatio !== null" class="delta-pill" :class="deltaRatio > 0 ? 'neg' : 'pos'">
            <component :is="deltaRatio > 0 ? TrendingUp : TrendingDown" :size="11" />
            {{ (deltaRatio * 100).toFixed(1) }}%
          </span>
          <span class="rf-i">对比 <b>{{ formatYuan(prevTotal) }}</b></span>
          <span class="rf-i">日均 <b>{{ formatYuan(perDayCents) }}</b></span>
          <span class="rf-i">笔数 <b>{{ activeCount }}</b></span>
        </div>
      </div>
    </PCard>

    <!-- ═══════ ② 支出构成（四维切换在卡头，原型 .report-compose）═══════ -->
    <PCard class="report-compose">
      <div class="card-h">
        <span class="card-t">支出构成</span>
        <span class="card-cap">分类 / 支付 / 记录人 / 节奏</span>
        <span class="chips" style="margin-left: auto">
          <PChip
            v-for="d in DIMS"
            :key="d.value"
            :active="dim === d.value"
            @click="dim = d.value"
          >
            {{ d.label }}
          </PChip>
        </span>
      </div>

      <PEmpty v-if="dimRows.length === 0" :icon="ChartPie">这个期间还没有构成数据</PEmpty>

      <div v-else class="compose-view" :data-dim="dim">
        <div class="compose-visual">
          <PDonut
            v-if="dim === 'cat'"
            :data="donutData"
            center-label="合计"
            :center-value="formatYuan(activeTotal)"
          />
          <div v-else-if="dim === 'week'" class="week-bars">
            <div v-for="r in dimRows" :key="r.name" class="week-bar">
              <em class="mono">{{ r.cents > 0 ? formatCompact(r.cents) : '' }}</em>
              <i :style="{ height: `${Math.max(3, (r.cents / dimMax) * 100)}%` }" />
              <span>{{ r.name.slice(-1) }}</span>
            </div>
          </div>
          <div v-else class="dim-bars">
            <div v-for="r in dimRows" :key="r.name" class="dim-bar">
              <span class="db-l">{{ r.name }}</span>
              <span class="db-track">
                <i :style="{ width: `${Math.max(3, (r.cents / dimMax) * 100)}%`, background: r.color }" />
              </span>
              <span class="db-v mono">{{ formatYuan(r.cents) }}</span>
            </div>
          </div>
        </div>

        <div class="compose-list">
          <div v-for="r in dimRows" :key="r.name" class="legend-row">
            <i :style="{ background: r.color }" />
            <span class="l-n">{{ r.name }}</span>
            <span class="l-v">{{ formatYuan(r.cents) }}</span>
            <span class="l-p">{{ activeTotal > 0 ? Math.round((r.cents / activeTotal) * 100) : 0 }}%</span>
          </div>
        </div>
      </div>
    </PCard>

    <!-- ═══════ ③ 涨跌榜 + 还款节奏（原型 .g-side 两栏）═══════ -->
    <div class="g-side">
      <PCard>
        <div class="card-h">
          <span class="card-t">涨跌榜</span>
          <span class="card-cap">分类环比 · 按差额排序</span>
        </div>
        <div v-if="movers.length > 0" class="mover-grid">
          <div v-for="m in movers" :key="m.name" class="mover">
            <PCatIcon :category-id="m.categoryId" :name="m.name" :size="30" />
            <div style="min-width: 0; flex: 1 1 auto">
              <div class="mover-t">{{ m.name }}</div>
              <div class="mover-s">{{ formatYuan(m.now) }} <span class="muted">/ 上期 {{ formatYuan(m.before) }}</span></div>
            </div>
            <div class="row-end mono tiny" :class="m.diff > 0 ? 'neg' : 'pos'">
              {{ m.diff > 0 ? '+' : '-' }}{{ formatYuan(Math.abs(m.diff)) }}
              <div class="mover-s" style="color: inherit; opacity: 0.75">
                {{ m.before ? `${Math.round((m.diff / m.before) * 100)}%` : '新增' }}
              </div>
            </div>
          </div>
        </div>
        <PEmpty v-else :icon="ChartPie">
          {{ tier === 'month' ? '该期间没有可对比的分类' : '切到「月」档看涨跌' }}
        </PEmpty>

        <!-- 一句话结论（原型 .report-note） -->
        <div v-if="conclusion !== ''" class="report-note">{{ conclusion }}</div>
      </PCard>

      <div class="stack">
        <PCard>
          <div class="card-h">
            <span class="card-t">还款节奏</span>
            <span class="card-cap">近 6 个月 · 按账期</span>
          </div>
          <div class="repay-steps">
            <div v-for="r in repaySteps" :key="r.month" class="repay-col">
              <span class="mono" style="font-size: 8.5px">{{ r.cents > 0 ? formatCompact(r.cents) : '' }}</span>
              <i :style="{ height: `${Math.max(3, (r.cents / repayMax) * 100)}%` }" />
              <span>{{ Number(r.month.slice(5, 7)) }}月</span>
            </div>
          </div>
        </PCard>

        <PCard>
          <div class="card-h">
            <span class="card-t">{{ currentYear }} 年度报告</span>
            <span class="card-cap">ANNUAL</span>
          </div>
          <button
            type="button"
            class="report-banner"
            style="width: 100%; text-align: left"
            @click="$router.push({ name: 'annual-summary', query: { year: currentYear } })"
          >
            <div>
              <div class="rb-t">{{ currentYear }} 年度报告已生成</div>
              <div class="rb-s">年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势</div>
            </div>
            <span style="margin-left: auto" class="spacer" />
            <ChevronRight :size="18" />
          </button>
        </PCard>

        <PCard>
          <div class="card-h">
            <span class="card-t">口径提醒</span>
            <span class="card-cap">这份报表怎么算的</span>
          </div>
          <p class="hint">
            合计与构成取自服务端报表接口，**月份归属按还款日**；退款以负数冲销计入当期；
            涨跌榜是「本期 vs 上期」两张报表的分类差值。
          </p>
        </PCard>
      </div>
    </div>

    <p v-if="loading" class="tiny muted" style="text-align: center">加载中…</p>
  </div>
</template>

<style scoped>
.period-nav {
  display: flex;
  align-items: center;
  gap: 6px;
}
.dim-bars {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.dim-bar {
  display: grid;
  grid-template-columns: 62px minmax(0, 1fr) 76px;
  align-items: center;
  gap: 10px;
}
.db-l {
  font-size: 11.5px;
  color: var(--ink-2);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.db-track {
  height: 10px;
  border-radius: 99px;
  background: var(--surface-3);
  overflow: hidden;
}
.db-track i {
  display: block;
  height: 100%;
  border-radius: 99px;
}
.db-v {
  text-align: right;
  font-size: 11px;
  color: var(--ink-2);
}
.progress-line {
  display: flex;
  justify-content: space-between;
  font-size: 10.5px;
  color: var(--ink-3);
  margin-top: 6px;
  font-family: var(--font-mono);
}
</style>
