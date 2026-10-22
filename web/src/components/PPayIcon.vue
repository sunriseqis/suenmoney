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
  <!--
    品牌矢量（支付宝/微信/云闪付/京东/抖音/银行卡）是 1024×1024 坐标系的路径，
    **必须用 1024 的 viewBox** —— 之前这里写成 0 0 24 24，路径被画在可视区外，
    表现就是「品牌图标全都看不见，只剩 4 个 Lucide 图标」（cash/creditcard/
    bank/wallet 是组件，不受 viewBox 影响）。
  -->
  <svg
    v-if="paths.length"
    :width="size"
    :height="size"
    viewBox="0 0 1024 1024"
    :style="{ color: resolved.color, flex: '0 0 auto' }"
    fill="currentColor"
    aria-hidden="true"
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
