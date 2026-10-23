/**
 * H0 骨架页。
 *
 * 这一版**只验证底座**：主题令牌能编译、能切换、能持久化。
 * 业务页面（流水 / 记账 / 概况 / 报表 / 设置）从 H1 起按任务书逐屏做。
 */
import { ThemeManager, ThemeName } from '../common/theme/ThemeManager';
import { ThemeTokens } from '../common/theme/AppTheme';
import { VectorRunner } from '../common/contract/VectorRunner';
import { Db } from '../common/store/Db';
import { bodyFont, displayFont } from '../common/theme/Fonts';

@Entry
@Component
struct Index {
  @State tokens: ThemeTokens = CYBER_FALLBACK();
  @State themeName: ThemeName = 'cyber';
  /** H0-5 的上机证据：点一下跑 30 条向量，结果直接可贴进验收包 */
  @State vectorReport: string = '';
  /** H0-4 的上机证据：七张表与列名 */
  @State schemaReport: string = '';

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
        .fontFamily(displayFont(this.themeName === 'candy'))
        .fontColor(this.tokens.ink)

      Text('鸿蒙端 · H0 骨架')
        .fontSize(12)
        .fontFamily(bodyFont(this.themeName === 'candy'))
        .fontColor(this.tokens.ink3)

      Button('跑测试向量')
        .fontSize(12)
        .backgroundColor(this.tokens.surface2)
        .fontColor(this.tokens.ink)
        .onClick(() => {
          this.vectorReport = VectorRunner.runAll();
        })

      Button('看表结构')
        .fontSize(12)
        .backgroundColor(this.tokens.surface2)
        .fontColor(this.tokens.ink)
        .onClick(() => {
          Db.schemaReport()
            .then((text: string) => {
              this.schemaReport = text;
            })
            .catch((e: Error) => {
              this.schemaReport = `读表结构失败：${e.message}`;
            });
        })

      if (this.vectorReport !== '') {
        Text(this.vectorReport)
          .fontSize(10)
          .fontColor(this.tokens.ink2)
          .width('92%')
      }
      if (this.schemaReport !== '') {
        Text(this.schemaReport)
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('92%')
      }

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
