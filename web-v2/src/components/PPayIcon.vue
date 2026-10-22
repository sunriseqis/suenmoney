<script setup lang="ts">
/**
 * 支付方式图标：优先用内置矢量路径（支付宝/微信/银行卡等品牌图形），
 * 没有对应品牌图时退回 Lucide 图标。
 */
import { computed } from 'vue';

import { LUCIDE_ICONS, resolvePaymentIcon, SVG_PATHS } from '@/utils/payment-icons';

const props = withDefaults(defineProps<{ name?: string; icon?: string; size?: number }>(), {
  name: '',
  icon: '',
  size: 16,
});

const resolved = computed(() => resolvePaymentIcon(props.name, props.icon));
const paths = computed(() => SVG_PATHS[resolved.value.id] ?? []);
const lucide = computed(() => LUCIDE_ICONS[resolved.value.id] ?? null);
</script>

<template>
  <svg
    v-if="paths.length"
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    :fill="resolved.color"
    aria-hidden="true"
    style="flex: 0 0 auto"
  >
    <path v-for="(d, i) in paths" :key="i" :d="d" />
  </svg>
  <component
    :is="lucide"
    v-else-if="lucide"
    :size="size"
    :stroke-width="2.2"
    :style="{ color: resolved.color }"
    aria-hidden="true"
  />
</template>
