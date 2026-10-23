/**
 * 设置屏（H6）：四区 —— 账目 / 计划 / 数据 / 家庭。
 *
 * 与移动 Web 对齐：四个分段（不是二级页面层层点进去），
 * 一屏内切段即可看到对应内容。
 *
 * 危险动作一律收进「更多」菜单（decisions：跳过不可逆，不能与该做的动作同权重）。
 */
import { router } from '@kit.ArkUI';

import { Api, CategoryNode, PlanItem, PlanTodoItem, PaymentMethodItem, UserSummary } from '../../common/net/Api';
import { ApiError } from '../../common/net/ApiError';
import { AuthStore } from '../../common/auth/AuthStore';
import { Db } from '../../common/store/Db';
import { VectorRunner } from '../../common/contract/VectorRunner';
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
  @State vectorReport: string = '';
  @State schemaReport: string = '';
  @State railRootId: string = '';

  aboutToAppear(): void {
    this.reload();
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

  // ── 账目 ────────────────────────────────────────────────────────────────
  @Builder
  accountsSection() {
    Column({ space: 10 }) {
      Text('分类')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
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
          }, (kid: CategoryNode) => kid.id)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Divider().color(this.tokens.line)

      Text('支付方式')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
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
      Text('计划')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
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
      Text('成员')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens.ink)
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
