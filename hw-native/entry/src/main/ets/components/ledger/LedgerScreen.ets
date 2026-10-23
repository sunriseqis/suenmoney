/**
 * 流水屏（H2）。
 *
 * 三档三形态（对齐移动 Web，不是可选项）：
 *   按月 → 逐笔明细（按消费日分组 + 日小计）
 *   按年 → 12 个月格（点格进入该月）
 *   全部 → 一年一格（点格进入该年）
 *
 * 数据来源：线上走接口，断网走本地库现算（离线 A 档）。
 * 金额一律来自服务端/本地的整数分，展示时才格式化。
 */
import { Api, ExpenseItem, MonthPoint, YearPoint } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { ExpenseDao } from '../../common/store/ExpenseDao';
import { CachedCategory, DictionaryDao } from '../../common/store/DictionaryDao';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, slotOf } from '../../common/theme/Palette';
import { formatYuan } from '../../common/contract/Contract';

const PAGE_SIZE = 100;

export interface LedgerDayGroup {
  date: string;
  cents: number;
  rows: ExpenseItem[];
}

@Component
export struct LedgerScreen {
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  /** 0=按月 1=按年 2=全部 */
  @State tier: number = 0;
  @State anchorMonth: string = currentMonthKey();
  @State anchorYear: string = currentMonthKey().substring(0, 4);
  @State rows: ExpenseItem[] = [];
  @State monthTotalCents: number = 0;
  @State monthCount: number = 0;
  @State cursor: string = '';
  @State hasMore: boolean = false;
  @State loading: boolean = false;
  @State offline: boolean = false;
  @State errorText: string = '';
  @State yearPoints: MonthPoint[] = [];
  @State yearTotalCents: number = 0;
  @State allYears: YearPoint[] = [];
  @State allTotalCents: number = 0;
  @State categoryNames: Map<string, CachedCategory> = new Map<string, CachedCategory>();
  @State paymentNames: Map<string, string> = new Map<string, string>();

  aboutToAppear(): void {
    this.reload();
  }

  /** 首次进入：先缓存字典（离线时要靠它显示分类名），再拉当月 */
  private async reload(): Promise<void> {
    this.errorText = '';
    this.loading = true;
    try {
      if (this.categoryNames.size === 0) {
        const cats = await Api.categories();
        await DictionaryDao.cacheCategories(cats.categories);
        this.categoryNames = await DictionaryDao.categoryNames();
        const pays = await Api.paymentMethods();
        await DictionaryDao.cachePayments(pays.paymentMethods);
        this.paymentNames = await DictionaryDao.paymentNames();
      }
      this.offline = false;
      await this.loadTier();
    } catch (e) {
      const err = e as ApiError;
      if (err.kind === 'network') {
        // 离线 A 档：本地现算
        this.offline = true;
        if (this.categoryNames.size === 0) {
          this.categoryNames = await DictionaryDao.categoryNames();
          this.paymentNames = await DictionaryDao.paymentNames();
        }
        await this.loadTier();
      } else {
        this.errorText = err.message;
      }
    } finally {
      this.loading = false;
    }
  }

  private async loadTier(): Promise<void> {
    if (this.tier === 0) {
      await this.loadMonth(true);
    } else if (this.tier === 1) {
      await this.loadYear();
    } else {
      await this.loadAll();
    }
  }

  /** 月档：第一页或翻页 */
  private async loadMonth(reset: boolean): Promise<void> {
    if (this.offline) {
      const local = await ExpenseDao.byMonth(this.anchorMonth);
      const total = await ExpenseDao.monthTotal(this.anchorMonth);
      this.rows = local;
      this.monthTotalCents = total.totalCents;
      this.monthCount = total.count;
      this.hasMore = false;
      return;
    }
    const page = await Api.expenses(this.anchorMonth, PAGE_SIZE, reset ? null : this.cursor);
    this.rows = reset ? page.items : this.rows.concat(page.items);
    this.cursor = page.nextCursor ?? '';
    this.hasMore = page.hasMore;
    // 顺手缓存，供断网时用
    await ExpenseDao.cache(page.items);
    const report = await Api.monthlyReport(this.anchorMonth);
    this.monthTotalCents = report.report.totalCents;
    this.monthCount = report.report.count;
  }

  private async loadYear(): Promise<void> {
    const body = await Api.yearlyReport(this.anchorYear);
    this.yearPoints = body.report.months;
    this.yearTotalCents = body.report.totalCents;
  }

  private async loadAll(): Promise<void> {
    const body = await Api.summaryReport();
    this.allYears = body.report.years;
    this.allTotalCents = body.report.totalCents;
  }

  /** 按消费日分组（组内小计），同一天的多笔归到一起 */
  private grouped(): LedgerDayGroup[] {
    const out: LedgerDayGroup[] = [];
    for (const row of this.rows) {
      const last = out.length > 0 ? out[out.length - 1] : null;
      if (last !== null && last.date === row.spendDate) {
        last.cents += row.amountCents;
        last.rows.push(row);
      } else {
        out.push({ date: row.spendDate, cents: row.amountCents, rows: [row] });
      }
    }
    return out;
  }

  /** 分类色（离线时字典可能为空 → 走哈希兜底，同一分类颜色仍稳定） */
  private categoryColorOf(row: ExpenseItem): string {
    const cat = this.categoryNames.get(row.categoryId);
    const colorField = cat !== undefined ? cat.color : row.parentCategoryColor ?? row.categoryColor;
    return chartColor(this.tokens, slotOf(colorField ?? '', row.categoryId));
  }

  private categoryNameOf(row: ExpenseItem): string {
    if (row.categoryName !== '') {
      return row.categoryName;
    }
    const cat = this.categoryNames.get(row.categoryId);
    return cat !== undefined ? cat.name : '—';
  }

  private paymentNameOf(row: ExpenseItem): string {
    if (row.paymentMethodName !== '') {
      return row.paymentMethodName;
    }
    const name = this.paymentNames.get(row.paymentMethodId);
    return name !== undefined ? name : '—';
  }

  @Builder
  tierTabs() {
    Row({ space: 6 }) {
      this.tierButton('按月', 0)
      this.tierButton('按年', 1)
      this.tierButton('全部', 2)
    }
    .width('100%')
  }

  @Builder
  tierButton(label: string, value: number) {
    Button(label)
      .fontSize(12)
      .height(30)
      .layoutWeight(1)
      .backgroundColor(this.tier === value ? this.tokens.accent : this.tokens.surface2)
      .fontColor(this.tier === value ? this.tokens.accentInk : this.tokens.ink2)
      .onClick(() => {
        this.tier = value;
        this.loading = true;
        this.loadTier().then(() => {
          this.loading = false;
        }).catch((e: ApiError) => {
          this.loading = false;
          this.errorText = e.message;
        });
      })
  }

  @Builder
  monthListView() {
    Column() {
      Row() {
        Text(this.anchorMonth)
          .fontSize(11)
          .fontColor(this.tokens.ink3)
        Blank()
        Text(`${this.monthCount} 笔 · ${formatYuan(this.monthTotalCents)}`)
          .fontSize(11)
          .fontColor(this.tokens.ink2)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 6 })

      List({ space: 6 }) {
        ForEach(this.grouped(), (group: LedgerDayGroup) => {
          ListItemGroup({ header: this.dayHeader(group) }) {
            ForEach(group.rows, (row: ExpenseItem) => {
              ListItem() {
                this.expenseRow(row)
              }
            }, (row: ExpenseItem) => row.id)
          }
        }, (group: LedgerDayGroup) => group.date)

        if (this.hasMore) {
          ListItem() {
            Button('加载更多')
              .width('100%')
              .height(36)
              .fontSize(12)
              .backgroundColor(this.tokens.surface2)
              .fontColor(this.tokens.ink2)
              .onClick(() => {
                this.loadMonth(false).then(() => {
                }).catch((e: ApiError) => {
                  this.errorText = e.message;
                });
              })
          }
        }
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  dayHeader(group: LedgerDayGroup) {
    Row() {
      Text(group.date)
        .fontSize(10)
        .fontColor(this.tokens.ink3)
      Blank()
      Text(formatYuan(group.cents))
        .fontSize(10)
        .fontColor(this.tokens.ink3)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 2 })
  }

  /** 行卡：色块首字 + 分类名 + 备注/支付/记录人 + 金额（对齐移动 Web 的行卡） */
  @Builder
  expenseRow(row: ExpenseItem) {
    Row({ space: 10 }) {
      Text(this.categoryNameOf(row).substring(0, 1))
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.categoryColorOf(row))
        .backgroundColor(this.tokens.surface2)
        .borderRadius(10)

      Column({ space: 2 }) {
        Text(this.categoryNameOf(row))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${row.note !== '' ? row.note + ' · ' : ''}${this.paymentNameOf(row)}`)
          .fontSize(10)
          .fontColor(this.tokens.ink3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(formatYuan(row.amountCents))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(row.amountCents < 0 ? this.tokens.mint : this.tokens.ink)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rMd)
    .border({ width: 1, color: this.tokens.line })
  }

  @Builder
  monthGridView() {
    Column() {
      Row() {
        Text(`${this.anchorYear} 年`)
          .fontSize(11)
          .fontColor(this.tokens.ink3)
        Blank()
        Text(formatYuan(this.yearTotalCents))
          .fontSize(11)
          .fontColor(this.tokens.ink2)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 6 })

      Grid() {
        ForEach(this.yearPoints, (point: MonthPoint) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(`${Number(point.month.substring(5, 7))} 月`)
                .fontSize(11)
                .fontColor(this.tokens.ink2)
              Text(formatYuan(point.totalCents))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tokens.ink)
              Text(`${point.count} 笔`)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
            .width('100%')
            .padding(8)
            .backgroundColor(this.tokens.surface)
            .borderRadius(this.tokens.rMd)
            .border({ width: 1, color: this.tokens.line })
            .onClick(() => {
              this.anchorMonth = point.month;
              this.tier = 0;
              this.loading = true;
              this.loadMonth(true).then(() => {
                this.loading = false;
              });
            })
          }
        }, (point: MonthPoint) => point.month)
      }
      .columnsTemplate('repeat(3, 1fr)')
      .columnsGap(8)
      .rowsGap(8)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  yearGridView() {
    Column() {
      Row() {
        Text('全部记录')
          .fontSize(11)
          .fontColor(this.tokens.ink3)
        Blank()
        Text(formatYuan(this.allTotalCents))
          .fontSize(11)
          .fontColor(this.tokens.ink2)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 6 })

      Grid() {
        ForEach(this.allYears, (point: YearPoint) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(point.year)
                .fontSize(11)
                .fontColor(this.tokens.ink2)
              Text(formatYuan(point.totalCents))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tokens.ink)
              Text(`${point.count} 笔`)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
            .width('100%')
            .padding(8)
            .backgroundColor(this.tokens.surface)
            .borderRadius(this.tokens.rMd)
            .border({ width: 1, color: this.tokens.line })
            .onClick(() => {
              this.anchorYear = point.year;
              this.tier = 1;
              this.loading = true;
              this.loadYear().then(() => {
                this.loading = false;
              });
            })
          }
        }, (point: YearPoint) => point.year)
      }
      .columnsTemplate('repeat(2, 1fr)')
      .columnsGap(8)
      .rowsGap(8)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column({ space: 10 }) {
      this.tierTabs()

      if (this.offline) {
        Text('离线：显示本地缓存')
          .fontSize(10)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }
      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(11)
          .fontColor(this.tokens.danger)
          .width('100%')
      }
      if (this.loading) {
        Text('加载中…')
          .fontSize(11)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }

      if (this.tier === 0) {
        this.monthListView()
      } else if (this.tier === 1) {
        this.monthGridView()
      } else {
        this.yearGridView()
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.tokens.bg)
  }
}

/** 当前月（YYYY-MM）。与 Web 的 currentMonth() 同义，用本地时区 */
function currentMonthKey(): string {
  const now = new Date();
  const m = now.getMonth() + 1;
  return `${now.getFullYear()}-${m < 10 ? '0' + m : String(m)}`;
}
