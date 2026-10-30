/**
 * 年度报告屏 —— 照 Web 移动端现状（AnnualSummaryView.vue）1:1 复刻。
 *
 * 只陈述报表里已有的事实：全年合计、与去年对比、12 个月走势、之最。
 * 不做任何预测或评分 —— 那些需要口径假设，一旦算错比不给更糟。
 *
 * 入口：报表屏的「{年} 年度报告」按钮 / 渐变大横幅（写 annualYear + 切屏）。
 * 返回：顶栏 ‹ 回报表（web history.back 落报表）；卡内「返回报表」按钮同效。
 */
import { Api, MonthPoint, YearlyReport } from '../../common/net/Api';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { formatMonthLabel, formatYuan } from '../../common/contract/Contract';
import { cardShadow, fontBodyOf, fontDisplayOf, fontMonoOf, mixHex, parseShadow, radiusOf } from '../../common/ui/UiStyle';

@Component
export struct AnnualScreen {
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 年份由报表屏写入（web route.query.year） */
  @StorageLink('annualYear') @Watch('reload') year: string = String(new Date().getFullYear());
  /** 年份快选（点年份条弹出）：数据来自 summaryReport.years（真实有数据的年份） */
  @State yearCalOpen: boolean = false;
  @State yearOptions: YearOption[] = [];
  @State report: YearlyReport | null = null;
  @State loading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  private reload(): void {
    this.load();
  }

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      this.report = (await Api.yearlyReport(this.year)).report;
    } catch (e) {
      this.report = null;
    }
    this.loading = false;
  }

  // ── 派生数据（与 Web computed 一一对应）──────────────────────────────

  private total(): number {
    return this.report !== null ? this.report.totalCents : 0;
  }

  private months(): MonthPoint[] {
    return this.report !== null ? this.report.months : [];
  }

  private monthsMax(): number {
    let max = 1;
    for (const m of this.months()) {
      if (m.totalCents > max) {
        max = m.totalCents;
      }
    }
    return max;
  }

  private yearAgoCents(): number {
    return this.report !== null && this.report.yearAgo !== undefined ? this.report.yearAgo.totalCents : 0;
  }

  private yearDelta(): number | null {
    if (this.report === null || this.report.yearAgo === undefined) {
      return null;
    }
    // 上年无数据时服务端会给 null 或干脆不带这个字段 → undefined*100 = NaN
    return ratioOf(this.report.yearAgo.change?.ratio);
  }

  private yearDeltaPct(): string {
    const r = this.yearDelta();
    return r === null ? '' : `${(r * 100).toFixed(1)}%`;
  }

  private yearDeltaColor(): string {
    const r = this.yearDelta();
    return r === null ? this.tok().ink2 : (r > 0 ? this.tok().danger : this.tok().ok);
  }

  private count(): number {
    return this.report !== null ? this.report.count : 0;
  }

  private quietMonths(): number {
    let n = 0;
    for (const m of this.months()) {
      if (m.totalCents === 0) {
        n++;
      }
    }
    return n;
  }

  /** 支出最多的分类行（web topCategory） */
  private topCat(): TopCatView | null {
    const r = this.report;
    if (r === null || r.categories === undefined) {
      return null;
    }
    const rows = r.categories;
    let best: TopCatView | null = null;
    for (const c of rows) {
      if (c.cents > 0 && (best === null || c.cents > best.cents)) {
        best = { name: c.name, cents: c.cents };
      }
    }
    return best;
  }

  /** topCat 取值器（builder 内禁止非空断言/可空链取值） */
  private topCatName(): string {
    const t = this.topCat();
    return t === null ? '' : t.name;
  }

  private topCatCentsText(): string {
    const t = this.topCat();
    return t === null ? '' : formatYuan(t.cents);
  }

  private topCatPct(): string {
    const t = this.topCat();
    if (t === null) {
      return '';
    }
    return `${this.total() > 0 ? Math.round((t.cents / this.total()) * 100) : 0}%`;
  }

  /** 大数字字号：Web 移动端 `.hero-amt` 是 34px（views.css:775） */
  private heroSize(): number {
    const s = formatYuan(this.total()).replace('¥', '');
    if (s.length <= 8) {
      return 34;
    }
    if (s.length <= 10) {
      return 28;
    }
    return 22;
  }

  private shiftYear(delta: number): void {
    this.year = String(Number(this.year) + delta);
  }

  private backToReport(): void {
    AppStorage.setOrCreate('activeScreen', 'report');
  }

  /** 打开年份快选：拉 summaryReport 拿「真实有数据的年份」（降序），补上当前选中的年份 */
  private async openYearPicker(): Promise<void> {
    this.yearCalOpen = true;
    const out: YearOption[] = [];
    try {
      const s = (await Api.summaryReport()).report;
      for (const y of s.years) {
        out.push({ year: y.year, totalCents: y.totalCents, count: y.count });
      }
    } catch (e) {
      // 拉不到也至少给出当前年份，避免空弹层
    }
    const hasCur = out.some((o: YearOption) => o.year === this.year);
    if (!hasCur) {
      out.push({ year: this.year, totalCents: 0, count: 0 });
    }
    out.sort((a: YearOption, b: YearOption) => (a.year < b.year ? 1 : -1));
    this.yearOptions = out;
  }

  /** 年份网格高度：3 列、格高 52、行距 6 */
  private yearGridHeight(): number {
    const rows = Math.max(1, Math.ceil(this.yearOptions.length / 3));
    return rows * 52 + (rows - 1) * 6;
  }

  private pickYear(y: string): void {
    this.year = y;
    this.yearCalOpen = false;
  }

  /** 年份快选弹层 */
  @Builder
  yearPicker() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.yearCalOpen = false;
        })
      Column({ space: 10 }) {
        Row() {
          Text('选择年份').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
          Blank()
          Text('关闭').fontSize(11).fontColor(this.tok().ink3)
            .onClick(() => {
              this.yearCalOpen = false;
            })
        }
        .width('100%')

        if (this.yearOptions.length === 0) {
          Text('加载中…').fontSize(11).fontColor(this.tok().ink3)
            .width('100%').textAlign(TextAlign.Center)
        } else {
          Grid() {
            ForEach(this.yearOptions, (o: YearOption) => {
              GridItem() {
                Column({ space: 2 }) {
                  // Column 没有 fontColor —— 颜色要分别写在两个 Text 上
                  Text(`${o.year}`).fontSize(14).fontWeight(FontWeight.Bold)
                    .fontFamily(fontMonoOf()).fontFeature('"tnum" on')
                    .fontColor(this.year === o.year ? this.tok().accentInk : this.tok().ink)
                  Text(o.count > 0 ? `${o.count} 笔` : '无数据').fontSize(9.5)
                    .fontFamily(fontMonoOf()).fontFeature('"tnum" on')
                    .fontColor(this.year === o.year ? this.tok().accentInk : this.tok().ink3)
                }
                .width('100%').height(52)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.year === o.year ? this.tok().accent : this.tok().surface2)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
                .border({ width: 1, color: this.year === o.year ? this.tok().accent : this.tok().line })
                .onClick(() => {
                  this.pickYear(o.year);
                })
              }
            }, (o: YearOption) => `yr-${o.year}`)
          }
          .columnsTemplate('repeat(3, 1fr)')
          .columnsGap(6)
          .rowsGap(6)
          .width('100%')
          // Grid 不定高会撑满父容器 → 卡片被拉全屏高
          .height(this.yearGridHeight())
        }
      }
      .width(320)
      .padding(14)
      .backgroundColor(this.tok().bg)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
      .border({ width: this.tok().borderW, color: this.tok().line })
    }
    .width('100%')
    .height('100%')
  }

  // ══════════════ ① 顶栏：年份切换 ══════════════

  @Builder
  yearBar() {
    Row({ space: 10 }) {
      this.chevronBtn('‹', -1)
      Text(`${this.year} 年`)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontMonoOf())
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink)
        // 点年份 → 快选弹层（比一直点 ‹ › 快）
        .onClick(() => {
          this.openYearPicker();
        })
      this.chevronBtn('›', 1)
      Blank()
      // 返回报表（PBtn ghost sm）
      Text('返回报表')
        .fontSize(this.isCyber() ? 11 : 11.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .letterSpacing(this.isCyber() ? 1.54 : 0)
        .fontColor(this.tok().ink2)
        .height(30)
        .padding({ left: 11, right: 11 })
        .textAlign(TextAlign.Center)
        .backgroundColor(Color.Transparent)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .border({ width: this.tok().borderW, color: this.isCyber() ? this.tok().line : Color.Transparent })
        .onClick(() => {
          this.backToReport();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** icon-btn 38 */
  @Builder
  chevronBtn(symbol: string, delta: number) {
    Text(symbol)
      .fontSize(20)
      .fontColor(this.tok().ink2)
      .width(38)
      .height(38)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({ width: this.tok().borderW, color: this.tok().line })
      .onClick(() => {
        this.shiftYear(delta);
      })
  }

  // ══════════════ ② 年度全貌（card--pop）══════════════

  @Builder
  overviewCard() {
    Column() {
      // card-h：orb 日历 + {year} 年度全貌 + N 个月 · N 笔
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(16)
            .fontColor([this.isCyber() ? this.tok().accent : this.tok().accentInk])
        }
        .width(34)
        .height(34)
        .borderRadius(this.isCyber() ? 1 : 17)
        .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().accent)
        .border({
          width: this.isCyber() ? 1 : 2,
          color: this.isCyber() ? this.tok().accent : this.tok().line2
        })
        .shadow(this.isCyber()
          ? { radius: 10, offsetX: 0, offsetY: -2, color: 'rgba(0,255,136,0.4)' } as ShadowOptions
          : parseShadow(`2px 2px 0 ${this.tok().line2}`) as ShadowOptions)

        Text(`${this.year} 年度全貌`)
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Blank()
        Text(`${this.months().length} 个月 · ${this.count()} 笔`)
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })
      .alignItems(VerticalAlign.Center)

      // hero-amt
      Row({ space: 4 }) {
        Text('¥')
          .fontSize(this.heroSize() * 0.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tok().ink2)
        Text(formatYuan(this.total()).replace('¥', ''))
          .fontSize(this.heroSize())
          .fontWeight(FontWeight.Bolder)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 0.4 : -1.33)
          .fontFeature('"tnum" on')
          .maxLines(1)
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 8, bottom: 4 })

      // hero-delta：环比胶囊 + 去年
      Row({ space: 8 }) {
        if (this.yearDelta() !== null) {
          Text(this.yearDeltaPct())
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.yearDeltaColor())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({ width: this.isCyber() ? 1 : 1.5, color: this.yearDeltaColor() })
        }
        Text(`去年 ${formatYuan(this.yearAgoCents())}`)
          .fontSize(11.5)
          .fontColor(this.tok().ink2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // hero-metrics（margin-top 14）：月均 / 单笔均值 / 空月
      Row({ space: 10 }) {
        this.statCell('月均', formatYuan(Math.round(this.total() / 12)))
        this.statCell('单笔均值', formatYuan(this.count() > 0 ? Math.round(this.total() / this.count()) : 0))
        this.statCell('空月', `${this.quietMonths()} 个月`)
      }
      .width('100%')
      .margin({ top: 14, bottom: 0 })
      .padding({ top: 14 })
      .border({ width: { top: 1 }, color: this.tok().line, style: BorderStyle.Dashed })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.isCyber() ? this.tok().line : this.tok().line2 })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** PStat：stat-v 21 display 700 + stat-l 10.5 ink3 */
  @Builder
  statCell(label: string, value: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(this.isCyber() ? 18 : 21)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .fontFeature('"tnum" on')
        .maxLines(1)
        .fontColor(this.tok().ink)
      Text(label)
        .fontSize(this.isCyber() ? 9.5 : 10.5)
        .letterSpacing(this.isCyber() ? 1.14 : 0.42)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .fontColor(this.tok().ink3)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  // ══════════════ ③ 12 个月走势 ══════════════

  @Builder
  monthsCard() {
    Column() {
      Row({ space: 10 }) {
        Text('12 个月走势')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Blank()
        Text('按还款日归属')
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })
      .alignItems(VerticalAlign.Center)

      if (this.months().length === 0) {
        Text('这一年还没有记录')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 34, bottom: 34, left: 10, right: 10 })
      } else {
        Row({ space: 4 }) {
          ForEach(this.months(), (m: MonthPoint) => {
            Column({ space: 4 }) {
              Column()
                .width('100%')
                .height(Math.max(4, Math.round((m.totalCents / this.monthsMax()) * 100)))
                .backgroundColor(m.totalCents > 0
                  ? mixHex(this.tok().accent, this.tok().surface, 0.75)
                  : this.tok().surface3)
                .borderRadius({ topLeft: 3, topRight: 3, bottomLeft: 0, bottomRight: 0 })
              Text(`${Number(m.month.substring(5, 7))}`)
                .fontSize(9.5)
                .fontFamily(fontMonoOf())
                .fontFeature('"tnum" on')
                .fontColor(this.tok().ink3)
            }
            .layoutWeight(1)
            .height(140)
            .justifyContent(FlexAlign.End)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              // 同上：把月份带到报表，空月也要如实落到那个月（而不是跳回当前月）
              AppStorage.setOrCreate('pickMonth', m.month);
              this.backToReport();
            })
          }, (m: MonthPoint) => m.month)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  // ══════════════ ④ 年度之最（g2 两列）══════════════

  @Builder
  peakCard() {
    Column() {
      Text('最高支出月')
        .fontSize(this.isCyber() ? 12.5 : 15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .letterSpacing(this.isCyber() ? 1.25 : 0)
        .fontColor(this.tok().ink)
        .width('100%')
        .margin({ bottom: 13 })
      if (this.report === null || this.report.peakMonth === null) {
        Text('没有数据')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 34, bottom: 34, left: 10, right: 10 })
      } else {
        Text(formatMonthLabel(this.report.peakMonth.month))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
          .maxLines(1)
        Text(formatYuan(this.report.peakMonth.totalCents))
          .fontSize(10.5)
          .fontColor(this.tok().ink2)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  @Builder
  largestCard() {
    Column() {
      Text('单笔最贵')
        .fontSize(this.isCyber() ? 12.5 : 15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .letterSpacing(this.isCyber() ? 1.25 : 0)
        .fontColor(this.tok().ink)
        .width('100%')
        .margin({ bottom: 13 })
      if (this.report === null || this.report.largest === undefined || this.report.largest === null) {
        Text('没有数据')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 34, bottom: 34, left: 10, right: 10 })
      } else {
        Text(formatYuan(this.report.largest.cents))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontFeature('"tnum" on')
          .fontColor(this.tok().ink)
          .maxLines(1)
        Text(`${this.report.largest.categoryName} · ${this.report.largest.repaymentDate}`)
          .fontSize(10.5)
          .fontColor(this.tok().ink2)
          .margin({ top: 4 })
          .maxLines(1)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  // ══════════════ ⑤ 支出最多的分类 ══════════════

  @Builder
  topCatCard() {
    Column() {
      Row({ space: 10 }) {
        Text('支出最多的分类')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Blank()
        Text('全年')
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })
      .alignItems(VerticalAlign.Center)

      if (this.topCat() !== null) {
        Row() {
          Text(this.topCatName())
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.topCatCentsText())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.tok().ink)
          Text(this.topCatPct())
            .fontSize(10.5)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.tok().ink2)
            .margin({ left: 10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
    Scroll() {
      Column({ space: 12 }) {
        this.yearBar()
        this.overviewCard()
        this.monthsCard()
        Row({ space: 16 }) {
          Column() {
            this.peakCard()
          }
          .layoutWeight(1)
          Column() {
            this.largestCard()
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        if (this.topCat() !== null) {
          this.topCatCard()
        }
        if (this.loading) {
          Text('加载中…')
            .fontSize(10.5)
            .fontColor(this.tok().ink2)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)

      // 年份快选
      if (this.yearCalOpen) {
        this.yearPicker()
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 支出最多的分类（web topCategory） */
interface TopCatView {
  name: string;
  cents: number;
}

/** 服务端可能没给的比率 → null（避免 `NaN%`） */
function ratioOf(r: number | null | undefined): number | null {
  return typeof r === 'number' && Number.isFinite(r) ? r : null;
}

/** 年份快选项（来自 summaryReport.years） */
interface YearOption {
  year: string;
  totalCents: number;
  count: number;
}
