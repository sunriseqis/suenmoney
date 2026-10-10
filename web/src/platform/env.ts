/**
 * 平台环境判断与动态运行时检测。
 *
 * 核心目标：
 * 保证 Web 源码不硬性静态依赖任何原生 SDK，纯 Web / PWA / Docker 部署时 100% 纯净；
 * 随时可将 Web 与 Android 拆为两个独立 Git 仓库。
 */

/**
 * 鸿蒙（ArkWeb 壳）注入到 window 上的原生能力桥。
 *
 * 为什么必须把鸿蒙和 Capacitor 分开：
 * 鸿蒙壳是**纯 ArkWeb**，没有 Capacitor 运行时，`window.Capacitor` 根本不存在。
 * 壳里的 `isNativePlatform()` 又是无条件 `return true`，于是老代码会「以为自己是
 * Capacitor 原生应用」→ 去 `getCapacitorPlugin('App')` 拿插件 → 永远拿不到 →
 * 返回键监听、前后台监听整条链路空跑（不报错，只是静默失效，最难查）。
 * 所以鸿蒙必须走下面这套「壳主动注入、Web 被动接收」的契约，而不是假装自己是 Capacitor。
 */
export interface SuenMoneyNativeBridge {
  /** 平台标识，鸿蒙壳固定为 'harmony' */
  platform: 'harmony';
  /** 应用版本；壳读不到 bundle 信息时为 null（**不再伪造 1.0.0**） */
  version: { versionName: string; versionCode: number } | null;
  /** 退出应用 */
  exit: () => void;
  /** 注册返回键处理（壳实际调用的是全局 `window.__suenmoneyOnNativeBack`，见 hardware.ts） */
  onBack?: (handler: () => boolean) => void;
  /** 原生前后台事件；壳未提供时回退到 visibilitychange / pageshow */
  onAppState?: (cb: (state: 'active' | 'background') => void) => void;
  /** 壳主动推送安全区避让高度 */
  safeArea?: (top: number, bottom: number) => void;
}

declare global {
  interface Window {
    __suenmoney?: SuenMoneyNativeBridge;
    /** 壳按返回键时调用；返回 true 表示 Web 已拦截（不退出） */
    __suenmoneyOnNativeBack?: () => boolean;
  }
}

/** 等待壳注入的轮询间隔与总时长：ArkWeb 的注入发生在 onPageEnd，可能晚于 Web 侧 onMounted */
const BRIDGE_POLL_MS = 100;
const BRIDGE_WAIT_MS = 5000;

/** 读取鸿蒙壳注入的原生能力桥；非鸿蒙 / 未注入时返回 null */
export function getNativeBridge(): SuenMoneyNativeBridge | null {
  if (typeof window === 'undefined') return null;
  return window.__suenmoney ?? null;
}

/**
 * 判定「当前跑在鸿蒙壳里」。
 *
 * 判据只有一个：壳注入了 `window.__suenmoney` 且 `platform === 'harmony'`。
 * 这是壳与 Web 之间显式的握手信号，比任何「猜」都可靠。
 */
export function isHarmonyPlatform(): boolean {
  return getNativeBridge()?.platform === 'harmony';
}

/**
 * 壳是在**页面加载完成后**才注入能力桥的（ArkWeb `onPageEnd` 里 runJavaScript），
 * 而 Web 的 onMounted 跑得更早。所以「现在还没注入」不代表「不会注入」。
 * 这里做一次有上限的短轮询：拿到就立刻回调，超时就放弃并走原有降级路径，
 * 绝不无限等待、也绝不在纯 Web 上注册任何原生拦截。
 */
export function whenNativeBridgeReady(callback: (bridge: SuenMoneyNativeBridge) => void): () => void {
  if (typeof window === 'undefined') return () => {};

  const existing = window.__suenmoney;
  if (existing) {
    callback(existing);
    return () => {};
  }

  let cancelled = false;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const deadline = Date.now() + BRIDGE_WAIT_MS;

  const poll = (): void => {
    if (cancelled) return;
    const bridge = window.__suenmoney;
    if (bridge) {
      callback(bridge);
      return;
    }
    // 超时：老壳 / 纯 Web / 壳注入失败 —— 放弃等待，交回各模块自己的降级路径
    if (Date.now() >= deadline) return;
    timer = setTimeout(poll, BRIDGE_POLL_MS);
  };
  timer = setTimeout(poll, BRIDGE_POLL_MS);

  return () => {
    cancelled = true;
    if (timer) clearTimeout(timer);
  };
}

export function isNativePlatform(): boolean {
  if (typeof window === 'undefined') return false;
  // 鸿蒙：壳注入了能力桥就算原生环境（哪怕它没有、也不该有 Capacitor）
  if (isHarmonyPlatform()) return true;
  const win = window as unknown as {
    Capacitor?: { isNativePlatform?: () => boolean };
    SuenHarmony?: { isNativePlatform?: () => boolean };
    __HARMONY_NEXT__?: boolean;
  };
  return Boolean(
    win.Capacitor?.isNativePlatform?.() ||
    win.SuenHarmony?.isNativePlatform?.() ||
    win.__HARMONY_NEXT__,
  );
}

export type PlatformType = 'android' | 'ios' | 'harmony' | 'web';

export function getPlatform(): PlatformType {
  if (typeof window === 'undefined') return 'web';

  // 鸿蒙新壳：能力桥是显式握手，优先认它
  if (isHarmonyPlatform()) return 'harmony';

  const win = window as unknown as {
    Capacitor?: {
      getPlatform?: () => string;
      isNativePlatform?: () => boolean;
    };
    SuenHarmony?: {
      getPlatform?: () => string;
    };
    __HARMONY_NEXT__?: boolean;
  };

  if (win.__HARMONY_NEXT__ || win.SuenHarmony) return 'harmony';

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

export function isHarmony(): boolean {
  return getPlatform() === 'harmony';
}

/** 动态安全加载 Capacitor 原生模块（纯 Web 运行时安全降级为 null） */
export async function getCapacitorPlugin<T = unknown>(pluginName: string): Promise<T | null> {
  if (!isNativePlatform()) return null;
  // 鸿蒙（新壳与老壳都是）没有 Capacitor 运行时，必须在这里拦一道。
  // 不拦的后果不只是「拿不到插件」：`import('@capacitor/app')` 在纯 Web 下会成功返回
  // 一个**代理对象**，而它是个 thenable —— 从 async 函数里 return 它等于让外层 Promise
  // 去 then() 它，于是访问 `.then` 时抛出的 CapacitorException 发生在 try/catch 之外，
  // 变成 unhandled rejection，把整条返回键/前后台链路静默打断（鸿蒙端最难查的那种故障）。
  if (getPlatform() === 'harmony') return null;
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
