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
import { computed, ref, watch } from 'vue';
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
import { currentMonth, formatMonthDay, formatMonthLabel, todayLocal } from '@/utils/dates';
import {
  centsToInput,
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

watch(
  () => props.open,
  async (open) => {
    if (!open) {
      categoryPickerOpen.value = false;
      paymentPickerOpen.value = false;
      return;
    }

    errorMessage.value = null;
    saving.value = false;

    try {
      await dict.load();
    } catch {
      errorMessage.value = '分类或支付方式加载失败，请检查网络后重试';
    }

    if (props.expense === null) resetForm();
    else fillFrom(props.expense);

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

async function save(): Promise<void> {
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
      });

      // 将已有普通支出改为分期时，原记录由新创建的分期计划接管，移除原单笔记录避免重账
      if (props.expense !== null) {
        await expensesApi.remove(props.expense.id);
      }

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

    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '保存失败，请重试';
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
    errorMessage.value = error instanceof ApiError ? error.message : '删除失败，请重试';
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
      class="absolute inset-x-0 bottom-0 top-[5vh] flex flex-col rounded-t-xl bg-surface shadow-2xl lg:left-auto lg:right-0 lg:top-0 lg:w-[480px] lg:rounded-none"
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
            class="grid h-7 w-7 place-items-center rounded-sm text-sm font-bold text-ink-muted transition-colors hover:bg-sunken hover:text-ink"
            aria-label="关闭"
            @click="close"
          >
            ✕
          </button>
        </div>
      </header>

      <!-- 中间可滚动表单区 -->
      <div class="min-h-0 flex-1 overflow-y-auto px-4 py-3 sm:px-6 space-y-4">
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
        <div class="divide-y divide-line/60 rounded-xl border border-line/60 bg-surface shadow-xs">
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
                  class="h-5 w-9 rounded-full bg-sunken transition-colors duration-200 peer-checked:bg-primary after:absolute after:left-[2px] after:top-[2px] after:h-4 after:w-4 after:rounded-full after:bg-white after:transition-all after:content-[''] peer-checked:after:translate-x-4"
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

        <!-- 移动端数字键盘（5列网格：左侧常用支付方式 + 右侧 4 列标准数字键盘） -->
        <div v-if="coreEditable" class="lg:hidden">
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
            class="w-full rounded-md bg-primary py-3 text-sm font-bold text-white shadow-xs transition-transform active:scale-95"
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
