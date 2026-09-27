<script setup lang="ts">
/**
 * 分类颜色选择器。
 *
 * 8 个色块 + 「自动」，和 IconPicker 同一套交互：
 * 「自动」把 color 清空，回到按分类名推导 —— 没有它，用户选错一次就永远
 * 只能换一个别的颜色掩盖，回不到默认状态。
 *
 * 选中态用**白色描边 + 放大**表达，而不是加内边框：色块本身就是颜色，
 * 往里面再画一个边框会在相近色相上几乎不可见。
 */
import { Check } from '@lucide/vue';

import { CATEGORY_COLORS } from '@/utils/category-colors';

defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [string] }>();
</script>

<template>
  <div class="rounded-md bg-sunken p-3">
    <div class="flex flex-wrap items-center gap-2">
      <!-- 自动 = 清空，回到按分类名推导 -->
      <button
        type="button"
        class="h-8 rounded-sm px-2.5 text-xs font-semibold transition-all duration-200"
        :class="
          modelValue === ''
            ? 'bg-primary-fill text-on-primary'
            : 'bg-canvas text-ink-muted hover:text-ink'
        "
        @click="emit('update:modelValue', '')"
      >
        自动
      </button>

      <span class="mx-1 h-5 w-px bg-line" aria-hidden="true" />

      <button
        v-for="c in CATEGORY_COLORS"
        :key="c.index"
        type="button"
        class="grid h-8 w-8 place-items-center rounded-sm transition-transform duration-200 hover:scale-110"
        :class="modelValue === String(c.index) ? 'ring-2 ring-ink ring-offset-2 ring-offset-sunken' : ''"
        :style="{ background: `var(${c.varName})` }"
        :aria-label="`颜色 ${c.index}`"
        :aria-pressed="modelValue === String(c.index)"
        @click="emit('update:modelValue', String(c.index))"
      >
        <Check
          v-if="modelValue === String(c.index)"
          :size="15"
          :stroke-width="3"
          class="text-white"
          aria-hidden="true"
        />
      </button>
    </div>

    <p class="mt-2 text-xs text-ink-muted">
      不选（自动）时，会按分类名固定分配一个颜色 —— 同一个分类在任何设备上都是同一个颜色。
    </p>
  </div>
</template>
