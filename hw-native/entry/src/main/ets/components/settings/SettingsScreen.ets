/**
 * 设置屏（对齐 web SettingsView 移动端）：三区 —— 账目 / 计划与还款 / 设备。
 *
 * 用户裁决（2026-10-25）：hw 端把 web 的「数据 + 家庭」合并为「设备」，
 * 仅保留 主题 / 修改密码 / 检查更新；文件流（导出/导入/备份/快照/WebDAV/
 * 账单导入）与成员、登录设备在 hw 端不渲染。
 *
 * 危险动作一律收进「更多」菜单（more-menu）：跳过不可逆，不能与正常操作同权重。
 */

import { cardShadow, fontBodyOf, fontMonoOf, outlineStrongOf, parseShadow, radiusOf } from '../../common/ui/UiStyle';
import { LengthMetrics } from '@kit.ArkUI';
import { ApiError } from '../../common/net/ApiError';
import { router } from '@kit.ArkUI';
import { THEME_STORAGE_KEY, ThemeManager } from '../../common/theme/ThemeManager';
import { CANDY, CYBER, ThemeTokens } from '../../common/theme/AppTheme';
import { formatYuan } from '../../common/contract/Contract';

import { fieldBgOf, fieldBorderWOf } from '../../common/ui/UiStyle';
import { CatIconView } from '../../common/ui/CatIconView';
import { PayIconView } from '../../common/ui/PayIconView';
import { CATEGORY_COLORS, categoryColorOf } from '../../common/ui/CategoryIcon';
import { ServerConfig } from '../../common/net/ServerConfig';
import { ProbeResult, ServerRouter } from '../../common/net/ServerRouter';
import { PAY_OPTIONS, PayOption } from '../../common/ui/PaymentIcon';
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
  PlanTodoItem
} from '../../common/net/Api';

/** 图标选择项（存 lucide 名字，web 端可直接解析；hw 端用内置 Symbol 近似渲染） */
/**
 * 服务器地址单槽的渲染参数。
 * ArkUI 的多参数 @Builder 不会随状态刷新，所以统一用「单对象 + $$」传递。
 */
interface SrvSlot {
  index: number;
  value: string;
  state: string;
}

interface CatIconOption {
  name: string;
  label: string;
  res: Resource;
}

/** 分类图标精选（名字必须是 web ICON_REGISTRY 里的键；res 必须是已验证的 sys.symbol 字面量） */
const CAT_ICON_OPTIONS: CatIconOption[] = [
  { name: 'utensils', label: '餐饮', res: $r('sys.symbol.fork_knife') },
  { name: 'shopping-basket', label: '买菜', res: $r('sys.symbol.cart') },
  { name: 'shopping-cart', label: '购物', res: $r('sys.symbol.bag') },
  { name: 'car-front', label: '打车', res: $r('sys.symbol.car') },
  { name: 'bus', label: '公交', res: $r('sys.symbol.subway') },
  { name: 'fuel', label: '加油', res: $r('sys.symbol.fuelpump') },
  { name: 'house', label: '居住', res: $r('sys.symbol.house') },
  { name: 'zap', label: '水电', res: $r('sys.symbol.bolt') },
  { name: 'hand-coins', label: '红包', res: $r('sys.symbol.moneybag') },
  { name: 'stethoscope', label: '医疗', res: $r('sys.symbol.hospital') },
  { name: 'pill', label: '药品', res: $r('sys.symbol.drug') },
  { name: 'gamepad-2', label: '娱乐', res: $r('sys.symbol.gamecontroller') },
  { name: 'film', label: '电影', res: $r('sys.symbol.movie') },
  { name: 'dumbbell', label: '健身', res: $r('sys.symbol.dumbbell') },
  { name: 'book-open', label: '书籍', res: $r('sys.symbol.book') },
  { name: 'graduation-cap', label: '教育', res: $r('sys.symbol.graduationcap') },
  { name: 'gift', label: '礼物', res: $r('sys.symbol.gift') },
  { name: 'cat', label: '宠物', res: $r('sys.symbol.pawprint') },
  { name: 'smartphone', label: '话费', res: $r('sys.symbol.phone') },
  { name: 'laptop', label: '电脑', res: $r('sys.symbol.computer') },
  { name: 'shirt', label: '服饰', res: $r('sys.symbol.shirt') },
  { name: 'credit-card', label: '信用卡', res: $r('sys.symbol.creditcard') },
  { name: 'wallet', label: '钱包', res: $r('sys.symbol.wallet') },
  { name: 'circle-ellipsis', label: '其他', res: $r('sys.symbol.doc_text') }
];

/** 待办紧急度（与概况页同口径）：迟到 danger / 明日 warn / 其余 ok */
function urgencyColorOf(date: string, tokens: ThemeTokens): string {
  const a = new Date();
  const t = new Date(`${date}T00:00:00`);
  const days = Math.round((Date.UTC(t.getFullYear(), t.getMonth(), t.getDate())
    - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000);
  if (days < 0) {
    return tokens.danger;
  }
  if (days <= 1) {
    return tokens.warn;
  }
  return tokens.ok;
}

/** 今天（YYYY-MM-DD，本地时区） */
function todayKey(): string {
  const d = new Date();
  const m = `${d.getMonth() + 1}`.padStart(2, '0');
  const day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

/** web formatMonthDay：'3月5日' */
function formatMonthDay(date: string): string {
  const parts = date.split('-');
  if (parts.length < 3) {
    return date;
  }
  return `${Number(parts[1])}月${Number(parts[2])}日`;
}

@Component
export struct SettingsScreen {
  /** 订阅全局主题名：切换后本屏立即重绘（不能存 tokens 快照） */
  @StorageLink(THEME_STORAGE_KEY) themeName: string = ThemeManager.get().name;
  /** 三档：dark / light / system */
  @State themeMode: string = ThemeManager.get().themeMode;
  /** 0=账目 1=计划与还款 2=设备 */
  @State section: number = 0;
  @State categories: CategoryNode[] = [];
  @State payments: PaymentMethodItem[] = [];
  @State plans: PlanItem[] = [];
  /** 待处理期次（web plansStore.dueTodos） */
  @State todos: PlanTodoItem[] = [];
  /** 已处理期次（skipped 在前 + confirmed 在后，web 顺序） */
  @State doneTodos: PlanTodoItem[] = [];
  @State errorText: string = '';
  @State loading: boolean = false;
  @State toastText: string = '';
  /** 弹层：'' | cat | pay | merge | plan */
  @State sheetKind: string = '';
  @State sheetOpen: boolean = false;
  @State busy: boolean = false;
  @State formError: string = '';
  // ── 分类表单 ──
  @State railRootId: string = '';
  // ── 多服务器（R98 的三槽，登录后要能改，否则换了地址就永远进不去）──
  /** 用户自己维护的候选服务器列表（不是几个空框） */
  @State srvList: string[] = [];
  /** 每项的连通状态：'' 未测 / 'ok' / 'bad' */
  @State srvProbe: string[] = [];
  @State srvMsg: string = '';
  @State srvActive: string = '';
  @State editingCategoryId: string = '';
  @State formName: string = '';
  @State formIcon: string = '';
  /** '' = 自动；'1'..'16' = 色号（存索引不存色值，换主题整体重排） */
  @State formColor: string = '';
  @State formParent: string = '';
  // ── 支付表单 ──
  @State editingPaymentId: string = '';
  @State formType: string = 'cash';
  @State formBillingDay: string = '1';
  @State formRepaymentDay: string = '20';
  @State formPayIcon: string = '';
  // ── 合并 ──
  @State mergeFromId: string = '';
  @State mergeIntoId: string = '';
  // ── 计划表单 ──
  @State formCategoryId: string = '';
  @State formPaymentId: string = '';
  @State formAmount: string = '';
  @State formPeriods: string = '12';
  @State formFirstDue: string = '';
  @State formAutoPost: boolean = false;
  // ── 设备区 ──
  @State pwdCurrent: string = '';
  @State pwdNew: string = '';
  @State updateChecking: boolean = false;
  @State updateMessage: string = '';
  /** R126 跨月撤销警告（状态驱动，不用 AlertDialog） */
  @State revertWarnOpen: boolean = false;
  @State revertWarnText: string = '';
  private pendingRevertId: string = '';

  aboutToAppear(): void {
    this.loadServers();
    this.reload();
  }

  // ── 数据 ────────────────────────────────────────────────────────────────
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
      const planBody = await Api.plans();
      this.plans = planBody.plans;
      const todoBody = await Api.planTodos(todayKey());
      this.todos = todoBody.todos;
      const skipped = await Api.doneTodos('skipped');
      const done = await Api.doneTodos('confirmed');
      this.doneTodos = skipped.todos.concat(done.todos);
    } catch (e) {
      const err = e as ApiError;
      this.errorText = err.kind === 'network' ? '离线：设置项需要联网' : err.message;
    } finally {
      this.loading = false;
    }
  }

  private showToast(text: string): void {
    this.toastText = text;
    setTimeout(() => {
      this.toastText = '';
    }, 2000);
  }

  private tok(): ThemeTokens {
    return this.themeName === 'candy' ? CANDY : CYBER;
  }

  private isCyber(): boolean {
    return this.themeName === 'cyber';
  }

  private async switchTheme(mode: string): Promise<void> {
    this.themeMode = mode;
    if (mode === 'light') {
      await ThemeManager.get().setMode('light');
    } else if (mode === 'system') {
      await ThemeManager.get().setMode('system');
    } else {
      await ThemeManager.get().setMode('dark');
    }
  }

  // ── 分类 ────────────────────────────────────────────────────────────────
  /** 当前 rail 选中的一级分类 */
  private railRoot(): CategoryNode | null {
    for (const r of this.categories) {
      if (r.id === this.railRootId) {
        return r;
      }
    }
    return null;
  }

  private railChildren(): CategoryNode[] {
    const root = this.railRoot();
    return root === null ? [] : root.children;
  }

  /** 正在编辑的是否一级类别（决定颜色选择器 / 归属类别谁出现） */
  private editingRoot(): boolean {
    if (this.editingCategoryId === '') {
      return this.formParent === '';
    }
    for (const r of this.categories) {
      if (r.id === this.editingCategoryId) {
        return r.parentId === null;
      }
      for (const kid of r.children) {
        if (kid.id === this.editingCategoryId) {
          return false;
        }
      }
    }
    return false;
  }

  /** web openCatCreate：新增类别（parent 落到第一个一级 —— 与 web 现状一致） */
  private openCatCreate(): void {
    this.formError = '';
    this.editingCategoryId = '';
    this.formName = '';
    this.formParent = this.categories.length > 0 ? this.categories[0].id : '';
    this.formIcon = '';
    this.formColor = '';
    this.sheetKind = 'cat';
    this.sheetOpen = true;
  }

  /** 新增二级：父级用当前 rail 选中的一级 */
  private openCatCreateChild(): void {
    this.formError = '';
    this.editingCategoryId = '';
    this.formName = '';
    this.formParent = this.railRootId;
    this.formIcon = '';
    this.formColor = '';
    this.sheetKind = 'cat';
    this.sheetOpen = true;
  }

  private openCatEdit(cat: CategoryNode): void {
    this.formError = '';
    this.editingCategoryId = cat.id;
    this.formName = cat.name;
    this.formParent = cat.parentId ?? '';
    this.formIcon = cat.icon;
    this.formColor = cat.color;
    this.sheetKind = 'cat';
    this.sheetOpen = true;
  }

  private async saveCat(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '') {
      this.formError = '请填写分类名称';
      return;
    }
    this.busy = true;
    try {
      if (this.editingCategoryId === '') {
        const req: CategoryCreateRequest = {
          name: this.formName.trim(),
          parentId: this.formParent,
          icon: this.formIcon,
          color: this.formColor,
          sortOrder: 0
        };
        await Api.createCategory(req);
        this.showToast('分类已新增');
      } else {
        const isRoot = this.editingRoot();
        let enabled = true;
        for (const r of this.categories) {
          if (r.id === this.editingCategoryId) {
            enabled = r.isEnabled;
          }
          for (const kid of r.children) {
            if (kid.id === this.editingCategoryId) {
              enabled = kid.isEnabled;
            }
          }
        }
        const req: CategoryPatchRequest = {
          name: this.formName.trim(),
          icon: this.formIcon,
          // 二级分类不写颜色（跟随一级）；一级才写
          color: isRoot ? this.formColor : '',
          parentId: isRoot ? null : this.formParent,
          isEnabled: enabled
        };
        await Api.patchCategory(this.editingCategoryId, req);
        this.showToast('分类已更新');
      }
      this.sheetOpen = false;
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    } finally {
      this.busy = false;
    }
  }

  private async removeCat(cat: CategoryNode): Promise<void> {
    try {
      await Api.deleteCategory(cat.id);
      this.showToast('分类已删除');
      await this.reload();
    } catch (e) {
      this.showToast('该分类已有流水引用，请改为停用');
    }
  }

  // ── 支付方式 ────────────────────────────────────────────────────────────
  private openPayCreate(): void {
    this.formError = '';
    this.editingPaymentId = '';
    this.formName = '';
    this.formType = 'credit';
    this.formBillingDay = '1';
    this.formRepaymentDay = '20';
    this.formPayIcon = '';
    this.sheetKind = 'pay';
    this.sheetOpen = true;
  }

  private openPayEdit(p: PaymentMethodItem): void {
    this.formError = '';
    this.editingPaymentId = p.id;
    this.formName = p.name;
    this.formType = p.type;
    this.formBillingDay = `${p.billingDay ?? 1}`;
    this.formRepaymentDay = `${p.repaymentDay ?? 20}`;
    this.formPayIcon = p.icon;
    this.sheetKind = 'pay';
    this.sheetOpen = true;
  }

  private async savePay(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '') {
      this.formError = '请填写支付方式名称';
      return;
    }
    this.busy = true;
    const isCredit = this.formType === 'credit';
    try {
      if (this.editingPaymentId === '') {
        const req: PaymentCreateRequest = {
          name: this.formName.trim(),
          type: this.formType,
          icon: this.formPayIcon,
          billingDay: isCredit ? Number(this.formBillingDay) : 0,
          repaymentDay: isCredit ? Number(this.formRepaymentDay) : 0,
          sortOrder: 0
        };
        await Api.createPayment(req);
        this.showToast('支付方式已新增');
      } else {
        let enabled = true;
        for (const p of this.payments) {
          if (p.id === this.editingPaymentId) {
            enabled = p.isEnabled;
          }
        }
        const req: PaymentPatchRequest = {
          name: this.formName.trim(),
          icon: this.formPayIcon,
          billingDay: isCredit ? Number(this.formBillingDay) : 0,
          repaymentDay: isCredit ? Number(this.formRepaymentDay) : 0,
          sortOrder: 0,
          isEnabled: enabled
        };
        await Api.patchPayment(this.editingPaymentId, req);
        this.showToast('支付方式已更新');
      }
      this.sheetOpen = false;
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    } finally {
      this.busy = false;
    }
  }

  private openMerge(p: PaymentMethodItem): void {
    this.formError = '';
    this.mergeFromId = p.id;
    this.mergeIntoId = '';
    for (const x of this.payments) {
      if (x.id !== p.id) {
        this.mergeIntoId = x.id;
        break;
      }
    }
    this.sheetKind = 'merge';
    this.sheetOpen = true;
  }

  private mergeFromName(): string {
    for (const p of this.payments) {
      if (p.id === this.mergeFromId) {
        return p.name;
      }
    }
    return '';
  }

  private async runMerge(): Promise<void> {
    if (this.mergeFromId === '' || this.mergeIntoId === '') {
      return;
    }
    this.busy = true;
    try {
      await Api.mergePayment(this.mergeFromId, this.mergeIntoId);
      this.showToast('已合并');
      this.sheetOpen = false;
      await this.reload();
    } catch (e) {
      this.formError = '合并失败';
    } finally {
      this.busy = false;
    }
  }

  private async removePay(p: PaymentMethodItem): Promise<void> {
    try {
      await Api.deletePayment(p.id);
      this.showToast('支付方式已删除');
      await this.reload();
    } catch (e) {
      this.showToast('该支付方式已有流水引用，请改为停用');
    }
  }

  // ── 计划 ────────────────────────────────────────────────────────────────
  private planTotal(p: PlanItem): number {
    return p.progress.paidCount + p.progress.pendingCount;
  }

  private activePlansCount(): number {
    let n = 0;
    for (const p of this.plans) {
      if (p.state === 'active') {
        n++;
      }
    }
    return n;
  }

  private endedPlansCount(): number {
    let n = 0;
    for (const p of this.plans) {
      if (p.state !== 'active') {
        n++;
      }
    }
    return n;
  }

  private openPlanSheet(): void {
    this.formError = '';
    this.formName = '';
    this.formCategoryId = this.categories.length > 0 ? this.categories[0].id : '';
    this.formPaymentId = '';
    for (const p of this.payments) {
      if (p.isEnabled) {
        this.formPaymentId = p.id;
        break;
      }
    }
    this.formAmount = '';
    this.formPeriods = '12';
    this.formFirstDue = todayKey();
    this.formAutoPost = false;
    this.sheetKind = 'plan';
    this.sheetOpen = true;
  }

  private async savePlan(): Promise<void> {
    this.formError = '';
    if (this.formName.trim() === '' || this.formCategoryId === '' || this.formPaymentId === '') {
      this.formError = '名称、分类、支付方式都要填';
      return;
    }
    const cents = Math.round(Number(this.formAmount) * 100);
    if (!Number.isFinite(cents) || cents <= 0) {
      this.formError = '请填写名称与每期金额';
      return;
    }
    this.busy = true;
    try {
      const req: PlanCreateRequest = {
        name: this.formName.trim(),
        categoryId: this.formCategoryId,
        paymentMethodId: this.formPaymentId,
        source: 'manual',
        amountCents: cents,
        totalAmountCents: 0,
        periods: Number(this.formPeriods),
        firstDueDate: this.formFirstDue,
        remindDaysBefore: 3,
        autoPost: this.formAutoPost,
        note: ''
      };
      await Api.createPlan(req);
      this.showToast('计划已创建');
      this.sheetOpen = false;
      await this.reload();
    } catch (e) {
      this.formError = (e as ApiError).message;
    } finally {
      this.busy = false;
    }
  }

  private async endPlan(p: PlanItem): Promise<void> {
    try {
      await Api.endPlan(p.id);
      this.showToast('计划已终止');
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  private async removePlan(p: PlanItem): Promise<void> {
    try {
      await Api.deletePlan(p.id);
      this.showToast('计划已删除');
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  // ── 期次 ────────────────────────────────────────────────────────────────
  private async actTodo(t: PlanTodoItem): Promise<void> {
    try {
      if (t.willAutoPost) {
        await Api.ackTodo(t.id);
        this.showToast('已确认并自动入账');
      } else {
        await Api.confirmTodo(t.id, '');
        this.showToast('已手动入账');
      }
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  private async skipTodo(t: PlanTodoItem): Promise<void> {
    try {
      await Api.skipTodo(t.id);
      this.showToast('已忽略本期');
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  /** 撤销入账 / 恢复跳过；R126：撤销跨月入账先警告（不阻止） */
  private restoreOrRevert(t: PlanTodoItem): void {
    if (t.status !== 'skipped') {
      const crossMonth = t.expenseMonth !== undefined && t.expenseMonth !== ''
        && t.expenseMonth !== todayKey().substring(0, 7);
      if (crossMonth) {
        this.revertWarnText = `这笔 ${formatYuan(t.amountCents)} 记在 ${t.expenseMonth}，撤销后 ${t.expenseMonth} 的报表会跟着变。`;
        this.pendingRevertId = t.id;
        this.revertWarnOpen = true;
        return;
      }
      this.doRevert(t.id);
    } else {
      this.doRestore(t.id);
    }
  }

  private async doRevert(id: string): Promise<void> {
    try {
      await Api.revertTodo(id);
      this.showToast('已撤销入账');
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  private async doRestore(id: string): Promise<void> {
    try {
      await Api.restoreTodo(id);
      this.showToast('已恢复为待处理');
      await this.reload();
    } catch (e) {
      this.errorText = (e as ApiError).message;
    }
  }

  // ── 设备区 ──────────────────────────────────────────────────────────────
  private async changePassword(): Promise<void> {
    if (this.pwdNew.length < 8) {
      this.showToast('新口令至少 8 位');
      return;
    }
    try {
      const res = await Api.changePassword(this.pwdCurrent, this.pwdNew);
      this.pwdCurrent = '';
      this.pwdNew = '';
      this.showToast(res.message !== '' ? res.message : '口令已修改');
    } catch (e) {
      this.showToast('修改失败：当前口令不对？');
    }
  }

  private async checkUpdate(): Promise<void> {
    this.updateChecking = true;
    try {
      const health = await Api.health();
      this.updateMessage = `服务端 v${health.version} · 连接正常`;
    } catch (e) {
      this.updateMessage = (e as ApiError).message;
    } finally {
      this.updateChecking = false;
    }
  }

  // ── 弹层标题 ────────────────────────────────────────────────────────────
  private sheetTitle(): string {
    if (this.sheetKind === 'cat') {
      return this.editingCategoryId === '' ? '新增分类' : '编辑分类';
    }
    if (this.sheetKind === 'pay') {
      return this.editingPaymentId === '' ? '新增支付方式' : '编辑支付方式';
    }
    if (this.sheetKind === 'merge') {
      return '合并支付方式';
    }
    return '新建计划';
  }

  // ══ UI ═════════════════════════════════════════════════════════════════
  /** 从 ServerConfig 读出三个槽（已填的地址 + 当前生效地址） */
  private loadServers(): void {
    this.srvList = ServerConfig.get().allServers.slice();
    this.srvActive = ServerConfig.get().baseUrl;
    this.srvProbe = [];
    for (let i = 0; i < this.srvList.length; i++) {
      this.srvProbe.push('');
    }
    this.srvMsg = '';
  }

  /** 三个槽派生出的有效地址 */
  private srvFilled(): string[] {
    const out: string[] = [];
    for (const v of this.srvList) {
      if (v.trim() !== '') {
        out.push(v.trim());
      }
    }
    return out;
  }

  /** 追加一条空候选（用户点「添加服务器」） */
  private addServer(): void {
    this.srvList.push('');
    this.srvProbe.push('');
    this.srvMsg = '';
  }

  /** 删除第 i 条候选 */
  private removeServer(i: number): void {
    if (i < this.srvList.length) {
      this.srvList.splice(i, 1);
      this.srvProbe.splice(i, 1);
      this.srvMsg = '';
    }
  }

  /** 逐槽探活 */
  private async testServers(): Promise<void> {
    const states: string[] = [];
    let okCount = 0;
    for (let i = 0; i < this.srvList.length; i++) {
      const url = this.srvList[i].trim();
      if (url === '') {
        states.push('');
        continue;
      }
      try {
        const r: ProbeResult = await ServerRouter.probe(url);
        states.push(r.ok ? 'ok' : 'bad');
        if (r.ok) {
          okCount += 1;
        }
      } catch (e) {
        states.push('bad');
      }
    }
    this.srvProbe = states;
    this.srvMsg = okCount > 0 ? `${okCount} 个地址可用` : '所有地址都连不上';
  }

  /** 保存三个槽（去空，第一个作为生效地址） */
  private async saveServers(): Promise<void> {
    const next = this.srvFilled();
    if (next.length === 0) {
      this.srvMsg = '至少填一个地址';
      return;
    }
    // 与 suenmusic 的模型一致：候选列表指向**同一套后端**（同 DB / 同 JWT），
    // 换路径不需要重新登录，所以这里只落库，不清 token。
    // 生效地址由 ServerRouter 按顺序探活自己选，用户不用手点「设为生效」。
    await ServerConfig.get().setServers(next, next[0]);
    this.srvActive = ServerConfig.get().baseUrl;
    this.srvMsg = '已保存';
  }

  /** 服务器地址单槽（连通点 + 输入框） */
  @Builder
  serverSlot($$: SrvSlot) {
    Row({ space: 8 }) {
      // 连通指示：未测=空心，可用=accent，不可用=danger
      Row()
        .width(7)
        .height(7)
        .borderRadius(4)
        .backgroundColor($$.state === 'ok'
          ? this.tok().ok
          : ($$.state === 'bad' ? this.tok().danger : this.tok().line))
      TextInput({ text: $$.value, placeholder: 'http://主机:端口' })
        .fontSize(11.5)
        .fontFamily(fontMonoOf())
        .layoutWeight(1)
        .height(34)
        .backgroundColor(this.isCyber() ? this.tok().surface3 : this.tok().surface2)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
        .border({ width: fieldBorderWOf(1, this.isCyber()), color: this.tok().line })
        .fontColor(this.tok().ink)
        .onChange((v: string) => {
          this.srvList[$$.index] = v;
        })
      if ($$.value.trim() !== '' && $$.value.trim() === this.srvActive) {
        Text('生效')
          .fontSize(9)
          .fontColor(this.tok().accent)
      }
      Text('×')
        .fontSize(14)
        .fontColor(this.tok().ink3)
        .width(26)
        .height(26)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.removeServer($$.index);
        })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  /** 当前左栏选中一级分类的颜色（二级分类继承它） */
  private parentColor(): string {
    for (const root of this.categories) {
      if (root.id === this.railRootId) {
        return categoryColorOf(root.name, root.color);
      }
    }
    return categoryColorOf('', '');
  }

  build() {
    // ⚠ 必须给 Stack 显式尺寸：否则 Scroll 的 height('100%') 没有参照，
    //   内容短的 tab（设备区）会被 Alignment.Bottom 推向底部居中，切 tab 就来回跳。
    Stack({ alignContent: Alignment.TopStart }) {
      // Scroll 必须放在一个「高度确定」的容器里（layoutWeight 撑满）：
      // 直接把 Scroll 当 Stack 子节点时，内容比视口短会被居中（设备区就是这样跳的）
      Column() {
      Scroll() {
        Column({ space: 12 }) {
          this.settingsTabs()
          if (this.section === 0) {
            this.catCard()
            this.payCard()
          } else if (this.section === 1) {
            this.plansCard()
            if (this.doneTodos.length > 0) {
              this.doneCard()
            }
            this.dueCard()
          } else {
            this.themeCard()
            this.serverCard()
            this.passwordCard()
            this.updateCard()
          }
          if (this.errorText !== '') {
            Text(this.errorText)
              .fontSize(11)
              .fontColor(this.tok().danger)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          if (this.loading) {
            Text('加载中…')
              .fontSize(10.5)
              .fontColor(this.tok().ink2)
              .width('100%')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        // 内容比视口短时（设备区），Scroll 会把内容列垂直居中 → 切 tab 整屏跳动。
        // 给一个「至少占满视口」的下限，内容就永远从顶部开始。
        .constraintSize({ minHeight: '100%' })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')

      // 浮层兜底容器：撑满高度 + 底对齐，替代原来 Stack 的 Alignment.Bottom
      // （Bottom 对齐会把「设备」这种内容短的 tab 整屏推到底部居中，切 tab 就跳）
      Column() {
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

      // R126 跨月撤销警告（状态驱动弹层）
      if (this.revertWarnOpen) {
        Column({ space: 10 }) {
          Text('撤销跨月入账')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink)
          Text(this.revertWarnText)
            .fontSize(11)
            .fontColor(this.tok().ink2)
          Row({ space: 8 }) {
            Button('再想想')
              .fontSize(11)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(this.tok().surface2)
              .fontColor(this.tok().ink2)
              .onClick(() => {
                this.revertWarnOpen = false;
              })
            Button('仍然撤销')
              .fontSize(11)
              .height(32)
              .layoutWeight(1)
              .backgroundColor(this.tok().danger)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.revertWarnOpen = false;
                this.doRevert(this.pendingRevertId);
              })
          }
          .width('100%')
        }
        .width('86%')
        .padding(14)
        .backgroundColor(this.tok().surface)
        .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
        .border({ width: 2, color: this.tok().danger })
        .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
      }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.sheetOpen, this.settingsSheet(), {
      height: SheetSize.LARGE,
      radius: this.isCyber() ? LengthMetrics.vp(0) : LengthMetrics.vp(22),
      dragBar: true,
      // 和记账抽屉一致：不要系统关闭按钮（它压住内容右上角，会盖到表单第一行）
      showClose: false,
      backgroundColor: this.tok().bg
    })
  }

  /** 分区页签（web .settings-tabs / .stab：下划线式） */
  @Builder
  settingsTabs() {
    Row({ space: 4 }) {
      this.stab('账目', 0)
      this.stab('计划与还款', 1)
      this.stab('设备', 2)
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: this.tok().line })
  }

  @Builder
  stab(label: string, value: number) {
    Text(label)
      .fontSize(11.5)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.section === value ? this.tok().ink : this.tok().ink3)
      .padding({ left: 10, right: 10, top: 7, bottom: 4 })
      .border({
        width: { bottom: 3 },
        color: this.section === value ? this.tok().accent : Color.Transparent
      })
      .onClick(() => {
        this.section = value;
      })
  }

  /** 悬浮圆图标（web .orb） */
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

  /** 卡片标题（web .card-h：orb + card-t + 右侧动作） */
  @Builder
  cardHead(title: string, hasOrb: boolean, orbTone: string, orbIcon: Resource) {
    Row({ space: 10 }) {
      if (hasOrb) {
        this.orb(orbTone, orbIcon)
      }
      Text(title)
        .fontSize(this.isCyber() ? 12.5 : 15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .letterSpacing(this.isCyber() ? 1.25 : 0)
        .fontColor(this.tok().ink)
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 13 })
  }

  /** 空态（web .empty） */
  @Builder
  emptyState(icon: Resource, text: string) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([this.tok().ink3])
      Text(text)
        .fontSize(12)
        .fontColor(this.tok().ink3)
    }
    .width('100%')
    .padding({ top: 34, bottom: 34, left: 10, right: 10 })
    .alignItems(HorizontalAlign.Center)
  }

  /** 小按钮（web .btn--sm）：默认变体 */
  @Builder
  smBtn(label: string) {
    Text(label)
      .fontSize(this.isCyber() ? 10 : 11.5)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
      .padding({ left: 11, right: 11, top: 4, bottom: 4 })
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
      .border({
        width: this.tok().borderW,
        color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
      })
      .shadow(this.isCyber()
        ? { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions
        : parseShadow('3px 3px 0 #1E293B') as ShadowOptions)
  }

  /** 幽灵小按钮（web .btn--ghost.btn--sm） */
  @Builder
  ghostSmBtn(label: string) {
    Text(label)
      .fontSize(11.5)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tok().ink2)
      .padding({ left: 11, right: 11, top: 4, bottom: 4 })
  }

  /** 图标圆按钮（web .icon-btn：38px 胶囊） */
  @Builder
  iconBtn(icon: Resource) {
    Stack() {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([this.tok().ink2])
    }
    .width(34)
    .height(34)
    .borderRadius(this.isCyber() ? 1 : 17)
    .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
    .border({
      width: this.tok().borderW,
      color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line
    })
  }

  /** 药丸标签（web .tag） */
  @Builder
  tag(text: string, tone: string) {
    Text(text)
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontFamily(fontMonoOf())
      .fontColor(tone === 'accent' ? this.tok().accent
        : (tone === 'warn' ? this.tok().warn : this.tok().ink2))
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: 1,
        style: tone === 'dash' ? BorderStyle.Dashed : BorderStyle.Solid,
        color: tone === 'accent' ? this.tok().accent
          : (tone === 'warn' ? this.tok().warn : this.tok().line)
      })
      .backgroundColor(tone === '' || tone === 'dash' ? this.tok().surface2 : Color.Transparent)
  }

  // ── 账目区 ──────────────────────────────────────────────────────────────
  /** 分类管理卡（web cat-admin 移动端：rail 横排换行 + 子类列表） */
  @Builder
  catCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        this.orb(this.tok().accent, $r('sys.symbol.label'))
        Text('分类管理')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
        Text('新增类别')
          .fontSize(this.isCyber() ? 10 : 11.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
          .padding({ left: 11, right: 11, top: 4, bottom: 4 })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .border({
            width: this.tok().borderW,
            color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
          })
          .onClick(() => {
            this.openCatCreate();
          })
      }
      .width('100%')
      .margin({ bottom: 3 })

      // 左侧一级导航（移动端：横排换行）
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(4), cross: LengthMetrics.px(4) } }) {
        ForEach(this.categories, (root: CategoryNode) => {
          Row({ space: 8 }) {
            CatIconView({
              catName: root.name,
              iconSize: 18,
              color: categoryColorOf(root.name, root.color)
            })
            Text(root.name)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.railRootId === root.id ? this.tok().ink : this.tok().ink2)
              .maxLines(1)
            Text(`${root.children.length}`)
              .fontSize(10)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
          }
          .padding({ left: 9, right: 9, top: 7, bottom: 7 })
          .borderRadius(this.isCyber() ? 1 : 9)
          .backgroundColor(this.railRootId === root.id ? this.tok().surface2 : Color.Transparent)
          .border({
            width: this.railRootId === root.id ? this.tok().borderW : 2,
            color: this.railRootId === root.id
              ? (this.isCyber() ? this.tok().accent : this.tok().line2)
              : Color.Transparent
          })
          .onClick(() => {
            this.railRootId = root.id;
          })
        }, (root: CategoryNode) => root.id)
      }
      .width('100%')

      // 右侧：当前一级下的二级分类（split 头 + 列表）
      Column({ space: 8 }) {
        Row({ space: 10 }) {
          Text(this.railRootName() !== '' ? `${this.railRootName()} · 分类` : '分类')
            .fontSize(10.5)
            .fontFamily(fontMonoOf())
            .fontColor(this.tok().ink3)
            .layoutWeight(1)
          Text('新增分类')
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.openCatCreateChild();
            })
          Text('编辑类别')
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              const root = this.railRoot();
              if (root !== null) {
                this.openCatEdit(root);
              }
            })
          Text('删除')
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              const root = this.railRoot();
              if (root !== null) {
                this.removeCat(root);
              }
            })
        }
        .width('100%')

        if (this.railChildren().length === 0) {
          this.emptyState($r('sys.symbol.label'), '这个一级分类下还没有二级分类')
        } else {
          ForEach(this.railChildren(), (kid: CategoryNode) => {
            Row({ space: 8 }) {
              // 二级分类的**颜色跟随一级**（Web PCatIcon 的 colorName = 父分类名），
              // 图标本身仍按二级自己的名字解析
              CatIconView({
                catName: kid.name,
                iconSize: 26,
                color: this.parentColor()
              })
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(kid.name)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.tok().ink)
                    .maxLines(1)
                  if (!kid.isEnabled) {
                    this.tag('已停用', 'warn')
                  }
                }
                Text(`${kid.expenseCount} 笔引用`)
                  .fontSize(10.5)
                  .fontColor(this.tok().ink3)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Stack() {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(14)
                  .fontColor([this.tok().ink2])
              }
              .width(34)
              .height(34)
              .borderRadius(this.isCyber() ? 1 : 17)
              .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
              .border({
                width: this.tok().borderW,
                color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line
              })
              .onClick(() => {
                this.openCatEdit(kid);
              })
              Stack() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(14)
                  .fontColor([this.tok().ink2])
              }
              .width(34)
              .height(34)
              .borderRadius(this.isCyber() ? 1 : 17)
              .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
              .border({
                width: this.tok().borderW,
                color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line
              })
              .onClick(() => {
                this.removeCat(kid);
              })
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .borderRadius(this.isCyber() ? 1 : 10)
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
            .border({ width: 1, color: this.tok().line })
          }, (kid: CategoryNode) => kid.id)
        }

        Text('分类与支付方式均为软删除：已有流水引用时拒绝删除，只能停用。')
          .fontSize(11)
          .fontColor(this.tok().ink3)
          .lineHeight(18)
          .width('100%')
          .margin({ top: 2 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** rail 一级分类名（builder 内避免可空链） */
  private railRootName(): string {
    const root = this.railRoot();
    return root === null ? '' : root.name;
  }

  /** 支付方式卡（web set-row） */
  @Builder
  payCard() {
    Column() {
      Row({ space: 10 }) {
        this.orb(this.tok().sky, $r('sys.symbol.creditcard'))
        Text('支付方式')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
        Text('新增')
          .fontSize(this.isCyber() ? 10 : 11.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
          .padding({ left: 11, right: 11, top: 4, bottom: 4 })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .border({
            width: this.tok().borderW,
            color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
          })
          .onClick(() => {
            this.openPayCreate();
          })
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.payments.length === 0) {
        this.emptyState($r('sys.symbol.wallet'), '还没有支付方式')
      } else {
        ForEach(this.payments, (p: PaymentMethodItem, idx: number) => {
          Row({ space: 12 }) {
            Stack() {
              PayIconView({
                payName: p.name,
                payIcon: p.icon,
                iconSize: 18,
                colorOverride: ''
              })
            }
            .width(32)
            .height(32)
            .borderRadius(this.isCyber() ? 1 : 9)
            .backgroundColor(this.tok().surface2)
            .border({ width: 1, color: this.tok().line })

            Column({ space: 2 }) {
              Text(p.name)
                .fontSize(12.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tok().ink)
                .maxLines(1)
              if (p.type === 'credit') {
                Text(`${p.billingDay ?? 1} 日账单 · ${p.repaymentDay ?? 20} 日还款`)
                  .fontSize(10.5)
                  .fontColor(this.tok().ink3)
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text('合并')
              .fontSize(11.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.tok().ink2)
              .onClick(() => {
                this.openMerge(p);
              })
            Stack() {
              SymbolGlyph($r('sys.symbol.square_and_pencil'))
                .fontSize(14)
                .fontColor([this.tok().ink2])
            }
            .width(34)
            .height(34)
            .borderRadius(this.isCyber() ? 1 : 17)
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
            .border({
              width: this.tok().borderW,
              color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line
            })
            .onClick(() => {
              this.openPayEdit(p);
            })
            Stack() {
              SymbolGlyph($r('sys.symbol.trash'))
                .fontSize(14)
                .fontColor([this.tok().ink2])
            }
            .width(34)
            .height(34)
            .borderRadius(this.isCyber() ? 1 : 17)
            .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
            .border({
              width: this.tok().borderW,
              color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line
            })
            .onClick(() => {
              this.removePay(p);
            })
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .border(idx < this.payments.length - 1
            ? { width: { bottom: 1 }, color: this.tok().line }
            : { width: 0 })
        }, (p: PaymentMethodItem) => p.id)
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

  // ── 计划区 ──────────────────────────────────────────────────────────────
  /** 还款计划卡 */
  @Builder
  plansCard() {
    Column() {
      Row({ space: 10 }) {
        Text('还款计划')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
        Text(`进行中 ${this.activePlansCount()} · 已结束 ${this.endedPlansCount()}`)
          .fontSize(9.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
        Text('新建计划')
          .fontSize(this.isCyber() ? 10 : 11.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
          .padding({ left: 11, right: 11, top: 4, bottom: 4 })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .border({
            width: this.tok().borderW,
            color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
          })
          .onClick(() => {
            this.openPlanSheet();
          })
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.plans.length === 0) {
        this.emptyState($r('sys.symbol.calendar'), '还没有计划')
      } else {
        ForEach(this.plans, (p: PlanItem, idx: number) => {
          Row({ space: 12 }) {
            Stack() {
              CatIconView({
                catName: p.categoryName !== undefined ? p.categoryName : p.name,
                iconSize: 18,
                color: categoryColorOf(p.categoryName !== undefined ? p.categoryName : p.name, '')
              })
            }
            .width(26)
            .height(26)
            .borderRadius(this.isCyber() ? 1 : 9)
            .backgroundColor(Color.Transparent)

            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(p.name)
                  .fontSize(12.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.tok().ink)
                  .maxLines(1)
                if (p.state !== 'active') {
                  this.tag('已结束', 'dash')
                } else if (p.autoPost) {
                  this.tag('自动', 'accent')
                }
              }
              Text(this.planSeqText(p))
                .fontSize(10.5)
                .fontColor(this.tok().ink3)
              // 进度刻度：最多 12 段（360 期逐期画只会变一片灰点）
              Row({ space: 2 }) {
                ForEach(this.planTicks(p), (filled: boolean, tIdx: number) => {
                  Row()
                    .layoutWeight(1)
                    .height(4)
                    .borderRadius(2)
                    .backgroundColor(filled ? this.tok().accent : this.tok().surface3)
                }, (filled: boolean, tIdx: number) => `${p.id}-${tIdx}`)
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // more-menu：危险动作（终止/删除）收进「更多」
            Text('更多')
              .fontSize(11)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
              .border({ width: 1, color: this.tok().line })
              .bindMenu([
                {
                  value: p.state === 'active' ? '终止计划' : '已结束',
                  action: () => {
                    if (p.state === 'active') {
                      this.endPlan(p);
                    }
                  }
                },
                {
                  value: '删除计划',
                  action: () => {
                    this.removePlan(p);
                  }
                }
              ])
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .padding({ top: 11, bottom: 11 })
          .border(idx < this.plans.length - 1
            ? { width: { bottom: 1 }, color: this.tok().line }
            : { width: 0 })
        }, (p: PlanItem) => p.id)
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

  /** 期次文案（web planSeq） */
  private planSeqText(p: PlanItem): string {
    const total = this.planTotal(p);
    const seq = total > 0 ? `${p.progress.paidCount}/${total} 期` : '—';
    const next = p.progress.nextDueDate !== null ? ` · 下次 ${formatMonthDay(p.progress.nextDueDate)}` : '';
    return `${seq} · 每期 ${formatYuan(p.amountCents)}${next}`;
  }

  /** 12 段进度刻度 */
  private planTicks(p: PlanItem): boolean[] {
    const total = Math.max(1, this.planTotal(p));
    const done = Math.round((p.progress.paidCount / total) * 12);
    const out: boolean[] = [];
    for (let i = 0; i < 12; i++) {
      out.push(i < done);
    }
    return out;
  }

  /** 已处理 / 已忽略卡 */
  @Builder
  doneCard() {
    Column() {
      Row({ space: 10 }) {
        Text('已处理 / 已忽略')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
        Text(`${this.doneTodos.length} 条`)
          .fontSize(9.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      ForEach(this.doneTodos, (t: PlanTodoItem, idx: number) => {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(`${t.planName} · ${t.periodSeq} 期`)
                .fontSize(12.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tok().ink)
                .maxLines(1)
              this.tag(t.status === 'skipped' ? '已忽略' : '已入账', t.status === 'skipped' ? 'dash' : 'accent')
            }
            Text(`${t.repaymentDate} · ${formatYuan(t.amountCents)}`)
              .fontSize(10.5)
              .fontColor(this.tok().ink3)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(t.status === 'skipped' ? '恢复' : '撤销')
            .fontSize(11.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.tok().ink2)
            .onClick(() => {
              this.restoreOrRevert(t);
            })
        }
        .width('100%')
        .padding({ top: 11, bottom: 11 })
        .border(idx < this.doneTodos.length - 1
          ? { width: { bottom: 1 }, color: this.tok().line }
          : { width: 0 })
      }, (t: PlanTodoItem) => `done-${t.id}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 待处理期次卡 */
  @Builder
  dueCard() {
    Column() {
      Row({ space: 10 }) {
        Text('待处理期次')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
        Text(`${this.todos.length} 笔`)
          .fontSize(9.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
      }
      .width('100%')
      .margin({ bottom: 13 })

      if (this.todos.length === 0) {
        this.emptyState($r('sys.symbol.checkmark'), '没有待处理的期次')
      } else {
        ForEach(this.todos, (t: PlanTodoItem, idx: number) => {
          Row({ space: 12 }) {
            Row()
              .width(4)
              .height(24)
              .borderRadius(2)
              .backgroundColor(urgencyColorOf(t.repaymentDate, this.tok()))

            Column({ space: 2 }) {
              Text(`${t.periodSeq}期 · ${t.planName}`)
                .fontSize(12.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tok().ink)
                .maxLines(1)
              Text(`${formatMonthDay(t.repaymentDate)} · ${formatYuan(t.amountCents)}`)
                .fontSize(10.5)
                .fontColor(this.tok().ink3)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text(t.willAutoPost ? '确认' : '入账')
              .fontSize(11.5)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isCyber() ? '#04170d' : this.tok().accentInk)
              .padding({ left: 11, right: 11, top: 4, bottom: 4 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
              .backgroundColor(this.tok().accent)
              .onClick(() => {
                this.actTodo(t);
              })

            // more-menu：跳过不可逆，收进「更多」
            Text('更多')
              .fontSize(11)
              .fontFamily(fontMonoOf())
              .fontColor(this.tok().ink3)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
              .border({ width: 1, color: this.tok().line })
              .bindMenu([
                {
                  value: '忽略本期',
                  action: () => {
                    this.skipTodo(t);
                  }
                }
              ])
          }
          .width('100%')
          .padding({ top: 11, bottom: 11 })
          .border(idx < this.todos.length - 1
            ? { width: { bottom: 1 }, color: this.tok().line }
            : { width: 0 })
        }, (t: PlanTodoItem) => t.id)
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

  // ── 设备区 ──────────────────────────────────────────────────────────────

  /** 主题选项（紧凑版：一排三个 pill，替代原来 56px 大预览的 theme-card） */
  @Builder
  themeChip(value: string, label: string) {
    Text(label)
      .fontSize(this.isCyber() ? 10.5 : 12)
      .fontWeight(FontWeight.Bold)
      .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
      .letterSpacing(this.isCyber() ? 0.8 : 0)
      .maxLines(1)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 9, bottom: 9 })
      .fontColor(this.themeMode === value
        ? (this.isCyber() ? this.tok().accent : this.tok().accentInk)
        : this.tok().ink2)
      .backgroundColor(this.themeMode === value
        ? (this.isCyber() ? 'rgba(0,255,136,0.1)' : this.tok().accent)
        : this.tok().surface2)
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
      .border({
        width: this.tok().borderW,
        color: this.themeMode === value ? this.tok().accent : this.tok().line
      })
      .onClick(() => {
        this.switchTheme(value);
      })
  }

  /** 主题卡（web theme-cards--3：移动端单列，56px 预览 + 标签 + 描述） */
  @Builder
  themeCard() {
    Column() {
      Row({ space: 10 }) {
        Text('主题')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 13 })

      // 主题收敛成三个横排选项（用户裁决：不要大预览块），一排占满宽度
      Row({ space: 8 }) {
        this.themeChip('light', '水果硬糖')
        this.themeChip('dark', '赛博朋克')
        this.themeChip('system', '跟随系统')
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





  /** 修改口令卡（web「我的账号」口令部分） */
  @Builder
  passwordCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('修改密码')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
      }
      .width('100%')

      Column({ space: 6 }) {
        Text('当前口令')
          .fontSize(9.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
        TextInput({ text: this.pwdCurrent, placeholder: '••••••' })
          .type(InputType.Password)
          .height(40)
          .fontSize(13)
          .fontColor(this.tok().ink)
          .backgroundColor(fieldBgOf(this.tok().surface, this.tok().surface2, this.isCyber()))
          .border({ width: fieldBorderWOf(this.tok().borderW, this.isCyber()), color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .onChange((v: string) => {
            this.pwdCurrent = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('新口令（至少 8 位）')
          .fontSize(9.5)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
        TextInput({ text: this.pwdNew, placeholder: '至少 8 位' })
          .type(InputType.Password)
          .height(40)
          .fontSize(13)
          .fontColor(this.tok().ink)
          .backgroundColor(fieldBgOf(this.tok().surface, this.tok().surface2, this.isCyber()))
          .border({ width: fieldBorderWOf(this.tok().borderW, this.isCyber()), color: outlineStrongOf(this.isCyber()) })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
          .onChange((v: string) => {
            this.pwdNew = v;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Text('修改口令')
        .fontSize(this.isCyber() ? 10 : 11.5)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .fontColor(this.isCyber() ? '#04170d' : this.tok().accentInk)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
        .backgroundColor(this.tok().accent)
        .onClick(() => {
          this.changePassword();
        })

      Text('改口令后其他设备会被退出登录。')
        .fontSize(11)
        .fontColor(this.tok().ink3)
        .lineHeight(18)
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

  /**
   * 服务器（多地址）：登录页的 R98 三槽在这里也能改。
   * 之前只有登录页能改地址，而登录页仅在未登录时加载、「退出登录」又没做，
   * 等于登录后**永远换不了服务器**。
   */
  @Builder
  serverCard() {
    Column() {
      Row({ space: 10 }) {
        Text('服务器')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 13 })

      // 用户自己添加的候选（第一条优先级最高）；没有就显示空态引导
      if (this.srvList.length === 0) {
        Text('还没有服务器，点下面「添加服务器」')
          .fontSize(11)
          .fontColor(this.tok().ink3)
          .width('100%')
          .margin({ bottom: 8 })
      } else {
        ForEach(this.srvList, (url: string, i: number) => {
          this.serverSlot({ index: i, value: url, state: i < this.srvProbe.length ? this.srvProbe[i] : '' })
        }, (url: string, i: number) => `srv-${i}-${url}`)
      }

      Row({ space: 8 }) {
        Text('+ 添加服务器')
          .fontSize(11)
          .fontColor(this.tok().accent)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .border({ width: 1, color: this.tok().accent })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .onClick(() => {
            this.addServer();
          })
        Blank()
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row({ space: 8 }) {
        Text(this.srvMsg)
          .fontSize(10)
          .fontFamily(fontMonoOf())
          .fontColor(this.tok().ink3)
          .layoutWeight(1)
        Button('测试')
          .fontSize(11)
          .height(30)
          .backgroundColor(this.tok().surface2)
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.testServers();
          })
        Button('保存')
          .fontSize(11)
          .height(30)
          .backgroundColor(this.tok().accent)
          .fontColor(this.tok().accentInk)
          .onClick(() => {
            this.saveServers();
          })
      }
      .width('100%')
      .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(this.tok().surface)
    .borderRadius(radiusOf(this.tok(), this.isCyber(), 16))
    .border({ width: this.tok().borderW, color: this.tok().line })
    .shadow(cardShadow(this.tok(), this.isCyber()) as ShadowOptions)
  }

  /** 检查更新卡 */
  @Builder
  updateCard() {
    Column() {
      Row({ space: 10 }) {
        Text('检查更新')
          .fontSize(this.isCyber() ? 12.5 : 15)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .letterSpacing(this.isCyber() ? 1.25 : 0)
          .fontColor(this.tok().ink)
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 13 })

      Row({ space: 10 }) {
        Text(this.updateChecking ? '检查中…' : '检查更新')
          .fontSize(this.isCyber() ? 10 : 11.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .backgroundColor(this.isCyber() ? Color.Transparent : this.tok().surface)
          .border({
            width: this.tok().borderW,
            color: this.isCyber() ? 'rgba(0,255,136,0.55)' : this.tok().line2
          })
          .shadow(this.isCyber()
        ? { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions
        : parseShadow('3px 3px 0 #1E293B') as ShadowOptions)
          .onClick(() => {
            this.checkUpdate();
          })
        Text(this.updateMessage)
          .fontSize(10.5)
          .fontColor(this.tok().ink3)
          .layoutWeight(1)
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

  // ── 弹层 ────────────────────────────────────────────────────────────────
  /** 设置弹层（web PSheet 移动端：底部上滑 93dvh；bindSheet LARGE 近似） */
  @Builder
  settingsSheet() {
    Column() {
      // sheet-head
      Text(this.sheetTitle())
        .fontSize(this.isCyber() ? 13 : 15)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
        .fontColor(this.isCyber() ? this.tok().accent : this.tok().ink)
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 12 })
        .border({ width: { bottom: 1 }, color: this.tok().line })

      Scroll() {
        Column({ space: 12 }) {
          if (this.sheetKind === 'cat') {
            this.catForm()
          } else if (this.sheetKind === 'pay') {
            this.payForm()
          } else if (this.sheetKind === 'merge') {
            this.mergeForm()
          } else {
            this.planForm()
          }
          if (this.formError !== '') {
            Text(this.formError)
              .fontSize(10.5)
              .fontColor(this.tok().danger)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // sheet-foot
      Row({ space: 8 }) {
        Text(this.footPrimaryLabel())
          .fontSize(this.isCyber() ? 10 : 12.5)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.isCyber() ? fontMonoOf() : fontBodyOf(false))
          .fontColor(this.isCyber() ? '#04170d' : this.tok().accentInk)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
          .backgroundColor(this.tok().accent)
          .onClick(() => {
            this.runFootPrimary();
          })
        Text('取消')
          .fontSize(12.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.tok().ink2)
          .onClick(() => {
            this.sheetOpen = false;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 14 })
      .border({ width: { top: 1 }, color: this.tok().line })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tok().bg)
  }

  private footPrimaryLabel(): string {
    if (this.sheetKind === 'merge') {
      return '合并';
    }
    if (this.sheetKind === 'plan') {
      return '创建';
    }
    return '保存';
  }

  private runFootPrimary(): void {
    if (this.sheetKind === 'cat') {
      this.saveCat();
    } else if (this.sheetKind === 'pay') {
      this.savePay();
    } else if (this.sheetKind === 'merge') {
      this.runMerge();
    } else {
      this.savePlan();
    }
  }

  /** 表单字段标签（web .field-l） */
  @Builder
  fieldLabel(text: string) {
    Text(text)
      .fontSize(9.5)
      .fontFamily(fontMonoOf())
      .fontColor(this.tok().ink3)
      .width('100%')
  }

  /** 表单输入框（web .input） */
  @Builder
  fieldInput(text: string, placeholder: string, password: boolean, onChange: (v: string) => void) {
    TextInput({ text: text, placeholder: placeholder })
      .type(password ? InputType.Password : InputType.Normal)
      .height(40)
      .fontSize(13)
      .fontColor(this.tok().ink)
      // cyber 下输入框体要走 surface2，否则贴在 bg 上看不出边界（用户反馈可见性差）
      .backgroundColor(fieldBgOf(this.tok().surface, this.tok().surface2, this.isCyber()))
      .border({ width: fieldBorderWOf(this.tok().borderW, this.isCyber()), color: outlineStrongOf(this.isCyber()) })
      .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rMd))
      .onChange((v: string) => {
        onChange(v);
      })
      .width('100%')
  }

  /** 分类表单 */
  @Builder
  catForm() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        this.fieldLabel('名称')
        this.fieldInput(this.formName, '如：外卖', false, (v: string) => {
          this.formName = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('图标')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          Text('自动')
            .fontSize(11)
            .fontFamily(fontMonoOf())
            .fontColor(this.formIcon === '' ? this.tok().accent : this.tok().ink2)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({
              width: 1,
              color: this.formIcon === '' ? this.tok().accent : this.tok().line
            })
            .onClick(() => {
              this.formIcon = '';
            })
          ForEach(CAT_ICON_OPTIONS, (opt: CatIconOption) => {
            Stack() {
              SymbolGlyph(opt.res)
                .fontSize(17)
                .fontColor([this.formIcon === opt.name ? this.tok().accent : this.tok().ink2])
            }
            .width(38)
            .height(38)
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .backgroundColor(this.tok().surface)
            .border({
              width: this.formIcon === opt.name ? 2 : 1,
              color: this.formIcon === opt.name ? this.tok().accent : this.tok().line
            })
            .onClick(() => {
              this.formIcon = opt.name;
            })
          }, (opt: CatIconOption) => opt.name)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // 只有一级类别能选颜色；二级分类的颜色跟随一级
      if (this.editingRoot()) {
        Column({ space: 6 }) {
          this.fieldLabel('颜色')
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
            Text('自动')
              .fontSize(11)
              .fontFamily(fontMonoOf())
              .fontColor(this.formColor === '' ? this.tok().accent : this.tok().ink2)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
              .border({
                width: 1,
                color: this.formColor === '' ? this.tok().accent : this.tok().line
              })
              .onClick(() => {
                this.formColor = '';
              })
            ForEach(CATEGORY_COLORS, (hex: string, cIdx: number) => {
              Row()
                .width(26)
                .height(26)
                .borderRadius(radiusOf(this.tok(), this.isCyber(), 8))
                .backgroundColor(hex)
                .border({
                  width: this.formColor === `${cIdx + 1}` ? 2 : 0,
                  color: this.tok().ink
                })
                .onClick(() => {
                  this.formColor = `${cIdx + 1}`;
                })
            }, (hex: string, cIdx: number) => `color-${cIdx}`)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      // 二级分类可以移动到别的类别下（同深度平移）
      if (!this.editingRoot() && this.editingCategoryId !== '') {
        Column({ space: 6 }) {
          this.fieldLabel('归属类别')
          Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
            ForEach(this.categories, (root: CategoryNode) => {
              Text(root.name)
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.formParent === root.id ? this.tok().ink : this.tok().ink2)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                .backgroundColor(this.formParent === root.id ? '#FBBF24' : this.tok().surface)
                .border({
                  width: 2,
                  color: this.formParent === root.id ? this.tok().line2 : this.tok().line
                })
                .onClick(() => {
                  this.formParent = root.id;
                })
            }, (root: CategoryNode) => `parent-${root.id}`)
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 支付方式表单 */
  @Builder
  payForm() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        this.fieldLabel('名称')
        this.fieldInput(this.formName, '如：招商信用卡', false, (v: string) => {
          this.formName = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('图标')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          Text('自动')
            .fontSize(11)
            .fontFamily(fontMonoOf())
            .fontColor(this.formPayIcon === '' ? this.tok().accent : this.tok().ink2)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .border({
              width: 1,
              color: this.formPayIcon === '' ? this.tok().accent : this.tok().line
            })
            .onClick(() => {
              this.formPayIcon = '';
            })
          ForEach(PAY_OPTIONS, (opt: PayOption) => {
            Row({ space: 6 }) {
              PayIconView({
                payName: opt.label,
                payIcon: opt.id,
                iconSize: 18,
                colorOverride: ''
              })
              Text(opt.label)
                .fontSize(10.5)
                .fontColor(this.formPayIcon === opt.id ? this.tok().ink : this.tok().ink2)
                .maxLines(1)
            }
            .constraintSize({ minWidth: 84 })
            .padding({ left: 8, right: 8, top: 7, bottom: 7 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rSm))
            .backgroundColor(this.tok().surface)
            .border({
              width: 1,
              color: this.formPayIcon === opt.id ? this.tok().accent : this.tok().line
            })
            .shadow(this.formPayIcon === opt.id
              ? { radius: 4, offsetX: 0, offsetY: 0, color: `#38${this.tok().accent.substring(1)}` } as ShadowOptions
              : { radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions)
            .onClick(() => {
              this.formPayIcon = opt.id;
            })
          }, (opt: PayOption) => opt.id)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('类型')
        Row({ space: 8 }) {
          Text('信用卡（有账单/还款日）')
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.formType === 'credit' ? this.tok().ink : this.tok().ink2)
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .backgroundColor(this.formType === 'credit' ? '#FBBF24' : this.tok().surface)
            .border({
              width: 2,
              color: this.formType === 'credit' ? this.tok().line2 : this.tok().line
            })
            .onClick(() => {
              this.formType = 'credit';
            })
          Text('即时结算')
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.formType === 'cash' ? this.tok().ink : this.tok().ink2)
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
            .backgroundColor(this.formType === 'cash' ? '#FBBF24' : this.tok().surface)
            .border({
              width: 2,
              color: this.formType === 'cash' ? this.tok().line2 : this.tok().line
            })
            .onClick(() => {
              this.formType = 'cash';
            })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.formType === 'credit') {
        Column({ space: 6 }) {
          this.fieldLabel('账单日')
          this.fieldInput(this.formBillingDay, '1-31', false, (v: string) => {
            this.formBillingDay = v;
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column({ space: 6 }) {
          this.fieldLabel('还款日')
          this.fieldInput(this.formRepaymentDay, '1-31', false, (v: string) => {
            this.formRepaymentDay = v;
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 合并支付方式表单 */
  @Builder
  mergeForm() {
    Column({ space: 12 }) {
      Text(`把「${this.mergeFromName()}」下的全部流水转到另一个支付方式，然后停用「${this.mergeFromName()}」。这一步在服务端一个事务里完成，不会出现「转了一半」。`)
        .fontSize(11)
        .fontColor(this.tok().ink3)
        .lineHeight(18)
        .width('100%')

      Column({ space: 6 }) {
        this.fieldLabel('转到')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          ForEach(this.payments, (p: PaymentMethodItem) => {
            if (p.id !== this.mergeFromId) {
              Text(p.name)
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.mergeIntoId === p.id ? this.tok().ink : this.tok().ink2)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                .backgroundColor(this.mergeIntoId === p.id ? '#FBBF24' : this.tok().surface)
                .border({
                  width: 2,
                  color: this.mergeIntoId === p.id ? this.tok().line2 : this.tok().line
                })
                .onClick(() => {
                  this.mergeIntoId = p.id;
                })
            }
          }, (p: PaymentMethodItem) => `merge-${p.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 新建计划表单 */
  @Builder
  planForm() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        this.fieldLabel('名称')
        this.fieldInput(this.formName, '如：房贷', false, (v: string) => {
          this.formName = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('分类')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          ForEach(this.categories, (root: CategoryNode) => {
            Text(root.name)
              .fontSize(11.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.formCategoryId === root.id ? this.tok().ink : this.tok().ink2)
              .padding({ left: 11, right: 11, top: 5, bottom: 5 })
              .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
              .backgroundColor(this.formCategoryId === root.id ? '#FBBF24' : this.tok().surface)
              .border({
                width: 2,
                color: this.formCategoryId === root.id ? this.tok().line2 : this.tok().line
              })
              .onClick(() => {
                this.formCategoryId = root.id;
              })
          }, (root: CategoryNode) => `plan-cat-${root.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('支付方式')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.px(6), cross: LengthMetrics.px(6) } }) {
          ForEach(this.payments, (p: PaymentMethodItem) => {
            if (p.isEnabled) {
              Text(p.name)
                .fontSize(11.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.formPaymentId === p.id ? this.tok().ink : this.tok().ink2)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .borderRadius(radiusOf(this.tok(), this.isCyber(), this.tok().rPill))
                .backgroundColor(this.formPaymentId === p.id ? '#FBBF24' : this.tok().surface)
                .border({
                  width: 2,
                  color: this.formPaymentId === p.id ? this.tok().line2 : this.tok().line
                })
                .onClick(() => {
                  this.formPaymentId = p.id;
                })
            }
          }, (p: PaymentMethodItem) => `plan-pay-${p.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('每期金额')
        this.fieldInput(this.formAmount, '1000.00', false, (v: string) => {
          this.formAmount = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('期数')
        this.fieldInput(this.formPeriods, '12', false, (v: string) => {
          this.formPeriods = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        this.fieldLabel('首期还款日')
        this.fieldInput(this.formFirstDue, todayKey(), false, (v: string) => {
          this.formFirstDue = v;
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text('到期自动入账')
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tok().ink)
          Text('关闭则每期需要手动点「入账」')
            .fontSize(10.5)
            .fontColor(this.tok().ink3)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.formAutoPost })
          .width(42)
          .height(24)
          .selectedColor(this.tok().accent)
          .onChange((v: boolean) => {
            this.formAutoPost = v;
          })
      }
      .width('100%')
      .padding({ top: 11, bottom: 11 })
      .border({ width: { bottom: 1 }, color: this.tok().line })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
