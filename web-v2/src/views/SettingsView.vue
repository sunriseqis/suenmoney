<script setup lang="ts">
/**
 * 设置（原型 `views/Settings.jsx` 的四区：账目 / 计划 / 数据 / 家庭）。
 *
 * 分区原则按「用户要干什么」而不是按技术域：
 *   账目 = 日常维护的字典（分类、支付方式）
 *   计划 = 还款计划与待办
 *   数据 = 主题、导入导出、危险操作
 *   家庭 = 成员与我
 *
 * 所有写操作完成后都 `dict.load(true)` 或 `plans.refresh()` 重新拉一次，
 * 不做「本地拼一个假对象塞进列表」—— 那样一旦服务端归一化过字段（比如
 * 二级分类继承父色），前端显示的就和真实数据不一致。
 */
import { CalendarDays, Check, Database, Moon, Pencil, Plus, Sun, Tag, Trash2, Users, Wallet } from '@lucide/vue';
import { computed, onMounted, ref } from 'vue';

import {
  ApiError,
  categories as categoriesApi,
  data as dataApi,
  paymentMethods as paymentsApi,
  plans as plansApi,
  users as usersApi,
  type Category,
  type PaymentMethod,
  type Plan,
  type PlanSource,
  type User,
} from '@/api';
import { useToast } from '@/composables/useToast';
import { useTheme } from '@/composables/useTheme';
import { useDictionariesStore } from '@/stores/dictionaries';
import { usePlansStore } from '@/stores/plans';
import { PBtn, PCard, PEmpty, PField, PIconBtn, PInput, PSeg, PSheet, PSwitch, PTag } from '@/ui';
import { todayLocal } from '@/utils/dates';
import { formatYuan, parseYuanToCents } from '@/utils/money';

const dict = useDictionariesStore();
const plansStore = usePlansStore();
const toast = useToast();
const theme = useTheme();

const today = todayLocal();

const TABS = [
  { value: 'ledger', label: '账目' },
  { value: 'plans', label: '计划' },
  { value: 'data', label: '数据' },
  { value: 'household', label: '家庭' },
] as const;

const tab = ref<'ledger' | 'plans' | 'data' | 'household'>('ledger');
const busy = ref(false);

function errText(error: unknown, fallback: string): string {
  return error instanceof ApiError ? error.message : fallback;
}

// ── 分类 ────────────────────────────────────────────────────────────────────
const catSheet = ref(false);
const catEditing = ref<Category | null>(null);
const catName = ref('');
const catParent = ref<string>('');
const catEnabled = ref(true);

function openCatCreate(): void {
  catEditing.value = null;
  catName.value = '';
  catParent.value = dict.rootCategories[0]?.id ?? '';
  catEnabled.value = true;
  catSheet.value = true;
}

function openCatEdit(cat: Category): void {
  catEditing.value = cat;
  catName.value = cat.name;
  catParent.value = cat.parentId ?? '';
  catEnabled.value = cat.isEnabled;
  catSheet.value = true;
}

async function saveCat(): Promise<void> {
  const name = catName.value.trim();
  if (name === '') {
    toast.show('请填写分类名称');
    return;
  }
  busy.value = true;
  try {
    if (catEditing.value === null) {
      await categoriesApi.create({ name, parentId: catParent.value === '' ? null : catParent.value });
      toast.show('分类已新增');
    } else {
      const editing = catEditing.value;
      await categoriesApi.update(editing.id, { name });
      // 停用/启用单独走 isEnabled，避免一次提交里混两种语义
      if (editing.isEnabled !== catEnabled.value) {
        await categoriesApi.update(editing.id, { isEnabled: catEnabled.value } as never);
      }
      toast.show('分类已更新');
    }
    catSheet.value = false;
    await dict.load(true);
  } catch (error) {
    toast.show(errText(error, '保存失败'));
  } finally {
    busy.value = false;
  }
}

async function toggleCat(cat: Category, next: boolean): Promise<void> {
  try {
    await categoriesApi.update(cat.id, { isEnabled: next } as never);
    await dict.load(true);
  } catch (error) {
    toast.show(errText(error, '操作失败'));
  }
}

async function removeCat(cat: Category): Promise<void> {
  try {
    await categoriesApi.remove(cat.id);
    toast.show('分类已删除');
    await dict.load(true);
  } catch (error) {
    toast.show(errText(error, '该分类已有流水引用，请改为停用'));
  }
}

// ── 支付方式 ────────────────────────────────────────────────────────────────
const paySheet = ref(false);
const payEditing = ref<PaymentMethod | null>(null);
const payName = ref('');
const payType = ref<'credit' | 'cash'>('credit');
const payBilling = ref('1');
const payRepay = ref('20');

function openPayCreate(): void {
  payEditing.value = null;
  payName.value = '';
  payType.value = 'credit';
  payBilling.value = '1';
  payRepay.value = '20';
  paySheet.value = true;
}

function openPayEdit(p: PaymentMethod): void {
  payEditing.value = p;
  payName.value = p.name;
  payType.value = p.type;
  payBilling.value = String(p.billingDay ?? 1);
  payRepay.value = String(p.repaymentDay ?? 20);
  paySheet.value = true;
}

async function savePay(): Promise<void> {
  const name = payName.value.trim();
  if (name === '') {
    toast.show('请填写支付方式名称');
    return;
  }
  busy.value = true;
  try {
    const isCredit = payType.value === 'credit';
    if (payEditing.value === null) {
      await paymentsApi.create({
        name,
        type: payType.value,
        ...(isCredit
          ? { billingDay: Number(payBilling.value), repaymentDay: Number(payRepay.value) }
          : {}),
      });
      toast.show('支付方式已新增');
    } else {
      await paymentsApi.update(payEditing.value.id, {
        name,
        ...(isCredit
          ? { billingDay: Number(payBilling.value), repaymentDay: Number(payRepay.value) }
          : {}),
      });
      toast.show('支付方式已更新');
    }
    paySheet.value = false;
    await dict.load(true);
  } catch (error) {
    toast.show(errText(error, '保存失败'));
  } finally {
    busy.value = false;
  }
}

async function removePay(p: PaymentMethod): Promise<void> {
  try {
    await paymentsApi.remove(p.id);
    toast.show('支付方式已删除');
    await dict.load(true);
  } catch (error) {
    toast.show(errText(error, '该支付方式已有流水引用，请改为停用'));
  }
}

// ── 计划 ────────────────────────────────────────────────────────────────────
const planSheet = ref(false);
const planName = ref('');
const planCategory = ref('');
const planPayment = ref('');
const planAmount = ref('');
const planPeriods = ref('12');
const planFirstDue = ref(today);
const planSource = ref<PlanSource>('manual');
const planAutoPost = ref(false);

function openPlanCreate(): void {
  planName.value = '';
  planCategory.value = dict.rootCategories[0] ? (dict.selectableChildren(dict.rootCategories[0])[0]?.id ?? '') : '';
  planPayment.value = dict.usablePaymentMethods[0]?.id ?? '';
  planAmount.value = '';
  planPeriods.value = '12';
  planFirstDue.value = today;
  planSource.value = 'manual';
  planAutoPost.value = false;
  planSheet.value = true;
}

async function savePlan(): Promise<void> {
  const name = planName.value.trim();
  const cents = parseYuanToCents(planAmount.value);
  if (name === '' || cents <= 0) {
    toast.show('请填写名称与每期金额');
    return;
  }
  busy.value = true;
  try {
    await plansApi.create({
      name,
      categoryId: planCategory.value,
      paymentMethodId: planPayment.value,
      source: planSource.value,
      amountCents: cents,
      periods: Number(planPeriods.value),
      firstDueDate: planFirstDue.value,
      remindDaysBefore: 3,
      autoPost: planAutoPost.value,
    });
    toast.show('计划已创建');
    planSheet.value = false;
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '创建失败'));
  } finally {
    busy.value = false;
  }
}

async function endPlan(plan: Plan): Promise<void> {
  try {
    await plansApi.end(plan.id);
    toast.show('计划已终止');
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '操作失败'));
  }
}

async function removePlan(plan: Plan): Promise<void> {
  try {
    await plansApi.delete(plan.id);
    toast.show('计划已删除');
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '删除失败'));
  }
}

// ── 数据 ────────────────────────────────────────────────────────────────────
const THEME_OPTIONS = [
  { value: 'dark', label: '赛博朋克' },
  { value: 'light', label: '水果硬糖' },
] as const;

const themeChoice = computed({
  get: () => theme.proto.value as string,
  set: (v: string) => theme.set(v === 'cyber' ? 'dark' : 'light'),
});

const importBusy = ref(false);

async function exportPackage(): Promise<void> {
  try {
    await dataApi.exportPackage({ scope: 'all' } as never);
    toast.show('账本已导出');
  } catch (error) {
    toast.show(errText(error, '导出失败'));
  }
}

async function exportCsv(): Promise<void> {
  try {
    await dataApi.exportCsv({ scope: 'all' } as never);
    toast.show('流水 CSV 已导出');
  } catch (error) {
    toast.show(errText(error, '导出失败'));
  }
}

async function onImportFile(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  importBusy.value = true;
  try {
    const text = await file.text();
    const pkg = JSON.parse(text) as unknown;
    const result = await dataApi.import(pkg);
    toast.show(`已导入（${result.counts?.expenses ?? 0} 笔支出）`);
    await dict.load(true);
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '导入失败：文件格式不对？'));
  } finally {
    importBusy.value = false;
    input.value = '';
  }
}

async function wipeAll(): Promise<void> {
  if (!window.confirm('确定清空全部数据？此操作不可撤销。')) return;
  try {
    await dataApi.wipe();
    toast.show('数据已清空');
    await dict.load(true);
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '清空失败'));
  }
}

async function resetDemo(): Promise<void> {
  if (!window.confirm('重置为演示数据？当前数据将被覆盖。')) return;
  try {
    await dataApi.resetDemo(today);
    toast.show('已重置为演示数据');
    await dict.load(true);
    await plansStore.refresh();
  } catch (error) {
    toast.show(errText(error, '重置失败'));
  }
}

// ── 家庭 ────────────────────────────────────────────────────────────────────
const members = ref<User[]>([]);
const memberSheet = ref(false);
const memberName = ref('');
const memberUsername = ref('');
const memberPassword = ref('');

async function loadMembers(): Promise<void> {
  try {
    members.value = (await usersApi.list()).users;
  } catch {
    members.value = [];
  }
}

function openMemberCreate(): void {
  memberName.value = '';
  memberUsername.value = '';
  memberPassword.value = '';
  memberSheet.value = true;
}

async function saveMember(): Promise<void> {
  if (memberUsername.value.trim() === '' || memberPassword.value.length < 8) {
    toast.show('登录名必填，口令至少 8 位');
    return;
  }
  busy.value = true;
  try {
    await usersApi.create({
      username: memberUsername.value.trim(),
      displayName: memberName.value.trim() || memberUsername.value.trim(),
      password: memberPassword.value,
    });
    toast.show('成员已添加');
    memberSheet.value = false;
    await loadMembers();
  } catch (error) {
    toast.show(errText(error, '添加失败'));
  } finally {
    busy.value = false;
  }
}

/** 成员停用：当前 /api/users 的 PATCH 不接受 isActive，等接口补上再接出来 */



onMounted(() => {
  void dict.load().catch(() => undefined);
  void plansStore.refresh().catch(() => undefined);
  void loadMembers();
});
</script>

<template>
  <div class="stack">
    <!-- 分区切换 -->
    <PCard>
      <PSeg
        :options="TABS"
        :value="tab"
        label="设置分区"
        @change="(v) => (tab = v as 'ledger' | 'plans' | 'data' | 'household')"
      />
    </PCard>

    <!-- ════════ 账目：分类 + 支付方式 ════════ -->
    <template v-if="tab === 'ledger'">
      <PCard>
        <div class="card-h">
          <span class="card-t">分类</span>
          <span class="card-cap">一级 {{ dict.rootCategories.length }} · 共
            {{ dict.categories.length }}</span>
          <PBtn size="sm" :icon="Plus" style="margin-left: auto" @click="openCatCreate">新增分类</PBtn>
        </div>
        <PEmpty v-if="dict.rootCategories.length === 0" :icon="Tag">还没有分类</PEmpty>
        <div v-for="root in dict.rootCategories" :key="root.id" class="set-group">
          <div class="set-row">
            <span class="set-body">
              <span class="set-t">{{ root.name }}</span>
              <span class="set-s">{{ root.children.length }} 个二级分类</span>
            </span>
            <PIconBtn :icon="Pencil" label="编辑" @click="openCatEdit(root)" />
            <PIconBtn :icon="Trash2" label="删除" @click="removeCat(root)" />
            <PSwitch :checked="root.isEnabled" label="启用" @change="(v) => toggleCat(root, v)" />
          </div>
          <div v-for="child in root.children" :key="child.id" class="set-row" style="padding-left: 16px">
            <span class="set-body">
              <span class="set-t">{{ child.name }}</span>
              <span class="set-s">{{ child.expenseCount }} 笔</span>
            </span>
            <PIconBtn :icon="Pencil" label="编辑" @click="openCatEdit(child)" />
            <PIconBtn :icon="Trash2" label="删除" @click="removeCat(child)" />
            <PSwitch :checked="child.isEnabled" label="启用" @change="(v) => toggleCat(child, v)" />
          </div>
        </div>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">支付方式</span>
          <span class="card-cap">{{ dict.paymentMethods.length }} 个</span>
          <PBtn size="sm" :icon="Plus" style="margin-left: auto" @click="openPayCreate">新增</PBtn>
        </div>
        <PEmpty v-if="dict.paymentMethods.length === 0" :icon="Wallet">还没有支付方式</PEmpty>
        <div v-for="p in dict.paymentMethods" :key="p.id" class="set-row">
          <span class="set-body">
            <span class="set-t">{{ p.name }}</span>
            <span class="set-s">
              {{ p.type === 'credit' ? `信用卡 · ${p.billingDay} 日账单 / ${p.repaymentDay} 日还款` : '即时结算' }}
            </span>
          </span>
          <PIconBtn :icon="Pencil" label="编辑" @click="openPayEdit(p)" />
          <PIconBtn :icon="Trash2" label="删除" @click="removePay(p)" />
        </div>
      </PCard>
    </template>

    <!-- ════════ 计划 ════════ -->
    <template v-else-if="tab === 'plans'">
      <PCard>
        <div class="card-h">
          <span class="card-t">还款计划</span>
          <span class="card-cap">进行中 {{ plansStore.activePlans.length }} · 已结束
            {{ plansStore.endedPlans.length }}</span>
          <PBtn size="sm" :icon="Plus" style="margin-left: auto" @click="openPlanCreate">新建计划</PBtn>
        </div>
        <PEmpty v-if="plansStore.plans.length === 0" :icon="CalendarDays">还没有计划</PEmpty>
        <div v-for="p in plansStore.plans" :key="p.id" class="set-row">
          <span class="set-body">
            <span class="set-t">
              {{ p.name }}
              <PTag v-if="p.state === 'ended'" tone="dash">已结束</PTag>
              <PTag v-else-if="p.autoPost" tone="accent">自动入账</PTag>
            </span>
            <span class="set-s">
              每期 {{ formatYuan(p.amountCents) }} · 首期 {{ p.firstDueDate }}
            </span>
          </span>
          <PBtn v-if="p.state === 'active'" size="sm" variant="ghost" @click="endPlan(p)">终止</PBtn>
          <PIconBtn :icon="Trash2" label="删除" @click="removePlan(p)" />
        </div>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">待处理期次</span>
          <span class="card-cap">{{ plansStore.dueTodos.length }} 笔</span>
        </div>
        <PEmpty v-if="plansStore.dueTodos.length === 0" :icon="Check">没有待处理的期次</PEmpty>
        <div v-for="t in plansStore.dueTodos" :key="t.id" class="set-row">
          <span class="set-body">
            <span class="set-t">{{ t.planName }} · {{ t.periodSeq }} 期</span>
            <span class="set-s">{{ t.repaymentDate }} · {{ formatYuan(t.amountCents) }}</span>
          </span>
          <PTag :tone="t.willAutoPost ? 'accent' : 'dash'">{{ t.willAutoPost ? '自动' : '手动' }}</PTag>
        </div>
      </PCard>
    </template>

    <!-- ════════ 数据 ════════ -->
    <template v-else-if="tab === 'data'">
      <PCard>
        <div class="card-h">
          <span class="card-t">主题</span>
          <span class="card-cap">两套设计语言</span>
        </div>
        <PSeg v-model:value="themeChoice" :options="THEME_OPTIONS" label="主题" @change="(v) => (themeChoice = v)" />
        <p class="hint" style="margin-top: 10px; display: flex; align-items: center; gap: 6px">
          <component :is="theme.proto.value === 'cyber' ? Moon : Sun" :size="13" />
          赛博朋克：黑底霓虹 / 水果硬糖：纸白糖果。顶栏右上角也能一键切换。
        </p>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">导出</span>
          <span class="card-cap">账本 JSON / 流水 CSV</span>
        </div>
        <div class="split">
          <PBtn :icon="Database" @click="exportPackage">导出账本（JSON）</PBtn>
          <PBtn @click="exportCsv">导出流水（CSV）</PBtn>
        </div>
        <p class="hint" style="margin-top: 8px">JSON 是全量数据包（可再导入）；CSV 只用于 Excel 对账。</p>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">导入</span>
          <span class="card-cap">账本 JSON</span>
        </div>
        <label class="btn btn--ghost" style="cursor: pointer">
          {{ importBusy ? '导入中…' : '选择 JSON 文件' }}
          <input type="file" accept="application/json,.json" style="display: none" @change="onImportFile" />
        </label>
        <p class="hint" style="margin-top: 8px">导入是**追加**，不会清空现有数据。</p>
      </PCard>

      <PCard>
        <div class="card-h">
          <span class="card-t">危险操作</span>
          <span class="card-cap">不可撤销</span>
        </div>
        <div class="split">
          <PBtn variant="danger" @click="wipeAll">清空全部数据</PBtn>
          <PBtn variant="ghost" @click="resetDemo">重置为演示数据</PBtn>
        </div>
      </PCard>
    </template>

    <!-- ════════ 家庭 ════════ -->
    <template v-else>
      <PCard>
        <div class="card-h">
          <span class="card-t">成员</span>
          <span class="card-cap">{{ members.length }} 人</span>
          <PBtn size="sm" :icon="Plus" style="margin-left: auto" @click="openMemberCreate">添加成员</PBtn>
        </div>
        <PEmpty v-if="members.length === 0" :icon="Users">还没有成员</PEmpty>
        <div v-for="m in members" :key="m.id" class="set-row">
          <span class="set-body">
            <span class="set-t">{{ m.displayName }}</span>
            <span class="set-s">@{{ m.username }}</span>
          </span>
          <PTag v-if="m.role === 'admin'" tone="accent">管理员</PTag>
        </div>
      </PCard>
    </template>

    <!-- ════════ 分类表单 ════════ -->
    <PSheet :open="catSheet" :title="catEditing ? '编辑分类' : '新增分类'" @close="catSheet = false">
      <PField label="名称" id="cat-name">
        <PInput id="cat-name" v-model="catName" placeholder="如：外卖" />
      </PField>
      <PField v-if="!catEditing" label="归属一级分类" id="cat-parent">
        <select id="cat-parent" v-model="catParent" class="input">
          <option v-for="r in dict.rootCategories" :key="r.id" :value="r.id">{{ r.name }}</option>
        </select>
      </PField>
      <template #foot>
        <PBtn variant="primary" :disabled="busy" @click="saveCat">保存</PBtn>
        <PBtn variant="ghost" @click="catSheet = false">取消</PBtn>
      </template>
    </PSheet>

    <!-- ════════ 支付方式表单 ════════ -->
    <PSheet :open="paySheet" :title="payEditing ? '编辑支付方式' : '新增支付方式'" @close="paySheet = false">
      <PField label="名称" id="pay-name">
        <PInput id="pay-name" v-model="payName" placeholder="如：招商信用卡" />
      </PField>
      <PField label="类型" id="pay-type">
        <select id="pay-type" v-model="payType" class="input">
          <option value="credit">信用卡（有账单/还款日）</option>
          <option value="cash">即时结算（储蓄卡 / 电子钱包 / 现金）</option>
        </select>
      </PField>
      <template v-if="payType === 'credit'">
        <PField label="账单日" id="pay-billing">
          <PInput id="pay-billing" v-model="payBilling" type="number" placeholder="1-31" />
        </PField>
        <PField label="还款日" id="pay-repay">
          <PInput id="pay-repay" v-model="payRepay" type="number" placeholder="1-31" />
        </PField>
      </template>
      <template #foot>
        <PBtn variant="primary" :disabled="busy" @click="savePay">保存</PBtn>
        <PBtn variant="ghost" @click="paySheet = false">取消</PBtn>
      </template>
    </PSheet>

    <!-- ════════ 计划表单 ════════ -->
    <PSheet :open="planSheet" title="新建计划" @close="planSheet = false">
      <PField label="名称" id="plan-name">
        <PInput id="plan-name" v-model="planName" placeholder="如：房贷" />
      </PField>
      <PField label="分类" id="plan-cat">
        <select id="plan-cat" v-model="planCategory" class="input">
          <option v-for="r in dict.rootCategories" :key="r.id" :value="r.id">{{ r.name }}</option>
        </select>
      </PField>
      <PField label="支付方式" id="plan-pay">
        <select id="plan-pay" v-model="planPayment" class="input">
          <option v-for="p in dict.usablePaymentMethods" :key="p.id" :value="p.id">{{ p.name }}</option>
        </select>
      </PField>
      <PField label="每期金额" id="plan-amount">
        <PInput id="plan-amount" v-model="planAmount" placeholder="1000.00" />
      </PField>
      <PField label="期数" id="plan-periods">
        <PInput id="plan-periods" v-model="planPeriods" type="number" />
      </PField>
      <PField label="首期还款日" id="plan-due">
        <input id="plan-due" v-model="planFirstDue" type="date" class="input" />
      </PField>
      <div class="set-row">
        <span class="set-body">
          <span class="set-t">到期自动入账</span>
          <span class="set-s">关闭则每期需要手动点「入账」</span>
        </span>
        <PSwitch :checked="planAutoPost" label="自动入账" @change="(v) => (planAutoPost = v)" />
      </div>
      <template #foot>
        <PBtn variant="primary" :disabled="busy" @click="savePlan">创建</PBtn>
        <PBtn variant="ghost" @click="planSheet = false">取消</PBtn>
      </template>
    </PSheet>

    <!-- ════════ 成员表单 ════════ -->
    <PSheet :open="memberSheet" title="添加成员" @close="memberSheet = false">
      <PField label="登录名" id="member-username">
        <PInput id="member-username" v-model="memberUsername" placeholder="小写字母" />
      </PField>
      <PField label="显示名" id="member-name">
        <PInput id="member-name" v-model="memberName" placeholder="界面上显示的名字" />
      </PField>
      <PField label="初始口令（至少 8 位）" id="member-password">
        <PInput id="member-password" v-model="memberPassword" type="password" />
      </PField>
      <template #foot>
        <PBtn variant="primary" :disabled="busy" @click="saveMember">添加</PBtn>
        <PBtn variant="ghost" @click="memberSheet = false">取消</PBtn>
      </template>
    </PSheet>
  </div>
</template>

<style scoped>
.set-group + .set-group {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px dashed var(--line);
}
</style>
