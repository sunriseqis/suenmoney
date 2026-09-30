<script setup lang="ts">
/**
 * 设置 → 系统管理与数据。
 *
 * 遵循极简与纯净交互：
 * 1. 数据管理：包含导出账本、导入账本、导出流水、导入流水 4 个核心操作，无冗余解释文字；
 * 2. 安全备份：基于 WebDAV 远程自动化定时灾备，每日自动保留最近 3 天备份。
 */
import { computed, onMounted, reactive, ref } from 'vue';
import {
  Archive,
  FileSpreadsheet,
  FileText,
  Upload,
} from '@lucide/vue';

import {
  ApiError,
  data as dataApi,
  saveDownload,
  webdavBackup,
  type WebdavConfig,
  type WebdavStatus,
} from '@/api';
import { useAuthStore } from '@/stores/auth';
import { useUiStore } from '@/stores/ui';
import { useUpdateStore } from '@/stores/update';

const updateStore = useUpdateStore();

import BillImportModal from './BillImportModal.vue';
import LedgerImportModal from './LedgerImportModal.vue';
import ServerSettingsPanel from './ServerSettingsPanel.vue';

const auth = useAuthStore();
const ui = useUiStore();

const isAdmin = computed(() => auth.user?.role === 'admin');

const errorMessage = ref<string | null>(null);
const notice = ref<string | null>(null);

// 弹窗状态
const ledgerModalOpen = ref(false);
const billModalOpen = ref(false);

// WebDAV 配置与状态
const webdavLoading = ref(false);
const webdavTesting = ref(false);
const webdavSaving = ref(false);
const webdavRunning = ref(false);

const webdavForm = reactive<WebdavConfig>({
  url: '',
  username: '',
  password: '',
  path: '/suenmoney',
  isEnabled: true,
});

const webdavStatus = ref<WebdavStatus>({
  lastBackupAt: null,
  lastBackupStatus: null,
  lastBackupMessage: null,
  lastBackupFilename: null,
});

function report(error: unknown, fallback: string): void {
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
  notice.value = null;
}

function clearNotice(): void {
  errorMessage.value = null;
  notice.value = null;
}

// ---- 数据管理动作 ---------------------------------------------------------

async function handleExportLedger(): Promise<void> {
  clearNotice();
  try {
    const file = await dataApi.backup();
    saveDownload(file);
    notice.value = '账本备份已导出';
  } catch (error) {
    report(error, '导出账本失败');
  }
}

async function handleExportExpensesCsv(): Promise<void> {
  clearNotice();
  try {
    const file = await dataApi.exportCsv({ scope: 'all' });
    saveDownload(file);
    notice.value = '流水对账表已导出';
  } catch (error) {
    report(error, '导出流水失败');
  }
}

function onLedgerImported(): void {
  notice.value = '账本数据导入成功';
  errorMessage.value = null;
}

function onBillImported(count: number): void {
  notice.value = `已成功导入 ${count} 笔流水明细`;
  errorMessage.value = null;
  ui.markDataChanged();
}

// ---- WebDAV 备份 ----------------------------------------------------------

async function loadWebdav(): Promise<void> {
  webdavLoading.value = true;
  try {
    const res = await webdavBackup.get();
    if (res.config) {
      webdavForm.url = res.config.url;
      webdavForm.username = res.config.username;
      webdavForm.password = res.config.password ?? '';
      webdavForm.path = res.config.path || '/suenmoney';
      webdavForm.isEnabled = res.config.isEnabled;
    }
    webdavStatus.value = res.status;
  } catch {
    // 忽略初次静默加载异常
  } finally {
    webdavLoading.value = false;
  }
}

async function handleTestWebdav(): Promise<void> {
  clearNotice();
  webdavTesting.value = true;
  try {
    const res = await webdavBackup.test({
      url: webdavForm.url,
      username: webdavForm.username,
      password: webdavForm.password,
      path: webdavForm.path,
    });
    notice.value = res.message || 'WebDAV 连接与写入权限测试成功';
  } catch (error) {
    report(error, 'WebDAV 测试失败');
  } finally {
    webdavTesting.value = false;
  }
}

async function handleSaveWebdav(): Promise<void> {
  clearNotice();
  webdavSaving.value = true;
  try {
    await webdavBackup.save({
      url: webdavForm.url,
      username: webdavForm.username,
      password: webdavForm.password,
      path: webdavForm.path,
      isEnabled: webdavForm.isEnabled,
    });
    notice.value = 'WebDAV 安全备份配置已保存';
    await loadWebdav();
  } catch (error) {
    report(error, '保存配置失败');
  } finally {
    webdavSaving.value = false;
  }
}

async function handleRunWebdavBackup(): Promise<void> {
  clearNotice();
  webdavRunning.value = true;
  try {
    const res = await webdavBackup.run();
    notice.value = `安全备份成功已上传至 WebDAV（${res.filename}）`;
    await loadWebdav();
  } catch (error) {
    report(error, '立即备份失败');
  } finally {
    webdavRunning.value = false;
  }
}

function formatBackupTime(isoStr: string | null): string {
  if (!isoStr) return '暂无记录';
  try {
    const d = new Date(isoStr);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  } catch {
    return isoStr;
  }
}

onMounted(() => {
  void loadWebdav();
});
</script>

<template>
  <div class="space-y-6">
    <!-- 服务端设置（置顶展示，所有成员均可配置） -->
    <ServerSettingsPanel />

    <!-- 管理员专属：数据管理与安全备份 -->
    <template v-if="isAdmin">
      <!-- 全局提示条 -->
      <div
        v-if="notice"
        class="flex items-center justify-between rounded-md bg-primary-fill/10 border border-primary/20 px-4 py-2.5 text-xs text-primary"
      >
        <span>{{ notice }}</span>
        <button type="button" class="ml-2 font-bold hover:underline" @click="notice = null">✕</button>
      </div>
      <div
        v-if="errorMessage"
        class="flex items-center justify-between rounded-md bg-danger/10 border border-danger/20 px-4 py-2.5 text-xs text-danger-text"
      >
        <span>{{ errorMessage }}</span>
        <button type="button" class="ml-2 font-bold hover:underline" @click="errorMessage = null">✕</button>
      </div>

      <!-- 卡片 1：数据管理 -->
    <section class="rounded-lg border border-line bg-surface p-5 shadow-xs">
      <h3 class="text-sm font-bold text-ink">数据管理</h3>

      <div class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <!-- 导出账本 -->
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-2 rounded-md border border-line bg-canvas p-4 text-center transition-all hover:border-primary/50 hover:bg-surface active:scale-[0.98]"
          @click="handleExportLedger"
        >
          <div class="flex h-9 w-9 items-center justify-center rounded-full bg-primary/10 text-primary">
            <Archive class="h-4 w-4" />
          </div>
          <span class="text-xs font-bold text-ink">导出账本</span>
        </button>

        <!-- 导入账本 -->
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-2 rounded-md border border-line bg-canvas p-4 text-center transition-all hover:border-primary/50 hover:bg-surface active:scale-[0.98]"
          @click="ledgerModalOpen = true"
        >
          <div class="flex h-9 w-9 items-center justify-center rounded-full bg-primary/10 text-primary">
            <Upload class="h-4 w-4" />
          </div>
          <span class="text-xs font-bold text-ink">导入账本</span>
        </button>

        <!-- 导出流水 -->
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-2 rounded-md border border-line bg-canvas p-4 text-center transition-all hover:border-primary/50 hover:bg-surface active:scale-[0.98]"
          @click="handleExportExpensesCsv"
        >
          <div class="flex h-9 w-9 items-center justify-center rounded-full bg-primary/10 text-primary">
            <FileSpreadsheet class="h-4 w-4" />
          </div>
          <span class="text-xs font-bold text-ink">导出流水</span>
        </button>

        <!-- 导入流水 -->
        <button
          type="button"
          class="flex flex-col items-center justify-center gap-2 rounded-md border border-line bg-canvas p-4 text-center transition-all hover:border-primary/50 hover:bg-surface active:scale-[0.98]"
          @click="billModalOpen = true"
        >
          <div class="flex h-9 w-9 items-center justify-center rounded-full bg-primary/10 text-primary">
            <FileText class="h-4 w-4" />
          </div>
          <span class="text-xs font-bold text-ink">导入流水</span>
        </button>
      </div>
    </section>

    <!-- 卡片 2：安全备份 -->
    <section class="rounded-lg border border-line bg-surface p-5 shadow-xs">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-bold text-ink">安全备份</h3>
        <label class="flex items-center gap-2 text-xs font-medium text-ink cursor-pointer">
          <input
            v-model="webdavForm.isEnabled"
            type="checkbox"
            class="h-4 w-4 rounded-xs border-line text-primary focus:ring-0"
          />
          每日自动备份
        </label>
      </div>

      <p class="mt-1 text-xs text-ink-muted">
        每日自动备份至 WebDAV，仅保留最近 3 天备份。
      </p>

      <!-- 备份状态横幅 -->
      <div
        v-if="webdavStatus.lastBackupAt"
        class="mt-3.5 flex items-center justify-between rounded-md bg-canvas px-3.5 py-2.5 text-xs"
      >
        <span class="text-ink-muted">上次备份：</span>
        <div class="flex items-center gap-1.5 font-medium">
          <span
            class="inline-block h-2 w-2 rounded-full"
            :class="webdavStatus.lastBackupStatus === 'success' ? 'bg-[#07C160]' : 'bg-danger'"
          />
          <span class="text-ink">{{ formatBackupTime(webdavStatus.lastBackupAt) }}</span>
          <span
            class="text-[11px]"
            :class="webdavStatus.lastBackupStatus === 'success' ? 'text-ink-muted' : 'text-danger'"
          >
            ({{ webdavStatus.lastBackupStatus === 'success' ? '成功' : '失败' }})
          </span>
        </div>
      </div>

      <!-- WebDAV 表单项 -->
      <div class="mt-4 space-y-3">
        <div>
          <label class="block text-xs font-medium text-ink">服务器地址 (URL)</label>
          <input
            v-model="webdavForm.url"
            type="url"
            placeholder="https://dav.jianguoyun.com/dav"
            class="mt-1 w-full rounded-sm border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none focus:border-primary"
          />
        </div>

        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div>
            <label class="block text-xs font-medium text-ink">账号</label>
            <input
              v-model="webdavForm.username"
              type="text"
              placeholder="WebDAV 用户名"
              class="mt-1 w-full rounded-sm border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none focus:border-primary"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-ink">密码</label>
            <input
              v-model="webdavForm.password"
              type="password"
              placeholder="WebDAV 密码 / 授权口令"
              class="mt-1 w-full rounded-sm border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none focus:border-primary"
            />
          </div>
        </div>

        <div>
          <label class="block text-xs font-medium text-ink">备份目录</label>
          <input
            v-model="webdavForm.path"
            type="text"
            placeholder="/suenmoney"
            class="mt-1 w-full rounded-sm border border-line bg-canvas px-3 py-2 text-xs text-ink outline-none focus:border-primary"
          />
        </div>
      </div>

      <!-- 操作按钮栏 -->
      <div class="mt-5 flex flex-wrap items-center justify-end gap-2.5 pt-3 border-t border-line">
        <button
          type="button"
          :disabled="webdavTesting || !webdavForm.url || !webdavForm.username"
          class="rounded-sm border border-line bg-canvas px-3.5 py-1.5 text-xs font-semibold text-ink hover:bg-surface disabled:opacity-50 transition-colors"
          @click="handleTestWebdav"
        >
          {{ webdavTesting ? '测试中…' : '测试连通' }}
        </button>

        <button
          type="button"
          :disabled="webdavSaving || !webdavForm.url || !webdavForm.username"
          class="rounded-sm border border-line bg-canvas px-3.5 py-1.5 text-xs font-semibold text-ink hover:bg-surface disabled:opacity-50 transition-colors"
          @click="handleSaveWebdav"
        >
          {{ webdavSaving ? '保存中…' : '保存配置' }}
        </button>

        <button
          type="button"
          :disabled="webdavRunning || !webdavForm.url"
          class="rounded-sm bg-primary-fill px-4 py-1.5 text-xs font-bold text-on-primary hover:opacity-90 disabled:opacity-50 transition-opacity"
          @click="handleRunWebdavBackup"
        >
          {{ webdavRunning ? '备份中…' : '立即备份' }}
        </button>
      </div>
    </section>
    </template>

    <!-- 关于应用与品牌展示 -->
    <section aria-label="关于应用" class="flex flex-col items-center justify-center pt-8 pb-4 text-center select-none">
      <img src="/logo.png" alt="SuenMoney" class="w-12 h-12 rounded-xl shadow-xs mb-2" />
      <div class="text-sm font-bold text-ink">SuenMoney</div>
      <div class="text-xs text-ink-muted mt-0.5">家庭记账 · 离线优先 · 多端自动同步</div>
      <div class="text-[11px] text-ink-muted/70 mt-1">
        版本 v{{ updateStore.appVersion?.versionName || '1.0.0' }}
      </div>

      <!-- 更新检查操作与状态反馈 -->
      <div class="mt-2.5 flex flex-col items-center gap-1.5">
        <button
          v-if="!updateStore.available"
          type="button"
          :disabled="updateStore.checking"
          class="inline-flex items-center gap-1.5 rounded-full border border-line bg-surface px-3 py-1 text-xs font-medium text-ink transition-colors hover:bg-canvas disabled:opacity-50"
          @click="updateStore.check(false)"
        >
          <span v-if="updateStore.checking" class="inline-block h-2 w-2 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          <span>{{ updateStore.checking ? '正在检查…' : '检查更新' }}</span>
        </button>

        <button
          v-else
          type="button"
          class="inline-flex items-center gap-1.5 rounded-full bg-primary-fill px-3.5 py-1 text-xs font-bold text-on-primary transition-transform hover:opacity-95 active:scale-95"
          @click="updateStore.open()"
        >
          <span>发现新版本 v{{ updateStore.latest?.versionName }} · 立即更新</span>
        </button>

        <p v-if="updateStore.message" class="text-[11px] text-ink-muted transition-opacity">
          {{ updateStore.message }}
        </p>
      </div>
    </section>

    <!-- 弹窗挂载 -->
    <LedgerImportModal
      :open="ledgerModalOpen"
      @close="ledgerModalOpen = false"
      @imported="onLedgerImported"
    />

    <BillImportModal
      :open="billModalOpen"
      @close="billModalOpen = false"
      @imported="onBillImported"
    />
  </div>
</template>
