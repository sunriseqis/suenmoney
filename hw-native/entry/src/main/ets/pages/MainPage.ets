/**
 * 移动外壳（规范 §3）。
 *
 * **没有底部导航**：Web 移动端把 `.sidebar .nav` 整条关掉（views.css:1115），
 * 导航只有两处 —— 流水页 hero 里的三个小入口（概况/报表/设置）+ 其余屏的顶栏返回按钮。
 * 之前我自造的 4-Tab 底栏是错的，必须去掉。
 *
 * 结构：sticky 品牌条 → 顶栏（流水页整条不渲染）→ 内容区 → build-stamp → Toast / 记账抽屉
 */
import { window } from '@kit.ArkUI';

import { LedgerScreen } from '../components/ledger/LedgerScreen';
import { DashboardScreen } from '../components/dashboard/DashboardScreen';
import { ReportScreen } from '../components/report/ReportScreen';
import { SettingsScreen } from '../components/settings/SettingsScreen';
import { BrandMark } from '../components/BrandMark';
import { THEME_STORAGE_KEY, ThemeManager } from '../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';
import { fontBodyOf, fontDisplayOf, parseShadow, radiusOf } from '../common/ui/UiStyle';
import { ensureFonts } from '../common/theme/FontRegistry';

/** 屏标识（顺序无关，仅作路由键） */
export type ScreenKey = 'ledger' | 'dashboard' | 'report' | 'settings';

@Entry
@Component
struct MainPage {
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  @State screen: ScreenKey = 'ledger';

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

  /** 品牌条：46×46 图标 + 15px 品牌名；副标题在移动端隐藏（app.css:736） */
  @Builder
  brandBar() {
    Row({ space: 10 }) {
      BrandMark()
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
  }

  /**
   * 二级页标题行（docs R17/R18/R19）：
   * `设置                    ×` —— 关闭键收在**标题行行尾**，不单独占一行、**不吸顶**、19px、--fg-muted。
   * 用 `×`（关闭这个页面）而不是 `‹`（返回上一页）：我们的场景是前者。
   */
  @Builder
  titleRow() {
    Row() {
      Text(this.titleOf())
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .fontColor(this.tok().ink3)
      Blank()
      Text('×')
        .fontSize(19)
        .fontColor(this.tok().ink3)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.screen = 'ledger';
        })
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 6, bottom: 2 })
  }

  private titleOf(): string {
    if (this.screen === 'dashboard') {
      return '概况';
    }
    if (this.screen === 'report') {
      return '报表';
    }
    return '设置';
  }

  /** 底部构建戳：含离线/待同步内联提示（C.1） */
  @Builder
  stamp() {
    Text(`SuenMoney · 单账本家庭记账`)
      .fontSize(9)
      .fontFamily(fontBodyOf(this.isCyber()))
      .fontColor(this.tok().ink3)
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 10 })
  }

  build() {
    Column() {
      this.brandBar()
      if (this.screen !== 'ledger') {
        this.titleRow()
      }
      Column() {
        if (this.screen === 'ledger') {
          LedgerScreen({
            onNavigate: (target: string) => {
              this.screen = target as ScreenKey;
            }
          })
        } else if (this.screen === 'dashboard') {
          DashboardScreen()
        } else if (this.screen === 'report') {
          ReportScreen()
        } else {
          SettingsScreen()
        }
        this.stamp()
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
  }
}
