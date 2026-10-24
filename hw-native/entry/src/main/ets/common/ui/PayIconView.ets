/**
 * 支付方式图标渲染器。
 *
 * 两种渲染路径（旧的 Path 手绘已废弃）：
 * - 品牌图形（支付宝/微信/云闪付/京东/抖音）：随包 SVG 媒体资源 + `Image` 原生矢量解码，
 *   任意尺寸清晰，`fillColor` 染品牌色（SVG 内未写死填充色才能染）。
 * - 非品牌（银行卡/信用卡/现金/银行转账/其它钱包）：鸿蒙内置 Symbol + `SymbolGlyph`。
 *
 * 用法：`PayIconView({ payName: p.name, payIcon: p.icon ?? '', iconSize: 16, colorOverride: '' })`
 * `colorOverride` 非空时覆盖品牌色（选中态染 accentInk 用）；留空用 `resolvePayVisual` 的品牌色。
 */
import { PayVisual, resolvePayVisual } from './PaymentIcon';

@Component
export struct PayIconView {
  /** 支付方式名（判定顺序与 Web 一致：显式 icon > 按名反推 > 兜底银行卡） */
  @Prop payName: string = '';
  /** 数据库存储的显式 icon（PayIconId，可空串） */
  @Prop payIcon: string = '';
  /** 渲染边长（vp/fp） */
  @Prop iconSize: number = 16;
  /** 非空时覆盖品牌色 */
  @Prop colorOverride: string = '';

  private visual(): PayVisual {
    return resolvePayVisual(this.payName, this.payIcon);
  }

  private color(): string {
    return this.colorOverride !== '' ? this.colorOverride : this.visual().color;
  }

  build() {
    if (this.visual().svg) {
      Image(this.visual().res)
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.color())
    } else {
      SymbolGlyph(this.visual().res)
        .fontSize(this.iconSize)
        .fontColor([this.color()])
    }
  }
}
