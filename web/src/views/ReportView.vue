<script setup lang="ts">
/**
 * 报表页：回答「花了多少」「花在什么上面」。
 *
 * 服务端只提供两种口径（月 / 年），这里的切换只是换一个请求参数，
 * 不做任何本地聚合 —— 聚合口径必须与服务端一致，否则同一个月在
 * 仪表盘和报表页会显示成两个不同的数字。
 */
import { computed, onMounted, ref, watch } from 'vue';

import {
  ApiError,
  reports as reportsApi,
  type CategoryBucket,
  type MonthlyReport,
  type PaymentMethodType,
  type YearlyReport,
} from '@/api';
import ChipButton from '@/components/ChipButton.vue';
import PeriodPicker from '@/components/PeriodPicker.vue';
import { useUiStore } from '@/stores/ui';
import { categoryColorVar, resolveCategoryColor } from '@/utils/category-colors';
import { currentMonth, elapsedDays, formatMonthLabel, formatMonthDay } from '@/utils/dates';
import { buildDonutArcs, DONUT_RADIUS } from '@/utils/donut';
import { resolvePaymentMethodIcon } from '@/utils/icons';
import { formatCompact, formatYuan } from '@/utils/money';
import { URGENCY_META, urgencyLabel, urgencyOfOptional } from '@/utils/urgency';

const ui = useUiStore();

type Scope = 'month' | 'year';

const scope = ref<Scope>('month');
const month = ref(currentMonth());
const year = ref(String(new Date().getFullYear()));

const monthly = ref<MonthlyReport | null>(null);
const yearly = ref<YearlyReport | null>(null);
const loading = ref(true);
const errorMessage = ref<string | null>(null);

async function load(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;

  try {
    if (scope.value === 'month') {
      monthly.value = (await reportsApi.monthly(month.value)).report;
    } else {
      yearly.value = (await reportsApi.yearly(year.value)).report;
    }
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '加载失败';
  } finally {
    loading.value = false;
  }
}

onMounted(load);
watch([scope, month, year], load);
watch(() => ui.dataVersion, load);

const totalCents = computed(() =>
  scope.value === 'month' ? (monthly.value?.totalCents ?? 0) : (yearly.value?.totalCents ?? 0),
);

const categories = computed<CategoryBucket[]>(() =>
  scope.value === 'month' ? (monthly.value?.categories ?? []) : (yearly.value?.categories ?? []),
);

const maxMonth = computed(() =>
  Math.max(1, ...(yearly.value?.months ?? []).map((item) => item.totalCents)),
);

/**
 * 环图的弧段。
 *
 * 几何计算（周长、offset 累加）在 `utils/donut.ts` —— 那里是纯函数、有单元测试，
 * 因为「offset 少累加一段」表现只是弧画歪了，界面不报错也看不出来。
 * 这里只负责把分类桶翻译成它要的输入：颜色还需要按分类名兜底推导。
 */
const donutArcs = computed(() =>
  buildDonutArcs(
    categories.value.map((item) => ({
      id: item.categoryId,
      ratio: item.ratio,
      color: categoryColorVar(resolveCategoryColor(item.name, item.color)),
    })),
  ),
);

/**
 * 排名行 —— 「按支付方式」与「按记录人」共用同一种行结构。
 *
 * 每行中间必须有一条「占比条」：这类行是**数据排名**，名称和金额摆在
 * 半栏宽（约 540px）的两端，中间会空出一大块，眼睛得横跨整行才能把两者对上。
 * 设置页那种「一行只有名称 + 一个尾部值」的列表则不需要 —— 那里的留白是
 * 正常的（macOS 设置面板就是这样）。
 *
 * 占比按 `totalCents` 现算，因为服务端对这两种口径不返回 ratio；
 * 总额为 0 时统一给 0，避免除零得到 NaN 后把条撑成整行。
 */
interface RankRow {
  key: string;
  name: string;
  cents: number;
  count: number;
  share: number;
}

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

const memberRows = computed<RankRow[]>(() => {
  const source = scope.value === 'month' ? monthly.value?.members : yearly.value?.members;

  return (source ?? []).map((item) => ({
    key: item.ownerId,
    name: item.name,
    cents: item.cents,
    count: item.count,
    share: toShare(item.cents),
  }));
});

const periodLabel = computed(() =>
  scope.value === 'month' ? formatMonthLabel(month.value) : `${year.value} 年`,
);

/** 年度视图里是否有数据 —— 没有就不画一根根都是 0 的柱子 */
const hasYearlyData = computed(() => (yearly.value?.totalCents ?? 0) !== 0);

/* ---- 概览四项指标 ------------------------------------------------------
 *
 * 这一页原先只有一个大数字加「共 N 笔」，然后直接进入构成细节 ——
 * 用户的原话是「有效信息偏少，大部分已在首页展示」。
 *
 * 加了这四格之后，这一页先回答「跟别的期间比怎么样」，再回答「花在哪」，
 * 是两层不同的问题，而不是把首页那块搬过来重复一遍。
 *
 * 四项里有三项是服务端新补的（同比 / 单笔最高 / 分类环比）；
 * 环比其实**早就返回了**（`monthlyReport` 一直带着 `previous` 与 `change`），
 * 只是前端从来没读 —— 属于「数据已备好、只差画」。
 */

/** 环比 / 同比的百分比文案。null 表示上期没有任何记录 —— 不给百分比 */
function ratioText(ratio: number | null): string {
  if (ratio === null) return '—';
  const percent = ratio * 100;
  // 0.5% 以内视为持平：`+0%` 会让用户以为「没变化」，而它其实是「变化很小」
  if (Math.abs(percent) < 0.5) return '持平';
  return `${percent > 0 ? '+' : ''}${percent.toFixed(0)}%`;
}

/**
 * 涨落配色。**花得更多是坏消息**，所以涨=红、跌=绿。
 * 这与国内股市的红涨绿跌一致，也与「风险色 = 红」一致，两边不会打架。
 */
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

/** 日均。分母用「已过天数」，月初按整月除会把数字压得没有意义 */
const dailyAverageCents = computed(() => {
  const period = scope.value === 'month' ? month.value : `${year.value}-12`;
  return Math.round(totalCents.value / Math.max(1, elapsedDays(period)));
});

const metrics = computed<Metric[]>(() => {
  if (scope.value === 'year') {
    const data = yearly.value;
    if (data === null) return [];

    const activeMonths = data.months.filter((item) => item.totalCents !== 0).length;
    const peak = data.months.reduce(
      (best, item) => (item.totalCents > best.totalCents ? item : best),
      data.months[0] ?? { month: `${year.value}-01`, totalCents: 0, count: 0 },
    );

    return [
      {
        label: '与去年',
        value: ratioText(data.yearAgo.change.ratio),
        hint: `去年 ${formatCompact(data.yearAgo.totalCents)}`,
        tone: ratioTone(data.yearAgo.change.ratio),
      },
      { label: '月均', value: formatCompact(Math.round(data.totalCents / 12)), hint: '', tone: 'text-ink' },
      {
        label: '最高月',
        value: peak.totalCents === 0 ? '—' : `${Number(peak.month.slice(5))} 月`,
        hint: peak.totalCents === 0 ? '' : formatCompact(peak.totalCents),
        tone: 'text-ink',
      },
      {
        label: '有记录的月份',
        value: `${activeMonths} / 12`,
        hint: '',
        tone: 'text-ink',
      },
    ];
  }

  const data = monthly.value;
  if (data === null) return [];

  return [
    {
      label: '较上月',
      value: ratioText(data.change.ratio),
      hint: formatCompact(data.previous.totalCents),
      tone: ratioTone(data.change.ratio),
    },
    {
      label: '去年同月',
      value: ratioText(data.yearAgo.change.ratio),
      hint: formatCompact(data.yearAgo.totalCents),
      tone: ratioTone(data.yearAgo.change.ratio),
    },
    {
      label: '单笔最高',
      value: data.largest === null ? '—' : formatCompact(data.largest.cents),
      hint: data.largest?.categoryName ?? '',
      tone: 'text-ink',
    },
    { label: '日均', value: formatCompact(dailyAverageCents.value), hint: '', tone: 'text-ink' },
  ];
});
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+24px)]">
    <header class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+16px)] lg:px-6 lg:pt-8">
      <!--
        与流水页共用同一个期间选择器（流水、报表、导出三处一套）。
        只是这里多一层「按月 / 按年」的粒度开关，所以面板要跟着换网格：
        按月给 12 个月，按年给 12 年。

        整块**居中**：手机与桌面都以「2026 年 9 月」这一行为轴，
        粒度开关、期间、大数字三层对齐在同一条中线上；期间字数变化时
        也不会把两侧的元素推来推去。
      -->
      <div class="lg:mx-auto lg:max-w-md">
        <div class="flex gap-2 lg:justify-center">
          <ChipButton :active="scope === 'month'" @click="scope = 'month'">按月</ChipButton>
          <ChipButton :active="scope === 'year'" @click="scope = 'year'">按年</ChipButton>
        </div>

        <div class="mt-4 flex justify-center">
          <PeriodPicker
            v-if="scope === 'month'"
            v-model:month="month"
            align="center"
            :label="periodLabel"
          />
          <PeriodPicker
            v-else
            v-model:year="year"
            mode="year"
            align="center"
            :label="periodLabel"
          />
        </div>
      </div>

      <p v-if="loading && totalCents === 0" class="skeleton mt-6 h-[48px] rounded-sm" />
      <p v-else class="mt-6 text-center text-display font-extrabold leading-none tracking-tight">
        {{ formatCompact(totalCents) }}
      </p>
      <p class="mt-3 text-center text-xs text-ink-muted">
        共 {{ scope === 'month' ? (monthly?.count ?? 0) : (yearly?.count ?? 0) }} 笔
      </p>

      <!--
        概览四项指标。这一页原先只有「一个大数字 + 共 N 笔」就直接进入构成细节，
        所以看起来「信息偏少、跟首页重复」—— 而这不是缺内容，
        是缺**这一页才有的那一层问题**：跟别的期间比怎么样。
        四项里三项是服务端新补的，环比其实一直返回着，只是从前端没读。
      -->
      <div
        v-if="metrics.length > 0"
        class="mt-8 grid grid-cols-2 gap-x-6 gap-y-5 lg:mx-auto lg:max-w-4xl lg:grid-cols-4 lg:gap-x-10"
      >
        <div v-for="item in metrics" :key="item.label" class="min-w-0">
          <span class="block text-xs text-ink-muted">{{ item.label }}</span>
          <b class="mt-1 block truncate text-lg font-bold tracking-tight" :class="item.tone">
            {{ item.value }}
          </b>
          <!-- 对照值：同比/环比的「跟谁比」，以及单笔最高是哪一类 -->
          <span class="mt-0.5 block h-4 truncate text-xs text-ink-muted">{{ item.hint }}</span>
        </div>
      </div>

      <p v-if="errorMessage !== null" class="mt-3 text-center text-sm text-danger-text">
        {{ errorMessage }}
      </p>
    </header>

    <main class="mx-auto w-full max-w-[var(--content-max)] px-4 lg:px-6">
      <!-- 年度：12 个月的柱状图 -->
      <section v-if="scope === 'year'" class="mt-8" aria-label="每月支出">
        <h2 class="label-cn">每月支出</h2>

        <p v-if="!hasYearlyData" class="mt-3 text-sm text-ink-muted">这一年还没有记录</p>

        <div v-else class="mt-3">
          <div class="flex h-32 items-end gap-1">
            <div
              v-for="item in yearly?.months"
              :key="item.month"
              class="flex-1 rounded-t-sm bg-primary transition-all duration-300"
              :style="{
                height: `${Math.max(item.totalCents === 0 ? 0 : 4, (item.totalCents / maxMonth) * 100)}%`,
                opacity: item.month === month ? 1 : 0.55,
              }"
              :title="`${item.month} ${formatYuan(item.totalCents)}`"
            />
          </div>
          <div class="mt-2 flex gap-1">
            <span
              v-for="item in yearly?.months"
              :key="item.month"
              class="flex-1 text-center text-[10px] text-ink-muted"
            >
              {{ Number(item.month.slice(5)) }}
            </span>
          </div>
        </div>
      </section>

      <!--
        单栏纵向（设计稿的 `.duo` 就是 `grid-template-columns: 1fr`）：
        分类构成 → 按支付方式 → 按记录人。

        曾按「桌面上切成左右双栏」做过一版，已放弃：双栏里每栏只有半宽，
        排名行的占比条短到看不出差距、环图也被挤小；而这三块本来就是
        **同一份数据的三种切法**（花在什么上 / 怎么花的 / 谁记的），
        纵向读下来是一条线，不存在「在两栏之间来回找」的问题。
      -->
      <!--
        分类构成：**块内两栏** —— 左环图、右明细。

        页面本身仍是块纵向堆叠（分类构成 → 按支付方式 → 按记录人），
        「两栏」指的是这一块自己用两列，不是把不同的块并排。
        理由见 decisions.md：这三块是同一份数据的三种切法，纵向读下来是一条线，
        没有跨栏对照的需求；但**块内部**用两列则能把宽度用掉。

        明细现在有四列（名称 / 环比 / 占比 / 金额），所以**撤掉了上一轮加的
        `max-w-[22rem]`**。那个上限当时是必须的 —— 一行里只有「名称 … 数值」
        两段，拉满一整行会在中间空出 600px。现在中间有环比和占比两列，
        宽度被真实信息用掉了，与排名行「数据排名中间要有东西」是同一条规则。
        宽度上限和真实列是**互斥的两种解法**，有了后者就不需要前者。
      -->
      <section v-if="categories.length > 0" class="mt-8" aria-label="分类构成">
        <h2 class="label-cn">分类构成</h2>

        <div
          class="mt-3 flex flex-col items-center gap-6 lg:grid lg:grid-cols-[200px_minmax(0,1fr)] lg:items-start lg:gap-10"
        >
          <div class="relative shrink-0">
            <svg
              width="140"
              height="140"
              viewBox="0 0 42 42"
              role="img"
              :aria-label="`支出构成，共 ${categories.length} 个分类`"
            >
              <!-- 底圈：占比不足 100% 时剩下的那一段也有颜色，不会看着像缺了一块 -->
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

            <div class="absolute inset-0 grid place-content-center text-center">
              <b class="block text-lg font-extrabold tracking-tight">
                {{ formatCompact(totalCents) }}
              </b>
              <span class="text-xs text-ink-muted">{{ categories.length }} 个分类</span>
            </div>
          </div>

          <!--
            明细用「色点 + 名称 + 环比 + 占比 + 金额」：色点与上面每段弧一一对应。
            刻意不放分类图标 —— 一行里同时出现色点、图标、金额三个标记，
            反而看不出哪个颜色对的是哪段弧。图标在流水页与记账抽屉里承担识别，
            这里承担识别的是颜色。

            列宽**定死**（不用 auto）：每个 <li> 各自是一个独立 grid，
            列宽随内容变会让各行的数值起点参差不齐 —— 与排名行同一个坑。
          -->
          <ul class="@container w-full min-w-0">
            <li
              class="hidden pb-1 text-[11px] font-bold tracking-widest text-ink-muted @min-[560px]:grid @min-[560px]:grid-cols-[minmax(0,1fr)_72px_52px_104px] @min-[560px]:gap-x-3"
            >
              <span>分类</span>
              <span class="text-right">{{ scope === 'year' ? '较去年' : '较上月' }}</span>
              <span class="text-right">占比</span>
              <span class="text-right">金额</span>
            </li>

            <li
              v-for="item in categories"
              :key="item.categoryId"
              class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1 border-b border-line/60 py-2.5 last:border-b-0 @min-[560px]:grid-cols-[minmax(0,1fr)_72px_52px_104px]"
            >
              <span class="flex min-w-0 items-center gap-2.5">
                <span
                  class="h-2.5 w-2.5 shrink-0 rounded-[3px]"
                  :style="{
                    background: categoryColorVar(resolveCategoryColor(item.name, item.color)),
                  }"
                  aria-hidden="true"
                />
                <span class="min-w-0 truncate text-sm">{{ item.name }}</span>
              </span>

              <span class="shrink-0 text-right text-sm font-semibold @min-[560px]:order-4">
                {{ formatYuan(item.cents) }}
              </span>

              <span
                class="shrink-0 text-right text-xs font-semibold @min-[560px]:order-2"
                :class="ratioTone(item.changeRatio)"
              >
                {{ ratioText(item.changeRatio) }}
              </span>

              <span class="shrink-0 text-right text-xs text-ink-muted @min-[560px]:order-3">
                {{ (item.ratio * 100).toFixed(0) }}%
              </span>
            </li>
          </ul>
        </div>
      </section>

      <!--
        按支付方式。
        行结构是**排名行**：名称 | 占比条 | 笔数 | 金额（窄容器下折成两行，
        见 `@container`）。紧急度没有丢 —— 它从整块底色退到还款日那一行的
        文字颜色上，与首页「本月待还」共用 utils/urgency.ts，两处不会两套口径。

        宽容器下名称列定宽 192px：还款日那行是「9月28日 还款 · 今天到期」，
        136px 装不下，会被截成「…· 今天到…」—— 恰好把紧急度那两个字切掉。
        定宽（而非 `auto`）是必须的：每个 `<li>` 各自是一个 grid，
        列宽随内容变会让各行的条起点参差不齐。
      -->
      <section
        v-if="scope === 'month' && paymentRows.length > 0"
        class="mt-8 @container"
        aria-label="按支付方式"
      >
        <h2 class="label-cn">按支付方式</h2>

        <ul class="mt-3">
          <li
            v-for="row in paymentRows"
            :key="row.key"
            class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1.5 border-b border-line/60 py-2.5 last:border-b-0 @min-[620px]:grid-cols-[192px_1fr_52px_100px]"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span class="grid h-7 w-7 shrink-0 place-items-center rounded-sm bg-sunken">
                <component
                  :is="resolvePaymentMethodIcon(row.type)"
                  :size="16"
                  class="text-ink-muted"
                  aria-hidden="true"
                />
              </span>
              <span class="min-w-0">
                <span class="block truncate text-sm font-semibold">{{ row.name }}</span>
                <span
                  v-if="row.type === 'credit' && row.repaymentDate !== null"
                  class="block truncate text-xs"
                  :class="URGENCY_META[urgencyOfOptional(row.repaymentDate)]"
                >
                  {{ formatMonthDay(row.repaymentDate) }} 还款 ·
                  {{ urgencyLabel(row.repaymentDate) }}
                </span>
              </span>
            </span>

            <span class="shrink-0 text-right text-sm font-semibold @min-[620px]:order-4">
              {{ formatYuan(row.cents) }}
            </span>

            <!-- 占比条：排名行中间必须有东西，否则名称与金额隔着半栏对不上 -->
            <span class="block h-1.5 overflow-hidden rounded-full bg-sunken @min-[620px]:order-2">
              <span
                class="block h-full rounded-full bg-primary"
                :style="{ width: `${row.share * 100}%` }"
              />
            </span>

            <span class="shrink-0 text-right text-xs text-ink-muted @min-[620px]:order-3">
              {{ row.count }} 笔
            </span>
          </li>
        </ul>
      </section>

      <!-- 按记录人：与上面同一种行结构，只是身份物换成姓名首字 -->
      <section v-if="memberRows.length > 0" class="mt-8 @container" aria-label="按记录人">
        <h2 class="label-cn">按记录人</h2>

        <ul class="mt-3">
          <li
            v-for="row in memberRows"
            :key="row.key"
            class="grid grid-cols-[1fr_auto] items-center gap-x-3 gap-y-1.5 border-b border-line/60 py-2.5 last:border-b-0 @min-[620px]:grid-cols-[192px_1fr_52px_100px]"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span
                class="grid h-7 w-7 shrink-0 place-items-center rounded-sm bg-sunken text-xs font-semibold text-ink-muted"
                aria-hidden="true"
              >
                {{ row.name.slice(0, 1) }}
              </span>
              <span class="min-w-0 truncate text-sm font-semibold">{{ row.name }}</span>
            </span>

            <span class="shrink-0 text-right text-sm font-semibold @min-[620px]:order-4">
              {{ formatYuan(row.cents) }}
            </span>

            <span class="block h-1.5 overflow-hidden rounded-full bg-sunken @min-[620px]:order-2">
              <span
                class="block h-full rounded-full bg-primary"
                :style="{ width: `${row.share * 100}%` }"
              />
            </span>

            <span class="shrink-0 text-right text-xs text-ink-muted @min-[620px]:order-3">
              {{ row.count }} 笔
            </span>
          </li>
        </ul>
      </section>

      <p
        v-if="!loading && categories.length === 0"
        class="py-12 text-center text-sm text-ink-muted"
      >
        {{ periodLabel }}还没有记录
      </p>
    </main>
  </div>
</template>
