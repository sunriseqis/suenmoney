/**
 * 概况屏（H4）。
 *
 * 对齐移动 Web 的 hero：
 *   期间档位 + 期间切换 → **大金额 + 环比** → **待办提醒条目（有则显示、无则隐藏）**
 *   → 三项指标 → 构成堆叠条 + 图例
 * 下面再挂：12 个月热力（点格下钻报表）+ 累计与跨度。
 *
 * 刻意不做：桌面形态的左右分栏、说明式文字（判据：这句话改变你要做什么吗）。
 */
import { Api, MonthlyReport, MonthPoint, PlanTodoItem, RollingMonth, SummaryReport, YearlyReport } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { displayFont, bodyFont } from '../../common/theme/Fonts';
import { CARD_PAD, cardRadiusOf, cardShadow, fontMonoOf, mixHex, radiusOf } from '../../common/ui/UiStyle';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, hashIndex } from '../../common/theme/Palette';
import { formatYuan, daysUntil, urgencyLabel } from '../../common/contract/Contract';

export interface TodoView {
  id: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  repaymentDate: string;
  willAutoPost: boolean;
  tone: string;
  label: string;
}

@Component
export struct DashboardScreen {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 0=按月 1=按年 2=全部 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  @State anchorYear: string = currentMonthKey().substring(0, 4);

  @State totalCents: number = 0;
  @State count: number = 0;
  @State prevTotalCents: number = -1;
  @State perDayCents: number = 0;
  @State creditDueCents: number = 0;

  @State monthReport: MonthlyReport | null = null;
  @State yearReport: YearlyReport | null = null;
  @State summary: SummaryReport | null = null;

  @State todos: TodoView[] = [];
  @State todoOpen: boolean = false;
  @State loading: boolean = false;
  @State errorText: string = '';
  @State offline: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      await this.loadTier();
      this.offline = false;
    } catch (e) {
      const err = e as ApiError;
      this.offline = err.kind === 'network';
      this.errorText = this.offline ? '离线：仅显示服务端上次返回的数据' : err.message;
    } finally {
      this.loading = false;
    }
  }

  private async loadTier(): Promise<void> {
    if (this.tier === 0) {
      const body = await Api.monthlyReport(this.anchorMonth);
      this.monthReport = body.report;
      this.totalCents = body.report.totalCents;
      this.count = body.report.count;
      // 环比：取近 12 月里上一个月
      const prev = this.prevMonthPoint(body.report.rolling12Months, this.anchorMonth);
      this.prevTotalCents = prev === null ? -1 : prev.totalCents;
      const dayCount = dayOfMonth();
      this.perDayCents = dayCount > 0 ? Math.round(body.report.totalCents / dayCount) : 0;
      this.creditDueCents = pendingCreditSum(body.report);
    } else if (this.tier === 1) {
      const body = await Api.yearlyReport(this.anchorYear);
      this.yearReport = body.report;
      this.totalCents = body.report.totalCents;
      this.count = body.report.count;
      this.prevTotalCents = -1;
      this.perDayCents = 0;
      this.creditDueCents = 0;
    } else {
      const body = await Api.summaryReport();
      this.summary = body.report;
      this.totalCents = body.report.totalCents;
      this.count = body.report.count;
      this.prevTotalCents = -1;
      this.perDayCents = body.report.monthlyAverageCents;
      this.creditDueCents = 0;
    }
  }

  private async actTodo(todo: TodoView, action: string): Promise<void> {
    try {
      if (action === 'skip') {
        await Api.skipTodo(todo.id);
      } else if (todo.willAutoPost) {
        await Api.ackTodo(todo.id);
      } else {
        await Api.confirmTodo(todo.id);
      }
      await this.reload();
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.message;
    }
  }

  private prevMonthPoint(points: RollingMonth[], month: string): MonthPoint | null {
    for (const p of points) {
      if (p.month === prevMonthKey(month)) {
        return { month: p.month, totalCents: p.totalCents ?? 0, count: p.count };
      }
    }
    return null;
  }

  /**
   * 预计月末（R69）：每月**前 3 天不显示**（数据太少），显示 `—` 并注明；
   * 其余日期按"已过 N 天"线性外推。
   */
  private monthEndEstimate(): string {
    const day = new Date().getDate();
    if (day <= 3) {
      return '—';
    }
    const lastDay = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).getDate();
    return formatYuan(Math.round((this.totalCents / day) * lastDay));
  }

  private deltaRatio(): number | null {
    if (this.prevTotalCents <= 0) {
      return null;
    }
    return (this.totalCents - this.prevTotalCents) / this.prevTotalCents;
  }

  private shiftMonth(delta: number): void {
    this.anchorMonth = shiftMonthKey(this.anchorMonth, delta);
    this.loading = true;
    this.reload().then(() => {
      this.loading = false;
    });
  }

  @Builder
  hero() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        this.tierButton({ label: '月', value: 0 })
        this.tierButton({ label: '年', value: 1 })
        this.tierButton({ label: '全部', value: 2 })
        Blank()
        if (this.tier === 0) {
          Button('‹')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.shiftMonth(-1);
            })
          Text(this.anchorMonth)
            .fontSize(11)
            .fontColor(this.tok().ink2)
          Button('›')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.shiftMonth(1);
            })
        }
      }
      .width('100%')

      // 提醒条**不在概况页**（R07/R116：行动层只在流水页顶卡），此处删除

      // 大金额 + 环比
      Row({ space: 6 }) {
        Text('¥')
          .fontSize(16)
          .fontColor(this.tok().ink3)
        Text(formatYuan(this.totalCents).replace('¥', ''))
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontFamily(displayFont(!this.isCyber()))
          .fontColor(this.tok().ink)
        if (this.deltaRatio() !== null) {
          Text(`${this.deltaRatio()! >= 0 ? '+' : '−'}${Math.abs(this.deltaRatio()! * 100).toFixed(1)}%`)
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink2)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), 999))
            .backgroundColor(mixHex(this.tok().accent, this.tok().surface, 0.12))
            .border({ width: 1.5, color: this.tok().accent })
        }
      }
      .width('100%')

      // 三项指标
      // R68：三子指标随档位变（月：日均/笔数/本月要还；年：月均/笔数/最高月；汇总：月均/笔数/记录天数）
      Row() {
        if (this.tier === 0) {
          this.metric({ label: '日均', value: formatYuan(this.perDayCents) })
          this.metric({ label: '笔数', value: `${this.count} 笔` })
          this.metric({ label: '预计月末', value: this.monthEndEstimate() })
        } else if (this.tier === 1) {
          this.metric({ label: '月均', value: formatYuan(Math.round(this.totalCents / 12)) })
          this.metric({ label: '笔数', value: `${this.count} 笔` })
          this.metric({ label: '最高月', value: this.yearReport!.peakMonth === null ? '—' : formatYuan(this.yearReport!.peakMonth.totalCents) })
        } else {
          this.metric({ label: '月均', value: formatYuan(this.perDayCents) })
          this.metric({ label: '笔数', value: `${this.count} 笔` })
          this.metric({ label: '记录天数', value: `${this.summary === null ? 0 : this.summary.recordedDays} 天` })
        }
      }
      .width('100%')

      // 构成堆叠条**不做**：分类构成是报表页的活（F09/D14）；视图里不出现任何分类名（R67）
    }
    .width('100%')
    .padding(CARD_PAD)
    .backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  @Builder
  tierButton($$: TierCell) {
    Button($$.label)
      .fontSize(11)
      .height(26)
      .backgroundColor(this.tier === $$.value ? this.tok().accent : this.tok().surface2)
      .fontColor(this.tier === $$.value ? this.tok().accentInk : this.tok().ink3)
      .onClick(() => {
        this.tier = $$.value;
        this.loading = true;
        this.reload().then(() => {
          this.loading = false;
        });
      })
  }

  /**
   * 指标格。
   *
   * **必须用单参数对象（$$）+ @Builder 引用传递**：ArkUI 的多参数 @Builder
   * 只在首帧求值一次，后续状态变化不会重绘 —— 这就是「合计对、笔数却是 0」
   * 的原因（数字是内联 Text 会刷新，笔数/日均走这个 Builder 就冻结了）。
   */
  @Builder
  metric($$: MetricCell) {
    Column({ space: 2 }) {
      Text($$.label)
        .fontSize(9)
        .fontColor(this.tok().ink3)
      Text($$.value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tok().ink)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 构成：一条堆叠条 + 前四条图例（不做环图 —— 环图是报表页的活） */
  @Builder
  heat() {
    Column({ space: 6 }) {
      Text('近 12 个月')
        .fontSize(10)
        .fontColor(this.tok().ink3)
        .width('100%')
      Grid() {
        ForEach(this.heatPoints(), (point: MonthPoint) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(point.month.substring(5, 7))
                .fontSize(9)
                .fontFamily(fontMonoOf())
                .fontColor(this.tok().ink3)
              Text(point.totalCents > 0 ? formatYuan(point.totalCents) : '—')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tok().ink)
                .maxLines(1)
              Column()
                .width('100%')
                .height(4)
                .backgroundColor(point.totalCents > 0
                  ? mixHex(this.tok().accent, this.tok().surface, this.heat4(point.totalCents, this.heatMean()))
                  : this.tok().surface3)
                .borderRadius(999)
            }
            .width('100%')
            .padding(6)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), 8))
            .border({ width: 1, color: this.tok().line })
          }
        }, (point: MonthPoint) => point.month)
      }
      .columnsTemplate('repeat(6, 1fr)')
      .columnsGap(6)
      .rowsGap(6)
      .height(2 * 50)
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  private heatPoints(): MonthPoint[] {
    const report = this.monthReport;
    if (report === null) {
      return [];
    }
    const out: MonthPoint[] = [];
    for (const p of report.rolling12Months) {
      out.push({ month: p.month, totalCents: p.totalCents ?? 0, count: p.count });
    }
    return out;
  }

  /** R70 四档（只用强调色明度，阈值相对均值） */
  private heat4(cents: number, mean: number): number {
    if (cents <= 0 || mean <= 0) {
      return 0;
    }
    const r = cents / mean;
    if (r >= 1.5) {
      return 0.42;
    }
    if (r >= 1.15) {
      return 0.24;
    }
    if (r >= 0.85) {
      return 0.12;
    }
    return 0.05;
  }

  private heatMean(): number {
    const list = this.heatPoints();
    if (list.length === 0) {
      return 0;
    }
    let sum = 0;
    for (const p of list) {
      sum += p.totalCents;
    }
    return sum / list.length;
  }

  private maxHeat(): number {
    let max = 0;
    for (const p of this.heatPoints()) {
      if (p.totalCents > max) {
        max = p.totalCents;
      }
    }
    return max;
  }

  /** 累计与跨度 */
  @Builder
  cumulative() {
    Column({ space: 6 }) {
      Text('累计')
        .fontSize(10)
        .fontColor(this.tok().ink3)
        .width('100%')
      // 累计条（R71）：**通栏一行、不含金额**，四项：已记 N 天 · M 笔 · 平均 A 笔/天 · 首笔日期
      Text(this.cumulativeLine())
        .fontSize(10.5)
        .fontColor(this.tok().ink3)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  /** 当前是深色（cyber）吗 —— 决定用 Orbitron 还是 Outfit */
  private isCyber(): boolean {
    return ThemeManager.get().name === 'cyber';
  }

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  /** 本月要还（R128）：信息层固定卡 —— 信用类合计 + 笔数 */
  @Builder
  creditCard() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('本月要还').fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
        Text(formatYuan(this.creditDueCents))
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(`信用类 ${this.creditCount()} 笔`)
        .fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
  }

  /** 信用类笔数（R128） */
  private creditCount(): number {
    if (this.monthReport === null) {
      return 0;
    }
    let n = 0;
    for (const p of this.monthReport.paymentMethods) {
      if (p.type === 'credit') {
        n += p.count;
      }
    }
    return n;
  }

  /** 进度对比卡（R73）：已过 N 天 + 日均 + 进度条（对近 3 个月日均） */
  @Builder
  progressCard() {
    Column({ space: 8 }) {
      Row() {
        this.metric({ label: '已过天数', value: `${new Date().getDate()} 天` })
        this.metric({ label: '本月日均', value: formatYuan(this.perDayCents) })
        this.metric({ label: '近 3 月日均', value: formatYuan(this.recent3Avg()) })
      }
      .width('100%')
      Stack({ alignContent: Alignment.Start }) {
        Row().width('100%').height(9).backgroundColor(this.tok().surface3).borderRadius(5)
        Row().width(`${this.progressPercent()}%`).height(9).backgroundColor(this.tok().accent).borderRadius(5)
      }
      .width('100%')
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
  }

  /** 近 3 个月日均（取 rolling12Months 里最近 3 个非空月） */
  private recent3Avg(): number {
    if (this.monthReport === null) {
      return 0;
    }
    const list = this.monthReport.rolling12Months;
    let sum = 0;
    let n = 0;
    for (let i = list.length - 1; i >= 0 && n < 3; i--) {
      const cents = list[i].totalCents ?? 0;
      if (cents > 0) {
        sum += cents;
        n += 1;
      }
    }
    return n > 0 ? Math.round(sum / n / 30) : 0;
  }

  /** 进度百分比：本月日均 / 近 3 月日均 */
  private progressPercent(): number {
    const base = this.recent3Avg();
    if (base <= 0) {
      return 0;
    }
    return Math.max(2, Math.min(100, Math.round((this.perDayCents / base) * 100)));
  }

  /** 累计条一句话（R71）：不含金额，只说量 */
  private cumulativeLine(): string {
    const s = this.summary;
    if (s === null) {
      return '—';
    }
    const days = s.recordedDays;
    const perDay = days > 0 ? (s.count / days).toFixed(1) : '0';
    return `已记 ${days} 天 · ${s.count} 笔 · 平均 ${perDay} 笔/天 · 首笔 ${s.firstDate ?? '—'}`;
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(10)
            .fontColor(this.offline ? this.tok().ink3 : this.tok().danger)
            .width('100%')
        }
        this.hero()
        if (this.tier === 0) {
          this.creditCard()
          this.progressCard()
          this.heat()
          if (this.summary === null) {
            Text('累计数据未加载')
              .fontSize(10)
              .fontColor(this.tok().ink3)
          } else {
            this.cumulative()
          }
        }
        if (this.loading) {
          Text('加载中…')
            .fontSize(10)
            .fontColor(this.tok().ink3)
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
    .onAppear(() => {
      // 累计数据单独取一次（与月档无关）
      Api.summaryReport().then((body) => {
        this.summary = body.report;
      }).catch(() => {
      });
    })
  }
}

/** @Builder 单参数对象（见 metric 的注释） */
export interface TierCell {
  label: string;
  value: number;
}

export interface MetricCell {
  label: string;
  value: string;
}

/** 报表里的分类桶（服务端返回，字段与 MonthlyReport.categories 一致） */
interface CategoryBucketView {
  categoryId: string;
  name: string;
  icon: string;
  color: string;
  cents: number;
  count: number;
  ratio: number;
}

/** 待办里的信用还款合计：用支付方式维度里 type=credit 的部分估算 */
function pendingCreditSum(report: MonthlyReport): number {
  let sum = 0;
  for (const p of report.paymentMethods) {
    if (p.type === 'credit') {
      sum += p.cents;
    }
  }
  return sum;
}

function heatOpacity(value: number, max: number): number {
  if (max <= 0) {
    return 0.08;
  }
  const r = value / max;
  return 0.08 + r * 0.82;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function currentMonthKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}`;
}

function todayKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
}

function dayOfMonth(): number {
  return new Date().getDate();
}

function shiftMonthKey(month: string, delta: number): string {
  const y = Number(month.substring(0, 4));
  const m = Number(month.substring(5, 7));
  const total = y * 12 + (m - 1) + delta;
  return `${Math.floor(total / 12)}-${pad2(total % 12 + 1)}`;
}

function prevMonthKey(month: string): string {
  return shiftMonthKey(month, -1);
}
