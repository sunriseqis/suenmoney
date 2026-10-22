<script setup lang="ts">
/**
 * 年度报告（原型 `views/Report.jsx` 的 annual 部分）。
 *
 * 只陈述报表里已有的事实：全年合计、与去年对比、12 个月走势、之最。
 * 不做任何预测或评分 —— 那些需要口径假设，一旦算错比不给更糟。
 */
import { BarChart3, CalendarDays, ChevronLeft, ChevronRight } from '@lucide/vue';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { reports, type YearlyReport } from '@/api';
import { PBtn, PCard, PEmpty, PIconBtn, POrb, PStat } from '@/ui';
import { formatMonthLabel } from '@/utils/dates';
import { formatYuan } from '@/utils/money';

const route = useRoute();
const router = useRouter();

const year = ref(String(route.query['year'] ?? new Date().getFullYear()));
const report = ref<YearlyReport | null>(null);
const loading = ref(true);

const total = computed(() => report.value?.totalCents ?? 0);
const months = computed(() => report.value?.months ?? []);
const monthsMax = computed(() => Math.max(1, ...months.value.map((m) => m.totalCents)));

const yearAgoCents = computed(() => report.value?.yearAgo.totalCents ?? 0);
const yearDelta = computed<number | null>(() => report.value?.yearAgo.change.ratio ?? null);

const peakMonth = computed(() => report.value?.peakMonth ?? null);
const largest = computed(() => report.value?.largest ?? null);

/** 支出最高的分类（全年） */
const topCategory = computed(() => {
  const rows = (report.value?.categories ?? []).filter((c) => c.cents > 0).slice().sort((a, b) => b.cents - a.cents);
  return rows[0] ?? null;
});

/** 有记录的空月数（用于「哪几个月最安静」这类事实陈述） */
const quietMonths = computed(() => months.value.filter((m) => m.totalCents === 0).length);

function shiftYear(delta: number): void {
  year.value = String(Number(year.value) + delta);
  void router.replace({ query: { year: year.value } });
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    report.value = (await reports.yearly(year.value)).report;
  } catch {
    report.value = null;
  } finally {
    loading.value = false;
  }
}

watch(year, () => void load());
onMounted(() => void load());
</script>

<template>
  <div class="stack">
    <!-- 顶栏：年份切换 -->
    <PCard>
      <div class="split">
        <PIconBtn :icon="ChevronLeft" label="上一年" @click="shiftYear(-1)" />
        <span class="mono" style="font-size: 15px; font-weight: 700">{{ year }}</span>
        <PIconBtn :icon="ChevronRight" label="下一年" @click="shiftYear(1)" />
        <PBtn
          variant="ghost"
          size="sm"
          style="margin-left: auto"
          @click="router.push({ name: 'report' })"
        >
          返回报表
        </PBtn>
      </div>
    </PCard>

    <!-- 年度全貌 -->
    <PCard class="card--pop">
      <div class="card-h">
        <POrb :icon="CalendarDays" tone="var(--accent)" ink="var(--accent-ink)" />
        <span class="card-t">{{ year }} 年度全貌</span>
        <span class="card-cap">{{ months.length }} 个月 · {{ report?.count ?? 0 }} 笔</span>
      </div>
      <div class="hero-amt"><span class="cur">¥</span>{{ formatYuan(total).replace('¥', '') }}</div>
      <div class="hero-delta">
        <span v-if="yearDelta !== null" class="delta-pill" :class="yearDelta > 0 ? 'neg' : 'pos'">
          {{ (yearDelta * 100).toFixed(1) }}%
        </span>
        <span>去年 {{ formatYuan(yearAgoCents) }}</span>
      </div>
      <div class="hero-metrics" style="margin-top: 14px">
        <PStat label="月均" :value="formatYuan(Math.round(total / 12))" />
        <PStat label="单笔均值" :value="formatYuan(report && report.count > 0 ? Math.round(total / report.count) : 0)" />
        <PStat label="空月" :value="`${quietMonths} 个月`" />
      </div>
    </PCard>

    <!-- 12 个月走势 -->
    <PCard>
      <div class="card-h">
        <span class="card-t">12 个月走势</span>
        <span class="card-cap">按还款日归属</span>
      </div>
      <PEmpty v-if="months.length === 0" :icon="CalendarDays">这一年还没有记录</PEmpty>
      <div v-else style="display: flex; gap: 4px; align-items: flex-end; height: 140px">
        <button
          v-for="m in months"
          :key="m.month"
          type="button"
          :title="`${formatMonthLabel(m.month)} ${formatYuan(m.totalCents)} · ${m.count} 笔`"
          style="flex: 1 1 0; display: flex; flex-direction: column; justify-content: flex-end; height: 100%; gap: 4px; cursor: pointer"
          @click="router.push({ name: 'report', query: { month: m.month } })"
        >
          <span
            :style="{
              height: `${Math.max(4, (m.totalCents / monthsMax) * 100)}%`,
              background: m.totalCents > 0 ? 'color-mix(in srgb, var(--accent) 75%, var(--surface))' : 'var(--surface-3)',
              borderRadius: '3px 3px 0 0',
              display: 'block',
            }"
          />
          <span class="tiny muted" style="font-family: var(--font-mono); font-size: 9.5px">
            {{ Number(m.month.slice(5, 7)) }}
          </span>
        </button>
      </div>
    </PCard>

    <!-- 年度之最 -->
    <div class="g2">
      <PCard>
        <div class="card-h">
          <span class="card-t">最高支出月</span>
        </div>
        <PEmpty v-if="!peakMonth" :icon="BarChart3">没有数据</PEmpty>
        <div v-else>
          <div style="font-family: var(--font-display); font-size: 26px; font-weight: 800">
            {{ formatMonthLabel(peakMonth.month) }}
          </div>
          <div class="tiny muted" style="margin-top: 4px">{{ formatYuan(peakMonth.totalCents) }}</div>
        </div>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">单笔最贵</span>
        </div>
        <PEmpty v-if="!largest" :icon="BarChart3">没有数据</PEmpty>
        <div v-else>
          <div style="font-family: var(--font-display); font-size: 26px; font-weight: 800">
            {{ formatYuan(largest.cents) }}
          </div>
          <div class="tiny muted" style="margin-top: 4px">{{ largest.categoryName }} · {{ largest.repaymentDate }}</div>
        </div>
      </PCard>
    </div>

    <!-- 全年最大分类 -->
    <PCard v-if="topCategory">
      <div class="card-h">
        <span class="card-t">支出最多的分类</span>
        <span class="card-cap">全年</span>
      </div>
      <div class="split" style="align-items: baseline">
        <span style="font-size: 15px; font-weight: 700">{{ topCategory.name }}</span>
        <span class="mono" style="margin-left: auto">{{ formatYuan(topCategory.cents) }}</span>
        <span class="mono tiny muted">{{ total > 0 ? Math.round((topCategory.cents / total) * 100) : 0 }}%</span>
      </div>
    </PCard>

    <p v-if="loading" class="tiny muted" style="text-align: center">加载中…</p>
  </div>
</template>
