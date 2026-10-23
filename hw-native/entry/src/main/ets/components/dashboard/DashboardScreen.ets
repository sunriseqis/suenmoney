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
import { ThemeManager } from '../../common/theme/ThemeManager';
import { ThemeTokens } from '../../common/theme/AppTheme';
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
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
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
      await this.loadTodos();
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

  private async loadTodos(): Promise<void> {
    const body = await Api.planTodos(todayKey());
    const list: TodoView[] = [];
    for (const t of body.todos) {
      const days = daysUntil(t.repaymentDate, todayKey());
      let tone = 'calm';
      if (days < 0) {
        tone = 'late';
      } else if (days <= 1) {
        tone = 'soon';
      }
      list.push({
        id: t.id,
        planName: t.planName,
        periodSeq: t.periodSeq,
        amountCents: t.amountCents,
        repaymentDate: t.repaymentDate,
        willAutoPost: t.willAutoPost,
        tone: tone,
        label: urgencyLabel(t.repaymentDate, todayKey())
      });
    }
    this.todos = list;
  }

  /** 待办动作：确认/入账 + 忽略（忽略不可逆，收在「更多」后面） */
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
        this.tierButton('月', 0)
        this.tierButton('年', 1)
        this.tierButton('全部', 2)
        Blank()
        if (this.tier === 0) {
          Button('‹')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tokens.surface2)
            .fontColor(this.tokens.ink2)
            .onClick(() => {
              this.shiftMonth(-1);
            })
          Text(this.anchorMonth)
            .fontSize(11)
            .fontColor(this.tokens.ink2)
          Button('›')
            .fontSize(14)
            .height(26)
            .width(30)
            .backgroundColor(this.tokens.surface2)
            .fontColor(this.tokens.ink2)
            .onClick(() => {
              this.shiftMonth(1);
            })
        }
      }
      .width('100%')

      // 待办提醒：有则显示、无则整条不渲染（与移动 Web 同一机制）
      if (this.todos.length > 0) {
        Column() {
          Row({ space: 6 }) {
            Text(`${this.todos.length} 笔待办`)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.todos[0].tone === 'late' ? this.tokens.danger : this.tokens.ink)
            Blank()
            Text(this.todoOpen ? '收起' : '展开')
              .fontSize(10)
              .fontColor(this.tokens.ink3)
          }
          .width('100%')
          .padding(10)
          .onClick(() => {
            this.todoOpen = !this.todoOpen;
          })

          if (this.todoOpen) {
            ForEach(this.todos, (todo: TodoView) => {
              Row({ space: 8 }) {
                // 颜色标记只给一个：左侧 3px 条，不整卡上色
                Divider()
                  .vertical(true)
                  .strokeWidth(3)
                  .color(todo.tone === 'late' ? this.tokens.danger : (todo.tone === 'soon' ? this.tokens.amber : this.tokens.line))
                  .height(28)
                Column({ space: 2 }) {
                  Text(`${todo.periodSeq}期 · ${todo.planName}`)
                    .fontSize(11)
                    .fontColor(this.tokens.ink)
                    .maxLines(1)
                  Text(`${todo.label} · ${formatYuan(todo.amountCents)}`)
                    .fontSize(9)
                    .fontColor(this.tokens.ink3)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button(todo.willAutoPost ? '确认' : '入账')
                  .fontSize(11)
                  .height(26)
                  .backgroundColor(this.tokens.surface2)
                  .fontColor(this.tokens.ink)
                  .onClick(() => {
                    this.actTodo(todo, 'confirm');
                  })
                // 危险动作收进「更多」：跳过不可逆，不能与主按钮同权重（decisions）
                Button('更多')
                  .fontSize(10)
                  .height(26)
                  .backgroundColor(this.tokens.surface)
                  .fontColor(this.tokens.ink3)
                  .bindMenu([
                    {
                      value: '忽略本期',
                      action: () => {
                        this.actTodo(todo, 'skip');
                      }
                    }
                  ])
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            }, (todo: TodoView) => todo.id)
          }
        }
        .width('100%')
        .backgroundColor(this.tokens.surface2)
        .borderRadius(this.tokens.rMd)
      }

      // 大金额 + 环比
      Row({ space: 6 }) {
        Text('¥')
          .fontSize(16)
          .fontColor(this.tokens.ink3)
        Text(formatYuan(this.totalCents).replace('¥', ''))
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tokens.ink)
        if (this.deltaRatio() !== null) {
          Text(`${(this.deltaRatio()! * 100).toFixed(1)}%`)
            .fontSize(11)
            .fontColor(this.deltaRatio()! > 0 ? this.tokens.danger : this.tokens.mint)
        }
      }
      .width('100%')

      // 三项指标
      Row() {
        this.metric('日均', formatYuan(this.perDayCents))
        this.metric('笔数', `${this.count} 笔`)
        this.metric('本月要还', formatYuan(this.creditDueCents))
      }
      .width('100%')

      // 构成堆叠条 + 图例（仅月档有分类构成）
      if (this.tier === 0 && this.monthReport !== null && this.monthReport.categories.length > 0) {
        this.composition(this.monthReport)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  @Builder
  tierButton(label: string, value: number) {
    Button(label)
      .fontSize(11)
      .height(26)
      .backgroundColor(this.tier === value ? this.tokens.accent : this.tokens.surface2)
      .fontColor(this.tier === value ? this.tokens.accentInk : this.tokens.ink3)
      .onClick(() => {
        this.tier = value;
        this.loading = true;
        this.reload().then(() => {
          this.loading = false;
        });
      })
  }

  @Builder
  metric(label: string, value: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(9)
        .fontColor(this.tokens.ink3)
      Text(value)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 构成：一条堆叠条 + 前四条图例（不做环图 —— 环图是报表页的活） */
  @Builder
  composition(report: MonthlyReport) {
    Column({ space: 6 }) {
      Row() {
        ForEach(report.categories.slice(0, 5), (cat: CategoryBucketView, index: number) => {
          Row()
            .layoutWeight(Math.max(1, Math.round(cat.ratio * 100)))
            .height(8)
            .backgroundColor(chartColor(this.tokens, hashIndex(cat.categoryId)))
        }, (cat: CategoryBucketView) => cat.categoryId)
      }
      .width('100%')
      .borderRadius(4)
      .clip(true)

      ForEach(report.categories.slice(0, 4), (cat: CategoryBucketView) => {
        Row({ space: 6 }) {
          Row()
            .width(8)
            .height(8)
            .backgroundColor(chartColor(this.tokens, hashIndex(cat.categoryId)))
            .borderRadius(2)
          Text(cat.name)
            .fontSize(10)
            .fontColor(this.tokens.ink2)
            .layoutWeight(1)
          Text(`${(cat.ratio * 100).toFixed(0)}%`)
            .fontSize(10)
            .fontColor(this.tokens.ink3)
          Text(formatYuan(cat.cents))
            .fontSize(10)
            .fontColor(this.tokens.ink2)
        }
        .width('100%')
      }, (cat: CategoryBucketView) => cat.categoryId)
    }
    .width('100%')
  }

  /** 12 个月热力：金额越高块越亮（不做彩虹色，避免与分类色混淆） */
  @Builder
  heat() {
    Column({ space: 6 }) {
      Text('近 12 个月')
        .fontSize(10)
        .fontColor(this.tokens.ink3)
        .width('100%')
      Row({ space: 4 }) {
        ForEach(this.heatPoints(), (point: MonthPoint) => {
          Column({ space: 2 }) {
            Column()
              .width('100%')
              .height(26)
              .backgroundColor(this.tokens.accent)
              .opacity(heatOpacity(point.totalCents, this.maxHeat()))
              .borderRadius(4)
            Text(point.month.substring(5, 7))
              .fontSize(8)
              .fontColor(this.tokens.ink3)
          }
          .layoutWeight(1)
        }, (point: MonthPoint) => point.month)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
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
        .fontColor(this.tokens.ink3)
        .width('100%')
      Row() {
        this.metric('累计支出', formatYuan(this.summary === null ? 0 : this.summary.totalCents))
        this.metric('记录天数', `${this.summary === null ? 0 : this.summary.recordedDays} 天`)
        this.metric('月均', formatYuan(this.summary === null ? 0 : this.summary.monthlyAverageCents))
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(10)
            .fontColor(this.offline ? this.tokens.ink3 : this.tokens.danger)
            .width('100%')
        }
        this.hero()
        if (this.tier === 0) {
          this.heat()
          if (this.summary === null) {
            Text('累计数据未加载')
              .fontSize(10)
              .fontColor(this.tokens.ink3)
          } else {
            this.cumulative()
          }
        }
        if (this.loading) {
          Text('加载中…')
            .fontSize(10)
            .fontColor(this.tokens.ink3)
        }
      }
      .width('100%')
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens.bg)
    .onAppear(() => {
      // 累计数据单独取一次（与月档无关）
      Api.summaryReport().then((body) => {
        this.summary = body.report;
      }).catch(() => {
      });
    })
  }
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
