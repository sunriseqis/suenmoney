<script setup lang="ts">
/**
 * 计划页：房贷与免息分期。
 *
 * 页面结构按「先处理、再管理」排序：
 *   1. 该处理了 —— 提醒日已到的待办（含逾期），带一键确认
 *   2. 我的计划 —— 进度、下一期、改计划、终止
 *   3. 新建计划 —— 折叠表单
 *
 * 「确认」在逾期时会先让用户选实际付款日 —— 这是刻意的：逾期确认时
 * 用户往往需要回忆到底哪天付的，但**选择只影响记录上的实际付款日，
 * 不改报表月份归属**（归属以计划里的还款日为准，补点确认不该挪动历史报表）。
 *
 * ## 期次行的「撤销」与「恢复」（第三轮返工）
 *
 * 「已入账」不再是一条单行道：期次行可以**撤销**（撤掉这一期的支出，回到待办），
 * 「已跳过」也可以**恢复**（回待办列表）。两者都只在这一页提供 ——
 * 仪表盘是「该处理了」的即时视图，撤销是回看既往；放在一起会让两类操作同权重，
 * 而其中一个要动已经记账的钱。
 *
 * 入口做两套，走同一段逻辑：**左滑 60% 露出动作**（触屏）+
 * **行内小按钮**（桌面端没有左滑手势，只有左滑等于桌面端无路可走）。
 */
import { computed, onMounted, ref, watch } from 'vue';

import {
  ApiError,
  plans as plansApi,
  type Plan,
  type PlanSource,
  type PlanTodo,
} from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import ChipButton from '@/components/ChipButton.vue';
import PaymentIcon from '@/components/PaymentIcon.vue';
import PlanTodoCard from '@/components/PlanTodoCard.vue';
import { useAuthStore } from '@/stores/auth';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { useUiStore } from '@/stores/ui';
import { formatMonthDay, formatMonthLabel, todayLocal } from '@/utils/dates';
import { formatCents, formatYuan, parseYuanToCents } from '@/utils/money';
/**
 * hideTodos：嵌入设置页时置 true，隐藏「该处理了」。
 * 首页已经完整展示待办，设置里的计划只负责**管理**（新建/编辑/规则）。
 * 同一份提醒在两个页面全量重复没有逻辑，只会让人怀疑两边是不是两份数据。
 */
defineProps<{ hideTodos?: boolean }>();


const auth = useAuthStore();
const dict = useDictionariesStore();
const plansStore = usePlansStore();
const ui = useUiStore();

const busy = ref(false);
const errorMessage = ref<string | null>(null);
const notice = ref<string | null>(null);

/** 按客户端本地时区算出的「今天」，用于新建计划表单的日期默认值 */
const today = todayLocal();

function clearMessages(): void {
  errorMessage.value = null;
  notice.value = null;
}

function report(error: unknown, fallback: string): void {
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
  notice.value = null;
}

// ---- 待办确认 -------------------------------------------------------------
// 确认与跳过的交互（含「逾期时先选实际付款日」）都在 PlanTodoCard 里，
// 仪表盘与计划页共用同一份实现 —— 各写一遍的话，那个细节迟早只在一边生效。

/** 卡片处理完一条待办后：通知全站刷新，并同步展开中的计划详情 */
async function onTodoChanged(): Promise<void> {
  clearMessages();
  ui.markDataChanged();

  if (expandedPlanId.value === null) return;

  try {
    planTodos.value = (await plansApi.get(expandedPlanId.value)).todos;
  } catch (error) {
    report(error, '计划详情刷新失败');
  }
}

/**
 * 在计划详情里直接入账。
 *
 * 用途是**提前还款**：待办卡片只显示「提醒日已到」的期，所以在到期之前
 * 计划详情是唯一的入口。这里不做逾期选日期那套（提前付款不存在逾期），
 * 真逾期了到上面的待办卡片处理。
 */
async function confirmFromDetail(todo: PlanTodo): Promise<void> {
  clearMessages();
  busy.value = true;

  try {
    await plansStore.confirmTodo(todo.id);
    ui.markDataChanged();
    planTodos.value = (await plansApi.get(todo.planId)).todos;
    notice.value = `已按计划日期入账「${todo.planName}」第 ${todo.periodSeq} 期`;
  } catch (error) {
    report(error, '确认失败');
  } finally {
    busy.value = false;
  }
}

// ---- 期次行的撤销 / 恢复 ---------------------------------------------------

/**
 * 左滑露出的位移比例。与模板里动作层的宽度是同一个数字：
 * 动作层占 `SWIPE_REVEAL * 100%`，前景行左移同样的比例，正好把它让出来。
 * 做成常量而不是两处各写一遍 `60%`，否则改一处就会出现「露出 60% 但只移了 50%」的白边。
 */
const SWIPE_REVEAL_PERCENT = 60;
/** 判定为「左滑」而不是「上下滚动」的最小横向位移 */
const SWIPE_TRIGGER_PX = 24;

const swipedTodoId = ref<string | null>(null);

let swipeTodoId: string | null = null;
let swipeStartX = 0;
let swipeStartY = 0;
let swipeTracking = false;

function onRowPointerDown(todo: PlanTodo, event: PointerEvent): void {
  // 只有可撤销 / 可恢复的行才有左滑语义，其余行完全不动
  if (todo.status !== 'confirmed' && todo.status !== 'skipped') return;

  swipeTodoId = todo.id;
  swipeStartX = event.clientX;
  swipeStartY = event.clientY;
  swipeTracking = true;
}

function onRowPointerMove(event: PointerEvent): void {
  if (!swipeTracking) return;

  const dx = event.clientX - swipeStartX;
  const dy = event.clientY - swipeStartY;

  /**
   * 纵向意图更强就放弃本次跟踪，并且**不再重新开启** ——
   * 否则在一个最多 600 期、`max-h-64 overflow-y-auto` 的列表里上下滚动，
   * 手指的横向漂移会一路误开滑动动作。
   * 判断放在第一段位移上就定生死，不做「再等等看」的抖动容忍，
   * 因为一旦开始滚动就再也没有可信的横向信号了。
   */
  if (Math.abs(dy) > Math.abs(dx)) {
    swipeTracking = false;
    return;
  }

  if (dx <= -SWIPE_TRIGGER_PX) {
    swipedTodoId.value = swipeTodoId;
    swipeTracking = false;
  } else if (dx >= SWIPE_TRIGGER_PX) {
    swipedTodoId.value = null;
    swipeTracking = false;
  }
}

function onRowPointerUp(): void {
  swipeTracking = false;
}

function closeSwipe(): void {
  swipedTodoId.value = null;
}

/**
 * 撤销一笔已入账的期次。
 *
 * **跨月先警告**：这笔支出的月份归属锚在 `repaymentDate`（与报表同源），
 * 若那一期不在本月，撤销会让**那个月**的合计当场变小 —— 一个已经看过、
 * 已经对过账的数字变了，用户多半会以为数据坏了。先说清楚金额与月份再动手。
 *
 * 用原生 `confirm` 而不是自建弹层：这是本项目里唯一一处「不可撤回的破坏性操作」提示，
 * 为它引入一套弹层组件、焦点陷阱、Esc 处理不划算；原生确认框在移动端 WebView 里
 * 也是系统级的，反而更醒目。
 */
async function revertTodo(todo: PlanTodo): Promise<void> {
  clearMessages();

  const month = todo.repaymentDate.slice(0, 7);
  if (month !== todayLocal().slice(0, 7)) {
    const confirmed = window.confirm(
      `这笔已计入 ${formatMonthLabel(month)}。撤销后该月合计将减少 ${formatYuan(todo.amountCents)}，`
        + `「${todo.planName}」第 ${todo.periodSeq} 期回到待办。确定撤销吗？`,
    );
    if (!confirmed) return;
  }

  closeSwipe();
  busy.value = true;
  try {
    await plansStore.revertTodo(todo.id);
    ui.markDataChanged();
    planTodos.value = (await plansApi.get(todo.planId)).todos;
    notice.value = `已撤销「${todo.planName}」第 ${todo.periodSeq} 期的入账，这一期回到待办（不会自动入账）`;
  } catch (error) {
    report(error, '撤销失败');
  } finally {
    busy.value = false;
  }
}

/** 恢复一个被跳过的期次。它同样不会再自动入账 —— 要用户自己确认。 */
async function restoreTodo(todo: PlanTodo): Promise<void> {
  clearMessages();
  closeSwipe();
  busy.value = true;
  try {
    await plansStore.restoreTodo(todo.id);
    ui.markDataChanged();
    planTodos.value = (await plansApi.get(todo.planId)).todos;
    notice.value = `「${todo.planName}」第 ${todo.periodSeq} 期已恢复为待确认`;
  } catch (error) {
    report(error, '恢复失败');
  } finally {
    busy.value = false;
  }
}

// ---- 计划详情 -------------------------------------------------------------

const expandedPlanId = ref<string | null>(null);
const planTodos = ref<PlanTodo[]>([]);
const sortedPlanTodos = computed(() => [...planTodos.value].sort((a, b) => a.periodSeq - b.periodSeq));
const detailLoading = ref(false);

async function togglePlan(plan: Plan): Promise<void> {
  clearMessages();

  if (expandedPlanId.value === plan.id) {
    expandedPlanId.value = null;
    planTodos.value = [];
    return;
  }

  expandedPlanId.value = plan.id;
  detailLoading.value = true;
  try {
    planTodos.value = (await plansApi.get(plan.id)).todos;
  } catch (error) {
    report(error, '计划详情加载失败');
  } finally {
    detailLoading.value = false;
  }
}

// ---- 改计划 ---------------------------------------------------------------

const editingPlanId = ref<string | null>(null);
const editForm = ref({ amountYuan: '', remainingPeriods: '', remindDaysBefore: '', autoPost: false });

function startEdit(plan: Plan): void {
  clearMessages();
  editingPlanId.value = plan.id;
  editForm.value = {
    amountYuan: formatCents(plan.amountCents).replace(/,/g, '').replace(/\.00$/, ''),
    remainingPeriods: String(plan.progress.pendingCount),
    remindDaysBefore: String(plan.remindDaysBefore),
    autoPost: plan.autoPost,
  };
}

async function submitEdit(plan: Plan): Promise<void> {
  clearMessages();

  const amountCents = parseYuanToCents(editForm.value.amountYuan);
  if (amountCents <= 0) {
    errorMessage.value = '每期金额必须大于 0';
    return;
  }

  const remainingPeriods = Number(editForm.value.remainingPeriods);
  if (!Number.isInteger(remainingPeriods) || remainingPeriods < 0) {
    errorMessage.value = '剩余期数必须是不小于 0 的整数（0 = 只保留已还的历史）';
    return;
  }

  busy.value = true;
  try {
    await plansApi.update(plan.id, {
      amountCents,
      remainingPeriods,
      remindDaysBefore: Number(editForm.value.remindDaysBefore),
      autoPost: editForm.value.autoPost,
    });

    editingPlanId.value = null;
    notice.value = `已按新参数重算「${plan.name}」的未执行期数，已还的历史不受影响`;
    await plansStore.refresh();
    planTodos.value = (await plansApi.get(plan.id)).todos;
    ui.markDataChanged();
  } catch (error) {
    report(error, '修改计划失败');
  } finally {
    busy.value = false;
  }
}

async function submitEnd(plan: Plan): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await plansStore.endPlan(plan.id);
    notice.value = `已终止「${plan.name}」，未执行的期数已作废，已还的历史保留`;
    expandedPlanId.value = null;
    ui.markDataChanged();
  } catch (error) {
    report(error, '终止计划失败');
  } finally {
    busy.value = false;
  }
}

async function submitDelete(plan: Plan): Promise<void> {
  if (!confirm(`确定彻底删除计划「${plan.name}」吗？已生成的历史记账记录将完整保留，该计划及相关待办将被移除。`)) {
    return;
  }
  clearMessages();
  busy.value = true;
  try {
    await plansStore.deletePlan(plan.id);
    notice.value = `已删除计划「${plan.name}」`;
    if (expandedPlanId.value === plan.id) {
      expandedPlanId.value = null;
    }
    ui.markDataChanged();
  } catch (error) {
    report(error, '删除计划失败');
  } finally {
    busy.value = false;
  }
}

// ---- 新建计划 -------------------------------------------------------------

const showCreate = ref(false);
const createForm = ref({
  source: 'manual' as PlanSource,
  name: '',
  categoryId: '',
  paymentMethodId: '',
  amountYuan: '',
  totalYuan: '',
  purchaseDate: today,
  periods: '',
  firstDueDate: today,
  remindDaysBefore: '3',
  autoPost: false,
});

/** 分期的每期金额由服务端拆（最后一期补差），这里只做预览 */
const installmentPreview = computed(() => {
  if (createForm.value.source !== 'installment') return null;

  const total = parseYuanToCents(createForm.value.totalYuan);
  const periods = Number(createForm.value.periods);
  if (total <= 0 || !Number.isInteger(periods) || periods < 1) return null;
  if (total < periods) return '总额太小，无法分成这么多期';

  const base = Math.floor(total / periods);
  const last = total - base * (periods - 1);
  return `每期 ${formatYuan(base)}，最后一期 ${formatYuan(last)}（合计恰好等于原价）`;
});

function resetCreateForm(): void {
  const root = dict.rootCategories[0] ?? null;
  createForm.value = {
    source: 'manual',
    name: '',
    categoryId: root === null ? '' : (dict.selectableChildren(root)[0]?.id ?? ''),
    paymentMethodId: dict.usablePaymentMethods[0]?.id ?? '',
    amountYuan: '',
    totalYuan: '',
    purchaseDate: today,
    periods: '',
    firstDueDate: today,
    remindDaysBefore: '3',
    autoPost: false,
  };
}

async function submitCreate(): Promise<void> {
  clearMessages();

  const periods = Number(createForm.value.periods);
  if (!Number.isInteger(periods) || periods < 1 || periods > 600) {
    errorMessage.value = '期数必须是 1–600 之间的整数';
    return;
  }
  if (createForm.value.categoryId === '' || createForm.value.paymentMethodId === '') {
    errorMessage.value = '请选择分类与支付方式';
    return;
  }

  const payload: Parameters<typeof plansApi.create>[0] = {
    name: createForm.value.name.trim(),
    categoryId: createForm.value.categoryId,
    paymentMethodId: createForm.value.paymentMethodId,
    source: createForm.value.source,
    periods,
    firstDueDate: createForm.value.firstDueDate,
    remindDaysBefore: Number(createForm.value.remindDaysBefore),
    autoPost: createForm.value.autoPost,
  };

  if (createForm.value.source === 'installment') {
    payload.totalAmountCents = parseYuanToCents(createForm.value.totalYuan);
    payload.purchaseDate = createForm.value.purchaseDate;
  } else {
    payload.amountCents = parseYuanToCents(createForm.value.amountYuan);
  }

  busy.value = true;
  try {
    await plansApi.create(payload);
    showCreate.value = false;
    resetCreateForm();
    notice.value = '计划已创建，各期待办已生成，提醒日到了会出现在上面';
    await plansStore.refresh();
  } catch (error) {
    report(error, '创建计划失败');
  } finally {
    busy.value = false;
  }
}

// ---- 生命周期 -------------------------------------------------------------

onMounted(async () => {
  await dict.load();
  resetCreateForm();
  try {
    const settled = await plansStore.refresh();
    if (settled > 0) {
      notice.value = `已自动入账 ${settled} 笔到期的支出`;
      ui.markDataChanged();
    }
  } catch (error) {
    report(error, '加载失败');
  }
});

// 在别处（如仪表盘）确认了待办，回到这一页要跟着更新
watch(() => ui.dataVersion, () => void plansStore.refresh());
</script>

<template>
  <section aria-label="计划">
    <div class="flex items-baseline justify-between">
      <h2 class="label-cn">计划</h2>
      <button
        type="button"
        class="text-xs font-semibold text-primary-text hover:underline"
        @click="showCreate = !showCreate"
      >
        {{ showCreate ? '取消' : '新建' }}
      </button>
    </div>
      <p
        v-if="errorMessage !== null"
        class="rounded-md bg-surface px-4 py-3 text-sm text-danger-text lg:mb-8"
      >
        {{ errorMessage }}
      </p>
      <p
        v-if="notice !== null"
        class="rounded-md bg-surface px-4 py-3 text-sm text-secondary-text lg:mb-8"
      >
        {{ notice }}
      </p>

      <!--
        新建计划表单独占满一行，不进栅格：它是一张表单，字段横向铺开才好填，
        塞进半栏会让「金额 / 支付方式 / 首期日期」挤成两行。
      -->
      <section v-if="showCreate" class="lg:mb-8" aria-label="新建计划">
        <h2 class="label-cn">新建计划</h2>

        <form class="mt-3 space-y-3" @submit.prevent="submitCreate">
          <div class="flex gap-2">
            <ChipButton :active="createForm.source === 'manual'" @click="createForm.source = 'manual'">
              固定支出（房贷、房租）
            </ChipButton>
            <ChipButton
              :active="createForm.source === 'installment'"
              @click="createForm.source = 'installment'"
            >
              免息分期
            </ChipButton>
          </div>

          <input
            v-model="createForm.name"
            placeholder="名称，如「房贷」「京东分期-手机」"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />

          <div class="no-scrollbar flex gap-2 overflow-x-auto pb-1">
            <ChipButton
              v-for="root in dict.rootCategories"
              :key="root.id"
              :active="createForm.categoryId === root.id"
              @click="createForm.categoryId = dict.selectableChildren(root)[0]?.id ?? ''"
            >
              {{ root.name }}
            </ChipButton>
          </div>

          <div class="flex flex-wrap gap-2">
            <ChipButton
              v-for="method in dict.usablePaymentMethods"
              :key="method.id"
              :active="createForm.paymentMethodId === method.id"
              @click="createForm.paymentMethodId = method.id"
            >
              <span class="inline-flex items-center gap-1.5">
                <PaymentIcon :name="method.name" :icon="method.icon" :size="14" />
                <span>{{ method.name }}</span>
              </span>
            </ChipButton>
          </div>

          <div v-if="createForm.source === 'installment'" class="space-y-2">
            <label class="label-cn" for="plan-total">消费原价</label>
            <input
              id="plan-total"
              v-model="createForm.totalYuan"
              inputmode="decimal"
              placeholder="如 6000"
              class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
            />
            <label class="label-cn" for="plan-purchase">消费日</label>
            <input
              id="plan-purchase"
              v-model="createForm.purchaseDate"
              type="date"
              class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink"
            />
            <p v-if="installmentPreview !== null" class="text-xs text-ink-muted">
              {{ installmentPreview }}
            </p>
          </div>

          <template v-else>
            <label class="label-cn" for="plan-amount">每期金额</label>
            <input
              id="plan-amount"
              v-model="createForm.amountYuan"
              inputmode="decimal"
              placeholder="如 10000"
              class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
            />
          </template>

          <div class="flex gap-2">
            <div class="min-w-0 flex-1">
              <label class="label-cn" for="plan-periods">期数</label>
              <input
                id="plan-periods"
                v-model="createForm.periods"
                inputmode="numeric"
                placeholder="房贷 240"
                class="mt-1 w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
              />
            </div>
            <div class="min-w-0 flex-1">
              <label class="label-cn" for="plan-first-due">首期还款日</label>
              <input
                id="plan-first-due"
                v-model="createForm.firstDueDate"
                type="date"
                class="mt-1 w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink"
              />
            </div>
          </div>

          <div>
            <label class="label-cn" for="plan-remind">提前几天提醒</label>
            <input
              id="plan-remind"
              v-model="createForm.remindDaysBefore"
              inputmode="numeric"
              class="mt-1 w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink"
            />
          </div>

          <button
            type="button"
            class="flex w-full items-center gap-2 rounded-sm bg-surface px-4 py-3 text-left text-sm"
            @click="createForm.autoPost = !createForm.autoPost"
          >
            <span
              class="inline-block size-4 shrink-0 rounded-sm"
              :class="createForm.autoPost ? 'bg-primary-fill' : 'bg-sunken'"
            />
            <span class="min-w-0 flex-1">
              到期自动入账
              <span class="block text-xs text-ink-muted">
                不开就手动点确认；开了则到期时自动生成支出，你不会看到待办
              </span>
            </span>
          </button>

          <button
            type="submit"
            :disabled="busy"
            class="w-full rounded-md bg-primary-fill py-3.5 text-sm font-bold text-on-primary transition-transform duration-200 active:scale-95 disabled:opacity-40"
          >
            {{ busy ? '创建中…' : '创建计划' }}
          </button>
        </form>
      </section>

      <!--
        桌面双栏：左「该处理了」（要动手），右「我的计划」（看进度）。
        与首页同一套分栏依据，用户在两个页面之间的心智模型是一致的。
      -->
      <div
      class="lg:grid lg:items-start lg:gap-8"
      :class="hideTodos ? '' : 'lg:grid-cols-2'"
    >
        <div v-if="!hideTodos">
          <!-- 该处理了 -->
          <section aria-label="待处理的待办">
            <h2 class="label-cn">该处理了</h2>

        <p v-if="plansStore.dueTodos.length === 0" class="mt-3 text-sm text-ink-muted">
          暂时没有到期的支出。到了各计划的提醒日，会出现在这里。
        </p>

        <ul v-else class="mt-3 space-y-3">
          <li v-for="todo in plansStore.dueTodos" :key="todo.id">
            <PlanTodoCard :todo="todo" @changed="onTodoChanged" />
          </li>
        </ul>
      </section>

        </div>

        <div>
          <!-- 计划列表 -->
          <section aria-label="我的计划">
            <h2 class="label-cn">我的计划</h2>

        <p v-if="plansStore.plans.length === 0" class="mt-3 text-sm text-ink-muted">
          还没有计划。房贷、房租、免息分期都可以建成计划，之后每期会自动提醒。
        </p>

        <ul v-else class="mt-3 space-y-3">
          <li v-for="plan in plansStore.plans" :key="plan.id" class="rounded-md bg-surface">
            <button
              type="button"
              class="flex w-full items-center gap-3 p-4 text-left"
              @click="togglePlan(plan)"
            >
              <!-- 身份物：分类图标。与待办卡同一条语言，两处不再是两种卡片 -->
              <span class="grid h-[34px] w-[34px] shrink-0 place-items-center rounded-sm bg-canvas">
                <CategoryIcon :category-id="plan.categoryId" :size="17" />
              </span>

              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-semibold">
                  {{ plan.name }}
                  <span v-if="plan.state === 'ended'" class="ml-1 text-xs text-ink-muted">
                    （已终止）
                  </span>
                  <span v-else-if="plan.autoPost" class="ml-1 text-xs text-secondary-text">
                    自动入账
                  </span>
                </span>
                <span class="block text-xs text-ink-muted">
                  每期 {{ formatYuan(plan.amountCents) }} ·
                  已还 {{ plan.progress.paidCount }} 期 · 剩余 {{ plan.progress.pendingCount }} 期
                </span>
                <span v-if="plan.progress.nextDueDate !== null" class="block text-xs text-ink-muted">
                  下一期 {{ formatMonthDay(plan.progress.nextDueDate) }}
                </span>
              </span>
              <span class="shrink-0 text-ink-muted">{{ expandedPlanId === plan.id ? '▾' : '▸' }}</span>
            </button>

            <!-- 展开：进度 + 待办 + 操作 -->
            <div v-if="expandedPlanId === plan.id" class="border-t border-line p-4">
              <dl class="grid grid-cols-2 gap-3 text-xs">
                <div>
                  <dt class="text-ink-muted">已付</dt>
                  <dd class="mt-0.5 text-sm font-semibold">
                    {{ formatYuan(plan.progress.paidCents) }}
                  </dd>
                </div>
                <div>
                  <dt class="text-ink-muted">剩余未付</dt>
                  <dd class="mt-0.5 text-sm font-semibold">
                    {{ formatYuan(plan.progress.pendingCents) }}
                  </dd>
                </div>
                <div v-if="plan.totalAmountCents !== null">
                  <dt class="text-ink-muted">消费原价</dt>
                  <dd class="mt-0.5 text-sm font-semibold">
                    {{ formatYuan(plan.totalAmountCents) }}
                  </dd>
                </div>
                <div v-if="plan.progress.expectedEndDate !== null">
                  <dt class="text-ink-muted">预计结清</dt>
                  <dd class="mt-0.5 text-sm font-semibold">
                    {{ formatMonthDay(plan.progress.expectedEndDate) }}
                  </dd>
                </div>
              </dl>

              <p v-if="detailLoading" class="mt-4 text-xs text-ink-muted">加载中…</p>

              <ul v-else class="mt-4 max-h-64 space-y-1 overflow-y-auto">
                <li
                  v-for="todo in sortedPlanTodos"
                  :key="todo.id"
                  class="relative overflow-hidden rounded-sm"
                >
                  <!--
                    左滑露出的动作层。宽度与 SWIPE_REVEAL_PERCENT 是同一个数字：
                    前景行左移同样的比例，正好把它完整让出来，不会留白边。
                  -->
                  <div
                    v-if="todo.status === 'confirmed' || todo.status === 'skipped'"
                    class="absolute inset-y-0 right-0 flex items-stretch overflow-hidden rounded-sm"
                    :style="{ width: `${SWIPE_REVEAL_PERCENT}%` }"
                  >
                    <button
                      v-if="todo.status === 'confirmed'"
                      type="button"
                      :disabled="busy"
                      class="flex-1 bg-danger-fill text-xs font-bold text-on-danger transition-opacity duration-200 disabled:opacity-40"
                      @click="revertTodo(todo)"
                    >
                      撤销入账
                    </button>
                    <button
                      v-else
                      type="button"
                      :disabled="busy"
                      class="flex-1 bg-canvas text-xs font-bold text-primary-text transition-opacity duration-200 disabled:opacity-40"
                      @click="restoreTodo(todo)"
                    >
                      恢复
                    </button>
                  </div>

                  <!--
                    前景行必须有**不透明**底色（bg-surface，与计划卡一致）：
                    否则左移之后背后的动作层会从文字间隙里透出来。
                    `touch-pan-y` 让纵向滚动仍然交给浏览器，横向手势才落到我们手里 ——
                    不设它的话，触屏上第一次 pointermove 就可能触发纵向滚动并把指针序列取消掉。
                  -->
                  <div
                    class="relative flex touch-pan-y items-center gap-3 bg-surface px-2 py-1.5 text-xs transition-transform duration-200"
                    :style="{
                      transform:
                        swipedTodoId === todo.id
                          ? `translateX(-${SWIPE_REVEAL_PERCENT}%)`
                          : 'translateX(0)',
                    }"
                    @pointerdown="onRowPointerDown(todo, $event)"
                    @pointermove="onRowPointerMove($event)"
                    @pointerup="onRowPointerUp()"
                    @pointercancel="onRowPointerUp()"
                  >
                    <span class="w-10 shrink-0 text-ink-muted">第{{ todo.periodSeq }}期</span>
                    <span class="w-16 shrink-0 text-ink-muted">
                      {{ formatMonthDay(todo.repaymentDate) }}
                    </span>
                    <span class="min-w-0 flex-1 text-right">{{ formatYuan(todo.amountCents) }}</span>
                    <span
                      class="w-14 shrink-0 text-right"
                      :class="{
                        'text-secondary-text': todo.status === 'confirmed',
                        'text-ink-muted': todo.status === 'pending' || todo.status === 'skipped',
                      }"
                    >
                      {{
                        todo.status === 'confirmed'
                          ? '已入账'
                          : todo.status === 'skipped'
                            ? '已跳过'
                            : todo.status === 'cancelled'
                              ? '已作废'
                              : '待确认'
                      }}
                    </span>

                    <!-- 提前还款的入口：待办卡片只显示提醒日已到的期，到不了这里 -->
                    <button
                      v-if="todo.status === 'pending'"
                      type="button"
                      :disabled="busy"
                      class="shrink-0 rounded-sm bg-canvas px-2 py-1 text-[11px] font-semibold text-primary-text transition-colors duration-200 hover:bg-sunken disabled:opacity-40"
                      @click="confirmFromDetail(todo)"
                    >
                      入账
                    </button>

                    <!--
                      桌面端的行内等价入口。`lg:` 才显示：桌面没有左滑手势，
                      只留滑动等于在这块屏幕上没有撤销路径。两者调的是同一个函数。
                    -->
                    <button
                      v-else-if="todo.status === 'confirmed'"
                      type="button"
                      :disabled="busy"
                      class="hidden shrink-0 rounded-sm bg-canvas px-2 py-1 text-[11px] font-semibold text-danger-text transition-colors duration-200 hover:bg-sunken disabled:opacity-40 lg:inline-flex"
                      @click="revertTodo(todo)"
                    >
                      撤销
                    </button>
                    <button
                      v-else-if="todo.status === 'skipped'"
                      type="button"
                      :disabled="busy"
                      class="hidden shrink-0 rounded-sm bg-canvas px-2 py-1 text-[11px] font-semibold text-primary-text transition-colors duration-200 hover:bg-sunken disabled:opacity-40 lg:inline-flex"
                      @click="restoreTodo(todo)"
                    >
                      恢复
                    </button>
                  </div>
                </li>
              </ul>

              <!-- 改计划 / 终止（仅创建者） -->
              <template v-if="plan.ownerId === auth.user?.id">
                <div v-if="editingPlanId === plan.id" class="mt-4 space-y-2">
                  <div class="flex gap-2">
                    <div class="min-w-0 flex-1">
                      <label class="label-cn" :for="`edit-amount-${plan.id}`">每期金额</label>
                      <input
                        :id="`edit-amount-${plan.id}`"
                        v-model="editForm.amountYuan"
                        inputmode="decimal"
                        class="mt-1 w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
                      />
                    </div>
                    <div class="min-w-0 flex-1">
                      <label class="label-cn" :for="`edit-periods-${plan.id}`">剩余期数</label>
                      <input
                        :id="`edit-periods-${plan.id}`"
                        v-model="editForm.remainingPeriods"
                        inputmode="numeric"
                        class="mt-1 w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
                      />
                    </div>
                  </div>

                  <div>
                    <label class="label-cn" :for="`edit-remind-${plan.id}`">提前几天提醒</label>
                    <input
                      :id="`edit-remind-${plan.id}`"
                      v-model="editForm.remindDaysBefore"
                      inputmode="numeric"
                      class="mt-1 w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink"
                    />
                  </div>

                  <button
                    type="button"
                    class="flex w-full items-center gap-2 rounded-sm bg-canvas px-3 py-2.5 text-left text-sm"
                    @click="editForm.autoPost = !editForm.autoPost"
                  >
                    <span
                      class="inline-block size-4 shrink-0 rounded-sm"
                      :class="editForm.autoPost ? 'bg-primary-fill' : 'bg-sunken'"
                    />
                    <span>到期自动入账</span>
                  </button>

                  <p class="text-xs leading-relaxed text-ink-muted">
                    保存会删掉所有未执行的待办并按新参数重建，**已还的期数不受影响**；
                    剩余期数填 0 相当于提前结清（只保留已还的历史）。
                  </p>

                  <div class="flex gap-2">
                    <button
                      type="button"
                      :disabled="busy"
                      class="flex-1 rounded-sm bg-primary-fill py-2.5 text-sm font-bold text-on-primary disabled:opacity-40"
                      @click="submitEdit(plan)"
                    >
                      保存并重算
                    </button>
                    <button
                      type="button"
                      class="rounded-sm bg-canvas px-4 py-2.5 text-sm font-semibold text-ink"
                      @click="editingPlanId = null"
                    >
                      取消
                    </button>
                  </div>
                </div>

                <div v-else class="mt-4 flex gap-2">
                  <button
                    type="button"
                    class="rounded-sm bg-canvas px-4 py-2.5 text-sm font-semibold text-ink hover:bg-sunken transition-colors"
                    @click="startEdit(plan)"
                  >
                    改计划
                  </button>
                  <button
                    v-if="plan.state === 'active'"
                    type="button"
                    :disabled="busy"
                    class="rounded-sm bg-canvas px-4 py-2.5 text-sm font-semibold text-danger-text hover:bg-danger/10 transition-colors disabled:opacity-40"
                    @click="submitEnd(plan)"
                  >
                    终止计划
                  </button>
                  <button
                    v-if="plan.state === 'ended'"
                    type="button"
                    :disabled="busy"
                    class="rounded-sm bg-canvas px-4 py-2.5 text-sm font-semibold text-danger-text hover:bg-danger/10 transition-colors disabled:opacity-40"
                    @click="submitDelete(plan)"
                  >
                    删除计划
                  </button>
                </div>
              </template>
            </div>
          </li>
        </ul>
          </section>
        </div>
      </div>
      </section>
</template>
