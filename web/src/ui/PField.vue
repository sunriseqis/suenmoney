<script setup lang="ts">
/** 原型表单字段（prototype `.field` / `.field-l` / `.input`）。 */
defineProps<{ label?: string; id?: string }>();
</script>

<template>
  <label class="field" :for="id">
    <span v-if="label" class="field-l">{{ label }}</span>
    <slot />
  </label>
</template>
