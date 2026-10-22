<script setup lang="ts">
/**
 * 品牌标记（计算器 mark）。
 *
 * 只出图，不带字标 —— 字标由外层按原型排版（侧边栏 `.brand-name` + `.brand-sub`），
 * 免得同一个词在两处用不同字号各排一遍。
 *
 * 深浅两版是不同的**几何**而非换色：cyber 版有霓虹四色外环 + 辉光，
 * candy 版是白机身深描边 + 硬阴影。所以按主题换文件，不做 CSS filter。
 */
import { computed } from 'vue';

import { useTheme } from '@/composables/useTheme';

withDefaults(defineProps<{ size?: number }>(), { size: 46 });

const theme = useTheme();
const src = computed(() => (theme.proto.value === 'cyber' ? '/logo.svg' : '/mark-light.svg'));
</script>

<template>
  <img :src="src" alt="SuenMoney" :width="size" :height="size" class="brand-mark" />
</template>

<style scoped>
.brand-mark {
  display: block;
  flex: 0 0 auto;
  border-radius: 12px;
}
</style>
