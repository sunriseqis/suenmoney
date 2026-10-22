<script setup lang="ts">
/** 原型药丸标签（prototype `Tag` → .tag / .tag--dash|accent|warn|danger）。 */
withDefaults(defineProps<{ tone?: '' | 'dash' | 'accent' | 'warn' | 'danger' }>(), { tone: '' });
</script>

<template>
  <span class="tag" :class="tone ? `tag--${tone}` : ''"><slot /></span>
</template>
