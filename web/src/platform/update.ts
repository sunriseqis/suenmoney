/**
 * 平台更新适配层。
 *
 * 铁律（§架构解耦纪律）：
 * 严禁在业务层静态 import 原生依赖；纯 Web / Docker 部署时 100% 纯净解耦并安全降级。
 */

import { getCapacitorPlugin, getNativeBridge, getPlatform, isNativePlatform } from './env.ts';

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
  return platform === 'android' || platform === 'ios' || platform === 'harmony';
}

/**
 * 读取当前客户端的真实版本号。
 *
 * 返回 `null` 的含义是**「不知道」**，不是「版本是 1.0.0」。
 * 为什么绝不返回伪造的占位版本：上层会拿这个值去和服务端比对版本，
 * 一个凭空捏造的 1.0.0 会让服务端永远判定「有更新」，于是用户反复看到
 * 「发现新版本 1.0.0」的假提示。宁可说不知道，也不要报一个假版本。
 */
export async function getNativeAppVersion(): Promise<AppVersion | null> {
  // 1. 鸿蒙新壳：壳在页面加载完成后注入 window.__suenmoney.version，
  //    读不到 bundle 信息时壳给的是 null（老壳伪造 1.0.0 的问题因此在源头消失）
  const harmonyVersion = getNativeBridge()?.version;
  if (harmonyVersion?.versionName) {
    return {
      versionName: String(harmonyVersion.versionName),
      versionCode: Number(harmonyVersion.versionCode) || 0,
    };
  }

  // 2. 鸿蒙老壳：ArkTS 注入的 SuenHarmony JSBridge 接口
  if (typeof window !== 'undefined' && !getNativeBridge()) {
    const win = window as unknown as {
      SuenHarmony?: {
        getAppVersion?: () => string;
      };
    };
    if (win.SuenHarmony?.getAppVersion) {
      try {
        const raw = win.SuenHarmony.getAppVersion();
        const parsed = JSON.parse(raw) as { versionName?: string; versionCode?: number };
        if (parsed?.versionName) {
          return {
            versionName: String(parsed.versionName),
            versionCode: Number(parsed.versionCode) || 0,
          };
        }
      } catch {
        // 忽略解析错误：读不到就是读不到，往下走其他途径
      }
    }
  }

  // 3. 优先尝试跨平台官方 App 插件（iOS 原生 CFBundleShortVersionString 与 Android versionName 统一标准）
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

  // 4. Android 特定的 SuenUpdate 原生插件兜底
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

  // 鸿蒙 NEXT 平台：通过系统浏览器打开下载
  if (platform === 'harmony') {
    if (typeof window !== 'undefined') {
      const win = window as unknown as {
        SuenHarmony?: { openInBrowser?: (url: string) => boolean };
      };
      if (win.SuenHarmony?.openInBrowser && options.url) {
        win.SuenHarmony.openInBrowser(options.url);
        return { status: 'installer_opened' };
      }
      if (options.url) {
        window.open(options.url, '_blank');
        return { status: 'installer_opened' };
      }
    }
    return { status: 'unsupported' };
  }

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
