<script setup lang="ts">
/**
 * 分类编辑独立弹窗。
 *
 * 解决移动端行内折叠编辑导致高度抖动、背景分界不清的问题。
 * 提供名称修改、图标颜色定制（一级）、父级分类移动（二级）、停用/启用及删除功能。
 */
import { computed, ref, watch } from 'vue';
import { X } from '@lucide/vue';
import { ApiError, categories as categoriesApi, type Category } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import CategoryIcon from './CategoryIcon.vue';
import ColorPicker from './ColorPicker.vue';
import IconPicker from './IconPicker.vue';

const props = defineProps<{
  open: boolean;
  category: Category | null;
  parentCategories: Category[];
}>();

const emit = defineEmits<{
  close: [];
  saved: [];
}>();

const dict = useDictionariesStore();
const isCreate = computed(() => props.category === null);
const targetDepth = ref<'root' | 'child'>('root');

const name = ref('');
const icon = ref('');
const color = ref('');
const parentId = ref<string | null>(null);
const isEnabled = ref(true);

const busy = ref(false);
const errorMessage = ref<string | null>(null);

const autoColor = computed(() => dict.previewAutoColor(props.category?.id, name.value));

const isRoot = computed(() => {
  if (isCreate.value) return targetDepth.value === 'root';
  return props.category ? props.category.parentId === null : true;
});

watch(
  () => [props.open, props.category] as const,
  ([isOpen, cat]) => {
    if (!isOpen) return;
    if (cat) {
      name.value = cat.name;
      icon.value = cat.icon || '';
      color.value = cat.color || '';
      parentId.value = cat.parentId;
      isEnabled.value = cat.isEnabled;
      targetDepth.value = cat.parentId === null ? 'root' : 'child';
      errorMessage.value = null;
    } else {
      name.value = '';
      icon.value = '';
      color.value = '';
      parentId.value = props.parentCategories[0]?.id ?? null;
      isEnabled.value = true;
      targetDepth.value = 'root';
      errorMessage.value = null;
    }
  },
  { immediate: true },
);

// 可转移的一级分类目标（排除自己当前所在的）
const moveTargets = computed(() => {
  if (!props.category || isRoot.value) return [];
  return props.parentCategories.filter((root) => root.id !== props.category?.parentId);
});

async function handleSave(): Promise<void> {
  const trimmed = name.value.trim();
  if (!trimmed) {
    errorMessage.value = '分类名称不能为空';
    return;
  }

  busy.value = true;
  errorMessage.value = null;

  try {
    if (isCreate.value) {
      await categoriesApi.create({
        name: trimmed,
        parentId: isRoot.value ? null : parentId.value,
        icon: isRoot.value ? icon.value : undefined,
        color: isRoot.value ? color.value : undefined,
      });
    } else if (props.category) {
      const payload: {
        name?: string;
        icon?: string;
        color?: string;
        parentId?: string | null;
        isEnabled?: boolean;
      } = {
        name: trimmed,
        isEnabled: isEnabled.value,
      };

      if (isRoot.value) {
        payload.icon = icon.value;
        payload.color = color.value;
      } else if (parentId.value !== props.category.parentId) {
        payload.parentId = parentId.value;
      }

      await categoriesApi.update(props.category.id, payload);
    }

    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '保存失败，请重试';
  } finally {
    busy.value = false;
  }
}

async function handleToggleEnabled(): Promise<void> {
  if (!props.category) return;
  busy.value = true;
  errorMessage.value = null;
  try {
    await categoriesApi.update(props.category.id, { isEnabled: !isEnabled.value });
    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '操作失败，请重试';
  } finally {
    busy.value = false;
  }
}

</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-[var(--z-modal)] flex items-center justify-center p-3 sm:p-6"
    role="dialog"
    aria-modal="true"
  >
    <!-- 背景遮罩 -->
    <div
      class="fixed inset-0 bg-black/60 backdrop-blur-xs transition-opacity"
      @click="emit('close')"
    />

    <!-- 弹窗卡片 -->
    <div
      class="relative z-10 flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl border border-line bg-surface shadow-2xl"
    >
      <!-- 顶栏 -->
      <header class="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div class="flex items-center gap-2">
          <CategoryIcon
            v-if="isRoot"
            :name="name"
            :icon="icon"
            :color="color || String(autoColor)"
            :size="20"
          />
          <h2 class="text-base font-bold text-ink">
            {{ isCreate ? '新增分类' : (isRoot ? '编辑一级分类' : '编辑二级分类') }}
          </h2>
        </div>
        <button
          type="button"
          class="rounded-sm p-1 text-ink-muted hover:bg-sunken hover:text-ink"
          @click="emit('close')"
        >
          <X class="h-5 w-5" />
        </button>
      </header>

      <!-- 表单内容 -->
      <div class="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        <!-- 错误提示 -->
        <p v-if="errorMessage" class="rounded-sm bg-danger/10 p-3 text-xs text-danger-text">
          {{ errorMessage }}
        </p>

        <!-- 新建模式下选择分类层级 -->
        <div v-if="isCreate" class="grid grid-cols-2 gap-1 rounded-md bg-sunken p-1">
          <button
            type="button"
            class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
            :class="targetDepth === 'root' ? 'bg-canvas text-ink' : 'text-ink-muted'"
            @click="targetDepth = 'root'"
          >
            一级分类
          </button>
          <button
            type="button"
            class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
            :class="targetDepth === 'child' ? 'bg-canvas text-ink' : 'text-ink-muted'"
            @click="targetDepth = 'child'"
          >
            二级分类
          </button>
        </div>

        <!-- 二级分类父级选择 -->
        <div v-if="isCreate && targetDepth === 'child'">
          <label class="label-cn block mb-1.5">归属父分类</label>
          <select
            v-model="parentId"
            class="w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink focus:ring-1 focus:ring-primary"
          >
            <option v-for="root in parentCategories" :key="root.id" :value="root.id">
              {{ root.name }}
            </option>
          </select>
        </div>

        <!-- 分类名称 -->
        <div>
          <label class="label-cn block mb-1.5">分类名称</label>
          <input
            v-model="name"
            type="text"
            maxlength="20"
            placeholder="如「餐饮美食」"
            class="w-full rounded-sm bg-sunken px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-muted focus:ring-1 focus:ring-primary"
          />
        </div>

        <!-- 一级分类：图标与颜色 -->
        <template v-if="isRoot">
          <div>
            <label class="label-cn block mb-1.5">分类图标</label>
            <IconPicker v-model="icon" />
          </div>

          <div>
            <label class="label-cn block mb-1.5">色彩主题</label>
            <ColorPicker v-model="color" :auto-color="autoColor" />
          </div>
        </template>

        <!-- 编辑已有二级分类：移动归属 -->
        <template v-else-if="!isCreate">
          <div v-if="moveTargets.length > 0">
            <label class="label-cn block mb-1.5">归属父分类</label>
            <select
              v-model="parentId"
              class="w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink focus:ring-1 focus:ring-primary"
            >
              <option v-for="root in parentCategories" :key="root.id" :value="root.id">
                {{ root.name }}
              </option>
            </select>
          </div>
        </template>
      </div>

      <!-- 底部动作条：停用最左边，取消与保存靠右 -->
      <footer class="flex items-center justify-between border-t border-line px-5 py-3.5 bg-canvas/40">
        <div>
          <button
            v-if="!isCreate"
            type="button"
            :disabled="busy"
            class="rounded-sm px-3.5 py-2 text-xs font-semibold transition-colors disabled:opacity-40"
            :class="
              isEnabled
                ? 'border border-danger/40 text-danger hover:bg-danger/10'
                : 'border border-line bg-canvas text-ink hover:bg-surface'
            "
            @click="handleToggleEnabled"
          >
            {{ isEnabled ? '停用' : '启用' }}
          </button>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm px-4 py-2 text-xs font-semibold text-ink-muted hover:bg-sunken hover:text-ink transition-colors disabled:opacity-40"
            @click="emit('close')"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm bg-primary-fill px-5 py-2 text-xs font-bold text-on-primary shadow-xs transition-opacity hover:opacity-90 disabled:opacity-40"
            @click="handleSave"
          >
            {{ busy ? '保存中...' : '保存' }}
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>
