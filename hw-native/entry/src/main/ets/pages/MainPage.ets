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
import { ThemeManager } from '../common/theme/ThemeManager';
import { ThemeTokens } from '../common/theme/AppTheme';

@Entry
@Component
struct MainPage {
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  @State currentTab: number = 0;

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() {
        LedgerScreen()
      }
      .tabBar('流水')

      TabContent() {
        DashboardScreen()
      }
      .tabBar('概况')

      TabContent() {
        ReportScreen()
      }
      .tabBar('报表')

      TabContent() {
        SettingsScreen()
      }
      .tabBar('设置')
    }
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .barMode(BarMode.Fixed)
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens.bg)
  }
}
