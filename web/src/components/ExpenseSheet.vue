<script setup lang="ts">
/**
 * 记账抽屉 —— 记一笔 / 编辑已有的账。
 *
 * 设计目标：**3 次点击内完成一笔记账**。打开时分类、支付方式、日期都已
 * 预选好（上次用的或第一项），正常情况下只需要「敲金额 → 保存」。
 *
 * 编辑与新建共用同一个组件：字段、校验、保存路径完全一致，
 * 分成两个组件迟早会在其中一边漏掉某个规则。
 */
import { computed, ref, watch } from 'vue';

import { ApiError, expenses as expensesApi, reports as reportsApi, type Expense } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { currentMonth, formatMonthDay, formatMonthLabel, todayLocal } from '@/utils/dates';
import { centsToInput, formatCompact, formatYuan, parseYuanToCents } from '@/utils/money';

import ChipButton from './ChipButton.vue';
import NumericKeypad from './NumericKeypad.vue';
import PaymentIcon from './PaymentIcon.vue';
import type { KeypadKey } from './keypad';

const props = withDefaults(
  defineProps<{
    open: boolean;
    /** 传了就是编辑模式，不传是新建 */
    expense?: Expense | null;
  }>(),
  { expense: null },
);

const emit = defineEmits<{ close: []; saved: [] }>();

const dict = useDictionariesStore();

/** 已用「＋」确认过的金额（分） */
const parts = ref<number[]>([]);
/** 当前正在输入的「元」文本 */
const input = ref('');
/** 退款 / 冲销：金额取负。用显式开关而不是让用户敲负号 —— 键盘上放不下负号键 */
const isRefund = ref(false);

const activeRootId = ref<string | null>(null);
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

/**
 * 计划生成的记录只允许改备注。
 *
 * 服务端已经强制了这条规则，这里同步做界面降级 —— 让用户看到「为什么改不了」，
 * 而不是敲完金额点保存才被 403 拒绝。
 */
const coreEditable = computed(() => props.expense === null || props.expense.source === 'manual');

const activeRoot = computed(
  () => dict.rootCategories.find((item) => item.id === activeRootId.value) ?? null,
);

const childOptions = computed(() =>
  activeRoot.value === null ? [] : dict.selectableChildren(activeRoot.value),
);

/** 服务端算出的入账日与还款日（预览，不落库） */
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
    // 预览失败不该阻塞记账 —— 它只是个提示，拿不到就不显示
    previewDates.value = null;
  }
}

/**
 * 键盘上方常驻的「本月已支出」。
 *
 * 记账的时候最想知道的就是「这个月已经花了多少」，可抽屉一弹出来整屏都被盖住，
 * 那个数字恰好是唯一看不到的 —— 于是要么凭记忆记，要么关掉抽屉再去看一眼。
 * 这里补一份，成本只有一次聚合查询。
 *
 * 拿不到就显示占位符，绝不阻塞记账：它是背景信息，不是记账流程的一环。
 */
const monthSpentCents = ref<number | null>(null);

async function refreshMonthSpent(): Promise<void> {
  try {
    monthSpentCents.value = (await reportsApi.monthly(currentMonth())).report.totalCents;
  } catch {
    monthSpentCents.value = null;
  }
}

/**
 * 这笔会记在哪个月。
 *
 * 这是界面上最容易被忽略、却最容易造成误解的一条信息：信用卡的还款日
 * 很可能落在下个月，于是用户记完一笔回到首页，发现「本月还是 0」，
 * 以为没保存成功（我自己在验证时就被骗了一次）。把结果直接说出来，误解就消失了。
 */
const landingHint = computed(() => {
  const dates = previewDates.value;
  if (dates === null) return null;

  const repaymentMonth = dates.repaymentDate.slice(0, 7);
  const sameMonth = repaymentMonth === spendDate.value.slice(0, 7);

  return sameMonth
    ? { shifted: false, text: `还款日 ${formatMonthDay(dates.repaymentDate)}` }
    : {
        shifted: true,
        text: `这笔会记在 ${formatMonthLabel(repaymentMonth)}（还款日 ${formatMonthDay(dates.repaymentDate)}）`,
      };
});

/* ---- 键盘上方的常驻摘要 -------------------------------------------------
 *
 * 解决的是「重要选择被分屏」：窄屏上抽屉的可滚动区只有 400 多像素，
 * 而金额块 + 分类 + 支付方式 + 日期 + 备注加起来刚好超一点 ——
 * 于是「支付方式 / 日期 / 备注」永远差一点才露出来，每次都要下滑才能核对。
 *
 * 修法不是把它们全搬到首屏（那样首屏会挤成一团），而是**把结果露出来**：
 * 用户这一步要确认的是「我选对了没」，不是「我要改」。
 * 所以键盘上方常驻一行摘要，点其中任意一段会把对应的字段滚进视野 ——
 * 要改的时候也只有一次点击，不用手动滑。
 *
 * 跨月提示也搬到了这里。它原先在「消费日期」字段下面，同样会在折叠线之下 ——
 * 而「这笔会记在下个月」恰恰是记账时最不能漏看的一句话
 * （项目早期就因为这个被误导过一次，见 decisions.md）。
 */
type FieldKey = 'category' | 'payment' | 'date' | 'note';

const categoryField = ref<HTMLElement | null>(null);
const paymentField = ref<HTMLElement | null>(null);
const dateField = ref<HTMLElement | null>(null);
const noteField = ref<HTMLElement | null>(null);

interface SummarySegment {
  key: FieldKey;
  label: string;
  /** 还没选 / 还是空的 —— 视觉上退一档，让「待补充」自己冒出来 */
  pending: boolean;
}

const categoryLabel = computed(() => {
  const category = categoryId.value === null ? null : dict.findCategory(categoryId.value);
  if (category === null) return '选分类';

  const parent = category.parentId === null ? null : dict.findCategory(category.parentId);
  return parent === null ? category.name : `${parent.name} · ${category.name}`;
});

const paymentLabel = computed(() => {
  const method =
    paymentMethodId.value === null ? null : dict.findPaymentMethod(paymentMethodId.value);
  return method?.name ?? '选支付方式';
});

const summarySegments = computed<SummarySegment[]>(() => [
  { key: 'category', label: categoryLabel.value, pending: categoryId.value === null },
  { key: 'payment', label: paymentLabel.value, pending: paymentMethodId.value === null },
  { key: 'date', label: formatMonthDay(spendDate.value), pending: false },
  { key: 'note', label: note.value === '' ? '备注' : note.value, pending: note.value === '' },
]);

function reveal(key: FieldKey): void {
  const target = { category: categoryField, payment: paymentField, date: dateField, note: noteField }[
    key
  ].value;

  // block:'nearest' —— 已经在视野里就不动，避免点一下整块跳一下
  target?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
}

/**
 * 「上次用的是哪个分类 / 支付方式」的记忆。
 *
 * 记账是高频动作，绝大多数时候重复的是同一组选择。每次都从第一项重新选，
 * 相当于每天都要多做两次点击 —— 而这两个点击没有任何信息量。
 */
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
    // 隐私模式下 localStorage 不可用，或存的内容被改坏了 —— 退回默认选择即可
    return null;
  }
}

function writeLastChoice(choice: LastChoice): void {
  try {
    localStorage.setItem(LAST_CHOICE_KEY, JSON.stringify(choice));
  } catch {
    /* 同上，失败不影响记账 */
  }
}

function applyDefaultChoice(): void {
  const root = dict.rootCategories[0] ?? null;
  activeRootId.value = root?.id ?? null;
  categoryId.value = root === null ? null : (dict.selectableChildren(root)[0]?.id ?? null);
}

function resetForm(): void {
  parts.value = [];
  input.value = '';
  isRefund.value = false;
  note.value = '';
  spendDate.value = todayLocal();
  confirmingDelete.value = false;

  const last = readLastChoice();

  // 分类：优先沿用上次的选择，但它必须**现在仍然可选**（可能已被停用或删除）
  const remembered = last === null ? null : dict.findCategory(last.categoryId);
  const usable = remembered !== null && remembered.isEnabled ? remembered : null;

  if (usable === null) {
    applyDefaultChoice();
  } else {
    categoryId.value = usable.id;
    const parent = usable.parentId === null ? null : dict.findCategory(usable.parentId);
    const rootId = parent !== null ? parent.id : usable.id;

    if (dict.rootCategories.some((item) => item.id === rootId)) {
      activeRootId.value = rootId;
    } else {
      // 父级已被停用，记忆失效
      applyDefaultChoice();
    }
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
  categoryId.value = expense.categoryId;

  const parent = dict.findCategory(expense.categoryId);
  activeRootId.value = parent === null ? null : (parent.parentId ?? parent.id);

  paymentMethodId.value = expense.paymentMethodId;
  spendDate.value = expense.spendDate;
  note.value = expense.note;
  confirmingDelete.value = false;
}

watch(
  () => props.open,
  async (open) => {
    if (!open) return;

    errorMessage.value = null;
    saving.value = false;

    try {
      await dict.load();
    } catch {
      errorMessage.value = '分类或支付方式加载失败，请检查网络后重试';
    }

    if (props.expense === null) resetForm();
    else fillFrom(props.expense);

    // 不 await：它只是背景信息，慢一点都不该让抽屉晚开一帧
    void refreshMonthSpent();
    await refreshPreview();
  },
  { immediate: true },
);

// 换支付方式或改日期都会改变账单日期，提示要跟着更新
watch([paymentMethodId, spendDate], () => {
  if (props.open) void refreshPreview();
});

/** 键盘输入只做「字形」层面的约束，真正的数值解析在 money.ts 里统一处理 */
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
    // 整数部分最多 9 位：配合服务端的金额上限一起挡住「多按几个 0」
    if (intPart.length >= 9) return;
    // 前导零替换掉，避免出现 "007"
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

function selectRoot(rootId: string): void {
  activeRootId.value = rootId;
  const root = dict.rootCategories.find((item) => item.id === rootId);
  if (root === undefined) return;
  categoryId.value = dict.selectableChildren(root)[0]?.id ?? null;
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

  const amountCents = isRefund.value ? -totalCents.value : totalCents.value;

  saving.value = true;
  try {
    if (props.expense === null) {
      await expensesApi.create({
        amountCents,
        categoryId: categoryId.value,
        paymentMethodId: paymentMethodId.value,
        spendDate: spendDate.value,
        note: note.value,
      });
    } else {
      await expensesApi.update(props.expense.id, {
        amountCents,
        categoryId: categoryId.value,
        paymentMethodId: paymentMethodId.value,
        spendDate: spendDate.value,
        note: note.value,
      });
    }

    // 记下这次的选择，下次打开抽屉直接沿用
    writeLastChoice({
      categoryId: categoryId.value,
      paymentMethodId: paymentMethodId.value,
    });

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
    await expensesApi.remove(props.expense.id);
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
    <!-- 遮罩：点它关闭。用 button 而不是 div 以获得键盘可达性 -->
    <button
      type="button"
      class="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)]"
      aria-label="关闭"
      @click="close"
    />

    <!--
      一份逻辑、两种容器：
        窄屏（<1024px）—— 底部抽屉，贴底、只有上圆角。
        桌面（≥1024px）—— 右侧定宽面板（500px），贴右边、整高、无圆角。
      之前是 `inset-x-0` 通栏且没有 max-width：1440px 的屏幕上它就是一个
      1440×846 的贴底大抽屉，输入框横跨整屏 —— 长得跟手机上不是一回事，
      只是被拉宽了。断点跟 tokens.css 的 --content-max 一致，都是 1024px。
    -->
    <section
      class="absolute inset-x-0 bottom-0 top-[6vh] flex flex-col rounded-t-md bg-surface lg:left-auto lg:right-0 lg:top-0 lg:w-[500px] lg:rounded-none"
      role="dialog"
      aria-modal="true"
      @keydown.esc="close"
    >
      <header class="flex items-center gap-2 px-4 pt-4 pb-2 lg:px-6 lg:pt-6">
        <h2 class="flex-1 text-lg font-bold">{{ expense === null ? '记一笔' : '编辑' }}</h2>

        <button
          v-if="expense !== null"
          type="button"
          class="rounded-sm px-3 py-2 text-sm font-semibold transition-colors duration-200"
          :class="confirmingDelete ? 'bg-danger text-white' : 'text-danger-text hover:bg-sunken'"
          :disabled="saving"
          @click="confirmDelete"
        >
          {{ confirmingDelete ? '确认删除' : '删除' }}
        </button>

        <button
          type="button"
          class="rounded-sm px-3 py-2 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink"
          @click="close"
        >
          取消
        </button>
      </header>

      <div class="min-h-0 flex-1 overflow-y-auto px-4 pb-4 lg:px-6">
        <!-- 金额 -->
        <div class="mt-2 text-center">
          <p class="text-xs text-ink-muted">
            <span v-if="parts.length > 0">
              {{ parts.map((item) => formatYuan(item)).join(' + ') }} +
            </span>
            <span class="ml-1">{{ isRefund ? '退款' : '支出' }}</span>
          </p>

          <p
            class="mt-1 text-3xl font-extrabold tracking-tight"
            :class="isRefund ? 'text-danger-text' : 'text-ink'"
          >
            {{ formatYuan(totalCents) }}
          </p>

          <div v-if="coreEditable" class="mt-3 flex justify-center gap-2">
            <ChipButton :active="!isRefund" @click="isRefund = false">支出</ChipButton>
            <ChipButton :active="isRefund" @click="isRefund = true">退款</ChipButton>
          </div>
        </div>

        <p
          v-if="!coreEditable"
          class="mt-4 rounded-md bg-surface p-3 text-xs leading-relaxed text-ink-muted"
        >
          这条记录由计划生成，金额与日期请在计划里修改；此处只能改备注。
        </p>

        <!--
          分类：一级一行、二级一行。有子项时以子项为准。
          它紧跟在金额下面（不折进任何抽屉），所以在窄屏上也**不必下滑就能选** ——
          记账流程里真正必需的只有「金额 + 分类」，这两样都在首屏。
        -->
        <fieldset ref="categoryField" :disabled="!coreEditable" class="mt-5">
          <legend class="label-cn">分类</legend>

          <div class="mt-2 flex gap-2 overflow-x-auto pb-1">
            <ChipButton
              v-for="root in dict.rootCategories"
              :key="root.id"
              :active="root.id === activeRootId"
              @click="selectRoot(root.id)"
            >
              {{ root.name }}
            </ChipButton>
          </div>

          <div v-if="childOptions.length > 0" class="mt-2 flex flex-wrap gap-2">
            <ChipButton
              v-for="option in childOptions"
              :key="option.id"
              :active="option.id === categoryId"
              @click="categoryId = option.id"
            >
              {{ option.name }}
            </ChipButton>
          </div>
        </fieldset>

        <!-- 支付方式 -->
        <fieldset ref="paymentField" :disabled="!coreEditable" class="mt-5">
          <legend class="label-cn">支付方式</legend>
          <div class="mt-2 flex flex-wrap gap-2">
            <ChipButton
              v-for="method in dict.usablePaymentMethods"
              :key="method.id"
              :active="method.id === paymentMethodId"
              @click="paymentMethodId = method.id"
            >
              <span class="inline-flex items-center gap-1.5">
                <PaymentIcon :name="method.name" :icon="method.icon" :size="14" />
                <span>{{ method.name }}</span>
                <span v-if="method.type === 'credit'" class="text-xs opacity-70">
                  {{ method.billingDay }}/{{ method.repaymentDay }}
                </span>
              </span>
            </ChipButton>
          </div>
          <p v-if="dict.usablePaymentMethods.length === 0" class="mt-2 text-xs text-ink-muted">
            还没有可用的支付方式，请先到「设置」里添加。
          </p>
        </fieldset>

        <!-- 日期 + 备注 -->
        <fieldset ref="dateField" :disabled="!coreEditable" class="mt-5">
          <legend class="label-cn">消费日期</legend>
          <div class="mt-2 flex items-center gap-2">
            <input
              v-model="spendDate"
              type="date"
              class="rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
            />
            <ChipButton :active="spendDate === todayLocal()" @click="spendDate = todayLocal()">
              今天
            </ChipButton>
          </div>

          <!--
            明确告诉用户这笔会落到哪个月。信用卡的还款日可能在下个月，
            不说明的话「记完本月还是 0」会被当成保存失败。
          -->
          <p
            v-if="landingHint !== null"
            class="mt-2 text-xs"
            :class="landingHint.shifted ? 'font-semibold text-accent-text' : 'text-ink-muted'"
          >
            {{ landingHint.text }}
          </p>
        </fieldset>

        <div ref="noteField" class="mt-5">
          <label class="label-cn" for="expense-note">备注</label>
          <input
            id="expense-note"
            v-model="note"
            type="text"
            maxlength="200"
            placeholder="选填"
            class="mt-2 w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
        </div>

        <p v-if="errorMessage !== null" class="mt-4 text-sm text-danger-text">
          {{ errorMessage }}
        </p>
      </div>

      <!--
        键盘吸底：编辑计划生成的记录时不需要金额输入，直接给保存。
        两者共用一条上边框，所以下面几行常驻信息都放在它里面 ——
        否则切到计划记录时会出现两条挨着的分割线。
      -->
      <div class="border-t border-line">
        <!--
          常驻摘要行：已选的分类 / 支付方式 / 日期 / 备注。
          窄屏可滚动区只有 400 多像素，这四项刚好在折叠线之下 ——
          每次都要下滑核对一次。点任意一段会把对应字段滚进视野，
          所以「核对」和「要改」都只花一次点击，不用手动滑。
        -->
        <div class="flex gap-1.5 overflow-x-auto px-4 pt-2.5 lg:px-6">
          <button
            v-for="segment in summarySegments"
            :key="segment.key"
            type="button"
            class="shrink-0 rounded-sm px-2 py-1 text-xs font-semibold transition-colors duration-200"
            :class="segment.pending ? 'bg-sunken text-ink-muted' : 'bg-sunken text-ink'"
            @click="reveal(segment.key)"
          >
            {{ segment.label }}
          </button>
        </div>

        <!--
          跨月提示常驻在这里。
          它原先在「消费日期」字段下面，同样在折叠线之下 —— 而「这笔会记在下个月」
          恰恰是记账时最不能漏看的一句（项目早期就因为这个被误导过一次）。
        -->
        <p
          v-if="landingHint !== null && landingHint.shifted"
          class="px-4 pt-1.5 text-xs font-semibold text-accent-text lg:px-6"
        >
          {{ landingHint.text }}
        </p>

        <!-- 键盘上方常驻「本月已支出」：记账时最该看见的数字，正好是抽屉盖住整屏后唯一看不见的那个 -->
        <p class="flex items-baseline justify-between px-4 pt-1.5 text-xs lg:px-6">
          <span class="text-ink-muted">本月已支出</span>
          <span class="font-semibold text-ink">
            {{ monthSpentCents === null ? '—' : formatCompact(monthSpentCents) }}
          </span>
        </p>

        <!-- 桌面上键盘不该铺满 500px：按键会变成一排扁长的色块，反而不好按 -->
        <div v-if="coreEditable" class="lg:mx-auto lg:max-w-[340px]">
          <NumericKeypad
            :can-save="canSave"
            :saving="saving"
            :save-label="expense === null ? '保存' : '更新'"
            @press="onKey"
          />
        </div>

        <div v-else class="p-4">
          <button
            type="button"
            :disabled="saving"
            class="w-full rounded-md bg-primary-fill py-3.5 text-base font-bold text-on-primary transition-transform duration-200 active:scale-95"
            @click="save"
          >
            {{ saving ? '保存中…' : '保存备注' }}
          </button>
        </div>
      </div>
    </section>
  </div>
</template>
