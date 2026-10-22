<script setup lang="ts">
/**
 * 原型抽屉（prototype `.sheet` / `.scrim`）。
 * 桌面从右侧滑入（宽 500），移动端从底部上滑（高 93dvh）—— 断点由原型 CSS 控制。
 */
defineProps<{ open: boolean; title?: string }>();
const emit = defineEmits<{ close: [] }>();
</script>

<template>
  <div v-if="open" class="scrim" @click="emit('close')">
    <div class="sheet" role="dialog" aria-modal="true" :aria-label="title" @click.stop>
      <div class="sheet-head">
        <span class="sheet-title">{{ title }}</span>
        <span style="margin-left: auto" />
        <slot name="head-actions" />
        <button type="button" class="icon-btn" aria-label="关闭" @click="emit('close')">✕</button>
      </div>
      <div class="sheet-body">
        <slot />
      </div>
      <div v-if="$slots.foot" class="sheet-foot">
        <slot name="foot" />
      </div>
    </div>
  </div>
</template>
