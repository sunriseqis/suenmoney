<script setup lang="ts">
/**
 * 原型卡片（prototype `Card` → .card）。
 * `pop` 加深边框与硬阴影，`flat` 去阴影，`tint` 用次要底色。
 */
withDefaults(defineProps<{ pop?: boolean; flat?: boolean; tint?: boolean }>(), {
  pop: false,
  flat: false,
  tint: false,
});
</script>

<template>
  <div class="card" :class="{ 'card--pop': pop, 'card--flat': flat, 'card--tint': tint }">
    <slot />
  </div>
</template>
