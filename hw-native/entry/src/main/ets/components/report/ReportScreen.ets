/**
 * 报表屏 —— 照 Web 移动端现状（ReportView.vue ≤860px）1:1 复刻。
 *
 * 单列五块（.stack gap 12）：
 *   report-head     紧凑事实条：Seg 三档 + period-nav + 年度报告入口 + 期间支出/环比/日均/笔数
 *   report-compose  支出构成四维（分类环图 / 支付 / 记录人 / 节奏），图例移动端全宽虚线行
 *   report-pair     涨跌榜（月档 vs 上期）+ 还款节奏（近 6 月柱）—— 移动端单列
 *   report-banner   {年} 年度报告渐变大横幅 → 年度报告屏
 *
 * 四个接口并发拉（月 / 上月 / 年 / 汇总），失败置 null 不清屏。
 */
import { Api, CategoryBucket, DailyPoint, MemberBucket, MonthlyReport, PaymentBucket, RollingMonth, SummaryReport, YearlyReport } from '../../common/net/Api';
import { LengthMetrics } from '@kit.ArkUI';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, slotOf } from '../../common/theme/Palette';
import { formatMonthLabel, formatYuan, shiftMonth } from '../../common/contract/Contract';
import { cardShadow, fontBodyOf, fontDisplayOf, fontMonoOf, mixHex, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { categoryColorOf } from '../../common/ui/CategoryIcon';
import { CatIconView } from '../../common/ui/CatIconView';
import { DonutChart, DonutSliceView } from './DonutChart';

/** 四维行（分类/支付/记录人/节奏共用） */
interface DimRow {
  name: string;
  cents: number;
  color: string;
}

/** 涨跌榜一行（web movers） */
interface MoverView {
  name: string;
  categoryId: string;
  color: string;
  now: number;
  before: number;
  diff: number;
}

@Component
export struct ReportScreen {
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 0=本月 1=本年 2=全部 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  /** cat / pay / owner / week */
  @State dim: string = 'cat';

  @State monthReport: MonthlyReport | null = null;
  @State prevMonthReport: MonthlyReport | null = null;
  @State yearReport: YearlyReport | null = null;
  @State summary: SummaryReport | null = null;
  @State loading: boolean = true;

  /** 其它屏下钻过来时带的月份（概况热力格 / 年度报告月柱） */
  @StorageLink('pickMonth') pickMonth: string = '';

  aboutToAppear(): void {
    // 有下钻月份就落到那个月（哪怕它是空月，也要如实展示空态）
    if (this.pickMonth !== '') {
      this.anchorMonth = this.pickMonth;
      this.tier = 0;
      this.pickMonth = '';
    }
    this.load();
  }

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  private anchorYear(): string {
    return this.anchorMonth.substring(0, 4);
  }

  /** 四个报表并发拉（web load()：失败置 null，不清屏以外的状态） */

  /** 期间快选月历（点期间标签弹出）：年 ‹ › + 12 个月格 */
  @State calOpen: boolean = false;
  @State calYearV: number = Number(currentMonthKey().substring(0, 4));

  private calMonthActive(mm: number): boolean {
    return this.tier === 0 && this.anchorMonth === monthKeyOf(this.calYearV, mm);
  }

  private applyPeriod(month: string, tier: number): void {
    // anchorYear 是从 anchorMonth 派生的方法，不能赋值
    this.anchorMonth = month;
    this.tier = tier;
    this.calOpen = false;
    this.load();
  }

  @Builder
  periodCalendar() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.calOpen = false;
        })
      Column({ space: 10 }) {
        Row() {
          Text('选择期间').fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.tok().ink)
          Blank()
          Text('关闭').fontSize(11).fontColor(this.tok().ink3)
            .onClick(() => {
              this.calOpen = false;
            })
        }
        .width('100%')

        Row() {
          Text('‹').fontSize(18).fontColor(this.tok().ink2).width(34).height(30)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.calYearV = this.calYearV - 1;
            })
          Blank()
          Text(`${this.calYearV} 年`).fontSize(15).fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber())).fontColor(this.tok().ink)
          Blank()
          Text('›').fontSize(18).fontColor(this.tok().ink2).width(34).height(30)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.calYearV = this.calYearV + 1;
            })
        }
        .width('100%')

        Grid() {
          ForEach(CAL_MONTHS, (mm: number) => {
            GridItem() {
              Text(`${mm}月`).fontSize(12).width('100%').height(38)
                .textAlign(TextAlign.Center).fontFamily(fontMonoOf())
                .fontColor(this.calMonthActive(mm) ? this.tok().accentInk : this.tok().ink2)
                .backgroundColor(this.calMonthActive(mm) ? this.tok().accent : this.tok().surface2)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
                .border({ width: 1, color: this.tok().line })
                .onClick(() => {
                  this.applyPeriod(monthKeyOf(this.calYearV, mm), 0);
                })
            }
          }, (mm: number) => `cal-${mm}`)
        }
        .columnsTemplate('repeat(4, 1fr)')
        .columnsGap(6)
        .rowsGap(6)
        .width('100%')

        Row({ space: 8 }) {
          Text('整年').fontSize(11.5).layoutWeight(1).height(32).textAlign(TextAlign.Center)
            .fontColor(this.tok().ink2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .border({ width: 1, color: this.tok().line })
            .onClick(() => {
              this.applyPeriod(monthKeyOf(this.calYearV, Number(this.anchorMonth.substring(5, 7))), 1);
            })
          Text('回到本月').fontSize(11.5).layoutWeight(1).height(32).textAlign(TextAlign.Center)
            .fontColor(this.tok().ink2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .border({ width: 1, color: this.tok().line })
            .onClick(() => {
              this.applyPeriod(currentMonthKey(), 0);
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding(14)
      .backgroundColor(this.tok().bg)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
      .border({ width: this.tok().borderW, color: this.tok().line })
    }
    .width('100%')
    .height('100%')
  }

  private async load(): Promise<void> {
    this.loading = true;
    let m: MonthlyReport | null = null;
    let p: MonthlyReport | null = null;
    let y: YearlyReport | null = null;
    let s: SummaryReport | null = null;
    try {
      m = (await Api.monthlyReport(this.anchorMonth)).report;
    } catch (e) {
      m = null;
    }
    try {
      p = (await Api.monthlyReport(shiftMonth(this.anchorMonth, -1))).report;
    } catch (e) {
      p = null;
    }
    try {
      y = (await Api.yearlyReport(this.anchorYear())).report;
    } catch (e) {
      y = null;
    }
    try {
      s = (await Api.summaryReport()).report;
    } catch (e) {
      s = null;
    }
    this.monthReport = m;
    this.prevMonthReport = p;
    this.yearReport = y;
    this.summary = s;
    this.loading = false;
  }

  // ── 派生数据（与 Web computed 一一对应）──────────────────────────────

  private activeTotal(): number {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.totalCents : 0;
    }
    if (this.tier === 1) {
      return this.yearReport !== null ? this.yearReport.totalCents : 0;
    }
    return this.summary !== null ? this.summary.totalCents : 0;
  }

  private activeCount(): number {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.count : 0;
    }
    if (this.tier === 1) {
      return this.yearReport !== null ? this.yearReport.count : 0;
    }
    return this.summary !== null ? this.summary.count : 0;
  }

  private prevTotal(): number {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.previous.totalCents : 0;
    }
    if (this.tier === 1) {
      return this.yearReport !== null && this.yearReport.yearAgo !== undefined
        ? this.yearReport.yearAgo.totalCents : 0;
    }
    return 0;
  }

  private deltaRatio(): number | null {
    if (this.tier === 0) {
      return this.monthReport !== null ? ratioOf(this.monthReport.change.ratio) : null;
    }
    if (this.tier === 1) {
      return this.yearReport !== null && this.yearReport.yearAgo !== undefined
        ? ratioOf(this.yearReport.yearAgo.changeRatio) : null;
    }
    return null;
  }

  /** 环比胶囊取值器（builder 内禁止非空断言，拆成取值器） */
  private deltaArrow(): string {
    const r = this.deltaRatio();
    return r === null || r <= 0 ? '↓' : '↑';
  }

  private deltaPctText(): string {
    const r = this.deltaRatio();
    return r === null ? '' : `${(r * 100).toFixed(1)}%`;
  }

  private deltaToneColor(): string {
    const r = this.deltaRatio();
    return r === null ? this.tok().ink2 : (r > 0 ? this.tok().danger : this.tok().ok);
  }

  private periodLabel(): string {
    if (this.tier === 0) {
      return formatMonthLabel(this.anchorMonth);
    }
    if (this.tier === 1) {
      return `${this.anchorYear()} 年`;
    }
    return '全部记录';
  }

  private perDayCents(): number {
    if (this.tier !== 0) {
      return this.activeCount() > 0 ? Math.round(this.activeTotal() / Math.max(1, this.activeCount())) : 0;
    }
    const elapsed = Math.max(1, new Date().getDate());
    return Math.round(this.activeTotal() / elapsed);
  }

  private categories(): CategoryBucket[] {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.categories : [];
    }
    if (this.tier === 1) {
      return this.yearReport !== null && this.yearReport.categories !== undefined ? this.yearReport.categories : [];
    }
    return this.summary !== null && this.summary.categories !== undefined ? this.summary.categories : [];
  }

  /** 分类维度行：前 7 类 + 其他（web donutData，颜色走 chart 8 槽） */
  private catRows(): DimRow[] {
    const rows: CategoryBucket[] = [];
    for (const c of this.categories()) {
      if (c.cents > 0) {
        rows.push(c);
      }
    }
    rows.sort((a: CategoryBucket, b: CategoryBucket) => b.cents - a.cents);
    const out: DimRow[] = [];
    for (const c of rows.slice(0, 7)) {
      out.push({ name: c.name, cents: c.cents, color: chartColor(this.tok(), slotOf(c.color, c.categoryId)) });
    }
    let rest = 0;
    for (const c of rows.slice(7)) {
      rest += c.cents;
    }
    if (rest > 0) {
      out.push({ name: '其他', cents: rest, color: this.tok().ink3 });
    }
    return out;
  }

  /** 环图数据（catRows 的去名视图） */
  private donutSlices(): DonutSliceView[] {
    const out: DonutSliceView[] = [];
    for (const r of this.catRows()) {
      out.push({ value: r.cents, color: r.color });
    }
    return out;
  }

  /** 涨跌榜：本期 vs 上期（仅月档有上期明细） */
  private movers(): MoverView[] {
    const prev = this.prevMonthReport;
    if (this.tier !== 0 || prev === null) {
      return [];
    }
    const out: MoverView[] = [];
    for (const c of this.categories()) {
      let before = 0;
      for (const pc of prev.categories) {
        if (pc.categoryId === c.categoryId) {
          before = pc.cents;
          break;
        }
      }
      const diff = c.cents - before;
      if (Math.abs(diff) > 0) {
        out.push({
          name: c.name,
          categoryId: c.categoryId,
          color: categoryColorOf(c.name, c.color),
          now: c.cents,
          before: before,
          diff: diff
        });
      }
    }
    out.sort((a: MoverView, b: MoverView) => Math.abs(b.diff) - Math.abs(a.diff));
    return out.slice(0, 6);
  }

  /** 当前维度下的行 */
  private dimRows(): DimRow[] {
    if (this.dim === 'cat') {
      return this.catRows();
    }
    if (this.dim === 'pay') {
      const src: PaymentBucket[] = this.monthReport !== null ? this.monthReport.paymentMethods : [];
      const colored: DimRow[] = [];
      let i = 0;
      for (const p of src) {
        colored.push({ name: p.name, cents: p.cents, color: chartColor(this.tok(), i % 8) });
        i++;
      }
      return this.filterSortRows(colored);
    }
    if (this.dim === 'owner') {
      const src: MemberBucket[] = this.monthReport !== null ? this.monthReport.members : [];
      const colored: DimRow[] = [];
      let i = 0;
      for (const m of src) {
        colored.push({ name: m.name, cents: m.cents, color: chartColor(this.tok(), (i + 3) % 8) });
        i++;
      }
      return this.filterSortRows(colored);
    }
    // 节奏：按星期几聚合（周日 → 周六）
    const wd: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    const byWeekday: number[] = [0, 0, 0, 0, 0, 0, 0];
    const daily: DailyPoint[] = this.monthReport !== null ? this.monthReport.daily : [];
    for (const d of daily) {
      const day = new Date(`${d.date}T00:00:00`).getDay();
      byWeekday[day] += d.cents;
    }
    const out: DimRow[] = [];
    for (let i = 0; i < 7; i++) {
      out.push({ name: wd[i], cents: byWeekday[i], color: this.tok().accent });
    }
    return out;
  }

  /** 支付/记录人维度公用的「先染色 → 过滤 0 → 按金额降序」 */
  private filterSortRows(src: DimRow[]): DimRow[] {
    const out: DimRow[] = [];
    for (const r of src) {
      if (r.cents > 0) {
        out.push(r);
      }
    }
    out.sort((a: DimRow, b: DimRow) => b.cents - a.cents);
    return out;
  }

  private dimMax(): number {
    let max = 1;
    for (const r of this.dimRows()) {
      if (r.cents > max) {
        max = r.cents;
      }
    }
    return max;
  }

  /** 还款节奏：近 6 个月（月报 rolling12Months 尾部） */
  private repaySteps(): RollingMonth[] {
    const src: RollingMonth[] = this.monthReport !== null ? this.monthReport.rolling12Months : [];
    return src.slice(Math.max(0, src.length - 6));
  }

  private repayMax(): number {
    let max = 1;
    for (const r of this.repaySteps()) {
      if ((r.totalCents ?? 0) > max) {
        max = r.totalCents ?? 0;
      }
    }
    return max;
  }

  /** 一句话结论（web conclusion） */
  private conclusion(): string {
    const total = this.activeTotal();
    if (total === 0) {
      return '这个期间还没有记录，记一笔之后这里会自动生成结论。';
    }
    const rows: CategoryBucket[] = [];
    for (const c of this.categories()) {
      rows.push(c);
    }
    rows.sort((a: CategoryBucket, b: CategoryBucket) => b.cents - a.cents);
    const top = rows.length > 0 ? rows[0] : null;
    const head = top !== null ? `头号开销是${top.name}，占 ${Math.round((top.cents / total) * 100)}%；` : '';
    const r = this.deltaRatio();
    const tail = r === null
      ? '这是第一段可对比的期间。'
      : `整体${r >= 0 ? '多花 ' : '少花 '}${formatYuan(Math.abs(total - this.prevTotal()))}（${Math.abs(r * 100).toFixed(1)}%）。`;
    return head + tail;
  }

  /** 环图重绘指纹（金额/颜色/主题都进指纹） */
  private donutSignature(): string {
    let s = `${this.tier}-${this.anchorMonth}-${this.themeName}-${this.activeTotal()}-`;
    for (const slice of this.donutSlices()) {
      s += `${slice.value}:${slice.color};`;
    }
    return s;
  }

  private switchTier(v: number): void {
    this.tier = v;
    // Web switchTier('year')：锚点落到当年 1 月
    if (v === 1) {
      this.anchorMonth = `${this.anchorYear()}-01`;
    }
    this.load();
  }

  private shift(delta: number): void {
    if (this.tier === 2) {
      return;
    }
    if (this.tier === 0) {
      this.anchorMonth = shiftMonth(this.anchorMonth, delta);
    } else {
      this.anchorMonth = `${Number(this.anchorYear()) + delta}-01`;
    }
    this.load();
  }

  /** 跳年度报告屏（web $router.push annual-summary?year=） */
  private openAnnual(): void {
    AppStorage.setOrCreate('annualYear', this.anchorYear());
    AppStorage.setOrCreate('activeScreen', 'annual');
  }

  // ══════════════ ① 页头 report-head ══════════════

  @Builder
  headCard() {
    Column() {
      // toolbar 第一行：Seg 三档 + period-nav
      Row({ space: 10 }) {
        Row({ space: this.isCyber() ? 0 : 4 }) {
          this.segBtn('本月', 0)
          this.segBtn('本年', 1)
          this.segBtn('全部', 2)
        }
        .padding(4)
        .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .border({ width: this.tok().borderW, color: this.tok().line })

        // 右半区吃剩余宽度（layoutWeight），标签占中间余量 —— 之前 minWidth 116vp
        // 把整条日期顶出了卡片（用户报「日期都飞出去了」）
        Row({ space: 4 }) {
          this.periodChevron('‹', -1)
          Text(this.periodLabel())
            .onClick(() => {
              this.calYearV = Number(this.anchorMonth.substring(0, 4));
              this.calOpen = true;
            })
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber()))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .layoutWeight(1)
          this.periodChevron('›', 1)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // toolbar 第二行：年度报告入口（web margin-left:auto，移动端换行后靠右）
      Row() {
        this.annualBtn()
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 8 })

      // report-facts：期间支出大数 + 环比/对比/日均/笔数
      Column({ space: 6 }) {
        Column({ space: 2 }) {
          Text('期间支出')
            .fontSize(10.5)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink2)
          Text(formatYuan(this.activeTotal()))
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber()))
            .letterSpacing(-0.52)
            .fontFeature('"tnum" on')
            .fontColor(this.tok().ink)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)

        Flex({
          wrap: FlexWrap.Wrap,
          alignItems: ItemAlign.Center,
          space: { main: LengthMetrics.px(10), cross: LengthMetrics.px(8) }
        }) {
          if (this.deltaRatio() !== null) {
            Row({ space: 3 }) {
              Text(this.deltaArrow())
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.deltaToneColor())
              Text(this.deltaPctText())
                .fontSize(10.5)
                .fontWeight(FontWeight.Bold)
                .fontFamily(fontMonoOf())
                .fontFeature('"tnum" on')
                .fontColor(this.deltaToneColor())
            }
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({ width: this.isCyber() ? 1 : 1.5, color: this.deltaToneColor() })
          }
          this.factItem('对比', formatYuan(this.prevTotal()))
          this.factItem('日均', formatYuan(this.perDayCents()))
          this.factItem('笔数', `${this.activeCount()}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 14 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** rf-i：标签 + 加粗数值（b = mono 600 ink） */
  @Builder
  factItem(label: string, value: string) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(10.5)
        .fontColor(this.tok().ink2)
      Text(value)
        .fontSize(10.5)
        .fontWeight(FontWeight.Medium)
        .fontFamily(fontMonoOf())
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** seg-btn（app.css:357） */
  @Builder
  segBtn(label: string, value: number) {
    Text(label)
      .fontSize(this.isCyber() ? 10.5 : 12)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .letterSpacing(this.isCyber() ? 1.05 : 0)
      .fontColor(this.tier === value
        ? (this.isCyber() ? this.tok().accent : this.tok().accentInk)
        : this.tok().ink2)
      .textAlign(TextAlign.Center)
      .padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor(this.tier === value
        ? (this.isCyber() ? 'rgba(0,255,136,0.1)' : this.tok().accent)
        : Color.Transparent)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: 2,
        color: this.tier === value && !this.isCyber() ? this.tok().line2 : Color.Transparent
      })
      .onClick(() => {
        this.switchTier(value);
      })
  }

  /** period-nav 的 ‹ ›（icon-btn 38px；全部档禁用 → 半透明） */
  @Builder
  periodChevron(symbol: string, delta: number) {
    Text(symbol)
      .fontSize(16)
      .fontColor(this.tok().ink2)
      .width(30)
      .height(30)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({ width: this.tok().borderW, color: this.tok().line })
      .opacity(this.tier === 2 ? 0.45 : 1)
      .onClick(() => {
        if (this.tier !== 2) {
          this.shift(delta);
        }
      })
  }

  /** 年度报告按钮（web PBtn ghost sm + Sparkles） */
  @Builder
  annualBtn() {
    Row({ space: 7 }) {
      Text('✦')
        .fontSize(12)
        .fontColor(this.tok().ink2)
      Text(`${this.anchorYear()} 年度报告`)
        .fontSize(this.isCyber() ? 11 : 11.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .letterSpacing(this.isCyber() ? 1.54 : 0)
        .fontColor(this.tok().ink2)
    }
    .alignItems(VerticalAlign.Center)
    .height(30)
    .padding({ left: 11, right: 11 })
    .backgroundColor(Color.Transparent)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
    .border({ width: this.tok().borderW, color: this.isCyber() ? this.tok().line : Color.Transparent })
    .onClick(() => {
      this.openAnnual();
    })
  }

  // ══════════════ ② 支出构成 report-compose ══════════════

  @Builder
  composeCard() {
    Column() {
      // card-h：card-t + chips（移动端 card-cap 隐藏、chips 全宽横滑）
      Column({ space: 8 }) {
        Text('支出构成')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Scroll() {
          Row({ space: 7 }) {
            this.dimChip('分类', 'cat')
            this.dimChip('支付', 'pay')
            this.dimChip('记录人', 'owner')
            this.dimChip('节奏', 'week')
          }
          .padding({ bottom: 2 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.dimRows().length === 0) {
        Text('这个期间还没有构成数据')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 34, bottom: 34, left: 10, right: 10 })
      } else {
        Column({ space: 12 }) {
          // compose-visual
          if (this.dim === 'cat') {
            DonutChart({
              slices: this.donutSlices(),
              tokens: this.tok(),
              signature: this.donutSignature(),
              ringSize: 136,
              centerLabel: '合计',
              centerValue: formatYuan(this.activeTotal()),
              isCyber: this.isCyber()
            })
          } else if (this.dim === 'week') {
            this.weekBars()
          } else {
            this.dimBars()
          }

          // compose-list：移动端全宽虚线图例行
          Column() {
            ForEach(this.dimRows(), (r: DimRow, idx: number) => {
              Row({ space: 8 }) {
                Row()
                  .width(9)
                  .height(9)
                  .borderRadius(3)
                  .backgroundColor(r.color)
                Text(r.name)
                  .fontSize(11.5)
                  .fontColor(this.tok().ink)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(formatYuan(r.cents))
                  .fontSize(11.5)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(this.tok().ink)
                  .width(64)
                  .textAlign(TextAlign.End)
                Text(`${this.activeTotal() > 0 ? Math.round((r.cents / this.activeTotal()) * 100) : 0}%`)
                  .fontSize(10)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(this.tok().ink3)
                  .width(32)   // Web 移动端图例栅格是 9px/1fr/64px/32px（views.css:1148-1157）
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({ top: 6, bottom: 6 })
              .border({
                width: idx < this.dimRows().length - 1 ? { bottom: 1 } : { bottom: 0 },
                color: this.tok().line,
                style: BorderStyle.Dashed
              })
            }, (r: DimRow) => `${r.name}-${r.cents}`)
          }
          .width('100%')
        }
        .width('100%')
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

  /** 四维 chip（app.css:383；is-on 琥珀底） */
  @Builder
  dimChip(label: string, value: string) {
    Text(label)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .letterSpacing(this.isCyber() ? 0.6 : 0)
      .fontColor(this.dim === value
        ? (this.isCyber() ? this.tok().accent : this.tok().onColor)
        : this.tok().ink2)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .backgroundColor(this.dim === value
        ? (this.isCyber() ? 'rgba(0,255,136,0.1)' : this.tok().amber)
        : (this.isCyber() ? Color.Transparent : this.tok().surface))
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.isCyber() ? 1 : 2,
        color: this.dim === value
          ? (this.isCyber() ? this.tok().accent : this.tok().line2)
          : this.tok().line
      })
      .shadow(this.dim === value && !this.isCyber()
        ? parseShadow(`2px 2px 0 ${this.tok().line2}`) as ShadowOptions
        : this.dim === value && this.isCyber()
          ? { radius: 12, offsetX: 0, offsetY: 0, color: 'rgba(0,255,136,0.3)' } as ShadowOptions
          : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
      .onClick(() => {
        this.dim = value;
      })
  }

  /** 节奏维度：7 根星期柱（views.css:291，移动端 h112 gap6） */
  @Builder
  weekBars() {
    Row({ space: 6 }) {
      ForEach(this.dimRows(), (r: DimRow) => {
        Column({ space: 6 }) {
          Text(r.cents > 0 ? formatCompactCents(r.cents) : '')
            .fontSize(8.5)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink3)
          Column()
            .width('100%')
            .constraintSize({ maxWidth: 30 })
            .height(Math.max(3, Math.round((r.cents / this.dimMax()) * 80)))
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().accent)
            .borderRadius({ topLeft: 6, topRight: 6, bottomLeft: 2, bottomRight: 2 })
            .border({
              width: this.isCyber() ? 0 : 1,
              color: this.tok().line2
            })
            .shadow(this.isCyber()
              ? { radius: 12, offsetX: 0, offsetY: -2, color: 'rgba(0,255,136,0.6)' } as ShadowOptions
              : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
          Text(r.name.substring(r.name.length - 1))
            .fontSize(9)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink3)
        }
        .layoutWeight(1)
        .height(112)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
      }, (r: DimRow) => `${r.name}-${r.cents}`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Bottom)
  }

  /** 支付/记录人维度：条形排名（62px 名 | 10px 轨道 | 76px 值） */
  @Builder
  dimBars() {
    Column({ space: 8 }) {
      ForEach(this.dimRows(), (r: DimRow) => {
        Row({ space: 10 }) {
          Text(r.name)
            .fontSize(11.5)
            .fontColor(this.tok().ink2)
            .width(62)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(10)
              .backgroundColor(this.tok().surface3)
              .borderRadius(this.tok().rPill)
            Row()
              .width(`${Math.max(3, Math.round((r.cents / this.dimMax()) * 100))}%`)
              .height(10)
              .backgroundColor(r.color)
              .borderRadius(this.tok().rPill)
          }
          .layoutWeight(1)
          Text(formatYuan(r.cents))
            .fontSize(11)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.tok().ink2)
            .width(76)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (r: DimRow) => `${r.name}-${r.cents}`)
    }
    .width('100%')
  }

  // ══════════════ ③ 涨跌榜 + 还款节奏 ══════════════

  @Builder
  moversCard() {
    Column() {
      this.cardHead('涨跌榜', '分类环比 · 按差额排序')
      if (this.movers().length > 0) {
        Column({ space: 10 }) {
          ForEach(this.movers(), (m: MoverView) => {
            Row({ space: 9 }) {
              // cat-ic 30：12% 分类色底 + 45% 分类色描边
              // 必须用 Stack 包住再给尺寸 —— 直接把 width/height 加在 SymbolGlyph 上，
              // 字形会贴在左上角（这就是「报表图标和流水页没对齐、看着错乱」的原因）
              Stack() {
                CatIconView({ catName: m.name, iconSize: 17, color: m.color })
              }
              .width(30)
              .height(30)
              .borderRadius(this.isCyber() ? 1 : 9)
              .backgroundColor(mixHex(m.color, this.tok().surface, 0.12))
              .border({ width: 1, color: mixHex(m.color, this.tok().surface, 0.45) })

              Column({ space: 2 }) {
                Text(m.name)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tok().ink)
                  .maxLines(1)
                Text(`${formatYuan(m.now)} / 上期 ${formatYuan(m.before)}`)
                  .fontSize(10)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(this.tok().ink3)
                  .maxLines(1)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Column({ space: 1 }) {
                Text(`${m.diff > 0 ? '+' : '-'}${formatYuan(Math.abs(m.diff))}`)
                  .fontSize(10.5)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(m.diff > 0 ? this.tok().danger : this.tok().ok)
                Text(this.moverPct(m))
                  .fontSize(10)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .opacity(0.75)
                  .fontColor(m.diff > 0 ? this.tok().danger : this.tok().ok)
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding({ left: 10, right: 10, top: 9, bottom: 9 })
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
            .border({ width: 1, color: this.tok().line })
          }, (m: MoverView) => `${m.categoryId}-${m.diff}`)
        }
        .width('100%')
      } else {
        Text(this.tier === 0 ? '该期间没有可对比的分类' : '切到「月」档看涨跌')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 34, bottom: 34, left: 10, right: 10 })
      }
      Text(this.conclusion())
        .fontSize(11)
        .lineHeight(19)
        .fontColor(this.tok().ink2)
        .width('100%')
        .margin({ top: 12 })
        .padding({ top: 10 })
        .border({ width: { top: 1 }, color: this.tok().line, style: BorderStyle.Dashed })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 涨跌百分比（上期为 0 → 新增） */
  private moverPct(m: MoverView): string {
    return m.before > 0 ? `${Math.round((m.diff / m.before) * 100)}%` : '新增';
  }

  @Builder
  repayCard() {
    Column() {
      this.cardHead('还款节奏', '近 6 个月 · 按账期')
      Row({ space: 8 }) {
        ForEach(this.repaySteps(), (r: RollingMonth) => {
          Column({ space: 5 }) {
            Text((r.totalCents ?? 0) > 0 ? formatCompactCents(r.totalCents ?? 0) : '')
              .fontSize(8.5)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
            Column()
              .width('100%')
              .height(Math.max(4, Math.round(((r.totalCents ?? 0) / this.repayMax()) * 64)))
              .backgroundColor(this.tok().pink)
              .borderRadius({ topLeft: 5, topRight: 5, bottomLeft: 0, bottomRight: 0 })
              .border({
                width: this.isCyber() ? 0 : 1,
                color: this.tok().line2
              })
              .shadow(this.isCyber()
                ? { radius: 12, offsetX: 0, offsetY: -2, color: 'rgba(255,0,255,0.6)' } as ShadowOptions
                : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
            Text(`${Number(r.month.substring(5, 7))}月`)
              .fontSize(9)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
          }
          .layoutWeight(1)
          .height(96)
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
        }, (r: RollingMonth) => r.month)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 卡头：card-t + card-cap（app.css:306/308/315） */
  @Builder
  cardHead(title: string, cap: string) {
    Row({ space: 10 }) {
      Text(title)
        .fontSize(this.isCyber() ? 12.5 : 15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .letterSpacing(this.isCyber() ? 1.25 : 0)
        .fontColor(this.tok().ink)
      Blank()
      Text(cap)
        .fontSize(9.5)
        .letterSpacing(1.52)
        .fontFamily(fontMonoOf())
        .fontColor(this.tok().ink3)
    }
    .width('100%')
    .margin({ bottom: 13 })
    .alignItems(VerticalAlign.Center)
  }

  // ══════════════ ④ 年度报告大横幅 ══════════════

  @Builder
  annualBanner() {
    Row({ space: 14 }) {
      Column({ space: 2 }) {
        Text(`${this.anchorYear()} 年度报告已生成`)
          .fontSize(this.isCyber() ? 13 : 16)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontDisplayOf(false))
          .letterSpacing(this.isCyber() ? 1.56 : 0)
          .fontColor(this.isCyber() ? this.tok().accent : '#FFFFFF')
          .maxLines(1)
        Text('年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势')
          .fontSize(11)
          .fontColor(this.isCyber() ? this.tok().accent : '#FFFFFF')
          .opacity(0.9)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(18)
        .fontColor(this.isCyber() ? this.tok().accent : '#FFFFFF')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 18, right: 18, top: 16, bottom: 16 })
    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rCard))
    .border({
      width: this.isCyber() ? 1 : 2,
      color: this.isCyber() ? this.tok().accent : this.tok().line2
    })
    .linearGradient({
      angle: 100,
      colors: this.isCyber()
        ? [['rgba(0,255,136,0.14)', 0], ['rgba(0,212,255,0.06)', 1]]
        : [[this.tok().accent, 0], ['#A78BFA', 0.65], [this.tok().pink, 1]]
    })
    .shadow(this.isCyber()
      ? { radius: 26, offsetX: 0, offsetY: -10, color: 'rgba(0,255,136,0.7)' } as ShadowOptions
      : parseShadow(`5px 5px 0 ${this.tok().line2}`) as ShadowOptions)
    .onClick(() => {
      this.openAnnual();
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
    Scroll() {
      Column({ space: 12 }) {
        this.headCard()
        this.composeCard()
        this.moversCard()
        this.repayCard()
        this.annualBanner()
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

      // 期间快选月历
      if (this.calOpen) {
        this.periodCalendar()
      }
    }
    .width('100%')
    .height('100%')
  }
}

/** 紧凑金额（web formatCompact）：万元以下舍角分，万元以上用「万」 */
function formatCompactCents(cents: number): string {
  const abs = Math.abs(cents);
  const sign = cents < 0 ? '-' : '';
  if (abs < 1000000) {
    const yuan = Math.round(abs / 100);
    return `${sign}¥${String(yuan).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
  }
  const wan = abs / 1000000;
  return `${sign}¥${wan >= 100 ? wan.toFixed(0) : wan.toFixed(1)}万`;
}

/** 服务端可能没给的比率 → null（undefined * 100 = NaN → 界面出现 NaN%） */
function ratioOf(r: number | null | undefined): number | null {
  return typeof r === 'number' && Number.isFinite(r) ? r : null;
}

const CAL_MONTHS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

/** (年, 月) → 'YYYY-MM' */
function monthKeyOf(year: number, month: number): string {
  return `${year}-${month < 10 ? '0' + month : String(month)}`;
}

function currentMonthKey(): string {
  const now = new Date();
  const m = now.getMonth() + 1;
  return `${now.getFullYear()}-${m < 10 ? '0' + m : String(m)}`;
}
