<script setup lang="ts">
/**
 * 分类选择弹层（Sheet / Modal）。
 *
 * 采用清晰的双列导航（左侧一级大类垂直导航，右侧二级分类网格）：
 * - 彻底消灭移动端的横向滑动条（Horizontal Scrollbars）；
 * - 避免在首屏堆叠数十个 Chips 导致的信息过载；
 * - 点选任意二级分类后即刻选中并自动关闭弹层。
 */
import { computed, ref, watch } from 'vue';

import type { Category } from '@/api/types';
import CategoryIcon from '@/components/CategoryIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';

const props = defineProps<{
  open: boolean;
  activeCategoryId: string | null;
}>();

const emit = defineEmits<{
  close: [];
  select: [categoryId: string];
}>();

const dict = useDictionariesStore();

const selectedRootId = ref<string | null>(null);

// 初始化选中的一级分类
watch(
  () => props.open,
  (isOpen) => {
    if (!isOpen) return;

    if (props.activeCategoryId) {
      const current = dict.findCategory(props.activeCategoryId);
      if (current) {
        selectedRootId.value = current.parentId ?? current.id;
        return;
      }
    }
    // 默认选中第一个可用的一级分类
    selectedRootId.value = dict.rootCategories[0]?.id ?? null;
  },
  { immediate: true },
);

const activeRoot = computed<Category | null>(() => {
  return dict.rootCategories.find((c) => c.id === selectedRootId.value) ?? dict.rootCategories[0] ?? null;
});

const subCategories = computed<Category[]>(() => {
  if (!activeRoot.value) return [];
  return dict.selectableChildren(activeRoot.value);
});

function handleSelect(id: string): void {
  emit('select', id);
  emit('close');
}

function close(): void {
  emit('close');
}
</script>

<template>
  <div v-if="open" class="fixed inset-0 z-[calc(var(--z-sheet)+10)] flex flex-col justify-end lg:justify-center lg:items-center">
    <!-- 遮罩背景 -->
    <button
      type="button"
      class="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)] transition-opacity"
      aria-label="关闭分类选择"
      @click="close"
    />

    <!-- 弹层主体 -->
    <div
      class="relative flex h-[75vh] max-h-[620px] w-full flex-col rounded-t-xl bg-surface shadow-2xl transition-transform lg:h-[580px] lg:w-[540px] lg:rounded-xl"
      role="dialog"
      aria-modal="true"
      @keydown.esc="close"
    >
      <!-- 弹层顶栏 -->
      <header class="flex items-center justify-between border-b border-line/60 px-4 py-3 sm:px-5">
        <div class="flex items-center gap-2">
          <span class="text-sm font-bold text-ink">选择分类</span>
          <span v-if="activeRoot" class="text-xs text-ink-muted">· {{ activeRoot.name }}</span>
        </div>
        <button
          type="button"
          class="relative grid h-10 w-10 place-items-center rounded-sm text-sm font-bold text-ink-muted hover:bg-sunken hover:text-ink after:absolute after:-inset-0.5 after:rounded-sm after:content-['']"
          aria-label="关闭"
          @click="close"
        >
          ✕
        </button>
      </header>

      <!-- 双列内容区 -->
      <div class="flex min-h-0 flex-1 overflow-hidden">
        <!-- 左侧一级大类垂直导航 -->
        <nav
          class="w-[104px] shrink-0 overflow-y-auto border-r border-line/60 bg-sunken/30 py-2 sm:w-[120px]"
          aria-label="一级分类"
        >
          <ul class="space-y-0.5 px-1.5">
            <li v-for="root in dict.rootCategories" :key="root.id">
              <button
                type="button"
                class="flex w-full items-center gap-2 rounded-sm px-2.5 py-2.5 text-left text-xs font-semibold transition-all duration-150"
                :class="
                  root.id === selectedRootId
                    ? 'bg-surface font-bold text-primary shadow-xs ring-1 ring-primary/20'
                    : 'text-ink-muted hover:bg-surface/60 hover:text-ink'
                "
                @click="selectedRootId = root.id"
              >
                <CategoryIcon
                  :name="root.name"
                  :icon="root.icon"
                  :color="root.color"
                  :size="15"
                />
                <span class="truncate">{{ root.name }}</span>
              </button>
            </li>
          </ul>
        </nav>

        <!-- 右侧二级分类网格 -->
        <main class="flex-1 overflow-y-auto p-3.5 sm:p-4" aria-label="二级分类列表">
          <div v-if="subCategories.length > 0" class="grid grid-cols-2 gap-2 sm:grid-cols-3">
            <button
              v-for="sub in subCategories"
              :key="sub.id"
              type="button"
              class="group flex flex-col items-center justify-center gap-1.5 rounded-md border p-3 text-center transition-all duration-150 active:scale-95"
              :class="
                sub.id === activeCategoryId
                  ? 'border-primary bg-primary/10 text-primary font-bold shadow-xs'
                  : 'border-line/70 bg-canvas hover:border-line hover:bg-sunken/40 text-ink'
              "
              @click="handleSelect(sub.id)"
            >
              <CategoryIcon
                :name="sub.name"
                :icon="activeRoot?.icon ?? sub.icon"
                :color="activeRoot?.color ?? sub.color"
                :color-name="activeRoot?.name ?? sub.name"
                :size="22"
              />
              <span class="truncate text-xs tracking-tight">
                {{ sub.name }}
              </span>
            </button>
          </div>

          <div v-else class="flex h-full items-center justify-center text-xs text-ink-muted">
            暂无可选分类
          </div>
        </main>
      </div>
    </div>
  </div>
</template>
