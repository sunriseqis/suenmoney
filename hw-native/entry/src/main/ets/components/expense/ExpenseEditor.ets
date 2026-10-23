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
import { Api, CategoryNode, ExpenseCreateRequest, ExpensePreview, PaymentMethodItem } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { formatCents, formatYuan, parseYuanToCents } from '../../common/contract/Contract';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { ThemeTokens } from '../../common/theme/AppTheme';

export interface ExpenseEditorProps {
  onSaved: () => void;
  onCancel: () => void;
}

@Component
export struct ExpenseEditor {
  props: ExpenseEditorProps = { onSaved: () => {
  }, onCancel: () => {
  } };

  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  @State amountText: string = '';
  @State categoryId: string = '';
  @State paymentId: string = '';
  @State spendDate: string = todayKey();
  @State note: string = '';
  @State isRefund: boolean = false;
  @State saving: boolean = false;
  @State errorText: string = '';
  @State preview: ExpensePreview | null = null;
  @State categories: CategoryNode[] = [];
  @State payments: PaymentMethodItem[] = [];
  @State categoryOpen: boolean = false;
  @State paymentOpen: boolean = false;
  @State railRootId: string = '';

  aboutToAppear(): void {
    this.loadDict();
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
      // 默认选第一个可选分类与第一个支付方式
      if (this.categories.length > 0) {
        this.railRootId = this.categories[0].id;
        const kids = this.categories[0].children;
        this.categoryId = kids.length > 0 ? kids[0].id : this.categories[0].id;
      }
      if (this.payments.length > 0) {
        this.paymentId = this.payments[0].id;
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

  private async save(): Promise<void> {
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
      const req: ExpenseCreateRequest = {
        amountCents: this.isRefund ? -cents : cents,
        categoryId: this.categoryId,
        paymentMethodId: this.paymentId,
        spendDate: this.spendDate,
        note: this.note
      };
      await Api.createExpense(req);
      this.props.onSaved();
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.kind === 'network' ? '网络不可用（离线记账在 H7 接入）' : err.message;
    } finally {
      this.saving = false;
    }
  }

  @Builder
  fieldRow(label: string, value: string, onTap: () => void) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(9)
          .fontColor(this.tokens.ink3)
        Text(value)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(16)
        .fontColor(this.tokens.ink3)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.tokens.surface2)
    .borderRadius(this.tokens.rMd)
    .onClick(onTap)
  }

  @Builder
  keypad() {
    Row({ space: 6 }) {
      // 左：支付快捷列（前 4 个）
      Column({ space: 6 }) {
        ForEach(this.payments.slice(0, 4), (p: PaymentMethodItem) => {
          Button(p.name.substring(0, 2))
            .fontSize(11)
            .height(40)
            .width('100%')
            .backgroundColor(this.paymentId === p.id ? this.tokens.accent : this.tokens.surface)
            .fontColor(this.paymentId === p.id ? this.tokens.accentInk : this.tokens.ink2)
            .border({ width: 1, color: this.tokens.line })
            .onClick(() => {
              this.paymentId = p.id;
              this.refreshPreview();
            })
        }, (p: PaymentMethodItem) => p.id)
      }
      .width(64)

      // 右：4×4 数字键
      Grid() {
        ForEach(KEYPAD_KEYS, (key: string) => {
          GridItem() {
            Button(key === 'B' ? '⌫' : (key === 'C' ? 'C' : (key === 'OK' ? '完成' : key)))
              .width('100%')
              .height('100%')
              .fontSize(key === 'OK' ? 13 : 18)
              .backgroundColor(key === 'OK' ? this.tokens.accent : this.tokens.surface)
              .fontColor(key === 'OK' ? this.tokens.accentInk : this.tokens.ink)
              .border({ width: 1, color: this.tokens.line })
              .onClick(() => {
                if (key === 'OK') {
                  this.save();
                } else {
                  this.press(key);
                }
              })
          }
        }, (key: string) => key)
      }
      .columnsTemplate('repeat(4, 1fr)')
      .rowsTemplate('repeat(4, 1fr)')
      .columnsGap(6)
      .rowsGap(6)
      .layoutWeight(1)
      .height(190)
    }
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('记一笔')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tokens.ink)
        Blank()
        if (this.isRefund) {
          Text('退款冲销')
            .fontSize(10)
            .fontColor(this.tokens.danger)
        }
      }
      .width('100%')

      // 金额
      Row({ space: 2 }) {
        Text(this.isRefund ? '-¥' : '¥')
          .fontSize(18)
          .fontColor(this.tokens.ink3)
        Text(this.amountText === '' ? '0.00' : this.amountText)
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tokens.ink)
      }
      .width('100%')
      .justifyContent(FlexAlign.End)

      this.fieldRow('分类', this.categoryName(), () => {
        this.categoryOpen = !this.categoryOpen;
      })
      this.fieldRow('消费日期', this.spendDate, () => {
        // 日期选择在 H3 第二批接 DatePicker；先用今天，避免假交互
      })
      this.fieldRow('支付方式', this.paymentName(), () => {
        this.paymentOpen = !this.paymentOpen;
      })

      TextInput({ placeholder: '备注（选填）', text: this.note })
        .height(36)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.note = v;
        })

      // 账期预览：跨月必须醒目
      Row({ space: 4 }) {
        if (this.crossesMonth()) {
          Text('这笔会记在')
            .fontSize(10)
            .fontColor(this.tokens.accent)
          Text(this.preview!.repaymentDate.substring(0, 7))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tokens.accent)
        } else {
          Text(this.preview === null ? '账期未取到' : `还款日 ${this.preview!.repaymentDate}`)
            .fontSize(10)
            .fontColor(this.tokens.ink3)
        }
        Blank()
        Text(formatYuan(this.isRefund ? -this.cents() : this.cents()))
          .fontSize(10)
          .fontColor(this.tokens.ink2)
      }
      .width('100%')

      Row({ space: 6 }) {
        Text('退款（负数冲销）')
          .fontSize(11)
          .fontColor(this.tokens.ink2)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.isRefund })
          .onChange((on: boolean) => {
            this.isRefund = on;
          })
      }
      .width('100%')

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(11)
          .fontColor(this.tokens.danger)
          .width('100%')
      }

      // 分类面板（左一级导航 + 右二级网格）
      if (this.categoryOpen) {
        Row({ space: 8 }) {
          List({ space: 4 }) {
            ForEach(this.categories, (root: CategoryNode) => {
              ListItem() {
                Text(root.name)
                  .fontSize(11)
                  .width('100%')
                  .padding(6)
                  .fontColor(this.railRootId === root.id ? this.tokens.ink : this.tokens.ink3)
                  .backgroundColor(this.railRootId === root.id ? this.tokens.surface2 : this.tokens.surface)
                  .borderRadius(6)
                  .onClick(() => {
                    this.railRootId = root.id;
                  })
              }
            }, (root: CategoryNode) => root.id)
          }
          .width(88)
          .height(140)

          Grid() {
            ForEach(this.railChildren(), (kid: CategoryNode) => {
              GridItem() {
                Text(kid.name)
                  .fontSize(11)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding(6)
                  .fontColor(this.categoryId === kid.id ? this.tokens.accentInk : this.tokens.ink2)
                  .backgroundColor(this.categoryId === kid.id ? this.tokens.accent : this.tokens.surface)
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
          .height(140)
        }
        .width('100%')
      }

      // 支付面板
      if (this.paymentOpen) {
        List({ space: 4 }) {
          ForEach(this.payments, (p: PaymentMethodItem) => {
            ListItem() {
              Row() {
                Text(p.name)
                  .fontSize(12)
                  .fontColor(this.paymentId === p.id ? this.tokens.ink : this.tokens.ink2)
                Blank()
                if (p.type === 'credit') {
                  Text(`${p.billingDay ?? 0} 日账单 · ${p.repaymentDay ?? 0} 日还`)
                    .fontSize(9)
                    .fontColor(this.tokens.ink3)
                }
              }
              .width('100%')
              .padding(8)
              .backgroundColor(this.paymentId === p.id ? this.tokens.surface2 : this.tokens.surface)
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
        .height(120)
      }

      this.keypad()

      Row({ space: 8 }) {
        Button(this.saving ? '保存中…' : '保存')
          .fontSize(13)
          .height(42)
          .layoutWeight(1)
          .backgroundColor(this.tokens.accent)
          .fontColor(this.tokens.accentInk)
          .enabled(!this.saving)
          .onClick(() => {
            this.save();
          })
        Button('取消')
          .fontSize(13)
          .height(42)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.props.onCancel();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.bg)
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

const KEYPAD_KEYS: string[] = ['7', '8', '9', 'B', '4', '5', '6', 'C', '1', '2', '3', 'OK', '0', '00', '.', '0'];

/** 今天（YYYY-MM-DD，本地时区） */
function todayKey(): string {
  const d = new Date();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  return `${d.getFullYear()}-${m < 10 ? '0' + m : String(m)}-${day < 10 ? '0' + day : String(day)}`;
}
