<script setup lang="ts">
/**
 * 报表（原型 `views/Report.jsx`）。
 *
 * 三档（本月/本年/全部）共用一套卡片：构成环图 + 明细、期内节奏、涨跌榜、
 * 还款节奏、本期洞察。所有数字来自 `/api/reports/*`，涨跌榜是「本期 vs 上期」
 * 两张报表的差值（两边都是服务端口径，不是前端累加）。
 */
import { ChartPie, ChevronLeft, ChevronRight, CreditCard, Sparkles, TrendingDown, TrendingUp } from '@lucide/vue';
import { computed, onMounted, ref, watch } from 'vue';

import { reports, type CategoryBucket, type MonthlyReport, type SummaryReport, type YearlyReport } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { PBar, PBtn, PCard, PDonut, PEmpty, PIconBtn, PSeg, PStat, PTag } from '@/ui';
import { currentMonth, daysInMonth, formatMonthLabel, shiftMonth, todayLocal } from '@/utils/dates';
import { formatYuan } from '@/utils/money';

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
    .map((c) => ({ name: c.name, now: c.cents, before: before.get(c.categoryId) ?? 0 }))
    .map((c) => ({ ...c, diff: c.now - c.before }))
    .filter((c) => Math.abs(c.diff) > 0)
    .sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff))
    .slice(0, 6);
});

/** 期内节奏：日分布（月档） */
const daily = computed(() => monthReport.value?.daily ?? []);
const dailyMax = computed(() => Math.max(1, ...daily.value.map((d) => d.cents)));

/** 还款节奏：信用卡聚合 */
const creditRows = computed(() =>
  (monthReport.value?.paymentMethods ?? [])
    .filter((p) => p.type === 'credit')
    .slice()
    .sort((a, b) => b.cents - a.cents),
);
const creditTotal = computed(() => creditRows.value.reduce((a, p) => a + p.cents, 0));

/** 本期洞察：几句结论（都是可直接从报表算出来的事实，不做预测） */
const insights = computed(() => {
  const out: string[] = [];
  const top = categories.value.slice().sort((a, b) => b.cents - a.cents)[0];
  if (top) {
    const pct = activeTotal.value > 0 ? Math.round((top.cents / activeTotal.value) * 100) : 0;
    out.push(`花费最集中的是「${top.name}」，占 ${pct}%（${formatYuan(top.cents)}，${top.count} 笔）。`);
  }
  if (tier.value === 'month' && monthReport.value) {
    const elapsed = Math.max(1, Number(today.slice(8, 10)));
    const days = daysInMonth(anchor.value);
    const perDay = Math.round(activeTotal.value / elapsed);
    out.push(`按已过 ${elapsed} 天算，日均 ${formatYuan(perDay)}；照这个速度月末约 ${formatYuan(perDay * days)}。`);
    const largest = monthReport.value.largest;
    if (largest) out.push(`单笔最高是「${largest.categoryName}」${formatYuan(largest.cents)}。`);
  }
  if (deltaRatio.value !== null) {
    const dir = deltaRatio.value > 0 ? '增加' : '减少';
    out.push(`与上期相比${dir} ${Math.abs(deltaRatio.value * 100).toFixed(1)}%（${formatYuan(Math.abs(activeTotal.value - prevTotal.value))}）。`);
  }
  return out;
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
    <!-- ═══════ 顶部：期间 + 合计 + 环比 ═══════ -->
    <PCard>
      <div class="hero-eyebrow">
        <PSeg :options="TIERS" :value="tier" label="报表期间" @change="switchTier" />
        <span style="margin-left: auto" />
        <div v-if="tier !== 'all'" class="period-nav">
          <PIconBtn :icon="ChevronLeft" label="上一期间" @click="shift(-1)" />
          <span class="mono tiny" style="min-width: 92px; text-align: center">{{ periodLabel }}</span>
          <PIconBtn :icon="ChevronRight" label="下一期间" @click="shift(1)" />
        </div>
        <PTag v-else tone="dash">全部记录</PTag>
      </div>

      <div class="hero-amt"><span class="cur">¥</span>{{ formatYuan(activeTotal).replace('¥', '') }}</div>
      <div class="hero-delta">
        <span v-if="deltaRatio !== null" class="delta-pill" :class="deltaRatio > 0 ? 'neg' : 'pos'">
          <component :is="deltaRatio > 0 ? TrendingUp : TrendingDown" :size="11" />
          {{ (deltaRatio * 100).toFixed(1) }}%
        </span>
        <span>上期 {{ formatYuan(prevTotal) }}</span>
      </div>

      <div class="hero-metrics" style="margin-top: 14px">
        <PStat label="笔数" :value="`${activeCount} 笔`" />
        <PStat label="单笔均值" :value="formatYuan(activeCount > 0 ? Math.round(activeTotal / activeCount) : 0)" />
        <PStat
          label="分类数"
          :value="`${categories.filter((c) => c.cents > 0).length} 个`"
        />
      </div>
    </PCard>

    <!-- ═══════ 分类构成 + 涨跌榜 ═══════ -->
    <div class="g-side">
      <PCard>
        <div class="card-h">
          <span class="card-t">分类构成</span>
          <span class="card-cap">{{ periodLabel }} · 按一级分类</span>
        </div>
        <PEmpty v-if="donutData.length === 0" :icon="ChartPie">这个期间还没有记录</PEmpty>
        <div v-else class="compose-view">
          <div class="donut-wrap">
            <PDonut :data="donutData" center-label="合计" :center-value="formatYuan(activeTotal)" />
            <div class="legend" style="flex: 1 1 200px">
              <div v-for="d in donutData" :key="d.name" class="legend-row">
                <i class="cl-dot" :style="{ background: d.color }" />
                <span class="l-n">{{ d.name }}</span>
                <span class="l-v mono">{{ formatYuan(d.value) }}</span>
                <span class="l-p mono">{{ activeTotal > 0 ? Math.round((d.value / activeTotal) * 100) : 0 }}%</span>
              </div>
            </div>
          </div>
        </div>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">涨跌榜</span>
          <span class="card-cap">{{ tier === 'month' ? '较上月' : '仅月档可用' }}</span>
        </div>
        <PEmpty v-if="movers.length === 0" :icon="TrendingUp">
          {{ tier === 'month' ? '与上月相比没有变化' : '切到「本月」档看涨跌' }}
        </PEmpty>
        <div v-else class="mover-grid">
          <div v-for="m in movers" :key="m.name" class="mover">
            <span class="mover-t">{{ m.name }}</span>
            <span class="mover-s mono">上期 {{ formatYuan(m.before) }} → 本期 {{ formatYuan(m.now) }}</span>
            <span class="mono" :class="m.diff > 0 ? 'neg' : 'pos'" style="font-weight: 700">
              {{ m.diff > 0 ? '+' : '' }}{{ formatYuan(m.diff) }}
            </span>
          </div>
        </div>
      </PCard>
    </div>

    <!-- ═══════ 期内节奏 ═══════ -->
    <PCard>
      <div class="card-h">
        <span class="card-t">期内节奏</span>
        <span class="card-cap">按消费日 · 仅月档</span>
      </div>
      <PEmpty v-if="daily.length === 0" :icon="ChartPie">切到「本月」档查看日分布</PEmpty>
      <div v-else>
        <div class="bar" style="height: 10px; margin-bottom: 8px">
          <span class="bar-fill" style="width: 100%; opacity: 0.15" />
        </div>
        <div style="display: flex; gap: 2px; align-items: flex-end; height: 88px">
          <div
            v-for="d in daily"
            :key="d.date"
            :title="`${d.date} ${formatYuan(d.cents)}`"
            :style="{
              flex: '1 1 0',
              height: `${Math.max(4, (d.cents / dailyMax) * 100)}%`,
              background: d.cents > 0 ? `color-mix(in srgb, var(--accent) ${40 + Math.round((d.cents / dailyMax) * 60)}%, var(--surface-3))` : 'var(--surface-3)',
              borderRadius: '3px 3px 0 0',
            }"
          />
        </div>
        <div class="progress-line" style="margin-top: 8px">
          <span>{{ daily[0]?.date ?? '' }} 起</span>
          <span>峰值 {{ formatYuan(dailyMax) }}</span>
        </div>
      </div>
    </PCard>

    <!-- ═══════ 还款节奏 ═══════ -->
    <PCard>
      <div class="card-h">
        <span class="card-t">还款节奏</span>
        <span class="card-cap">信用卡 · 合计 {{ formatYuan(creditTotal) }}</span>
      </div>
      <PEmpty v-if="creditRows.length === 0" :icon="CreditCard">本月没有信用卡消费</PEmpty>
      <div v-else style="display: flex; flex-direction: column; gap: 10px">
        <div v-for="p in creditRows" :key="p.paymentMethodId">
          <div class="split" style="margin-bottom: 4px">
            <span style="font-size: 12.5px; font-weight: 600">{{ p.name }}</span>
            <span class="tiny muted" style="margin-left: auto">{{ p.count }} 笔 · {{ formatYuan(p.cents) }}</span>
          </div>
          <PBar :pct="creditTotal > 0 ? (p.cents / creditTotal) * 100 : 0" />
        </div>
      </div>
    </PCard>

    <!-- ═══════ 本期洞察 ═══════ -->
    <PCard>
      <div class="card-h">
        <span class="card-t">本期洞察</span>
        <span class="card-cap">只陈述报表里的事实</span>
      </div>
      <PEmpty v-if="insights.length === 0" :icon="Sparkles">数据太少，得不出结论</PEmpty>
      <div v-else class="insight">
        <p v-for="(text, i) in insights" :key="i">{{ text }}</p>
      </div>
    </PCard>

    <!-- ═══════ 年度报告入口 ═══════ -->
    <PCard v-if="tier === 'year'">
      <div class="split">
        <div>
          <div class="card-t">{{ currentYear }} 年度报告</div>
          <div class="tiny muted">12 个月走势、年度之最、单笔最贵</div>
        </div>
        <PBtn
          variant="primary"
          style="margin-left: auto"
          @click="$router.push({ name: 'annual-summary', query: { year: currentYear } })"
        >
          打开年度报告
        </PBtn>
      </div>
    </PCard>

    <p v-if="loading" class="tiny muted" style="text-align: center">加载中…</p>
  </div>
</template>

<style scoped>
.period-nav {
  display: flex;
  align-items: center;
  gap: 6px;
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
