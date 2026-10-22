<script setup lang="ts">
/**
 * 分类徽位（原型 `CatIcon`）：12% 分类色底 + 分类色图标 + 同色描边。
 *
 * 颜色规则收在字典 store 里（二级分类继承一级的颜色），这里只负责画。
 * 颜色必须走内联 style —— 色号是运行时值，Tailwind 生成不出动态类。
 */
import { computed } from 'vue';

import { useDictionariesStore } from '@/stores/dictionaries';
import { categoryColorVar } from '@/utils/category-colors';
import { resolveCategoryIcon } from '@/utils/icons';

const props = withDefaults(
  defineProps<{
    /** 分类名（图标为空时按名字兜底推断） */
    name?: string;
    /** 显式图标名，空串表示没设过 */
    icon?: string;
    /** 显式色号，空串表示按名字推导 */
    color?: string;
    /** 参与颜色推导的名字（二级分类要传一级的名字） */
    colorName?: string;
    /** 有 id 时优先由字典 store 解析图标与颜色 */
    categoryId?: string | null;
    size?: number;
  }>(),
  { name: '', icon: '', color: '', colorName: '', categoryId: null, size: 30 },
);

const dict = useDictionariesStore();
const fromId = computed(() => (props.categoryId === null ? null : dict.visualOf(props.categoryId)));
const displayName = computed(() => fromId.value?.name ?? props.name ?? '');
const displayIcon = computed(() => fromId.value?.icon ?? props.icon ?? '');
const displayColor = computed(() => fromId.value?.color ?? props.color ?? '');
const colorName = computed(() => fromId.value?.colorName ?? props.colorName ?? displayName.value);

const comp = computed(() => resolveCategoryIcon({ name: displayName.value, icon: displayIcon.value }));
const colorIndex = computed(() =>
  fromId.value ? fromId.value.colorIndex : dict.colorOf(props.categoryId, colorName.value, displayColor.value),
);

const style = computed(() => {
  const c = categoryColorVar(colorIndex.value);
  return { width: `${props.size}px`, height: `${props.size}px`, color: c, background: `color-mix(in srgb, ${c} 12%, transparent)`, borderColor: `color-mix(in srgb, ${c} 45%, transparent)` };
});
</script>

<template>
  <span class="cat-ic" :style="style">
    <component :is="comp" :size="Math.round(size * 0.56)" :stroke-width="2.2" aria-hidden="true" />
  </span>
</template>
