import { getCapacitorPlugin } from './env';

type AppResumeListener = () => void;

/**
 * 监听应用恢复至前台（打开软件、切回前台、页面可见）。
 * 自动适配纯 Web 与 Android 原生容器。
 *
 * @param callback 唤醒回调
 * @returns 移除监听函数
 */
export function onAppResume(callback: AppResumeListener): () => void {
  let cleanedUp = false;
  let nativeHandle: { remove: () => void | Promise<void> } | null = null;

  // 1. Web 标准 API 监听：visibilitychange 与 pageshow
  const onVisibilityChange = () => {
    if (document.visibilityState === 'visible') {
      callback();
    }
  };

  const onPageShow = (e: PageTransitionEvent) => {
    if (e.persisted) {
      callback();
    }
  };

  if (typeof document !== 'undefined') {
    document.addEventListener('visibilitychange', onVisibilityChange);
  }
  if (typeof window !== 'undefined') {
    window.addEventListener('pageshow', onPageShow);
  }

  // 2. 原生 App 插件动态接入（若处于原生容器）
  void getCapacitorPlugin<{
    addListener: (
      eventName: 'appStateChange',
      cb: (state: { isActive: boolean }) => void,
    ) => Promise<{ remove: () => Promise<void> }>;
  }>('App').then((appPlugin) => {
    if (cleanedUp || !appPlugin) return;
    void appPlugin
      .addListener('appStateChange', (state) => {
        if (state.isActive) {
          callback();
        }
      })
      .then((handle) => {
        if (cleanedUp) {
          void handle.remove();
        } else {
          nativeHandle = handle;
        }
      });
  });

  return () => {
    cleanedUp = true;
    if (typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', onVisibilityChange);
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('pageshow', onPageShow);
    }
    if (nativeHandle) {
      void nativeHandle.remove();
    }
  };
}
