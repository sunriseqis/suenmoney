/**
 * 报表屏（docs 优先，R76–R86）。
 *
 * 结构（照 docs 的块集合，月 8 / 年 7 / 汇总 5）：
 *   标题行由外壳给（`报表 ×`）
 *   1 档位 + 期间（无页首大数字、无「共 N 笔」—— R86）
 *   2 分类构成（环图 + 可展开二级图例；**环心显示分类数**，不显示合计 —— R78）
 *   3 按支付方式 / 按记录人（排名行**中间必须有占比条** —— R79）
 *   4 期内节奏（月档按天折线逐点标值 / 年档按月 / 汇总按年 —— R82）
 *   5 对照四格（月：上月 / 去年同月 / 近12月均值 / 单笔最高 —— R83）
 *   6 还款节奏（**仅月档**：本月已刷 + 下月要还 —— R84）
 *   7 本期洞察（月 3 / 年 3 / 汇总 2，纯规则引擎 —— R85）
 *   8 涨跌榜（涨红跌绿，阈值 ±¥50 或 ±3% 取高 —— R37）
 *
 * 块纵向堆叠、块内允许两栏；桌面不分栏（R80）。
 */
import { Api, CategoryBucket, DailyPoint, MemberBucket, MonthlyReport, PaymentBucket, SummaryReport, YearPoint, YearlyReport } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, hashIndex } from '../../common/theme/Palette';
import { formatYuan, shiftMonth } from '../../common/contract/Contract';
import { CARD_PAD, cardRadiusOf, cardShadow, fontDisplayOf, fontMonoOf, radiusOf } from '../../common/ui/UiStyle';
import { DonutChart, DonutSliceView } from './DonutChart';

export interface TierChipModel {
  label: string;
  value: number;
}

@Component
export struct ReportScreen {
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 0=本月 1=本年 2=汇总 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  @State anchorYear: string = currentMonthKey().substring(0, 4);
  @State report: MonthlyReport | null = null;
  @State summary: SummaryReport | null = null;
  @State year: YearlyReport | null = null;
  @State loading: boolean = false;
  @State errorText: string = '';

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      if (this.tier === 0) {
        const body = await Api.monthlyReport(this.anchorMonth);
        this.report = body.report;
      } else if (this.tier === 1) {
        const body = await Api.yearlyReport(this.anchorYear);
        this.year = body.report;
      } else {
        const body = await Api.summaryReport();
        this.summary = body.report;
      }
    } catch (e) {
      this.errorText = (e as ApiError).message;
    } finally {
      this.loading = false;
    }
  }

  // ── 数据派生 ────────────────────────────────────────────────────────────
  private categories(): CategoryBucket[] {
    if (this.tier === 1) {
      return this.year !== null && this.year.categories !== undefined ? this.year.categories : [];
    }
    return this.report === null ? [] : this.report.categories;
  }

  /** 支付方式排名数据源（R79）：年档取年报，月档取月报 */
  private payments(): PaymentBucket[] {
    if (this.tier === 1) {
      return this.year !== null && this.year.paymentMethods !== undefined ? this.year.paymentMethods : [];
    }
    return this.report === null ? [] : this.report.paymentMethods;
  }

  /** 记录人排名数据源（R79） */
  private members(): MemberBucket[] {
    if (this.tier === 1) {
      return this.year !== null && this.year.members !== undefined ? this.year.members : [];
    }
    return this.report === null ? [] : this.report.members;
  }

  private slices(): DonutSliceView[] {
    // R77：图例只列前 6，其余合并成「其他」（颜色用中性色，避免和真实分类混淆）
    const cats = this.categories();
    const out: DonutSliceView[] = [];
    let otherRatio = 0;
    for (let i = 0; i < cats.length; i++) {
      const c = cats[i];
      if (i < 6) {
        out.push({ label: c.name, ratio: c.ratio, color: chartColor(this.tok(), hashIndex(c.categoryId)) });
      } else {
        otherRatio += c.ratio;
      }
    }
    if (otherRatio > 0) {
      out.push({ label: '其他', ratio: otherRatio, color: this.tok().ink3 });
    }
    return out;
  }

  private signature(): string {
    let s = `${this.tier}-${this.anchorMonth}-${this.categories().length}-`;
    for (const slice of this.slices()) {
      s += `${slice.label}:${slice.ratio.toFixed(4)}:${slice.color};`;
    }
    return s;
  }

  /** 洞察（R85）：纯规则引擎，月 3 / 年 3 / 汇总 2，句式 `{分类} {金额}（{为什么}）` */
  private insights(): string[] {
    const out: string[] = [];
    // 汇总档（R85：2 条）——此时 report/year 均为空，用 summary 生成
    if (this.tier === 2) {
      const sum = this.summary;
      if (sum === null) {
        return out;
      }
      out.push(`累计 ${formatYuan(sum.totalCents)}（${sum.count} 笔 · ${sum.recordedDays} 天）`);
      out.push(`月均 ${formatYuan(sum.monthlyAverageCents)}（按有记录月份平均）`);
      return out.slice(0, 2);
    }
    const r = this.report;
    if (r === null || this.tier === 1) {
      // 年档洞察（R85：3 条）—— 数据全部来自年报，不受是否看过月档影响
      const y = this.year;
      if (y === null) {
        return out;
      }
      if (y.largest !== null && y.largest !== undefined) {
        out.push(`${y.largest.categoryName} ${formatYuan(y.largest.cents)}（本年最大一笔）`);
      }
      if (y.peakMonth !== null) {
        out.push(`最高月 ${y.peakMonth.month}（${formatYuan(y.peakMonth.totalCents)}）`);
      }
      let lowMonth = '';
      let lowCents = -1;
      for (const m of y.months) {
        if (m.totalCents > 0 && (lowCents < 0 || m.totalCents < lowCents)) {
          lowMonth = m.month;
          lowCents = m.totalCents;
        }
      }
      if (lowMonth !== '') {
        out.push(`最低月 ${lowMonth}（${formatYuan(lowCents)}）`);
      }
      if (out.length === 0) {
        out.push(`本年合计 ${formatYuan(y.totalCents)}（${y.count} 笔）`);
      }
      return out.slice(0, 3);
    }
    if (r.largest !== null) {
      out.push(`${r.largest.categoryName} ${formatYuan(r.largest.cents)}（本期最大一笔）`);
    }
    const movers = this.movers();
    if (movers.length > 0) {
      const m = movers[0];
      const why = (m.changeRatio ?? 0) > 0 ? '涨得最多' : '降得最多';
      out.push(`${m.name} ${formatYuan(m.cents)}（${why}）`);
    }
    let creditCents = 0;
    for (const p of r.paymentMethods) {
      if (p.type === 'credit') {
        creditCents += p.cents;
      }
    }
    out.push(`信用类 ${formatYuan(creditCents)}（还款集中在这类）`);
    return out.slice(0, this.tier === 2 ? 2 : 3);
  }

  /** 涨跌（R37）：阈值 ±¥50 或 ±3%，取高 */
  private movers(): CategoryBucket[] {
    const list: CategoryBucket[] = [];
    for (const c of this.categories()) {
      const prev = c.previousCents ?? 0;
      if (prev === 0) {
        continue;
      }
      const delta = c.cents - prev;
      const ratio = Math.abs(delta) / prev;
      if (Math.abs(delta) >= 5000 || ratio >= 0.03) {
        list.push(c);
      }
    }
    list.sort((a: CategoryBucket, b: CategoryBucket) => Math.abs(b.cents - (b.previousCents ?? 0)) - Math.abs(a.cents - (a.previousCents ?? 0)));
    return list.slice(0, 3);
  }

  /** 对照四格（R83）：月档 = 上月 / 去年同月 / 近12月均值 / 单笔最高 */
  private compareFacts(): CompareFact[] {
    const out: CompareFact[] = [];
    const r = this.report;
    if (r === null) {
      return out;
    }
    out.push({ label: '上月', value: formatYuan(r.previous.totalCents) });
    // R83：去年同月取服务端 yearAgo，不再硬编码 0
    out.push({ label: '去年同月', value: formatYuan(r.yearAgo === undefined ? 0 : r.yearAgo.totalCents) });
    let sum = 0;
    let n = 0;
    for (const m of r.rolling12Months) {
      sum += m.totalCents ?? 0;
      n += 1;
    }
    out.push({ label: '近 12 月均值', value: formatYuan(n > 0 ? Math.round(sum / n) : 0) });
    out.push({ label: '单笔最高', value: formatYuan(r.largest === null ? 0 : r.largest.cents) });
    return out;
  }

  /** 期内节奏（R82）：月档按天，逐点标值（这里用 31 根竖柱 + 峰值标数，避免折线在 ArkUI 里的实现成本） */
  private dailyMax(): number {
    let max = 0;
    const r = this.report;
    if (r === null) {
      return 0;
    }
    for (const d of r.daily) {
      if (d.cents > max) {
        max = d.cents;
      }
    }
    return max;
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.errorText !== '') {
          Text(this.errorText).fontSize(10).fontColor(this.tok().danger).width('100%')
        }
        this.headCard()
        if (this.tier === 2) {
          // 汇总档 5 块（R76）：记录跨度 / 期内节奏(按年) / 洞察 2 条
          // 规范明文：汇总档不出现「年度对照」（没有对比期可比）
          this.spanCard()
          this.rhythmCard()
          this.insightCard()
        } else if (this.tier === 1) {
          // 年档 7 块（R76）：分类构成 / 支付排名 / 记录人 / 期内节奏 / 年度对照 / 涨跌榜 / 洞察
          // 数据全部来自 `/api/reports/yearly`（服务端已返回 categories/paymentMethods/members）
          this.composeCard()
          this.rankCard()
          this.memberCard()
          this.rhythmCard()
          this.yearCompareCard()
          this.moversCard()
          this.insightCard()
        } else {
          this.composeCard()
          this.rankCard()
          this.memberCard()
          this.rhythmCard()
          if (this.tier === 0) {
            this.compareCard()
            this.repayCard()
            this.moversCard()
          }
          this.insightCard()
        }
        if (this.loading) {
          Text('加载中…').fontSize(10).fontColor(this.tok().ink3)
        }
      }
      .width('100%')
      .padding({ bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  /** 档位 + 期间（**无页首大数字**，R86） */
  @Builder
  headCard() {
    Row({ space: 8 }) {
      this.tierChip({ label: '本月', value: 0 })
      this.tierChip({ label: '本年', value: 1 })
      this.tierChip({ label: '汇总', value: 2 })
      Blank()
      if (this.tier !== 2) {
        Text('‹').fontSize(16).fontColor(this.tok().ink3).padding({ left: 6, right: 6 })
          .onClick(() => {
            this.shift(-1);
          })
        Text(this.tier === 0 ? this.anchorMonth : this.anchorYear)
          .fontSize(13).fontWeight(FontWeight.Bold).fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
        Text('›').fontSize(16).fontColor(this.tok().ink3).padding({ left: 6, right: 6 })
          .onClick(() => {
            this.shift(1);
          })
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  private shift(delta: number): void {
    if (this.tier === 0) {
      this.anchorMonth = shiftMonth(this.anchorMonth, delta);
    } else {
      this.anchorYear = String(Number(this.anchorYear) + delta);
    }
    this.reload();
  }

  @Builder
  tierChip($$: TierChipModel) {
    Text($$.label)
      .fontSize(11.5)
      .fontWeight(this.tier === $$.value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.tier === $$.value ? this.tok().ink : this.tok().ink3)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor(this.tier === $$.value ? this.tok().surface2 : Color.Transparent)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 999))
      .onClick(() => {
        this.tier = $$.value;
        this.reload();
      })
  }

  /** 分类构成：环图（中心=分类数，R78）+ 图例 */
  @Builder
  composeCard() {
    Column({ space: 10 }) {
      Text('分类构成')
        .fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      Row({ space: 12 }) {
        DonutChart({
          slices: this.slices(),
          tokens: this.tok(),
          signature: this.signature(),
          centerLabel: `${this.categories().length} 类`
        })
        Column({ space: 6 }) {
          ForEach(this.slices().slice(0, 6), (slice: DonutSliceView) => {
            Row({ space: 6 }) {
              Row().width(9).height(9).backgroundColor(slice.color).borderRadius(3)
              Text(slice.label).fontSize(10.5).fontColor(this.tok().ink2)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              Text(`${(slice.ratio * 100).toFixed(0)}%`).fontSize(10).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
            }.width('100%')
          }, (slice: DonutSliceView) => slice.label)
        }.layoutWeight(1)
      }.width('100%')
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 按记录人排名（R79：中间必须有占比条；汇总档也有此块） */
  @Builder
  memberCard() {
    Column({ space: 10 }) {
      Text('按记录人').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      ForEach(this.memberBuckets(), (m: MemberBucket) => {
        Row({ space: 8 }) {
          Text(m.name).fontSize(11).fontColor(this.tok().ink2).width(84).maxLines(1)
          Stack({ alignContent: Alignment.Start }) {
            Row().width('100%').height(10).backgroundColor(this.tok().surface3).borderRadius(5)
            Row().width(`${Math.round(m.ratio * 100)}%`).height(10)
              .backgroundColor(chartColor(this.tok(), hashIndex(m.ownerId))).borderRadius(5)
          }.layoutWeight(1)
          Text(formatYuan(m.cents)).fontSize(11).fontFamily(fontMonoOf()).fontColor(this.tok().ink)
        }.width('100%')
      }, (m: MemberBucket) => m.ownerId)
    }
    .width('100%').padding(CARD_PAD).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  private memberBuckets(): MemberBucket[] {
    return this.members();
  }

  /** 排名行（R79）：中间必须有占比条 */
  @Builder
  rankCard() {
    Column({ space: 10 }) {
      Text('按支付方式').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      ForEach(this.payBuckets(), (p: PaymentBucket) => {
        Row({ space: 8 }) {
          Text(p.name).fontSize(11).fontColor(this.tok().ink2).width(84).maxLines(1)
          Stack({ alignContent: Alignment.Start }) {
            Row().width('100%').height(10).backgroundColor(this.tok().surface3).borderRadius(5)
            Row().width(`${Math.round(this.payRatio(p) * 100)}%`).height(10)
              .backgroundColor(chartColor(this.tok(), hashIndex(p.paymentMethodId))).borderRadius(5)
          }.layoutWeight(1)
          Text(formatYuan(p.cents)).fontSize(11).fontFamily(fontMonoOf()).fontColor(this.tok().ink)
        }.width('100%')
      }, (p: PaymentBucket) => p.paymentMethodId)
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  private payBuckets(): PaymentBucket[] {
    return this.payments();
  }

  private payRatio(p: PaymentBucket): number {
    const total = this.tier === 1
      ? (this.year === null ? 0 : this.year.totalCents)
      : (this.report === null ? 0 : this.report.totalCents);
    return total > 0 ? p.cents / total : 0;
  }

  /** 期内节奏（R82）：月档按天 — 31 根竖柱，峰值标数 */
  @Builder
  rhythmCard() {
    Column({ space: 8 }) {
      Text('期内节奏').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      if (this.tier === 0 && this.report !== null) {
        Row({ space: 2 }) {
          ForEach(this.report.daily, (d: DailyPoint) => {
            Column().width(4)
              .height(this.dailyMax() > 0 ? Math.max(2, Math.round((d.cents / this.dailyMax()) * 56)) : 2)
              .backgroundColor(d.cents > 0 ? this.tok().accent : this.tok().surface3)
              .borderRadius(2)
          }, (d: DailyPoint) => d.date)
        }
        .height(56)
        .alignItems(VerticalAlign.Bottom)
        Row() {
          Text(`峰值 ${formatYuan(this.dailyMax())}`).fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
        }.width('100%')
      } else if (this.year !== null) {
        // 年档：按月 12 根柱
        Row({ space: 3 }) {
          ForEach(this.year.months, (m: MonthPointView) => {
            Column().width(8)
              .height(this.yearMax() > 0 ? Math.max(2, Math.round((m.totalCents / this.yearMax()) * 56)) : 2)
              .backgroundColor(m.totalCents > 0 ? this.tok().accent : this.tok().surface3)
              .borderRadius(2)
          }, (m: MonthPointView) => m.month)
        }
        .height(56)
        .alignItems(VerticalAlign.Bottom)
        Row() {
          Text(`最高月 ${this.year.peakMonth === null ? '—' : formatYuan(this.year.peakMonth.totalCents)}`)
              .fontFeature('"tnum" on')
            .fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
        }.width('100%')
      } else if (this.summary !== null) {
        // 汇总档：按年柱（R82）
        Row({ space: 6 }) {
          ForEach(this.summary.years, (y: YearPoint) => {
            Column().width(14)
              .height(this.summaryMax() > 0 ? Math.max(2, Math.round((y.totalCents / this.summaryMax()) * 56)) : 2)
              .backgroundColor(y.totalCents > 0 ? this.tok().accent : this.tok().surface3)
              .borderRadius(2)
          }, (y: YearPoint) => y.year)
        }
        .height(56)
        .alignItems(VerticalAlign.Bottom)
        Row() {
          Text(`共 ${this.summary.years.length} 年`)
            .fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
        }.width('100%')
      } else {
        Text('合计按年').fontSize(10).fontColor(this.tok().ink3)
      }
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  /** 对照四格（R83） */
  @Builder
  compareCard() {
    Column({ space: 8 }) {
      Text('对照').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      Grid() {
        ForEach(this.compareFacts(), (f: CompareFact) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(f.label).fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
              Text(f.value).fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
            }.alignItems(HorizontalAlign.Start).width('100%')
          }
        }, (f: CompareFact) => f.label)
      }
      .columnsTemplate('repeat(2, 1fr)').columnsGap(10).rowsGap(10).width('100%')
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  private summaryMax(): number {
    let max = 0;
    if (this.summary !== null) {
      for (const y of this.summary.years) {
        if (y.totalCents > max) {
          max = y.totalCents;
        }
      }
    }
    return max;
  }

  private yearMax(): number {
    let max = 0;
    if (this.year !== null) {
      for (const m of this.year.months) {
        if (m.totalCents > max) {
          max = m.totalCents;
        }
      }
    }
    return max;
  }

  /** 年档对照四格（R83）：去年 / 近 3 年均值 / 最高月 / 单笔最高 */
  private yearCompareFacts(): CompareFact[] {
    const y = this.year;
    if (y === null) {
      return [];
    }
    let sum = 0;
    for (const m of y.months) {
      sum += m.totalCents;
    }
    // R83：四格是「与谁比」——去年 / 近 3 年均值 / 最高月 / 单笔最高
    return [
      { label: '去年', value: y.yearAgo === undefined || y.yearAgo === null ? '—' : formatYuan(y.yearAgo.totalCents) },
      { label: '近 3 年均值', value: y.average3YearsCents === undefined ? '—' : formatYuan(y.average3YearsCents) },
      { label: '最高月', value: y.peakMonth === null ? '—' : formatYuan(y.peakMonth.totalCents) },
      { label: '单笔最高', value: y.largest === undefined || y.largest === null ? '—' : formatYuan(y.largest.cents) }
    ];
  }

  @Builder
  yearCompareCard() {
    Column({ space: 8 }) {
      Text('年度对照').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      Grid() {
        ForEach(this.yearCompareFacts(), (f: CompareFact) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(f.label).fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
              Text(f.value).fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
            }.alignItems(HorizontalAlign.Start).width('100%')
          }
        }, (f: CompareFact) => f.label)
      }
      .columnsTemplate('repeat(2, 1fr)').columnsGap(10).rowsGap(10).width('100%')
    }
    .width('100%').padding(CARD_PAD).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
  }

  /** 还款节奏（R84）：仅月档，本月已刷 + 下月要还 */
  @Builder
  repayCard() {
    Column({ space: 8 }) {
      Text('还款节奏').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      Row() {
        this.repayFact({ label: '本月已刷', value: formatYuan(this.creditCents()) })
        this.repayFact({ label: '下月要还', value: formatYuan(this.nextMonthDueCents()) })
      }.width('100%')
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  @Builder
  repayFact($$: CompareFact) {
    Column({ space: 2 }) {
      Text($$.label).fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
      Text($$.value).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  /** 下月要还：还款日落在下个月的信用类金额（R84 与「本月已刷」是两个数） */
  private nextMonthDueCents(): number {
    const r = this.report;
    if (r === null) {
      return 0;
    }
    const next = shiftMonth(this.anchorMonth, 1);
    let sum = 0;
    for (const p of r.paymentMethods) {
      if (p.type !== 'credit') {
        continue;
      }
      const due = p.repaymentDate ?? '';
      if (due.startsWith(next)) {
        sum += p.cents;
      }
    }
    return sum;
  }

  private creditCents(): number {
    let sum = 0;
    for (const p of this.payBuckets()) {
      if (p.type === 'credit') {
        sum += p.cents;
      }
    }
    return sum;
  }

  /** 涨跌榜（R37） */
  @Builder
  moversCard() {
    Column({ space: 8 }) {
      Text('涨跌榜').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      if (this.movers().length === 0) {
        Text('本期没有超过阈值的变化').fontSize(10).fontColor(this.tok().ink3).width('100%')
      }
      ForEach(this.movers(), (c: CategoryBucket) => {
        Row({ space: 8 }) {
          Text(c.name).fontSize(11).fontColor(this.tok().ink2).width(72).maxLines(1)
          Text(formatYuan(c.cents)).fontSize(11).fontFamily(fontMonoOf()).fontColor(this.tok().ink).layoutWeight(1)
            .fontFeature('"tnum" on')
          Text(this.deltaText(c)).fontSize(10).fontFamily(fontMonoOf())
            .fontColor((c.cents - (c.previousCents ?? 0)) >= 0 ? this.tok().danger : this.tok().ok)
        }.width('100%')
      }, (c: CategoryBucket) => c.categoryId)
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  private deltaText(c: CategoryBucket): string {
    const delta = c.cents - (c.previousCents ?? 0);
    return `${delta >= 0 ? '+' : '-'}${formatYuan(Math.abs(delta))}`;
  }

  /** 本期洞察（R85） */
  @Builder
  insightCard() {
    Column({ space: 6 }) {
      Text('本期洞察').fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).width('100%')
      ForEach(this.insights(), (line: string) => {
        Text(line).fontSize(10.5).fontColor(this.tok().ink2).width('100%')
      }, (line: string) => line)
    }
    .width('100%').padding(14).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
  }

  /** 汇总档：年度对比（按年金额条） */



  /** 汇总档：记录跨度 */
  @Builder
  spanCard() {
    Row({ space: 10 }) {
      this.repayFact({ label: '记录天数', value: `${this.summary === null ? 0 : this.summary.recordedDays} 天` })
      this.repayFact({ label: '总笔数', value: `${this.summary === null ? 0 : this.summary.count} 笔` })
      this.repayFact({ label: '月均', value: formatYuan(this.summary === null ? 0 : this.summary.monthlyAverageCents) })
    }
    .width('100%').padding(CARD_PAD).backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.tok().borderW, color: this.tok().line })
  }
}

export interface CompareFact {
  label: string;
  value: string;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function currentMonthKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}`;
}

interface MonthPointView {
  month: string;
  totalCents: number;
  count: number;
}
