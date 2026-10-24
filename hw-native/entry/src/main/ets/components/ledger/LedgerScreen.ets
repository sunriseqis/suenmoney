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

import { Api, ExpenseItem, MonthPoint, PaymentMethodItem, UserSummary, YearPoint } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { ExpenseDao } from '../../common/store/ExpenseDao';
import { CachedCategory, DictionaryDao } from '../../common/store/DictionaryDao';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { cardRadiusOf, fontDisplayOf, fontMonoOf, mixHex, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { displayFont, bodyFont } from '../../common/theme/Fonts';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, slotOf } from '../../common/theme/Palette';
import { daysUntil, formatMonthLabel, formatYuan, shiftMonth } from '../../common/contract/Contract';
import { LengthMetrics } from '@kit.ArkUI';
import { ExpenseEditor } from '../expense/ExpenseEditor';

export interface TierChipModel {
  label: string;
  value: number;
}

export interface HeroTodo {
  id: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  willAutoPost: boolean;
  tone: string;
}

export interface HeroFactModel {
  label: string;
  value: string;
}

export interface NavBtnModel {
  label: string;
  target: string;
}

const PAGE_SIZE = 100;

export interface LedgerDayGroup {
  date: string;
  cents: number;
  rows: ExpenseItem[];
}

@Component
export struct LedgerScreen {
  /** 外壳传入的跳转回调（移动端导航只在这里和顶栏返回） */
  onNavigate: (target: string) => void = () => {
  };

  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
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
  // ── 移动 hero 数据（规范 §4.1）──
  @State prevTotalCents: number = -1;
  @State creditDueCents: number = 0;
  @State heroTodos: HeroTodo[] = [];
  @State todoOpen: boolean = false;
  @State pullHintShown: boolean = false;
  @State showHint: boolean = false;
  /** R114：刚保存的记录高亮 1.5s */
  @State highlightId: string = '';
  @State errorText: string = '';
  @State yearPoints: MonthPoint[] = [];
  @State yearTotalCents: number = 0;
  @State allYears: YearPoint[] = [];
  @State allTotalCents: number = 0;
  @State categoryNames: Map<string, CachedCategory> = new Map<string, CachedCategory>();
  @State paymentNames: Map<string, string> = new Map<string, string>();

  // ── 检索（H2 第二批）──
  @State keyword: string = '';
  @State filterCategory: string = '';
  @State filterPayment: string = '';
  @State filterOwner: string = '';
  /** 0=按日期 1=按金额 */
  @State sortMode: number = 0;
  @State filterOpen: boolean = false;
  @State rootCategories: CachedCategory[] = [];
  @State paymentOptions: CachedCategory[] = [];
  @State ownerOptions: CachedCategory[] = [];
  /** 记账抽屉开关（移动 Web 的唯一写入入口是下拉手势，这里同一机制） */
  @State sheetOpen: boolean = false;
  /** 非 null 表示抽屉处于编辑态 */
  @State editingRow: ExpenseItem | null = null;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.reload();
    this.maybeShowPullHint();
  }

  /** R115：首次进流水页提示一次「下拉可记账」，之后永不再现 */
  private maybeShowPullHint(): void {
    if (this.pullHintShown) {
      return;
    }
    this.pullHintShown = true;
    this.showHint = true;
    setTimeout(() => {
      this.showHint = false;
    }, 2600);
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

        // 筛选项：分类只列一级（二级归属一级，列出来会重复）；支付列全部；记录人取 users
        const roots: CachedCategory[] = [];
        this.categoryNames.forEach((cat: CachedCategory) => {
          if (cat.parentId === '' || cat.parentId === null) {
            roots.push(cat);
          }
        });
        this.rootCategories = roots;
        const payOpts: CachedCategory[] = [];
        pays.paymentMethods.forEach((p: PaymentMethodItem) => {
          if (p.isEnabled) {
            payOpts.push({ id: p.id, name: p.name, icon: p.icon, color: '', parentId: '' });
          }
        });
        this.paymentOptions = payOpts;
        const users = await Api.users();
        const owners: CachedCategory[] = [];
        users.users.forEach((u: UserSummary) => {
          owners.push({ id: u.id, name: u.displayName, icon: '', color: '', parentId: '' });
        });
        this.ownerOptions = owners;
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
      this.rows = this.applyLocalFilters(local);
      this.monthTotalCents = total.totalCents;
      this.monthCount = total.count;
      this.hasMore = false;
      return;
    }
    const page = await Api.expenses(
      this.anchorMonth,
      PAGE_SIZE,
      reset ? null : this.cursor,
      this.keyword.trim(),
      this.filterCategory,
      this.filterPayment,
      this.filterOwner
    );
    this.rows = reset ? page.items : this.rows.concat(page.items);
    this.cursor = page.nextCursor ?? '';
    this.hasMore = page.hasMore;
    // 顺手缓存，供断网时用
    await ExpenseDao.cache(page.items);
    const report = await Api.monthlyReport(this.anchorMonth);
    this.monthTotalCents = report.report.totalCents;
    this.monthCount = report.report.count;
    this.prevTotalCents = report.report.previous.totalCents;
    let credit = 0;
    for (const p of report.report.paymentMethods) {
      if (p.type === 'credit') {
        credit += p.cents;
      }
    }
    this.creditDueCents = credit;
    await this.loadHeroTodos();
  }

  /** hero 的待办条目（有则显示、无则整条不渲染） */
  private async loadHeroTodos(): Promise<void> {
    try {
      const body = await Api.planTodos(todayKey());
      const list: HeroTodo[] = [];
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
          willAutoPost: t.willAutoPost,
          tone: tone
        });
      }
      this.heroTodos = list;
    } catch (e) {
      this.heroTodos = [];
    }
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

  /** 本地筛选（离线路径用；线上由服务端过滤） */
  private applyLocalFilters(source: ExpenseItem[]): ExpenseItem[] {
    const q = this.keyword.trim();
    const out: ExpenseItem[] = [];
    for (const row of source) {
      if (q !== '') {
        const name = this.categoryNameOf(row);
        const hit = name.indexOf(q) >= 0 || row.note.indexOf(q) >= 0;
        if (!hit) {
          continue;
        }
      }
      if (this.filterCategory !== '') {
        const cat = this.categoryNames.get(row.categoryId);
        const rootId = cat !== undefined && cat.parentId !== '' ? cat.parentId : row.categoryId;
        if (rootId !== this.filterCategory) {
          continue;
        }
      }
      if (this.filterPayment !== '' && row.paymentMethodId !== this.filterPayment) {
        continue;
      }
      if (this.filterOwner !== '' && row.ownerId !== this.filterOwner) {
        continue;
      }
      out.push(row);
    }
    return out;
  }

  /** 排序后的行（按金额时同额保持日期序，避免每次刷新顺序抖动） */
  private sortedRows(): ExpenseItem[] {
    const list: ExpenseItem[] = this.rows.slice();
    if (this.sortMode === 1) {
      list.sort((a: ExpenseItem, b: ExpenseItem) => b.amountCents - a.amountCents);
    } else {
      list.sort((a: ExpenseItem, b: ExpenseItem) => a.spendDate < b.spendDate ? 1 : (a.spendDate > b.spendDate ? -1 : 0));
    }
    return list;
  }

  /** 按消费日分组（组内小计），同一天的多笔归到一起 */
  private grouped(): LedgerDayGroup[] {
    const out: LedgerDayGroup[] = [];
    for (const row of this.sortedRows()) {
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
    return chartColor(this.tok(), slotOf(colorField ?? '', row.categoryId));
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

  /**
   * 移动 hero（规范 §4.1，照 Web `.mobile-hero`）：
   * eyebrow → 38vp 大金额 → 环比胶囊 → 三事实（虚线分隔）→ 三入口 → 待办条 → 展开待办。
   */
  /**
   * 顶卡（docs R20–R23）：
   * - **两态由数据决定**：有未处理 → 两列（本月支出 + 处理提醒）；无 → 本月支出独占整列。
   *   同一个组件带布尔，不写两个分支（R21）。
   * - 提醒**默认收起**，点一下向下展开（把列表顶下去，不是浮层），展开态不记忆（R22）。
   * - **只有逾期时整张顶卡吸顶**；吸顶是位置、颜色标记是"要不要动手"，两者互不解释（R23）。
   */
  @Builder
  topCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        // 左/整列：本月支出
        Column({ space: 3 }) {
          Text(`${formatMonthLabel(this.anchorMonth)} · 本月支出`)
            .fontSize(9.5)
            .letterSpacing(1.3)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink3)
          Row({ space: 2 }) {
            Text('¥')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tok().ink2)
            Text(formatYuan(this.monthTotalCents).replace('¥', ''))
              .fontSize(38)
              .fontWeight(FontWeight.Bolder)
              .fontFamily(fontDisplayOf(this.isCyber()))
              .letterSpacing(-1.3)
              .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
          }
          .alignItems(VerticalAlign.Bottom)
          if (this.deltaRatio() !== null) {
            Text(`${(this.deltaRatio()! * 100).toFixed(1)}%`)
              .fontSize(10.5)
              .fontWeight(FontWeight.Bold)
              .fontFamily(fontMonoOf())
              .fontColor(this.deltaRatio()! > 0 ? this.tok().danger : this.tok().ok)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 右半格：处理提醒（0 条时整格消失，不留占位）
        if (this.heroTodos.length > 0) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(3)
                .backgroundColor(this.heroTodos[0].tone === 'late'
                  ? this.tok().danger
                  : (this.heroTodos[0].tone === 'soon' ? this.tok().warn : this.tok().ink3))
              Text(`${this.heroTodos.length} 笔待办`)
                .fontSize(11)
                .fontColor(this.tok().ink2)
                .layoutWeight(1)
              Text(this.todoOpen ? '⌃' : '⌄')
                .fontSize(11)
                .fontColor(this.tok().ink3)
            }
            .width('100%')
            .onClick(() => {
              this.todoOpen = !this.todoOpen;
            })
            ForEach(this.heroTodos.slice(0, 2), (t: HeroTodo) => {
              Text(`${t.periodSeq}期 · ${formatYuan(t.amountCents)}`)
                .fontSize(10)
                .fontFamily(fontMonoOf())
                .fontColor(this.tok().ink3)
                .maxLines(1)
                .width('100%')
            }, (t: HeroTodo) => `mini-${t.id}`)
          }
          .width(112)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 10 })
          .border({ width: { left: 1 }, color: this.tok().line })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // 三事实（R53 同源：日均 / 笔数 / 本月要还）
      Row() {
        this.heroFact({ label: '日均', value: formatYuan(this.perDayCents()) })
        this.heroFact({ label: '笔数', value: `${this.monthCount} 笔` })
        this.heroFact({ label: '本月要还', value: formatYuan(this.creditDueCents) })
      }
      .width('100%')
      .padding({ top: 9, bottom: 9 })
      .border({ width: { top: 1, bottom: 1 }, color: this.tok().line, style: BorderStyle.Dashed })

      // 展开明细：把列表顶下去（不是浮层）
      if (this.todoOpen && this.heroTodos.length > 0) {
        Column() {
          ForEach(this.heroTodos, (t: HeroTodo) => {
            Row({ space: 8 }) {
              Row()
                .width(4)
                .height(20)
                .borderRadius(2)
                .backgroundColor(t.tone === 'late' ? this.tok().danger : (t.tone === 'soon' ? this.tok().warn : this.tok().ok))
              Text(`${t.periodSeq}期 · ${t.planName}`)
                .fontSize(11.5)
                .fontColor(this.tok().ink)
                .layoutWeight(1)
                .maxLines(1)
              Text(t.willAutoPost ? '自动' : '需手动')
                .fontSize(9.5)
                .fontColor(t.willAutoPost ? this.tok().ink3 : this.tok().danger)
              Text(formatYuan(t.amountCents))
                .fontSize(10)
                .fontFamily(fontMonoOf())
                .fontColor(this.tok().ink2)
              Text(t.willAutoPost ? '确认' : '入账')
                .fontSize(10)
                .fontColor(this.tok().ink)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .border({ width: 1, color: this.tok().line })
                .onClick(() => {
                  this.actTodo(t, false);
                })
              // F36：自动入账期次**不提供「忽略」**（那等于偷偷关掉自动入账）
              if (!t.willAutoPost) {
                Text('更多')
                  .fontSize(10)
                  .fontColor(this.tok().ink3)
                  .bindMenu([{
                    value: '忽略本期',
                    action: () => {
                      this.actTodo(t, true);
                    }
                  }])
              }
            }
            .width('100%')
            .padding({ top: 5, bottom: 5 })
            .border({ width: { bottom: 1 }, color: this.tok().line })
          }, (t: HeroTodo) => t.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(cardRadiusOf(this.isCyber()))
    .border({ width: this.isCyber() ? 1 : 2, color: this.isCyber() ? this.tok().accent : this.tok().line2 })
  }

  /** 待办动作：确认/入账（落库）与忽略（不可逆，收在更多里） */
  private async actTodo(t: HeroTodo, skip: boolean): Promise<void> {
    try {
      if (skip) {
        await Api.skipTodo(t.id);
      } else if (t.willAutoPost) {
        await Api.ackTodo(t.id);
      } else {
        await Api.confirmTodo(t.id);
      }
      await this.loadHeroTodos();
      await this.loadMonth(true);
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  @Builder
  heroFact($$: HeroFactModel) {
    Column({ space: 2 }) {
      Text($$.label)
        .fontSize(9)
        .fontFamily(fontMonoOf())
        .fontColor(this.tok().ink3)
      Text($$.value)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tok().ink)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  private deltaRatio(): number | null {
    if (this.prevTotalCents <= 0) {
      return null;
    }
    return (this.monthTotalCents - this.prevTotalCents) / this.prevTotalCents;
  }

  /** 日均：当月总额 / 已过天数（与 Web perDayCents 同义） */
  private perDayCents(): number {
    const day = new Date().getDate();
    return day > 0 ? Math.round(this.monthTotalCents / day) : 0;
  }

  /**
   * 控制行（R13/R14/R16）：
   * 第 1 行 = 档位段 + 期间（靠左） ｜ 三入口（靠右、**不定宽次要链接、无选中态**）
   * 第 2 行 = 搜索（**独占并撑满**）+ 筛选
   */
  @Builder
  controlRow() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        // 档位：月 / 年 / 全部（R50 三档三形态）
        Row({ space: 4 }) {
          this.tierChip({ label: '月', value: 0 })
          this.tierChip({ label: '年', value: 1 })
          this.tierChip({ label: '全部', value: 2 })
        }
        // 期间
        if (this.tier !== 2) {
          Text('‹')
            .fontSize(16)
            .fontColor(this.tok().ink3)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.shiftPeriod(-1);
            })
          Text(this.tier === 0 ? this.anchorMonth : this.anchorYear)
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber()))
            .fontColor(this.tok().ink)
          Text('›')
            .fontSize(16)
            .fontColor(this.tok().ink3)
            .padding({ left: 6, right: 6 })
            .onClick(() => {
              this.shiftPeriod(1);
            })
        } else {
          Text('全部记录')
            .fontSize(12)
            .fontColor(this.tok().ink2)
        }
        Blank()
        // 三入口：次要链接、不定宽、无选中态（R14）
        Text('概况')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .onClick(() => {
            this.onNavigate('dashboard');
          })
        Text('报表')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .onClick(() => {
            this.onNavigate('report');
          })
        Text('设置')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .onClick(() => {
            this.onNavigate('settings');
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 档位小段（等宽仅用于"档位"，不是三入口） */
  @Builder
  tierChip($$: TierChipModel) {
    Text($$.label)
      .fontSize(11.5)
      .fontWeight(this.tier === $$.value ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.tier === $$.value ? this.tok().ink : this.tok().ink3)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(this.tier === $$.value ? this.tok().surface2 : Color.Transparent)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 999))
      .onClick(() => {
        this.tier = $$.value;
        this.loading = true;
        this.loadTier().then(() => {
          this.loading = false;
        });
      })
  }

  private shiftPeriod(delta: number): void {
    if (this.tier === 0) {
      this.anchorMonth = shiftMonth(this.anchorMonth, delta);
    } else {
      this.anchorYear = String(Number(this.anchorYear) + delta);
    }
    this.loading = true;
    this.loadTier().then(() => {
      this.loading = false;
    });
  }

  @Builder
  tierButton(label: string, value: number) {
    Button(label)
      .fontSize(12)
      .height(30)
      .layoutWeight(1)
      .backgroundColor(this.tier === value ? this.tok().accent : this.tok().surface2)
      .fontColor(this.tier === value ? this.tok().accentInk : this.tok().ink2)
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

  /** 检索区：搜索 + 筛选（折叠）+ 排序 */
  @Builder
  searchBar() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索备注或分类', text: this.keyword })
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.tok().surface2)
          .onChange((v: string) => {
            this.keyword = v;
          })
          .onSubmit(() => {
            this.reload();
          })

        Button(this.filterOpen ? '收起' : '筛选')
          .fontSize(12)
          .height(36)
          .backgroundColor(this.activeFilterCount() > 0 ? this.tok().accent : this.tok().surface2)
          .fontColor(this.activeFilterCount() > 0 ? this.tok().accentInk : this.tok().ink2)
          .onClick(() => {
            this.filterOpen = !this.filterOpen;
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('按日期')
          .fontSize(11)
          .height(28)
          .layoutWeight(1)
          .backgroundColor(this.sortMode === 0 ? this.tok().surface3 : this.tok().surface2)
          .fontColor(this.sortMode === 0 ? this.tok().ink : this.tok().ink3)
          .onClick(() => {
            this.sortMode = 0;
          })
        Button('按金额')
          .fontSize(11)
          .height(28)
          .layoutWeight(1)
          .backgroundColor(this.sortMode === 1 ? this.tok().surface3 : this.tok().surface2)
          .fontColor(this.sortMode === 1 ? this.tok().ink : this.tok().ink3)
          .onClick(() => {
            this.sortMode = 1;
          })
      }
      .width('100%')

      if (this.filterOpen) {
        Column({ space: 6 }) {
          this.filterGroup('分类', this.rootCategories, this.filterCategory, 'category')
          this.filterGroup('支付', this.paymentOptions, this.filterPayment, 'payment')
          this.filterGroup('记录人', this.ownerOptions, this.filterOwner, 'owner')
          Button('清除全部筛选')
            .fontSize(11)
            .height(28)
            .backgroundColor(this.tok().surface2)
            .fontColor(this.tok().ink3)
            .onClick(() => {
              this.filterCategory = '';
              this.filterPayment = '';
              this.filterOwner = '';
              this.keyword = '';
              this.reload();
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(this.tok().surface2)
        .borderRadius(this.tok().rMd)
      }
    }
    .width('100%')
  }

  @Builder
  filterGroup(label: string, options: CachedCategory[], selected: string, kind: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(9)
        .fontColor(this.tok().ink3)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
        ForEach(options, (opt: CachedCategory) => {
          Button(opt.name)
            .fontSize(11)
            .height(26)
            .backgroundColor(selected === opt.id ? this.tok().accent : this.tok().surface)
            .fontColor(selected === opt.id ? this.tok().accentInk : this.tok().ink2)
            .border({ width: 1, color: this.tok().line })
            .onClick(() => {
              const next: string = selected === opt.id ? '' : opt.id;
              if (kind === 'category') {
                this.filterCategory = next;
              } else if (kind === 'payment') {
                this.filterPayment = next;
              } else {
                this.filterOwner = next;
              }
              this.reload();
            })
        }, (opt: CachedCategory) => `${kind}-${opt.id}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  private activeFilterCount(): number {
    let n = 0;
    if (this.filterCategory !== '') {
      n++;
    }
    if (this.filterPayment !== '') {
      n++;
    }
    if (this.filterOwner !== '') {
      n++;
    }
    return n;
  }

  /**
   * 月档列表（docs R51/R52/R55）：无组头、合计只在有筛选时显示、触底加载更多/查看上月。
   */
  @Builder
  monthListView() {
    Column() {
      if (this.activeFilterCount() > 0) {
        Text(`筛选结果 ${this.monthCount} 笔 · 合计 ${formatYuan(this.monthTotalCents)}`)
          .fontSize(10.5)
          .fontColor(this.tok().ink3)
          .width('100%')
          .padding({ bottom: 6 })
      }

      List({ space: 8, scroller: this.scroller }) {
        ForEach(this.sortedRows(), (row: ExpenseItem) => {
          ListItem() {
            this.expenseRow(row)
          }
        }, (row: ExpenseItem) => row.id)

        ListItem() {
          Button(this.hasMore ? '加载更多' : '查看上月')
            .width('100%')
            .height(36)
            .fontSize(12)
            .backgroundColor(this.tok().surface)
            .fontColor(this.tok().ink3)
            .border({ width: this.tok().borderW, color: this.tok().line })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .onClick(() => {
              if (this.hasMore) {
                this.loadMonth(false);
              } else {
                this.shiftPeriod(-1);
              }
            })
        }
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 行卡（docs R53/R54/R138）：分类徽位 44px + 分类名/备注 + 支付方式 · 日 · 账期 + 金额。
   * 日期只写「日」；不挂"还款日"药丸（紧急度属于概况"本月要还"）。
   */
  @Builder
  expenseRow(row: ExpenseItem) {
    Row({ space: 10 }) {
      Text(this.categoryNameOf(row).substring(0, 1))
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.categoryColorOf(row))
        .backgroundColor(mixHex(this.categoryColorOf(row), this.tok().surface, 0.12))
        .borderRadius(radiusOf(this.tok(), this.isCyber(), 12))
        .border({ width: 1, color: mixHex(this.categoryColorOf(row), this.tok().surface, 0.45) })

      Column({ space: 3 }) {
        Text(row.note !== '' ? `${this.categoryNameOf(row)} · ${row.note}` : this.categoryNameOf(row))
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tok().ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.subline(row))
          .fontSize(10)
          .fontColor(this.tok().ink3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(formatYuan(row.amountCents))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontFamily(fontMonoOf())
        .fontColor(this.tok().ink)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.highlightId === row.id
      ? mixHex(this.tok().accent, this.tok().surface, 0.14)
      : this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
    .border({ width: this.isCyber() ? 1 : 2, color: this.tok().line })
    .onClick(() => {
      this.editingRow = row;
      this.sheetOpen = true;
    })
  }

  /** 副行：支付方式 · 日 · 账期（R53：`9月12日刷 · 28日还 · 16天`；现金无账期） */
  private subline(row: ExpenseItem): string {
    const day = Number(row.spendDate.substring(8, 10));
    if (row.paymentMethodType !== 'credit') {
      return `${this.paymentNameOf(row)} · ${day}日`;
    }
    const spendMd = `${Number(row.spendDate.substring(5, 7))}月${day}日`;
    const dueMd = `${Number(row.repaymentDate.substring(5, 7))}月${Number(row.repaymentDate.substring(8, 10))}日`;
    return `${this.paymentNameOf(row)} · ${day}日 · ${spendMd}刷 · ${dueMd}还 · ${daysBetween(row.spendDate, row.repaymentDate)}天`;
  }

  @Builder
  monthGridView() {
    Column() {
      Row() {
        Text(`${this.anchorYear} 年`)
          .fontSize(11)
          .fontColor(this.tok().ink3)
        Blank()
        Text(formatYuan(this.yearTotalCents))
          .fontSize(11)
          .fontColor(this.tok().ink2)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 6 })

      Grid() {
        ForEach(this.yearPoints, (point: MonthPoint) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(`${Number(point.month.substring(5, 7))} 月`)
                .fontSize(11)
                .fontColor(this.tok().ink2)
              Text(point.totalCents > 0 ? formatYuan(point.totalCents) : '—')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontFamily(fontMonoOf())
                .fontColor(this.tok().ink)
              Text(`${point.count} 笔`)
                .fontSize(9)
                .fontColor(this.tok().ink3)
            }
            .width('100%')
            .padding(8)
            .backgroundColor(this.tok().surface)
            .borderRadius(this.tok().rMd)
            .border({ width: 1, color: this.tok().line })
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
          .fontColor(this.tok().ink3)
        Blank()
        Text(formatYuan(this.allTotalCents))
          .fontSize(11)
          .fontColor(this.tok().ink2)
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 6 })

      Grid() {
        ForEach(this.allYears, (point: YearPoint) => {
          GridItem() {
            Column({ space: 2 }) {
              Text(point.year)
                .fontSize(11)
                .fontColor(this.tok().ink2)
              Text(formatYuan(point.totalCents))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tok().ink)
              Text(`${point.count} 笔`)
                .fontSize(9)
                .fontColor(this.tok().ink3)
            }
            .width('100%')
            .padding(8)
            .backgroundColor(this.tok().surface)
            .borderRadius(this.tok().rMd)
            .border({ width: 1, color: this.tok().line })
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

  @Builder
  expenseSheet() {
    ExpenseEditor({
      props: {
        editing: this.editingRow,
        onSaved: (savedId: string) => {
          this.sheetOpen = false;
          this.editingRow = null;
          // R114：保存后新记录滚到列表顶并高亮 1.5 秒
          this.reload().then(() => {
            this.highlightId = savedId;
            this.scroller.scrollEdge(Edge.Top);
            setTimeout(() => {
              this.highlightId = '';
            }, 1500);
          });
        },
        onCancel: () => {
          this.sheetOpen = false;
          this.editingRow = null;
        }
      }
    })
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
    Column({ space: 10 }) {
      if (this.showHint) {
        Text('下拉可记账')
          .fontSize(10)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
      }
      this.topCard()
      this.controlRow()

      if (this.tier === 0) {
        this.searchBar()
      }

      if (this.offline) {
        Text('离线：显示本地缓存')
          .fontSize(10)
          .fontColor(this.tok().ink3)
          .width('100%')
      }
      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(11)
          .fontColor(this.tok().danger)
          .width('100%')
      }
      if (this.loading) {
        Text('加载中…')
          .fontSize(11)
          .fontColor(this.tok().ink3)
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
    .backgroundColor(this.tok().bg)
    .bindSheet($$this.sheetOpen, this.expenseSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      showClose: true,
      backgroundColor: this.tok().bg
    })
    // 下拉记一笔：与移动 Web 同一机制（顶部下拉），不留兜底按钮
    .parallelGesture(
      PanGesture({ direction: PanDirection.Down, distance: 40 })
        .onActionEnd((event: GestureEvent) => {
          if (this.tier !== 0) {
            return;
          }
          const atTop = this.scroller.currentOffset().yOffset <= 0;
          if (atTop && event.offsetY > 80) {
            this.editingRow = null;
            this.sheetOpen = true;
          }
        })
    )
  }
}

/** 当前月（YYYY-MM）。与 Web 的 currentMonth() 同义，用本地时区 */
function currentMonthKey(): string {
  const now = new Date();
  const m = now.getMonth() + 1;
  return `${now.getFullYear()}-${m < 10 ? '0' + m : String(m)}`;
}

/** 今天（YYYY-MM-DD，本地时区） */
function todayKey(): string {
  const d = new Date();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}

/** 两个 YYYY-MM-DD 的天数差（账期） */
function daysBetween(x: string, y: string): number {
  const ta = Date.UTC(Number(x.substring(0, 4)), Number(x.substring(5, 7)) - 1, Number(x.substring(8, 10)));
  const tb = Date.UTC(Number(y.substring(0, 4)), Number(y.substring(5, 7)) - 1, Number(y.substring(8, 10)));
  return Math.round((tb - ta) / 86400000);
}
