/**
 * 移动外壳 —— 照 Web 移动端现状（App.vue ≤860px + views.css:1112 覆盖段）1:1 复刻。
 *
 * 结构（自上而下）：
 *   sidebar  横向品牌条：nav 整条关掉（views.css:1115），只剩品牌位；点品牌回流水（App.vue RouterLink）
 *   topbar   **所有屏都渲染**（App.vue:210，流水页只是没有返回键）：
 *            非流水页 ‹ 返回 + 15px 标题 + 主题切换 + 「记一笔」主按钮（App.vue:228）
 *   content  padding 6/12/64（views.css:1121）、gap 12（app.css:757）
 *   build-stamp 底部构建戳（离线/待同步内联）
 *
 * 记账入口两个：topbar「记一笔」按钮 + 流水页下拉手势（LedgerScreen 内实现）。
 * 跨屏「记一笔」管线：先切回流水屏，再延迟写 createRequest，流水屏 @Watch 打开抽屉。
 */
import { display, window } from '@kit.ArkUI';

import { LedgerScreen } from '../components/ledger/LedgerScreen';
import { DashboardScreen } from '../components/dashboard/DashboardScreen';
import { AnnualScreen } from '../components/report/AnnualScreen';
import { ReportScreen } from '../components/report/ReportScreen';
import { SettingsScreen } from '../components/settings/SettingsScreen';
import { BrandMark } from '../components/BrandMark';
import { THEME_STORAGE_KEY, ThemeManager } from '../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';
import { fontBodyOf, fontDisplayOf, fontMonoOf, parseShadow, radiusOf } from '../common/ui/UiStyle';
import { ensureFonts } from '../common/theme/FontRegistry';

/** 屏标识（顺序无关，仅作路由键） */
export type ScreenKey = 'ledger' | 'dashboard' | 'report' | 'annual' | 'settings';
/** 当前屏：放 AppStorage，流水页的入口直接写它（回调传参在 ArkUI 里不稳） */
export const SCREEN_STORAGE_KEY = 'activeScreen';

@Entry
@Component
struct MainPage {
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  @StorageLink(SCREEN_STORAGE_KEY) screen: string = 'ledger';
  /** 沉浸式后状态栏高度（vp），顶部自己补；底部不再为手势条留白 */
  @StorageLink('statusBarVp') statusBarVp: number = 0;

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  aboutToAppear(): void {
    ensureFonts(this.getUIContext());
    this.applySystemBars();
  }

  /** 状态栏跟随主题（不设的话浅色主题顶部仍是深色，像被切了一刀） */
  private applySystemBars(): void {
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      win.setWindowSystemBarProperties({
        statusBarColor: this.tok().bg,
        statusBarContentColor: this.tok().ink,
        navigationBarColor: this.tok().bg,
        navigationBarContentColor: this.tok().ink
      });
      // 沉浸式：窗口铺满整屏，否则系统会在底部留一条手势避让区，
      // 本应用没有底部 tab，那条留白纯属浪费（实测吃掉 ~110px，列表少显示一行）。
      win.setWindowLayoutFullScreen(true);
      // 沉浸式之后状态栏区域要靠自己补内边距，先量出来
      const avoid = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const density = display.getDefaultDisplaySync().densityPixels;
      AppStorage.setOrCreate('statusBarVp', avoid.topRect.height / density);
    }).catch(() => {
    });
  }


  /** 顶栏标题（web PAGE_META；sub 在移动端隐藏 app.css:756） */
  private topTitle(): string {
    if (this.screen === 'dashboard') {
      return '概况';
    }
    if (this.screen === 'ledger') {
      return '流水';
    }
    if (this.screen === 'report') {
      return '报表';
    }
    if (this.screen === 'annual') {
      return '年度报告';
    }
    return '设置';
  }

  /** 顶栏 ‹ 的返回目的地：年度报告回报表（web history.back 落报表），其余回流水 */
  private backTarget(): string {
    return this.screen === 'annual' ? 'report' : 'ledger';
  }

  /**
   * 顶栏（web .topbar，移动端 views.css:1118：padding 8 12、gap 8、标题 15px）。
   * 流水页也渲染（topbar--bare 只影响返回键的有无，样式无差别）。
   */
  @Builder
  topBar() {
    Row({ space: 8 }) {
      // 流水页不渲染顶栏（用户裁决）；其余屏只留返回键 + 标题，保证能回到流水。
      if (this.screen !== 'ledger') {
        Text('‹')
          .fontSize(20)
          .fontColor(this.tok().ink2)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .border({ width: this.tok().borderW, color: this.tok().line })
          .onClick(() => {
            AppStorage.setOrCreate(SCREEN_STORAGE_KEY, this.backTarget());
          })
      }

      // topbar-title：15px；cyber 大写 + 0.12em 字距 + 绿光（app.css:191）
      Text(this.topTitle())
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .letterSpacing(this.isCyber() ? 1.8 : 0)
        .fontColor(this.tok().ink)
        .maxLines(1)

      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.tok().bg)
    .border({ width: { bottom: 1 }, color: this.tok().line })
  }

  /**
   * 「记一笔」跨屏管线：流水屏持有记账抽屉，别屏点击时先切屏、
   * 再延迟写 createRequest（等 LedgerScreen 挂载完 @Watch 才能收到）。
   */
  private openCreate(): void {
    if (this.screen !== 'ledger') {
      AppStorage.setOrCreate(SCREEN_STORAGE_KEY, 'ledger');
    }
    setTimeout(() => {
      AppStorage.setOrCreate('createRequest', Date.now());
    }, 200);
  }

  /** 下拉提示（web .pull-hint，app.css:683/761）：30×14 胶囊箭头 + mono 9.5 说明 */
  @Builder
  pullHint() {
    Row({ space: 6 }) {
      Text('⌄')
        .fontSize(10)
        .fontColor(this.tok().ink3)
        .width(30)
        .height(14)
        .textAlign(TextAlign.Center)
        .border({ width: 1, color: this.tok().line })
        .borderRadius(this.tok().rPill)
      Text('下拉记一笔')
        .fontSize(9.5)
        .letterSpacing(1.52)
        .fontFamily(fontMonoOf())
        .fontColor(this.tok().ink3)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 待同步条数与离线态：从 AppStorage 订阅，LedgerScreen 维护 */
  @StorageLink('offline') offline: boolean = false;


  /** 底部构建戳：含离线/待同步内联提示（C.1） */

  build() {
    Column() {
      // 顶部品牌条与标题栏按用户裁决**整条不渲染**：
      // logo / SuenMoney / 页面标题 / 主题切换 / 记一笔 全部去掉，
      // 流水页直接从内容开始（主题切换在设置页，记一笔走下拉手势）。
      this.topBar()
      // content：padding 6/12/64（views.css:1121）、gap 12（app.css:757）
      Column({ space: 12 }) {
        if (this.screen === 'ledger') {
          this.pullHint()
        }
        Column() {
          if (this.screen === 'ledger') {
            LedgerScreen()
          } else if (this.screen === 'dashboard') {
            DashboardScreen()
          } else if (this.screen === 'report') {
            ReportScreen()
          } else if (this.screen === 'annual') {
            AnnualScreen()
          } else {
            SettingsScreen()
          }
        }
        .layoutWeight(1)
        .width('100%')
        // 品牌页脚**不渲染**：Web 移动端 `@media (max-width:860px) .side-foot{display:none}`（app.css:741），
        // 之前无条件渲染，等于在手机底部固定吃掉 ~105px，把列表挤成一行。
      }
      .layoutWeight(1)
      .width('100%')
      // 顶部补状态栏高度（沉浸式后要自己补；流水页没有顶栏挡着，必须落在这里）
      // 底部留 12（Web 的 64 是浏览器滚动留白，原生端没有浏览器，照抄会把列表压掉一行）
      .padding({ left: 12, right: 12, top: 6 + this.statusBarVp, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
    // 本应用没有底部 tab，底部只需要让背景铺到物理边缘，不再为手势条留白
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
