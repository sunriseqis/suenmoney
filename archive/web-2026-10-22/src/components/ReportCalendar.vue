<script setup lang="ts">
/**
 * 流水页日历组件（A26 · A28 · §6.3.3）。
 *
 * 铁律：
 *   1. 格子只给量（当月合计 / 全年合计），不塞环图、排名等。
 *   2. 花销深浅四档（只用强调色透明度）：最多 / 稍多 / 均值上下 / 最少；0 为单独无填充档。
 *   3. 点一下选中（下方卡切到该期间），再点同格或点卡上下钻。
 */
import { computed } from 'vue';

import { formatCompact } from '@/utils/money';

export interface CalendarCell {
  key: string;
  label: string;
  amountCents: number;
  count: number;
}

const props = defineProps<{
  mode: 'year' | 'all';
  items: CalendarCell[];
  selectedKey: string | null;
}>();

const emit = defineEmits<{
  (e: 'select', key: string): void;
  (e: 'drill', key: string): void;
}>();

const totalAmountCents = computed(() =>
  props.items.reduce((acc, it) => acc + it.amountCents, 0),
);

const totalCount = computed(() =>
  props.items.reduce((acc, it) => acc + it.count, 0),
);

/** 计算非零均值（m = 本档均值） */
const meanCents = computed(() => {
  const nonZeros = props.items.filter((item) => item.amountCents > 0);
  if (nonZeros.length === 0) return 0;
  return totalAmountCents.value / nonZeros.length;
});

/**
 * 四档深浅（§6.3.3 花销深浅）：
 *   4: 最多 · 最深 (>= 1.5m)
 *   3: 稍多 · 略深 (1.15m ~ 1.5m)
 *   2: 平均数上下 · 普通 (0.85m ~ 1.15m)
 *   1: 最少 · 最浅 (< 0.85m 且 > 0)
 *   0: 一笔都没有 (0)
 */
function cellShadeStyle(cents: number): Record<string, string> {
  if (cents === 0) {
    return {
      backgroundColor: 'transparent',
      borderColor: 'var(--border)',
    };
  }

  const m = meanCents.value;
  if (m === 0) {
    return { backgroundColor: 'rgba(59, 130, 246, 0.12)' };
  }

  const ratio = cents / m;
  let alpha = 0.12;

  if (ratio >= 1.5) {
    alpha = 0.42;
  } else if (ratio >= 1.15) {
    alpha = 0.24;
  } else if (ratio >= 0.85) {
    alpha = 0.12;
  } else {
    alpha = 0.05;
  }

  return {
    backgroundColor: `rgba(59, 130, 246, ${alpha})`,
    borderColor: `rgba(59, 130, 246, ${Math.min(0.8, alpha + 0.15)})`,
  };
}

function handleCellClick(key: string): void {
  if (props.selectedKey === key) {
    emit('drill', key);
  } else {
    emit('select', key);
  }
}
</script>

<template>
  <div class="rounded-md border border-line/60 bg-subtle p-3 sm:p-4">
    <!-- 汇总行：共 N 笔 · ¥X，均值 ¥Y（§6.3.3 图例删掉，保留均值作为轴） -->
    <div class="mb-3 flex flex-wrap items-center justify-between gap-2 text-xs text-ink-muted">
      <span>{{ mode === 'year' ? '年度 12 个月日历' : '全部年份日历' }}</span>
      <div class="flex items-center gap-3">
        <span>共 {{ totalCount }} 笔 · {{ formatCompact(totalAmountCents) }}</span>
        <span v-if="meanCents > 0" class="font-semibold text-ink">
          {{ mode === 'year' ? '月均' : '年均' }} {{ formatCompact(meanCents) }}
        </span>
      </div>
    </div>

    <!-- 年档 12 格：移动端 4 列 x 3 行，桌面 6 列或 12 列 -->
    <div
      v-if="mode === 'year'"
      class="grid grid-cols-3 gap-2 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-12"
    >
      <button
        v-for="cell in items"
        :key="cell.key"
        type="button"
        class="group relative flex flex-col items-center justify-center rounded-sm border p-2 text-center transition-all duration-150 hover:brightness-95 active:scale-95"
        :class="[
          selectedKey === cell.key
            ? 'ring-2 ring-primary ring-offset-1 ring-offset-canvas shadow-xs font-bold'
            : 'border-line/60',
        ]"
        :style="cellShadeStyle(cell.amountCents)"
        :aria-pressed="selectedKey === cell.key"
        @click="handleCellClick(cell.key)"
      >
        <span class="text-xs font-medium text-ink">{{ cell.label }}</span>
        <span class="mt-1 block text-[11px] tabular-nums" :class="cell.amountCents === 0 ? 'text-ink-muted' : 'text-ink font-semibold'">
          {{ cell.amountCents === 0 ? '—' : formatCompact(cell.amountCents) }}
        </span>
      </button>
    </div>

    <!-- 全部档（汇总）：各年份网格 -->
    <div
      v-else
      class="grid grid-cols-2 gap-2.5 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6"
    >
      <button
        v-for="cell in items"
        :key="cell.key"
        type="button"
        class="group relative flex flex-col items-center justify-center rounded-sm border p-3 text-center transition-all duration-150 hover:brightness-95 active:scale-95"
        :class="[
          selectedKey === cell.key
            ? 'ring-2 ring-primary ring-offset-1 ring-offset-canvas shadow-xs font-bold'
            : 'border-line/60',
        ]"
        :style="cellShadeStyle(cell.amountCents)"
        :aria-pressed="selectedKey === cell.key"
        @click="handleCellClick(cell.key)"
      >
        <span class="text-sm font-semibold text-ink">{{ cell.label }}</span>
        <span class="mt-1 block text-xs tabular-nums" :class="cell.amountCents === 0 ? 'text-ink-muted' : 'text-ink font-semibold'">
          {{ cell.amountCents === 0 ? '—' : formatCompact(cell.amountCents) }}
        </span>
        <span v-if="cell.count > 0" class="mt-0.5 text-[10px] text-ink-muted">
          {{ cell.count }} 笔
        </span>
      </button>
    </div>
  </div>
</template>
