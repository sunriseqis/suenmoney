<script setup lang="ts">
/**
 * 选项胶囊。
 *
 * 分类、支付方式、日期快选、报表口径切换都用它 —— 这几处的交互语义完全相同
 * （从一组里单选一个），如果各自内联写一遍样式，「选中态长什么样」这件事
 * 就会在不同页面上逐渐漂移。
 *
 * 用 `active` 而不是 `selected`：它同时被用作「单选选中」和「分段控件当前项」。
 */
withDefaults(
  defineProps<{
    active?: boolean;
    disabled?: boolean;
  }>(),
  { active: false, disabled: false },
);
</script>

<template>
  <button
    type="button"
    :disabled="disabled"
    :aria-pressed="active"
    class="inline-flex shrink-0 items-center gap-1 rounded-sm px-3 py-2 text-sm font-medium transition-colors duration-200 disabled:opacity-40"
    :class="
      active
        ? 'bg-primary-fill text-on-primary'
        : 'bg-surface text-ink-muted hover:text-ink'
    "
  >
    <slot />
  </button>
</template>
