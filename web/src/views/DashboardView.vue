<script setup lang="ts">
/**
 * 概况（原型 `views/Dashboard.jsx`）。
 *
 * 五卡布局：主卡（期间 + 大金额 + 环比 + 三指标 + 构成条）/ 待办与要还 /
 * 月度热力 / 累计与跨度 / 还款进度。
 *
 * 数据全部来自报表接口，**不从前端明细重算**：合计、构成、环比、热力
 * 都有服务端口径，前端再算一遍迟早与报表页对不上。
 */
import { Check,
  CalendarDays,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Layers,
  Plus,
  ReceiptText,
  TrendingDown,
  TrendingUp,
} from '@lucide/vue';
import { computed, onMounted, ref, watch } from 'vue';

import { reports, type CategoryBucket, type MonthlyReport, type SummaryReport, type YearlyReport } from '@/api';
import { useToast } from '@/composables/useToast';
import ReminderRow from '@/components/ReminderRow.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useUiStore } from '@/stores/ui';
import { PBtn, PCard, PIconBtn, POrb, PSeg, PStat, PTag } from '@/ui';
import { currentMonth, daysInMonth, elapsedDays, formatMonthLabel, formatMonthDay, shiftMonth, todayLocal } from '@/utils/dates';
import { formatCompact, formatYuan } from '@/utils/money';

const ui = useUiStore();
const dict = useDictionariesStore();
const plans = usePlansStore();
const toast = useToast();

type Tier = 'month' | 'year' | 'all';

const TIERS = [
  { value: 'month', label: '本月' },
  { value: 'year', label: '本年' },
  { value: 'all', label: '全部' },
] as const;

const tier = ref<Tier>('month');
const anchor = ref(currentMonth());
const alertOpen = ref(false);

const monthReport = ref<MonthlyReport | null>(null);
const yearReport = ref<YearlyReport | null>(null);
const summaryReport = ref<SummaryReport | null>(null);
const loading = ref(true);

const today = todayLocal();
const currentYear = computed(() => anchor.value.slice(0, 4));

/** 当期合计 / 上期合计 / 环比 */
const totalCents = computed(() => {
  if (tier.value === 'month') return monthReport.value?.totalCents ?? 0;
  if (tier.value === 'year') return yearReport.value?.totalCents ?? 0;
  return summaryReport.value?.totalCents ?? 0;
});

const prevCents = computed(() => {
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

const count = computed(() => {
  if (tier.value === 'month') return monthReport.value?.count ?? 0;
  if (tier.value === 'year') return yearReport.value?.count ?? 0;
  return summaryReport.value?.count ?? 0;
});

/** 三指标：月档看日均/预计月末，年档看月均/最高月，全部档看月均/跨度 */
const metrics = computed(() => {
  const monthAvg = summaryReport.value?.monthlyAverageCents ?? 0;
  if (tier.value === 'month') {
    const total = monthReport.value?.totalCents ?? 0;
    const elapsed = Math.max(1, elapsedDays(anchor.value, today));
    const days = daysInMonth(anchor.value);
    const perDay = Math.round(total / elapsed);
    const projected = Math.round((total / elapsed) * days);
    return [
      { label: '日均支出', value: formatYuan(perDay) },
      { label: '笔数', value: `${count.value} 笔` },
      { label: '预计月末', value: formatYuan(projected) },
    ];
  }
  const peak = yearReport.value?.peakMonth ?? null;
  const span = Math.max(1, Math.round((summaryReport.value?.recordedDays ?? 0) / 30));
  return [
    { label: '月均支出', value: formatYuan(monthAvg) },
    { label: '笔数', value: `${count.value} 笔` },
    tier.value === 'year'
      ? { label: '最高月', value: peak ? formatMonthLabel(peak.month) : '—' }
      : { label: '记录跨度', value: `${span} 个月` },
  ];
});

/** 构成：前 4 类 + 其他（颜色走账本色 8 槽） */
const composeRows = computed(() => {
  const cats: CategoryBucket[] =
    tier.value === 'month'
      ? (monthReport.value?.categories ?? [])
      : tier.value === 'year'
        ? (yearReport.value?.categories ?? [])
        : (summaryReport.value?.categories ?? []);
  const rows = cats.filter((c) => c.cents > 0).slice().sort((a, b) => b.cents - a.cents);
  const top = rows.slice(0, 4).map((c) => ({
    id: c.categoryId,
    name: c.name,
    cents: c.cents,
    color: `var(--chart-${((dict.colorOf(c.categoryId, c.name, c.color) - 1) % 8) + 1})`,
  }));
  const rest = rows.slice(4).reduce((a, c) => a + c.cents, 0);
  if (rest > 0) top.push({ id: '__rest', name: '其他', cents: rest, color: 'var(--ink-3)' });
  return top;
});

function percentOf(cents: number): number {
  const total = composeRows.value.reduce((a, r) => a + r.cents, 0);
  return total > 0 ? Math.round((cents / total) * 100) : 0;
}

/** 近 12 个月（月档才有 rolling12） */
const rolling12 = computed(() => monthReport.value?.rolling12Months ?? []);
const rolling12Max = computed(() => Math.max(1, ...rolling12.value.map((m) => m.totalCents ?? 0)));
const rolling12Total = computed(() => rolling12.value.reduce((a, m) => a + (m.totalCents ?? 0), 0));

function heatDot(cents: number | null): Record<string, string> {
  if (cents === null || cents === 0) return { background: 'var(--surface-3)' };
  const pct = Math.min(1, cents / rolling12Max.value);
  return { background: `color-mix(in srgb, var(--accent) ${Math.round(18 + pct * 82)}%, var(--surface-3))` };
}

/** 本月要还 */
const creditDue = computed(() =>
  (monthReport.value?.paymentMethods ?? []).filter((p) => p.type === 'credit'),
);
const creditDueTotal = computed(() => creditDue.value.reduce((a, p) => a + p.cents, 0));

/** 待办 */
const dueTodos = computed(() => plans.dueTodos);
const dueTotal = computed(() => dueTodos.value.reduce((a, t) => a + t.amountCents, 0));
const overdueCount = computed(
  () => dueTodos.value.filter((t) => t.repaymentDate < today).length,
);

/** 还款进度：本月计划固定还款 vs 已入账 */
const planMonthly = computed(() => plans.activePlans.reduce((a, p) => a + p.amountCents, 0));
const planPaid = computed(() => {
  const stillDue = dueTodos.value
    .filter((t) => t.repaymentDate.slice(0, 7) === currentMonth())
    .reduce((a, t) => a + t.amountCents, 0);
  return Math.max(0, planMonthly.value - stillDue);
});
const progressPct = computed(() => (planMonthly.value > 0 ? (planPaid.value / planMonthly.value) * 100 : 0));

/** 累计卡 */
const cumRows = computed(() => {
  const s = summaryReport.value;
  return [
    { label: '历史累计', value: formatYuan(s?.totalCents ?? 0) },
    { label: '记录笔数', value: `${s?.count ?? 0} 笔` },
    { label: '记录跨度', value: `${Math.max(1, Math.round((s?.recordedDays ?? 0) / 30))} 个月 · ${s?.years.length ?? 0} 年` },
    { label: '月均支出', value: formatYuan(s?.monthlyAverageCents ?? 0) },
    { label: '单笔均值', value: formatYuan(s?.perExpenseAverageCents ?? 0) },
  ];
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
    const [m, y, s] = await Promise.all([
      reports.monthly(anchor.value.slice(0, 7)).catch(() => null),
      reports.yearly(currentYear.value).catch(() => null),
      reports.summary().catch(() => null),
    ]);
    monthReport.value = m?.report ?? null;
    yearReport.value = y?.report ?? null;
    summaryReport.value = s?.report ?? null;
  } finally {
    loading.value = false;
  }
}

/**
 * 待办三个动作：自动入账类只需「确认」（ack），手动类要「入账」（confirm），
 * 两者都可「忽略」（skip）。分支放在这里而不是模板里，避免模板出现三目套三目。
 */
function todoAction(todo: { id: string; willAutoPost: boolean }, kind: 'ack' | 'confirm' | 'skip'): void {
  void (async () => {
    try {
      if (kind === 'skip') await plans.skipTodo(todo.id);
      else if (todo.willAutoPost) await plans.ackTodo(todo.id);
      else await plans.confirmTodo(todo.id);
      toast.show(kind === 'skip' ? '已忽略这笔待办' : todo.willAutoPost ? '已确认并自动入账' : '已手动入账');
      await Promise.all([load(), plans.loadDueTodos()]);
    } catch {
      toast.show('操作失败，请重试');
    }
  })();
}

watch(anchor, () => void load());
onMounted(() => {
  void plans.loadDueTodos().catch(() => undefined);
  void plans.loadPlans().catch(() => undefined);
  void load();
});
</script>

<template>
  <div class="overview-grid">
    <!-- ═══════════════════════════════════════════════════════════════
         ① 主卡（独占一整行）
         上半：期间 + 大金额 + 环比 + 三指标 + 构成条
         下半：三个小组件 —— 本月要还 / 待办提醒 / 还款进度
         （收纳进主卡：这三件事都是「这个月还要付多少」，与主金额同属一条事务线，
           拆成独立卡片会把一屏切成四块，视线要来回跳）
         ═══════════════════════════════════════════════════════════════ -->
    <PCard class="og-hero card--pop">
      <div class="hero-eyebrow">
        <PSeg :options="TIERS" :value="tier" label="期间" @change="switchTier" />
        <span style="margin-left: auto" />
        <div v-if="tier !== 'all'" class="period-nav">
          <PIconBtn :icon="ChevronLeft" label="上一期间" @click="shift(-1)" />
          <span class="mono tiny" style="min-width: 92px; text-align: center">{{ periodLabel }}</span>
          <PIconBtn :icon="ChevronRight" label="下一期间" @click="shift(1)" />
        </div>
        <PTag v-else tone="dash">全部记录</PTag>
      </div>

      <div class="hero-amt"><span class="cur">¥</span>{{ formatYuan(totalCents).replace('¥', '') }}</div>

      <div class="hero-delta">
        <span v-if="deltaRatio !== null" class="delta-pill" :class="deltaRatio > 0 ? 'neg' : 'pos'">
          <component :is="deltaRatio > 0 ? TrendingUp : TrendingDown" :size="11" />
          {{ (deltaRatio * 100).toFixed(1) }}%
        </span>
        <span>较{{ tier === 'month' ? '上月' : tier === 'year' ? '去年' : '上一段' }} {{ formatYuan(prevCents) }}</span>
      </div>

      <div class="hero-metrics">
        <PStat v-for="m in metrics" :key="m.label" :label="m.label" :value="m.value" />
      </div>

      <div class="stack-bar" role="img" aria-label="支出构成堆叠条" style="margin-top: 14px">
        <span v-for="r in composeRows" :key="r.id" :style="{ flex: r.cents, background: r.color }" />
      </div>
      <div class="compose-legend" style="margin-top: 8px">
        <span v-for="r in composeRows" :key="r.id" class="cl-item">
          <i class="cl-dot" :style="{ background: r.color }" />
          {{ r.name }}
          <b class="mono" style="font-weight: 600">{{ percentOf(r.cents) }}%</b>
        </span>
      </div>

      <!-- ── 三个小组件：同一行的三列，窄屏堆叠 ── -->
      <div class="hero-widgets">
        <!-- 小组件 1：本月要还 -->
        <section class="hero-widget">
          <div class="hw-head">
            <span class="hw-title">本月要还</span>
            <span class="hw-cap">{{ creditDue.length }} 张卡</span>
          </div>
          <div class="hw-value">{{ formatYuan(creditDueTotal) }}</div>
          <div v-if="creditDue.length === 0" class="hw-empty">本月没有信用卡账单</div>
          <template v-else>
            <div v-for="p in creditDue.slice(0, 3)" :key="p.paymentMethodId" class="hw-row">
              <span class="hw-row-name">{{ p.name }}</span>
              <span class="hw-row-val mono">{{ formatYuan(p.cents) }}</span>
            </div>
            <div v-if="creditDue.length > 3" class="hw-more">还有 {{ creditDue.length - 3 }} 张…</div>
          </template>
        </section>

        <!-- 小组件 2：待办提醒（无待办时整块收起成一行绿字） -->
        <section class="hero-widget">
          <div class="hw-head">
            <span class="hw-title">待办提醒</span>
            <span v-if="dueTodos.length > 0" class="hw-cap">{{ dueTodos.length }} 笔</span>
            <button
              v-if="dueTodos.length > 0"
              type="button"
              class="hw-toggle"
              :aria-expanded="alertOpen"
              :aria-label="alertOpen ? '收起待办' : '展开待办'"
              @click="alertOpen = !alertOpen"
            >
              <component :is="alertOpen ? ChevronUp : ChevronDown" :size="13" />
            </button>
          </div>
          <div class="hw-value" :class="{ 'hw-value--late': overdueCount > 0 }">
            {{ formatYuan(dueTotal) }}
          </div>
          <div v-if="dueTodos.length === 0" class="hw-empty hw-empty--ok">
            <Check :size="12" />计划待办已清空
          </div>
          <template v-else>
            <div class="hw-sub">
              {{ overdueCount > 0 ? `${overdueCount} 笔已逾期` : '全部未到期' }} ·
              {{ formatMonthDay(dueTodos[0]!.repaymentDate) }} 最近
            </div>
            <div v-if="alertOpen" class="hw-todos">
              <ReminderRow
                v-for="t in dueTodos"
                :key="t.id"
                :title="`${t.planName} · ${t.periodSeq} 期`"
                :sub="`${formatMonthDay(t.repaymentDate)} · ${t.willAutoPost ? '到期自动入账' : '需手动入账'}`"
                :amount="formatYuan(t.amountCents)"
                @skip="todoAction(t, 'skip')"
              >
                <PBtn size="sm" variant="ghost" @click="todoAction(t, t.willAutoPost ? 'ack' : 'confirm')">
                  {{ t.willAutoPost ? '确认' : '入账' }}
                </PBtn>
              </ReminderRow>
            </div>
          </template>
        </section>

        <!-- 小组件 3：还款进度 -->
        <section class="hero-widget">
          <div class="hw-head">
            <span class="hw-title">还款进度</span>
            <span class="hw-cap">{{ plans.activePlans.length }} 个计划</span>
          </div>
          <div class="hw-value">
            {{ formatYuan(planPaid) }}
            <span class="hw-value-sub">/ {{ formatYuan(planMonthly) }}</span>
          </div>
          <div class="bar" style="margin-top: 6px">
            <span
              class="bar-fill"
              :style="{
                width: `${Math.min(100, progressPct)}%`,
                background: progressPct > 120 ? 'var(--danger)' : progressPct > 100 ? 'var(--warn)' : 'var(--accent)',
              }"
            />
          </div>
          <div class="hw-sub">
            {{ progressPct.toFixed(0) }}% · 本月计划固定还款
            <button v-if="plans.activePlans.length > 0" type="button" class="hw-link" @click="$router.push({ name: 'settings' })">
              管理
            </button>
          </div>
        </section>
      </div>

      <div class="toolbar" style="margin-top: 14px">
        <PBtn variant="primary" :icon="Plus" @click="ui.openCreate()">记一笔</PBtn>
        <PBtn variant="ghost" :icon="ReceiptText" @click="$router.push({ name: 'ledger' })">查看流水</PBtn>
      </div>
    </PCard>

    <!-- ═══════ ② 月度热力 ═══════ -->
    <PCard class="og-heat og-card">
      <div class="card-h">
        <POrb :icon="CalendarDays" tone="var(--amber)" ink="#1E293B" />
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
            :class="{ 'is-now': cell.month === currentMonth() }"
            :title="`${cell.month} ${formatYuan(cell.totalCents ?? 0)}`"
            @click="$router.push({ name: 'report', query: { month: cell.month } })"
          >
            <span class="heat-m">{{ Number(cell.month.slice(5, 7)) }}月</span>
            <span class="heat-v">{{ cell.totalCents ? formatCompact(cell.totalCents) : '—' }}</span>
            <span class="heat-dot" :style="heatDot(cell.totalCents)" />
          </button>
        </div>
      </div>
      <div class="og-card-foot">
        <span class="tiny muted">近 12 个月合计 <b class="mono" style="color: var(--ink)">{{ formatYuan(rolling12Total) }}</b></span>
        <PBtn size="sm" variant="ghost" @click="$router.push({ name: 'report' })">打开报表</PBtn>
      </div>
    </PCard>

    <!-- ═══════ ③ 累计与跨度 ═══════ -->
    <PCard class="og-cum og-card">
      <div class="card-h">
        <POrb :icon="Layers" tone="var(--mint)" ink="#1E293B" />
        <span class="card-t">累计与跨度</span>
        <span class="card-cap">全部历史口径</span>
      </div>
      <div class="og-card-body">
        <div style="display: flex; flex-direction: column; gap: 10px">
          <div v-for="row in cumRows" :key="row.label" class="kv">
            <span class="tiny muted">{{ row.label }}</span><b>{{ row.value }}</b>
          </div>
        </div>
      </div>
    </PCard>

    <p v-if="loading" class="tiny muted" style="text-align: center">加载中…</p>
  </div>
</template>
