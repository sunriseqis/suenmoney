<script setup lang="ts">
/**
 * 主题切换（三档：深色 / 浅色 / 跟随系统）。
 *
 * 默认深色 —— v3 是深色设计，跟随系统会让浅色系统用户看到两套语言。
 * 做成 M3 分段控件：选中项 primary 12% 底 + primary 字，边界用 outline-strong。
 */
import { ref, watch } from 'vue';

import { applyTheme, effectiveTheme, readStoredTheme, type ThemeChoice } from '@/utils/theme';

const OPTIONS: Array<{ value: ThemeChoice; label: string }> = [
  { value: 'dark', label: '深色' },
  { value: 'light', label: '浅色' },
  { value: 'system', label: '跟随' },
];

const current = ref<ThemeChoice>(readStoredTheme() ?? 'dark');
const preview = ref<'dark' | 'light'>(effectiveTheme(current.value));

watch(current, (choice) => {
  applyTheme(choice);
  preview.value = effectiveTheme(choice);
});
</script>

<template>
  <div class="flex items-center justify-between gap-4">
    <div>
      <p class="text-sm font-medium">主题</p>
      <p class="mt-0.5 text-xs text-ink-muted">
        当前生效：{{ preview === 'dark' ? '深色' : '浅色' }}
      </p>
    </div>
    <div
      class="flex gap-1 rounded-full bg-sunken p-1"
      role="radiogroup"
      aria-label="主题"
    >
      <button
        v-for="opt in OPTIONS"
        :key="opt.value"
        type="button"
        role="radio"
        :aria-checked="current === opt.value"
        class="rounded-full px-3.5 py-1.5 text-xs transition-colors"
        :class="current === opt.value
          ? 'bg-primary-container font-medium text-primary'
          : 'text-ink-muted hover:text-ink'"
        @click="current = opt.value"
      >
        {{ opt.label }}
      </button>
    </div>
  </div>
</template>
