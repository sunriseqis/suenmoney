<script setup lang="ts">
/** 原型进度条（prototype `Bar` → .bar / .bar-fill）。 */
withDefaults(defineProps<{ pct: number; tone?: string }>(), { tone: 'var(--accent)' });
</script>

<template>
  <div class="bar">
    <span class="bar-fill" :style="{ width: `${Math.max(0, Math.min(100, pct))}%`, background: tone }" />
  </div>
</template>
