/**
 * 平台更新适配层。
 *
 * 铁律（§架构解耦纪律）：
 * 严禁在业务层静态 import 原生依赖；纯 Web / Docker 部署时 100% 纯净解耦并安全降级。
 */

import { getCapacitorPlugin, isNativePlatform } from './env';

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

export function isNativeUpdateSupported(): boolean {
  return isNativePlatform();
}

export async function getNativeAppVersion(): Promise<AppVersion | null> {
  const plugin = await getCapacitorPlugin<SuenUpdateNativePlugin>('SuenUpdate');
  if (!plugin) return null;
  try {
    return await plugin.getAppVersion();
  } catch {
    return null;
  }
}

export async function downloadAndInstallUpdate(
  options: DownloadAndInstallOptions,
): Promise<UpdateInstallResult> {
  const plugin = await getCapacitorPlugin<SuenUpdateNativePlugin>('SuenUpdate');
  if (!plugin) return { status: 'unsupported' };
  return await plugin.downloadAndInstall(options);
}
