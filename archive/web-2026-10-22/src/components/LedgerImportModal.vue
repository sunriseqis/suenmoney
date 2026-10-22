<script setup lang="ts">
import { ref, watch } from 'vue';
import { Upload, X } from '@lucide/vue';

import { ApiError, data as dataApi } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useUiStore } from '@/stores/ui';

const props = defineProps<{
  open: boolean;
}>();

const emit = defineEmits<{
  close: [];
  imported: [];
}>();

const dict = useDictionariesStore();
const ui = useUiStore();

const mode = ref<'merge' | 'restore'>('merge');
const fileInput = ref<HTMLInputElement | null>(null);
const selectedFile = ref<File | null>(null);
const fileContent = ref<unknown | null>(null);
const busy = ref(false);
const errorMessage = ref<string | null>(null);

watch(
  () => props.open,
  (isOpen) => {
    if (!isOpen) {
      selectedFile.value = null;
      fileContent.value = null;
      errorMessage.value = null;
      mode.value = 'merge';
    }
  },
);

async function onFileSelected(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  if (!input.files || input.files.length === 0) return;
  const file = input.files[0]!;
  input.value = '';

  errorMessage.value = null;
  selectedFile.value = file;

  try {
    const text = await file.text();
    fileContent.value = JSON.parse(text);
  } catch {
    errorMessage.value = '文件解析失败，请确保上传的是有效的 JSON 账本备份文件';
    selectedFile.value = null;
    fileContent.value = null;
  }
}

async function handleImport(): Promise<void> {
  if (!fileContent.value) {
    errorMessage.value = '请先选择 JSON 账本文件';
    return;
  }

  busy.value = true;
  errorMessage.value = null;

  try {
    if (mode.value === 'merge') {
      await dataApi.import(fileContent.value);
    } else {
      await dataApi.restore(fileContent.value);
    }

    await dict.load(true);
    ui.markDataChanged();
    emit('imported');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '导入失败';
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs"
    @click.self="emit('close')"
  >
    <div
      class="w-full max-w-md rounded-lg bg-surface p-5 shadow-xl border border-line"
      @click.stop
    >
      <!-- 弹窗标题 -->
      <div class="flex items-center justify-between pb-3 border-b border-line">
        <h3 class="text-base font-bold text-ink">导入账本</h3>
        <button
          type="button"
          class="rounded-xs p-1 text-ink-muted hover:bg-canvas hover:text-ink transition-colors"
          @click="emit('close')"
        >
          <X class="h-4 w-4" />
        </button>
      </div>

      <!-- 模式选择（全量 / 增量） -->
      <div class="mt-4">
        <div class="grid grid-cols-2 gap-2 rounded-md bg-canvas p-1">
          <button
            type="button"
            class="rounded-xs py-2 text-xs font-semibold transition-colors"
            :class="
              mode === 'merge'
                ? 'bg-surface text-ink font-bold shadow-xs'
                : 'text-ink-muted hover:text-ink'
            "
            @click="mode = 'merge'"
          >
            增量
          </button>
          <button
            type="button"
            class="rounded-xs py-2 text-xs font-semibold transition-colors"
            :class="
              mode === 'restore'
                ? 'bg-surface text-ink font-bold shadow-xs'
                : 'text-ink-muted hover:text-ink'
            "
            @click="mode = 'restore'"
          >
            全量
          </button>
        </div>
      </div>

      <!-- 文件选择区域 -->
      <div class="mt-4">
        <div
          class="flex flex-col items-center justify-center rounded-md border-2 border-dashed border-line bg-canvas/40 px-4 py-6 text-center transition-colors hover:border-primary/50"
        >
          <Upload class="h-8 w-8 text-ink-muted opacity-60" />
          <p class="mt-2 text-xs font-medium text-ink">
            {{ selectedFile ? selectedFile.name : '选择 JSON 账本备份文件' }}
          </p>

          <button
            type="button"
            class="mt-3 rounded-sm bg-canvas px-4 py-1.5 text-xs font-semibold text-ink border border-line hover:bg-surface transition-colors"
            @click="fileInput?.click()"
          >
            {{ selectedFile ? '更换文件' : '浏览文件' }}
          </button>
          <input
            ref="fileInput"
            type="file"
            accept=".json,application/json"
            class="sr-only"
            @change="onFileSelected"
          />
        </div>
      </div>

      <!-- 错误提示 -->
      <p v-if="errorMessage" class="mt-3 text-xs text-danger">
        {{ errorMessage }}
      </p>

      <!-- 底部动作按钮 -->
      <div class="mt-5 flex items-center justify-end gap-2.5">
        <button
          type="button"
          :disabled="busy"
          class="rounded-sm border border-line bg-canvas px-4 py-2 text-xs font-medium text-ink hover:bg-surface disabled:opacity-50"
          @click="emit('close')"
        >
          取消
        </button>
        <button
          type="button"
          :disabled="busy || !fileContent"
          class="rounded-sm bg-primary-fill px-4 py-2 text-xs font-bold text-on-primary hover:opacity-90 disabled:opacity-50"
          @click="handleImport"
        >
          {{ busy ? '正在导入…' : '开始导入' }}
        </button>
      </div>
    </div>
  </div>
</template>
