/**
 * 设置屏（H6）：四区 —— 账目 / 计划 / 数据 / 家庭。
 *
 * 与移动 Web 对齐：四个分段（不是二级页面层层点进去），
 * 一屏内切段即可看到对应内容。
 *
 * 危险动作一律收进「更多」菜单（decisions：跳过不可逆，不能与该做的动作同权重）。
 */
import { LengthMetrics, router } from '@kit.ArkUI';

import {
  Api,
  CategoryCreateRequest,
  CategoryNode,
  CategoryPatchRequest,
  PaymentCreateRequest,
  PaymentMethodItem,
  PaymentPatchRequest,
  PlanCreateRequest,
  PlanItem,
  PlanTodoItem,
  UserCreateRequest,
  UserSummary
} from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { AuthStore } from '../../common/auth/AuthStore';
import { Db } from '../../common/store/Db';
import { VectorRunner } from '../../common/contract/VectorRunner';
import { Outbox, OutboxEntry } from '../../common/sync/Outbox';
import { SyncEngine } from '../../common/sync/SyncEngine';
import { ThemeManager, ThemeName } from '../../common/theme/ThemeManager';
import { ThemeTokens } from '../../common/theme/AppTheme';
import { chartColor, hashIndex } from '../../common/theme/Palette';
import { formatYuan, daysUntil, urgencyLabel } from '../../common/contract/Contract';

@Component
export struct SettingsScreen {
  @State tokens: ThemeTokens = ThemeManager.get().tokens;
  @State themeName: ThemeName = ThemeManager.get().name;
  /** 0=账目 1=计划 2=数据 3=家庭 */
  @State section: number = 0;
  @State categories: CategoryNode[] = [];
  @State payments: PaymentMethodItem[] = [];
  @State plans: PlanItem[] = [];
  @State todos: PlanTodoItem[] = [];
  @State users: UserSummary[] = [];
  @State errorText: string = '';
  @State loading: boolean = false;
  /** 弹层：'' | category | payment | plan */
  @State sheetMode: string = '';
  @State editingCategoryId: string = '';
  @State editingPaymentId: string = '';
  @State editingPlanId: string = '';
  // 表单字段（分类）
  @State formName: string = '';
  @State formIcon: string = '';
  @State formColor: number = 0;
  @State formParent: string = '';
  // 表单字段（支付）
  @State formType: string = 'cash';
  @State formBillingDay: number = 0;
  @State formRepaymentDay: number = 0;
  @State formMergeInto: string = '';
  // 表单字段（计划）
  @State formCategoryId: string = '';
  @State formPaymentId: string = '';
  @State formAmount: string = '';
  @State formPeriods: number = 12;
  @State formFirstDue: string = '';
  @State formAutoPost: boolean = false;
  @State formUsername: string = '';
  @State formPassword: string = '';
  @State formRole: string = 'member';
  @State formError: string = '';
  @State pendingCount: number = 0;
  @State deadLetters: OutboxEntry[] = [];
  @State syncMessage: string = '';
  @State vectorReport: string = '';
  @State schemaReport: string = '';
  @State railRootId: string = '';

  aboutToAppear(): void {
    this.reload();
    this.refreshQueue();
  }

  /** 队列状态（待发送 / 死信）—— 死信必须可见，不许静默丢弃 */
  private async refreshQueue(): Promise<void> {
    try {
      this.pendingCount = await Outbox.pendingCount();
      this.deadLetters = await Outbox.deadLetters();
    } catch (e) {
      this.pendingCount = 0;
      this.deadLetters = [];
    }
  }

  private async syncNow(): Promise<void> {
    this.syncMessage = '同步中…';
    const report = await SyncEngine.syncNow();
    this.syncMessage = report.error !== ''
      ? report.error
      : `推送 ${report.pushed} · 拉取 ${report.pulled} · 游标 ${report.cursor}`;
    await this.refreshQueue();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const cats = await Api.categories();
      this.categories = cats.categories;
      if (this.categories.length > 0 && this.railRootId === '') {
        this.railRootId = this.categories[0].id;
      }
      const pays = await Api.paymentMethods();
      this.payments = pays.paymentMethods;
      const plans = await Api.plans();
      this.plans = plans.plans;
      const todoBody = await Api.planTodos(todayKey());
      this.todos = todoBody.todos;
      const userBody = await Api.users();
      this.users = userBody.users;
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.kind === 'network' ? '离线：设置项需要联网' : err.message;
    } finally {
      this.loading = false;
    }
  }

  private async switchTheme(name: ThemeName): Promise<void> {
    await ThemeManager.get().set(name);
    this.themeName = name;
    this.tokens = ThemeManager.get().tokens;
  }

  // ── 弹层：打开与保存 ────────────────────────────────────────────────────
  private openCategorySheet(cat: CategoryNode | null, parentId: string): void {
    this.formError = '';
    this.editingCategoryId = cat === null ? '' : cat.id;
    this.formName = cat === null ? '' : cat.name;
    this.formIcon = cat === null ? '' : cat.icon;
    this.formColor = cat === null ? 0 : Number(cat.color) || 0;
    this.formParent = cat === null ? parentId : (cat.parentId ?? '');
    this.sheetMode = 'category';
  }

  private openPaymentSheet(pay: PaymentMethodItem | null): void {
    this.formError = '';
    this.editingPaymentId = pay === null ? '' : pay.id;
    this.formName = pay === null ? '' : pay.name;
    this.formType = pay === null ? 'cash' : pay.type;
    this.formBillingDay = pay === null ? 0 : (pay.billingDay ?? 0);
    this.formRepaymentDay = pay === null ? 0 : (pay.repaymentDay ?? 0);
    this.formMergeInto = '';
    this.sheetMode = 'payment';
  }

  private openPlanSheet(): void {
    this.formError = '';
    this.editingPlanId = '';
    this.formName = '';
    this.formCategoryId = '';
    this.formPaymentId = '';
    this.formAmount = '';
    this.formPeriods = 12;
    this.formFirstDue = todayKey();
    this.formAutoPost = false;
    this.sheetMode = 'plan';
  }

  private openMemberSheet(): void {
    this.formError = '';
    this.formName = '';
    this.formUsername = '';
    this.formPassword = '';
    this.formRole = 'member';
    this.sheetMode = 'member';
  }

  private async saveMember(): Promise<void> {
    this.formError = '';
    if (this.formUsername.trim() === '' || this.formPassword.length < 6) {
      this.formError = '登录名必填，口令至少 6 位';
      return;
    }
    try {
      const req: UserCreateRequest = {
        username: this.formUsername.trim(),
        displayName: this.formName.trim() === '' ? this.formUsername.trim() : this.formName.trim(),
        password: this.formPassword,
        role: this.formRole
      };
      await Api.createUser(req);
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    }
  }

  private async saveCategory(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '') {
      this.formError = '请填写名称';
      return;
    }
    try {
      if (this.editingCategoryId === '') {
        const req: CategoryCreateRequest = {
          name: this.formName.trim(),
          parentId: this.formParent,
          icon: this.formIcon.trim(),
          color: this.formParent === '' ? String(this.formColor) : '',
          sortOrder: 0
        };
        await Api.createCategory(req);
      } else {
        const req: CategoryPatchRequest = {
          name: this.formName.trim(),
          icon: this.formIcon.trim(),
          // 二级分类不设颜色：颜色跟一级走，这里传空串让服务端保持继承
          color: this.formParent === '' ? String(this.formColor) : '',
          parentId: this.formParent === '' ? null : this.formParent,
          isEnabled: true
        };
        await Api.patchCategory(this.editingCategoryId, req);
      }
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      const err = e as ApiError;
      this.formError = err.message;
    }
  }

  private async savePayment(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '') {
      this.formError = '请填写名称';
      return;
    }
    if (this.formType === 'credit' && (this.formBillingDay < 1 || this.formRepaymentDay < 1)) {
      this.formError = '信用卡需要填写账单日与还款日';
      return;
    }
    try {
      if (this.editingPaymentId === '') {
        const req: PaymentCreateRequest = {
          name: this.formName.trim(),
          type: this.formType,
          icon: '',
          billingDay: this.formType === 'credit' ? this.formBillingDay : 0,
          repaymentDay: this.formType === 'credit' ? this.formRepaymentDay : 0,
          sortOrder: 0
        };
        await Api.createPayment(req);
      } else {
        const req: PaymentPatchRequest = {
          name: this.formName.trim(),
          icon: '',
          billingDay: this.formType === 'credit' ? this.formBillingDay : 0,
          repaymentDay: this.formType === 'credit' ? this.formRepaymentDay : 0,
          sortOrder: 0,
          isEnabled: true
        };
        await Api.patchPayment(this.editingPaymentId, req);
        if (this.formMergeInto !== '') {
          await Api.mergePayment(this.editingPaymentId, this.formMergeInto);
        }
      }
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      const err = e as ApiError;
      this.formError = err.message;
    }
  }

  private async savePlan(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '' || this.formCategoryId === '' || this.formPaymentId === '') {
      this.formError = '名称、分类、支付方式都要填';
      return;
    }
    const cents = Math.round(Number(this.formAmount) * 100);
    if (!Number.isFinite(cents) || cents <= 0) {
      this.formError = '每期金额要大于 0';
      return;
    }
    try {
      const req: PlanCreateRequest = {
        name: this.formName.trim(),
        categoryId: this.formCategoryId,
        paymentMethodId: this.formPaymentId,
        source: 'manual',
        amountCents: cents,
        totalAmountCents: 0,
        periods: this.formPeriods,
        firstDueDate: this.formFirstDue,
        remindDaysBefore: 3,
        autoPost: this.formAutoPost,
        note: ''
      };
      await Api.createPlan(req);
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      const err = e as ApiError;
      this.formError = err.message;
    }
  }

  // ── 账目 ────────────────────────────────────────────────────────────────
  @Builder
  accountsSection() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('分类')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .layoutWeight(1)
        Button('新增类别')
          .fontSize(10)
          .height(26)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.openCategorySheet(null, '');
          })
        Button('新增分类')
          .fontSize(10)
          .height(26)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.openCategorySheet(null, this.railRootId);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        List({ space: 4 }) {
          ForEach(this.categories, (root: CategoryNode) => {
            ListItem() {
              Row() {
                Text(root.name)
                  .fontSize(11)
                  .fontColor(this.railRootId === root.id ? this.tokens.ink : this.tokens.ink3)
                  .layoutWeight(1)
                Text(String(root.children.length))
                  .fontSize(9)
                  .fontColor(this.tokens.ink3)
              }
              .width('100%')
              .padding(8)
              .backgroundColor(this.railRootId === root.id ? this.tokens.surface2 : this.tokens.surface)
              .borderRadius(6)
              .onClick(() => {
                this.railRootId = root.id;
              })
            }
          }, (root: CategoryNode) => root.id)
        }
        .width(110)
        .height(200)

        Column({ space: 6 }) {
          ForEach(this.railChildren(), (kid: CategoryNode) => {
            Row({ space: 6 }) {
              Row()
                .width(8)
                .height(8)
                .backgroundColor(chartColor(this.tokens, hashIndex(kid.id)))
                .borderRadius(2)
              Text(kid.name)
                .fontSize(11)
                .fontColor(this.tokens.ink2)
                .layoutWeight(1)
              Text(`${kid.expenseCount} 笔`)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
              if (!kid.isEnabled) {
                Text('已停用')
                  .fontSize(9)
                  .fontColor(this.tokens.ink3)
              }
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
            .onClick(() => {
              this.openCategorySheet(kid, this.railRootId);
            })
          }, (kid: CategoryNode) => kid.id)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Divider().color(this.tokens.line)

      Row({ space: 8 }) {
        Text('支付方式')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .layoutWeight(1)
        Button('新增')
          .fontSize(10)
          .height(26)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.openPaymentSheet(null);
          })
      }
      .width('100%')

      ForEach(this.payments, (p: PaymentMethodItem) => {
        Row({ space: 8 }) {
          Text(p.name.substring(0, 1))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .fontSize(12)
            .fontColor(this.tokens.ink)
            .backgroundColor(this.tokens.surface2)
            .borderRadius(8)
          Column({ space: 2 }) {
            Text(p.name)
              .fontSize(12)
              .fontColor(this.tokens.ink)
            // 现金不显示账期说明（没有账单日），信用卡才显示
            if (p.type === 'credit') {
              Text(`${p.billingDay ?? 0} 日账单 · ${p.repaymentDay ?? 0} 日还款`)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (!p.isEnabled) {
            Text('已停用')
              .fontSize(9)
              .fontColor(this.tokens.ink3)
          }
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
        .onClick(() => {
          this.openPaymentSheet(p);
        })
      }, (p: PaymentMethodItem) => p.id)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  private railChildren(): CategoryNode[] {
    for (const root of this.categories) {
      if (root.id === this.railRootId) {
        return root.children.length > 0 ? root.children : [root];
      }
    }
    return [];
  }

  // ── 计划 ────────────────────────────────────────────────────────────────
  @Builder
  plansSection() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('计划')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .layoutWeight(1)
        Button('新建计划')
          .fontSize(10)
          .height(26)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.openPlanSheet();
          })
      }
      .width('100%')

      ForEach(this.plans, (plan: PlanItem) => {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(plan.name)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tokens.ink)
              .layoutWeight(1)
            if (plan.autoPost) {
              Text('自动')
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
            if (plan.state === 'ended') {
              Text('已结束')
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
            // 终止/删除是危险动作，收进「更多」
            Button('更多')
              .fontSize(9)
              .height(24)
              .backgroundColor(this.tokens.surface)
              .fontColor(this.tokens.ink3)
              .bindMenu([
                {
                  value: '终止计划',
                  action: () => {
                    this.endPlanById(plan.id);
                  }
                },
                {
                  value: '删除计划',
                  action: () => {
                    this.deletePlanById(plan.id);
                  }
                }
              ])
          }
          .width('100%')

          Text(`${plan.progress.paidCount}/${plan.progress.paidCount + plan.progress.pendingCount} 期 · 每期 ${formatYuan(plan.amountCents)}${plan.progress.nextDueDate !== null ? ' · 下次 ' + plan.progress.nextDueDate : ''}`)
            .fontSize(10)
            .fontColor(this.tokens.ink3)
            .width('100%')

          // 进度刻度最多 12 段：12 期一眼看得出还剩几格；360 期逐期画只会变一片灰点
          Row({ space: 2 }) {
            ForEach(planTicks(plan), (filled: boolean, index: number) => {
              Row()
                .layoutWeight(1)
                .height(4)
                .backgroundColor(filled ? this.tokens.accent : this.tokens.surface3)
                .borderRadius(2)
            }, (filled: boolean, index: number) => `${plan.id}-${index}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      }, (plan: PlanItem) => plan.id)

      if (this.todos.length > 0) {
        Divider().color(this.tokens.line)
        Text('待处理')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .width('100%')

        ForEach(this.todos, (todo: PlanTodoItem) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(`${todo.periodSeq}期 · ${todo.planName}`)
                .fontSize(11)
                .fontColor(this.tokens.ink)
              Text(`${todo.repaymentDate} · ${formatYuan(todo.amountCents)}`)
                .fontSize(9)
                .fontColor(this.tokens.ink3)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button(todo.willAutoPost ? '确认' : '入账')
              .fontSize(11)
              .height(28)
              .backgroundColor(this.tokens.surface2)
              .fontColor(this.tokens.ink)
              .onClick(() => {
                this.actTodo(todo, 'confirm');
              })

            // 危险动作收进「更多」：跳过不可逆，平铺等于把误触代价做得和正常操作一样低
            Button('更多')
              .fontSize(10)
              .height(28)
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
          .padding({ top: 4, bottom: 4 })
        }, (todo: PlanTodoItem) => todo.id)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  private async endPlanById(id: string): Promise<void> {
    try {
      await Api.endPlan(id);
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  private async deletePlanById(id: string): Promise<void> {
    try {
      await Api.deletePlan(id);
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  private async actTodo(todo: PlanTodoItem, action: string): Promise<void> {
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

  // ── 数据 ────────────────────────────────────────────────────────────────
  @Builder
  dataSection() {
    Column({ space: 12 }) {
      Text('主题')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
        .width('100%')

      Row({ space: 10 }) {
        Button('水果硬糖')
          .fontSize(12)
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.themeName === 'candy' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.themeName === 'candy' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.switchTheme('candy');
          })
        Button('赛博朋克')
          .fontSize(12)
          .height(36)
          .layoutWeight(1)
          .backgroundColor(this.themeName === 'cyber' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.themeName === 'cyber' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.switchTheme('cyber');
          })
      }
      .width('100%')

      Divider().color(this.tokens.line)

      Text('同步')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
        .width('100%')

      Row({ space: 8 }) {
        Text(`待发送 ${this.pendingCount} 条`)
          .fontSize(10)
          .fontColor(this.tokens.ink2)
          .layoutWeight(1)
        Button('立即同步')
          .fontSize(11)
          .height(30)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.syncNow();
          })
      }
      .width('100%')

      if (this.syncMessage !== '') {
        Text(this.syncMessage)
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }

      // 死信：重试用尽的条目，必须让用户看见并能重投
      if (this.deadLetters.length > 0) {
        Text(`发送失败 ${this.deadLetters.length} 条`)
          .fontSize(10)
          .fontColor(this.tokens.danger)
          .width('100%')
        ForEach(this.deadLetters, (entry: OutboxEntry) => {
          Text(`${entry.action} · ${entry.lastError !== '' ? entry.lastError : '未知原因'}`)
            .fontSize(9)
            .fontColor(this.tokens.ink3)
            .width('100%')
        }, (entry: OutboxEntry) => entry.id)
        Button('全部重试')
          .fontSize(11)
          .height(30)
          .width('100%')
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            Outbox.retryDeadLetters().then(() => {
              this.refreshQueue();
              this.syncNow();
            });
          })
      }

      Divider().color(this.tokens.line)

      Text('底座自检')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
        .width('100%')

      Row({ space: 10 }) {
        Button('跑测试向量')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.vectorReport = VectorRunner.runAll();
          })
        Button('看表结构')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            Db.schemaReport()
              .then((text: string) => {
                this.schemaReport = text;
              })
              .catch((e: Error) => {
                this.schemaReport = `读表结构失败：${e.message}`;
              });
          })
      }
      .width('100%')

      if (this.vectorReport !== '') {
        Text(this.vectorReport)
          .fontSize(9)
          .fontColor(this.tokens.ink2)
          .width('100%')
      }
      if (this.schemaReport !== '') {
        Text(this.schemaReport)
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }

      Divider().color(this.tokens.line)

      Button('退出登录')
        .fontSize(12)
        .height(36)
        .width('100%')
        .backgroundColor(this.tokens.surface2)
        .fontColor(this.tokens.danger)
        .onClick(() => {
          AuthStore.logout().then(() => {
            router.replaceUrl({ url: 'pages/LoginPage' });
          });
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  // ── 家庭 ────────────────────────────────────────────────────────────────
  @Builder
  familySection() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('成员')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink)
          .layoutWeight(1)
        Button('添加')
          .fontSize(10)
          .height(26)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.openMemberSheet();
          })
      }
      .width('100%')

      ForEach(this.users, (user: UserSummary) => {
        Row({ space: 8 }) {
          Text(user.displayName.substring(0, 1))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .fontSize(12)
            .fontColor(this.tokens.ink)
            .backgroundColor(this.tokens.surface2)
            .borderRadius(14)
          Column({ space: 2 }) {
            Text(user.displayName)
              .fontSize(12)
              .fontColor(this.tokens.ink)
            Text(user.username)
              .fontSize(9)
              .fontColor(this.tokens.ink3)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(user.role === 'owner' ? '管理员' : '成员')
            .fontSize(9)
            .fontColor(this.tokens.ink3)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }, (user: UserSummary) => user.id)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.tokens.surface)
    .borderRadius(this.tokens.rCard)
    .border({ width: 1, color: this.tokens.line })
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        this.sectionButton('账目', 0)
        this.sectionButton('计划', 1)
        this.sectionButton('数据', 2)
        this.sectionButton('家庭', 3)
      }
      .width('100%')

      if (this.errorText !== '') {
        Text(this.errorText)
          .fontSize(10)
          .fontColor(this.tokens.danger)
          .width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.section === 0) {
            this.accountsSection()
          } else if (this.section === 1) {
            this.plansSection()
          } else if (this.section === 2) {
            this.dataSection()
          } else {
            this.familySection()
          }
          if (this.loading) {
            Text('加载中…')
              .fontSize(10)
              .fontColor(this.tokens.ink3)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(this.tokens.bg)
  }

  @Builder
  sheetContent() {
    Column({ space: 10 }) {
      Text(this.sheetTitle())
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tokens.ink)
        .width('100%')

      if (this.sheetMode === 'category') {
        this.categoryForm()
      } else if (this.sheetMode === 'payment') {
        this.paymentForm()
      } else {
        this.planForm()
      }

      if (this.formError !== '') {
        Text(this.formError)
          .fontSize(10)
          .fontColor(this.tokens.danger)
          .width('100%')
      }

      Row({ space: 8 }) {
        Button('保存')
          .fontSize(13)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.tokens.accent)
          .fontColor(this.tokens.accentInk)
          .onClick(() => {
            if (this.sheetMode === 'category') {
              this.saveCategory();
            } else if (this.sheetMode === 'payment') {
              this.savePayment();
            } else if (this.sheetMode === 'member') {
              this.saveMember();
            } else {
              this.savePlan();
            }
          })
        Button('取消')
          .fontSize(13)
          .height(40)
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.ink2)
          .onClick(() => {
            this.sheetMode = '';
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.tokens.bg)
  }

  private sheetTitle(): string {
    if (this.sheetMode === 'category') {
      return this.editingCategoryId === '' ? '新增' : '编辑分类';
    }
    if (this.sheetMode === 'payment') {
      return this.editingPaymentId === '' ? '新增支付方式' : '编辑支付方式';
    }
    if (this.sheetMode === 'member') {
      return '添加成员';
    }
    return '新建计划';
  }

  @Builder
  categoryForm() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '名称', text: this.formName })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formName = v;
        })

      // 图标：先用 1 个字符代替（图标库接入放到 H8 打磨）
      TextInput({ placeholder: '图标（单个字符）', text: this.formIcon })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formIcon = v;
        })

      // 颜色只在「一级」出现：二级分类继承父级颜色，不给选择器
      if (this.formParent === '') {
        Text('颜色')
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('100%')
        Row({ space: 6 }) {
          ForEach(COLOR_SLOTS, (slot: number) => {
            Row()
              .width(26)
              .height(26)
              .backgroundColor(chartColor(this.tokens, slot))
              .borderRadius(13)
              .border({
                width: this.formColor === slot + 1 ? 3 : 1,
                color: this.formColor === slot + 1 ? this.tokens.ink : this.tokens.line
              })
              .onClick(() => {
                this.formColor = slot + 1;
              })
          }, (slot: number) => `color-${slot}`)
        }
        .width('100%')
      } else {
        Text('颜色跟所属一级分类走')
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('100%')
      }

      if (this.editingCategoryId !== '') {
        Button('停用分类')
          .fontSize(11)
          .height(32)
          .width('100%')
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.danger)
          .onClick(() => {
            this.deactivateCategory();
          })
      }
    }
    .width('100%')
  }

  @Builder
  paymentForm() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '名称', text: this.formName })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formName = v;
        })

      Row({ space: 8 }) {
        Button('现金/储蓄卡')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.formType === 'cash' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.formType === 'cash' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.formType = 'cash';
          })
        Button('信用卡')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.formType === 'credit' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.formType === 'credit' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.formType = 'credit';
          })
      }
      .width('100%')

      if (this.formType === 'credit') {
        Row({ space: 8 }) {
          Text(`账单日 ${this.formBillingDay} 日`)
            .fontSize(11)
            .fontColor(this.tokens.ink2)
            .layoutWeight(1)
          Counter() {
            Text('')
          }
          .onInc(() => {
            this.formBillingDay = Math.min(31, this.formBillingDay + 1);
          })
          .onDec(() => {
            this.formBillingDay = Math.max(1, this.formBillingDay - 1);
          })
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(`还款日 ${this.formRepaymentDay} 日`)
            .fontSize(11)
            .fontColor(this.tokens.ink2)
            .layoutWeight(1)
          Counter() {
            Text('')
          }
          .onInc(() => {
            this.formRepaymentDay = Math.min(31, this.formRepaymentDay + 1);
          })
          .onDec(() => {
            this.formRepaymentDay = Math.max(1, this.formRepaymentDay - 1);
          })
        }
        .width('100%')
      }

      if (this.editingPaymentId !== '') {
        Text('合并到（把本支付方式的记录并到另一个，然后停用本项）')
          .fontSize(9)
          .fontColor(this.tokens.ink3)
          .width('100%')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          ForEach(this.mergeTargets(), (p: PaymentMethodItem) => {
            Button(p.name)
              .fontSize(10)
              .height(26)
              .backgroundColor(this.formMergeInto === p.id ? this.tokens.accent : this.tokens.surface2)
              .fontColor(this.formMergeInto === p.id ? this.tokens.accentInk : this.tokens.ink2)
              .onClick(() => {
                this.formMergeInto = this.formMergeInto === p.id ? '' : p.id;
              })
          }, (p: PaymentMethodItem) => `merge-${p.id}`)
        }
        .width('100%')

        Button('停用支付方式')
          .fontSize(11)
          .height(32)
          .width('100%')
          .backgroundColor(this.tokens.surface2)
          .fontColor(this.tokens.danger)
          .onClick(() => {
            this.deactivatePayment();
          })
      }
    }
    .width('100%')
  }

  private mergeTargets(): PaymentMethodItem[] {
    const out: PaymentMethodItem[] = [];
    for (const p of this.payments) {
      if (p.id !== this.editingPaymentId && p.isEnabled) {
        out.push(p);
      }
    }
    return out;
  }

  @Builder
  memberForm() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '显示名（如 爱人）', text: this.formName })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formName = v;
        })
      TextInput({ placeholder: '登录名', text: this.formUsername })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formUsername = v;
        })
      TextInput({ placeholder: '初始口令（至少 6 位）', text: this.formPassword })
        .type(InputType.Password)
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formPassword = v;
        })
      Row({ space: 8 }) {
        Button('成员')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.formRole === 'member' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.formRole === 'member' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.formRole = 'member';
          })
        Button('管理员')
          .fontSize(11)
          .height(32)
          .layoutWeight(1)
          .backgroundColor(this.formRole === 'admin' ? this.tokens.accent : this.tokens.surface2)
          .fontColor(this.formRole === 'admin' ? this.tokens.accentInk : this.tokens.ink2)
          .onClick(() => {
            this.formRole = 'admin';
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  planForm() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '计划名称（如 房贷）', text: this.formName })
        .height(38)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formName = v;
        })

      Text('分类')
        .fontSize(9)
        .fontColor(this.tokens.ink3)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
        ForEach(this.allCategories(), (cat: CategoryNode) => {
          Button(cat.name)
            .fontSize(10)
            .height(26)
            .backgroundColor(this.formCategoryId === cat.id ? this.tokens.accent : this.tokens.surface2)
            .fontColor(this.formCategoryId === cat.id ? this.tokens.accentInk : this.tokens.ink2)
            .onClick(() => {
              this.formCategoryId = cat.id;
            })
        }, (cat: CategoryNode) => `pcat-${cat.id}`)
      }
      .width('100%')

      Text('支付方式')
        .fontSize(9)
        .fontColor(this.tokens.ink3)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
        ForEach(this.enabledPayments(), (p: PaymentMethodItem) => {
          Button(p.name)
            .fontSize(10)
            .height(26)
            .backgroundColor(this.formPaymentId === p.id ? this.tokens.accent : this.tokens.surface2)
            .fontColor(this.formPaymentId === p.id ? this.tokens.accentInk : this.tokens.ink2)
            .onClick(() => {
              this.formPaymentId = p.id;
            })
        }, (p: PaymentMethodItem) => `ppay-${p.id}`)
      }
      .width('100%')

      TextInput({ placeholder: '每期金额（元）', text: this.formAmount })
        .height(38)
        .type(InputType.NUMBER_DECIMAL)
        .backgroundColor(this.tokens.surface2)
        .onChange((v: string) => {
          this.formAmount = v;
        })

      Row({ space: 8 }) {
        Text(`共 ${this.formPeriods} 期`)
          .fontSize(11)
          .fontColor(this.tokens.ink2)
          .layoutWeight(1)
        Counter() {
          Text('')
        }
        .onInc(() => {
          this.formPeriods = Math.min(360, this.formPeriods + 1);
        })
        .onDec(() => {
          this.formPeriods = Math.max(1, this.formPeriods - 1);
        })
      }
      .width('100%')

      Row({ space: 8 }) {
        Text('自动入账')
          .fontSize(11)
          .fontColor(this.tokens.ink2)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.formAutoPost })
          .onChange((on: boolean) => {
            this.formAutoPost = on;
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  private allCategories(): CategoryNode[] {
    const out: CategoryNode[] = [];
    for (const root of this.categories) {
      if (root.children.length > 0) {
        for (const kid of root.children) {
          out.push(kid);
        }
      } else {
        out.push(root);
      }
    }
    return out;
  }

  private enabledPayments(): PaymentMethodItem[] {
    const out: PaymentMethodItem[] = [];
    for (const p of this.payments) {
      if (p.isEnabled) {
        out.push(p);
      }
    }
    return out;
  }

  private async deactivateCategory(): Promise<void> {
    try {
      const cat = this.findCategoryById(this.editingCategoryId);
      if (cat === null) {
        return;
      }
      const req: CategoryPatchRequest = {
        name: cat.name,
        icon: cat.icon,
        color: cat.parentId === null ? cat.color : '',
        parentId: cat.parentId,
        isEnabled: false
      };
      await Api.patchCategory(cat.id, req);
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    }
  }

  private async deactivatePayment(): Promise<void> {
    try {
      await Api.deletePayment(this.editingPaymentId);
      this.sheetMode = '';
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    }
  }

  private findCategoryById(id: string): CategoryNode | null {
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

  @Builder
  sectionButton(label: string, value: number) {
    Button(label)
      .fontSize(11)
      .height(30)
      .layoutWeight(1)
      .backgroundColor(this.section === value ? this.tokens.accent : this.tokens.surface2)
      .fontColor(this.section === value ? this.tokens.accentInk : this.tokens.ink3)
      .onClick(() => {
        this.section = value;
      })
  }
}

const COLOR_SLOTS: number[] = [0, 1, 2, 3, 4, 5, 6, 7];

/** 12 段进度刻度：按已还期数比例点亮（精确数字仍由旁边文字给出） */
function planTicks(plan: PlanItem): boolean[] {
  const total = plan.progress.paidCount + plan.progress.pendingCount;
  const filled = total > 0 ? Math.round((plan.progress.paidCount / total) * 12) : 0;
  const out: boolean[] = [];
  for (let i = 0; i < 12; i++) {
    out.push(i < filled);
  }
  return out;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function todayKey(): string {
  const now = new Date();
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`;
}
