<script setup lang="ts">
/** 原型开关（prototype `Switch` → .switch / .is-on）。 */
defineProps<{ checked: boolean; label?: string }>();
const emit = defineEmits<{ change: [value: boolean] }>();
</script>

<template>
  <button
    type="button"
    role="switch"
    class="switch"
    :class="{ 'is-on': checked }"
    :aria-checked="checked"
    :aria-label="label"
    @click="emit('change', !checked)"
  />
</template>
