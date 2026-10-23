/**
 * 环图（H5）：Canvas 自绘，不引图表库。
 *
 * 为什么自绘：这里只需要画圆弧，引库的成本（体积、样式对抗、生命周期）大于收益。
 * 为什么不用 SVG stroke-dasharray：ArkUI 没有 SVG；Canvas 直接按角度画弧更直接。
 *
 * 重绘触发：Canvas 不会自动重绘，所以父组件传一个 `signature`（数据指纹），
 * 变化时用 @Watch 重画。指纹比逐字段比较省事，也不会漏（金额/占比/颜色都进指纹）。
 */
import { ThemeTokens } from '../../common/theme/AppTheme';

export interface DonutSliceView {
  label: string;
  ratio: number;
  color: string;
}

@Component
export struct DonutChart {
  @Prop slices: DonutSliceView[] = [];
  @Prop tokens: ThemeTokens = {} as ThemeTokens;
  @Prop @Watch('redraw') signature: string = '';
  /** 环中间的文案（总支出） */
  @Prop centerLabel: string = '';

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  redraw(): void {
    this.draw();
  }

  private draw(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0) {
      return;
    }
    const cx = w / 2;
    const cy = h / 2;
    const radius = Math.min(w, h) / 2 - 10;
    const lineWidth = Math.max(10, radius * 0.34);

    this.ctx.clearRect(0, 0, w, h);

    // 先画底环：没有任何数据时也要有形状，否则页面会缺一块
    this.ctx.beginPath();
    this.ctx.strokeStyle = this.tokens.surface3;
    this.ctx.lineWidth = lineWidth;
    this.ctx.arc(cx, cy, radius - lineWidth / 2, 0, Math.PI * 2);
    this.ctx.stroke();

    let start = -Math.PI / 2; // 12 点方向起笔
    for (const slice of this.slices) {
      const ratio = Math.max(0, slice.ratio);
      if (ratio <= 0) {
        continue;
      }
      const sweep = Math.min(1, ratio) * Math.PI * 2;
      this.ctx.beginPath();
      this.ctx.strokeStyle = slice.color;
      this.ctx.lineWidth = lineWidth;
      this.ctx.lineCap = 'butt';
      this.ctx.arc(cx, cy, radius - lineWidth / 2, start, start + sweep);
      this.ctx.stroke();
      start += sweep;
      if (start >= Math.PI * 1.5) {
        break;
      }
    }

    if (this.centerLabel !== '') {
      this.ctx.fillStyle = this.tokens.ink;
      this.ctx.font = '14vp sans-serif';
      this.ctx.textAlign = 'center';
      this.ctx.textBaseline = 'middle';
      this.ctx.fillText(this.centerLabel, cx, cy);
    }
  }

  build() {
    Stack() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.draw();
        })
    }
    .width(160)
    .height(160)
  }
}
