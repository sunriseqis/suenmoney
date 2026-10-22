<script setup lang="ts">
/**
 * 分类图标选择（分组网格）。
 *
 * 图标名必须来自 `ICON_REGISTRY` —— 存进去的是名字，渲染时再查表；
 * 存组件本身没法过 JSON，也没法在服务端做校验。
 */
import { computed, ref } from 'vue';

import { ICON_GROUPS, ICON_REGISTRY, type IconName } from '@/utils/icons';
import { PInput } from '@/ui';

defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();

const keyword = ref('');

const groups = computed(() => {
  const k = keyword.value.trim();
  if (k === '') return ICON_GROUPS;
  return ICON_GROUPS.map((g) => ({ label: g.label, icons: g.icons.filter((i) => i.includes(k)) })).filter(
    (g) => g.icons.length > 0,
  );
});

function pick(name: IconName): void {
  emit('update:modelValue', name);
}
</script>

<template>
  <div class="icon-picker">
    <PInput v-model="keyword" placeholder="搜索图标（英文名）" />
    <div class="ip-scroll">
      <div v-for="g in groups" :key="g.label" class="ip-group">
        <span class="field-l">{{ g.label }}</span>
        <div class="ip-grid">
          <button
            v-for="name in g.icons"
            :key="name"
            type="button"
            class="ip-cell"
            :class="{ 'is-on': modelValue === name }"
            :title="name"
            @click="pick(name)"
          >
            <component :is="ICON_REGISTRY[name]" :size="17" :stroke-width="2.2" aria-hidden="true" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.icon-picker {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.ip-scroll {
  max-height: 240px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.ip-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(38px, 1fr));
  gap: 6px;
  margin-top: 6px;
}
.ip-cell {
  aspect-ratio: 1;
  display: grid;
  place-items: center;
  border: 1px solid var(--line);
  border-radius: var(--r-sm);
  background: var(--surface);
  color: var(--ink-2);
  transition: all 0.16s;
}
.ip-cell:hover {
  color: var(--ink);
  border-color: var(--ink-3);
}
.ip-cell.is-on {
  border-color: var(--accent);
  color: var(--accent);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 25%, transparent);
}
</style>
