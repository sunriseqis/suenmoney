<script setup lang="ts">
/**
 * 记一笔 / 编辑支出（原型 `views/ExpenseSheet.jsx`）。
 *
 * 结构照原型：顶部金额显示 → 分类格 + 日期格 → 支付方式格 → 备注 → 退款/分期
 * 两个开关 → 金额预览 → 5 列键盘（左支付列 + 右数字键）→ 底部动作。
 *
 * 业务规则（都是踩过坑的）：
 *   · 金额一律整数分；退款**不加负号输入**，用开关把正值翻成负数 —— 让用户手输
 *     「-」很容易出现「-¥-50」这种脏数据。
 *   · 分期只在「信用卡 + 非退款」时可用，且**走计划接口**而不是支出接口：
 *     一次请求内建计划并软删原单，避免弱网下「计划已建、原单还在」的中间态。
 *   · 离线时落 Outbox 队列（乐观更新），联网后自动补偿；分期不支持离线。
 */
import { Check, ChevronRight, Layers, RotateCcw, Trash2, X } from '@lucide/vue';
import { computed, ref, watch } from 'vue';

import {
  ApiError,
  expenses as expensesApi,
  plans as plansApi,
  type Expense,
  type PaymentMethod,
} from '@/api';
import PCatIcon from '@/components/PCatIcon.vue';
import PPayIcon from '@/components/PPayIcon.vue';
import { useToast } from '@/composables/useToast';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useSyncStore } from '@/stores/sync';
import { PBtn, PIconBtn, PSwitch, PTag } from '@/ui';
import { todayLocal } from '@/utils/dates';
import { formatYuan } from '@/utils/money';

const props = defineProps<{ open: boolean; expense: Expense | null }>();
const emit = defineEmits<{ close: []; saved: [] }>();

const dict = useDictionariesStore();
const sync = useSyncStore();
const plansStore = usePlansStore();
const toast = useToast();

const today = todayLocal();

const amount = ref('');
const categoryId = ref('');
const paymentId = ref('');
const spendDate = ref(today);
const note = ref('');
const isRefund = ref(false);
const periods = ref<number | null>(null);

const catOpen = ref(false);
const payOpen = ref(false);
const railId = ref('');
const saving = ref(false);
const errorMessage = ref<string | null>(null);
const previewDates = ref<{ postingDate: string; repaymentDate: string } | null>(null);

const cents = computed(() => Math.round((Number.parseFloat(amount.value) || 0) * 100));
const effectiveCents = computed(() => (isRefund.value ? -cents.value : cents.value));

const payment = computed<PaymentMethod | null>(() => dict.findPaymentMethod(paymentId.value));
const isCredit = computed(() => payment.value?.type === 'credit');
const canInstallment = computed(() => isCredit.value && !isRefund.value);
const perPeriodCents = computed(() => (periods.value ? Math.round(cents.value / periods.value) : 0));

const category = computed(() => dict.findCategory(categoryId.value));
const categoryLabel = computed(() => {
  const cat = category.value;
  if (!cat) return '选择分类';
  const root = coreRootName(cat.id);
  return root !== '' && root !== cat.name ? `${root} · ${cat.name}` : cat.name;
});

function coreRootName(childId: string): string {
  for (const root of dict.rootCategories) {
    if (root.children.some((c) => c.id === childId)) return root.name;
  }
  return '';
}

const selectableChildren = computed(() => {
  const root = dict.rootCategories.find((r) => r.id === railId.value);
  return root ? dict.selectableChildren(root) : [];
});

/** 打开抽屉时初始化：编辑带入原值，新建给默认（第一个一级分类的第一个子类 + 第一个支付方式） */
watch(
  () => [props.open, props.expense] as const,
  ([open, expense]) => {
    if (!open) return;
    errorMessage.value = null;
    if (expense) {
      amount.value = (Math.abs(expense.amountCents) / 100).toFixed(2);
      categoryId.value = expense.categoryId;
      paymentId.value = expense.paymentMethodId;
      spendDate.value = expense.spendDate;
      note.value = expense.note;
      isRefund.value = expense.amountCents < 0;
      periods.value = null;
    } else {
      amount.value = '';
      const firstRoot = dict.rootCategories[0];
      const firstCat = firstRoot ? dict.selectableChildren(firstRoot)[0] : null;
      categoryId.value = firstCat?.id ?? '';
      paymentId.value = dict.usablePaymentMethods[0]?.id ?? '';
      spendDate.value = today;
      note.value = '';
      isRefund.value = false;
      periods.value = null;
    }
    railId.value = rootOfCategory(categoryId.value);
    previewDates.value = null;
    void refreshPreview();
  },
  { immediate: true },
);

function rootOfCategory(childId: string): string {
  for (const root of dict.rootCategories) {
    if (root.id === childId || root.children.some((c) => c.id === childId)) return root.id;
  }
  return dict.rootCategories[0]?.id ?? '';
}

/** 账期预览：信用卡必须问服务端「这笔记在哪个月」，不要在本地重算 */
async function refreshPreview(): Promise<void> {
  if (!isCredit.value || paymentId.value === '') {
    previewDates.value = null;
    return;
  }
  try {
    previewDates.value = await expensesApi.preview({ spendDate: spendDate.value, paymentMethodId: paymentId.value });
  } catch {
    previewDates.value = null;
  }
}

watch([paymentId, spendDate], () => {
  void refreshPreview();
});

/** 键盘输入 */
function press(key: string): void {
  if (key === 'C') {
    amount.value = '';
    return;
  }
  if (key === 'B') {
    amount.value = amount.value.slice(0, -1);
    return;
  }
  if (key === '.') {
    if (!amount.value.includes('.')) amount.value = (amount.value || '0') + '.';
    return;
  }
  const next = (amount.value === '0' ? '' : amount.value) + key;
  if (next.includes('.') && (next.split('.')[1]?.length ?? 0) > 2) return;
  if (next.length > 9) return;
  amount.value = next;
}

async function save(): Promise<void> {
  errorMessage.value = null;
  if (cents.value === 0) {
    errorMessage.value = '请输入金额';
    return;
  }
  if (categoryId.value === '' || paymentId.value === '') {
    errorMessage.value = '请选择分类与支付方式';
    return;
  }
  saving.value = true;
  try {
    const editing = props.expense;

    // 分期：走计划接口（服务端在同一个事务里建计划 + 软删原单）
    if (periods.value !== null && canInstallment.value) {
      if (!sync.isOnline) {
        errorMessage.value = '分期需要联网创建';
        return;
      }
      await plansApi.create({
        name: note.value.trim() !== '' ? note.value.trim() : `${categoryLabel.value}分期`,
        categoryId: categoryId.value,
        paymentMethodId: paymentId.value,
        source: 'installment',
        totalAmountCents: cents.value,
        purchaseDate: spendDate.value,
        periods: periods.value,
        firstDueDate: previewDates.value?.repaymentDate ?? spendDate.value,
        remindDaysBefore: 3,
        autoPost: false,
        note: note.value.trim(),
        confirmFirst: false,
        ...(editing !== null ? { consumeExpenseId: editing.id } : {}),
      });
      await plansStore.refresh();
      toast.show('已创建分期计划');
      emit('saved');
      emit('close');
      return;
    }

    if (editing === null) {
      if (!sync.isOnline) {
        await sync.addOfflineExpense({
          amountCents: effectiveCents.value,
          categoryId: categoryId.value,
          paymentMethodId: paymentId.value,
          spendDate: spendDate.value,
          note: note.value,
        });
        toast.show(`已离线记一笔 ${formatYuan(effectiveCents.value)}`);
      } else {
        try {
          await expensesApi.create({
            amountCents: effectiveCents.value,
            categoryId: categoryId.value,
            paymentMethodId: paymentId.value,
            spendDate: spendDate.value,
            note: note.value,
          });
          toast.show(`已记一笔 ${formatYuan(effectiveCents.value)}`);
        } catch (error) {
          if (error instanceof ApiError && error.status === 0) {
            await sync.addOfflineExpense({
              amountCents: effectiveCents.value,
              categoryId: categoryId.value,
              paymentMethodId: paymentId.value,
              spendDate: spendDate.value,
              note: note.value,
            });
            toast.show('网络异常，已存入离线队列');
          } else {
            throw error;
          }
        }
      }
    } else {
      if (!sync.isOnline) {
        await sync.updateOfflineExpense(editing.id, {
          amountCents: effectiveCents.value,
          categoryId: categoryId.value,
          paymentMethodId: paymentId.value,
          spendDate: spendDate.value,
          note: note.value,
        });
        toast.show('已离线保存');
      } else {
        await expensesApi.update(editing.id, {
          amountCents: effectiveCents.value,
          categoryId: categoryId.value,
          paymentMethodId: paymentId.value,
          spendDate: spendDate.value,
          note: note.value,
        });
        toast.show('已保存修改');
      }
    }

    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '保存失败，请重试';
  } finally {
    saving.value = false;
  }
}

async function remove(): Promise<void> {
  const editing = props.expense;
  if (editing === null) return;
  saving.value = true;
  try {
    if (!sync.isOnline) {
      await sync.deleteOfflineExpense(editing.id);
    } else {
      await expensesApi.remove(editing.id);
    }
    toast.show('已删除这笔记录');
    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '删除失败';
  } finally {
    saving.value = false;
  }
}

function pickCategory(id: string): void {
  categoryId.value = id;
  catOpen.value = false;
}

function pickPayment(id: string): void {
  paymentId.value = id;
  payOpen.value = false;
}

const KEYS = ['7', '8', '9', 'B', '4', '5', '6', 'C', '1', '2', '3', 'OK', '0', '00', '.'];
</script>

<template>
  <template v-if="open">
    <div class="scrim" @click="emit('close')" />
    <div class="sheet" role="dialog" aria-modal="true" :aria-label="expense ? '编辑支出' : '记一笔'">
      <div class="sheet-head">
        <span class="sheet-title">{{ expense ? '编辑支出' : '记一笔' }}</span>
        <PTag v-if="isRefund" tone="danger">退款冲销</PTag>
        <PTag v-if="periods" tone="accent">{{ periods }} 期免息</PTag>
        <span style="margin-left: auto" />
        <PIconBtn v-if="expense" :icon="Trash2" label="删除" @click="remove" />
        <PIconBtn :icon="X" label="关闭" @click="emit('close')" />
      </div>

      <div class="sheet-body">
        <!-- 金额显示 -->
        <div class="amt-display">
          <span class="a-cur">{{ isRefund ? '-¥' : '¥' }}</span>
          <span class="a-val">{{ amount || '0.00' }}</span>
          <span class="a-tail">{{ payment?.name ?? '' }}</span>
        </div>

        <div class="g2" style="gap: 8px">
          <button type="button" class="sheet-cell" @click="catOpen = true">
            <PCatIcon :category-id="categoryId" :size="28" />
            <span style="min-width: 0">
              <span class="lbl" style="display: block">分类</span>
              <span class="val">{{ categoryLabel }}</span>
            </span>
            <ChevronRight :size="14" style="margin-left: auto; color: var(--ink-3)" />
          </button>

          <label class="sheet-cell" style="cursor: pointer">
            <input
              v-model="spendDate"
              type="date"
              :max="today"
              aria-label="消费日期"
              style="border: 0; background: transparent; padding: 0; width: 100%; font-size: 12.5px; font-weight: 600; color: var(--ink)"
            />
          </label>
        </div>

        <button type="button" class="sheet-cell" @click="payOpen = true">
          <PPayIcon :name="payment?.name ?? ''" :size="18" />
          <span style="min-width: 0">
            <span class="lbl" style="display: block">支付方式</span>
            <span class="val">
              {{ payment?.name ?? '选择支付方式' }}
              <span v-if="isCredit" class="tiny muted">· 信用卡</span>
            </span>
          </span>
          <ChevronRight :size="14" style="margin-left: auto; color: var(--ink-3)" />
        </button>

        <input v-model="note" class="input" placeholder="备注（选填）" aria-label="备注" />

        <!-- 退款 -->
        <div class="set-row" style="padding: 6px 0">
          <span class="set-ic"><RotateCcw :size="15" /></span>
          <div class="set-body">
            <div class="set-t">退款（负数冲销）</div>
            <div class="set-s">
              {{ periods ? '分期中的消费不能标记退款' : '退款不使用「收入」，直接以负数金额冲减本期支出' }}
            </div>
          </div>
          <PSwitch
            :checked="isRefund"
            label="退款"
            @change="(v) => { isRefund = v; if (v) periods = null; }"
          />
        </div>

        <!-- 分期 -->
        <div class="set-row" style="padding: 6px 0">
          <span class="set-ic"><Layers :size="15" /></span>
          <div class="set-body">
            <div class="set-t">分期（仅信用卡 · 非退款）</div>
            <div class="set-s">
              {{ isCredit ? '免息分期，每期金额自动四舍五入' : '当前支付方式不支持分期，请先切换到信用卡' }}
            </div>
          </div>
          <div class="split">
            <select
              v-if="periods"
              v-model.number="periods"
              class="input"
              style="width: 84px; min-height: 32px; padding: 4px 8px"
              aria-label="分期期数"
            >
              <option :value="3">3 期</option>
              <option :value="6">6 期</option>
              <option :value="12">12 期</option>
              <option :value="24">24 期</option>
            </select>
            <PSwitch
              :checked="periods !== null"
              label="分期"
              @change="(v) => {
                if (v && !isCredit) { toast.show('切到信用卡后才能分期'); return; }
                if (v && isRefund) isRefund = false;
                periods = v ? 12 : null;
              }"
            />
          </div>
        </div>

        <!-- 预览 -->
        <div class="preview-box">
          金额预览（不落库先算）：<br />
          <template v-if="isCredit">
            账期归属 <b>{{ previewDates?.repaymentDate ?? '—' }}</b> 还款日 · 本次计入
            <b>{{ formatYuan(effectiveCents) }}</b>
            <span v-if="periods"> · 每期约 <b>{{ formatYuan(perPeriodCents) }}</b>，共 {{ periods }} 期</span>
          </template>
          <template v-else>
            即时入账，消费日期 <b>{{ spendDate }}</b>
          </template>
        </div>

        <p v-if="errorMessage" class="tiny" style="color: var(--danger); margin: 0">{{ errorMessage }}</p>

        <!-- 键盘 -->
        <div class="keypad">
          <div class="paycol">
            <button
              v-for="p in dict.usablePaymentMethods.slice(0, 6)"
              :key="p.id"
              type="button"
              class="pay-key"
              :class="{ 'is-on': paymentId === p.id }"
              :title="p.name"
              @click="paymentId = p.id"
            >
              <PPayIcon :name="p.name" :size="15" />
              <span style="overflow: hidden; text-overflow: ellipsis; white-space: nowrap; width: 100%; text-align: center">
                {{ p.name.slice(0, 4) }}
              </span>
            </button>
          </div>
          <div class="keys">
            <template v-for="k in KEYS" :key="k">
              <button v-if="k === 'OK'" type="button" class="key key--ok" @click="save">完成</button>
              <button
                v-else
                type="button"
                class="key"
                :class="{ 'key--fn': k === 'B' || k === 'C' }"
                @click="press(k)"
              >
                <template v-if="k === 'B'">←</template>
                <template v-else-if="k === 'C'">清空</template>
                <template v-else>{{ k }}</template>
              </button>
            </template>
          </div>
        </div>
      </div>

      <div class="sheet-foot">
        <PBtn variant="primary" :icon="Check" style="flex: 1 1 auto" :disabled="saving" @click="save">
          {{ saving ? '保存中…' : expense ? '保存修改' : '记下这笔' }}
        </PBtn>
        <PBtn variant="ghost" @click="emit('close')">取消</PBtn>
      </div>
    </div>

    <!-- 分类选择：左一级导航 + 右二级网格 -->
    <template v-if="catOpen">
      <div class="picker-mask" @click="catOpen = false" />
      <div class="picker" role="dialog" aria-modal="true" aria-label="选择分类">
        <div class="picker-head">
          <span class="modal-title">选择分类</span>
          <span class="tiny muted mono" style="margin-left: auto">
            一级 {{ dict.rootCategories.length }} / 二级
            {{ dict.rootCategories.reduce((a, r) => a + r.children.length, 0) }}
          </span>
          <PIconBtn :icon="X" label="关闭" @click="catOpen = false" />
        </div>
        <div class="picker-body">
          <div class="picker-rail">
            <button
              v-for="root in dict.rootCategories"
              :key="root.id"
              type="button"
              class="picker-rail-btn"
              :class="{ 'is-on': railId === root.id }"
              @click="railId = root.id"
            >
              <PCatIcon :category-id="root.id" :size="20" />
              {{ root.name }}
            </button>
          </div>
          <div class="picker-grid">
            <button
              v-for="child in selectableChildren"
              :key="child.id"
              type="button"
              class="picker-cell"
              :class="{ 'is-on': categoryId === child.id }"
              @click="pickCategory(child.id)"
            >
              <PCatIcon :category-id="child.id" :size="20" />
              <span style="min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap">
                {{ child.name }}
              </span>
            </button>
          </div>
        </div>
      </div>
    </template>

    <!-- 支付方式：纵向列表（带账期说明） -->
    <template v-if="payOpen">
      <div class="picker-mask" @click="payOpen = false" />
      <div class="picker" role="dialog" aria-modal="true" aria-label="选择支付方式" style="width: min(440px, calc(100vw - 20px))">
        <div class="picker-head">
          <span class="modal-title">支付方式</span>
          <span class="tiny muted mono" style="margin-left: auto">账期随卡</span>
          <PIconBtn :icon="X" label="关闭" @click="payOpen = false" />
        </div>
        <div style="padding: 12px; overflow-y: auto">
          <div class="pay-list">
            <button
              v-for="p in dict.usablePaymentMethods"
              :key="p.id"
              type="button"
              class="pay-item"
              :class="{ 'is-on': paymentId === p.id }"
              @click="pickPayment(p.id)"
            >
              <span class="set-ic"><PPayIcon :name="p.name" :size="16" /></span>
              <span style="flex: 1 1 auto; min-width: 0">
                <span style="display: block; font-size: 12.5px; font-weight: 600">{{ p.name }}</span>
                <span class="tiny muted" style="display: block; margin-top: 2px">
                  {{ p.type === 'credit' ? `信用卡 · ${p.billingDay ?? '—'} 日账单 / ${p.repaymentDay ?? '—'} 日还款` : '即时结算' }}
                </span>
              </span>
              <Check v-if="paymentId === p.id" :size="16" style="color: var(--accent)" />
            </button>
          </div>
        </div>
      </div>
    </template>
  </template>
</template>

<style scoped>
/* 只补原型没覆盖的两处：金额显示的字号与键盘的支付列宽度 */
.amt-display .a-cur {
  font-size: 20px;
  align-self: flex-start;
  margin-top: 6px;
}
.amt-display .a-val {
  font-size: clamp(30px, 7vw, 44px);
}
.paycol {
  display: grid;
  grid-template-columns: 1fr;
  gap: 6px;
}
</style>
