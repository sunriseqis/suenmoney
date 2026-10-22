/**
 * 应用更新 Store（原生 Android 自动下载安装，纯 Web/Docker 安全降级）。
 *
 * 两个主要触发入口：
 *   1. App 启动或切到前台时静默检查一次 —— 没更新不打扰，有更新且未被忽略时弹窗提示；
 *   2. 设置/系统页「检查更新」按钮 —— 明确反馈（如“当前已是最新版本”或“发现新版本”）。
 */

import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { readToken } from '@/api/client';
import * as updateApi from '@/api/update';
import {
  downloadAndInstallUpdate,
  getNativeAppVersion,
  getPlatform,
  isNativeUpdateSupported,
  type AppVersion,
} from '@/platform';

const SKIPPED_KEY = 'suenmoney.update.skippedVersion';

function readSkipped(): string {
  try {
    return localStorage.getItem(SKIPPED_KEY) ?? '';
  } catch {
    return '';
  }
}

function writeSkipped(version: string): void {
  try {
    localStorage.setItem(SKIPPED_KEY, version);
  } catch {
    // 忽略隐私模式限制
  }
}

export const useUpdateStore = defineStore('update', () => {
  const appVersion = ref<AppVersion | null>(null);
  const result = ref<updateApi.UpdateCheckResult | null>(null);
  const checking = ref(false);
  const installing = ref(false);
  const dialogOpen = ref(false);
  const autoPrompt = ref(false);
  const error = ref('');
  const message = ref('');

  const isSupported = computed(() => isNativeUpdateSupported());
  const available = computed(() => result.value?.available === true);
  const latest = computed(() => result.value?.latest ?? null);

  // 初始化尝试读取本地原生应用版本
  void (async () => {
    try {
      const ver = await getNativeAppVersion();
      if (ver) appVersion.value = ver;
    } catch {
      // 忽略启动时读取错误
    }
  })();

  /**
   * 检查更新。
   * @param silent 是否为静默检查（启动时使用：无更新或网络故障时不打扰，被忽略过的版本不再弹）
   */
  async function check(silent = false): Promise<void> {
    // 平台门禁：纯 Web / Docker 部署没有「客户端」可更新。
    if (!isSupported.value) return;

    // 只有 iOS / Android 有可比较的版本与可安装的产物。
    // 鸿蒙在服务端没有对应的安装包渠道，且壳可能注入 version: null（读不到就是读不到），
    // 这里直接安静返回：不发请求、不弹窗、不写 message，避免在鸿蒙端弹出无法处理的更新提示。
    const currentPlatform = getPlatform();
    if (currentPlatform !== 'android' && currentPlatform !== 'ios') return;

    if (checking.value) return;

    checking.value = true;
    error.value = '';
    if (!silent) message.value = '';

    try {
      const nativeVer = await getNativeAppVersion();
      // 「读不到原生版本」和「版本是 1.0.0」必须严格区分。
      // 旧实现会在这里兜一个 { versionName: '1.0.0', versionCode: 1 } 再去和服务端比版本，
      // 服务端当然判定「有更新」→ 鸿蒙端反复弹假更新提示，用户点进去发现装不了。
      // 这里读不到就直接放弃本次检查：宁可说不知道，也不要报一个假版本。
      if (!nativeVer) {
        appVersion.value = null;
        if (!silent) message.value = '无法获取当前版本，请稍后再试';
        return;
      }
      appVersion.value = nativeVer;

      const checked = await updateApi.checkUpdate(appVersion.value, {
        force: !silent,
        platform: currentPlatform,
      });
      result.value = checked;

      if (!checked.available || !checked.latest) {
        if (!silent) message.value = '当前已是最新版本';
        return;
      }

      message.value = `发现新版本 ${checked.latest.versionName}`;

      // 启动静默提醒：若该版本曾被用户点击「以后再说」，本次不再弹窗打扰
      if (silent && readSkipped() === checked.latest.versionName) return;

      autoPrompt.value = silent;
      dialogOpen.value = true;
    } catch (e) {
      if (silent) return;
      message.value = e instanceof Error ? e.message : '检查更新失败，请稍后重试';
    } finally {
      checking.value = false;
    }
  }

  function dismiss(): void {
    if (installing.value) return;
    dialogOpen.value = false;
    error.value = '';
    if (autoPrompt.value && latest.value) {
      writeSkipped(latest.value.versionName);
    }
    autoPrompt.value = false;
  }

  function open(): void {
    if (!available.value) return;
    autoPrompt.value = false;
    error.value = '';
    dialogOpen.value = true;
  }

  async function install(): Promise<void> {
    const info = latest.value;
    const checked = result.value;
    if (!available.value || !info || !checked || installing.value) return;

    installing.value = true;
    error.value = '';

    try {
      const currentPlatform = getPlatform() === 'ios' ? 'ios' : 'android';
      const url = updateApi.getFullDownloadUrl(checked, currentPlatform);
      const token = readToken() || '';

      const outcome = await downloadAndInstallUpdate({
        url,
        accessToken: token,
        fileName: info.fileName,
        expectedVersionName: info.versionName,
        expectedVersionCode: info.versionCode || undefined,
        expectedSha256: info.sha256 || undefined,
      });

      if (outcome.status === 'unsupported') {
        error.value = '当前环境不支持直接安装，请在移动端客户端内使用';
        return;
      }

      dialogOpen.value = false;
      autoPrompt.value = false;

      message.value =
        currentPlatform === 'ios'
          ? '已在浏览器中打开 IPA 下载，请使用自签工具完成安装'
          : outcome.status === 'install_permission_required'
            ? '请允许本应用安装未知来源应用，然后再次点击更新'
            : '已打开系统安装界面，请按提示完成安装';
    } catch (e) {
      error.value = e instanceof Error ? e.message : '更新下载失败，请稍后重试';
    } finally {
      installing.value = false;
    }
  }

  return {
    appVersion,
    result,
    checking,
    installing,
    dialogOpen,
    autoPrompt,
    error,
    message,
    isSupported,
    available,
    latest,
    check,
    dismiss,
    open,
    install,
  };
});
