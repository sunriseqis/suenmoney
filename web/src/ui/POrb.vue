<script setup lang="ts">
/** 原型卡头圆形图标（prototype `Orb` → .orb）。深色下自动变切角发光方框。 */
import type { Component } from 'vue';

withDefaults(defineProps<{ icon: Component; tone?: string; ink?: string }>(), {
  tone: 'var(--accent)',
  ink: '#fff',
});
</script>

<template>
  <span class="orb" :style="{ background: tone, color: ink }">
    <component :is="icon" :size="16" :stroke-width="2.2" aria-hidden="true" />
  </span>
</template>
