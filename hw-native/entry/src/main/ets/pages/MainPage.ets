/**
 * 主框架（H1）：四个入口 —— 流水 / 概况 / 报表 / 设置。
 *
 * 对齐移动 Web：**四个入口不变**（侧边栏在窄屏折叠成横向条，原生用底部 Tab）。
 * H1 只做框架与设置里的两个开关（主题、登出），业务页面从 H2 起逐屏填。
 */
import { router } from '@kit.ArkUI';

import { AuthStore } from '../common/auth/AuthStore';
import { VectorRunner } from '../common/contract/VectorRunner';
import { Db } from '../common/store/Db';
import { ThemeManager, ThemeName } from '../common/theme/ThemeManager';
import { ThemeTokens } from '../common/theme/AppTheme';
import { bodyFont, displayFont } from '../common/theme/Fonts';

@Entry
@Component
struct MainPage {
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  @State themeName: ThemeName = ThemeManager.get().name;
  @State currentTab: number = 0;
  /** 底座自检：向量结果与表结构（真机验收时截图用） */
  @State vectorReport: string = '';
  @State schemaReport: string = '';

  private async switchTheme(name: ThemeName): Promise<void> {
    await ThemeManager.get().set(name);
    this.themeName = name;
    this.tokens = ThemeManager.get().tokens;
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
        TabContent() {
          this.placeholder('流水', 'H2')
        }
        .tabBar('流水')

        TabContent() {
          this.placeholder('概况', 'H4')
        }
        .tabBar('概况')

        TabContent() {
          this.placeholder('报表', 'H5')
        }
        .tabBar('报表')

        TabContent() {
          Column({ space: 14 }) {
            Text('设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontFamily(displayFont(this.themeName === 'candy'))
              .fontColor(this.tokens.ink)

            Text('主题')
              .fontSize(11)
              .fontColor(this.tokens.ink3)
              .width('100%')

            Row({ space: 10 }) {
              Button('水果硬糖')
                .fontSize(12)
                .backgroundColor(this.themeName === 'candy' ? this.tokens.accent : this.tokens.surface2)
                .fontColor(this.themeName === 'candy' ? this.tokens.accentInk : this.tokens.ink2)
                .onClick(() => {
                  this.switchTheme('candy');
                })
              Button('赛博朋克')
                .fontSize(12)
                .backgroundColor(this.themeName === 'cyber' ? this.tokens.accent : this.tokens.surface2)
                .fontColor(this.themeName === 'cyber' ? this.tokens.accentInk : this.tokens.ink2)
                .onClick(() => {
                  this.switchTheme('cyber');
                })
            }
            .width('100%')

            Text('底座自检')
              .fontSize(11)
              .fontColor(this.tokens.ink3)
              .width('100%')

            Row({ space: 10 }) {
              Button('跑测试向量')
                .fontSize(12)
                .backgroundColor(this.tokens.surface2)
                .fontColor(this.tokens.ink2)
                .onClick(() => {
                  this.vectorReport = VectorRunner.runAll();
                })
              Button('看表结构')
                .fontSize(12)
                .backgroundColor(this.tokens.surface2)
                .fontColor(this.tokens.ink2)
                .onClick(() => {
                  Db.schemaReport()
                    .then((text: string) => {
                      this.schemaReport = text;
                    })
                    .catch((e: Error) => {
                      this.schemaReport = `读表结构失败：${e.message}`;
                    });
                })
            }
            .width('100%')

            if (this.vectorReport !== '') {
              Text(this.vectorReport)
                .fontSize(10)
                .fontColor(this.tokens.ink2)
                .width('100%')
            }
            if (this.schemaReport !== '') {
              Text(this.schemaReport)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
                .width('100%')
            }

            Button('退出登录')
              .fontSize(12)
              .height(40)
              .backgroundColor(this.tokens.surface2)
              .fontColor(this.tokens.danger)
              .onClick(() => {
                AuthStore.logout().then(() => {
                  router.replaceUrl({ url: 'pages/LoginPage' });
                });
              })
          }
          .width('100%')
          .padding(20)
          .alignItems(HorizontalAlign.Start)
        }
        .tabBar('设置')
      }
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .barMode(BarMode.Fixed)
      .backgroundColor(this.tokens.bg)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens.bg)
  }

  /** H1 的占位块：只说明「这一屏在哪个阶段做」，不放假内容 */
  @Builder
  placeholder(title: string, stage: string) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontFamily(displayFont(this.themeName === 'candy'))
        .fontColor(this.tokens.ink)
      Text(`${stage} 阶段实现`)
        .fontSize(12)
        .fontFamily(bodyFont(this.themeName === 'candy'))
        .fontColor(this.tokens.ink3)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
