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

import { ApiError, expenses as expensesApi, type Expense } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { formatMonthDay, formatMonthLabel, todayLocal } from '@/utils/dates';
import { centsToInput, formatYuan, parseYuanToCents } from '@/utils/money';

import ChipButton from './ChipButton.vue';
import NumericKeypad from './NumericKeypad.vue';
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

    <section
      class="absolute inset-x-0 bottom-0 top-[6vh] flex flex-col rounded-t-md bg-surface shadow-none"
      role="dialog"
      aria-modal="true"
      @keydown.esc="close"
    >
      <header class="flex items-center gap-2 px-4 pt-4 pb-2">
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

      <div class="min-h-0 flex-1 overflow-y-auto px-4 pb-4">
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

        <!-- 分类：一级一行、二级一行。有子项时以子项为准 -->
        <fieldset :disabled="!coreEditable" class="mt-5">
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
        <fieldset :disabled="!coreEditable" class="mt-5">
          <legend class="label-cn">支付方式</legend>
          <div class="mt-2 flex flex-wrap gap-2">
            <ChipButton
              v-for="method in dict.usablePaymentMethods"
              :key="method.id"
              :active="method.id === paymentMethodId"
              @click="paymentMethodId = method.id"
            >
              {{ method.name }}
              <span v-if="method.type === 'credit'" class="text-xs opacity-70">
                {{ method.billingDay }}/{{ method.repaymentDay }}
              </span>
            </ChipButton>
          </div>
          <p v-if="dict.usablePaymentMethods.length === 0" class="mt-2 text-xs text-ink-muted">
            还没有可用的支付方式，请先到「设置」里添加。
          </p>
        </fieldset>

        <!-- 日期 + 备注 -->
        <fieldset :disabled="!coreEditable" class="mt-5">
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

        <div class="mt-5">
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

      <!-- 键盘吸底：编辑计划生成的记录时不需要金额输入，直接给保存 -->
      <div v-if="coreEditable" class="border-t border-line">
        <NumericKeypad
          :can-save="canSave"
          :saving="saving"
          :save-label="expense === null ? '保存' : '更新'"
          @press="onKey"
        />
      </div>
      <div v-else class="border-t border-line p-4">
        <button
          type="button"
          :disabled="saving"
          class="w-full rounded-md bg-primary-fill py-3.5 text-base font-bold text-on-primary transition-transform duration-200 active:scale-95"
          @click="save"
        >
          {{ saving ? '保存中…' : '保存备注' }}
        </button>
      </div>
    </section>
  </div>
</template>
