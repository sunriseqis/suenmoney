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
  type YearlyReport,
} from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import ChipButton from '@/components/ChipButton.vue';
import { useUiStore } from '@/stores/ui';
import { categoryColorVar, resolveCategoryColor } from '@/utils/category-colors';
import { currentMonth, formatMonthLabel, formatMonthDay, shiftMonth } from '@/utils/dates';
import { resolvePaymentMethodIcon } from '@/utils/icons';
import { formatCompact, formatYuan } from '@/utils/money';
import {
  URGENCY_BAR,
  URGENCY_CARD,
  URGENCY_META,
  urgencyLabel,
  urgencyOfOptional,
} from '@/utils/urgency';

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

const maxCategory = computed(() => Math.max(1, ...categories.value.map((item) => item.cents)));
const maxMonth = computed(() =>
  Math.max(1, ...(yearly.value?.months ?? []).map((item) => item.totalCents)),
);

function step(delta: number): void {
  if (scope.value === 'month') {
    month.value = shiftMonth(month.value, delta);
  } else {
    year.value = String(Number(year.value) + delta);
  }
}

const periodLabel = computed(() =>
  scope.value === 'month' ? formatMonthLabel(month.value) : `${year.value} 年`,
);

/** 年度视图里是否有数据 —— 没有就不画一根根都是 0 的柱子 */
const hasYearlyData = computed(() => (yearly.value?.totalCents ?? 0) !== 0);
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+24px)]">
    <header class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+16px)] lg:px-6 lg:pt-8">
      <!--
        与首页同理：桌面上把期间切换收窄成一块紧凑的选择器。

        并且整块**居中**：手机上是 ← 贴左边、→ 贴右边（拇指够得到），
        但桌面上把 24px 的箭头分置 448px 两端，看着跟中间的「2026年9月」
        没关系了。居中 + h1 定宽（min-w-32）后，三个元素成为一个整体，
        而且月份字数变化时箭头不会左右跳。
      -->
      <div class="lg:mx-auto lg:max-w-md">
        <div class="flex gap-2 lg:justify-center">
          <ChipButton :active="scope === 'month'" @click="scope = 'month'">按月</ChipButton>
          <ChipButton :active="scope === 'year'" @click="scope = 'year'">按年</ChipButton>
        </div>

        <div class="mt-4 flex items-center gap-2 lg:justify-center lg:gap-8">
        <button
          type="button"
          class="rounded-sm px-2 py-1 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink"
          aria-label="上一期"
          @click="step(-1)"
        >
          ←
        </button>
        <h1 class="flex-1 text-center text-sm font-semibold text-ink-muted lg:min-w-32 lg:flex-none">
          {{ periodLabel }}
        </h1>
        <button
          type="button"
          class="rounded-sm px-2 py-1 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink"
          aria-label="下一期"
          @click="step(1)"
        >
          →
        </button>
        </div>
      </div>

      <p v-if="loading && totalCents === 0" class="skeleton mt-6 h-[48px] rounded-sm" />
      <p v-else class="mt-6 text-center text-display font-extrabold leading-none tracking-tight">
        {{ formatCompact(totalCents) }}
      </p>
      <p class="mt-3 text-center text-xs text-ink-muted">
        共 {{ scope === 'month' ? (monthly?.count ?? 0) : (yearly?.count ?? 0) }} 笔
      </p>

      <p v-if="errorMessage !== null" class="mt-3 text-center text-sm text-danger-text">
        {{ errorMessage }}
      </p>
    </header>

    <main class="mx-auto w-full max-w-[var(--content-max)] px-4 lg:px-6">
      <!-- 年度：12 个月的柱状图 -->
      <section v-if="scope === 'year'" class="mt-8 lg:mt-0" aria-label="每月支出">
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
        桌面双栏：左边「钱花在什么上」（分类构成），右边「怎么花的」（支付方式 + 记录人）。
        分栏依据是「回答的是哪个问题」，而不是条目多少 —— 这样扫视时每栏
        内部是同一类信息，不用在两栏之间来回找。
      -->
      <div class="lg:mt-8 lg:grid lg:grid-cols-2 lg:items-start lg:gap-8">
        <div class="lg:space-y-6">
          <!-- 分类构成 -->
          <section v-if="categories.length > 0" class="mt-8 lg:mt-0" aria-label="分类构成">
            <h2 class="label-cn">分类构成</h2>

        <ul class="mt-3 space-y-3">
          <li v-for="item in categories" :key="item.categoryId">
            <!-- 图标是 18px 的方块，用 items-center 对齐；baseline 会让它跟文字顶边不齐 -->
            <div class="flex items-center gap-3">
              <CategoryIcon :name="item.name" :icon="item.icon" :color="item.color" :size="18" />
              <span class="min-w-0 flex-1 truncate text-sm font-semibold">{{ item.name }}</span>
              <span class="shrink-0 text-xs text-ink-muted">{{ item.count }} 笔</span>
              <span class="shrink-0 text-xs text-ink-muted">
                {{ (item.ratio * 100).toFixed(1) }}%
              </span>
              <span class="shrink-0 text-sm font-bold">{{ formatYuan(item.cents) }}</span>
            </div>
            <div class="mt-1.5 h-2 overflow-hidden rounded-sm bg-surface">
              <div
                class="h-full rounded-sm"
                :style="{
                  width: `${(item.cents / maxCategory) * 100}%`,
                  background: categoryColorVar(resolveCategoryColor(item.name, item.color)),
                }"
              />
            </div>
          </li>
        </ul>
      </section>

        </div>

        <div class="lg:space-y-6">
          <!-- 按支付方式 -->
          <section
            v-if="scope === 'month' && (monthly?.paymentMethods.length ?? 0) > 0"
            class="mt-8 lg:mt-0"
            aria-label="按支付方式"
          >
            <h2 class="label-cn">按支付方式</h2>
        <ul class="mt-3 space-y-2">
          <li
            v-for="item in monthly?.paymentMethods"
            :key="item.paymentMethodId"
            class="relative overflow-hidden rounded-md px-3.5 py-3"
            :class="URGENCY_CARD[urgencyOfOptional(item.repaymentDate)]"
          >
            <!-- 与首页「本月待还」同一套紧急度配色，两处不会出现两套口径 -->
            <span
              class="absolute inset-y-0 left-0 w-1"
              :class="URGENCY_BAR[urgencyOfOptional(item.repaymentDate)]"
              aria-hidden="true"
            />
            <div class="flex items-center gap-3">
              <component
                :is="resolvePaymentMethodIcon(item.type)"
                :size="18"
                class="shrink-0 text-ink-muted"
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-semibold">{{ item.name }}</span>
                <span
                  class="block truncate text-xs"
                  :class="URGENCY_META[urgencyOfOptional(item.repaymentDate)]"
                >
                  {{ item.count }} 笔
                  <template v-if="item.type === 'credit' && item.repaymentDate !== null">
                    · {{ formatMonthDay(item.repaymentDate) }} 还款 ·
                    {{ urgencyLabel(item.repaymentDate) }}
                  </template>
                </span>
              </span>
              <span class="shrink-0 text-sm font-bold">{{ formatYuan(item.cents) }}</span>
            </div>
          </li>
        </ul>
      </section>

          <!-- 按记录人 -->
          <section
            v-if="(scope === 'month' ? monthly?.members : yearly?.members)?.length"
            class="mt-8 lg:mt-0"
            aria-label="按记录人"
          >
        <h2 class="label-cn">按记录人</h2>
        <ul class="mt-3 space-y-2">
          <li
            v-for="item in scope === 'month' ? monthly?.members : yearly?.members"
            :key="item.ownerId"
            class="flex items-center gap-3"
          >
            <span class="min-w-0 flex-1 truncate text-sm">{{ item.name }}</span>
            <span class="shrink-0 text-xs text-ink-muted">{{ item.count }} 笔</span>
            <span class="shrink-0 text-sm font-semibold">{{ formatYuan(item.cents) }}</span>
          </li>
        </ul>
          </section>
        </div>
      </div>

      <!-- 空态放在栅格**外面**：它要占满整宽，塞进某一栏会看着像那一栏的内容 -->
      <p
        v-if="!loading && categories.length === 0"
        class="py-12 text-center text-sm text-ink-muted"
      >
        {{ periodLabel }}还没有记录
      </p>
    </main>
  </div>
</template>
