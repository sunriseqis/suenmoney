import { getCapacitorPlugin, getNativeBridge, whenNativeBridgeReady } from './env.ts';

export interface HardwareBackOptions {
  onBack: (canGoBack: boolean) => boolean | void; // 返回 true 表示已由业务消费拦截，不退出应用
  onExit: () => void;
}

/**
 * 「返回前是否还有未保存内容」的询问事件名。
 *
 * 约定（鸿蒙返回键专用）：任何持有脏数据的组件监听 window 上的
 * `suenmoney:before-back`，在事件上调用 `preventDefault()` 即表示「有未保存内容，别退」。
 * 鸿蒙返回键是**同步**回调原生函数的，拿不到 Promise，所以只能用同步的 DOM 事件来问；
 * 业务侧监听器只需同步地把 decide 结果写进 event.detail，不需要 await。
 */
export const BEFORE_BACK_EVENT = 'suenmoney:before-back';

export interface BeforeBackEventDetail {
  /** 业务侧填写：true = 有未保存内容，应拦截返回键 */
  shouldIntercept?: boolean;
}

/**
 * 询问业务侧当前是否有未保存内容（脏表单 / 未提交草稿）。
 *
 * 事件是同步派发的，返回时 detail 里就是业务侧的答复；
 * 没有任何监听器时 detail 保持空 → 返回 false → 允许退出（绝不因为没人应答而卡死返回键）。
 */
function askBeforeBack(): boolean {
  if (typeof window === 'undefined') return false;
  const detail: BeforeBackEventDetail = {};
  try {
    const event = new CustomEvent<BeforeBackEventDetail>(BEFORE_BACK_EVENT, {
      detail,
      cancelable: true,
    });
    const notCancelled = window.dispatchEvent(event);
    // 双通道：既认 preventDefault()，也认 detail.shouldIntercept，方便业务侧任选一种写法
    return !notCancelled || detail.shouldIntercept === true;
  } catch {
    // CustomEvent 构造/派发失败（如极端降级 WebView）：宁可放行也不卡死返回键
    return false;
  }
}

/**
 * 监听物理返回键。
 *
 * 三条路径，各自独立判断，谁有条件谁就上：
 *  1. 鸿蒙新壳：注册全局 `window.__suenmoneyOnNativeBack`，由壳在 onBackPress 时调用。
 *     决策权完全在 Web —— 先问业务「有没有未保存内容」，再问 onBack 是否消费，
 *     都不消费才调用壳的 exit()。Web 返回 false 时壳也会自行退出，二者一致。
 *  2. iOS / Android：Capacitor App 插件的 backButton 事件，行为保持不变。
 *  3. 老壳 / 纯 Web：既没等到桥也没有插件 —— 不注册任何拦截，返回键行为与改动前完全一致。
 */
export function setupHardwareBack(options: HardwareBackOptions): () => void {
  // 注意：这里**不能**因为「此刻还不是原生环境」就提前返回。
  // 鸿蒙壳是在页面加载完成后（onPageEnd）才注入能力桥，而本函数通常在 onMounted 里调用 ——
  // 那一刻 window.__suenmoney 还不存在。若按老写法 `if (!isNativePlatform()) return`，
  // 真机上就会在这里直接空跑返回，返回键永远接不上（比空跑更难查：连日志都没有）。
  // 所以改为：三条路径各自独立判断，谁有条件谁就上，没有的静默跳过。

  let nativeHandle: { remove: () => Promise<void> } | null = null;
  let isCleaned = false;
  const cleanups: Array<() => void> = [];
  let installedBackHandler: (() => boolean) | null = null;

  // ---- 1. 鸿蒙：把返回键决策权交给 Web ----
  const registerHarmonyBack = (): void => {
    if (isCleaned || typeof window === 'undefined') return;

    const handler = (): boolean => {
      if (isCleaned) return false;

      // 1a. 先问业务：有没有还没保存的东西？—— 这一步优先于路由返回，
      //     否则在二级页面上带着未保存草稿时，返回键会直接退到上一页而不是提示用户。
      if (askBeforeBack()) return true;

      // 1b. 交给业务原有的返回逻辑（关抽屉 / 路由回退）
      const handled = options.onBack(canGoBack());
      if (handled) return true;

      // 1c. 无人拦截 → 允许退出。返回 false 让壳按自己的策略退出，
      //     同时主动走 onExit（内部会调壳的 exit），两条通路都能真正退出，
      //     不会停在「谁都不退」的中间态。
      try {
        options.onExit();
      } catch {
        // onExit 抛错时兜底直接调壳的 exit，再不行就把 false 交回壳让它自己退
        try {
          getNativeBridge()?.exit?.();
        } catch {
          // 壳退出失败：返回 false，壳侧仍有默认退出行为，返回键不会被卡死
        }
      }
      return false;
    };

    installedBackHandler = handler;
    // 后注册覆盖先注册：HMR / 组件重挂载时始终用最新一次传入的 options，
    // 避免拿到上一次的 stale 回调（这正是早期「幂等跳过」写法埋的坑）。
    window.__suenmoneyOnNativeBack = handler;
  };

  // 立刻注册，不等壳注入。
  //
  // 为什么必须立刻：壳只注入了 window.__suenmoneyExit 与 __HARMONY_NEXT__，
  // **从来没有注入 window.__suenmoney 这个能力桥对象**。而下面的
  // whenNativeBridgeReady 是以「桥出现」为触发条件的，等来的必然是 5秒超时，
  // 于是 window.__suenmoneyOnNativeBack 永远不会被注册 —— 壳的 onBackPress
  // 转发的是一个undefined，返回键形同失灵。
  // 「有没有注册」这件事交给壳侧在**每次**返回键时用
  // `window.__suenmoneyOnNativeBack && ...` 现场判断，Web 侧不必替它预判。
  registerHarmonyBack();

  // 桥若将来真的被注入（例如壳补上 onAppState/safeArea），再注册一次以刷新 options。
  // 现在这只是一次幂等的重复赋值：真正的注册已经发生在上面。
  const cancelBridgeWait = whenNativeBridgeReady(registerHarmonyBack);
  cleanups.push(cancelBridgeWait);

  // ---- 2. iOS / Android：Capacitor App 插件 ----
  // 行为与改动前完全一致；纯 Web / 鸿蒙下 getCapacitorPlugin 直接给 null，这里自然空跑。
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
    for (const fn of cleanups) {
      fn();
    }
    // 只摘掉自己注册的那个：若之后有别的 setupHardwareBack 实例重新注册过，
    // 这里删掉就会把别人的处理器误伤，返回键会彻底失灵。
    if (typeof window !== 'undefined' && window.__suenmoneyOnNativeBack === installedBackHandler) {
      delete window.__suenmoneyOnNativeBack;
    }
    if (nativeHandle) {
      void nativeHandle.remove();
    }
  };
}

/**
 * SPA 内部是否还有可回退的历史。
 *
 * 鸿蒙壳不再替我们做 accessBackward() 判断，所以 Web 要自己算。
 * 这里从保守方向取值：只有 `history.length > 1` 才认为「有上一页可退」。
 * 宁可判成不可回退（让业务走退出，用户明确看到应用关闭），
 * 也不要在其实退不掉的地方执行 router.back() —— 那会让返回键按了没反应，比直接退出更难排查。
 */
function canGoBack(): boolean {
  if (typeof window === 'undefined') return false;
  return window.history.length > 1;
}

export async function exitNativeApp(): Promise<void> {
  // 鸿蒙：优先走能力桥的 exit。
  const bridge = getNativeBridge();
  if (bridge?.exit) {
    try {
      bridge.exit();
    } catch {
      // 壳退出失败时静默降级，交给壳侧默认行为
    }
    return;
  }

  // 鸿蒙：壳实际注入的是 window.__suenmoneyExit（Index.ets 的 injectExitHandler），
  // 而**不是** window.__suenmoney 能力桥对象。少了这一条，返回键走到最后一步
  // 「无人拦截 → 允许退出」时什么都不会发生：桥读不到、Capacitor 插件也没有，
  // 于是「返回键退出应用」静默失效 —— 用户按返回键毫无反应，比直接退出更难排查。
  if (typeof window !== 'undefined') {
    const shellExit = (window as unknown as { __suenmoneyExit?: () => void }).__suenmoneyExit;
    if (typeof shellExit === 'function') {
      try {
        shellExit();
      } catch {
        // 壳退出失败时静默降级，交给壳侧默认行为
      }
      return;
    }
  }

  const appPlugin = await getCapacitorPlugin<{ exitApp: () => Promise<void> }>('App');
  if (appPlugin) {
    void appPlugin.exitApp();
  }
}
