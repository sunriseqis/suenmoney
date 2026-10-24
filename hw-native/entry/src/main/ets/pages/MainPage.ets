/**
 * 主框架：四个入口 —— 流水 / 概况 / 报表 / 设置。
 *
 * 对齐移动 Web：**四个入口不变**（窄屏侧边栏折成横向条，原生用底部 Tab）。
 * 每个入口一个独立的屏组件，框架本身不持有业务状态 ——
 * 否则切 Tab 会把上一屏的加载态带进来。
 */
import { LedgerScreen } from '../components/ledger/LedgerScreen';
import { DashboardScreen } from '../components/dashboard/DashboardScreen';
import { ReportScreen } from '../components/report/ReportScreen';
import { SettingsScreen } from '../components/settings/SettingsScreen';
import { window } from '@kit.ArkUI';
import { THEME_STORAGE_KEY, ThemeManager } from '../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';
import { bodyFont } from '../common/theme/Fonts';

/** 底栏按钮参数（单参数对象：多参数 @Builder 不刷新） */
export interface TabItemView {
  label: string;
  selected: boolean;
}

@Entry
@Component
struct MainPage {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  @State currentTab: number = 0;
  /** 当前主题名（用来给底栏/标题选字体族） */
  @State themeIsCandy: boolean = ThemeManager.get().name === 'candy';

  aboutToAppear(): void {
    this.applySystemBars();
    // 主题在别的页面切换后回到这里要跟着变（同一个单例，读一次即可）
    this.themeIsCandy = this.themeName === 'candy';
  }

  /**
   * 状态栏跟主题走。
   *
   * 不设的话：浅色主题下状态栏仍是深色底，顶部像被切了一刀；
   * 内容色（时间/电量）也要反色，否则浅底白字看不见。
   */
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

  /** 底栏按钮：文字/选中色都取主题令牌，不用系统默认蓝 */
  @Builder
  tabBarItem($$: TabItemView) {
    Column({ space: 2 }) {
      Text($$.label)
        .fontSize(11)
        .fontWeight($$.selected ? FontWeight.Bold : FontWeight.Normal)
        .fontFamily(bodyFont(this.themeIsCandy))
        .fontColor($$.selected ? this.tok().ink : this.tok().ink3)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() {
        LedgerScreen()
      }
      .tabBar(this.tabBarItem({ label: '流水', selected: this.currentTab === 0 }))

      TabContent() {
        DashboardScreen()
      }
      .tabBar(this.tabBarItem({ label: '概况', selected: this.currentTab === 1 }))

      TabContent() {
        ReportScreen()
      }
      .tabBar(this.tabBarItem({ label: '报表', selected: this.currentTab === 2 }))

      TabContent() {
        SettingsScreen()
      }
      .tabBar(this.tabBarItem({ label: '设置', selected: this.currentTab === 3 }))
    }
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .barMode(BarMode.Fixed)
    .barBackgroundColor(this.tok().surface)
    .barHeight(56)
    .divider({ strokeWidth: 1, color: this.tok().line })
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
  }
}
