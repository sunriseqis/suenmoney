<script setup lang="ts">
/**
 * 分类颜色选择（16 槽账本色）。
 *
 * 色号存的是 **1–16 的索引**，不是色值 —— 换主题时账本色整体重排，
 * 存死色值会让「同一分类在深浅主题下颜色对不上」。
 */
import { CATEGORY_COLORS } from '@/utils/category-colors';

defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();
</script>

<template>
  <div class="color-picker">
    <button
      type="button"
      class="cp-auto"
      :class="{ 'is-on': modelValue === '' }"
      title="自动（按分类名推导）"
      @click="emit('update:modelValue', '')"
    >
      自动
    </button>
    <button
      v-for="c in CATEGORY_COLORS"
      :key="c.index"
      type="button"
      class="cp-cell"
      :class="{ 'is-on': modelValue === String(c.index) }"
      :style="{ background: `var(${c.varName})` }"
      :title="`色号 ${c.index}`"
      :aria-label="`色号 ${c.index}`"
      @click="emit('update:modelValue', String(c.index))"
    />
  </div>
</template>

<style scoped>
.color-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  align-items: center;
}
.cp-cell {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  border: 2px solid transparent;
  transition: transform 0.16s;
}
.cp-cell:hover {
  transform: scale(1.12);
}
.cp-cell.is-on {
  border-color: var(--ink);
}
.cp-auto {
  padding: 4px 10px;
  border: 1px solid var(--line);
  border-radius: 999px;
  font-size: 11px;
  color: var(--ink-2);
  font-family: var(--font-mono);
}
.cp-auto.is-on {
  border-color: var(--accent);
  color: var(--accent);
}
</style>
