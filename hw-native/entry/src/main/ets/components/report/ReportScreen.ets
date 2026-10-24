/**
 * 报表屏（H5）。
 *
 * 结构（对齐移动 Web 的「块纵向堆叠、块内两栏」）：
 *   report-head：档位 + 期间切换 + 三个事实（总支出 / 笔数 / 日均）
 *   report-compose：四维切换（分类 / 支付 / 记录人 / 节奏）+ 环图 + 明细
 *   涨跌榜：本期 vs 上期，按变化幅度排序
 *   还款节奏：信用卡账单与还款日
 *   年度报告：12 月走势 + 年度之最
 *
 * 一条硬规则（decisions）：**排名行中间必须有占比条** ——
 * 名称与金额摆两端、中间空一大块时，眼睛要横跨整行才能对上，数据排名不能这样。
 */
import { Api, CategoryBucket, DailyPoint, MonthlyReport, PaymentBucket, YearlyReport } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { displayFont, bodyFont } from '../../common/theme/Fonts';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, hashIndex } from '../../common/theme/Palette';
import { formatYuan } from '../../common/contract/Contract';
import { DonutChart, DonutSliceView } from './DonutChart';

@Component
export struct ReportScreen {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 0=月 1=年 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  @State anchorYear: string = currentMonthKey().substring(0, 4);
  /** 构成维度：0=分类 1=支付 2=记录人 3=节奏 */
  @State dim: number = 0;
  @State monthReport: MonthlyReport | null = null;
  @State yearReport: YearlyReport | null = null;
  @State loading: boolean = false;
  @State errorText: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      if (this.tier === 0) {
        const body = await Api.monthlyReport(this.anchorMonth);
        this.monthReport = body.report;
      } else {
        const body = await Api.yearlyReport(this.anchorYear);
        this.yearReport = body.report;
      }
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.kind === 'network' ? '离线：报表需要联网' : err.message;
    } finally {
      this.loading = false;
    }
  }

  // ── 四维数据 ────────────────────────────────────────────────────────────
  private slices(): DonutSliceView[] {
    const out: DonutSliceView[] = [];
    const report = this.monthReport;
    if (report === null) {
      return out;
    }
    if (this.dim === 0) {
      for (const c of report.categories) {
        out.push({ label: c.name, ratio: c.ratio, color: chartColor(this.tok(), hashIndex(c.categoryId)) });
      }
    } else if (this.dim === 1) {
      for (const p of report.paymentMethods) {
        out.push({ label: p.name, ratio: this.paymentRatio(p), color: chartColor(this.tok(), hashIndex(p.paymentMethodId)) });
      }
    } else if (this.dim === 2) {
      for (const m of report.members) {
        out.push({ label: m.name, ratio: m.ratio, color: chartColor(this.tok(), hashIndex(m.ownerId)) });
      }
    } else {
      // 节奏：把 31 天按周聚合成 5 段，避免环图碎成 31 片
      const weeks = this.weeklyPoints();
      const total = this.totalCents();
      for (let i = 0; i < weeks.length; i++) {
        out.push({
          label: `第 ${i + 1} 周`,
          ratio: total > 0 ? weeks[i] / total : 0,
          color: chartColor(this.tok(), i)
        });
      }
    }
    return out;
  }

  private totalCents(): number {
    return this.monthReport === null ? 0 : this.monthReport.totalCents;
  }

  private paymentRatio(p: PaymentBucket): number {
    const total = this.totalCents();
    return total > 0 ? p.cents / total : 0;
  }

  /** 31 天 → 5 段周合计 */
  private weeklyPoints(): number[] {
    const out: number[] = [0, 0, 0, 0, 0];
    const report = this.monthReport;
    if (report === null) {
      return out;
    }
    for (const d of report.daily) {
      const weekIndex = Math.min(4, Math.floor((d.day - 1) / 7));
      out[weekIndex] += d.cents;
    }
    return out;
  }

  private signature(): string {
    let s = `${this.dim}-${this.anchorMonth}-${this.totalCents()}-`;
    for (const slice of this.slices()) {
      s += `${slice.label}:${slice.ratio.toFixed(4)}:${slice.color};`;
    }
    return s;
  }

  // ── 涨跌榜 ──────────────────────────────────────────────────────────────
  private movers(): CategoryBucket[] {
    const report = this.monthReport;
    if (report === null) {
      return [];
    }
    const list: CategoryBucket[] = report.categories.slice();
    list.sort((a: CategoryBucket, b: CategoryBucket) => {
      const av = Math.abs((a.changeRatio ?? 0) * (a.previousCents ?? 0));
      const bv = Math.abs((b.changeRatio ?? 0) * (b.previousCents ?? 0));
      return bv - av;
    });
    return list.slice(0, 4);
  }

  @Builder
  head() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        this.tierButton({ label: '月', value: 0 })
        this.tierButton({ label: '年', value: 1 })
        Blank()
        if (this.tier === 0) {
          Button('‹')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.anchorMonth = shiftMonthKey(this.anchorMonth, -1);
              this.reload();
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
              this.anchorMonth = shiftMonthKey(this.anchorMonth, 1);
              this.reload();
            })
        } else {
          Button('‹')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.anchorYear = String(Number(this.anchorYear) - 1);
              this.reload();
            })
          Text(this.anchorYear)
            .fontSize(11)
            .fontColor(this.tok().ink2)
          Button('›')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.anchorYear = String(Number(this.anchorYear) + 1);
              this.reload();
            })
        }
      }
      .width('100%')

      Row() {
        this.fact({
          label: '总支出',
          value: formatYuan(this.tier === 0 ? this.totalCents() : (this.yearReport?.totalCents ?? 0))
        })
        this.fact({
          label: '笔数',
          value: `${this.tier === 0 ? (this.monthReport?.count ?? 0) : (this.yearReport?.count ?? 0)} 笔`
        })
        this.fact({ label: '日均', value: formatYuan(this.dailyAverage()) })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  private dailyAverage(): number {
    if (this.tier === 0) {
      const report = this.monthReport;
      if (report === null) {
        return 0;
      }
      return Math.round(report.totalCents / dayOfMonth());
    }
    const year = this.yearReport;
    if (year === null || year.months.length === 0) {
      return 0;
    }
    return Math.round(year.totalCents / (year.months.length * 30));
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
        this.reload();
      })
  }

  /** 单参数对象 + $$ 引用传递：多参数 @Builder 首帧后不再重绘（同概况页那个 bug） */
  @Builder
  fact($$: FactCell) {
    Column({ space: 2 }) {
      Text($$.label)
        .fontSize(9)
        .fontColor(this.tok().ink3)
      Text($$.value)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(displayFont(!this.isCyber()))
        .fontColor(this.tok().ink)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  compose() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        this.dimButton({ label: '分类', value: 0 })
        this.dimButton({ label: '支付', value: 1 })
        this.dimButton({ label: '记录人', value: 2 })
        this.dimButton({ label: '节奏', value: 3 })
      }
      .width('100%')

      Row({ space: 12 }) {
        DonutChart({
          slices: this.slices(),
          tokens: this.tok(),
          signature: this.signature(),
          centerLabel: formatYuan(this.totalCents())
        })
        Column({ space: 6 }) {
          ForEach(this.slices().slice(0, 6), (slice: DonutSliceView) => {
            Row({ space: 6 }) {
              Row()
                .width(8)
                .height(8)
                .backgroundColor(slice.color)
                .borderRadius(2)
              Text(slice.label)
                .fontSize(10)
                .fontColor(this.tok().ink2)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(`${(slice.ratio * 100).toFixed(0)}%`)
                .fontSize(10)
                .fontColor(this.tok().ink3)
            }
            .width('100%')
          }, (slice: DonutSliceView) => slice.label)
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  @Builder
  dimButton($$: TierCell) {
    Button($$.label)
      .fontSize(11)
      .height(26)
      .layoutWeight(1)
      .backgroundColor(this.dim === $$.value ? this.tok().surface3 : this.tok().surface2)
      .fontColor(this.dim === $$.value ? this.tok().ink : this.tok().ink3)
      .onClick(() => {
        this.dim = $$.value;
      })
  }

  /** 涨跌榜：只列「上期有数据」的分类，否则全是新增，没有可比性 */
  @Builder
  moversCard() {
    Column({ space: 8 }) {
      Text('涨跌榜')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tok().ink)
        .width('100%')
      ForEach(this.movers(), (cat: CategoryBucket) => {
        Row({ space: 8 }) {
          Text(cat.name)
            .fontSize(11)
            .fontColor(this.tok().ink2)
            .width(64)
            .maxLines(1)
          Text(formatYuan(cat.cents))
            .fontSize(11)
            .fontColor(this.tok().ink)
            .layoutWeight(1)
          Text(this.changeText(cat))
            .fontSize(10)
            .fontColor((cat.changeRatio ?? 0) > 0 ? this.tok().danger : this.tok().mint)
        }
        .width('100%')
      }, (cat: CategoryBucket) => cat.categoryId)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  private changeText(cat: CategoryBucket): string {
    const prev = cat.previousCents ?? 0;
    if (prev === 0) {
      return '新增';
    }
    const delta = cat.cents - prev;
    const sign = delta >= 0 ? '+' : '-';
    return `${sign}${formatYuan(Math.abs(delta))}`;
  }

  /** 还款节奏：信用卡的账单日/还款日（现金与储蓄卡不出现） */
  @Builder
  repayCard() {
    Column({ space: 8 }) {
      Text('还款节奏')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tok().ink)
        .width('100%')
      ForEach(this.creditPayments(), (p: PaymentBucket) => {
        Row({ space: 8 }) {
          Text(p.name)
            .fontSize(11)
            .fontColor(this.tok().ink2)
            .width(90)
            .maxLines(1)
          // 中间放占比条：名称与金额摆两端会让眼睛横跨整行才能对上
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(6)
              .backgroundColor(this.tok().surface3)
              .borderRadius(3)
            Row()
              .width(`${Math.round(this.paymentRatio(p) * 100)}%`)
              .height(6)
              .backgroundColor(chartColor(this.tok(), hashIndex(p.paymentMethodId)))
              .borderRadius(3)
          }
          .layoutWeight(1)
          Text(formatYuan(p.cents))
            .fontSize(11)
            .fontColor(this.tok().ink)
        }
        .width('100%')
      }, (p: PaymentBucket) => p.paymentMethodId)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  private creditPayments(): PaymentBucket[] {
    const out: PaymentBucket[] = [];
    const report = this.monthReport;
    if (report === null) {
      return out;
    }
    for (const p of report.paymentMethods) {
      if (p.type === 'credit') {
        out.push(p);
      }
    }
    return out;
  }

  /** 年度报告：12 月走势（横向条）+ 年度之最 */
  @Builder
  yearCard() {
    Column({ space: 8 }) {
      Text('年度走势')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tok().ink)
        .width('100%')
      ForEach(this.yearReport?.months ?? [], (point: MonthPointView) => {
        Row({ space: 8 }) {
          Text(`${Number(point.month.substring(5, 7))} 月`)
            .fontSize(9)
            .fontColor(this.tok().ink3)
            .width(36)
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(8)
              .backgroundColor(this.tok().surface3)
              .borderRadius(4)
            Row()
              .width(`${this.yearBarWidth(point.totalCents)}%`)
              .height(8)
              .backgroundColor(this.tok().accent)
              .borderRadius(4)
          }
          .layoutWeight(1)
          Text(formatYuan(point.totalCents))
            .fontSize(9)
            .fontColor(this.tok().ink2)
        }
        .width('100%')
      }, (point: MonthPointView) => point.month)

      if (this.yearReport?.peakMonth !== null && this.yearReport !== null) {
        Row({ space: 6 }) {
          Text('最高月')
            .fontSize(10)
            .fontColor(this.tok().ink3)
          Text(this.yearReport!.peakMonth!.month)
            .fontSize(10)
            .fontColor(this.tok().ink)
          Text(formatYuan(this.yearReport!.peakMonth!.totalCents))
            .fontSize(10)
            .fontColor(this.tok().ink2)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(this.tok().rCard)
    .border({ width: 1, color: this.tok().line })
  }

  private yearBarWidth(cents: number): number {
    const year = this.yearReport;
    if (year === null || year.totalCents <= 0) {
      return 0;
    }
    return Math.max(1, Math.round((cents / year.totalCents) * 100));
  }

  /** 当前是深色（cyber）吗 —— 决定用 Orbitron 还是 Outfit */
  private isCyber(): boolean {
    return ThemeManager.get().name === 'cyber';
  }

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(10)
            .fontColor(this.tok().danger)
            .width('100%')
        }
        this.head()
        if (this.tier === 0) {
          this.compose()
          this.moversCard()
          this.repayCard()
        } else {
          this.yearCard()
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
  }
}

export interface FactCell {
  label: string;
  value: string;
}

export interface TierCell {
  label: string;
  value: number;
}

interface MonthPointView {
  month: string;
  totalCents: number;
  count: number;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function currentMonthKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}`;
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
