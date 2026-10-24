/**
 * 品牌徽标（docs R139）：**机身 + 显示屏（有内容、带指示灯） + 4×5 键盘**，三者缺一不可；
 * 亮起的键位拼出 `S`。三形态：≥32px 完整版 / <32px 简化版 / 单色版。
 *
 * 之前用 `layered_image` 直接贴图不满足 R139（缺显示屏与键盘的结构语义），这里用图形拼。
 */
import { THEME_STORAGE_KEY, ThemeManager } from '../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';

/** 4×5 键盘里需要点亮的位置（拼出 S） */
const LIT_KEYS: number[] = [0, 1, 2, 5, 8, 9, 10, 13, 16, 17, 18];

@Component
export struct BrandMark {
  @Prop markSize: number = 46;
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  build() {
    // 简化版（<32px）：只保留机身与显示屏，键位改为一条亮线
    if (this.markSize < 32) {
      Column({ space: 2 }) {
        Row().width('86%').height(this.markSize * 0.22).backgroundColor(this.tok().accent).borderRadius(1)
        Row().width('56%').height(this.markSize * 0.10).backgroundColor(this.tok().accentInk).borderRadius(1)
      }
      .width(this.markSize)
      .height(this.markSize)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.tok().ink)
      .borderRadius(this.markSize * 0.22)
    } else {
      Column({ space: this.markSize * 0.06 }) {
        // 显示屏：带指示灯 + 内容
        Row({ space: this.markSize * 0.06 }) {
          Row().width(this.markSize * 0.08).height(this.markSize * 0.08)
            .borderRadius(this.markSize * 0.04).backgroundColor(this.tok().accent)
          Row().width(this.markSize * 0.34).height(this.markSize * 0.07)
            .borderRadius(1).backgroundColor(this.tok().accent)
        }
        .width('84%')
        .height(this.markSize * 0.24)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ left: this.markSize * 0.06 })
        .backgroundColor(this.tok().accentInk)
        .borderRadius(this.markSize * 0.06)

        // 4×5 键盘：亮键拼 S
        Grid() {
          ForEach(KEY_INDEX, (i: number) => {
            GridItem() {
              Row()
                .width('100%')
                .height('100%')
                .backgroundColor(LIT_KEYS.indexOf(i) >= 0 ? this.tok().accent : this.tok().ink3)
                .borderRadius(1)
            }
          }, (i: number) => `k${i}`)
        }
        .columnsTemplate('repeat(4, 1fr)')
        .rowsTemplate('repeat(5, 1fr)')
        .columnsGap(1.5)
        .rowsGap(1.5)
        .width('84%')
        .layoutWeight(1)
      }
      .width(this.markSize)
      .height(this.markSize)
      .padding(this.markSize * 0.07)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.tok().ink)
      .borderRadius(this.markSize * 0.22)
    }
  }
}

const KEY_INDEX: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19];
