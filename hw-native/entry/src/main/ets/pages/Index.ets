/**
 * H0 骨架页。
 *
 * 这一版**只验证底座**：主题令牌能编译、能切换、能持久化。
 * 业务页面（流水 / 记账 / 概况 / 报表 / 设置）从 H1 起按任务书逐屏做。
 */
import { ThemeManager, ThemeName } from '../common/theme/ThemeManager';
import { ThemeTokens } from '../common/theme/AppTheme';

@Entry
@Component
struct Index {
  @State tokens: ThemeTokens = CYBER_FALLBACK();
  @State themeName: ThemeName = 'cyber';

  aboutToAppear(): void {
    const mgr = ThemeManager.get();
    this.themeName = mgr.name;
    this.tokens = mgr.tokens;
  }

  build() {
    Column({ space: 12 }) {
      Text('SuenMoney')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tokens.ink)

      Text('鸿蒙端 · H0 骨架')
        .fontSize(12)
        .fontColor(this.tokens.ink3)

      Row({ space: 10 }) {
        Button('水果硬糖')
          .fontSize(12)
          .backgroundColor(this.themeName === 'candy' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.themeName === 'candy' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            ThemeManager.get().set('candy');
            this.themeName = 'candy';
            this.tokens = ThemeManager.get().tokens;
          })
        Button('赛博朋克')
          .fontSize(12)
          .backgroundColor(this.themeName === 'cyber' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.themeName === 'cyber' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            ThemeManager.get().set('cyber');
            this.themeName = 'cyber';
            this.tokens = ThemeManager.get().tokens;
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.tokens.bg)
  }
}

/** 首帧兜底：aboutToAppear 之前先给深色，避免白闪 */
function CYBER_FALLBACK(): ThemeTokens {
  return ThemeManager.get().tokens;
}
