<script setup lang="ts">
/** 原型输入框（prototype `.input`，深色下自动变等宽终端风）。 */
withDefaults(
  defineProps<{
    modelValue: string;
    placeholder?: string;
    type?: string;
    id?: string;
    autocomplete?: string;
  }>(),
  { placeholder: '', type: 'text', id: undefined, autocomplete: undefined },
);
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();
</script>

<template>
  <input
    :id="id"
    class="input"
    :type="type"
    :value="modelValue"
    :placeholder="placeholder"
    :autocomplete="autocomplete"
    @input="emit('update:modelValue', ($event.target as HTMLInputElement).value)"
  />
</template>
