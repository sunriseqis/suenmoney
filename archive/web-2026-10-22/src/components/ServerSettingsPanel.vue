<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { ArrowDown, ArrowUp, GripVertical, Plus, Trash2 } from '@lucide/vue';
import {
  probeServerUrl,
  readServerUrls,
  setActiveServerUrl,
  writeServerUrls,
} from '@/api';
import { useSyncStore } from '@/stores/sync';

const syncStore = useSyncStore();

// 服务端地址动态列表（纯净输入框，不再硬编码固定数量）
const serverUrls = ref<string[]>(['']);
const testing = ref(false);
const notice = ref<string | null>(null);
let noticeTimer: ReturnType<typeof setTimeout> | undefined;

function showNotice(msg: string): void {
  notice.value = msg;
  if (noticeTimer) clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => {
    notice.value = null;
  }, 3500);
}

function loadUrls(): void {
  const list = readServerUrls();
  serverUrls.value = list.length > 0 ? [...list] : [''];
}

onMounted(() => {
  loadUrls();
});

const cleanedUrls = computed(() =>
  serverUrls.value.map((u) => u.trim().replace(/\/+$/, '')).filter(Boolean),
);

function isActive(url?: string): boolean {
  if (!syncStore.isOnline || !syncStore.activeServerUrl || !url) return false;
  const cleanActive = syncStore.activeServerUrl.trim().replace(/\/+$/, '');
  const clean = url.trim().replace(/\/+$/, '');
  return clean.length > 0 && cleanActive === clean;
}

// ---- 列表加减与排序 --------------------------------------------------------

function addUrl(): void {
  serverUrls.value.push('');
}

function removeUrl(index: number): void {
  if (serverUrls.value.length > 1) {
    serverUrls.value.splice(index, 1);
  } else {
    serverUrls.value[0] = '';
  }
}

function moveUp(index: number): void {
  if (index <= 0) return;
  const item = serverUrls.value.splice(index, 1)[0];
  if (item !== undefined) {
    serverUrls.value.splice(index - 1, 0, item);
  }
}

function moveDown(index: number): void {
  if (index >= serverUrls.value.length - 1) return;
  const item = serverUrls.value.splice(index, 1)[0];
  if (item !== undefined) {
    serverUrls.value.splice(index + 1, 0, item);
  }
}

// 拖拽排序支持
const dragIndex = ref<number | null>(null);

function onDragStart(index: number): void {
  dragIndex.value = index;
}

function onDragOver(e: DragEvent): void {
  e.preventDefault();
}

function onDrop(index: number): void {
  if (dragIndex.value === null || dragIndex.value === index) return;
  const moved = serverUrls.value.splice(dragIndex.value, 1)[0];
  if (moved !== undefined) {
    serverUrls.value.splice(index, 0, moved);
  }
  dragIndex.value = null;
}

// ---- 操作逻辑 -------------------------------------------------------------

/**
 * 测试连通性：按顺序依次检测，自动寻找并切换至第一个可用地址。
 */
async function handleTest(): Promise<void> {
  testing.value = true;
  const urlsToTest = cleanedUrls.value;
  if (urlsToTest.length === 0) {
    showNotice('请先填写服务端地址');
    testing.value = false;
    return;
  }

  let firstConnected: string | null = null;
  let firstLatency: number | undefined;

  for (const url of urlsToTest) {
    if (!url) continue;
    const probe = await probeServerUrl(url, 2500);
    if (probe.ok) {
      firstConnected = url;
      firstLatency = probe.latencyMs;
      break;
    }
  }

  if (firstConnected) {
    writeServerUrls(urlsToTest);
    setActiveServerUrl(firstConnected);
    await syncStore.checkConnectivity();
    showNotice(`已连通 (${firstLatency}ms)`);
  } else {
    syncStore.isOnline = false;
    showNotice('未检测到可用服务端（离线可用）');
  }

  testing.value = false;
}

/**
 * 保存服务端配置
 */
function handleSave(): void {
  const urlsToSave = cleanedUrls.value;
  writeServerUrls(urlsToSave);
  showNotice('已保存');
  void syncStore.checkConnectivity();
}

/**
 * 立即触发双向同步
 */
async function handleSync(): Promise<void> {
  await syncStore.runSync();
  if (syncStore.isOnline) {
    showNotice('同步完成');
  } else {
    showNotice('当前处于离线状态，已暂存本地');
  }
}
</script>

<template>
  <section class="rounded-lg bg-surface p-5 border border-line">
    <!-- 顶栏：标题与当前微型状态标签（在线 / 离线） -->
    <div class="flex items-center justify-between pb-3 border-b border-line">
      <h2 class="text-sm font-bold text-ink">服务端设置</h2>
      <span
        class="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium"
        :class="
          syncStore.isOnline
            ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
            : 'bg-sunken text-ink-muted'
        "
      >
        <span
          class="h-1.5 w-1.5 rounded-full"
          :class="syncStore.isOnline ? 'bg-emerald-500' : 'bg-slate-400'"
        />
        {{ syncStore.isOnline ? '在线' : '离线' }}
      </span>
    </div>

    <!-- 服务端地址列表：纯净输入框，支持拖拽与箭头微调优先级 -->
    <div class="mt-4 space-y-2.5">
      <div
        v-for="(_, index) in serverUrls"
        :key="index"
        class="flex items-center gap-2"
        draggable="true"
        @dragstart="onDragStart(index)"
        @dragover="onDragOver"
        @drop="onDrop(index)"
      >
        <!-- 拖动手柄 -->
        <button
          type="button"
          class="text-ink-muted hover:text-ink cursor-grab active:cursor-grabbing p-1 touch-none"
          title="拖动调整顺序"
          tabindex="-1"
        >
          <GripVertical :size="15" />
        </button>

        <!-- 输入框（右侧内嵌生效小绿点） -->
        <div class="relative flex-1">
          <input
            v-model="serverUrls[index]"
            type="url"
            placeholder="http://192.168.1.100:3310"
            class="w-full rounded-sm border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none focus:border-primary transition-colors font-mono"
            :class="{ 'pr-7': isActive(serverUrls[index]) }"
          />
          <!-- 生效绿点（●） -->
          <span
            v-if="isActive(serverUrls[index])"
            class="absolute right-2.5 top-1/2 -translate-y-1/2 flex items-center justify-center text-emerald-500"
            title="当前生效"
          >
            <span class="inline-block h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
          </span>
        </div>

        <!-- 顺序调整按钮（适配移动触屏） -->
        <div class="flex items-center gap-0.5">
          <button
            type="button"
            :disabled="index === 0"
            class="p-1 text-ink-muted hover:text-ink disabled:opacity-20 transition-opacity"
            title="上移"
            @click="moveUp(index)"
          >
            <ArrowUp :size="14" />
          </button>
          <button
            type="button"
            :disabled="index === serverUrls.length - 1"
            class="p-1 text-ink-muted hover:text-ink disabled:opacity-20 transition-opacity"
            title="下移"
            @click="moveDown(index)"
          >
            <ArrowDown :size="14" />
          </button>
        </div>

        <!-- 删除单行按钮 -->
        <button
          type="button"
          class="p-1 text-ink-muted hover:text-danger-text transition-colors"
          title="删除此地址"
          @click="removeUrl(index)"
        >
          <Trash2 :size="14" />
        </button>
      </div>
    </div>

    <!-- 底部添加按钮（固定 + 号） -->
    <div class="mt-3 flex justify-center">
      <button
        type="button"
        class="inline-flex items-center justify-center h-8 w-8 rounded-full border border-dashed border-line text-ink-muted hover:border-primary hover:text-primary hover:bg-canvas transition-colors"
        title="添加服务端地址框"
        aria-label="添加服务端地址框"
        @click="addUrl"
      >
        <Plus :size="16" />
      </button>
    </div>

    <!-- 操作按钮栏：仅测试、保存、同步 3 个按钮，左侧内联通知防止页面高度跳动 -->
    <div class="mt-4 flex flex-wrap items-center justify-between gap-2 pt-3 border-t border-line min-h-[46px]">
      <div class="text-xs text-ink-muted min-w-0 flex-1 truncate">
        <span v-if="notice" class="text-primary-text font-medium">{{ notice }}</span>
      </div>

      <div class="flex items-center gap-2 shrink-0">
        <button
          type="button"
          :disabled="testing"
          class="rounded-sm border border-line bg-canvas px-3.5 py-1.5 text-xs font-semibold text-ink hover:bg-surface disabled:opacity-50 transition-colors"
          @click="handleTest"
        >
          {{ testing ? '测试中…' : '测试' }}
        </button>

        <button
          type="button"
          :disabled="testing"
          class="rounded-sm border border-line bg-canvas px-3.5 py-1.5 text-xs font-semibold text-ink hover:bg-surface disabled:opacity-50 transition-colors"
          @click="handleSave"
        >
          保存
        </button>

        <button
          type="button"
          :disabled="syncStore.isSyncing || testing"
          class="rounded-sm bg-primary-fill px-4 py-1.5 text-xs font-bold text-on-primary hover:opacity-90 disabled:opacity-50 transition-opacity"
          @click="handleSync"
        >
          {{ syncStore.isSyncing ? '同步中…' : '同步' }}
        </button>
      </div>
    </div>
  </section>
</template>
