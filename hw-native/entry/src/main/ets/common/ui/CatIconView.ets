/**
 * 分类图标渲染器：鸿蒙内置 Symbol（SymbolGlyph）。
 *
 * 旧的 `IconView`（Path 手绘 Lucide SVG 路径）在真机上描边发糊，已删除；
 * 系统符号字体任意字号都清晰、自带字重、跟随主题。
 *
 * 用法：`CatIconView({ catName: '餐饮', iconSize: 20, color: '#00ff88' })`
 * 名字不在内置表里（用户自建分类）自动落到兜底符号，不会出现空徽位。
 */
import { categorySymbolOf } from './CategoryIcon';

@Component
export struct CatIconView {
  /** 分类名（按名字命中内置符号；自建分类走兜底） */
  @Prop catName: string = '';
  /** 渲染边长（fp，SymbolGlyph 用 fontSize 控制大小，不要再套 scale） */
  @Prop iconSize: number = 20;
  /** 分类色（走 categoryColorOf 的 16 色槽结果） */
  @Prop color: string = '#000000';

  build() {
    SymbolGlyph(categorySymbolOf(this.catName))
      .fontSize(this.iconSize)
      // fontColor 收的是「数组」，不是单个颜色 —— 最容易写错的点
      .fontColor([this.color])
  }
}
