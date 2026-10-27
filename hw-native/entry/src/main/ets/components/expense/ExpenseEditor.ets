/**
 * 记一笔（H3 · 抽屉内容）。
 *
 * 对齐移动 Web 的抽屉：
 *   金额显示 → 分类 / 日期 / 支付方式 三行字段 → 备注 → 退款开关 → 账期预览
 *   → 常用分类快捷条 → 5 列键盘（左支付列 + 右数字键）→ 保存
 *
 * 三条硬口径：
 *   1. **跨月必须明说**「这笔会记在 2026 年 11 月（还款日 11-28）」——
 *      信用卡还款日落到下个月时，用户会以为保存失败。
 *   2. 金额整数分：输入是文本，落库前用 parseYuanToCents 转整数，
 *      全程不出现浮点（`parseFloat*100` 会差一分钱）。
 *   3. 退款不加负号输入，用开关把正值翻成负数。
 */

/** @Builder 单参数对象（多参数不刷新，见 fieldRow 注释） */
import {
  Api,
  CategoryNode,
  ExpenseCreateRequest,
  ExpenseItem,
  ExpensePatchRequest,
  ExpensePreview,
  PaymentMethodItem,
  PlanCreateRequest
} from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { formatCents, formatYuan, parseYuanToCents } from '../../common/contract/Contract';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { FOCUS_RING, fontDisplayOf, fontMonoOf, outlineStrongOf, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { PayIconView } from '../../common/ui/PayIconView';
import { CatIconView } from '../../common/ui/CatIconView';
import { categoryColorOf } from '../../common/ui/CategoryIcon';
import { LastPick, LastPickValue } from '../../common/store/LastPick';
import { Outbox } from '../../common/sync/Outbox';
import { SyncEngine } from '../../common/sync/SyncEngine';
import { ulid } from '../../common/contract/Contract';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';

export interface FieldRowModel {
  label: string;
  value: string;
  onTap: () => void;
}

export interface ExpenseEditorProps {
  /** 非 null 即编辑已有记录（标题变「编辑」，底部出现删除） */
  editing: ExpenseItem | null;
  /** 保存成功回调：带上记录 id，外壳据此滚到顶并高亮（R114） */
  onSaved: (savedId: string) => void;
  onCancel: () => void;
}

@Component
export struct ExpenseEditor {
  /** R108：2026-11-28 → 2026 年 11 月 */
  private monthLabel(date: string): string {
    const y = date.substring(0, 4);
    const m = date.substring(5, 7);
    return `${y} 年 ${Number(m)} 月`;
  }

  /** R108：2026-11-28 → 11月28日 */
  private dateShort(date: string): string {
    return `${Number(date.substring(5, 7))}月${Number(date.substring(8, 10))}日`;
  }
  props: ExpenseEditorProps = {
    editing: null,
    onSaved: () => {
    },
    onCancel: () => {
    }
  };

  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照，见 ThemeManager 注释） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  @State amountText: string = '';
  @State categoryId: string = '';
  @State paymentId: string = '';
  @State spendDate: string = todayKey();
  @State note: string = '';
  @State isRefund: boolean = false;
  /** 分期（R113：仅信用卡且非退款可用） */
  @State installment: boolean = false;
  @State periods: number = 3;
  @State saving: boolean = false;
  @State errorText: string = '';
  /** 本月已支出（R107：背景信息，不 await，拿不到显示占位） */
  @State monthSpentCents: number | null = null;
  /** 备注聚焦时折叠数字键盘（R111） */
  @State noteFocus: boolean = false;
  @State preview: ExpensePreview | null = null;
  @State categories: CategoryNode[] = [];
  @State payments: PaymentMethodItem[] = [];
  /** 消费日期自绘日历（替代系统 DatePickerDialog） */
  @State dateCalOpen: boolean = false;
  @State dateCalYear: number = 0;
  @State dateCalMonth: number = 0;
  @State categoryOpen: boolean = false;
  @State paymentOpen: boolean = false;
  @State railRootId: string = '';

  aboutToAppear(): void {
    this.loadDict();
    // R107：本月已支出是背景信息，**不 await**，拿不到就显示占位
    const month = todayKey().substring(0, 7);
    Api.monthlyReport(month).then((body) => {
      this.monthSpentCents = body.report.totalCents;
    }).catch(() => {
      this.monthSpentCents = null;
    });
  }

  private async loadDict(): Promise<void> {
    try {
      const cats = await Api.categories();
      this.categories = cats.categories;
      const pays = await Api.paymentMethods();
      const usable: PaymentMethodItem[] = [];
      for (const p of pays.paymentMethods) {
        if (p.isEnabled) {
          usable.push(p);
        }
      }
      this.payments = usable;
      if (this.categories.length > 0) {
        this.railRootId = this.categories[0].id;
      }

      const editing = this.props.editing;
      if (editing !== null) {
        // 编辑：回填原值（含退款符号）
        this.amountText = formatCents(Math.abs(editing.amountCents)).replace(/,/g, '');
        this.categoryId = editing.categoryId;
        this.paymentId = editing.paymentMethodId;
        this.spendDate = editing.spendDate;
        this.note = editing.note;
        this.isRefund = editing.amountCents < 0;
        for (const root of this.categories) {
          if (root.id === editing.categoryId) {
            this.railRootId = root.id;
          }
          for (const kid of root.children) {
            if (kid.id === editing.categoryId) {
              this.railRootId = root.id;
            }
          }
        }
      } else {
        // 新建：沿用上次选择，但必须先校验「仍然可选」（分类可能已停用）
        const last: LastPickValue | null = await LastPick.read();
        const lastCat = last === null ? null : this.findCategory(last.categoryId);
        const lastPay = last === null ? null : this.findPayment(last.paymentMethodId);
        const firstRoot = this.categories.length > 0 ? this.categories[0] : null;
        if (lastCat !== null && lastCat.isEnabled) {
          this.categoryId = lastCat.id;
          for (const root of this.categories) {
            if (root.id === lastCat.parentId) {
              this.railRootId = root.id;
            }
            for (const kid of root.children) {
              if (kid.id === lastCat.id) {
                this.railRootId = root.id;
              }
            }
          }
        } else if (firstRoot !== null) {
          const kids = firstRoot.children;
          this.categoryId = kids.length > 0 ? kids[0].id : firstRoot.id;
        }
        this.paymentId = lastPay !== null && lastPay.isEnabled
          ? lastPay.id
          : (this.payments.length > 0 ? this.payments[0].id : '');
      }
      this.refreshPreview();
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.message;
    }
  }

  /** 账期预览：问服务端，不在客户端重算账单周期 */
  private async refreshPreview(): Promise<void> {
    if (this.paymentId === '') {
      this.preview = null;
      return;
    }
    try {
      this.preview = await Api.previewExpense(this.spendDate, this.paymentId);
    } catch (e) {
      this.preview = null;
    }
  }

  /** 当前支付方式是不是信用卡（决定分期可用性） */
  private isCredit(): boolean {
    for (const p of this.payments) {
      if (p.id === this.paymentId) {
        return p.type === 'credit';
      }
    }
    return false;
  }

  /** 输入框默认描边（R35 焦点环的未聚焦态） */
  private lineColor(): string {
    return this.isCyber() ? this.tok().line : outlineStrongOf(false);
  }

  private cents(): number {
    return parseYuanToCents(this.amountText);
  }

  /** 跨月：还款日月份 ≠ 消费日月份 */
  private crossesMonth(): boolean {
    const due = this.preview;
    if (due === null) {
      return false;
    }
    return due.repaymentDate.substring(0, 7) !== this.spendDate.substring(0, 7);
  }

  private findCategory(id: string): CategoryNode | null {
    for (const root of this.categories) {
      if (root.id === id) {
        return root;
      }
      for (const kid of root.children) {
        if (kid.id === id) {
          return kid;
        }
      }
    }
    return null;
  }

  private findPayment(id: string): PaymentMethodItem | null {
    for (const p of this.payments) {
      if (p.id === id) {
        return p;
      }
    }
    return null;
  }

  /** 支付方式快捷键名精炼到 2–3 字（R112） */
  private shortName(name: string): string {
    const map: Record<string, string> = {
      '招商银行信用卡': '招行', '招行信用卡': '招行', '支付宝': '支付宝', '微信': '微信',
      '花呗': '花呗', '现金': '现金', '工资卡': '工资卡', '建设银行': '建行'
    };
    const hit = map[name];
    if (hit !== undefined) {
      return hit;
    }
    return name.length > 3 ? name.substring(0, 2) : name;
  }

  private categoryName(): string {
    for (const root of this.categories) {
      if (root.id === this.categoryId) {
        return root.name;
      }
      for (const kid of root.children) {
        if (kid.id === this.categoryId) {
          return `${root.name} · ${kid.name}`;
        }
      }
    }
    return '选择分类';
  }

  private paymentName(): string {
    for (const p of this.payments) {
      if (p.id === this.paymentId) {
        return p.name;
      }
    }
    return '选择支付方式';
  }

  private press(key: string): void {
    // OK 就是「保存」——之前它掉进数字分支，按了什么都不会发生，语义和按钮对不上
    if (key === 'OK') {
      if (this.canSave() && !this.saving) {
        this.save();
      }
      return;
    }
    if (key === 'C') {
      this.amountText = '';
      return;
    }
    if (key === 'B') {
      this.amountText = this.amountText.length > 0 ? this.amountText.substring(0, this.amountText.length - 1) : '';
      return;
    }
    if (key === '.') {
      if (this.amountText.indexOf('.') < 0) {
        this.amountText = (this.amountText === '' ? '0' : this.amountText) + '.';
      }
      return;
    }
    const next = (this.amountText === '0' ? '' : this.amountText) + key;
    if (next.indexOf('.') >= 0) {
      const parts = next.split('.');
      if (parts.length > 1 && parts[1].length > 2) {
        return;
      }
    }
    if (next.length > 9) {
      return;
    }
    this.amountText = next;
  }

  /** 保存键可用条件：金额 > 0 且分类与支付方式都已选 */
  private canSave(): boolean {
    return this.cents() > 0 && this.categoryId !== '' && this.paymentId !== '';
  }

  private async save(): Promise<void> {
    let savedId: string = this.props.editing === null ? '' : this.props.editing.id;
    this.errorText = '';
    const cents = this.cents();
    if (cents === 0) {
      this.errorText = '请输入金额';
      return;
    }
    if (this.categoryId === '' || this.paymentId === '') {
      this.errorText = '请选择分类与支付方式';
      return;
    }
    this.saving = true;
    try {
      const editing = this.props.editing;
      if (editing !== null) {
        const patch: ExpensePatchRequest = {
          amountCents: this.isRefund ? -cents : cents,
          categoryId: this.categoryId,
          paymentMethodId: this.paymentId,
          spendDate: this.spendDate,
          note: this.note
        };
        await Api.updateExpense(editing.id, patch);
      } else if (this.installment) {
        // 分期走计划接口（不是支出接口）：总额 + 期数，服务端生成各期待办
        const total = cents;
        const per = Math.floor(total / this.periods);
        const planReq: PlanCreateRequest = {
          name: `${this.categoryName()} 分期`,
          categoryId: this.categoryId,
          paymentMethodId: this.paymentId,
          source: 'installment',
          amountCents: per,
          totalAmountCents: total,
          periods: this.periods,
          firstDueDate: this.spendDate,
          remindDaysBefore: 3,
          autoPost: false,
          note: this.note
        };
        await Api.createPlan(planReq);
        savedId = '';
      } else {
        const req: ExpenseCreateRequest = {
          amountCents: this.isRefund ? -cents : cents,
          categoryId: this.categoryId,
          paymentMethodId: this.paymentId,
          spendDate: this.spendDate,
          note: this.note
        };
        const created = await Api.createExpense(req);
        savedId = created.expense.id;
        // 成功后才记住这次选择（失败的记账不该影响下次默认值）
        const pick: LastPickValue = { categoryId: this.categoryId, paymentMethodId: this.paymentId };
        await LastPick.write(pick);
      }
      this.props.onSaved(savedId);
    } catch (e) {
      const err = e as ApiError;
      if (err.kind === 'network' && this.props.editing === null) {
        // 离线写：入队（队列落库，关掉 App 也不会丢），联网后自动补推
        await this.enqueueOffline(cents);
        this.props.onSaved('');
        return;
      }
      this.errorText = err.kind === 'network' ? '网络不可用，请稍后再试' : err.message;
    } finally {
      this.saving = false;
    }
  }

  /**
   * 离线写入。
   *
   * 刻意**不做乐观行**：本地算不出还款日（账单周期那段逻辑只在服务端），
   * 硬造一行会让「这个月的合计」先对后错。所以只入队 + 明确告知，
   * 联网后同步进账，用户看到的是「已排队」而不是「已入账」。
   */
  private async enqueueOffline(cents: number): Promise<void> {
    const id = ulid();
    const payload = JSON.stringify({
      amountCents: this.isRefund ? -cents : cents,
      categoryId: this.categoryId,
      paymentMethodId: this.paymentId,
      spendDate: this.spendDate,
      note: this.note
    } as OfflineExpensePayload);
    await Outbox.enqueue('create_expense', id, payload);
    SyncEngine.schedulePush();
    this.errorText = '网络不可用：已存本机，联网后自动记入';
  }

  /** 日期选择（系统 DatePickerDialog，不自己画日历） */
  private pickDate(): void {
    // 系统 DatePickerDialog 与本应用的设计语言不一致（圆角/配色/字体都是系统的），
    // 改为自绘日历：月份 ‹ › + 星期表头 + 6×7 日格。
    const d = parseDateKey(this.spendDate);
    this.dateCalYear = d.getFullYear();
    this.dateCalMonth = d.getMonth() + 1;
    this.dateCalOpen = true;
  }

  /** 该年该月的天数 */
  private daysInMonth(y: number, m: number): number {
    return new Date(y, m, 0).getDate();
  }

  /** 该年该月 1 号是星期几（0=周日） */
  private firstWeekday(y: number, m: number): number {
    return new Date(y, m - 1, 1).getDay();
  }

  /** 日历格：前置留白用 0 表示 */
  private dayCells(): number[] {
    const out: number[] = [];
    const lead = this.firstWeekday(this.dateCalYear, this.dateCalMonth);
    for (let i = 0; i < lead; i++) {
      out.push(0);
    }
    const total = this.daysInMonth(this.dateCalYear, this.dateCalMonth);
    for (let d = 1; d <= total; d++) {
      out.push(d);
    }
    while (out.length % 7 !== 0) {
      out.push(0);
    }
    return out;
  }

  private shiftDateMonth(delta: number): void {
    let m = this.dateCalMonth + delta;
    let y = this.dateCalYear;
    if (m < 1) {
      m = 12;
      y = y - 1;
    } else if (m > 12) {
      m = 1;
      y = y + 1;
    }
    this.dateCalMonth = m;
    this.dateCalYear = y;
  }

  private pickDay(day: number): void {
    this.spendDate = dateKeyOf(this.dateCalYear, this.dateCalMonth, day);
    this.dateCalOpen = false;
    this.refreshPreview();
  }

  /** 删除是软删（墓碑），但仍要二次确认 —— 用户看到的是「没了」 */
  private confirmDelete(): void {
    const editing = this.props.editing;
    if (editing === null) {
      return;
    }
    AlertDialog.show({
      title: '删除这笔记录？',
      message: `${this.categoryName()} ${formatYuan(editing.amountCents)} · ${editing.spendDate}`,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: this.tok().danger,
        action: () => {
          this.saving = true;
          Api.deleteExpense(editing.id)
            .then(() => {
              this.saving = false;
              this.props.onSaved('');
            })
            .catch((e: ApiError) => {
              this.saving = false;
              this.errorText = e.message;
            });
        }
      }
    });
  }

  /** 单参数对象 + $$：多参数 @Builder 不会随分类/支付方式的变化重绘 */
  @Builder
  fieldRow($$: FieldRowModel) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text($$.label)
          .fontSize(9)
          .fontColor(this.tok().ink3)
        Text($$.value)
          .fontSize(13)
            .fontFeature('"tnum" on')
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tok().ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(16)
        .fontColor(this.tok().ink3)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.tok().surface2)
    .borderRadius(this.tok().rMd)
    .onClick(() => {
      $$.onTap();
    })
  }

  /**
   * 键盘（R101/R103）：**5 列** = 左支付列（独立，物理分割线）+ 右 4×4 数字键；
   * 宽高比 ~1.35:1；数字键浮起（surface + 阴影）；完成键占右侧两行。
   */
  /** R103：常用分类胶囊条（按本月笔数前 6），点一下直接换分类 */
  /** 分类图标色：二级跟随一级（同设置页 parentColor 的口径） */
  private catColorOf(cat: CategoryNode): string {
    for (const root of this.categories) {
      if (root.id === cat.parentId) {
        return categoryColorOf(root.name, root.color);
      }
      if (root.id === cat.id) {
        return categoryColorOf(root.name, root.color);
      }
    }
    return categoryColorOf(cat.name, cat.color);
  }

  /** 快捷分类第 i 个（没有就返回 null，调用处用 if 判断） */
  private quickAt(i: number): CategoryNode | null {
    const list = this.quickCats();
    return i < list.length ? list[i] : null;
  }

  /** 快捷分类单元格：宽高由外面的网格决定，样式跟键盘按键同一套 */
  @Builder
  quickCell(c: CategoryNode) {
    Row({ space: 4 }) {
      // 分类图标（和流水行/设置页同一套内置 Symbol；二级色跟随一级）
      CatIconView({
        catName: c.name,
        iconSize: 13,
        color: this.categoryId === c.id ? this.tok().accentInk : this.catColorOf(c)
      })
      Text(c.name)
        .fontSize(10.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(fontDisplayOf(this.isCyber()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontColor(this.categoryId === c.id ? this.tok().accentInk : this.tok().ink2)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.categoryId === c.id ? this.tok().accent : this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 11))
    .border({ width: 1, color: this.categoryId === c.id ? this.tok().accent : this.tok().line })
    .shadow(parseShadow(this.isCyber() ? '0px 0px 0px rgba(0,0,0,0)' : '2px 2px 0 ' + this.tok().line))
    .onClick(() => {
      this.categoryId = c.id;
      this.categoryOpen = false;
      this.refreshPreview();
    })
  }


  /** 消费日期日历（自绘，替代系统 DatePickerDialog） */
  @Builder
  dateCalendar() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.dateCalOpen = false;
        })
      Column({ space: 10 }) {
        Row() {
          Text('消费日期')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
          Blank()
          Text('关闭')
            .fontSize(11)
            .fontColor(this.tok().ink3)
            .onClick(() => {
              this.dateCalOpen = false;
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
              this.shiftDateMonth(-1);
            })
          Blank()
          Text(`${this.dateCalYear} 年 ${this.dateCalMonth} 月`)
            .fontSize(14)
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
              this.shiftDateMonth(1);
            })
        }
        .width('100%')

        Row() {
          ForEach(WEEKDAYS, (w: string) => {
            Text(w)
              .fontSize(10)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }, (w: string) => `wd-${w}`)
        }
        .width('100%')

        Grid() {
          ForEach(this.dayCells(), (d: number, idx: number) => {
            GridItem() {
              if (d === 0) {
                Text('')
                  .width('100%')
                  .height(34)
              } else {
                Text(`${d}`)
                  .fontSize(12.5)
                  .fontFamily(fontMonoOf())
                  .width('100%')
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .fontColor(this.spendDate === dateKeyOf(this.dateCalYear, this.dateCalMonth, d)
                    ? this.tok().accentInk
                    : this.tok().ink)
                  .backgroundColor(this.spendDate === dateKeyOf(this.dateCalYear, this.dateCalMonth, d)
                    ? this.tok().accent
                    : Color.Transparent)
                  .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
                  .onClick(() => {
                    this.pickDay(d);
                  })
              }
            }
          }, (d: number, idx: number) => `day-${idx}-${d}`)
        }
        .columnsTemplate('repeat(7, 1fr)')
        .columnsGap(2)
        .rowsGap(2)
        .width('100%')
        .height(240)
      }
      .width('88%')
      .padding(14)
      .backgroundColor(this.tok().bg)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
      .border({ width: this.tok().borderW, color: this.tok().line })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  quickBar() {
    // 列结构跟键盘完全一致：左 62vp（对齐支付列）+ 1vp 竖线 + 4 等分（对齐 7/8/9/←）
    Row() {
      Column() {
        if (this.quickAt(0) !== null) {
          this.quickCell(this.quickAt(0)!)
        }
      }
      .width(54)
      .height(40)

      Divider().vertical(true).strokeWidth(1).color(this.tok().line).height(40)

      Grid() {
        ForEach([1, 2, 3, 4], (i: number) => {
          GridItem() {
            if (this.quickAt(i) !== null) {
              this.quickCell(this.quickAt(i)!)
            }
          }
        }, (i: number) => `quick-${i}`)
      }
      .columnsTemplate('repeat(4, 1fr)')
      .columnsGap(5)
      .layoutWeight(1)
      .height(40)
      .padding({ left: 6 })
    }
    .width('100%')
    .height(40)
  }

  /** 常用分类：二级里本月笔数最多的前 6 个（不足则补最近使用的） */
  private quickCats(): CategoryNode[] {
    const out: CategoryNode[] = [];
    for (const root of this.categories) {
      for (const kid of root.children) {
        if (kid.isEnabled && kid.expenseCount > 0) {
          out.push(kid);
        }
      }
    }
    out.sort((a: CategoryNode, b: CategoryNode) => b.expenseCount - a.expenseCount);
    // 5 个正好铺满键盘的列宽：1 个对齐左侧支付列，4 个对齐 7/8/9/←
    return out.slice(0, 5);
  }

  @Builder
  keypad() {
    Row() {
      // 左：支付快捷列（与键盘之间用 1vp 竖线物理分割）
      Column({ space: 6 }) {
        ForEach(this.payments.slice(0, 4), (p: PaymentMethodItem) => {
          Row({ space: 4 }) {
            PayIconView({
              payName: p.name,
              payIcon: p.icon ?? '',
              iconSize: 13,
              colorOverride: this.paymentId === p.id ? this.tok().accentInk : ''
            })
            Text(this.shortName(p.name))
              .fontSize(9.5)
              .fontColor(this.paymentId === p.id ? this.tok().accentInk : this.tok().ink2)
              .maxLines(1)
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .width('100%')
          .padding({ top: 7, bottom: 7 })
          .backgroundColor(this.paymentId === p.id ? this.tok().accent : this.tok().surface)
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .border({ width: 1, color: this.tok().line })
          .onClick(() => {
            this.paymentId = p.id;
            this.refreshPreview();
          })
        }, (p: PaymentMethodItem) => p.id)
        // 「更多」常驻（Web ExpenseSheet.vue:546-557：取前 4 个 + 固定「更多」），
        // 支付方式少于 4 个时它就是打开完整列表的入口，不隐藏
        Button('更多')
          .fontSize(9)
          .layoutWeight(1)
          .width('100%')
          .backgroundColor(this.tok().surface3)
          .fontColor(this.tok().ink3)
          .onClick(() => {
            this.paymentOpen = true;
          })
      }
      // Web 移动端键盘左列是 54px（views.css:899；桌面才是 62px）
      .width(54)
      .height(210)
      .padding({ right: 6 })

      Divider().vertical(true).strokeWidth(1).color(this.tok().line).height(210)

      // 右：4×4（完成键跨两行）
      Grid() {
        ForEach(KEYPAD_KEYS, (key: string) => {
          GridItem() {
            Button(key === 'B' ? '←' : (key === 'C' ? '清空' : (key === 'OK' ? '保存' : key)))
              .width('100%')
              .height('100%')
              .fontSize(key === 'OK' ? 14 : (key === 'C' ? 13 : 19))
              .fontWeight(FontWeight.Bold)
              .fontFamily(fontDisplayOf(this.isCyber()))
              .backgroundColor(key === 'OK'
                ? (this.canSave() ? this.tok().accent : this.tok().surface2)
                : this.tok().surface)
              .fontColor(key === 'OK'
                ? (this.canSave() ? this.tok().accentInk : this.tok().ink3)
                : this.tok().ink)
              .borderRadius(radiusOf(this.tok(), this.isCyber(), 11))
              .border({ width: 1, color: this.tok().line })
              .shadow(parseShadow(this.isCyber() ? '0px 0px 0px rgba(0,0,0,0)' : '2px 2px 0 ' + this.tok().line))
              .onClick(() => {
                this.press(key);
              })
          }
          .rowStart(key === 'OK' ? 3 : undefined)
          .rowEnd(key === 'OK' ? 4 : undefined)
          .columnStart(key === 'OK' ? 4 : undefined)
          .columnEnd(key === 'OK' ? 4 : undefined)
        }, (key: string) => `k-${key}`)
      }
      .columnsTemplate('repeat(4, 1fr)')
      .rowsTemplate('repeat(4, 1fr)')
      .columnsGap(5)
      .rowsGap(5)
      .layoutWeight(1)
      .height(210)
      .padding({ left: 6 })
    }
    .width('100%')
    .height(210)
  }

  /** 当前主题令牌（每次 build 都重新取，跟随 themeName 变化） */
  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  /** 是否深色（cyber）—— 决定圆角/阴影/切角/字体族 */
  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  /** 分类选择弹窗：遮罩 + 居中卡片（原来是页面内联展开，会把键盘顶走） */
  @Builder
  catPickerSheet() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：点一下关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.categoryOpen = false;
        })
      Column({ space: 8 }) {
        Row() {
          Text('选择分类')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
          Blank()
          Text('关闭')
            .fontSize(11)
            .fontColor(this.tok().ink3)
            .onClick(() => {
              this.categoryOpen = false;
            })
        }
        .width('100%')

        Row({ space: 8 }) {
          List({ space: 4 }) {
            ForEach(this.categories, (root: CategoryNode) => {
              ListItem() {
                Text(root.name)
                  .fontSize(11)
                  .width('100%')
                  .padding(6)
                  .fontColor(this.railRootId === root.id ? this.tok().ink : this.tok().ink3)
                  .backgroundColor(this.railRootId === root.id ? this.tok().surface2 : this.tok().surface)
                  .borderRadius(6)
                  .onClick(() => {
                    this.railRootId = root.id;
                  })
              }
            }, (root: CategoryNode) => root.id)
          }
          .width(88)
          .height(160)
          .scrollBar(BarState.Off)

          Grid() {
            ForEach(this.railChildren(), (kid: CategoryNode) => {
              GridItem() {
                Text(kid.name)
                  .fontSize(11)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(6)
                  .fontColor(this.categoryId === kid.id ? this.tok().accentInk : this.tok().ink2)
                  .backgroundColor(this.categoryId === kid.id ? this.tok().accent : this.tok().surface)
                  .borderRadius(6)
                  .onClick(() => {
                    this.categoryId = kid.id;
                    this.categoryOpen = false;
                  })
              }
            }, (kid: CategoryNode) => kid.id)
          }
          .columnsTemplate('repeat(3, 1fr)')
          .columnsGap(6)
          .rowsGap(6)
          .layoutWeight(1)
          .height(160)
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

  /** 支付方式选择弹窗 */
  @Builder
  payPickerSheet() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .onClick(() => {
          this.paymentOpen = false;
        })
      Column({ space: 8 }) {
        Row() {
          Text('选择支付方式')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
          Blank()
          Text('关闭')
            .fontSize(11)
            .fontColor(this.tok().ink3)
            .onClick(() => {
              this.paymentOpen = false;
            })
        }
        .width('100%')

        List({ space: 4 }) {
          ForEach(this.payments, (p: PaymentMethodItem) => {
            ListItem() {
              Row() {
                Text(p.name)
                  .fontSize(12)
                  .fontColor(this.paymentId === p.id ? this.tok().ink : this.tok().ink2)
                Blank()
                if (p.type === 'credit') {
                  Text(`${p.billingDay ?? 0} 日账单 · ${p.repaymentDay ?? 0} 日还`)
                    .fontSize(9)
                    .fontColor(this.tok().ink3)
                }
              }
              .width('100%')
              .padding(8)
              .backgroundColor(this.paymentId === p.id ? this.tok().surface2 : this.tok().surface)
              .borderRadius(6)
              .onClick(() => {
                this.paymentId = p.id;
                this.paymentOpen = false;
                this.refreshPreview();
              })
            }
          }, (p: PaymentMethodItem) => p.id)
        }
        .width('100%')
        .height(160)
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

  build() {
    Stack({ alignContent: Alignment.Center }) {
    Column({ space: 10 }) {
      // 标题行：退款标记紧挨标题，**不再放右上角**
      // （右上角是 sheet 的系统关闭按钮位置，两者叠在一起会把金额盖住）
      Row({ space: 8 }) {
        Text(this.props.editing === null ? '记一笔' : '编辑支出')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tok().ink)
        if (this.isRefund) {
          Text('退款冲销')
            .fontSize(10)
            .fontColor(this.tok().danger)
        }
        Blank()
        // 编辑态才有的删除（原来在底部那一行，现在取消按钮去掉了，挪到标题右侧）
        if (this.props.editing !== null) {
          Text('删除')
            .fontSize(11)
            .fontColor(this.tok().danger)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.confirmDelete();
            })
        }
      }
      .width('100%')

      // 金额
      Row({ space: 2 }) {
        Text(this.isRefund ? '-¥' : '¥')
          .fontSize(18)
          .fontColor(this.tok().ink3)
        Text(this.amountText === '' ? '0.00' : this.amountText)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tok().ink)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)

      this.fieldRow({
        label: '分类', value: this.categoryName(), onTap: () => {
          this.categoryOpen = !this.categoryOpen;
        }
      })
      this.fieldRow({
        label: '消费日期', value: this.spendDate, onTap: () => {
          this.pickDate();
        }
      })
      this.fieldRow({
        label: '支付方式', value: this.paymentName(), onTap: () => {
          this.paymentOpen = !this.paymentOpen;
        }
      })

      TextInput({ placeholder: '备注（选填）', text: this.note })
        .height(36)
        .backgroundColor(this.tok().surface)
        .border({ width: this.tok().borderW, color: outlineStrongOf(this.isCyber()) })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
        .fontColor(this.tok().ink)
        .onChange((v: string) => {
          this.note = v;
        })
        .border({ width: this.noteFocus ? 2 : this.tok().borderW, color: this.noteFocus ? FOCUS_RING : this.lineColor() })
        .onFocus(() => {
          this.noteFocus = true;
        })
        .onBlur(() => {
          this.noteFocus = false;
        })

      // 账期预览：跨月必须醒目
      Row({ space: 4 }) {
        if (this.crossesMonth()) {
          // R108：明说年月与还款日，不只是裸 YYYY-MM
          Text('这笔会记在')
            .fontSize(10)
            .fontColor(this.tok().accent)
          Text(this.monthLabel(this.preview!.repaymentDate))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().accent)
          Text(`（还款日 ${this.dateShort(this.preview!.repaymentDate)}）`)
            .fontSize(10)
            .fontColor(this.tok().accent)
        } else {
          Text(this.preview === null ? '账期未取到' : `还款日 ${this.preview!.repaymentDate}`)
            .fontSize(10)
            .fontColor(this.tok().ink3)
        }
        Blank()
        Text(formatYuan(this.isRefund ? -this.cents() : this.cents()))
            .fontFeature('"tnum" on')
          .fontSize(10)
            .fontFeature('"tnum" on')
          .fontColor(this.tok().ink2)
      }
      .width('100%')

      // R113：分期仅信用卡且非退款可用；退款仅非分期可用（互斥）
      if (this.isCredit() && !this.isRefund) {
        Row({ space: 6 }) {
          Text('分期付款').fontSize(11).fontColor(this.tok().ink2).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.installment })
            .onChange((on: boolean) => {
              this.installment = on;
            })
        }
        .width('100%')
        if (this.installment) {
          Row({ space: 6 }) {
            ForEach(PERIOD_OPTIONS, (n: number) => {
              Text(`${n} 期`).fontSize(10)
                .fontColor(this.periods === n ? this.tok().accentInk : this.tok().ink2)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(this.periods === n ? this.tok().accent : this.tok().surface2)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), 999))
                .onClick(() => {
                  this.periods = n;
                })
            }, (n: number) => `p-${n}`)
            Blank()
          }
          .width('100%')
          Text(`每期约 ${formatYuan(Math.floor(this.cents() / this.periods))}`)
              .fontFeature('"tnum" on')
            .fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3).width('100%')
              .fontFeature('"tnum" on')
        }
      }

      Row({ space: 6 }) {
        Text('退款')
          .fontSize(11)
          .fontColor(this.tok().ink2)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.isRefund })
          .enabled(!this.installment)
          .onChange((on: boolean) => {
            this.isRefund = on;
          })
      }
      .width('100%')

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(11)
          .fontColor(this.tok().danger)
          .width('100%')
      }


      // 键盘上方只保留一行摘要（R107）：本月已支出，不 await，拿不到显示占位
      Row({ space: 6 }) {
        Text('本月已支出').fontSize(9).fontFamily(fontMonoOf()).fontColor(this.tok().ink3)
        Text(this.monthSpentCents === null ? '—' : formatYuan(this.monthSpentCents))
            .fontFeature('"tnum" on')
          .fontSize(10).fontFamily(fontMonoOf()).fontColor(this.tok().ink2)
            .fontFeature('"tnum" on')
      }
      .width('100%')

      if (this.noteFocus) {
        // R111：备注输入时折叠数字键盘，给出上方辅助保存条
        Row({ space: 8 }) {
          Text(formatYuan(this.isRefund ? -this.cents() : this.cents()))
              .fontFeature('"tnum" on')
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.tok().ink).layoutWeight(1)
              .fontFeature('"tnum" on')
          Button('收起键盘').fontSize(11).height(32)
            .backgroundColor(this.tok().surface2).fontColor(this.tok().ink3)
            .onClick(() => {
              this.noteFocus = false;
            })
          Button('保存').fontSize(12).height(32)
            .backgroundColor(this.tok().accent).fontColor(this.tok().accentInk)
            .enabled(this.canSave())
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(this.tok().surface2)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
      } else {
        this.quickBar()
        this.keypad()
      }

    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tok().bg)

    // 分类 / 支付方式：**弹窗**（遮罩 + 居中卡片），不再在底部内联展开把键盘顶走
    if (this.categoryOpen) {
      this.catPickerSheet()
    }
    if (this.paymentOpen) {
      this.payPickerSheet()
    }
    if (this.dateCalOpen) {
      this.dateCalendar()
    }
    }
    .width('100%')
    .height('100%')
  }

  /** 当前一级下的二级（没有二级就用一级自己） */
  private railChildren(): CategoryNode[] {
    for (const root of this.categories) {
      if (root.id === this.railRootId) {
        return root.children.length > 0 ? root.children : [root];
      }
    }
    return [];
  }
}

const WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

const KEYPAD_KEYS: string[] = ['7', '8', '9', 'B', '4', '5', '6', 'C', '1', '2', '3', 'OK', '0', '00', '.'];

interface OfflineExpensePayload {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
}

/** (年,月,日) → 'YYYY-MM-DD' */
function dateKeyOf(y: number, m: number, d: number): string {
  const mm = m < 10 ? `0${m}` : `${m}`;
  const dd = d < 10 ? `0${d}` : `${d}`;
  return `${y}-${mm}-${dd}`;
}

/** 'YYYY-MM-DD' → Date（本地时区零点，避免时区偏移一天） */
function parseDateKey(key: string): Date {
  return new Date(
    Number(key.substring(0, 4)),
    Number(key.substring(5, 7)) - 1,
    Number(key.substring(8, 10))
  );
}

/** Date → 'YYYY-MM-DD'（本地时区） */
function toDateKey(d: Date): string {
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}

/** 今天（YYYY-MM-DD，本地时区） */
function todayKey(): string {
  const d = new Date();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}

const PERIOD_OPTIONS: number[] = [3, 6, 12, 24];
