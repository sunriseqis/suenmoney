/**
 * 概况屏（H4）—— 照 Web 移动端现状（DashboardView.vue ≤860px）1:1 复刻。
 *
 * 单列三卡（views.css:991：overview-grid 移动端单列、gap 12）：
 *   og-hero（card--pop）  期间 Seg + period-nav + 待办提醒条 + 大金额 + 环比胶囊
 *                         + 三指标 + 构成堆叠条/图例 + 展开待办（确认/入账 + 更多→忽略本期）
 *   og-heat               月度支出热力：近 12 个月 4 列热力格（点格去报表）+ 近 12 月合计
 *   og-cum                累计与跨度：5 行 kv
 *
 * 数据全部来自报表接口（月/年/汇总三个并发拉），前端不重算合计。
 * 待办动作与流水页不同：这里带「确认 / 入账 / 忽略本期」动作层（Web 概况页现状）。
 */

import { Api, CategoryBucket, MonthlyReport, SummaryReport, YearlyReport } from '../../common/net/Api';
import { LengthMetrics } from '@kit.ArkUI';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { cardShadow, fontBodyOf, fontDisplayOf, fontMonoOf, mixHex, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, slotOf } from '../../common/theme/Palette';
import { formatMonthLabel, formatYuan, shiftMonth } from '../../common/contract/Contract';

/** 构成条/图例的一行（web composeRows） */
export interface ComposeRow {
  id: string;
  name: string;
  cents: number;
  color: string;
}

/** 待办行（web dueTodos 的展示模型） */
export interface DashTodo {
  id: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  repaymentDate: string;
  willAutoPost: boolean;
  daysUntil: number;
}

/** 近 12 月格子（rolling12Months 的展示模型） */
export interface Rolling {
  month: string;
  totalCents: number;
}

@Component
export struct DashboardScreen {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 0=本月 1=本年 2=全部 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  /** 展开后的待办（web alertOpen） */
  @State todoOpen: boolean = false;

  @State monthReport: MonthlyReport | null = null;
  @State yearReport: YearlyReport | null = null;
  @State summary: SummaryReport | null = null;
  @State todos: DashTodo[] = [];
  @State loading: boolean = true;
  @State errorText: string = '';
  /** 轻提示（web useToast） */
  @State toastText: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private reload(): void {
    this.load();
    this.loadTodos();
  }

  /** 三个报表并发拉（web load()：失败置 null，不清屏以外的状态） */
  private async load(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    let m: MonthlyReport | null = null;
    let y: YearlyReport | null = null;
    let s: SummaryReport | null = null;
    try {
      m = (await Api.monthlyReport(this.anchorMonth)).report;
    } catch (e) {
      m = null;
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
    this.yearReport = y;
    this.summary = s;
    if (m === null && y === null && s === null) {
      this.errorText = '报表加载失败，请检查网络后重试';
    }
    this.loading = false;
  }

  private async loadTodos(): Promise<void> {
    try {
      const body = await Api.planTodos(todayKey());
      const list: DashTodo[] = [];
      for (const t of body.todos) {
        const days = daysUntilLocal(t.repaymentDate, todayKey());
        list.push({
          id: t.id,
          planName: t.planName,
          periodSeq: t.periodSeq,
          amountCents: t.amountCents,
          repaymentDate: t.repaymentDate,
          willAutoPost: t.willAutoPost,
          daysUntil: days
        });
      }
      // 逾期最前，其余按剩余天数升序
      list.sort((a: DashTodo, b: DashTodo) => a.daysUntil - b.daysUntil);
      this.todos = list;
    } catch (e) {
      this.todos = [];
    }
  }

  /**
   * 待办三个动作（web todoAction）：自动入账类「确认」(ack)，手动类「入账」(confirm)，
   * 两者都可「忽略」(skip)。
   */
  private async todoAction(todo: DashTodo, kind: string): Promise<void> {
    try {
      if (kind === 'skip') {
        await Api.skipTodo(todo.id);
        this.showToast('已忽略这笔待办');
      } else if (todo.willAutoPost) {
        await Api.ackTodo(todo.id);
        this.showToast('已确认并自动入账');
      } else {
        await Api.confirmTodo(todo.id);
        this.showToast('已手动入账');
      }
      await this.load();
      await this.loadTodos();
    } catch (e) {
      this.showToast('操作失败，请重试');
    }
  }

  /** 轻提示：2 秒后自动消失 */
  private showToast(text: string): void {
    this.toastText = text;
    setTimeout(() => {
      this.toastText = '';
    }, 2000);
  }

  // ── 派生数据（与 Web computed 一一对应）──────────────────────────────

  private anchorYear(): string {
    return this.anchorMonth.substring(0, 4);
  }

  private totalCents(): number {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.totalCents : 0;
    }
    if (this.tier === 1) {
      return this.yearReport !== null ? this.yearReport.totalCents : 0;
    }
    return this.summary !== null ? this.summary.totalCents : 0;
  }

  private prevCents(): number {
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
      return this.monthReport !== null ? this.monthReport.change.ratio : null;
    }
    if (this.tier === 1) {
      return this.yearReport !== null && this.yearReport.yearAgo !== undefined
        ? this.yearReport.yearAgo.changeRatio : null;
    }
    return null;
  }

  /** 环比胶囊三件套（builder 内禁止非空断言，拆成取值器） */
  private deltaArrow(): string {
    const r = this.deltaRatio();
    return r === null ? '' : (r > 0 ? '↑' : '↓');
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

  private countOf(): number {
    if (this.tier === 0) {
      return this.monthReport !== null ? this.monthReport.count : 0;
    }
    if (this.tier === 1) {
      return this.yearReport !== null ? this.yearReport.count : 0;
    }
    return this.summary !== null ? this.summary.count : 0;
  }

  /** 三指标（web metrics）：月档看日均/预计月末，年档看月均/最高月，全部档看月均/跨度 */
  private metricValues(): string[] {
    if (this.tier === 0) {
      const total = this.totalCents();
      const elapsed = elapsedDaysOf(this.anchorMonth);
      const days = daysInMonthOf(this.anchorMonth);
      const perDay = Math.round(total / elapsed);
      const projected = Math.round((total / elapsed) * days);
      return [formatYuan(perDay), `${this.countOf()} 笔`, formatYuan(projected)];
    }
    const monthAvg = this.summary !== null ? this.summary.monthlyAverageCents : 0;
    if (this.tier === 1) {
      const peak = this.yearReport !== null ? this.yearReport.peakMonth : null;
      return [formatYuan(monthAvg), `${this.countOf()} 笔`,
        peak !== null && peak !== undefined ? formatMonthLabel(peak.month) : '—'];
    }
    const span = Math.max(1, Math.round((this.summary !== null ? this.summary.recordedDays : 0) / 30));
    return [formatYuan(monthAvg), `${this.countOf()} 笔`, `${span} 个月`];
  }

  private metricLabels(): string[] {
    if (this.tier === 0) {
      return ['日均支出', '笔数', '预计月末'];
    }
    if (this.tier === 1) {
      return ['月均支出', '笔数', '最高月'];
    }
    return ['月均支出', '笔数', '记录跨度'];
  }

  /** 构成：前 4 类 + 其他（颜色走 chart 8 槽，与 Web dict.colorOf 同口径） */
  private composeRows(): ComposeRow[] {
    let cats: CategoryBucket[] = [];
    if (this.tier === 0) {
      cats = this.monthReport !== null ? this.monthReport.categories : [];
    } else if (this.tier === 1) {
      cats = this.yearReport !== null && this.yearReport.categories !== undefined ? this.yearReport.categories : [];
    } else {
      cats = this.summary !== null && this.summary.categories !== undefined ? this.summary.categories : [];
    }
    const rows: CategoryBucket[] = [];
    for (const c of cats) {
      if (c.cents > 0) {
        rows.push(c);
      }
    }
    rows.sort((a: CategoryBucket, b: CategoryBucket) => b.cents - a.cents);
    const out: ComposeRow[] = [];
    const top = rows.slice(0, 4);
    for (const c of top) {
      out.push({
        id: c.categoryId,
        name: c.name,
        cents: c.cents,
        color: chartColor(this.tok(), slotOf(c.color, c.categoryId))
      });
    }
    let rest = 0;
    for (const c of rows.slice(4)) {
      rest += c.cents;
    }
    if (rest > 0) {
      out.push({ id: '__rest', name: '其他', cents: rest, color: this.tok().ink3 });
    }
    return out;
  }

  private composeTotal(): number {
    let sum = 0;
    for (const r of this.composeRows()) {
      sum += r.cents;
    }
    return sum;
  }

  private percentOf(cents: number): number {
    const total = this.composeTotal();
    return total > 0 ? Math.round((cents / total) * 100) : 0;
  }

  /** 近 12 个月（月报的 rolling12） */
  private rolling12(): Rolling[] {
    if (this.monthReport === null) {
      return [];
    }
    const out: Rolling[] = [];
    for (const m of this.monthReport.rolling12Months) {
      out.push({ month: m.month, totalCents: m.totalCents ?? 0 });
    }
    return out;
  }

  private rolling12Max(): number {
    let max = 1;
    for (const m of this.rolling12()) {
      if (m.totalCents > max) {
        max = m.totalCents;
      }
    }
    return max;
  }

  private rolling12Total(): number {
    let sum = 0;
    for (const m of this.rolling12()) {
      sum += m.totalCents;
    }
    return sum;
  }

  /** 热力格底色（web heatDot：0 → surface-3，否则 accent 按占比混色 18%~100%） */
  private heatColor(cents: number): string {
    if (cents <= 0) {
      return this.tok().surface3;
    }
    const pct = Math.min(1, cents / this.rolling12Max());
    return mixHex(this.tok().accent, this.tok().surface3, (18 + pct * 82) / 100);
  }

  /** 待办合计 / 逾期数 */
  private dueTotalCents(): number {
    let sum = 0;
    for (const t of this.todos) {
      sum += t.amountCents;
    }
    return sum;
  }

  private overdueCount(): number {
    let n = 0;
    for (const t of this.todos) {
      if (t.daysUntil < 0) {
        n++;
      }
    }
    return n;
  }

  /** 提醒条圆点（web todoTone）：逾期→late；有需手动→soon；否则 calm */
  private todoDotColor(): string {
    if (this.overdueCount() > 0) {
      return this.tok().danger;
    }
    for (const t of this.todos) {
      if (!t.willAutoPost) {
        return this.tok().warn;
      }
    }
    return this.tok().ink3;
  }

  /** 紧急度三档（web urgencyLevel）：迟于还款日=late，0–1 天=soon，更远=calm */
  private urgencyColorOf(t: DashTodo): string {
    if (t.daysUntil < 0) {
      return this.tok().danger;
    }
    if (t.daysUntil <= 1) {
      return this.tok().warn;
    }
    return this.tok().ink3;
  }

  /** 概况大金额字号：clamp(36px, 5vw, 52px) 移动端约 38；位数多时收缩防撑爆 */
  private heroAmountSize(): number {
    const s = formatYuan(this.totalCents()).replace('¥', '');
    if (s.length <= 8) {
      return 38;
    }
    if (s.length <= 10) {
      return 30;
    }
    return 24;
  }

  private switchTier(v: number): void {
    this.tier = v;
    // Web switchTier('year')：锚点落到当年 1 月
    if (v === 1) {
      this.anchorMonth = `${this.anchorYear()}-01`;
    }
    this.load();
  }

  private shiftPeriod(delta: number): void {
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

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  // ══════════════ ① 主卡 og-hero（card--pop）══════════════

  @Builder
  ogHero() {
    Column() {
      // hero-eyebrow：期间 Seg + period-nav（全部档换 PTag）
      Row({ space: 8 }) {
        Row({ space: this.isCyber() ? 0 : 4 }) {
          this.eyebrowSegBtn('本月', 0)
          this.eyebrowSegBtn('本年', 1)
          this.eyebrowSegBtn('全部', 2)
        }
        .padding(4)
        .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .border({ width: this.tok().borderW, color: this.tok().line })

        if (this.tier !== 2) {
          // 右半区吃剩余宽度（layoutWeight），标签自己占中间余量 —— 这样永远不会把 › 顶出卡片
          Row({ space: 4 }) {
            this.periodChevron('‹', -1)
            Text(this.periodLabel())
              .fontSize(10.5)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink2)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .layoutWeight(1)
            this.periodChevron('›', 1)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.End)
          .alignItems(VerticalAlign.Center)
        } else {
          Text('全部记录')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink2)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.tok().surface2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({
              width: 1,
              color: this.tok().line,
              style: this.isCyber() ? BorderStyle.Solid : BorderStyle.Dashed
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // hero-todo：待办提醒条（没有待办时整条不渲染）
      if (this.todos.length > 0) {
        Row({ space: 8 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.todoDotColor())
          Text(`${this.todos.length} 笔待办`)
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tok().ink)
          Text(formatYuan(this.dueTotalCents()))
            .fontSize(10.5)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.tok().ink2)
          if (this.overdueCount() > 0) {
            Text(`${this.overdueCount()} 笔逾期`)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().danger)
          }
          Blank()
          Text(this.todoOpen ? '⌃' : '⌄')
            .fontSize(13)
            .fontColor(this.tok().ink2)
        }
        .width('100%')
        .margin({ top: 10 })
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(this.tok().surface2)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
        .border({ width: 1, color: this.tok().line })
        .onClick(() => {
          this.todoOpen = !this.todoOpen;
        })
      }

      // hero-amt：大金额（¥ 0.5em，基线对齐）
      Row({ space: 4 }) {
        Text('¥')
          .fontSize(this.heroAmountSize() * 0.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tok().ink2)
        Text(formatYuan(this.totalCents()).replace('¥', ''))
          .fontSize(this.heroAmountSize())
          .fontWeight(FontWeight.Bolder)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.14 : -1.33)
          .fontFeature('"tnum" on')
          .maxLines(1)
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 8, bottom: 4 })

      // hero-delta：环比胶囊 + 较上期
      Row({ space: 8 }) {
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
          .border({
            width: this.isCyber() ? 1 : 1.5,
            color: this.deltaToneColor()
          })
        }
        Text(`较${this.tier === 0 ? '上月' : (this.tier === 1 ? '去年' : '上一段')} ${formatYuan(this.prevCents())}`)
          .fontSize(11.5)
          .fontColor(this.tok().ink2)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // hero-metrics：三指标（上虚线）
      Row({ space: 10 }) {
        this.metricCell(this.metricLabels()[0], this.metricValues()[0])
        this.metricCell(this.metricLabels()[1], this.metricValues()[1])
        this.metricCell(this.metricLabels()[2], this.metricValues()[2])
      }
      .width('100%')
      .margin({ top: 16 })
      .padding({ top: 14 })
      .border({ width: { top: 1 }, color: this.tok().line, style: BorderStyle.Dashed })

      // stack-bar：构成堆叠条（flex 按金额）
      Row() {
        ForEach(this.composeRows(), (r: ComposeRow) => {
          Row()
            .layoutWeight(r.cents)
            .height('100%')
            .backgroundColor(r.color)
        }, (r: ComposeRow) => r.id)
      }
      .width('100%')
      .height(9)
      .margin({ top: 14 })
      .backgroundColor(this.tok().surface3)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({ width: 1, color: this.tok().line })
      .clip(true)

      // compose-legend：图例（dot + 名 + 百分比）
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(14), cross: LengthMetrics.px(6) } }) {
        ForEach(this.composeRows(), (r: ComposeRow) => {
          Row({ space: 5 }) {
            Row()
              .width(8)
              .height(8)
              .borderRadius(radiusOf(this.tok(), this.isCyber(), 2))
              .backgroundColor(r.color)
            Text(r.name)
              .fontSize(11)
              .fontColor(this.tok().ink2)
            Text(`${this.percentOf(r.cents)}%`)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontFamily(fontMonoOf())
              .fontFeature('"tnum" on')
              .fontColor(this.tok().ink2)
          }
          .alignItems(VerticalAlign.Center)
        }, (r: ComposeRow) => r.id)
      }
      .width('100%')
      .margin({ top: 9 })

      // hero-todos：展开后的待办（一行一条：色条 · N期·计划 · 自动/需手动 · 金额 · 动作）
      if (this.todoOpen && this.todos.length > 0) {
        Column() {
          ForEach(this.todos, (t: DashTodo, idx: number) => {
            this.todoLine(t, idx)
          }, (t: DashTodo) => t.id)
        }
        .width('100%')
        .margin({ top: 4 })
        .padding({ left: 10, right: 10, top: 2, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.isCyber() ? this.tok().line : this.tok().line2 })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 期间 Seg 按钮（web .seg-btn） */
  @Builder
  eyebrowSegBtn(label: string, value: number) {
    Text(label)
      .fontSize(this.isCyber() ? 10.5 : 12)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.tier === value
        ? (this.isCyber() ? this.tok().accent : this.tok().accentInk)
        : this.tok().ink2)
      .textAlign(TextAlign.Center)
      .padding({ left: 13, right: 13, top: 6, bottom: 6 })
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

  /** period-nav 的 ‹ ›（icon-btn 38px） */
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
      .onClick(() => {
        this.shiftPeriod(delta);
      })
  }

  /** 三指标格（web PStat） */
  @Builder
  metricCell(label: string, value: string) {
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

  /** 展开后的单条待办（web .todo-line，最后一条无下边线） */
  @Builder
  todoLine(t: DashTodo, idx: number) {
    Row({ space: 8 }) {
      Row()
        .width(4)
        .height(22)
        .borderRadius(2)
        .backgroundColor(this.urgencyColorOf(t))
      Text(`${t.periodSeq}期 · ${t.planName}`)
        .fontSize(11.5)
        .fontColor(this.tok().ink)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(t.willAutoPost ? '自动' : '需手动')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontMonoOf())
        .fontColor(this.urgencyColorOf(t))
      Text(formatYuan(t.amountCents))
        .fontSize(10.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontMonoOf())
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink)
      // 主动作：确认（自动类）/ 入账（手动类）
      Text(t.willAutoPost ? '确认' : '入账')
        .fontSize(11.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .fontColor(this.tok().ink2)
        .padding({ left: 11, right: 11, top: 4, bottom: 4 })
        .backgroundColor(Color.Transparent)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .border({
          width: this.isCyber() ? 1 : this.tok().borderW,
          color: this.isCyber() ? this.tok().line : Color.Transparent
        })
        .onClick(() => {
          this.todoAction(t, t.willAutoPost ? 'ack' : 'confirm');
        })
      // 危险动作收进「更多」（web more-menu）：跳过不可逆
      Text('更多')
        .fontSize(11)
        .fontFamily(fontMonoOf())
        .fontColor(this.tok().ink3)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
        .border({ width: 1, color: this.tok().line })
        .bindMenu([{
          value: '忽略本期',
          action: () => {
            this.todoAction(t, 'skip');
          }
        }])
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .border({
      width: idx < this.todos.length - 1 ? { bottom: 1 } : { bottom: 0 },
      color: this.tok().line
    })
  }

  // ══════════════ ② 月度热力 og-heat ══════════════

  @Builder
  ogHeat() {
    Column() {
      Row({ space: 10 }) {
        this.orb('#FBBF24', $r('sys.symbol.calendar'))
        Text('月度支出热力')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Blank()
        Text('近 12 个月 · 点击下钻')
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      // heat-grid：移动端 4 列（views.css:994），gap 5
      Grid() {
        ForEach(this.rolling12(), (cell: Rolling) => {
          GridItem() {
            Column({ space: 3 }) {
              Text(`${Number(cell.month.substring(5, 7))}月`)
                .fontSize(9)
                .fontFamily(fontMonoOf())
                .fontColor(this.tok().ink3)
              Text(cell.totalCents > 0 ? formatCompactCents(cell.totalCents) : '—')
                .fontSize(10)
                .fontWeight(FontWeight.Bold)
                .fontFamily(fontMonoOf())
                .fontFeature('"tnum" on')
                .fontColor(this.tok().ink)
                .maxLines(1)
              Row()
                .width('100%')
                .height(4)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                .backgroundColor(this.heatColor(cell.totalCents))
            }
            .width('100%')
            .padding({ left: 3, right: 3, top: 7, bottom: 6 })
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(this.tok().surface2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), 7))
            .border({
              width: 1,
              color: cell.month === currentMonthKey()
                ? (this.isCyber() ? this.tok().accent : this.tok().line2)
                : this.tok().line
            })
            .shadow(cell.month === currentMonthKey() && !this.isCyber()
              ? parseShadow(`2px 2px 0 ${this.tok().line2}`) as ShadowOptions
              : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
          }
          .onClick(() => {
            AppStorage.setOrCreate('activeScreen', 'report');
          })
        }, (cell: Rolling) => cell.month)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(5)
      .rowsGap(5)
      .width('100%')

      // og-card-foot：近 12 个月合计 + 打开报表
      Row({ space: 10 }) {
        Text('近 12 个月合计')
          .fontSize(10.5)
          .fontColor(this.tok().ink2)
        Text(formatYuan(this.rolling12Total()))
          .fontSize(10.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontMonoOf())
          .fontFeature('"tnum" on')
          .fontColor(this.tok().ink)
        Blank()
        Text('打开报表')
          .fontSize(11.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.tok().ink2)
          .padding({ left: 11, right: 11, top: 4, bottom: 4 })
          .onClick(() => {
            AppStorage.setOrCreate('activeScreen', 'report');
          })
      }
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

  // ══════════════ ③ 累计与跨度 og-cum ══════════════

  @Builder
  ogCum() {
    Column() {
      Row({ space: 10 }) {
        this.orb('#34D399', $r('sys.symbol.coins'))
        Text('累计与跨度')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
        Blank()
        Text('全部历史口径')
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      Column() {
        this.kvRow('历史累计', formatYuan(this.summary !== null ? this.summary.totalCents : 0))
        this.kvRow('记录笔数', `${this.summary !== null ? this.summary.count : 0} 笔`)
        this.kvRow('记录跨度', `${Math.max(1, Math.round((this.summary !== null ? this.summary.recordedDays : 0) / 30))} 个月 · ${this.summary !== null ? this.summary.years.length : 0} 年`)
        this.kvRow('月均支出', formatYuan(this.summary !== null ? this.summary.monthlyAverageCents : 0))
        this.kvRow('单笔均值', formatYuan(this.summary !== null && this.summary.perExpenseAverageCents !== undefined ? this.summary.perExpenseAverageCents : 0))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** kv 单行（web .kv） */
  @Builder
  kvRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(10.5)
        .fontColor(this.tok().ink2)
        .layoutWeight(1)
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontFamily(fontMonoOf())
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { bottom: 1 }, color: this.tok().line, style: BorderStyle.Dashed })
  }

  /** 悬浮圆图标（web .orb）：candy 贴纸感；cyber 切角线框 */
  @Builder
  orb(tone: string, icon: Resource) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([this.isCyber() ? this.tok().accent : '#1E293B'])
    }
    .width(34)
    .height(34)
    .borderRadius(this.isCyber() ? 1 : 17)
    .backgroundColor(this.isCyber() ? Color.Transparent : tone)
    .border({
      width: this.isCyber() ? 1 : 2,
      color: this.isCyber() ? this.tok().accent : this.tok().line2
    })
    .shadow(this.isCyber()
      ? { radius: 10, offsetX: 0, offsetY: -2, color: 'rgba(0,255,136,0.4)' } as ShadowOptions
      : parseShadow(`2px 2px 0 ${this.tok().line2}`) as ShadowOptions)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Column({ space: 12 }) {
          if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(10.5)
              .fontColor(this.tok().danger)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          this.ogHero()
          this.ogHeat()
          this.ogCum()
          if (this.loading) {
            Text('加载中…')
              .fontSize(10.5)
              .fontColor(this.tok().ink2)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 轻提示（web useToast → PToast）：底部居中、2 秒消失
      if (this.toastText !== '') {
        Text(this.toastText)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tok().bg)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(this.tok().ink)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .border({ width: 2, color: this.tok().line2 })
          .shadow(parseShadow('4px 4px 0 rgba(0,0,0,0.18)') as ShadowOptions)
          .margin({ bottom: 26 })
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

/** 该月有多少天（web daysInMonth：UTC 口径） */
function daysInMonthOf(month: string): number {
  const y = Number(month.substring(0, 4));
  const m = Number(month.substring(5, 7));
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** 这个月已过多少天（web elapsedDays）：历史/未来月份按整月算 */
function elapsedDaysOf(month: string): number {
  const total = daysInMonthOf(month);
  if (month !== currentMonthKey()) {
    return total;
  }
  const day = new Date().getDate();
  return Math.min(total, Math.max(1, day));
}

function currentMonthKey(): string {
  const now = new Date();
  const m = now.getMonth() + 1;
  return `${now.getFullYear()}-${m < 10 ? '0' + m : String(m)}`;
}

function todayKey(): string {
  const d = new Date();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}

function daysUntilLocal(target: string, from: string): number {
  const a = Date.UTC(
    Number(from.substring(0, 4)),
    Number(from.substring(5, 7)) - 1,
    Number(from.substring(8, 10))
  );
  const b = Date.UTC(
    Number(target.substring(0, 4)),
    Number(target.substring(5, 7)) - 1,
    Number(target.substring(8, 10))
  );
  return Math.round((b - a) / 86400000);
}
