import { getCapacitorPlugin, isNativePlatform } from './env';

export interface HardwareBackOptions {
  onBack: (canGoBack: boolean) => boolean | void; // 返回 true 表示已由业务消费拦截，不退出应用
  onExit: () => void;
}

/**
 * 监听物理返回键（Android / 移动手势返回）。
 * 业务代码零耦合原生 SDK，纯 Web 自动安全跳过。
 */
export function setupHardwareBack(options: HardwareBackOptions): () => void {
  if (!isNativePlatform()) return () => {};

  let nativeHandle: { remove: () => Promise<void> } | null = null;
  let isCleaned = false;

  void getCapacitorPlugin<{
    addListener: (
      eventName: 'backButton',
      cb: (data: { canGoBack: boolean }) => void,
    ) => Promise<{ remove: () => Promise<void> }>;
    exitApp: () => Promise<void>;
  }>('App').then((appPlugin) => {
    if (isCleaned || !appPlugin) return;

    void appPlugin
      .addListener('backButton', ({ canGoBack }) => {
        const handled = options.onBack(canGoBack);
        if (!handled) {
          options.onExit();
        }
      })
      .then((handle) => {
        if (isCleaned) {
          void handle.remove();
        } else {
          nativeHandle = handle;
        }
      });
  });

  return () => {
    isCleaned = true;
    if (nativeHandle) {
      void nativeHandle.remove();
    }
  };
}

export async function exitNativeApp(): Promise<void> {
  const appPlugin = await getCapacitorPlugin<{ exitApp: () => Promise<void> }>('App');
  if (appPlugin) {
    void appPlugin.exitApp();
  }
}
