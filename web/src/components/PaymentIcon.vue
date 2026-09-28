<script setup lang="ts">
import { computed } from 'vue';

import {
  LUCIDE_ICONS,
  resolvePaymentIcon,
  SVG_PATHS,
} from '@/utils/payment-icons';

const props = withDefaults(
  defineProps<{
    name?: string;
    icon?: string;
    size?: number;
    colored?: boolean;
  }>(),
  {
    name: '',
    icon: '',
    size: 16,
    colored: true,
  },
);

const resolved = computed(() => resolvePaymentIcon(props.name, props.icon));
const isSvgPath = computed(() => Boolean(SVG_PATHS[resolved.value.id]));
const svgPaths = computed(() => SVG_PATHS[resolved.value.id] ?? []);
const lucideComponent = computed(() => LUCIDE_ICONS[resolved.value.id] ?? null);

const style = computed(() => ({
  color: props.colored ? resolved.value.color : 'currentColor',
}));
</script>

<template>
  <svg
    v-if="isSvgPath"
    viewBox="0 0 1024 1024"
    :width="size"
    :height="size"
    :style="style"
    fill="currentColor"
    class="shrink-0 inline-block align-middle"
    aria-hidden="true"
  >
    <path v-for="(p, idx) in svgPaths" :key="idx" :d="p" />
  </svg>
  <component
    :is="lucideComponent"
    v-else-if="lucideComponent"
    :size="size"
    :style="style"
    class="shrink-0 inline-block align-middle"
    aria-hidden="true"
  />
  <svg
    v-else
    viewBox="0 0 1024 1024"
    :width="size"
    :height="size"
    :style="style"
    fill="currentColor"
    class="shrink-0 inline-block align-middle"
    aria-hidden="true"
    <path v-if="SVG_PATHS.card?.[0]" :d="SVG_PATHS.card[0]" />
  </svg>
</template>
