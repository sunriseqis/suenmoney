<script setup lang="ts">
/** 原型的按钮式分段控件（prototype `Seg` → .seg / .seg-btn / .is-on）。 */
defineProps<{
  options: ReadonlyArray<{ value: string; label: string }>;
  value: string;
  label?: string;
}>();
const emit = defineEmits<{ change: [value: string] }>();
</script>

<template>
  <div class="seg" role="tablist" :aria-label="label">
    <button
      v-for="opt in options"
      :key="opt.value"
      type="button"
      role="tab"
      class="seg-btn"
      :class="{ 'is-on': value === opt.value }"
      :aria-selected="value === opt.value"
      @click="emit('change', opt.value)"
    >
      {{ opt.label }}
    </button>
  </div>
</template>
