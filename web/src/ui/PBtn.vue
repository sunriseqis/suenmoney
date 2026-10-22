<script setup lang="ts">
/**
 * 原型按钮（对应原型 ui.jsx 的 `Btn`）。
 *
 * 类名、变体、尺寸全部照抄原型 app.css：
 *   .btn / .btn--primary / .btn--pink / .btn--ghost / .btn--danger / .btn--sm / .btn--icon
 * 深浅两套外观由 CSS 里的 `.app[data-theme=...] .btn` 接管，组件本身不判断主题。
 */
import type { Component } from 'vue';

withDefaults(
  defineProps<{
    variant?: '' | 'primary' | 'pink' | 'ghost' | 'danger';
    size?: '' | 'sm' | 'icon';
    icon?: Component;
    disabled?: boolean;
    type?: 'button' | 'submit';
  }>(),
  { variant: '', size: '', icon: undefined, disabled: false, type: 'button' },
);
</script>

<template>
  <button
    :type="type"
    :disabled="disabled"
    class="btn"
    :class="[variant ? `btn--${variant}` : '', size ? `btn--${size}` : '']"
  >
    <component :is="icon" v-if="icon" :size="size === 'sm' ? 12 : 14" :stroke-width="2.2" aria-hidden="true" />
    <slot />
  </button>
</template>
