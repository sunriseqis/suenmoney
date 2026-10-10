import { webview } from '@kit.ArkWeb';
// WebResourceResponse 只能从 @kit.ArkWeb 的 webview 命名空间取：new webview.WebResourceResponse(...)
// 旧模块 @ohos.web.webview 的默认导出是 webview 命名空间对象本身（不是那个类，new 它会报
// 10505001「This expression is not constructable. Type 'typeof webview' has no construct
// signatures」），且它并不导出具名成员 WebResourceResponse（报「has no exported member」）。
// 故此处不再从 @ohos.web.webview 导入任何东西；webview 命名空间同时用于 WebviewController。
import { bundleManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SuenMoney_IndexPage';
const DOMAIN = 0x0000;
const LOCAL_ORIGIN = 'http://localhost';

// 避让区连续变化（旋转、键盘弹出）时合并推送的防抖窗口，单位 ms。
const SAFE_AREA_DEBOUNCE_MS = 100;

// 注入给 Web 的原生版本信息。字段名与 Web 侧 AppVersion（platform/update.ts）严格一致。
interface NativeVersionInfo {
  versionName: string;
  versionCode: number;
}

class HarmonyBridge {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /**
   * 读取当前原生应用版本，返回**可直接嵌入注入脚本的 JS 字面量字符串**。
   * 读取失败时返回 `'null'`（也就是 JS 的 null 字面量），绝不伪造版本号。
   *
   * 为什么失败不兜一个假版本：这个值会被 Web 拿去和服务端比对版本，
   * 凭空捏造的 1.0.0 会让服务端永远判定「有更新」，于是用户反复看到
   * 「发现新版本 1.0.0」的假提示，点进去还装不了。宁可说不知道。
   */
  getAppVersionLiteral(): string {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      const info: NativeVersionInfo = {
        versionName: bundleInfo.versionName,
        versionCode: bundleInfo.versionCode
      };
      return JSON.stringify(info);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get bundle info: %{public}s', JSON.stringify(err));
      return 'null';
    }
  }

  // 老接口：javaScriptProxy 只能同步返回值，老 Web 包按 JSON 字符串解析它。
  // 现在它与 getAppVersionLiteral 共用同一份实现，失败同样是 'null'，
  // 于是「壳伪造 1.0.0」这个缺陷在**两条**读取路径上同时消失。
  getAppVersion(): string {
    return this.getAppVersionLiteral();
  }

  // 唤起外部默认浏览器打开链接（用于自更新下载或外部查看）
  openInBrowser(url: string): boolean {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url
      };
      this.context.startAbility(want);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to open browser: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 退出应用。Web 侧判定「没有未保存内容、可以退出」后经window.__suenmoneyExit() 调用。
  // 用 terminateSelf()：它只销毁当前 UIAbility 并回到桌面，
  // 进程随之结束；相比 startAbility 跳转到别处更符合「退出」的语义。
  exitApp(): void {
    try {
      this.context.terminateSelf();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to terminate self: %{public}s', JSON.stringify(err));
    }
  }

  // 平台标识
  isNativePlatform(): boolean {
    return true;
  }

  getPlatform(): string {
    return 'harmony_next';
  }
}

// 是否为debug 构建包。
// 为什么必须判断：setWebDebuggingAccess(true) 会让任何人用 USB 连上设备就能
// inspect 本应用的全部 Web 页面（含用户账本数据、token）。它只该在开发包打开，
// 正式包打开等于把线上数据裸奔给任何物理接触设备的人。
// applicationInfo.debug 由 Hvigor 按 buildMode 注入：debug 包为 true，release 包为 false。
function isDebugPackage(context: common.UIAbilityContext): boolean {
  try {
    return context.applicationInfo.debug;
  } catch (err) {
    // 取不到就按「非debug」处理：宁可开发时少一个调试入口，也不能让正式包带上它。
    hilog.error(DOMAIN, TAG, 'Failed to read applicationInfo.debug: %{public}s', JSON.stringify(err));
    return false;
  }
}

@Entry
@Component
struct Index {
  private webviewController: webview.WebviewController = new webview.WebviewController();
  // @Watch 挂在 @StorageProp 上：EntryAbility 监听 avoidAreaChange 后写入 AppStorage，
  // 这里随之收到新值并回调 onSafeAreaChange，从而把避让区实时推给 Web。
  @StorageProp('topAvoidHeight') @Watch('onSafeAreaChange') topAvoidHeight: number = 0;
  @StorageProp('bottomAvoidHeight') @Watch('onSafeAreaChange') bottomAvoidHeight: number = 0;
  // 这里保留已废弃的 getContext(this)，不迁移到 this.getUIContext()。
  // 原因：这是**成员变量初始化器**，不是成员方法也不是生命周期回调，
  // 而 getUIContext() 按 ArkUI 约定只在成员方法/生命周期回调里才保证可用 ——
  // 构造期组件的原生实例尚未就绪，取到的 UIContext 可能为空。
  // 一旦 bridge 构造失败，本文件下方那段注释描述的三个降级会**静默**同时发生
  // （平台认不出、版本号读不到、前后台事件退化），且不带任何日志。
  // 拿一个不阻塞构建的弃用 WARN 去换这种风险不划算，故维持现状。
  private bridge: HarmonyBridge = new HarmonyBridge(getContext(this) as common.UIAbilityContext);

  // 避让区防抖句柄。旋转屏幕/键盘弹出时 avoidAreaChange 会连续触发多次，
  // 不合并的话会连续注入十几遍同样的CSS 变量，白白重排页面。
  private safeAreaTimer: number = -1;
  // 页面是否已完成一次 onPageEnd。未加载完时不能调 runJavaScript，否则会抛错。
  private pageReady: boolean = false;

  // bridge 在成员初始化阶段构建（见下方字段声明），此处不用它。
  // getContext 已废弃（API 18 起），改用 this.getUIContext().getHostContext()；
  // 两者拿到的都是当前 Ability 的 UIAbilityContext，isDebugPackage 的判定结果不变。
  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!isDebugPackage(context)) {
      return;
    }
    try {
      // 仅debug 包开启 ArkWeb 调试（支持通过 Chrome DevTools inspect 调试）
      webview.WebviewController.setWebDebuggingAccess(true);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to set web debugging: %{public}s', JSON.stringify(err));
    }
  }

  // 把当前避让区高度写进 Web 的 CSS 变量。
  // 单位换算说明：ArkUI 的避让区是 px，Web 的 --safe-top/--safe-bottom 按 px 使用
  // （web/src/styles/tokens.css 里就是拿它做 calc(var(--safe-bottom) + ...)），
  // 因此这里换算后仍以 'px' 结尾 —— Web 侧只认 CSS px，写 vp 会被当成另一个数。
  //
  // 全局 px2vp() 已废弃，改用绑定到本组件的 this.getUIContext().px2vp()。
  // 两者换算结果完全相同（同一个 px→vp 公式，只是不再依赖隐式的全局 UI 上下文），
  // 因此 CSS 变量的值不变，避让区注入行为不受影响。
  private injectSafeArea(): void {
    const topPx = this.getUIContext().px2vp(this.topAvoidHeight);
    const bottomPx = this.getUIContext().px2vp(this.bottomAvoidHeight);
    const script = `
      document.documentElement.style.setProperty('--safe-top', '${topPx}px');
      document.documentElement.style.setProperty('--safe-bottom', '${bottomPx}px');
    `;
    try {
      this.webviewController.runJavaScript(script);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to inject safe area: %{public}s', JSON.stringify(err));
    }
  }

  // 避让区变化回调（旋转/ 键盘弹出）。延迟一个防抖窗口再注入，合并突发事件。
  private onSafeAreaChange(): void {
    if (!this.pageReady) {
      return;
    }
    if (this.safeAreaTimer !== -1) {
      clearTimeout(this.safeAreaTimer);
    }
    this.safeAreaTimer = setTimeout(() => {
      this.safeAreaTimer = -1;
      this.injectSafeArea();
    }, SAFE_AREA_DEBOUNCE_MS);
  }

  // 注入壳侧能力桥：window.__suenmoney（契约对象）+ window.__suenmoneyExit + 平台标记。
  //
  // 【这个对象为什么必须存在】
  // Web 层（web/src/platform/*）与壳之间只有这一份显式契约，Web 靠读它决定三件事：
  //   ① 是不是鸿蒙端—— env.ts 判据是 `window.__suenmoney?.platform === 'harmony'`；
  //   ② 原生版本是多少 —— update.ts 读 `.version`，读不到返回 null（此时更新检查被跳过）；
  //   ③ 有没有前后台切换 —— lifecycle.ts 订阅 `.onAppState`，拿不到就回退 visibilitychange。
  // 桥对象缺席时不会报错，只会**静默降级**：平台认不出来、版本号读不到（鸿蒙端永远查不到更新）、
  // 前后台事件退化成 Web 标准事件。三个故障一起出现，且都不带日志，所以必须在这里补齐。
  //
  // 【为什么用赋值而不是裸对象字面量】
  // ArkTS 里 `{platform: 'harmony', ...}` 这种「裸对象字面量语句」不是合法语句（会编译失败），
  // 对象字面量只能出现在赋值右侧或传参位置。因此这里统一写成 `window.__suenmoney = {...}`。
  //
  // 【为什么 onAppState 这个键不提供】
  // 壳目前**没有**对应的前后台事件源：Ability 的 onForeground/onBackground 只打了日志，
  // 既没有把状态写进 AppStorage，也没有 runJavaScript 推给页面。塞一个空函数等于
  // 「假装有」——lifecycle.ts 会以为订阅成功，反而**不再回退** visibilitychange，
  // 把现在能用的降级路径也弄坏。宁可少一个键：Web 侧 `bridge.onAppState?.()` 会安全跳过，
  // 由 visibilitychange / pageshow 兜底（这对刷新时机是够的）。
  //
  // 【为什么 safeArea 这个键不提供】
  // 契约里 safeArea 是「壳主动推给 Web」的函数，但壳当前的推送方式是把避让区
  // 直接写成 CSS 变量（injectSafeArea，与首屏注入共用同一函数），不经过这个对象。
  // Web 侧也没有任何地方调用 bridge.safeArea，提供了就是死代码。
  private injectNativeBridge(): void {
    // 版本在这里读一次并取好字面量，读失败得到字符串 'null'，注入后就是 JS 的 null。
    const versionLiteral = this.bridge.getAppVersionLiteral();
    const script = `
      window.__suenmoneyExit = function () {
        try {
          SuenHarmony.exitApp();
        } catch (e) {
          console.error('[harmony] exitApp failed: ' + e);
        }
      };
      window.__HARMONY_NEXT__ = true;
      window.__suenmoney = {
        platform: 'harmony',
        version: ${versionLiteral},
        exit: function () {
          try {
            SuenHarmony.exitApp();
          } catch (e) {
            console.error('[harmony] exitApp failed: ' + e);
          }
        }
      };
    `;
    try {
      this.webviewController.runJavaScript(script);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to inject native bridge: %{public}s', JSON.stringify(err));
    }
  }

  // 拦截系统返回手势/返回键。
  // 为什么把决策权交给 Web：原生无从得知页面里有没有未保存的表单/草稿，
  // 只按accessBackward() 走会在「有未保存内容」时直接丢掉编辑现场。
  // 这里只负责转发，是否真的退出由 Web 判断（拦截或调 __suenmoneyExit）。
  //
  // 为什么**不**做「一次性探测」（曾经 probeWebBackHandler 的做法，已删除）：
  // onPageEnd 只触发一次，而 Web 侧 window.__suenmoneyOnNativeBack 的注册时刻不可预知
  // （组件挂载、路由、甚至壳注入桥的早晚都可能让它晚一步）。探测结果是一次性快照，
  // 只要 Web 晚一步，那次探测就得到 false 并被永久缓存，于是「有未提交草稿时按返回键」
  // 这个拦截**永远不会生效** —— 而这正是本次要修的核心诉求。快照必然过期，所以不复用。
  onBackPress(): boolean {
    // 无条件转发：`window.__suenmoneyOnNativeBack && ...` 本身就是「注册了才调用」的判据。
    // 老 Web 包（没注册这个函数）时表达式求值为 undefined，本次返回不被消费，
    // 自然落到下面的原生逻辑 —— 与改动前的降级行为完全一致。
    if (this.pageReady) {
      try {
        this.webviewController.runJavaScript(
          'window.__suenmoneyOnNativeBack && window.__suenmoneyOnNativeBack()');
        // 返回 true 表示本次返回已被消费。Web 若判定可以退出会再调 __suenmoneyExit()，
        // 若判定有未保存内容则自己提示；两种情况都不该再由原生重复处理。
        return true;
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Failed to forward back to web: %{public}s', JSON.stringify(err));
        return true;
      }
    }

    // 页面还没加载完（或 runJavaScript 抛错前的兜底）：沿用原生逻辑，
    // 优先让网页后退，无历史则返回 false 交回系统默认行为（退出应用）。
    if (this.webviewController.accessBackward()) {
      this.webviewController.backward();
      return true;
    }
    return false;
  }

  // 辅助函数：根据文件后缀匹配 MIME 类型
  private getMimeType(filePath: string): string {
    const lower = filePath.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) return 'application/javascript';
    if (lower.endsWith('.css')) return 'text/css';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.ico')) return 'image/x-icon';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    return 'application/octet-stream';
  }

  // 从 rawfile 读取本地资源构建 WebResourceResponse
  // 类型与构造都走 @kit.ArkWeb 的 webview 命名空间（见文件头 import 处注释）：
  // 该类不是旧模块 @ohos.web.webview 的默认导出，只能写成 webview.WebResourceResponse。
  private loadRawFile(rawPath: string): webview.WebResourceResponse | null {
    try {
      // getContext 已废弃（API 18 起），改用 this.getUIContext().getHostContext()。
      // 这里在 try 内，取不到 context 会抛，行为与原先的 getContext 失败路径一致（返回 null）。
      const hostCtx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const resMgr = hostCtx.resourceManager;
      const content = resMgr.getRawFileContentSync(rawPath);
      const response: webview.WebResourceResponse = new webview.WebResourceResponse();
      response.setResponseData(content.buffer as ArrayBuffer);
      response.setResponseMimeType(this.getMimeType(rawPath));
      response.setResponseEncoding('utf-8');
      response.setResponseCode(200);
      response.setReasonMessage('OK');
      response.setResponseIsReady(true);
      return response;
    } catch (err) {
      return null;
    }
  }

  build() {
    Column() {
      Web({
        src: `${LOCAL_ORIGIN}/index.html`,
        controller: this.webviewController
      })
        .domStorageAccess(true)
        .fileAccess(true)
        .imageAccess(true)
        .databaseAccess(true) // 启用 IndexedDB 支持离线记账
        .mixedMode(MixedMode.All)
        .javaScriptAccess(true)
        .javaScriptProxy({
          object: this.bridge,
          name: 'SuenHarmony',
          methodList: ['getAppVersion', 'openInBrowser', 'isNativePlatform', 'getPlatform', 'exitApp'],
          controller: this.webviewController
        })
        .onInterceptRequest((event) => {
          if (!event) return null;
          const reqUrl = event.request.getRequestUrl();

          // 仅拦截指向 http://localhost 的本地静态资源请求
          if (!reqUrl.startsWith(`${LOCAL_ORIGIN}/`) && reqUrl !== LOCAL_ORIGIN) {
            return null;
          }

          let relativePath = reqUrl.substring(LOCAL_ORIGIN.length);
          if (relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1);
          }
          relativePath = relativePath.split('?')[0].split('#')[0];

          try {
            relativePath = decodeURIComponent(relativePath);
          } catch (e) {
            // 忽略 URI 解码异常
          }

          if (!relativePath || relativePath === '') {
            relativePath = 'index.html';
          }

          // 1. 优先尝试直接从 rawfile 读取文件
          // 显式标注类型：ArkTS 不接受推断出的 any/unknown（arkts-no-any-unknown）
          const directFile: webview.WebResourceResponse | null = this.loadRawFile(relativePath);
          if (directFile) {
            return directFile;
          }

          // 2. SPA 路由回退：非静态文件请求（无文件扩展名，如 /ledger, /login, /dashboard）回退返回 index.html
          if (!relativePath.includes('.')) {
            const spaIndex: webview.WebResourceResponse | null = this.loadRawFile('index.html');
            if (spaIndex) {
              return spaIndex;
            }
          }

          hilog.warn(DOMAIN, TAG, 'Rawfile resource not found: %{public}s', relativePath);
          return null;
        })
        .onConsole((event) => {
          if (event) {
            hilog.info(DOMAIN, TAG, 'WebConsole: %{public}s', event.message.getMessage());
          }
          return false;
        })
        .onErrorReceive((event) => {
          if (event) {
            hilog.error(DOMAIN, TAG, 'WebError: %{public}s, code: %{public}d',
              event.error.getErrorInfo(), event.error.getErrorCode());
          }
        })
        .onHttpErrorReceive((event) => {
          if (event) {
            hilog.error(DOMAIN, TAG, 'WebHttpError: %{public}s, status: %{public}d',
              event.request.getRequestUrl(), event.response.getResponseCode());
          }
        })
        .onPageEnd(() => {
          this.pageReady = true;
          // 首屏也要有正确的避让区值，所以这里注入一次；
          // 之后旋转/键盘引起的实时更新走 onSafeAreaChange → injectSafeArea()，
          // 两条路径共用同一个 injectSafeArea()，避免首屏与后续行为不一致。
          this.injectSafeArea();
          // 注入能力桥对象（window.__suenmoney）+ 窗口级退出函数 + 平台标记，
          // 供 Web 侧决定「是不是鸿蒙、原生版本是多少、能不能退出」。
          this.injectNativeBridge();
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }
}
