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
import { window } from '@kit.ArkUI';

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
    }).catch(() => {
    });
  }

  /** 品牌条（web 移动端 .sidebar）：LOGO 32 + 品牌名 15；nav / 副标题 / side-foot 全部关掉 */
  @Builder
  brandBar() {
    Row({ space: 10 }) {
      BrandMark({ markSize: 32 })
      Text('SuenMoney')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .fontColor(this.tok().ink)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 6 })
    .backgroundColor(this.tok().bg)
    .border({ width: { bottom: 1 }, color: this.tok().line })
    .onClick(() => {
      AppStorage.setOrCreate(SCREEN_STORAGE_KEY, 'ledger');
    })
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
      // 非流水页：‹ 返回流水（web goBack：移动端落地页无处可返回）
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

      // topbar-actions（gap 9）：主题切换 + 记一笔
      Row({ space: 9 }) {
        // 主题切换（web toggleTheme：cyber→light，其余→dark）；图标 ☀/☾ 文本字形
        Text(this.isCyber() ? '☀' : '☾')
          .fontSize(16)
          .fontColor(this.tok().ink2)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .border({ width: this.tok().borderW, color: this.tok().line })
          .onClick(() => {
            ThemeManager.get().setMode(this.isCyber() ? 'light' : 'dark');
          })

        // 记一笔（web PBtn variant="primary" icon=Plus）：
        // candy = accent 底 + 3px3px 硬阴影；cyber = accent 底 + #04170d 字 + 绿光（app.css:263）
        Row({ space: 7 }) {
          Text('+')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isCyber() ? '#04170d' : this.tok().accentInk)
          Text('记一笔')
            .fontSize(this.isCyber() ? 11 : 12.5)
            .fontWeight(FontWeight.Bold)
            .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
            .letterSpacing(this.isCyber() ? 1.54 : 0)
            .fontColor(this.isCyber() ? '#04170d' : this.tok().accentInk)
        }
        .alignItems(VerticalAlign.Center)
        .height(38)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.tok().accent)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .border({
          width: this.tok().borderW,
          color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
        })
        .shadow(this.isCyber()
          ? { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,255,136,0.35)' } as ShadowOptions
          : parseShadow('3px 3px 0 #1E293B') as ShadowOptions)
        .onClick(() => {
          this.openCreate();
        })
      }
      .alignItems(VerticalAlign.Center)
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
  @StorageLink('pendingSync') pendingSync: number = 0;
  @StorageLink('offline') offline: boolean = false;

  /** build-stamp（App.vue:247）：主题 + 档位 + 记录条数 + 离线/待同步 N */
  private stampText(): string {
    let out = 'SuenMoney · 单账本家庭记账';
    const pend = this.pendingSync;
    if (pend > 0) {
      out += ` · 待同步 ${pend}`;
    } else if (this.offline) {
      out += ' · 离线';
    }
    return out;
  }

  /** 底部构建戳：含离线/待同步内联提示（C.1） */
  @Builder
  stamp() {
    Text(this.stampText())
      .fontSize(9)
      .fontFeature('"tnum" on')
      .fontFamily(fontBodyOf(this.isCyber()))
      .fontColor(this.tok().ink3)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 10 })
  }

  build() {
    Column() {
      this.brandBar()
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
        this.stamp()
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 64 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
  }
}
