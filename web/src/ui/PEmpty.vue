<script setup lang="ts">
/** 原型空态（prototype `Empty` → .empty）。仅用于「区块内无内容」，不用于整页。 */
import type { Component } from 'vue';

defineProps<{ icon?: Component }>();
</script>

<template>
  <div class="empty">
    <component :is="icon" v-if="icon" :size="18" aria-hidden="true" />
    <slot />
  </div>
</template>
