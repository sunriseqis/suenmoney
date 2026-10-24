/**
 * 矢量图标（Lucide + 支付品牌）。
 *
 * Web 端用 `<component :is="LucideIcon">` 渲染 Lucide 组件；鸿蒙端没有随包的图标资产，
 * 但 ArkUI 的 `Path` 组件**直接吃 SVG 的 `d` 字符串**，配合 `stroke` 运行时可染 ——
 * 所以不需要把图标转成字体，也不需要 PNG。
 *
 * 几何来自 `IconPaths.ets`（Lucide 由 `docs/design/icons/lucide/*.svg` 机械转换；
 * 支付品牌由 Web `payment-icons.ts` 归一化到同一 24 单位空间），形状与 Web 一致。
 *
 * 两个坑（都踩过，别再犯）：
 * 1. `fill(Color.Transparent)` **不能**表达"只描边"，会画成实心块 → 用 `fillOpacity(0)`。
 * 2. `Shape.viewPort` 的缩放实测不生效（图形按 24vp 原尺寸画，比徽位还大）→
 *    改成 `Path` 固定 24vp + `.scale(iconSize/24)`，这是确定性的。
 */
@Component
export struct IconView {
  /** SVG 的 path d（24 单位空间，可含多个子路径） */
  @Prop path: string = '';
  /** 渲染边长（vp） */
  @Prop iconSize: number = 20;
  /** 描边/填充色（运行时可染，分类色直接传进来） */
  @Prop color: string = '#000000';
  /** 描边宽度（24 单位空间内，Lucide 是 2） */
  @Prop strokeW: number = 2;
  /** true = 填充型（支付品牌 logo），false = 描边型（Lucide） */
  @Prop filled: boolean = false;

  build() {
    Stack() {
      Path()
        .commands(this.path)
        // 描边型必须真的"不填充"：`Color.Transparent` 与 `fillOpacity(0)` 实测都无效，
        // 只有 ARGB 全零（#00000000）才会被当成透明填充。
        .fill(this.filled ? this.color : '#00000000')
        .stroke(this.color)
        .strokeOpacity(this.filled ? 0 : 1)
        .strokeWidth(this.strokeW)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
        // ⚠ Path 的 commands 坐标单位是 **px**（不是 vp）—— 24 单位只画 24px。
        //   而 iconSize 是 vp，所以要换算：缩放比 = vp2px(iconSize) / (24 + 描边宽)；
//   除以 (24+描边) 是因为描边会向外扩 strokeW/2，实测不补这一项图标会大 8%。
        //   Path 的盒子也用 px 写死 24，这样 Stack 居中 + 围绕中心缩放才对得上。
        .width('24px')
        .height('24px')
        .scale({ x: vp2px(this.iconSize) / (24 + this.strokeW), y: vp2px(this.iconSize) / (24 + this.strokeW) })
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }
}
