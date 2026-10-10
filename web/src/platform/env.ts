/**
 * 平台环境判断与动态运行时检测。
 *
 * 核心目标：
 * 保证 Web 源码不硬性静态依赖任何原生 SDK，纯 Web / PWA / Docker 部署时 100% 纯净；
 * 随时可将 Web 与 Android 拆为两个独立 Git 仓库。
 */

export function isNativePlatform(): boolean {
  if (typeof window === 'undefined') return false;
  const win = window as unknown as { Capacitor?: { isNativePlatform?: () => boolean } };
  return Boolean(win.Capacitor?.isNativePlatform?.());
}

export type PlatformType = 'android' | 'ios' | 'web';

export function getPlatform(): PlatformType {
  if (typeof window === 'undefined') return 'web';
  const win = window as unknown as {
    Capacitor?: {
      getPlatform?: () => string;
      isNativePlatform?: () => boolean;
    };
  };
  const capPlatform = win.Capacitor?.getPlatform?.();
  if (capPlatform === 'ios') return 'ios';
  if (capPlatform === 'android') return 'android';

  // 备用兜底（某些运行环境下如果 Capacitor.getPlatform 尚未初始化）
  const ua = navigator?.userAgent ?? '';
  if (/iPad|iPhone|iPod/.test(ua)) return 'ios';
  if (/Android/.test(ua)) return 'android';

  return 'web';
}

export function isIos(): boolean {
  return getPlatform() === 'ios';
}

export function isAndroid(): boolean {
  return getPlatform() === 'android';
}

/** 动态安全加载 Capacitor 原生模块（纯 Web 运行时安全降级为 null） */
export async function getCapacitorPlugin<T = unknown>(pluginName: string): Promise<T | null> {
  if (!isNativePlatform()) return null;
  try {
    const win = window as unknown as { Capacitor?: { Plugins?: Record<string, T> } };
    if (win.Capacitor?.Plugins?.[pluginName]) {
      return win.Capacitor.Plugins[pluginName];
    }
    // 动态尝试动态导入，防止构建期静态死绑定
    if (pluginName === 'App') {
      const mod = await import('@capacitor/app');
      return mod.App as unknown as T;
    }
  } catch {
    // 纯 Web 环境或未安装该原生插件时安全降级
  }
  return null;
}
