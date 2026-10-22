<script setup lang="ts">
/**
 * 构成卡（四维切换：分类 / 支付 / 记录人 / 节奏）。
 *
 * 同一个「本月花了多少」可以从四个角度看，所以不做四张卡，做一张卡带四个视角：
 *   · 堆叠条给出比例概览
 *   · 下面列表给前 3 名 + 其他
 *   · 颜色按维度循环账本色（同一维度内不重复色）
 *
 * 数据由调用方按维度算好传进来（`dimensions`），这里只负责画 —— 维度聚合
 * 属于报表口径，不该散在展示组件里。
 */
import { computed, ref } from 'vue';

import { ChartPie } from '@lucide/vue';

import { PEmpty, PSeg } from '@/ui';
import { formatYuan } from '@/utils/money';

export interface CompositionBucket {
  name: string;
  cents: number;
  /** 颜色变量名或色值，由调用方决定（分类色 / 支付色 / 成员色 / 节奏色） */
  color: string;
}

const props = defineProps<{
  totalCents: number;
  dimensions: Array<{ key: string; label: string; buckets: CompositionBucket[] }>;
  defaultKey?: string;
}>();

const active = ref(props.defaultKey ?? props.dimensions[0]?.key ?? 'cat');

const options = computed(() => props.dimensions.map((d) => ({ value: d.key, label: d.label })));

const buckets = computed(() => {
  const dim = props.dimensions.find((d) => d.key === active.value) ?? props.dimensions[0];
  return (dim?.buckets ?? []).filter((b) => b.cents > 0).slice().sort((a, b) => b.cents - a.cents);
});

const top3 = computed(() => buckets.value.slice(0, 3));
const rest = computed(() => buckets.value.slice(3));

function pct(cents: number): number {
  return props.totalCents > 0 ? Math.round((cents / props.totalCents) * 100) : 0;
}
</script>

<template>
  <div class="composition">
    <div class="card-h">
      <span class="card-t">构成</span>
      <span class="card-cap">{{ formatYuan(totalCents) }}</span>
    </div>

    <PSeg :options="options" :value="active" label="构成维度" @change="(v) => (active = v)" />

    <PEmpty v-if="buckets.length === 0" :icon="ChartPie">这个期间没有记录</PEmpty>

    <template v-else>
      <div class="stack-bar" role="img" aria-label="构成堆叠条" style="margin-top: 12px">
        <span
          v-for="b in buckets"
          :key="b.name"
          :style="{ flex: b.cents, background: b.color }"
        />
      </div>

      <div class="compose-legend" style="margin-top: 10px">
        <span v-for="b in top3" :key="b.name" class="cl-item">
          <i class="cl-dot" :style="{ background: b.color }" />
          {{ b.name }}
          <b class="mono" style="font-weight: 600">{{ formatYuan(b.cents) }} · {{ pct(b.cents) }}%</b>
        </span>
        <span v-if="rest.length > 0" class="cl-item">
          <i class="cl-dot" style="background: var(--ink-3)" />
          其他 {{ rest.length }} 项
          <b class="mono" style="font-weight: 600">
            {{ formatYuan(rest.reduce((a, b) => a + b.cents, 0)) }}
          </b>
        </span>
      </div>
    </template>
  </div>
</template>

<style scoped>
.composition {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
</style>
