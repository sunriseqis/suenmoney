/**
 * 流水屏（H2）—— 照 Web 移动端现状（LedgerView.vue ≤860px 一支）1:1 复刻。
 *
 * 结构（自上而下，全部来自 web 现状，不再走 docs 偏差表）：
 *   mobile-hero   期间眉标 + 38px 大金额 + 环比胶囊 + 三事实 + 三入口小按钮 + 待办条
 *   PCard 工具栏  搜索行（点击展开）+ 折叠区（档位 Seg / 期间 / 筛选 / 排序 Seg）+ 筛选组
 *   PCard 月档    「流水明细」头 + date-cap 组头（今日/昨日/N日 + 日小计）+ m-row 行卡 + 加载更多/查看上月
 *   PCard 年档    12 个月格（year-cell + 进度条，点格直接进该月）
 *   PCard 全部档  一年一格（点格进该年 1 月）
 *
 * 数据来源：线上走接口，断网走本地库现算（离线 A 档）。
 * 金额一律来自服务端/本地的整数分，展示时才格式化。
 */

import { Api, ExpenseItem, MonthPoint, PaymentMethodItem, UserSummary, YearPoint } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { ExpenseDao } from '../../common/store/ExpenseDao';
import { Outbox } from '../../common/sync/Outbox';
import { CachedCategory, DictionaryDao } from '../../common/store/DictionaryDao';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { cardShadow, fontBodyOf, fontDisplayOf, fontMonoOf, mixHex, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { CATEGORY_COLORS, parseCategoryColorIndex, deriveColorIndex } from '../../common/ui/CategoryIcon';
import { CatIconView } from '../../common/ui/CatIconView';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { daysUntil, formatMonthLabel, formatYuan, shiftMonth } from '../../common/contract/Contract';
import { LengthMetrics } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { ExpenseEditor } from '../expense/ExpenseEditor';
import { BrandMark } from '../BrandMark';

export interface HeroTodo {
  id: string;
  planName: string;
  periodSeq: number;
  amountCents: number;
  willAutoPost: boolean;
  /** 距还款日天数（负=逾期） */
  daysUntil: number;
  /** 'pending' 待处理；'skipped' 曾被忽略、现已逾期重现 */
  status: string;
}

export interface HeroFactModel {
  label: string;
  value: string;
}

const PAGE_SIZE = 100;

export interface LedgerDayGroup {
  date: string;
  cents: number;
  rows: ExpenseItem[];
}

@Component
export struct LedgerScreen {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 外壳「记一笔」按钮的请求（切到本屏后打开记账抽屉） */
  @StorageLink('createRequest') @Watch('onCreateRequest') createReq: number = 0;
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
  // ── 移动 hero 数据 ──
  @State prevTotalCents: number = -1;
  @State creditDueCents: number = 0;
  @State heroTodos: HeroTodo[] = [];
  @State todoOpen: boolean = false;
  /** R114：刚保存的记录高亮 1.5s */
  @State highlightId: string = '';
  /** 待同步条目数（离线提示只由它驱动） */
  @State pendingSync: number = 0;
  /** 同步到 AppStorage，供 build-stamp 订阅 */
  @StorageLink('pendingSync') sharedPending: number = 0;
  /** 轻提示 */
  @State toastText: string = '';
  @State errorText: string = '';
  @State yearPoints: MonthPoint[] = [];
  @State yearTotalCents: number = 0;
  @State allYears: YearPoint[] = [];
  @State allTotalCents: number = 0;
  @State categoryNames: Map<string, CachedCategory> = new Map<string, CachedCategory>();
  @State paymentNames: Map<string, string> = new Map<string, string>();

  // ── 检索（工具栏折叠区）──
  @State keyword: string = '';
  @State filterCategory: string = '';
  @State filterPayment: string = '';
  @State filterOwner: string = '';
  /** 0=按日期 1=按金额 */
  @State sortMode: number = 0;
  /** 窄屏：高级控件默认收起（web advOpen） */
  @State advOpen: boolean = false;
  @State searchFocused: boolean = false;
  @State showFilters: boolean = false;
  @State rootCategories: CachedCategory[] = [];
  @State paymentOptions: CachedCategory[] = [];
  @State ownerOptions: CachedCategory[] = [];
  /** 记账抽屉（移动 Web 的唯一写入入口是下拉手势；外壳按钮走 createRequest） */
  @State sheetOpen: boolean = false;
  /** 非 null 表示抽屉处于编辑态 */
  @State editingRow: ExpenseItem | null = null;
  /** 期间快选月历（点期间标签弹出） */
  @State calOpen: boolean = false;
  @State calYearV: number = Number(currentMonthKey().substring(0, 4));
  /** 下拉手势进度 0..1（驱动顶部「+」指示器的缩放/透明度） */
  @State pullProgress: number = 0;
  /** 下拉手势累计位移 */
  @State pullMax: number = 0;
  private scroller: Scroller = new Scroller();
  private keywordTimer: number = -1;

  /** 抽屉保存后立即刷新待同步条数 */
  refreshPending(): void {
    Outbox.pendingCount().then((n: number) => {
      this.pendingSync = n;
      this.sharedPending = n;
    }).catch(() => {
    });
  }

  aboutToAppear(): void {
    this.reload();
    Outbox.pendingCount().then((n: number) => {
      this.pendingSync = n;
      this.sharedPending = n;
    }).catch(() => {
    });
  }

  /** 外壳「记一笔」：切屏后 StorageLink 变化触发 */
  private onCreateRequest(): void {
    if (this.createReq > 0) {
      this.editingRow = null;
      this.sheetOpen = true;
    }
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
        list.push({
          id: t.id,
          planName: t.planName,
          periodSeq: t.periodSeq,
          amountCents: t.amountCents,
          willAutoPost: t.willAutoPost,
          daysUntil: days,
          status: t.status
        });
      }
      // 按紧急度排序 —— 逾期最前，其余按剩余天数升序
      list.sort((a: HeroTodo, b: HeroTodo) => a.daysUntil - b.daysUntil);
      this.heroTodos = list;
    } catch (e) {
      this.heroTodos = [];
    }
  }

  /** 逾期：还款日已过（含被忽略后重现的期次） */
  private todoOverdue(t: HeroTodo): boolean {
    return t.status === 'skipped' || t.daysUntil < 0;
  }

  /** 待办标签：逾期 / 还有N天 / 今天 / 自动 */
  private todoTag(t: HeroTodo): string {
    if (this.todoOverdue(t)) {
      return t.daysUntil < 0 ? `逾期 ${-t.daysUntil} 天` : '逾期';
    }
    if (t.daysUntil === 0) {
      return '今天';
    }
    return t.willAutoPost ? `自动 · 还有 ${t.daysUntil} 天` : `还有 ${t.daysUntil} 天`;
  }

  /**
   * 「处理」= 立即入账。
   *
   * 两种计划都走同一条路：`confirmTodo` 直接生成支出记录。
   * 逾期重现的期次（status='skipped'）也允许 —— 服务端已放开 skipped → confirmed。
   */
  private async processTodo(t: HeroTodo): Promise<void> {
    try {
      await Api.confirmTodo(t.id, '');
      this.showToast('已入账');
      await this.loadHeroTodos();
      await this.reload();
    } catch (e) {
      this.showToast((e as ApiError).message);
    }
  }

  /**
   * 「忽略」= 别再提醒我（但账怎么算，取决于计划是不是自动入账）：
   * - 自动入账 → `ackTodo`：只摘掉提醒，`status` 仍是 pending，**到期照旧自动入账**；
   * - 非自动入账 → `skipTodo`：这一期不提醒、也不入账（用户自己承担）。
   *   若之后逾期且没人处理，会以「逾期」形态重新出现（只给入账，不给忽略）。
   */
  private async ignoreTodo(t: HeroTodo): Promise<void> {
    try {
      if (t.willAutoPost) {
        await Api.ackTodo(t.id);
        this.showToast('已忽略提醒，到期自动入账');
      } else {
        await Api.skipTodo(t.id);
        this.showToast('已忽略本期，不会入账');
      }
      await this.loadHeroTodos();
    } catch (e) {
      this.showToast((e as ApiError).message);
    }
  }

  /**
   * 当前档位的合计（对齐 Web `periodTotalCents` computed）：
   * 月档取月报、年档取年报、全部档取汇总。
   * 之前顶卡大金额硬用 `monthTotalCents`，切到年/全部档后数字仍是月合计 —— 显示错误。
   */
  private periodTotalCents(): number {
    if (this.tier === 0) {
      return this.monthTotalCents;
    }
    if (this.tier === 1) {
      return this.yearTotalCents;
    }
    return this.allTotalCents;
  }

  private async loadYear(): Promise<void> {
    const body = await Api.yearlyReport(this.anchorYear);
    this.yearPoints = body.report.months;
    this.yearTotalCents = body.report.totalCents;
    // 年档的「上期」= 去年（Web prevTotalCents 同源）；不设的话环比会拿月档的上期算
    this.prevTotalCents = body.report.yearAgo !== undefined ? body.report.yearAgo.totalCents : 0;
  }

  private async loadAll(): Promise<void> {
    const body = await Api.summaryReport();
    this.allYears = body.report.years;
    this.allTotalCents = body.report.totalCents;
    // 全部档没有「上期」（Web prevTotalCents 返回 0），环比胶囊不显示
    this.prevTotalCents = 0;
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

  /** 排序后的行（与 Web sortedItems 同规则：同日按 id 倒序，避免刷新抖动） */
  private sortedRows(): ExpenseItem[] {
    const list: ExpenseItem[] = this.rows.slice();
    if (this.sortMode === 1) {
      list.sort((a: ExpenseItem, b: ExpenseItem) => b.amountCents - a.amountCents);
    } else {
      list.sort((a: ExpenseItem, b: ExpenseItem) =>
        a.spendDate === b.spendDate ? (a.id < b.id ? 1 : -1) : (a.spendDate < b.spendDate ? 1 : -1));
    }
    return list;
  }

  /** 按消费日分组（组内小计），分组顺序跟排序走（金额排序时组序=首笔出现序） */
  private dayGroups(): LedgerDayGroup[] {
    const src = this.sortedRows();
    const groups: LedgerDayGroup[] = [];
    const index: Map<string, number> = new Map<string, number>();
    for (const row of src) {
      const hit = index.get(row.spendDate);
      if (hit !== undefined) {
        const g = groups[hit];
        g.rows.push(row);
        g.cents += row.amountCents;
      } else {
        index.set(row.spendDate, groups.length);
        const rows: ExpenseItem[] = [row];
        groups.push({ date: row.spendDate, cents: row.amountCents, rows: rows });
      }
    }
    return groups;
  }

  /** 组头日期文案（Web formatLedgerDate.dayText）：今日 / 昨日 / N日 */
  private dayTextOf(date: string): string {
    if (date === todayKey()) {
      return '今日';
    }
    if (date === yesterdayKey()) {
      return '昨日';
    }
    return `${Number(date.substring(8, 10))}日`;
  }

  /** 分类色（离线时字典可能为空 → 走哈希兜底；二级分类的颜色跟一级走） */
  private categoryColorOf(row: ExpenseItem): string {
    const cat = this.categoryNames.get(row.categoryId);
    let colorField = '';
    if (cat !== undefined) {
      if (cat.parentId !== '' && cat.parentId !== null) {
        const parent = this.categoryNames.get(cat.parentId);
        colorField = parent !== undefined && parent.color !== '' ? parent.color : cat.color;
      } else {
        colorField = cat.color;
      }
    }
    if (colorField === '') {
      colorField = row.parentCategoryColor ?? row.categoryColor ?? '';
    }
    // 用 web 同款的 16 色调色板（--chart-1..16）；脏数据/未设时按名字推导
    const idx = parseCategoryColorIndex(colorField);
    if (idx !== null) {
      return CATEGORY_COLORS[idx - 1];
    }
    return CATEGORY_COLORS[deriveColorIndex(this.categoryNameOf(row)) - 1];
  }

  private categoryNameOf(row: ExpenseItem): string {
    if (row.categoryName !== '') {
      return row.categoryName;
    }
    const cat = this.categoryNames.get(row.categoryId);
    return cat !== undefined ? cat.name : '—';
  }

  /**
   * 期次文案（`3期`），非计划来源返回空串。
   * 用户 2026-10-29：「流水条目不会显示多少期，比如京东分期-3期」。
   * 取自 `planPeriodSeq`，所以**历史记录也能显示**。
   */
  private periodSeqOf(row: ExpenseItem): string {
    if (row.source === 'plan' && row.planPeriodSeq !== undefined && row.planPeriodSeq !== null) {
      return `${row.planPeriodSeq}期`;
    }
    return '';
  }

  private paymentNameOf(row: ExpenseItem): string {
    if (row.paymentMethodName !== '') {
      return row.paymentMethodName;
    }
    const name = this.paymentNames.get(row.paymentMethodId);
    return name !== undefined ? name : '—';
  }

  /** 大金额字号：常态 38（web .mh-amt），位数多时按档收缩防撑爆 */
  private heroAmountSize(): number {
    const s = formatYuan(this.periodTotalCents()).replace('¥', '');
    if (s.length <= 8) {
      return 38;
    }
    if (s.length <= 10) {
      return 30;
    }
    return 24;
  }

  private deltaRatio(): number | null {
    if (this.prevTotalCents <= 0) {
      return null;
    }
    return (this.periodTotalCents() - this.prevTotalCents) / this.prevTotalCents;
  }

  /** 日均：当月总额 / 已过天数（与 Web perDayCents 同义） */
  private perDayCents(): number {
    const day = new Date().getDate();
    return day > 0 ? Math.round(this.periodTotalCents() / day) : 0;
  }

  /** 期间标签（web period-label） */
  private periodLabel(): string {
    if (this.tier === 0) {
      return formatMonthLabel(this.anchorMonth);
    }
    if (this.tier === 1) {
      return `${this.anchorYear} 年`;
    }
    return '全部记录';
  }

  /** 生效筛选数（web filterCount：分类/支付/记录人） */
  private filterCount(): number {
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

  private overdueCount(): number {
    let n = 0;
    for (const t of this.heroTodos) {
      // skipped = 曾被忽略、已逾期重现，同样算逾期
      if (t.status === 'skipped' || t.daysUntil < 0) {
        n++;
      }
    }
    return n;
  }

  /** 待办条圆点颜色（web todoTone）：有逾期→late；有需手动→soon；否则 calm */
  private todoDotColor(): string {
    if (this.overdueCount() > 0) {
      return this.tok().danger;
    }
    for (const t of this.heroTodos) {
      if (!t.willAutoPost) {
        return this.tok().warn;
      }
    }
    return this.tok().ink3;
  }

  private switchTier(v: number): void {
    if (this.tier === v) {
      return;
    }
    this.tier = v;
    if (v === 1) {
      // Web switchTier('year')：锚点落到该年 1 月
      this.anchorYear = this.anchorMonth.substring(0, 4);
      this.anchorMonth = `${this.anchorYear}-01`;
    }
    this.loading = true;
    this.loadTier().then(() => {
      this.loading = false;
    });
  }

  private shiftPeriod(delta: number): void {
    if (this.tier === 0) {
      this.anchorMonth = shiftMonth(this.anchorMonth, delta);
    } else {
      this.anchorYear = String(Number(this.anchorYear) + delta);
      this.anchorMonth = `${this.anchorYear}-01`;
    }
    this.loading = true;
    this.loadTier().then(() => {
      this.loading = false;
    });
  }

  private toggleFilter(kind: string, id: string): void {
    if (kind === 'category') {
      this.filterCategory = this.filterCategory === id ? '' : id;
    } else if (kind === 'payment') {
      this.filterPayment = this.filterPayment === id ? '' : id;
    } else {
      this.filterOwner = this.filterOwner === id ? '' : id;
    }
    this.reload();
  }

  private clearFilters(): void {
    this.filterCategory = '';
    this.filterPayment = '';
    this.filterOwner = '';
    this.keyword = '';
    this.reload();
  }

  /** 年档格子最大值（进度条分母） */
  private yearCellMax(): number {
    let max = 1;
    for (const p of this.yearPoints) {
      if (p.totalCents > max) {
        max = p.totalCents;
      }
    }
    return max;
  }

  private allCellMax(): number {
    let max = 1;
    for (const y of this.allYears) {
      if (y.totalCents > max) {
        max = y.totalCents;
      }
    }
    return max;
  }

  /** 轻提示：2 秒后自动消失 */
  private showToast(text: string): void {
    this.toastText = text;
    setTimeout(() => {
      this.toastText = '';
    }, 2000);
  }

  /** 当前是深色（cyber）吗 */
  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  // ══════════════ 移动 hero（web .mobile-hero）══════════════

  @Builder
  topHero() {
    Column({ space: 12 }) {
      // mh-head：眉标 + 大金额 + 环比胶囊
      Column({ space: 3 }) {
        Text(`${formatMonthLabel(this.anchorMonth)} · 本月支出`)
          .fontSize(9.5)
          .letterSpacing(1.33)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
        Row({ space: 2 }) {
          Text('¥')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink2)
          Text(formatYuan(this.periodTotalCents()).replace('¥', ''))
            .fontSize(this.heroAmountSize())
            .fontWeight(FontWeight.Bolder)
            .fontFamily(fontDisplayOf(this.isCyber()))
            .letterSpacing(this.isCyber() ? 0.38 : -1.33)
            .fontFeature('"tnum" on')
            .maxLines(1)
            .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
        }
        .alignItems(VerticalAlign.Bottom)
        if (this.deltaRatio() !== null) {
          // delta-pill：文本即语义色（涨=红跌=绿），描边跟文本走；不额外加符号
          Text(`${(this.deltaRatio()! * 100).toFixed(1)}%`)
            .fontSize(10.5)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontMonoOf())
            .fontFeature('"tnum" on')
            .fontColor(this.deltaRatio()! > 0 ? this.tok().danger : this.tok().ok)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({
              width: this.isCyber() ? 1 : 1.5,
              color: this.deltaRatio()! > 0 ? this.tok().danger : this.tok().ok
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // mh-facts：三事实，上下虚线
      Row({ space: 8 }) {
        this.heroFact({ label: '日均', value: formatYuan(this.perDayCents()) })
        this.heroFact({ label: '笔数', value: `${this.monthCount} 笔` })
        this.heroFact({ label: '本月要还', value: formatYuan(this.creditDueCents) })
      }
      .width('100%')
      .padding({ top: 9, bottom: 9 })
      .border({ width: { top: 1, bottom: 1 }, color: this.tok().line, style: BorderStyle.Dashed })

      // mh-nav mh-nav--sm：三入口小按钮
      Row({ space: 6 }) {
        this.mhNavBtn('概况', 'dashboard')
        this.mhNavBtn('报表', 'report')
        this.mhNavBtn('设置', 'settings')
      }
      .width('100%')

      // hero-todo：待办提醒条（无待办整条不渲染）
      if (this.heroTodos.length > 0) {
        Row({ space: 8 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.todoDotColor())
          // 收起态只给条数 + 箭头（用户 2026-10-29 裁决：金额/逾期数都去掉，
          // 展开后每条的金额和逾期天数已经写清楚了，汇总条不用重复）
          Text(`${this.heroTodos.length} 笔待处理`)
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tok().ink)
            .layoutWeight(1)
          Text(this.todoOpen ? '⌃' : '⌄')
            .fontSize(11)
            .fontColor(this.tok().ink3)
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

      // mh-todos：展开后的待办（一行一条，仅展示；动作在概况页，与 Web 一致）
      if (this.todoOpen && this.heroTodos.length > 0) {
        Column() {
          ForEach(this.heroTodos, (t: HeroTodo, idx: number) => {
            Column({ space: 5 }) {
              Row({ space: 8 }) {
                Row()
                  .width(4)
                  .height(18)
                  .borderRadius(2)
                  .backgroundColor(this.todoOverdue(t) ? this.tok().danger
                    : (t.willAutoPost ? this.tok().warn : this.tok().accent))
                Text(`${t.periodSeq}期 · ${t.planName}`)
                  .fontSize(11.5)
                  .fontColor(this.tok().ink)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.todoTag(t))
                  .fontSize(9.5)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(fontMonoOf())
                  .fontColor(this.todoOverdue(t) ? this.tok().danger
                    : (t.willAutoPost ? this.tok().warn : this.tok().ink3))
              }
              .width('100%')

              Row({ space: 8 }) {
                Text(formatYuan(t.amountCents))
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(this.tok().ink)
                  .layoutWeight(1)
                // 逾期只给「入账」：这一期已经被忽略过一次，再给忽略等于无限拖延
                if (!this.todoOverdue(t)) {
                  Text('忽略')
                    .fontSize(10.5)
                    .fontColor(this.tok().ink2)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                    .border({ width: 1, color: this.tok().line })
                    .onClick(() => {
                      this.ignoreTodo(t);
                    })
                }
                Text(this.todoOverdue(t) ? '入账' : '处理')
                  .fontSize(10.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.tok().accentInk)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                  .backgroundColor(this.tok().accent)
                  .onClick(() => {
                    this.processTodo(t);
                  })
              }
              .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 6, bottom: 6 })
            .border(idx < this.heroTodos.length - 1
              ? { width: { bottom: 1 }, color: this.tok().line }
              : { width: 0 })
          }, (t: HeroTodo) => t.id)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 2 })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .linearGradient(this.isCyber()
      ? { angle: 180, colors: [['#0F00FF88', 0], [this.tok().surface, 0.62]] }
      : { angle: 180, colors: [[this.tok().surface, 0], [this.tok().surface, 1]] })
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 20))
    .border({
      width: this.isCyber() ? 1 : 2,
      color: this.isCyber() ? 'rgba(0,255,136,0.45)' : this.tok().line2
    })
    .shadow(this.isCyber()
      ? { radius: 16, offsetX: 0, offsetY: 0, color: 'rgba(0,255,136,0.35)' } as ShadowOptions
      : parseShadow(`4px 4px 0 ${this.tok().line2}`) as ShadowOptions)
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
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink)
        .maxLines(1)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  @Builder
  mhNavBtn(label: string, target: string) {
    Text(label)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink2)
      .textAlign(TextAlign.Center)
      .padding({ left: 4, right: 4, top: 7, bottom: 7 })
      .layoutWeight(1)
      .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: 1,
        color: this.isCyber() ? 'rgba(0,255,136,0.32)' : this.tok().line
      })
      .onClick(() => {
        AppStorage.setOrCreate('activeScreen', target);
      })
  }

  // ══════════════ 工具栏（web .ledger-toolbar + filter-row）══════════════

  @Builder
  toolbarCard() {
    Column() {
      Column({ space: 8 }) {
        // lt-search：搜索行（点击展开高级区）
        Row({ space: 8 }) {
          Stack({ alignContent: Alignment.Start }) {
            TextInput({ placeholder: '搜索备注或分类', text: this.keyword })
              .padding({ left: 34, right: 12, top: 9, bottom: 9 })
              .height(40)
              .fontSize(13)
              .fontColor(this.tok().ink)
              .placeholderColor(this.tok().ink3)
              .backgroundColor(this.isCyber() ? '#12121a' : this.tok().surface)
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
              .border({
                width: this.tok().borderW,
                color: this.searchFocused ? this.tok().accent : this.tok().line
              })
              .shadow(this.searchFocused
                ? parseShadow(`3px 3px 0 ${this.tok().accent}`) as ShadowOptions
                : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
              .onFocus(() => {
                this.searchFocused = true;
                this.advOpen = true;
              })
              .onBlur(() => {
                this.searchFocused = false;
              })
              .onChange((v: string) => {
                this.keyword = v;
                if (this.keywordTimer >= 0) {
                  clearTimeout(this.keywordTimer);
                }
                this.keywordTimer = setTimeout(() => {
                  this.reload();
                }, 400);
              })
              .onSubmit(() => {
                if (this.keywordTimer >= 0) {
                  clearTimeout(this.keywordTimer);
                }
                this.reload();
              })
            Row() {
              SymbolGlyph($r('sys.symbol.magnifyingglass'))
                .fontSize(15)
                .fontColor([this.tok().ink3])
            }
            .height(40)
            .margin({ left: 11 })
          }
          .layoutWeight(1)
          .onClick(() => {
            this.advOpen = true;
          })

          if (this.advOpen) {
            Text('收起')
              .fontSize(11.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tok().ink2)
              .padding({ left: 11, right: 11, top: 6, bottom: 6 })
              .onClick(() => {
                this.advOpen = false;
              })
          }
        }
        .width('100%')

        // lt-adv：折叠的高級控件
        if (this.advOpen) {
          Column({ space: 8 }) {
            // 档位 Seg（按月 / 按年 / 全部）
            Row({ space: 4 }) {
              this.tierSegBtn('按月', 0)
              this.tierSegBtn('按年', 1)
              this.tierSegBtn('全部', 2)
            }
            .width('100%')
            .padding(4)
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({ width: this.tok().borderW, color: this.tok().line })

            Row({ space: 8 }) {
              // period-nav
              Row({ space: 4 }) {
                this.navChevron('‹', -1)
                Text(this.periodLabel())
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(fontDisplayOf(this.isCyber()))
                  .fontColor(this.tok().ink)
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 76 })
                  // 点期间标签 → 弹出月历，快速跳月份/年份（比一直点 ‹ › 快）
                  .onClick(() => {
                    this.calYearV = Number(this.anchorMonth.substring(0, 4));
                    this.calOpen = true;
                  })
                this.navChevron('›', 1)
              }

              // 筛选（有筛选时变主按钮）
              Text(`筛选${this.filterCount() > 0 ? ` · ${this.filterCount()}` : ''}`)
                .fontSize(11.5)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
                .fontColor(this.filterCount() > 0
                  ? (this.isCyber() ? this.tok().accentInk : this.tok().accentInk)
                  : this.tok().ink)
                .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                .backgroundColor(this.filterCount() > 0 ? this.tok().accent : this.tok().surface)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                .border({
                  width: this.tok().borderW,
                  color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
                })
                .shadow(this.isCyber()
                  ? { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions
                  : parseShadow('3px 3px 0 #1E293B') as ShadowOptions)
                .onClick(() => {
                  this.showFilters = !this.showFilters;
                })

              Blank()
            }
            .width('100%')

            // 排序 Seg（按日期 / 按金额）
            Row({ space: 4 }) {
              this.sortSegBtn('按日期', 0)
              this.sortSegBtn('按金额', 1)
            }
            .width('100%')
            .padding(4)
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({ width: this.tok().borderW, color: this.tok().line })
          }
          .width('100%')
        }
      }
      .width('100%')

      // filter-row：三组筛选（分类 / 支付 / 记录人）
      if (this.showFilters) {
        Column({ space: 12 }) {
          Column({ space: 6 }) {
            Text('分类')
              .fontSize(9.5)
              .letterSpacing(1.14)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(8), cross: LengthMetrics.px(6) } }) {
              this.catAllChip()
              ForEach(this.rootCategories, (opt: CachedCategory) => {
                this.catChip(opt)
              }, (opt: CachedCategory) => opt.id)
            }
            .width('100%')
          }
          .width('100%')

          Column({ space: 6 }) {
            Text('支付')
              .fontSize(9.5)
              .letterSpacing(1.14)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(8), cross: LengthMetrics.px(6) } }) {
              ForEach(this.paymentOptions, (opt: CachedCategory) => {
                this.payChip(opt)
              }, (opt: CachedCategory) => opt.id)
            }
            .width('100%')
          }
          .width('100%')

          Column({ space: 6 }) {
            Text('记录人')
              .fontSize(9.5)
              .letterSpacing(1.14)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .width('100%')
            Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(8), cross: LengthMetrics.px(6) } }) {
              ForEach(this.ownerOptions, (opt: CachedCategory) => {
                this.ownerChip(opt)
              }, (opt: CachedCategory) => opt.id)
            }
            .width('100%')
            if (this.filterCount() > 0 || this.keyword !== '') {
              Text('清除')
                .fontSize(11.5)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tok().ink2)
                .padding({ left: 11, right: 11, top: 6, bottom: 6 })
                .onClick(() => {
                  this.clearFilters();
                })
            }
          }
          .width('100%')
        }
        .width('100%')
        .margin({ top: 6 })
        .padding({ top: 14 })
        .border({ width: { top: 1 }, color: this.tok().line, style: BorderStyle.Dashed })
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  @Builder
  tierSegBtn(label: string, value: number) {
    Text(label)
      .fontSize(this.isCyber() ? 10.5 : 12)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.tier === value
        ? (this.isCyber() ? this.tok().accent : this.tok().accentInk)
        : this.tok().ink2)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ left: 13, right: 13, top: 6, bottom: 6 })
      .backgroundColor(this.tier === value
        ? (this.isCyber() ? '#1A00FF88' : this.tok().accent)
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

  @Builder
  sortSegBtn(label: string, value: number) {
    Text(label)
      .fontSize(this.isCyber() ? 10.5 : 12)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.sortMode === value
        ? (this.isCyber() ? this.tok().accent : this.tok().accentInk)
        : this.tok().ink2)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ left: 13, right: 13, top: 6, bottom: 6 })
      .backgroundColor(this.sortMode === value
        ? (this.isCyber() ? '#1A00FF88' : this.tok().accent)
        : Color.Transparent)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: 2,
        color: this.sortMode === value && !this.isCyber() ? this.tok().line2 : Color.Transparent
      })
      .onClick(() => {
        this.sortMode = value;
      })
  }

  @Builder
  navChevron(symbol: string, delta: number) {
    Text(symbol)
      .fontSize(18)
      .fontColor(this.tok().ink2)
      .width(38)
      .height(38)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.tok().surface)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({ width: this.tok().borderW, color: this.tok().line })
      .opacity(this.tier === 2 ? 0.45 : 1)
      .onClick(() => {
        if (this.tier !== 2) {
          this.shiftPeriod(delta);
        }
      })
  }

  @Builder
  catAllChip() {
    Text('全部')
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.filterCategory === ''
        ? (this.isCyber() ? this.tok().accent : this.tok().onColor)
        : this.tok().ink2)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .backgroundColor(this.filterCategory === ''
        ? (this.isCyber() ? '#1A00FF88' : this.tok().amber)
        : (this.isCyber() ? Color.Transparent : this.tok().surface))
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.isCyber() ? 1 : 2,
        color: this.filterCategory === ''
          ? (this.isCyber() ? this.tok().accent : this.tok().line2)
          : this.tok().line
      })
      .shadow({
        radius: 0,
        offsetX: this.filterCategory === '' && !this.isCyber() ? 2 : 0,
        offsetY: this.filterCategory === '' && !this.isCyber() ? 2 : 0,
        color: this.tok().line2
      })
      .onClick(() => {
        this.toggleFilter('category', '');
      })
  }

  @Builder
  catChip(opt: CachedCategory) {
    Text(opt.name)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.filterCategory === opt.id
        ? (this.isCyber() ? this.tok().accent : this.tok().onColor)
        : this.tok().ink2)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .backgroundColor(this.filterCategory === opt.id
        ? (this.isCyber() ? '#1A00FF88' : this.tok().amber)
        : (this.isCyber() ? Color.Transparent : this.tok().surface))
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.isCyber() ? 1 : 2,
        color: this.filterCategory === opt.id
          ? (this.isCyber() ? this.tok().accent : this.tok().line2)
          : this.tok().line
      })
      .shadow({
        radius: 0,
        offsetX: this.filterCategory === opt.id && !this.isCyber() ? 2 : 0,
        offsetY: this.filterCategory === opt.id && !this.isCyber() ? 2 : 0,
        color: this.tok().line2
      })
      .onClick(() => {
        this.toggleFilter('category', opt.id);
      })
  }

  @Builder
  payChip(opt: CachedCategory) {
    Text(opt.name)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.filterPayment === opt.id
        ? (this.isCyber() ? this.tok().accent : this.tok().onColor)
        : this.tok().ink2)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .backgroundColor(this.filterPayment === opt.id
        ? (this.isCyber() ? '#1A00FF88' : this.tok().amber)
        : (this.isCyber() ? Color.Transparent : this.tok().surface))
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.isCyber() ? 1 : 2,
        color: this.filterPayment === opt.id
          ? (this.isCyber() ? this.tok().accent : this.tok().line2)
          : this.tok().line
      })
      .shadow({
        radius: 0,
        offsetX: this.filterPayment === opt.id && !this.isCyber() ? 2 : 0,
        offsetY: this.filterPayment === opt.id && !this.isCyber() ? 2 : 0,
        color: this.tok().line2
      })
      .onClick(() => {
        this.toggleFilter('payment', opt.id);
      })
  }

  @Builder
  ownerChip(opt: CachedCategory) {
    Text(opt.name)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Medium)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.filterOwner === opt.id
        ? (this.isCyber() ? this.tok().accent : this.tok().onColor)
        : this.tok().ink2)
      .padding({ left: 11, right: 11, top: 5, bottom: 5 })
      .backgroundColor(this.filterOwner === opt.id
        ? (this.isCyber() ? '#1A00FF88' : this.tok().amber)
        : (this.isCyber() ? Color.Transparent : this.tok().surface))
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.isCyber() ? 1 : 2,
        color: this.filterOwner === opt.id
          ? (this.isCyber() ? this.tok().accent : this.tok().line2)
          : this.tok().line
      })
      .shadow({
        radius: 0,
        offsetX: this.filterOwner === opt.id && !this.isCyber() ? 2 : 0,
        offsetY: this.filterOwner === opt.id && !this.isCyber() ? 2 : 0,
        color: this.tok().line2
      })
      .onClick(() => {
        this.toggleFilter('owner', opt.id);
      })
  }

  // ══════════════ 月档（card-h + m-list）══════════════

  @Builder
  monthCard() {
    Column() {
      Row({ space: 10 }) {
        Text('流水明细')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
        Blank()
        Text(`${this.rows.length} 笔 · 合计 ${formatYuan(this.monthTotalCents)}`)
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.loading) {
        Text('加载中…')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(34)
      } else if (this.dayGroups().length === 0) {
        Text('没有符合条件的流水')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(34)
      } else {
        // m-list：组间 8px；组内行卡贴边（Web 现状）
        Column({ space: 8 }) {
          ForEach(this.dayGroups(), (g: LedgerDayGroup) => {
            Column() {
              // date-cap 组头 + 日小计
              Row() {
                Text(this.dayTextOf(g.date))
                  .fontSize(10.5)
                  .letterSpacing(0.84)
                  .fontFamily(fontMonoOf())
                  .fontColor(this.tok().ink2)
                Blank()
                Text(formatYuan(g.cents))
                  .fontSize(10.5)
                  .fontFamily(fontMonoOf())
                  .fontFeature('"tnum" on')
                  .fontColor(this.tok().ink3)
              }
              .width('100%')
              .padding({ left: 4, right: 4, top: 12, bottom: 6 })

              ForEach(g.rows, (row: ExpenseItem) => {
                this.expenseRow(row)
              }, (row: ExpenseItem) => row.id)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (g: LedgerDayGroup) => g.date)
        }
        .width('100%')

        if (this.hasMore) {
          Row() {
            Text('加载更多')
              .fontSize(12.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tok().ink)
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .backgroundColor(this.tok().surface)
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
              .border({ width: this.tok().borderW, color: this.tok().line2 })
              .shadow(this.isCyber()
                ? { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions
                : parseShadow('3px 3px 0 #1E293B') as ShadowOptions)
              .onClick(() => {
                this.loadMonth(false);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 14 })
        } else if (this.rows.length > 0) {
          Row() {
            Text('‹ 查看上月')
              .fontSize(12.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tok().ink2)
              .padding({ left: 16, right: 16, top: 9, bottom: 9 })
              .onClick(() => {
                this.shiftPeriod(-1);
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 14 })
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /**
   * 下拉记一笔的指示器：**应用 logo + 下方小字「记一笔」**，随下拉进度**逐段展开**。
   * 用「高度随进度增长的裁切窗口」实现（不是先整块出现再放大）：
   * 拉到多少就看到多少，logo 先露出来，小字随后跟上。
   */
  @Builder
  pullIndicator() {
    if (this.pullProgress > 0.01) {
      Column() {
        Column({ space: 4 }) {
          BrandMark({ markSize: 34 })
          Text('记一笔')
            .fontSize(9.5)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontMonoOf())
            .letterSpacing(1.2)
            .fontColor(this.tok().ink2)
        }
        .width(96)
      }
      .width('100%')
      // 内容自然高度 ≈ 34 + 4 + 14 = 52vp；按进度线性揭示
      .height(52 * Math.min(1, this.pullProgress))
      .clip(true)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .opacity(0.35 + 0.65 * Math.min(1, this.pullProgress))
    }
  }

  /** 行卡（web .m-row）：34px 分类徽位 + 名称/退款 + 备注·支付·记录人 + 金额/还款日 */
  @Builder
  expenseRow(row: ExpenseItem) {
    Row({ space: 8 }) {
      Stack() {
        CatIconView({
          catName: this.categoryNameOf(row),
          iconSize: 19,
          color: this.categoryColorOf(row)
        })
      }
      .width(34)
      .height(34)
      .backgroundColor(mixHex(this.categoryColorOf(row), this.tok().surface, 0.12))
      .borderRadius(9)
      .border({ width: 1, color: mixHex(this.categoryColorOf(row), this.tok().surface, 0.45) })

      Column({ space: 3 }) {
        // 第一行：分类（主字号）+ 标题(=note) + 归属，后两者用小字
        // 用户 2026-10-29：备注/支付/归属挤一行显示不全，改成
        //   第一行 分类 · 标题 · 归属
        //   第二行 支付 · 期数
        Row({ space: 6 }) {
          Text(this.categoryNameOf(row))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tok().ink)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (row.amountCents < 0) {
            Text('退款')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().danger)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
              .border({ width: 1, color: this.tok().danger })
          }
          if (row.note !== '') {
            Text(row.note)
              .fontSize(10)
              .fontColor(this.tok().ink3)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          Text(row.ownerName !== '' ? row.ownerName : '—')
            .fontSize(10)
            .fontColor(this.tok().ink3)
            .maxLines(1)
        }

        // 第二行：支付方式 + 期数（计划来源才有）
        Row({ space: 6 }) {
          Text(this.paymentNameOf(row))
            .fontSize(10)
            .fontColor(this.tok().ink3)
            .maxLines(1)
          if (this.periodSeqOf(row) !== '') {
            Text('·')
              .fontSize(10)
              .fontColor(this.tok().ink3)
            Text(this.periodSeqOf(row))
              .fontSize(10)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column({ space: 2 }) {
        Text(formatYuan(row.amountCents))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontFamily(fontMonoOf())
          .fontFeature('"tnum" on')
          .fontColor(row.amountCents < 0 ? this.tok().ok : this.tok().ink)
        Text(row.paymentMethodType === 'credit' ? `${row.repaymentDate.substring(5)} 还` : '即时')
          .fontSize(10.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink2)
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.highlightId === row.id
      ? mixHex(this.tok().accent, this.tok().surface, 0.14)
      : this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .onClick(() => {
      this.editingRow = row;
      this.sheetOpen = true;
    })
  }

  // ══════════════ 年档 / 全部档（cal-year-grid 3 列）══════════════

  @Builder
  yearCard() {
    Column() {
      Row({ space: 10 }) {
        Text(`${this.anchorYear} 年`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
        Blank()
        Text(`合计 ${formatYuan(this.yearTotalCents)}`)
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      Grid() {
        ForEach(this.yearPoints, (point: MonthPoint) => {
          GridItem() {
            this.yearCell(
              `${Number(point.month.substring(5, 7))}月`,
              point.month === currentMonthKey(),
              formatYuan(point.totalCents),
              point.count,
              Math.round(point.totalCents / this.yearCellMax() * 100)
            )
          }
          // 下钻：点年格 → 切到该月的月档（Web drillMonth）
          // 之前格子上没有 onClick，点了没反应
          .onClick(() => {
            this.anchorMonth = point.month;
            this.tier = 0;
            this.loading = true;
            this.loadTier().then(() => {
              this.loading = false;
            });
          })
        }, (point: MonthPoint) => point.month)
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }


  /** 期间快选月历：年 ‹ › + 12 个月格；点月份落到该月，另有「整年 / 回到本月」 */
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
          Text('选择期间')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
          Blank()
          Text('关闭')
            .fontSize(11)
            .fontColor(this.tok().ink3)
            .onClick(() => {
              this.calOpen = false;
            })
        }
        .width('100%')

        Row() {
          Text('‹')
            .fontSize(18)
            .fontColor(this.tok().ink2)
            .width(34)
            .height(30)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.calYearV = this.calYearV - 1;
            })
          Blank()
          Text(`${this.calYearV} 年`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontFamily(fontDisplayOf(this.isCyber()))
            .fontColor(this.tok().ink)
          Blank()
          Text('›')
            .fontSize(18)
            .fontColor(this.tok().ink2)
            .width(34)
            .height(30)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.calYearV = this.calYearV + 1;
            })
        }
        .width('100%')

        Grid() {
          ForEach(CAL_MONTHS, (mm: number) => {
            GridItem() {
              Text(`${mm}月`)
                .fontSize(12)
                .width('100%')
                .height(38)
                .textAlign(TextAlign.Center)
                .fontFamily(fontMonoOf())
                .fontColor(this.calMonthActive(mm) ? this.tok().accentInk : this.tok().ink2)
                .backgroundColor(this.calMonthActive(mm) ? this.tok().accent : this.tok().surface2)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
                .border({ width: 1, color: this.tok().line })
                .onClick(() => {
                  this.anchorMonth = monthKeyOf(this.calYearV, mm);
                  this.anchorYear = String(this.calYearV);
                  this.tier = 0;
                  this.calOpen = false;
                  this.loading = true;
                  this.reload().then(() => {
                    this.loading = false;
                  });
                })
            }
          }, (mm: number) => `cal-${mm}`)
        }
        .columnsTemplate('repeat(4, 1fr)')
        .columnsGap(6)
        .rowsGap(6)
        .width('100%')
        // ⚠ Grid 不给高度会撑满父容器 → 卡片被拉成全屏高、内容贴顶。
        // 12 格 4 列 3 行：格高 38 + 行距 6 → 3*38 + 2*6 = 126
        .height(126)

        Row({ space: 8 }) {
          Text('整年')
            .fontSize(11.5)
            .layoutWeight(1)
            .height(32)
            .textAlign(TextAlign.Center)
            .fontColor(this.tok().ink2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .border({ width: 1, color: this.tok().line })
            .onClick(() => {
              this.anchorYear = String(this.calYearV);
              this.tier = 1;
              this.calOpen = false;
              this.loading = true;
              this.reload().then(() => {
                this.loading = false;
              });
            })
          Text('回到本月')
            .fontSize(11.5)
            .layoutWeight(1)
            .height(32)
            .textAlign(TextAlign.Center)
            .fontColor(this.tok().ink2)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .border({ width: 1, color: this.tok().line })
            .onClick(() => {
              this.anchorMonth = currentMonthKey();
              this.anchorYear = currentMonthKey().substring(0, 4);
              this.tier = 0;
              this.calOpen = false;
              this.loading = true;
              this.reload().then(() => {
                this.loading = false;
              });
            })
        }
        .width('100%')
      }
      .width(300)
      .padding(14)
      .backgroundColor(this.tok().bg)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
      .border({ width: this.tok().borderW, color: this.tok().line })
    }
    .width('100%')
    .height('100%')
  }

  /** 月历里「当前选中的月」高亮 */
  private calMonthActive(mm: number): boolean {
    return this.tier === 0 && this.anchorMonth === monthKeyOf(this.calYearV, mm);
  }

  /** 年档单格：月份 + 本月标记 + 笔数 + 金额 + 进度条（点击进该月） */
  @Builder
  yearCell(label: string, isCurrent: boolean, amountText: string, count: number, pct: number) {
    Column({ space: 4 }) {
      Row({ space: 5 }) {
        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
        if (isCurrent) {
          Text('本月')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().accent)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({ width: 1, color: this.tok().accent })
        }
        Blank()
        Text(`${count} 笔`)
          .fontSize(10.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink2)
      }
      .width('100%')

      Text(amountText)
        .fontSize(11)
        .fontFamily(fontMonoOf())
        .fontFeature('"tnum" on')
        .fontColor(this.tok().ink2)

      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(5)
          .backgroundColor(this.tok().surface3)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .border({ width: 1, color: this.tok().line })
        Row()
          .width(`${pct}%`)
          .height(5)
          .backgroundColor(this.tok().accent)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .margin({ left: 1 })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 12, bottom: 12 })
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
    .border({ width: this.tok().borderW, color: isCurrent ? this.tok().line2 : this.tok().line })
  }

  @Builder
  allCard() {
    Column() {
      Row({ space: 10 }) {
        Text('全部记录')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(fontDisplayOf(this.isCyber()))
          .fontColor(this.tok().ink)
        Blank()
        Text(`${this.allYears.length} 年 · 合计 ${formatYuan(this.allTotalCents)}`)
          .fontSize(9.5)
          .letterSpacing(1.52)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.allYears.length === 0 && !this.loading) {
        Text('还没有任何记录')
          .fontSize(12)
          .fontColor(this.tok().ink3)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(34)
      } else {
        Grid() {
          ForEach(this.allYears, (point: YearPoint) => {
            GridItem() {
              this.yearCell(
                point.year,
                false,
                formatYuan(point.totalCents),
                point.count,
                Math.round(point.totalCents / this.allCellMax() * 100)
              )
            }
            // 全部档点年格 → 切到该年的年档（同 Web drillYear）
            .onClick(() => {
              this.anchorYear = point.year;
              this.anchorMonth = `${point.year}-01`;
              this.tier = 1;
              this.loading = true;
              this.loadTier().then(() => {
                this.loading = false;
              });
            })
          }, (point: YearPoint) => point.year)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(10)
        .rowsGap(10)
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  @Builder
  expenseSheet() {
    ExpenseEditor({
      props: {
        editing: this.editingRow,
        onSaved: (savedId: string) => {
          this.showToast(savedId === '' ? '已保存' : '已记账');
          this.sheetOpen = false;
          this.editingRow = null;
          // 保存后新记录滚到列表顶并高亮 1.5 秒
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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          this.topHero()
          this.toolbarCard()
          if (this.tier === 0) {
            this.monthCard()
          } else if (this.tier === 1) {
            this.yearCard()
          } else {
            this.allCard()
          }
          if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(11)
              .fontColor(this.tok().danger)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        // 内容比视口短时（空月份/空年份很常见），Scroll 会把内容列**垂直居中** →
        // 切档/切屏就整页上下跳。给一个「至少占满视口」的下限，永远从顶部开始。
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 期间快选月历（点期间标签弹出）
      if (this.calOpen) {
        this.periodCalendar()
      }

      // 下拉记一笔的指示器：撑满高度的透明命中层 + 顶对齐（用 .overlay 会挡住整页点击）
      Column() {
        this.pullIndicator()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .padding({ top: 12 })
      .hitTestBehavior(HitTestMode.Transparent)

      // 轻提示（web .toast）：底部居中、2 秒消失
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
    .bindSheet($$this.sheetOpen, this.expenseSheet(), {
      // 贴合内容高度：既没有底部空白，也不会把键盘撑大
      height: SheetSize.FIT_CONTENT,
      // Web 移动端抽屉圆角 `22px 22px 0 0`，cyber 下为 0（app.css:762-773）
      radius: this.isCyber() ? LengthMetrics.vp(0) : LengthMetrics.vp(22),
      dragBar: true,
      // 不要系统关闭按钮：它压在内容右上角，和「退款冲销」标记一起盖住金额；
      // 关闭走抽屉内的「取消」、下拉收起、或点 OK 保存后自动关。
      showClose: false,
      backgroundColor: this.tok().bg
    })
    // 下拉记一笔：移动 Web 的唯一手势入口；阈值 60vp，列表须已在顶部
    .parallelGesture(
      PanGesture({ direction: PanDirection.Down, distance: 20 })
        .onActionStart(() => {
          this.pullMax = 0;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (event.offsetY > this.pullMax) {
            this.pullMax = event.offsetY;
          }
          // 60vp 触发阈值，进度封顶到 1（超出部分不再放大，反馈更稳）
          const p = Math.min(1, this.pullMax / 60);
          if (Math.abs(p - this.pullProgress) > 0.02) {
            this.pullProgress = p;
          }
        })
        .onActionEnd(() => {
          const atTop = this.scroller.currentOffset().yOffset <= 0;
          const hit = atTop && this.pullMax > 60;
          if (hit) {
            // 把展开补满（不放大），再开抽屉
            animateTo({ duration: 120, curve: Curve.Friction }, () => {
              this.pullProgress = 1;
            });
            // 轻微震动（下拉触发反馈）；失败静默（没有马达/没授权都不影响功能）
            vibrator.startVibration({ type: 'time', duration: 18 }, { id: 0, usage: 'unknown' })
              .catch(() => {
              });
            setTimeout(() => {
              this.editingRow = null;
              this.sheetOpen = true;
              animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
                this.pullProgress = 0;
              });
            }, 110);
          } else {
            animateTo({ duration: 160, curve: Curve.EaseOut }, () => {
              this.pullProgress = 0;
            });
          }
          this.pullMax = 0;
        })
    )
  }
}

/** 当前月（YYYY-MM）。与 Web 的 currentMonth() 同义，用本地时区 */
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

/** 今天（YYYY-MM-DD，本地时区） */
function todayKey(): string {
  const d = new Date();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}

/** 昨天（YYYY-MM-DD，本地时区）—— 组头「昨日」判定 */
function yesterdayKey(): string {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}
