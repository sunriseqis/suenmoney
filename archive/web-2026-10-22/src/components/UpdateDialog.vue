<script setup lang="ts">
/**
 * 应用自动更新弹窗（全局唯一，挂载在 App.vue 根节点）。
 *
 * 两个入口共用：
 *   1. 启动或切到前台时的静默检查（检测到新版本且未被忽略时自动唤起）；
 *   2. 设置/系统页面的「检查更新」手动触发。
 */
import { ArrowDownCircle, Loader2 } from '@lucide/vue';
import { computed } from 'vue';

import { useUpdateStore } from '@/stores/update';

const update = useUpdateStore();

const info = computed(() => update.latest);

const sizeText = computed(() => {
  const bytes = info.value?.size ?? 0;
  if (bytes <= 0) return '';
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="update.dialogOpen && info"
      class="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs transition-opacity duration-200"
      @click.self="update.dismiss()"
    >
      <div
        class="w-full max-w-sm rounded-2xl border border-line bg-surface p-6 shadow-2xl transition-all duration-200"
        role="dialog"
        aria-modal="true"
        aria-labelledby="update-dialog-title"
      >
        <div class="flex items-center gap-3">
          <div class="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <ArrowDownCircle :size="24" :stroke-width="2.2" />
          </div>
          <div>
            <h3 id="update-dialog-title" class="text-base font-bold text-ink">
              发现新版本
            </h3>
            <p class="text-xs font-semibold text-primary">
              SuenMoney v{{ info.versionName }}
            </p>
          </div>
        </div>

        <div class="mt-4 space-y-2 rounded-xl border border-line/60 bg-canvas/60 p-3.5 text-xs">
          <div class="flex justify-between">
            <span class="text-ink-muted">当前版本</span>
            <span class="font-mono font-medium text-ink">
              v{{ update.appVersion?.versionName || '1.0.0' }}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-ink-muted">最新版本</span>
            <span class="font-mono font-semibold text-primary">
              v{{ info.versionName }}
            </span>
          </div>
          <div v-if="sizeText" class="flex justify-between">
            <span class="text-ink-muted">安装包大小</span>
            <span class="font-mono font-medium text-ink">{{ sizeText }}</span>
          </div>
        </div>

        <!-- 错误提示 -->
        <p v-if="update.error" class="mt-3 rounded-lg bg-rose-500/10 px-3 py-2 text-xs font-medium text-rose-500">
          {{ update.error }}
        </p>

        <!-- 下载中状态提示 -->
        <div
          v-else-if="update.installing"
          class="mt-3 flex items-center gap-2 rounded-lg bg-primary/10 px-3 py-2 text-xs font-medium text-primary"
        >
          <Loader2 class="h-4 w-4 animate-spin text-primary" />
          <span>正在下载安装包并准备安装，请稍候…</span>
        </div>

        <div class="mt-6 flex items-center justify-end gap-2.5">
          <button
            type="button"
            :disabled="update.installing"
            class="rounded-xl border border-line bg-canvas px-4 py-2 text-xs font-semibold text-ink-muted transition-colors hover:bg-surface hover:text-ink disabled:opacity-50"
            @click="update.dismiss()"
          >
            以后再说
          </button>
          <button
            type="button"
            :disabled="update.installing"
            class="inline-flex items-center gap-1.5 rounded-xl bg-primary-fill px-4 py-2 text-xs font-bold text-on-primary transition-transform duration-150 hover:opacity-95 active:scale-95 disabled:opacity-60"
            @click="update.install()"
          >
            <Loader2 v-if="update.installing" class="h-3.5 w-3.5 animate-spin" />
            <span>{{ update.installing ? '安装中…' : '立即更新' }}</span>
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
