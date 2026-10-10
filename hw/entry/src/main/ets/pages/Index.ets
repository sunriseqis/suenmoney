import { webview } from '@kit.ArkWeb';
import { bundleManager } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'SuenMoney_IndexPage';
const DOMAIN = 0x0000;

class HarmonyBridge {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  // 获取当前原生应用版本号
  getAppVersion(): string {
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return JSON.stringify({
        versionName: bundleInfo.versionName,
        versionCode: bundleInfo.versionCode,
        platform: 'harmony_next'
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get bundle info: %{public}s', JSON.stringify(err));
      return JSON.stringify({
        versionName: '1.0.0',
        versionCode: 1,
        platform: 'harmony_next'
      });
    }
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

  // 平台标识
  isNativePlatform(): boolean {
    return true;
  }

  getPlatform(): string {
    return 'harmony_next';
  }
}

@Entry
@Component
struct Index {
  private webviewController: webview.WebviewController = new webview.WebviewController();
  @StorageProp('topAvoidHeight') topAvoidHeight: number = 0;
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 0;
  private bridge: HarmonyBridge = new HarmonyBridge(getContext(this) as common.UIAbilityContext);

  // 拦截系统返回手势/返回键：优先让网页后退
  onBackPress(): boolean {
    if (this.webviewController.accessBackward()) {
      this.webviewController.backward();
      return true;
    }
    return false;
  }

  build() {
    Column() {
      Web({
        src: $rawfile('index.html'),
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
          methodList: ['getAppVersion', 'openInBrowser', 'isNativePlatform', 'getPlatform'],
          controller: this.webviewController
        })
        .onPageEnd(() => {
          // 注入安全区高度与平台全局标记
          const topPx = px2vp(this.topAvoidHeight);
          const bottomPx = px2vp(this.bottomAvoidHeight);
          const injectScript = `
            document.documentElement.style.setProperty('--safe-top', '${topPx}px');
            document.documentElement.style.setProperty('--safe-bottom', '${bottomPx}px');
            window.__HARMONY_NEXT__ = true;
          `;
          try {
            this.webviewController.runJavaScript(injectScript);
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'Failed to inject CSS safe area: %{public}s', JSON.stringify(e));
          }
        })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }
}
