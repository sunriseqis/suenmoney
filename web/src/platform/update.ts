/**
 * 平台更新适配层。
 *
 * 铁律（§架构解耦纪律）：
 * 严禁在业务层静态 import 原生依赖；纯 Web / Docker 部署时 100% 纯净解耦并安全降级。
 */

import { getCapacitorPlugin, getPlatform, isNativePlatform } from './env.ts';

export interface AppVersion {
  versionName: string;
  versionCode: number;
}

export interface DownloadAndInstallOptions {
  url: string;
  accessToken?: string;
  fileName: string;
  expectedVersionName?: string;
  expectedVersionCode?: number;
  expectedSha256?: string;
}

export interface UpdateInstallResult {
  status: 'installer_opened' | 'install_permission_required' | 'unsupported';
}

interface SuenUpdateNativePlugin {
  getAppVersion(): Promise<AppVersion>;
  downloadAndInstall(
    options: DownloadAndInstallOptions,
  ): Promise<{ status: 'installer_opened' | 'install_permission_required' }>;
}

interface CapacitorAppPlugin {
  getInfo(): Promise<{ name: string; id: string; build: string; version: string }>;
}

export function isNativeUpdateSupported(): boolean {
  if (!isNativePlatform()) return false;
  const platform = getPlatform();
  return platform === 'android' || platform === 'ios';
}

export async function getNativeAppVersion(): Promise<AppVersion | null> {
  // 1. 优先尝试跨平台官方 App 插件（iOS 原生 CFBundleShortVersionString 与 Android versionName 统一标准）
  try {
    const appPlugin = await getCapacitorPlugin<CapacitorAppPlugin>('App');
    if (appPlugin) {
      const info = await appPlugin.getInfo();
      if (info?.version) {
        const buildCode = parseInt(info.build, 10);
        return {
          versionName: info.version,
          versionCode: Number.isFinite(buildCode) ? buildCode : 0,
        };
      }
    }
  } catch {
    // 降级尝试 Android 专用原生插件
  }

  // 2. Android 特定的 SuenUpdate 原生插件兜底
  try {
    const plugin = await getCapacitorPlugin<SuenUpdateNativePlugin>('SuenUpdate');
    if (plugin) {
      return await plugin.getAppVersion();
    }
  } catch {
    // 纯 Web 或未安装
  }

  return null;
}

export async function downloadAndInstallUpdate(
  options: DownloadAndInstallOptions,
): Promise<UpdateInstallResult> {
  const platform = getPlatform();

  // iOS 平台：由于系统沙盒与安装限制，IPA 包通过浏览器调起下载并引导自签安装
  if (platform === 'ios') {
    if (typeof window !== 'undefined' && options.url) {
      window.open(options.url, '_blank');
      return { status: 'installer_opened' };
    }
    return { status: 'unsupported' };
  }

  // Android 平台：通过专用插件下载并唤起系统 PackageInstaller
  const plugin = await getCapacitorPlugin<SuenUpdateNativePlugin>('SuenUpdate');
  if (!plugin) return { status: 'unsupported' };
  return await plugin.downloadAndInstall(options);
}
