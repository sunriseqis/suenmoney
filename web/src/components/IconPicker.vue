<script setup lang="ts">
/**
 * 图标选择器。
 *
 * 平铺 80 个图标是选不动的，所以按用途分组（餐饮 / 交通 / 居住 …）——
 * 分组标签本身就是检索线索，比图标名字好用的多。
 *
 * 选中态用**主色填充**表达，不用边框或阴影：Flat 没有阴影可用，
 * 而填充在密集的小方块里是最醒目的区分方式。
 */
import { ICON_GROUPS, ICON_REGISTRY, type IconName } from '@/utils/icons';

defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [string] }>();

function pick(name: IconName): void {
  emit('update:modelValue', name);
}
</script>

<template>
  <div class="rounded-md bg-sunken p-3">
    <!--
      「自动」= 把 icon 清空，回到按分类名推断。
      没有这个选项的话，用户一旦手滑选错就只能挑一个别的图标来掩盖，永远回不到默认状态。

      它放在**滚动区外面**：放在网格后面的话会被 288px 的滚动高度截掉，
      而它恰恰是「改错了想撤销」时第一个要找的东西 —— 藏起来等于没有。
    -->
    <button
      type="button"
      class="w-full rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
      :class="
        modelValue === ''
          ? 'bg-primary-fill text-on-primary'
          : 'bg-canvas text-ink-muted hover:text-ink'
      "
      :aria-pressed="modelValue === ''"
      @click="emit('update:modelValue', '')"
    >
      自动（按分类名推断）
    </button>

    <div class="mt-2 max-h-60 overflow-y-auto">
      <div v-for="group in ICON_GROUPS" :key="group.label" class="mb-3 last:mb-0">
        <p class="label-cn">{{ group.label }}</p>

        <div class="mt-1.5 flex flex-wrap gap-1">
          <button
            v-for="name in group.icons"
            :key="name"
            type="button"
            class="grid h-9 w-9 place-items-center rounded-sm transition-colors duration-200"
            :class="
              modelValue === name
                ? 'bg-primary-fill text-on-primary'
                : 'bg-canvas text-ink-muted hover:text-ink'
            "
            :aria-pressed="modelValue === name"
            :aria-label="`图标 ${name}`"
            @click="pick(name)"
          >
            <component :is="ICON_REGISTRY[name]" :size="18" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
