/**
 * 环图（web PDonut 1:1）：stroke-dasharray 同款几何 —— r = size/2 - 12、
 * 环宽 16、每段留 2.5px 的缝、12 点方向起笔；环心是「标签 + 数值」两行。
 *
 * Canvas 不会自动重绘，父组件传 `signature`（数据指纹），@Watch 触发重画。
 */
import { ThemeTokens } from '../../common/theme/AppTheme';
import { fontDisplayOf, fontMonoOf } from '../../common/ui/UiStyle';

/** 环图一段（value 为绝对金额，图内按合计归一 —— 与 web sum 口径一致） */
export interface DonutSliceView {
  value: number;
  color: string;
}

@Component
export struct DonutChart {
  @Prop slices: DonutSliceView[] = [];
  @Prop tokens: ThemeTokens = {} as ThemeTokens;
  @Prop @Watch('redraw') signature: string = '';
  /** 直径（移动端报表 136，views.css:1146）；不能叫 size——会撞 CustomComponent.size() */
  @Prop ringSize: number = 136;
  /** 环心小标签（web donut-c-l） */
  @Prop centerLabel: string = '';
  /** 环心数值（web donut-c-v） */
  @Prop centerValue: string = '';
  @Prop isCyber: boolean = false;

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
    const radius = this.ringSize / 2 - 12;
    const lineWidth = 16;

    this.ctx.clearRect(0, 0, w, h);

    // 底环（surface-3）：没有任何数据时也要有形状
    this.ctx.beginPath();
    this.ctx.strokeStyle = this.tokens.surface3;
    this.ctx.lineWidth = lineWidth;
    this.ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    this.ctx.stroke();

    let sum = 0;
    for (const s of this.slices) {
      sum += Math.max(0, s.value);
    }
    if (sum <= 0) {
      return;
    }

    const circumference = 2 * Math.PI * radius;
    const gapAngle = 2.5 / radius; // web：dash 里减 2.5px 换算成弧度
    let start = -Math.PI / 2; // rotate(-90)：12 点方向起笔
    for (const s of this.slices) {
      const len = (Math.max(0, s.value) / sum) * circumference;
      if (len <= 2.5) {
        start += len / radius;
        continue;
      }
      const drawSweep = (len - 2.5) / radius;
      this.ctx.beginPath();
      this.ctx.strokeStyle = s.color;
      this.ctx.lineWidth = lineWidth;
      this.ctx.lineCap = 'butt';
      this.ctx.arc(cx, cy, radius, start, start + drawSweep);
      this.ctx.stroke();
      start += len / radius;
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
      // 环心：donut-c-l（9.5 mono 大写 + 0.14em）+ donut-c-v（21 display 800）
      Column({ space: 2 }) {
        if (this.centerLabel !== '') {
          Text(this.centerLabel)
            .fontSize(9.5)
            .letterSpacing(1.33)
            .fontFamily(fontMonoOf())
            .fontColor(this.tokens.ink3)
            .maxLines(1)
        }
        if (this.centerValue !== '') {
          Text(this.centerValue)
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber))
            .letterSpacing(-0.42)
            .fontColor(this.tokens.ink)
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(this.ringSize)
    .height(this.ringSize)
  }
}
