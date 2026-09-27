<script setup lang="ts">
/**
 * 首页仪表盘。
 *
 * 三块内容，按「你最想先看到什么」排序：
 *   1. 本月支出总额 —— 这是整个应用存在的理由，必须一眼可见
 *   2. 待还 —— 信用卡的还款日快到了是要**行动**的事，不能埋在报表里
 *   3. 支出构成 + 最近流水 —— 回答「花在什么上面」
 */
import { computed, onMounted, ref, watch } from 'vue';
import { RouterLink } from 'vue-router';

import { categoryColorVar, resolveCategoryColor } from '@/utils/category-colors';

import {
  ApiError,
  expenses as expensesApi,
  reports as reportsApi,
  type Expense,
  type MonthlyReport,
} from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import PlanTodoCard from '@/components/PlanTodoCard.vue';
import { usePlansStore } from '@/stores/plans';
import { useUiStore } from '@/stores/ui';
import {
  currentMonth,
  formatDayLabel,
  formatMonthDay,
  formatMonthLabel,
  shiftMonth,
  todayLocal,
} from '@/utils/dates';
import { formatCompact, formatYuan } from '@/utils/money';
import {
  URGENCY_BAR,
  URGENCY_CARD,
  URGENCY_META,
  urgencyLabel,
  urgencyOfOptional,
} from '@/utils/urgency';

const ui = useUiStore();
const plansStore = usePlansStore();

const month = ref(currentMonth());
const report = ref<MonthlyReport | null>(null);
const recent = ref<Expense[]>([]);
const loading = ref(true);
const errorMessage = ref<string | null>(null);
/** 自动入账的提示：它改变了账目，但用户并没有主动操作 */
const settleNotice = ref<string | null>(null);

async function load(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;

  try {
    /**
     * 顺序不能反：**先结算到期的自动入账待办，再取报表**。
     * 结算会生成新的支出记录，先取报表的话这一次的总额会把刚入账的那几笔漏掉
     * （用户得刷新一次才看得到，看起来像「数字不对」）。
     *
     * 也没有把这件事写成「结算后触发一次全站刷新」：那会让 load() 递归调用自己。
     */
    const settled = await plansStore.loadDueTodos();
    settleNotice.value = settled > 0 ? `已自动入账 ${settled} 笔到期的支出` : null;

    const [monthResult, listResult] = await Promise.all([
      reportsApi.monthly(month.value),
      expensesApi.list({ month: month.value, limit: 8 }),
    ]);
    report.value = monthResult.report;
    recent.value = listResult.items;
  } catch (error) {
    errorMessage.value =
      error instanceof ApiError ? error.message : '加载失败，请下拉重试';
  } finally {
    loading.value = false;
  }
}

/** 待办卡片处理完一条之后：重算整个仪表盘（总额、构成、流水都会变） */
function onTodoChanged(): void {
  ui.markDataChanged();
}

onMounted(load);
watch(month, load);
// 记账抽屉保存成功后刷新：整个仪表盘的数字都会变
watch(() => ui.dataVersion, load);

const isCurrentMonth = computed(() => month.value === currentMonth());

/**
 * 环比文案。
 *
 * `ratio` 为 null 表示**上期没有任何记录** —— 此时「涨了 100%」是误导：
 * 从 0 到 X 的百分比在数学上无意义，用户看到会以为消费暴涨。
 */
/*
 * hero 上的几个次要指标。
 * 之前只有一句连写的环比文案；拆成独立数值后才能在色块里排成
 * 「较上月 / 笔数 / 日均 / 本月待还」四格，窄屏 2x2、宽屏一行。
 */

/** 环比。ratio 为 null 表示**上期没有任何记录** —— 从 0 到 X 的百分比是误导 */
const changeRatioText = computed(() => {
  const data = report.value;
  if (data === null) return null;
  if (data.previous.totalCents === 0 && data.totalCents === 0) return null;
  if (data.change.ratio === null) return null;
  const sign = data.change.ratio >= 0 ? '+' : '';
  return `${sign}${(data.change.ratio * 100).toFixed(1)}%`;
});

const changeDeltaText = computed(() => {
  const data = report.value;
  if (data === null || data.change.ratio === null) return '';
  const sign = data.change.ratio >= 0 ? '+' : '';
  return `${sign}${formatYuan(data.change.deltaCents)}`;
});

/** 本月有还款日的信用类支付方式 */
const creditDue = computed(() =>
  (report.value?.paymentMethods ?? []).filter((item) => item.type === 'credit'),
);

const totalCents = computed(() => report.value?.totalCents ?? 0);

/** 本月笔数 */
const monthCount = computed(() => report.value?.count ?? 0);

/** 本月待还合计 */
const dueTotalCents = computed(() =>
  creditDue.value.reduce((sum, item) => sum + item.cents, 0),
);

/**
 * 日均。用「本月已过天数」而不是整月天数 —— 月初看日均没有意义，
 * 月末它才逼近真实水平。这是口径问题不是 bug，但要写清楚。
 */
const dailyAverageCents = computed(() => {
  const year = Number(month.value.slice(0, 4));
  const mon = Number(month.value.slice(5, 7));
  const daysInMonth = new Date(Date.UTC(year, mon, 0)).getUTCDate();
  const elapsed = isCurrentMonth.value ? Number(todayLocal().slice(8, 10)) : daysInMonth;
  return Math.round(totalCents.value / Math.max(1, elapsed));
});
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+24px)]">
    <!-- 月份切换：上一月 / 当前月 / 下一月 -->
    <header class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+20px)] lg:px-6 lg:pt-8">
      <!--
        月份切换在桌面上收窄到 max-w-md 并居中：不限宽的话 ← 和 → 会被 flex-1
        的标题推到相距 900px，两个按钮看起来跟标题没关系了。
        h1 用 min-w-32 定宽，月份从「9月」变成「12月」时箭头不会左右跳。
      -->

      <!--
        hero：Flat 设计系统的 "full-section color block"。
        之前整页纯白，等于把这条要求丢掉了 —— 而它是整个页面唯一该「喊」的地方。

        次要指标排成 2x2（窄屏）/ 一行四列（宽屏）：**用宽度承载信息层级**，
        而不是把四句话挤在数字底下。
      -->
      <div
        class="mt-6 rounded-lg bg-primary-fill p-5 text-on-primary lg:mt-8 lg:rounded-[14px] lg:p-7"
      >
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-sm bg-white/15 transition-colors duration-200 hover:bg-white/30"
            aria-label="上一个月"
            @click="month = shiftMonth(month, -1)"
          >
            ←
          </button>
          <span class="text-sm font-bold opacity-95">{{ formatMonthLabel(month) }}</span>
          <button
            type="button"
            class="grid h-8 w-8 place-items-center rounded-sm bg-white/15 transition-colors duration-200 hover:bg-white/30 disabled:opacity-30"
            :disabled="isCurrentMonth"
            aria-label="下一个月"
            @click="month = shiftMonth(month, 1)"
          >
            →
          </button>

          <!--
            计划与设置：手机上不占底栏格子（底栏留给每天要点几十次的四个入口）。
            桌面上隐藏 —— 顶部导航里已有，留着就是同一屏两套一模一样的链接。
          -->
          <span class="flex-1" aria-hidden="true" />
                    <RouterLink
            :to="{ name: 'settings' }"
            class="rounded-sm px-2 py-1 text-sm font-semibold text-white/85 transition-colors duration-200 hover:text-white lg:hidden"
          >
            设置
          </RouterLink>
        </div>

        <p class="mt-4 text-xs font-semibold tracking-widest opacity-80">本月支出</p>

        <p
          v-if="loading && report === null"
          class="skeleton mt-2 h-[52px] w-56 rounded-sm"
        />
        <p v-else class="mt-2 text-amount font-extrabold leading-none tracking-tight">
          {{ formatCompact(totalCents) }}
        </p>

        <div class="mt-5 grid grid-cols-2 gap-x-6 gap-y-4 lg:mt-6 lg:grid-cols-4 lg:gap-x-10">
          <div class="text-xs">
            <span class="block opacity-75">较上月</span>
            <b class="mt-0.5 block text-[15px] font-bold">
              <template v-if="changeRatioText !== null">
                {{ changeRatioText }}
                <span class="opacity-80">（{{ changeDeltaText }}）</span>
              </template>
              <template v-else>—</template>
            </b>
          </div>
          <div class="text-xs">
            <span class="block opacity-75">笔数</span>
            <b class="mt-0.5 block text-[15px] font-bold">{{ monthCount }} 笔</b>
          </div>
          <div class="text-xs">
            <span class="block opacity-75">日均</span>
            <b class="mt-0.5 block text-[15px] font-bold">{{ formatCompact(dailyAverageCents) }}</b>
          </div>
          <div class="text-xs">
            <span class="block opacity-75">本月待还</span>
            <b class="mt-0.5 block text-[15px] font-bold">{{ formatCompact(dueTotalCents) }}</b>
          </div>
        </div>

        <p v-if="errorMessage !== null" class="mt-4 text-sm font-semibold text-white">
          {{ errorMessage }}
        </p>
      </div>
    </header>

    <main class="mx-auto w-full max-w-[var(--content-max)] px-4 lg:px-6">
      <p v-if="settleNotice !== null" class="mt-6 rounded-md bg-surface px-4 py-3 text-sm text-secondary-text">
        {{ settleNotice }}
      </p>

      <!--
        桌面双栏：**左栏放「要动手的事」，右栏放「看的事」**。
        分栏依据不是内容多少，而是「用户要不要做决定」—— 待办与待还需要操作，
        构成与流水只需阅读。手机上它们本来就是上下堆叠的，所以这里只是
        在宽屏把它们并排，顺序不变。

        各 section 的 mt 在 lg 下归零、改由两栏的 space-y 统一控制：
        否则左栏起点是 24px、右栏是 32px，并排后这个 8px 的差会直接看出来。
      -->
      <!--
        单列堆叠的整宽区块，**不是双栏**。

        上一版是固定的 grid-cols-2：左栏（该处理了 / 本月待还）两个区块都有 v-if，
        待办清空之后左栏就成了空壳，内容孤零零贴在右侧 —— 待办清空恰恰是常态。
        现在宽度在**区块内部**用（构成图例两栏、待办卡自动换行），
        空态就是整块不出现，不会留洞。
      -->
      <div>
          <!-- 该处理了：需要用户**行动**，排在所有信息性内容之前 -->
          <section
            v-if="plansStore.dueTodos.length > 0"
            class="mt-8"
            aria-label="该处理了"
          >
        <div class="flex items-baseline justify-between">
          <h2 class="label-cn">该处理了</h2>
                  </div>

        <!--
          列数由**内容最小宽**决定，不写死 sm:2 / xl:3。

          写死列数的问题：1 条待办时卡片只占 1/3，右侧空出 2/3 ——
          而这一区块是「要动手的事」，空着的大片区域会让人怀疑是不是没加载完。
          auto-fit(minmax(280px,1fr)) 下：
            1 条 → 整行；2 条 → 各半；3 条 → 三等分；
            4 条起 → 每 3 个一行，末行靠左、有多少占多少。
          280px 是卡片能舒服放下「标题 + 金额 + 两个按钮」的下限：
            手机 358px 容器 → 1 列；平板 600px → 2 列；桌面 1120px → 3 列。
          与 sm/xl 断点方案在这三档的结果一致，但 1/2/4/5 条时不再留洞。
        -->
        <div
          class="mt-3 grid grid-cols-[repeat(auto-fit,minmax(280px,1fr))] gap-3"
        >
          <PlanTodoCard
            v-for="todo in plansStore.dueTodos"
            :key="todo.id"
            :todo="todo"
            @changed="onTodoChanged"
          />
        </div>
      </section>

      <!--
        本月待还。
        原来这里写的是「用强调色块，且是页面上唯一的强色块」—— 但待办卡当时也用琥珀满色，
        这条约定在实现时就失效了，于是整屏变成五块并列的琥珀。
        现在两处共用 utils/urgency.ts：底色一律中性，颜色只走左侧色条与状态文字。
      -->
          <section v-if="creditDue.length > 0" class="mt-6 space-y-2 lg:mt-0" aria-label="本月待还">
        <h2 class="label-cn">本月待还</h2>

        <div
          v-for="item in creditDue"
          :key="item.paymentMethodId"
          class="relative overflow-hidden rounded-md px-3.5 py-3"
          :class="URGENCY_CARD[urgencyOfOptional(item.repaymentDate)]"
        >
          <span
            class="absolute inset-y-0 left-0 w-1"
            :class="URGENCY_BAR[urgencyOfOptional(item.repaymentDate)]"
            aria-hidden="true"
          />
          <div class="flex items-center gap-3">
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-bold">{{ item.name }}</p>
              <p
                class="truncate text-xs"
                :class="URGENCY_META[urgencyOfOptional(item.repaymentDate)]"
              >
                {{
                  item.repaymentDate === null
                    ? '本月无还款日'
                    : `${formatMonthDay(item.repaymentDate)} · ${urgencyLabel(item.repaymentDate)}`
                }}
              </p>
            </div>
            <p class="shrink-0 text-lg font-bold">{{ formatYuan(item.cents) }}</p>
          </div>
        </div>
          </section>
          <!-- 支出构成 -->
          <section
            v-if="(report?.categories.length ?? 0) > 0"
            class="mt-8 lg:mt-0"
            aria-label="支出构成"
          >
            <h2 class="label-cn">支出构成</h2>

        <!--
          一条**整体的**堆叠条放最上面：各分类占多上一眼可见。
          之前是每行一条各自独立的横条 —— 它们互相不可比（都占满自己那一行），
          「构成」这件事反而看不出来。
        -->
        <div class="flex h-2.5 overflow-hidden rounded-full bg-surface">
          <span
            v-for="item in report?.categories"
            :key="item.categoryId"
            :style="{
              width: `${item.ratio * 100}%`,
              background: categoryColorVar(resolveCategoryColor(item.name, item.color)),
            }"
          />
        </div>

        <!-- 图例两栏：把卡片里的横向空间用掉，而不是让每行拖得很长 -->
        <ul class="mt-4 grid gap-x-10 gap-y-1 sm:grid-cols-2">
          <li
            v-for="item in report?.categories"
            :key="item.categoryId"
            class="flex items-center gap-2.5 py-1.5"
          >
            <span
              class="h-2.5 w-2.5 shrink-0 rounded-[3px]"
              :style="{ background: categoryColorVar(resolveCategoryColor(item.name, item.color)) }"
              aria-hidden="true"
            />
            <CategoryIcon
              :name="item.name"
              :icon="item.icon"
              :color="item.color"
              :size="18"
            />
            <span class="min-w-0 flex-1 truncate text-sm">{{ item.name }}</span>
            <span class="shrink-0 text-xs text-ink-muted">
              {{ (item.ratio * 100).toFixed(0) }}%
            </span>
            <span class="shrink-0 text-sm font-semibold">{{ formatYuan(item.cents) }}</span>
          </li>
        </ul>
      </section>

          <!-- 最近流水 -->
          <section class="mt-8 lg:mt-0" aria-label="最近流水">
            <div class="flex items-baseline justify-between">
              <h2 class="label-cn">最近流水</h2>
          <RouterLink
            :to="{ name: 'ledger' }"
            class="text-xs font-semibold text-primary-text hover:underline"
          >
            全部
          </RouterLink>
        </div>

        <p v-if="!loading && recent.length === 0" class="mt-3 text-sm text-ink-muted">
          这个月还没有记录。点下方「记一笔」开始。
        </p>

        <ul class="mt-2">
          <li v-for="row in recent" :key="row.id">
            <button
              type="button"
              class="flex w-full items-center gap-3 rounded-md px-2 py-2.5 text-left transition-colors duration-200 hover:bg-sunken"
              @click="ui.openEdit(row)"
            >
              <span class="w-12 shrink-0 text-xs text-ink-muted">
                {{ formatDayLabel(row.spendDate) }}
              </span>
              <span class="w-5 shrink-0 text-ink-muted">
                <CategoryIcon
                :name="row.categoryName"
                :icon="row.categoryIcon"
                :color="row.parentCategoryColor ?? row.categoryColor"
                :color-name="row.parentCategoryName ?? row.categoryName"
                :size="18"
              />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm">
                  {{ row.parentCategoryName === null ? row.categoryName : `${row.parentCategoryName} · ${row.categoryName}` }}
                </span>
                <span class="block truncate text-xs text-ink-muted">
                  {{ row.note === '' ? row.paymentMethodName : row.note }}
                </span>
              </span>
              <span
                class="shrink-0 text-sm font-semibold"
                :class="row.amountCents < 0 ? 'text-danger-text' : ''"
              >
                {{ formatYuan(row.amountCents) }}
              </span>
            </button>
          </li>
        </ul>
          </section>
      </div>
    </main>
  </div>
</template>
