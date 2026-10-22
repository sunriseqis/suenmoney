<script setup lang="ts">
/** 原型圆形图标按钮（prototype `IconBtn` → .icon-btn）。 */
import type { Component } from 'vue';

defineProps<{ icon: Component; label: string; disabled?: boolean }>();
</script>

<template>
  <button type="button" class="icon-btn" :aria-label="label" :title="label" :disabled="disabled">
    <component :is="icon" :size="17" :stroke-width="2.2" aria-hidden="true" />
  </button>
</template>
