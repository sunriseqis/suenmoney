<script setup lang="ts">
/**
 * 记账抽屉 —— 记一笔 / 编辑已有的账。
 *
 * 全新紧凑移动端架构：
 * 1. 顶部：金额大字 + 收支切换；
 * 2. 中间：紧凑单行信息卡片（分类行、支付方式行、消费日期行、分期行、备注行）；
 * 3. 弹层解耦：分类与支付方式采用独立 Sheet 面板，选完即走，彻底移除横向滚动条；
 * 4. 底部：去除横向摘要滑块，紧凑状态条 + 固定数字键盘。
 */
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import {
  Calendar,
  ChevronRight,
  CreditCard,
  FileText,
} from '@lucide/vue';

import {
  ApiError,
  expenses as expensesApi,
  plans as plansApi,
  reports as reportsApi,
  type Category,
  type Expense,
  type PaymentMethod,
} from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import CategoryPickerSheet from '@/components/CategoryPickerSheet.vue';
import ChipButton from '@/components/ChipButton.vue';
import NumericKeypad from '@/components/NumericKeypad.vue';
import PaymentIcon from '@/components/PaymentIcon.vue';
import PaymentMethodPickerSheet from '@/components/PaymentMethodPickerSheet.vue';
import type { KeypadKey } from '@/components/keypad';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useSyncStore } from '@/stores/sync';
import { BEFORE_BACK_EVENT } from '@/platform';
import { currentMonth, formatMonthDay, formatMonthLabel, todayLocal } from '@/utils/dates';
import { clearDraft, isDraftMeaningful, readDraft, writeDraft } from '@/utils/draft';
import {
  centsToInput,
  formatCents,
  formatCompact,
  formatYuan,
  parseYuanToCents,
  splitInstallment,
} from '@/utils/money';

const props = withDefaults(
  defineProps<{
    open: boolean;
    expense?: Expense | null;
  }>(),
  { expense: null },
);

const emit = defineEmits<{ close: []; saved: [] }>();

const dict = useDictionariesStore();
const plansStore = usePlansStore();
const syncStore = useSyncStore();

// 弹层控制
const categoryPickerOpen = ref(false);
const paymentPickerOpen = ref(false);

/** 已用「＋」确认过的金额（分） */
const parts = ref<number[]>([]);
/** 当前正在输入的「元」文本 */
const input = ref('');
/** 退款 / 冲销 */
const isRefund = ref(false);

const categoryId = ref<string | null>(null);
const paymentMethodId = ref<string | null>(null);
const spendDate = ref(todayLocal());
const note = ref('');

/**
 * 备注输入框是否聚焦。
 * 移动端聚焦时折叠自制数字键盘（原生软键盘必然弹起，两键盘并存会把输入框
 * 和金额顶出可视区），并把「保存」临时挂到原生键盘上方的辅助条里。
 */
const noteFocused = ref(false);

const saving = ref(false);
const errorMessage = ref<string | null>(null);
const confirmingDelete = ref(false);

const partsTotal = computed(() => parts.value.reduce((sum, item) => sum + item, 0));
const inputCents = computed(() => parseYuanToCents(input.value));
const totalCents = computed(() => partsTotal.value + inputCents.value);
const canSave = computed(() => totalCents.value > 0);

/** 计划生成的记录只允许改备注 */
const coreEditable = computed(() => props.expense === null || props.expense.source === 'manual');

/** 当前选中的分类对象及面包屑展示名 */
const selectedCategory = computed(() => dict.findCategory(categoryId.value));
const categoryLabel = computed(() => {
  const cat = selectedCategory.value;
  if (!cat) return '选择分类';
  if (cat.parentId) {
    const parent = dict.findCategory(cat.parentId);
    return parent ? `${parent.name} · ${cat.name}` : cat.name;
  }
  return cat.name;
});

/** 当前选中的支付方式对象及展示名 */
const selectedPaymentMethod = computed(() => dict.findPaymentMethod(paymentMethodId.value));
const paymentLabel = computed(() => {
  return selectedPaymentMethod.value?.name ?? '选择支付方式';
});

/** 是否为信用卡类型 */
const isCreditCard = computed(() => selectedPaymentMethod.value?.type === 'credit');

/** 仅当支付方式为信用卡类型、可核心编辑、且非退款时才允许分期（记账和修改共用） */
const canInstallment = computed(
  () => coreEditable.value && isCreditCard.value && !isRefund.value,
);

// 分期相关状态（仅信用卡非退款有效）
const isInstallment = ref(false);
const installmentPeriods = ref(12);
const customPeriods = ref(false);
const customPeriodsInput = ref('');

function selectPeriods(p: number): void {
  installmentPeriods.value = p;
  customPeriods.value = false;
}

function enableCustomPeriods(): void {
  customPeriods.value = true;
  if (!customPeriodsInput.value) {
    customPeriodsInput.value = String(installmentPeriods.value || 12);
  }
}

watch(canInstallment, (can) => {
  if (!can) isInstallment.value = false;
});

const effectivePeriods = computed(() => {
  if (customPeriods.value) {
    const val = parseInt(customPeriodsInput.value, 10);
    return Number.isFinite(val) && val >= 2 && val <= 600 ? val : 12;
  }
  return installmentPeriods.value;
});

const installmentAmounts = computed(() => {
  if (!canInstallment.value || !isInstallment.value || totalCents.value <= 0) return [];
  return splitInstallment(totalCents.value, effectivePeriods.value);
});

const perPeriodCents = computed(() => installmentAmounts.value[0] ?? 0);
const installmentPerPeriodText = computed(() => formatYuan(perPeriodCents.value));

const desktopAmountInputRef = ref<HTMLInputElement | null>(null);

function handleDesktopAmountInput(e: Event): void {
  const target = e.target as HTMLInputElement;
  let val = target.value.replace(/[^\d.]/g, '');
  const dots = val.split('.');
  if (dots.length > 2) {
    val = `${dots[0]}.${dots.slice(1).join('')}`;
  }
  if (dots[1] && dots[1].length > 2) {
    val = `${dots[0]}.${dots[1].slice(0, 2)}`;
  }
  input.value = val;
}

const saveLabel = computed(() => {
  if (canInstallment.value && isInstallment.value) {
    return props.expense === null ? '创建分期' : '转为分期';
  }
  return props.expense === null ? '保存' : '更新';
});

/** 账单日与还款日服务端预览（预览，不落库） */
const previewDates = ref<{ postingDate: string; repaymentDate: string } | null>(null);

async function refreshPreview(): Promise<void> {
  if (!coreEditable.value || paymentMethodId.value === null) {
    previewDates.value = null;
    return;
  }

  try {
    previewDates.value = await expensesApi.preview({
      spendDate: spendDate.value,
      paymentMethodId: paymentMethodId.value,
    });
  } catch {
    previewDates.value = null;
  }
}

/** 键盘上方常驻的「本月已支出」 */
const monthSpentCents = ref<number | null>(null);

/** 常用度统计（本地记录 + 当月服务端统计） */
const USAGE_COUNTS_KEY = 'suenmoney:usage-counts';

interface UsageCounts {
  categories: Record<string, number>;
  paymentMethods: Record<string, number>;
}

function getStoredUsageCounts(): UsageCounts {
  try {
    const raw = localStorage.getItem(USAGE_COUNTS_KEY);
    if (!raw) return { categories: {}, paymentMethods: {} };
    const parsed = JSON.parse(raw) as Partial<UsageCounts>;
    return {
      categories:
        parsed.categories && typeof parsed.categories === 'object' ? parsed.categories : {},
      paymentMethods:
        parsed.paymentMethods && typeof parsed.paymentMethods === 'object'
          ? parsed.paymentMethods
          : {},
    };
  } catch {
    return { categories: {}, paymentMethods: {} };
  }
}

const usageCounts = ref<UsageCounts>(getStoredUsageCounts());
const serverUsageCounts = ref<{
  categories: Record<string, number>;
  paymentMethods: Record<string, number>;
}>({ categories: {}, paymentMethods: {} });

function recordUsage(catId: string | null, methodId: string | null): void {
  if (!catId && !methodId) return;
  try {
    const counts = getStoredUsageCounts();
    if (catId) counts.categories[catId] = (counts.categories[catId] ?? 0) + 1;
    if (methodId) counts.paymentMethods[methodId] = (counts.paymentMethods[methodId] ?? 0) + 1;
    localStorage.setItem(USAGE_COUNTS_KEY, JSON.stringify(counts));
    usageCounts.value = counts;
  } catch {
    // 忽略写入失败
  }
}

async function refreshMonthSpent(): Promise<void> {
  try {
    const reportData = (await reportsApi.monthly(currentMonth())).report;
    monthSpentCents.value = reportData.totalCents;

    const catCounts: Record<string, number> = {};
    for (const cat of reportData.categories) {
      if (cat.children && cat.children.length > 0) {
        for (const child of cat.children) {
          catCounts[child.categoryId] = (catCounts[child.categoryId] ?? 0) + child.count;
        }
      } else {
        catCounts[cat.categoryId] = (catCounts[cat.categoryId] ?? 0) + cat.count;
      }
    }

    const pmCounts: Record<string, number> = {};
    for (const pm of reportData.paymentMethods ?? []) {
      pmCounts[pm.paymentMethodId] = (pmCounts[pm.paymentMethodId] ?? 0) + pm.count;
    }

    serverUsageCounts.value = { categories: catCounts, paymentMethods: pmCounts };
  } catch {
    monthSpentCents.value = null;
  }
}

/** 所有可选的叶子分类（按一级分类原顺序展开） */
const allSelectableCategories = computed<Category[]>(() => {
  const list: Category[] = [];
  for (const root of dict.rootCategories) {
    for (const child of dict.selectableChildren(root)) {
      list.push(child);
    }
  }
  return list;
});

/** 快捷方式第一行：最常用的几个分类（展示开头两个字符） */
const quickCategories = computed<Category[]>(() => {
  const scored = allSelectableCategories.value.map((cat, originalIndex) => {
    const localScore = usageCounts.value.categories[cat.id] ?? 0;
    const serverScore = serverUsageCounts.value.categories[cat.id] ?? 0;
    const totalScore = localScore * 5 + serverScore;
    return { cat, totalScore, originalIndex };
  });

  scored.sort((a, b) => {
    if (b.totalScore !== a.totalScore) {
      return b.totalScore - a.totalScore;
    }
    return a.originalIndex - b.originalIndex;
  });

  return scored.slice(0, 6).map((item) => item.cat);
});

interface PaymentSlot {
  key: string;
  type: 'method' | 'more' | 'empty';
  label: string;
  title: string;
  rowSpan?: number;
  method?: PaymentMethod;
}

/** 智能精炼支付方式展示名称（避免「支付宝」截成「支付」，统一为 2~3 个自然字） */
function getShortPaymentName(name: string): string {
  if (name.startsWith('支付宝')) return '支付宝';
  if (name.startsWith('微信')) return '微信';
  if (name.includes('招商')) return '招商';
  if (name.includes('工行') || name.includes('工商')) return '工行';
  if (name.includes('建行') || name.includes('建设')) return '建行';
  if (name.includes('农行') || name.includes('农业')) return '农行';
  if (name.includes('中行') || name.includes('中国银行')) return '中行';
  if (name.includes('广发')) return '广发';
  if (name.includes('中信')) return '中信';
  if (name.includes('交通')) return '交行';
  if (name.includes('浦发')) return '浦发';
  if (name.includes('民生')) return '民生';
  if (name.includes('兴业')) return '兴业';
  if (name.includes('光大')) return '光大';
  if (name.includes('平安')) return '平安';
  if (name.includes('京东')) return '京东';
  if (name.includes('美团')) return '美团';
  if (name.includes('花呗')) return '花呗';
  if (name.includes('白条')) return '白条';
  if (name.includes('现金')) return '现金';
  return name.length <= 3 ? name : name.slice(0, 2);
}

/** 键盘左侧第 1 列：常用支付方式（高度与右侧数字键 1:1 对齐） */
const leftPaymentSlots = computed<PaymentSlot[]>(() => {
  const allUsable = dict.usablePaymentMethods;
  const scored = allUsable.map((pm, originalIndex) => {
    const localScore = usageCounts.value.paymentMethods[pm.id] ?? 0;
    const serverScore = serverUsageCounts.value.paymentMethods[pm.id] ?? 0;
    const totalScore = localScore * 5 + serverScore;
    return { pm, totalScore, originalIndex };
  });

  scored.sort((a, b) => {
    if (b.totalScore !== a.totalScore) {
      return b.totalScore - a.totalScore;
    }
    return a.originalIndex - b.originalIndex;
  });

  const topMethods = scored.map((item) => item.pm);

  // 若当前已选支付方式不在 Top 4 内，替换至第 4 位保证始终可见高亮
  const activeMethod = dict.findPaymentMethod(paymentMethodId.value);
  let pickedMethods: PaymentMethod[] = [];

  if (topMethods.length <= 4) {
    pickedMethods = [...topMethods];
  } else {
    const inTop4 = topMethods.slice(0, 4).some((pm) => pm.id === paymentMethodId.value);
    if (inTop4 || !activeMethod || !activeMethod.isEnabled) {
      pickedMethods = topMethods.slice(0, 4);
    } else {
      pickedMethods = [...topMethods.slice(0, 3), activeMethod];
    }
  }

  // 场景 A：刚好仅有 2 个支付方式，平分 4 行（各占 2 行大触控区）
  if (pickedMethods.length === 2 && allUsable.length === 2) {
    return pickedMethods.map((pm) => ({
      key: pm.id,
      type: 'method',
      label: getShortPaymentName(pm.name),
      title: pm.name,
      rowSpan: 2,
      method: pm,
    }));
  }

  // 场景 B：仅有 1 个支付方式，独占 4 行
  const onlyOne = pickedMethods[0];
  if (pickedMethods.length === 1 && allUsable.length === 1 && onlyOne) {
    return [
      {
        key: onlyOne.id,
        type: 'method',
        label: getShortPaymentName(onlyOne.name),
        title: onlyOne.name,
        rowSpan: 4,
        method: onlyOne,
      },
    ];
  }

  // 场景 C：3 个或更多
  const slots: PaymentSlot[] = [];
  for (const pm of pickedMethods) {
    slots.push({
      key: pm.id,
      type: 'method',
      label: getShortPaymentName(pm.name),
      title: pm.name,
      method: pm,
    });
  }

  // 若不足 4 个且系统还有其他支付方式，补充「更多」入口
  if (slots.length < 4 && allUsable.length > slots.length) {
    slots.push({
      key: '__more__',
      type: 'more',
      label: '更多',
      title: '选择其他支付方式',
    });
  }

  // 占位补齐至 4 个确保 Grid 绝对稳固
  while (slots.length < 4) {
    slots.push({
      key: `__empty_${slots.length}__`,
      type: 'empty',
      label: '',
      title: '',
    });
  }

  return slots;
});

function handleLeftSlotClick(slot: PaymentSlot): void {
  if (slot.type === 'method' && slot.method) {
    paymentMethodId.value = slot.method.id;
  } else if (slot.type === 'more') {
    paymentPickerOpen.value = true;
  }
}

/** 这笔支出落在哪个月的提示 */
const landingHint = computed(() => {
  const dates = previewDates.value;
  if (dates === null) return null;

  const repaymentMonth = dates.repaymentDate.slice(0, 7);
  const sameMonth = repaymentMonth === spendDate.value.slice(0, 7);

  return sameMonth
    ? { shifted: false, text: `还款日 ${formatMonthDay(dates.repaymentDate)}` }
    : {
        shifted: true,
        text: `还款落入 ${formatMonthLabel(repaymentMonth)}（${formatMonthDay(dates.repaymentDate)} 到期）`,
      };
});

/** 上次选择的分类与支付方式记忆 */
const LAST_CHOICE_KEY = 'suenmoney:last-choice';

interface LastChoice {
  categoryId: string;
  paymentMethodId: string;
}

function readLastChoice(): LastChoice | null {
  try {
    const raw = localStorage.getItem(LAST_CHOICE_KEY);
    if (raw === null) return null;
    const parsed = JSON.parse(raw) as Partial<LastChoice>;
    if (typeof parsed.categoryId !== 'string' || typeof parsed.paymentMethodId !== 'string') {
      return null;
    }
    return { categoryId: parsed.categoryId, paymentMethodId: parsed.paymentMethodId };
  } catch {
    return null;
  }
}

function writeLastChoice(choice: LastChoice): void {
  try {
    localStorage.setItem(LAST_CHOICE_KEY, JSON.stringify(choice));
  } catch {
    // 忽略写入失败
  }
}

function applyDefaultChoice(): void {
  const root = dict.rootCategories[0] ?? null;
  categoryId.value = root === null ? null : (dict.selectableChildren(root)[0]?.id ?? null);
}

function resetForm(): void {
  parts.value = [];
  input.value = '';
  isRefund.value = false;
  isInstallment.value = false;
  installmentPeriods.value = 12;
  customPeriods.value = false;
  customPeriodsInput.value = '';
  note.value = '';
  spendDate.value = todayLocal();
  confirmingDelete.value = false;

  const last = readLastChoice();
  const remembered = last === null ? null : dict.findCategory(last.categoryId);
  const usable = remembered !== null && remembered.isEnabled ? remembered : null;

  if (usable === null) {
    applyDefaultChoice();
  } else {
    categoryId.value = usable.id;
  }

  const rememberedMethod = last === null ? null : dict.findPaymentMethod(last.paymentMethodId);
  paymentMethodId.value =
    rememberedMethod !== null && rememberedMethod.isEnabled
      ? rememberedMethod.id
      : (dict.usablePaymentMethods[0]?.id ?? null);
}

function fillFrom(expense: Expense): void {
  parts.value = [];
  input.value = centsToInput(expense.amountCents);
  isRefund.value = expense.amountCents < 0;
  isInstallment.value = false;
  installmentPeriods.value = 12;
  customPeriods.value = false;
  customPeriodsInput.value = '';
  categoryId.value = expense.categoryId;
  paymentMethodId.value = expense.paymentMethodId;
  spendDate.value = expense.spendDate;
  note.value = expense.note;
  confirmingDelete.value = false;
}

// ---------------------------------------------------------------------------
// 草稿：切后台/进程被回收后不丢「记一半的账」
// ---------------------------------------------------------------------------

/**
 * 草稿分桶：`expense` 用途 + 上下文，**在打开面板那一刻定死**（不是 computed）。
 * - 新建 → `new:<账期>`：切到别的月再记是另一笔半成品，不该互相顶掉；
 * - 编辑 → `edit:<expenseId>`：编辑 A 笔时绝不能把编辑 B 笔的草稿恢复进来。
 *
 * 定死而不是跟着 spendDate 变：编辑中途改日期不该把草稿换到另一个 key 去，
 * 否则旧 key 留下一份「僵尸草稿」，下次同账期打开时凭空多问一次。
 */
const DRAFT_SCOPE = 'expense';

const draftContext = ref('');

/** 打开面板时检测到的可恢复草稿；非 null 时在表单上方给「恢复 / 丢弃」两个动作 */
const pendingDraft = ref<ExpenseDraft | null>(null);

/** 打开时的初始形态：用来判断「用户到底改没改」（没改就不该存草稿） */
let baselineCategoryId: string | null = null;
let baselinePaymentMethodId: string | null = null;

const DRAFT_DEBOUNCE_MS = 400;

interface ExpenseDraft {
  parts: number[];
  input: string;
  isRefund: boolean;
  categoryId: string | null;
  paymentMethodId: string | null;
  spendDate: string;
  note: string;
  /** 打开面板时的初始分类/支付方式：与它相同即视为「用户没动过这一项」 */
  baseCategoryId: string | null;
  basePaymentMethodId: string | null;
}

let draftTimer: ReturnType<typeof setTimeout> | undefined;

function currentDraft(): ExpenseDraft {
  return {
    parts: [...parts.value],
    input: input.value,
    isRefund: isRefund.value,
    categoryId: categoryId.value,
    paymentMethodId: paymentMethodId.value,
    spendDate: spendDate.value,
    note: note.value,
    baseCategoryId: baselineCategoryId,
    basePaymentMethodId: baselinePaymentMethodId,
  };
}

function isDraftMeaningfulDraft(draft: ExpenseDraft): boolean {
  return isDraftMeaningful({
    totalCents: draft.parts.reduce((sum, p) => sum + p, 0) + parseYuanToCents(draft.input),
    note: draft.note,
    categoryChanged: draft.categoryId !== draft.baseCategoryId,
    paymentMethodChanged: draft.paymentMethodId !== draft.basePaymentMethodId,
  });
}

/** 记一份防抖快照。没动过的表单不写 —— 否则每次打开记账都会留下一份空草稿。 */
function scheduleDraftWrite(): void {
  if (draftTimer !== undefined) clearTimeout(draftTimer);
  draftTimer = setTimeout(writeDraftNow, DRAFT_DEBOUNCE_MS);
}

/**
 * 立即落盘（防抖到期、或保存失败时同步补写一份，保证「草稿已保留」这句提示是真的）。
 *
 * 刻意**不检查 props.open**：防抖窗口里用户可能刚好把面板关了（保存成功的正常路径），
 * 那一刻草稿已经被 dropDraft 清过；反过来，切后台/关面板时正在防抖窗口内，
 * 定时器仍会在面板关闭后才触发 —— 此时内容还没提交，必须写下去，否则等于白做草稿。
 * 判据用 draftContext 是否为空：没打开过面板就没有可写的上下文。
 */
/**
 * 立即落盘（防抖到期、或保存失败时同步补写一份，保证「草稿已保留」这句提示是真的）。
 *
 * 刻意**不检查 props.open**：防抖窗口里用户可能刚好把面板关了（保存成功的正常路径），
 * 那一刻草稿已经被 dropDraft 清过；反过来，切后台/关面板时正处于防抖窗口内，
 * 定时器仍会在面板关闭后才触发 —— 此时内容还没提交，必须写下去，否则等于白做草稿。
 * 判据用 draftContext 是否为空：没打开过面板就没有可写的上下文。
 */
function writeDraftNow(): void {
  if (draftTimer !== undefined) {
    clearTimeout(draftTimer);
    draftTimer = undefined;
  }
  if (draftContext.value === '') return;
  const draft = currentDraft();
  if (!isDraftMeaningfulDraft(draft)) {
    clearDraft(DRAFT_SCOPE, draftContext.value);
    return;
  }
  writeDraft(DRAFT_SCOPE, draftContext.value, draft);
}

function dropDraft(): void {
  if (draftTimer !== undefined) {
    clearTimeout(draftTimer);
    draftTimer = undefined;
  }
  clearDraft(DRAFT_SCOPE, draftContext.value);
  pendingDraft.value = null;
}

function restoreDraft(draft: ExpenseDraft): void {
  parts.value = [...draft.parts];
  input.value = draft.input;
  isRefund.value = draft.isRefund;
  categoryId.value = draft.categoryId;
  paymentMethodId.value = draft.paymentMethodId;
  spendDate.value = draft.spendDate;
  note.value = draft.note;
  pendingDraft.value = null;
  if (paymentMethodId.value !== null) void refreshPreview();
}

// ---------------------------------------------------------------------------
// 草稿：返回键（鸿蒙/安卓）的脏表单拦截
// ---------------------------------------------------------------------------

/** 按返回键被拦下时的就地提示；面板关闭时清空 */
const backInterceptHint = ref<string | null>(null);

/**
 * 声明「面板里有未提交内容，别退」。
 *
 * 为什么必须由 Web 侧主动声明：返回键是**原生**事件，原生无从得知页面里有没有半截表单。
 * 不声明就等于默认「没有未保存内容」→ 用户一按返回，正在记的半笔账连面板一起消失，
 * 而「切后台顺手记一笔」恰恰是本应用最高频的动作。
 * hardware.ts 的 askBeforeBack() 在返回键时同步派发 BEFORE_BACK_EVENT，
 * 这里 preventDefault() 即是应答（同步，不需要 await）。
 *
 * 判据复用草稿工具的 isDraftMeaningful，不另造状态：
 * 有金额、有备注、改过分类或支付方式，才算「用户真的输入过」。
 * 刚打开的空表单不拦 —— 否则用户按返回永远退不出记账面板。
 * 注意只依据**当前面板**的输入判断：localStorage 里那份 pendingDraft 已经落盘了，
 * 按返回不会丢它，为它拦一次只会白白卡住用户。
 */
function onBeforeBack(event: Event): void {
  if (!props.open) return;
  if (!isDraftMeaningfulDraft(currentDraft())) return;

  event.preventDefault();
  // 此刻多半还在 400ms 防抖窗口内，磁盘上的草稿还是上一次的内容。
  // 同步补写一次，提示里那句「已保留草稿」才是真的。
  writeDraftNow();
  backInterceptHint.value = '这笔还没记上，内容已保留为草稿。确认不记了请点右上角关闭。';
}

let backGuardAttached = false;

function attachBackGuard(): void {
  if (typeof window === 'undefined' || backGuardAttached) return;
  window.addEventListener(BEFORE_BACK_EVENT, onBeforeBack);
  backGuardAttached = true;
}

/** 面板关闭/提交成功后必须摘掉：监听器留在 window 上会跨面板累积，返回键被上一笔的脏状态卡住。 */
function detachBackGuard(): void {
  if (typeof window === 'undefined' || !backGuardAttached) return;
  window.removeEventListener(BEFORE_BACK_EVENT, onBeforeBack);
  backGuardAttached = false;
}

onBeforeUnmount(detachBackGuard);

watch(
  () => props.open,
  async (open) => {
    if (!open) {
      categoryPickerOpen.value = false;
      paymentPickerOpen.value = false;
      backInterceptHint.value = null;
      detachBackGuard();
      return;
    }

    attachBackGuard();

    errorMessage.value = null;
    saving.value = false;

    try {
      await dict.load();
    } catch {
      errorMessage.value = '分类或支付方式加载失败，请检查网络后重试';
    }

    if (props.expense === null) resetForm();
    else fillFrom(props.expense);

    // 上下文在打开这一刻定死：新开面板先给上下文，再谈恢复 —— 否则读草稿的 key 是空的。
    draftContext.value =
      props.expense === null ? `new:${spendDate.value.slice(0, 7)}` : `edit:${props.expense.id}`;
    baselineCategoryId = categoryId.value;
    baselinePaymentMethodId = paymentMethodId.value;

    // 恢复提示：只在「有实质内容且还没过期」时弹。空表单不该打扰用户，
    // 否则几次之后用户就会闭眼点「丢弃」，真出事时也一起点掉。
    const existing = readDraft<ExpenseDraft>(DRAFT_SCOPE, draftContext.value);
    pendingDraft.value =
      existing !== null &&
      isDraftMeaningfulDraft({ ...existing, baseCategoryId: baselineCategoryId, basePaymentMethodId: baselinePaymentMethodId })
        ? existing
        : null;

    void refreshMonthSpent();
    await refreshPreview();

    setTimeout(() => {
      desktopAmountInputRef.value?.focus();
      desktopAmountInputRef.value?.select();
    }, 50);
  },
  { immediate: true },
);

watch([paymentMethodId, spendDate], () => {
  if (props.open) void refreshPreview();
});

// 任何字段变更都留一份草稿：移动端切后台被系统回收时，全内存的表单会直接归零，
// 而「切后台顺手记一笔」是这个应用最高频的动作。防抖 400ms 避免每按一个键写一次。
watch([parts, input, isRefund, categoryId, paymentMethodId, spendDate, note], () => {
  if (!props.open) return;
  // 用户已经在改了，之前的「按返回被拦下」提示立刻撤掉，避免与新内容对不上。
  backInterceptHint.value = null;
  scheduleDraftWrite();
});

function appendInput(key: string): void {
  if (key === '.') {
    if (input.value.includes('.')) return;
    input.value = `${input.value === '' ? '0' : input.value}.`;
    return;
  }

  if (key === '00') {
    input.value = input.value === '' ? '0' : `${input.value}00`;
    return;
  }

  const [intPart = '', decPart] = input.value.split('.');

  if (decPart === undefined) {
    if (intPart.length >= 9) return;
    input.value = input.value === '0' ? key : input.value + key;
    return;
  }

  if (decPart.length >= 2) return;
  input.value += key;
}

function onKey(key: KeypadKey): void {
  errorMessage.value = null;

  if (key === 'back') {
    input.value = input.value.slice(0, -1);
    return;
  }

  if (key === 'plus') {
    const cents = inputCents.value;
    if (cents > 0) {
      parts.value = [...parts.value, cents];
      input.value = '';
    }
    return;
  }

  if (key === 'save') {
    void save();
    return;
  }

  appendInput(key);
}

function handleCategorySelected(id: string): void {
  categoryId.value = id;
}

function handlePaymentMethodSelected(id: string): void {
  paymentMethodId.value = id;
}

/**
 * 把保存失败翻译成用户能据以行动的一句话。
 *
 * 分三档是因为三种失败的下一步完全不同：
 * - 在线接口报错 → 服务端给了原因（分类被删、字段非法等），照实说；
 * - 离线暂存失败 → 网络已经不通了，用户只能稍后重试，必须说清「这笔**还没记上**」；
 * - 完全不认识 → 说「已保留草稿」，并告诉用户草稿在哪（下次打开记账可恢复）。
 */
function describeSaveError(error: unknown): string {
  if (error instanceof ApiError && error.status === 0) {
    return '连不上服务器，这笔账还没记上。草稿已保留，恢复网络后再点一次保存即可。';
  }
  if (error instanceof ApiError) {
    return error.message;
  }
  // 离线写入路径抛出来的都是非ApiError（IndexedDB / Outbox 层）
  return '保存失败，这笔账还没记上。草稿已保留，可稍后重试；若反复失败请检查本机存储空间。';
}

async function save(): Promise<void> {
  // in-flight 守卫：连点「保存」只发一次请求，否则会记两笔。
  // saving 是同步置位的（下面第一个 await 之前），所以第二次点击一定进得来这道判。
  if (!canSave.value || saving.value) return;

  if (categoryId.value === null) {
    errorMessage.value = '请选择分类';
    return;
  }
  if (paymentMethodId.value === null) {
    errorMessage.value = '请选择支付方式';
    return;
  }

  if (canInstallment.value && isInstallment.value && customPeriods.value) {
    const p = parseInt(customPeriodsInput.value, 10);
    if (!Number.isFinite(p) || p < 2 || p > 600) {
      errorMessage.value = '分期期数需在 2 到 600 之间';
      return;
    }
  }

  const amountCents = isRefund.value ? -totalCents.value : totalCents.value;

  saving.value = true;
  try {
    if (canInstallment.value && isInstallment.value) {
      if (!previewDates.value) {
        await refreshPreview();
      }
      const planName =
        note.value.trim() !== '' ? note.value.trim() : `${categoryLabel.value}分期`;
      const firstDueDate = previewDates.value?.repaymentDate || spendDate.value;
      /**
       * 把已有普通支出改为分期时，**在同一次请求**里建计划 + 软删原单。
       *
       * 以前是 `create` 之后再 `remove` 两步：弱网下第一步成功、第二步失败，
       * 就会留下「计划已建、原支出还在」的中间态 —— 同一笔钱在待还里
       * 同时以原全额和分期期次出现，而且不报错。现在交给服务端一个事务兜住。
       */
      await plansApi.create({
        name: planName,
        categoryId: categoryId.value,
        paymentMethodId: paymentMethodId.value,
        source: 'installment',
        totalAmountCents: totalCents.value,
        purchaseDate: spendDate.value,
        periods: effectivePeriods.value,
        firstDueDate,
        remindDaysBefore: 3,
        autoPost: false,
        note: note.value.trim(),
        confirmFirst: false,
        ...(props.expense !== null ? { consumeExpenseId: props.expense.id } : {}),
      });

      await plansStore.refresh();
    } else if (props.expense === null) {
      if (!syncStore.isOnline) {
        await syncStore.addOfflineExpense({
          amountCents,
          categoryId: categoryId.value,
          paymentMethodId: paymentMethodId.value,
          spendDate: spendDate.value,
          note: note.value,
        });
      } else {
        try {
          await expensesApi.create({
            amountCents,
            categoryId: categoryId.value,
            paymentMethodId: paymentMethodId.value,
            spendDate: spendDate.value,
            note: note.value,
          });
        } catch (error) {
          if (error instanceof ApiError && error.status === 0) {
            // 网络异常连不上服务器时，平滑转入离线队列
            await syncStore.addOfflineExpense({
              amountCents,
              categoryId: categoryId.value,
              paymentMethodId: paymentMethodId.value,
              spendDate: spendDate.value,
              note: note.value,
            });
          } else {
            throw error;
          }
        }
      }
    } else {
      if (!syncStore.isOnline) {
        await syncStore.updateOfflineExpense(props.expense.id, {
          amountCents,
          categoryId: categoryId.value,
          paymentMethodId: paymentMethodId.value,
          spendDate: spendDate.value,
          note: note.value,
        });
      } else {
        try {
          await expensesApi.update(props.expense.id, {
            amountCents,
            categoryId: categoryId.value,
            paymentMethodId: paymentMethodId.value,
            spendDate: spendDate.value,
            note: note.value,
          });
        } catch (error) {
          if (error instanceof ApiError && error.status === 0) {
            await syncStore.updateOfflineExpense(props.expense.id, {
              amountCents,
              categoryId: categoryId.value,
              paymentMethodId: paymentMethodId.value,
              spendDate: spendDate.value,
              note: note.value,
            });
          } else {
            throw error;
          }
        }
      }
    }

    writeLastChoice({
      categoryId: categoryId.value,
      paymentMethodId: paymentMethodId.value,
    });
    recordUsage(categoryId.value, paymentMethodId.value);

    // 提交成功才清草稿：失败时草稿必须留着，否则用户重试要重新敲一遍金额与备注。
    dropDraft();

    emit('saved');
    emit('close');
  } catch (error) {
    // 离线写入（sync.ts / idb.ts）失败现在会往上抛，这里必须接住并说人话 ——
    // 否则只剩一个静默失败的记账面板，用户以为记上了，实际没有。
    // 同时补写一份草稿：提示里说了「草稿已保留」，就得真的留得住（防抖可能还没到点）。
    writeDraftNow();
    errorMessage.value = describeSaveError(error);
  } finally {
    saving.value = false;
  }
}

async function confirmDelete(): Promise<void> {
  if (props.expense === null || saving.value) return;

  if (!confirmingDelete.value) {
    confirmingDelete.value = true;
    return;
  }

  saving.value = true;
  try {
    if (!syncStore.isOnline) {
      await syncStore.deleteOfflineExpense(props.expense.id);
    } else {
      try {
        await expensesApi.remove(props.expense.id);
      } catch (error) {
        if (error instanceof ApiError && error.status === 0) {
          await syncStore.deleteOfflineExpense(props.expense.id);
        } else {
          throw error;
        }
      }
    }
    emit('saved');
    emit('close');
  } catch (error) {
    // 删除失败不写草稿：草稿里是一笔「待保存的修改」，而这笔已经被删了 ——
    // 留着会让下次打开弹出一个恢复不回来的编辑草稿。
    dropDraft();
    errorMessage.value = describeSaveError(error);
    confirmingDelete.value = false;
  } finally {
    saving.value = false;
  }
}

function close(): void {
  emit('close');
}
</script>

<template>
  <div v-if="open" class="fixed inset-0 z-[var(--z-sheet)]">
    <!-- 遮罩背景 -->
    <button
      type="button"
      class="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)]"
      aria-label="关闭"
      @click="close"
    />

    <!--
      容器自适应：
      - 窄屏（<1024px）：优雅底部抽屉（max-h-[92vh]），自适应内容高，底部吸附键盘；
      - 宽屏（≥1024px）：右侧定宽 480px 面板。
    -->
    <section
      class="absolute inset-x-0 bottom-0 top-[5vh] flex flex-col rounded-t-[24px] bg-surface shadow-[var(--el-2)] lg:left-auto lg:right-0 lg:top-0 lg:w-[480px] lg:rounded-none"
      role="dialog"
      aria-modal="true"
      @keydown.esc="close"
    >
      <!-- 顶栏 -->
      <header class="flex items-center justify-between border-b border-line/60 px-4 py-3 sm:px-6">
        <div class="flex items-center gap-2">
          <h2 class="text-base font-bold text-ink">
            {{ expense === null ? '记一笔' : '编辑支出' }}
          </h2>
          <span v-if="expense?.source === 'plan'" class="rounded bg-sunken px-1.5 py-0.5 text-[10px] text-ink-muted">
            计划生成
          </span>
        </div>

        <div class="flex items-center gap-2">
          <button
            v-if="expense !== null"
            type="button"
            class="rounded-sm px-2.5 py-1 text-xs font-semibold transition-colors duration-150"
            :class="confirmingDelete ? 'bg-danger-fill text-on-danger font-bold' : 'text-danger-text hover:bg-sunken'"
            :disabled="saving"
            @click="confirmDelete"
          >
            {{ confirmingDelete ? '确认删除' : '删除' }}
          </button>

          <button
            type="button"
            class="relative grid h-10 w-10 place-items-center rounded-sm text-sm font-bold text-ink-muted transition-colors hover:bg-sunken hover:text-ink after:absolute after:-inset-0.5 after:rounded-sm after:content-['']"
            aria-label="关闭"
            @click="close"
          >
            ✕
          </button>
        </div>
      </header>

      <!-- 中间可滚动表单区 -->
      <div class="min-h-0 flex-1 overflow-y-auto px-4 py-3 sm:px-6 space-y-4">
        <!--
          草稿恢复提示。
          只在检测到未过期且有实质内容的草稿时出现；空表单不打扰用户。
          默认**不自动恢复** —— 自动恢复会把用户没打算提交的东西带进去，
          也说不清当前屏幕上的数字是他自己刚输的还是上次留下的。
        -->
        <div v-if="pendingDraft !== null" class="rounded-md border border-primary/40 bg-primary/10 p-3">
          <p class="text-xs font-bold text-primary-text">上次有未提交的记账草稿</p>
          <p class="mt-1 text-[11px] leading-relaxed text-primary-text/90">
            草稿里有：
            <strong>{{ formatCents(
              pendingDraft.parts.reduce((sum, p) => sum + p, 0) + parseYuanToCents(pendingDraft.input),
            ) }}</strong>
            <template v-if="pendingDraft.note !== ''"> · 备注「{{ pendingDraft.note }}」</template>
            · {{ formatMonthDay(pendingDraft.spendDate) }}。要恢复吗？
          </p>
          <div class="mt-2 flex items-center gap-3">
            <button
              type="button"
              class="rounded-sm bg-primary-fill px-3 py-1.5 text-xs font-bold text-on-primary transition-opacity hover:opacity-90"
              @click="restoreDraft(pendingDraft!)"
            >
              恢复草稿
            </button>
            <button
              type="button"
              class="text-xs font-semibold text-ink-muted hover:text-ink"
              @click="dropDraft"
            >
              丢弃，重新记
            </button>
          </div>
        </div>

        <!-- ① 金额与支出/退款切换 -->
        <div class="rounded-xl border border-line/60 bg-canvas/70 p-4 text-center shadow-xs">
          <!-- 连加算式提示 -->
          <p v-if="parts.length > 0" class="text-xs font-mono text-ink-muted">
            {{ parts.map((item) => formatYuan(item)).join(' + ') }} +
          </p>

          <!-- 桌面端：直接用物理键盘输入的金额输入框 -->
          <div
            v-if="coreEditable"
            class="mt-1 hidden lg:flex items-center justify-center font-mono text-3xl sm:text-4xl font-black tracking-tight"
          >
            <span :class="isRefund ? 'text-danger-text' : 'text-ink'">{{ isRefund ? '-¥' : '¥' }}</span>
            <input
              ref="desktopAmountInputRef"
              :value="input"
              type="text"
              placeholder="0.00"
              class="w-56 bg-transparent text-center outline-none border-b-2 border-line/40 focus:border-primary transition-colors placeholder:text-ink-muted/30"
              :class="isRefund ? 'text-danger-text' : 'text-ink'"
              @input="handleDesktopAmountInput"
              @keydown.enter.prevent="save"
            />
          </div>

          <!-- 移动端：展示大字金额，由下方自定义数字键盘输入 -->
          <p
            class="mt-1 font-mono text-3xl sm:text-4xl font-black tracking-tight"
            :class="[isRefund ? 'text-danger-text' : 'text-ink', coreEditable ? 'lg:hidden' : '']"
          >
            {{ isRefund ? '-' : '' }}{{ formatYuan(totalCents) }}
          </p>

          <!-- 支出 / 退款切换胶囊 -->
          <div v-if="coreEditable" class="mt-2.5 inline-flex rounded-full bg-sunken/80 p-0.5">
            <button
              type="button"
              class="rounded-full px-3 py-1 text-xs font-bold transition-all duration-150"
              :class="!isRefund ? 'bg-surface text-ink shadow-xs' : 'text-ink-muted hover:text-ink'"
              @click="isRefund = false"
            >
              支出
            </button>
            <button
              type="button"
              class="rounded-full px-3 py-1 text-xs font-bold transition-all duration-150"
              :class="isRefund ? 'bg-surface text-danger-text shadow-xs' : 'text-ink-muted hover:text-ink'"
              @click="isRefund = true"
            >
              退款
            </button>
          </div>
        </div>

        <p
          v-if="!coreEditable"
          class="rounded-md bg-sunken/60 p-2.5 text-xs leading-relaxed text-ink-muted"
        >
          此记录由计划自动生成，金额与日期在计划中维护；此处仅支持修改备注。
        </p>

        <!-- ② 核心信息卡片（单行单元格流，彻底移除横向滑块） -->
        <div class="divide-y divide-outline/60 rounded-2xl border border-outline/60 bg-surface-container shadow-[var(--el-1)]">
          <!-- 分类单元格行 -->
          <button
            type="button"
            :disabled="!coreEditable"
            class="flex w-full items-center justify-between p-3.5 text-left transition-colors duration-150 hover:bg-sunken/40 first:rounded-t-xl active:bg-sunken disabled:opacity-60"
            @click="categoryPickerOpen = true"
          >
            <div class="flex items-center gap-3 min-w-0">
              <div class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-sunken">
                <CategoryIcon :category-id="categoryId" :size="18" />
              </div>
              <div class="min-w-0">
                <span class="block text-[10px] font-medium text-ink-muted">支出分类</span>
                <span class="block truncate text-sm font-bold text-ink">
                  {{ categoryLabel }}
                </span>
              </div>
            </div>
            <div class="flex items-center gap-1 text-ink-muted">
              <span class="text-xs font-medium">更改</span>
              <ChevronRight class="h-4 w-4" />
            </div>
          </button>

          <!-- 支付方式单元格行 -->
          <button
            type="button"
            :disabled="!coreEditable"
            class="flex w-full items-center justify-between p-3.5 text-left transition-colors duration-150 hover:bg-sunken/40 active:bg-sunken disabled:opacity-60"
            @click="paymentPickerOpen = true"
          >
            <div class="flex items-center gap-3 min-w-0">
              <div class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-sunken">
                <PaymentIcon
                  v-if="selectedPaymentMethod"
                  :name="selectedPaymentMethod.name"
                  :icon="selectedPaymentMethod.icon"
                  :size="18"
                />
              </div>
              <div class="min-w-0">
                <span class="block text-[10px] font-medium text-ink-muted">支付方式</span>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="truncate text-sm font-bold text-ink">{{ paymentLabel }}</span>
                  <span
                    v-if="selectedPaymentMethod?.type === 'credit'"
                    class="rounded bg-sunken px-1.5 py-0.2 text-[10px] text-ink-muted"
                  >
                    账单{{ selectedPaymentMethod.billingDay }}日 / 还款{{ selectedPaymentMethod.repaymentDay }}日
                  </span>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-1 text-ink-muted">
              <span class="text-xs font-medium">更改</span>
              <ChevronRight class="h-4 w-4" />
            </div>
          </button>

          <!-- 消费日期单元格行 -->
          <div class="flex items-center justify-between p-3.5">
            <div class="flex items-center gap-3 min-w-0">
              <div class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-sunken text-ink-muted">
                <Calendar class="h-4 w-4" />
              </div>
              <div class="min-w-0">
                <span class="block text-[10px] font-medium text-ink-muted">消费日期</span>
                <span class="block text-sm font-bold text-ink">
                  {{ formatMonthDay(spendDate) }}
                </span>
              </div>
            </div>

            <div class="flex items-center gap-2">
              <button
                v-if="spendDate !== todayLocal()"
                type="button"
                class="rounded px-2 py-0.5 text-xs font-semibold text-primary hover:bg-sunken transition-colors"
                @click="spendDate = todayLocal()"
              >
                设为今天
              </button>
              <input
                v-model="spendDate"
                type="date"
                :disabled="!coreEditable"
                class="rounded border border-line/80 bg-sunken px-2 py-1 text-xs font-semibold text-ink outline-none"
              />
            </div>
          </div>

          <!-- 分期付款单元格行（仅信用卡类型、非退款且可核心编辑时展示） -->
          <div v-if="canInstallment" class="p-3.5 space-y-2.5">
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-3 min-w-0">
                <div class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-sunken text-ink-muted">
                  <CreditCard class="h-4 w-4" />
                </div>
                <div class="min-w-0">
                  <span class="block text-[10px] font-medium text-ink-muted">分期还款</span>
                  <span class="block text-sm font-bold text-ink">
                    {{ isInstallment ? `${effectivePeriods} 期（约 ${installmentPerPeriodText}/期）` : '未开启' }}
                  </span>
                </div>
              </div>

              <!-- 切换开关 -->
              <label class="relative inline-flex cursor-pointer items-center">
                <input
                  v-model="isInstallment"
                  type="checkbox"
                  class="peer sr-only"
                />
                <div
                  class="h-5 w-9 rounded-full bg-surface-high transition-colors duration-200 peer-checked:bg-primary after:absolute after:left-[2px] after:top-[2px] after:h-4 after:w-4 after:rounded-full after:bg-on-surface after:transition-all after:content-[''] peer-checked:after:translate-x-4"
                />
              </label>
            </div>

            <!-- 分期期数选项 -->
            <div v-if="isInstallment" class="rounded-lg bg-sunken/40 p-2.5">
              <div class="flex flex-wrap items-center gap-1.5">
                <ChipButton
                  v-for="p in [3, 6, 12, 24]"
                  :key="p"
                  :active="!customPeriods && installmentPeriods === p"
                  @click="selectPeriods(p)"
                >
                  {{ p }} 期
                </ChipButton>
                <ChipButton
                  :active="customPeriods"
                  @click="enableCustomPeriods"
                >
                  自定义
                </ChipButton>
                <span v-if="customPeriods" class="inline-flex items-center gap-1 text-xs ml-1">
                  <input
                    v-model="customPeriodsInput"
                    type="number"
                    min="2"
                    max="600"
                    placeholder="期数"
                    class="w-14 rounded border border-line bg-surface px-2 py-0.5 text-xs text-ink outline-none"
                  />
                  <span class="text-ink-muted">期</span>
                </span>
              </div>
              <p class="mt-1.5 text-[11px] text-ink-muted">
                {{
                  expense !== null
                    ? `将此笔支出转为 ${effectivePeriods} 期分期计划，原支出记录将由分期接管。`
                    : `共 ${effectivePeriods} 期，到期前由系统自动提醒入账。`
                }}
              </p>
            </div>
          </div>

          <!-- 备注单元格行 -->
          <div class="flex items-center gap-3 p-3.5 last:rounded-b-xl">
            <div class="grid h-8 w-8 shrink-0 place-items-center rounded-lg bg-sunken text-ink-muted">
              <FileText class="h-4 w-4" />
            </div>
            <div class="flex-1 min-w-0">
              <label for="expense-note-input" class="block text-[10px] font-medium text-ink-muted">
                备注说明
              </label>
              <input
                id="expense-note-input"
                v-model="note"
                type="text"
                maxlength="200"
                placeholder="选填，如商户名、商品名"
                class="w-full bg-transparent text-sm font-medium text-ink outline-none placeholder:text-ink-muted/60"
                @focus="noteFocused = true"
                @blur="noteFocused = false"
                @keydown.enter.prevent="save"
              />
            </div>
            <button
              v-if="note"
              type="button"
              class="text-xs text-ink-muted hover:text-ink px-1"
              @click="note = ''"
            >
              ✕
            </button>
          </div>
        </div>

        <p v-if="errorMessage !== null" class="mt-2 text-center text-xs font-semibold text-danger-text">
          {{ errorMessage }}
        </p>

        <!-- 返回键被拦下时的提示：就地说明「内容没丢」，而不是让用户以为返回键坏了 -->
        <p
          v-if="backInterceptHint !== null"
          class="mt-2 rounded-md bg-sunken/70 px-3 py-2 text-center text-xs font-semibold text-ink-muted"
        >
          {{ backInterceptHint }}
        </p>
      </div>

      <!-- ③ 吸底区：去除横向滑动条，紧凑状态栏 + 数字键盘（移动端）/ 动作按钮（桌面端） -->
      <div class="border-t border-line/60 bg-surface">
        <!-- 紧凑单行状态栏 -->
        <div class="flex items-center justify-between px-4 py-1.5 text-xs border-b border-line/30 lg:px-6">
          <div class="min-w-0 pr-2">
            <span
              v-if="landingHint !== null"
              :class="landingHint.shifted ? 'font-bold text-accent-text' : 'text-ink-muted'"
              class="truncate block text-[11px]"
            >
              {{ landingHint.text }}
            </span>
          </div>

          <div class="flex items-baseline gap-1.5 shrink-0 text-ink-muted text-[11px]">
            <span>本月已支出</span>
            <b class="text-ink font-bold tabular-nums">
              {{ monthSpentCents === null ? '—' : formatCompact(monthSpentCents) }}
            </b>
          </div>
        </div>

        <!-- 移动端快捷分类选择区：常用分类（横排单行，清晰分界底色） -->
        <div
          v-if="coreEditable && quickCategories.length > 0"
          class="px-2.5 py-1.5 border-b border-line/70 bg-sunken/40 lg:hidden"
        >
          <div class="flex items-center gap-1">
            <button
              v-for="cat in quickCategories"
              :key="cat.id"
              type="button"
              :title="cat.name"
              class="flex-1 min-w-0 py-1.5 px-1 rounded-full text-xs text-center transition-all duration-150 active:scale-95"
              :class="
                cat.id === categoryId
                  ? 'bg-primary-fill text-on-primary font-bold shadow-xs'
                  : 'bg-surface text-ink-muted hover:bg-canvas hover:text-ink font-medium border border-line/50'
              "
              @click="categoryId = cat.id"
            >
              <span class="truncate block">{{ cat.name.slice(0, 2) }}</span>
            </button>
          </div>
        </div>

        <!-- 备注输入辅助条（移动端）：原生软键盘弹出、数字键盘折叠时，保存临时挂在这条上。
             v-show 而非 v-if —— blur 与按钮 click 的竞态下元素不能被卸载。 -->
        <div
          v-show="noteFocused"
          class="flex items-center justify-between gap-3 px-4 py-2 border-b border-line/70 lg:hidden"
        >
          <div class="min-w-0 text-xs text-ink-muted">
            <span class="mr-1.5">金额</span>
            <b class="text-sm font-bold text-ink tabular-nums">{{ formatCents(totalCents) }}</b>
          </div>
          <button
            type="button"
            :disabled="coreEditable ? !canSave || saving : saving"
            class="rounded-md bg-primary-fill px-5 py-1.5 text-xs font-bold text-on-primary shadow-xs transition-transform active:scale-95 disabled:opacity-40"
            @mousedown.prevent
            @click="save"
          >
            {{ saving ? '…' : coreEditable ? saveLabel : '保存备注' }}
          </button>
        </div>

        <!-- 移动端数字键盘（5列网格：左侧常用支付方式 + 右侧 4 列标准数字键盘）。
             备注聚焦时折叠：原生软键盘 + 数字键盘并存会把表单顶出屏幕。 -->
        <div v-if="coreEditable" v-show="!noteFocused" class="lg:hidden">
          <NumericKeypad
            :can-save="canSave"
            :saving="saving"
            :save-label="saveLabel"
            @press="onKey"
          >
            <template #left>
              <button
                v-for="slot in leftPaymentSlots"
                :key="slot.key"
                type="button"
                :disabled="slot.type === 'empty'"
                :title="slot.title"
                class="flex items-center justify-center rounded-lg text-xs font-medium transition-all duration-150 active:scale-95 disabled:invisible"
                :class="[
                  slot.rowSpan === 2 ? 'row-span-2' : slot.rowSpan === 4 ? 'row-span-4' : '',
                  slot.type === 'method' && slot.method?.id === paymentMethodId
                    ? 'bg-primary-fill text-on-primary font-bold shadow-xs'
                    : 'bg-canvas text-ink-muted hover:bg-surface hover:text-ink border border-line/50',
                ]"
                @click="handleLeftSlotClick(slot)"
              >
                <span class="truncate px-1">{{ slot.label }}</span>
              </button>
            </template>
          </NumericKeypad>
        </div>

        <!-- 桌面端底部操作按钮栏（取代虚拟数字键盘组件） -->
        <div v-if="coreEditable" class="hidden lg:flex items-center justify-end gap-3 px-6 py-4">
          <button
            type="button"
            :disabled="saving"
            class="rounded-sm border border-line px-5 py-2.5 text-xs font-semibold text-ink-muted hover:bg-sunken hover:text-ink transition-colors disabled:opacity-40"
            @click="close"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="!canSave || saving"
            class="rounded-sm bg-primary-fill px-6 py-2.5 text-xs font-bold text-on-primary shadow-xs hover:opacity-90 active:scale-95 transition-all disabled:opacity-40"
            @click="save"
          >
            {{ saving ? '保存中…' : saveLabel }}
          </button>
        </div>

        <!-- 计划生成记录修改保存按钮 -->
        <div v-else class="p-4">
          <button
            type="button"
            :disabled="saving"
            class="w-full rounded-[14px] bg-tertiary py-3 text-sm font-bold text-on-tertiary shadow-[var(--el-1)] transition-all active:scale-[.98] [clip-path:polygon(0_0,100%_0,100%_100%,9px_100%,0_calc(100%_-_9px))]"
            @click="save"
          >
            {{ saving ? '保存中…' : '保存备注' }}
          </button>
        </div>
      </div>
    </section>

    <!-- 独立的双列分类选择抽屉（绝无横向滑动条） -->
    <CategoryPickerSheet
      :open="categoryPickerOpen"
      :active-category-id="categoryId"
      @close="categoryPickerOpen = false"
      @select="handleCategorySelected"
    />

    <!-- 独立的纵向支付方式选择抽屉 -->
    <PaymentMethodPickerSheet
      :open="paymentPickerOpen"
      :active-payment-method-id="paymentMethodId"
      @close="paymentPickerOpen = false"
      @select="handlePaymentMethodSelected"
    />
  </div>
</template>
