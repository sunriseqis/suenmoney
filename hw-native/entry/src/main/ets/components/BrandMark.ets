/**
 * 品牌徽标（规范 §3）：46×46、圆角 12。
 *
 * 用应用自己的 layered_image（与桌面图标同源），不做文字占位 ——
 * Web 侧同样是 `img.brand-mark` 引真实图标。
 */
@Component
export struct BrandMark {
  build() {
    Image($r('app.media.layered_image'))
      .width(46)
      .height(46)
      .borderRadius(12)
      .objectFit(ImageFit.Cover)
  }
}
