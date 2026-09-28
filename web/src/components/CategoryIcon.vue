<script setup lang="ts">
/**
 * 分类图标。
 *
 * 存在的意义是**收敛兜底逻辑**：图标可能来自用户显式选择，也可能因为存量数据
 * 里 icon 是空字符串而需要前端按分类名猜一个。让五个视图各自调
 * `resolveCategoryIcon` 的话，迟早有一处漏掉兜底，于是那一页的分类全是空白。
 *
 * 传 name 而不是 categoryId，是因为它要能用在「聚合结果」上 ——
 * 报表返回的是分类桶，那里只有 name，没有完整的 Category 对象。
 *
 * 反过来，手里**已经有 categoryId** 时（计划、待办这类只带 id 的地方）
 * 直接传 `categoryId` 更省事也更安全：图标取自己的、颜色取一级的规则
 * 由字典 store 的 `visualOf` 统一给出，调用处不必再复述一遍。
 * 两套入参二选一，同时给时以 name/icon/color 为准。
 */
import { computed } from 'vue';

import { useDictionariesStore } from '@/stores/dictionaries';
import { categoryColorVar, resolveCategoryColor } from '@/utils/category-colors';
import { resolveCategoryIcon } from '@/utils/icons';

const props = withDefaults(
  defineProps<{
    /** 分类名，用于 icon/color 为空时兜底推断 */
    name?: string;
    /** 显式存储的图标名；空字符串表示没设过 */
    icon?: string;
    /** 显式存储的色号（'1'–'8'）；空字符串表示没设过，按分类名推导 */
    color?: string;
    /**
     * 参与颜色推导的名字，默认用 `name`。
     *
     * **只有一级分类有颜色** —— 二级分类的图标必须传一级分类的名字与色号，
     * 否则「外卖」「下馆子」会各自按自己的名字推导出五花八门的颜色，
     * 用户给「餐饮」选的紫就完全落不到流水行上。
     * （图标仍由 `name` 决定 —— 二级有自己的图标，只有颜色跟一级走。）
     */
    colorName?: string;
    /** 有分类 id 时优先走它，图标与颜色的解析交给字典 store */
    categoryId?: string | null;
    size?: number;
    strokeWidth?: number;
  }>(),
  { name: '', icon: '', color: '', colorName: '', categoryId: null, size: 18, strokeWidth: 2 },
);

const dict = useDictionariesStore();

const fromId = computed(() => (props.categoryId === null ? null : dict.visualOf(props.categoryId)));

const displayName = computed(() => fromId.value?.name ?? props.name ?? '');
const displayIcon = computed(() => fromId.value?.icon ?? props.icon ?? '');
const displayColor = computed(() => fromId.value?.color ?? props.color ?? '');
const colorName = computed(() => fromId.value?.colorName ?? props.colorName ?? displayName.value);

const component = computed(() =>
  resolveCategoryIcon({ name: displayName.value, icon: displayIcon.value }),
);

/**
 * 图标颜色 = 分类颜色。
 *
 * 必须走内联 style 而不是 Tailwind 类：色号是 1–8 的**运行时**值，
 * Tailwind 只会为它在源码里出现过的字面量生成类，动态值生成不出来。
 * 内联 style 优先级高于 `class="text-ink-muted"`，所以调用处即便还写着
 * 灰色类也会被覆盖 —— 那种类现在是死代码，应从调用处删掉。
 */
const colorStyle = computed(() => ({
  color: categoryColorVar(resolveCategoryColor(colorName.value, displayColor.value)),
}));
</script>

<template>
  <component
    :is="component"
    :size="size"
    :stroke-width="strokeWidth"
    :style="colorStyle"
    class="shrink-0"
    aria-hidden="true"
  />
</template>
