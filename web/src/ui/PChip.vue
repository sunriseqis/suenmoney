<script setup lang="ts">
/** 原型筛选药丸（prototype `Chip` → .chip / .is-on / .chip-dot）。 */
defineProps<{ active?: boolean; dot?: string }>();
const emit = defineEmits<{ click: [] }>();
</script>

<template>
  <button type="button" class="chip" :class="{ 'is-on': active }" :aria-pressed="!!active" @click="emit('click')">
    <i v-if="dot" class="chip-dot" :style="{ background: dot }" />
    <slot />
  </button>
</template>
