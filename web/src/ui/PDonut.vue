<script setup lang="ts">
/**
 * 环形图（原型 ui.jsx `Donut`）—— 用 stroke-dasharray 画同心圆环，
 * 每段之间留 2.5 的缝，视觉上是一段段独立的色块而不是一张饼。
 */
import { computed } from 'vue';

const props = withDefaults(
  defineProps<{
    data: Array<{ name: string; value: number; color: string }>;
    centerLabel?: string;
    centerValue?: string;
    size?: number;
  }>(),
  { centerLabel: '合计', centerValue: '', size: 176 },
);

const r = computed(() => props.size / 2 - 12);
const circumference = computed(() => 2 * Math.PI * r.value);
const sum = computed(() => props.data.reduce((a, d) => a + d.value, 0) || 1);

const segments = computed(() => {
  let acc = 0;
  return props.data.map((d) => {
    const len = (d.value / sum.value) * circumference.value;
    const seg = { ...d, dash: `${Math.max(0, len - 2.5)} ${circumference.value - Math.max(0, len - 2.5)}`, offset: -acc };
    acc += len;
    return seg;
  });
});
</script>

<template>
  <div class="donut" :style="{ width: `${size}px`, height: `${size}px` }">
    <svg width="100%" height="100%" :viewBox="`0 0 ${size} ${size}`" aria-hidden="true">
      <circle :cx="size / 2" :cy="size / 2" :r="r" fill="none" stroke="var(--surface-3)" stroke-width="16" />
      <circle
        v-for="(s, i) in segments"
        :key="i"
        :cx="size / 2"
        :cy="size / 2"
        :r="r"
        fill="none"
        :stroke="s.color"
        stroke-width="16"
        :stroke-dasharray="s.dash"
        :stroke-dashoffset="s.offset"
        :transform="`rotate(-90 ${size / 2} ${size / 2})`"
      />
    </svg>
    <div class="donut-center">
      <span class="donut-c-l">{{ centerLabel }}</span>
      <span class="donut-c-v">{{ centerValue }}</span>
    </div>
  </div>
</template>
