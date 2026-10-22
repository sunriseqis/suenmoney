<script setup lang="ts">
/** 原型指标（prototype `Stat` → .stat / .stat-v / .stat-l / .stat-sub）。 */
defineProps<{ label: string; value: string; sub?: string }>();
</script>

<template>
  <div class="stat">
    <span class="stat-v">{{ value }}</span>
    <span class="stat-l">{{ label }}</span>
    <span v-if="sub" class="stat-sub">{{ sub }}</span>
  </div>
</template>
