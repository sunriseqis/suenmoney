<script setup lang="ts">
/**
 * 年度总结页 —— 年度回顾叙事与成就印记。
 *
 * 与报表页的「年档」区别：
 * - 报表页负责「查账与分析」：数据表格、对比矩阵、分类明细；
 * - 年度总结页负责「读与回顾」：叙事化总览、年度之最、月度起伏画卷、年度成就徽章。
 */
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import {
  ArrowLeft,
  Award,
  Calendar,
  CreditCard,
  Flame,
  Sparkles,
  TrendingDown,
  Trophy,
} from '@lucide/vue';

import { ApiError, reports as reportsApi, type YearlyReport } from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { categoryColorVar } from '@/utils/category-colors';
import { formatMonthDay, formatMonthLabel } from '@/utils/dates';
import { formatCompact, formatYuan } from '@/utils/money';

const route = useRoute();
const router = useRouter();
const dict = useDictionariesStore();

const currentYear = new Date().getFullYear();
const year = ref(
  typeof route.query.year === 'string' && route.query.year.match(/^\d{4}$/)
    ? route.query.year
    : String(currentYear),
);

const loading = ref(false);
const errorMessage = ref<string | null>(null);
const report = ref<YearlyReport | null>(null);

// 可选年份列表（从最早年份到今年）
const availableYears = computed(() => {
  const list: string[] = [];
  for (let y = currentYear; y >= currentYear - 5; y -= 1) {
    list.push(String(y));
  }
  return list;
});

async function loadData(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  try {
    const res = await reportsApi.yearly(year.value);
    report.value = res.report;
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '加载年度总结失败';
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  dict.load();
  void loadData();
});
watch(year, () => {
  void loadData();
});

// 月均支出
const monthlyAverageCents = computed(() => {
  if (!report.value || report.value.totalCents === 0) return 0;
  return Math.round(report.value.totalCents / 12);
});

// 最大单月支出占比
const maxMonthCents = computed(() => {
  if (!report.value) return 1;
  const max = Math.max(...report.value.months.map((m) => m.totalCents));
  return max > 0 ? max : 1;
});

// 动态成就勋章计算
interface Achievement {
  id: string;
  title: string;
  desc: string;
  icon: typeof Trophy;
  colorClass: string;
}

const achievements = computed<Achievement[]>(() => {
  const r = report.value;
  if (!r || r.totalCents === 0) return [];

  const list: Achievement[] = [];

  // 1. 坚持记账
  if (r.count >= 200) {
    list.push({
      id: 'active_master',
      title: '记账达人',
      desc: `全年坚持录入 ${r.count} 笔真实账单，账目井井有条`,
      icon: Trophy,
      colorClass: 'text-amber-500 bg-amber-500/10',
    });
  } else if (r.count >= 30) {
    list.push({
      id: 'active_starter',
      title: '生活记录者',
      desc: `全年在册 ${r.count} 笔生活点滴，开启自律之旅`,
      icon: Sparkles,
      colorClass: 'text-emerald-500 bg-emerald-500/10',
    });
  }

  // 2. 消费平稳 / 节制
  if (r.yearAgo.totalCents > 0 && r.yearAgo.change.deltaCents < 0) {
    list.push({
      id: 'saving_champion',
      title: '节约先锋',
      desc: `较去年支出减少了 ${formatYuan(Math.abs(r.yearAgo.change.deltaCents))}，克制显成效`,
      icon: TrendingDown,
      colorClass: 'text-blue-500 bg-blue-500/10',
    });
  }

  // 3. 多彩生活（分类丰富度）
  if (r.categories.length >= 5) {
    list.push({
      id: 'rich_life',
      title: '全景生活家',
      desc: `涉猎 ${r.categories.length} 个主要消费领域，生活丰盈多彩`,
      icon: Award,
      colorClass: 'text-purple-500 bg-purple-500/10',
    });
  }

  // 4. 单笔大件
  if (r.largest && r.largest.cents >= 100000) {
    list.push({
      id: 'major_purchase',
      title: '品质投资',
      desc: `在「${r.largest.categoryName}」果断投入大件，提升生活质感`,
      icon: CreditCard,
      colorClass: 'text-rose-500 bg-rose-500/10',
    });
  }

  return list;
});

function goBack(): void {
  router.push({ name: 'report', query: { scope: 'year', year: year.value } });
}
</script>

<template>
  <div class="min-h-screen bg-canvas px-4 py-6 sm:px-6 lg:py-10">
    <div class="mx-auto max-w-3xl space-y-6">
      <!-- 顶栏导航与年份切换 -->
      <header class="flex items-center justify-between">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-sm px-2.5 py-1.5 text-xs font-semibold text-ink-muted transition-colors hover:bg-surface hover:text-ink"
          @click="goBack"
        >
          <ArrowLeft class="h-4 w-4" />
          <span>返回年度报表</span>
        </button>

        <div class="flex items-center gap-2">
          <label for="year-selector" class="text-xs text-ink-muted">总结年份：</label>
          <select
            id="year-selector"
            v-model="year"
            class="rounded-sm bg-surface px-3 py-1.5 text-xs font-bold text-ink outline-none border border-line"
          >
            <option v-for="y in availableYears" :key="y" :value="y">{{ y }} 年</option>
          </select>
        </div>
      </header>

      <!-- 错误提示 -->
      <p v-if="errorMessage !== null" class="rounded-md bg-danger/10 p-3 text-xs text-danger-text">
        {{ errorMessage }}
      </p>

      <!-- 加载态 -->
      <div v-if="loading" class="rounded-md bg-surface p-12 text-center text-xs text-ink-muted">
        正在编排 {{ year }} 年度生活画卷…
      </div>

      <!-- 数据为空 -->
      <div
        v-else-if="report === null || report.totalCents === 0"
        class="rounded-md bg-surface p-12 text-center text-xs text-ink-muted"
      >
        {{ year }} 年还没有任何支出记录，快去记录第一笔生活开销吧！
      </div>

      <!-- 年度报告正文 -->
      <main v-else class="space-y-6">
        <!-- 核心 Hero：年度总结封面 -->
        <section
          aria-label="年度全貌"
          class="relative overflow-hidden rounded-md bg-gradient-to-br from-surface via-surface to-primary/5 p-6 shadow-sm sm:p-8"
        >
          <div class="relative z-10">
            <span class="inline-flex items-center gap-1.5 rounded-full bg-primary-fill/10 px-3 py-1 text-xs font-bold text-primary">
              <Sparkles class="h-3.5 w-3.5" />
              <span>{{ year }} 年度财务印记</span>
            </span>

            <p class="mt-4 text-xs font-medium text-ink-muted">全年累计生活总支出</p>
            <h1 class="mt-1 text-3xl font-extrabold tracking-tight text-ink sm:text-4xl">
              {{ formatYuan(report.totalCents) }}
            </h1>

            <div class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <div class="rounded-sm bg-canvas/70 p-3">
                <span class="text-[11px] text-ink-muted">总记录笔数</span>
                <p class="mt-0.5 text-base font-bold text-ink">{{ report.count }} 笔</p>
              </div>

              <div class="rounded-sm bg-canvas/70 p-3">
                <span class="text-[11px] text-ink-muted">月均支出</span>
                <p class="mt-0.5 text-base font-bold text-ink">
                  {{ formatCompact(monthlyAverageCents) }}
                </p>
              </div>

              <div class="rounded-sm bg-canvas/70 p-3">
                <span class="text-[11px] text-ink-muted">涉猎大类</span>
                <p class="mt-0.5 text-base font-bold text-ink">{{ report.categories.length }} 个</p>
              </div>

              <div class="rounded-sm bg-canvas/70 p-3">
                <span class="text-[11px] text-ink-muted">较去年同期</span>
                <p class="mt-0.5 text-base font-bold text-ink">
                  <span
                    v-if="report.yearAgo.change.ratio !== null"
                    :class="report.yearAgo.change.deltaCents > 0 ? 'text-accent-text' : 'text-emerald-500'"
                  >
                    {{ report.yearAgo.change.deltaCents > 0 ? '↑' : '↓' }}
                    {{ Math.abs(Math.round(report.yearAgo.change.ratio * 100)) }}%
                  </span>
                  <span v-else class="text-ink-muted">首年</span>
                </p>
              </div>
            </div>
          </div>
        </section>

        <!-- 年度之最（Peak & Moments） -->
        <section aria-label="年度之最" class="rounded-md bg-surface p-5 sm:p-6">
          <h2 class="label-cn mb-4">年度之最 · 特别记忆</h2>

          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <!-- 单笔最贵一笔 -->
            <div class="rounded-sm bg-canvas p-4">
              <div class="flex items-center justify-between">
                <span class="text-xs font-semibold text-ink-muted">年度单笔最高</span>
                <Flame class="h-4 w-4 text-rose-500" />
              </div>

              <div v-if="report.largest" class="mt-2.5">
                <p class="text-xl font-extrabold text-ink">
                  {{ formatYuan(report.largest.cents) }}
                </p>
                <div class="mt-1.5 flex items-center gap-2 text-xs text-ink">
                  <span class="font-medium">{{ report.largest.categoryName }}</span>
                  <span class="text-ink-muted">·</span>
                  <span class="text-ink-muted">{{ formatMonthDay(report.largest.repaymentDate) }}</span>
                </div>
              </div>
              <p v-else class="mt-2 text-xs text-ink-muted">无单笔记录</p>
            </div>

            <!-- 开销最集中的月份 -->
            <div class="rounded-sm bg-canvas p-4">
              <div class="flex items-center justify-between">
                <span class="text-xs font-semibold text-ink-muted">年度支出最高月份</span>
                <Calendar class="h-4 w-4 text-accent-text" />
              </div>

              <div v-if="report.peakMonth" class="mt-2.5">
                <p class="text-xl font-extrabold text-accent-text">
                  {{ formatYuan(report.peakMonth.totalCents) }}
                </p>
                <p class="mt-1.5 text-xs text-ink-muted">
                  落在 <strong>{{ formatMonthLabel(report.peakMonth.month) }}</strong>
                </p>
              </div>
              <p v-else class="mt-2 text-xs text-ink-muted">数据不足</p>
            </div>
          </div>
        </section>

        <!-- 12 个月月度走势画卷 -->
        <section aria-label="月度起伏轨迹" class="rounded-md bg-surface p-5 sm:p-6">
          <div class="flex items-baseline justify-between mb-4">
            <h2 class="label-cn">12 个月支出走势画卷</h2>
            <span class="text-xs text-ink-muted">月均 {{ formatCompact(monthlyAverageCents) }}</span>
          </div>

          <!-- 12 根柱状图 -->
          <div class="grid grid-cols-12 items-end gap-1.5 pt-6 pb-2 sm:gap-2">
            <div
              v-for="m in report.months"
              :key="m.month"
              class="group flex flex-col items-center"
            >
              <!-- 柱体 -->
              <div class="relative w-full flex flex-col justify-end h-28 rounded-xs bg-sunken/40">
                <div
                  class="w-full rounded-xs transition-all duration-300"
                  :class="m.totalCents === report.peakMonth?.totalCents ? 'bg-accent-text' : 'bg-primary-fill/70 group-hover:bg-primary-fill'"
                  :style="{ height: `${Math.max(4, Math.round((m.totalCents / maxMonthCents) * 100))}%` }"
                />
              </div>

              <!-- 月份标签 -->
              <span class="mt-2 text-[10px] text-ink-muted group-hover:text-ink">
                {{ Number(m.month.slice(5)) }}月
              </span>
            </div>
          </div>
        </section>

        <!-- 年度主力分类排行 -->
        <section aria-label="年度分类画卷" class="rounded-md bg-surface p-5 sm:p-6">
          <div class="flex items-baseline justify-between mb-4">
            <h2 class="label-cn">年度消费构成排行</h2>
            <span class="text-xs text-ink-muted">共 {{ report.categories.length }} 个分类</span>
          </div>

          <div class="space-y-3.5">
            <div
              v-for="(cat, idx) in report.categories"
              :key="cat.categoryId"
              class="space-y-1.5"
            >
              <div class="flex items-center justify-between text-xs">
                <div class="flex items-center gap-2">
                  <span class="w-4 text-center font-bold text-ink-muted">{{ idx + 1 }}</span>
                  <CategoryIcon
                    :name="cat.name"
                    :icon="cat.icon"
                    :color="cat.color"
                    :size="16"
                  />
                  <span class="font-medium text-ink">{{ cat.name }}</span>
                  <span class="text-[10px] text-ink-muted">（{{ cat.count }}笔）</span>
                </div>

                <div class="flex items-baseline gap-2">
                  <span class="font-extrabold text-ink">{{ formatYuan(cat.cents) }}</span>
                  <span class="w-10 text-right text-[11px] text-ink-muted">
                    {{ Math.round(cat.ratio * 100) }}%
                  </span>
                </div>
              </div>

              <!-- 占比进度条 -->
              <div class="h-1.5 w-full overflow-hidden rounded-full bg-sunken">
                <div
                  class="h-full rounded-full transition-all duration-300"
                  :style="{
                    width: `${Math.round(cat.ratio * 100)}%`,
                    backgroundColor: categoryColorVar(dict.colorOf(cat.categoryId, cat.name, cat.color)),
                  }"
                />
              </div>
            </div>
          </div>
        </section>

        <!-- 年度成就印记勋章 -->
        <section
          v-if="achievements.length > 0"
          aria-label="年度成就勋章"
          class="rounded-md bg-surface p-5 sm:p-6"
        >
          <div class="flex items-center gap-2 mb-4">
            <Trophy class="h-4 w-4 text-amber-500" />
            <h2 class="label-cn">年度成就勋章</h2>
          </div>

          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div
              v-for="badge in achievements"
              :key="badge.id"
              class="flex items-start gap-3 rounded-sm bg-canvas p-3.5"
            >
              <div class="rounded-sm p-2" :class="badge.colorClass">
                <component :is="badge.icon" class="h-5 w-5" />
              </div>
              <div>
                <h3 class="text-xs font-bold text-ink">{{ badge.title }}</h3>
                <p class="mt-0.5 text-xs text-ink-muted leading-relaxed">{{ badge.desc }}</p>
              </div>
            </div>
          </div>
        </section>

        <!-- 底部结语与分享祝福 -->
        <footer class="rounded-md bg-sunken/40 p-6 text-center text-xs text-ink-muted">
          <p class="font-medium text-ink">
            “每一笔记录，都是真实生活的倒影。”
          </p>
          <p class="mt-1">
            感谢您在 {{ year }} 年里认真对待每一份开销。愿新的一年，财务丰盈，从容前行。
          </p>
        </footer>
      </main>
    </div>
  </div>
</template>
