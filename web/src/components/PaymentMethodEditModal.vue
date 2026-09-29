<script setup lang="ts">
/**
 * 支付方式独立弹窗。
 *
 * 统一移动端交互，避免行内折叠导致的页面晃动。
 * 支持新增支付方式、修改名称、信用卡周期属性（账单日/还款日）、图标定制、
 * 停用/启用、以及支付方式数据迁移与合并。
 */
import { computed, ref, watch } from 'vue';
import { X } from '@lucide/vue';
import {
  ApiError,
  paymentMethods as paymentMethodsApi,
  type PaymentMethod,
  type PaymentMethodType,
} from '@/api';
import PaymentIcon from './PaymentIcon.vue';
import PaymentIconPicker from './PaymentIconPicker.vue';

const props = withDefaults(
  defineProps<{
    open: boolean;
    method: PaymentMethod | null;
    availableMethods?: PaymentMethod[];
  }>(),
  { availableMethods: () => [] },
);

const emit = defineEmits<{
  close: [];
  saved: [];
}>();

const isCreate = computed(() => props.method === null);

const name = ref('');
const type = ref<PaymentMethodType>('cash');
const icon = ref('');
const billingDay = ref('');
const repaymentDay = ref('');
const isEnabled = ref(true);

const mergeTargetId = ref('');
const deleteSourceOnMerge = ref(true);

const busy = ref(false);
const errorMessage = ref<string | null>(null);

const otherMethods = computed(() => {
  if (!props.method) return [];
  return props.availableMethods.filter((m) => m.id !== props.method?.id && m.isEnabled);
});

watch(
  () => [props.open, props.method] as const,
  ([isOpen, m]) => {
    if (!isOpen) return;
    if (m) {
      name.value = m.name;
      type.value = m.type;
      icon.value = m.icon || '';
      billingDay.value = m.billingDay ? String(m.billingDay) : '';
      repaymentDay.value = m.repaymentDay ? String(m.repaymentDay) : '';
      isEnabled.value = m.isEnabled;
      mergeTargetId.value = '';
      deleteSourceOnMerge.value = true;
      errorMessage.value = null;
    } else {
      name.value = '';
      type.value = 'cash';
      icon.value = '';
      billingDay.value = '';
      repaymentDay.value = '';
      isEnabled.value = true;
      mergeTargetId.value = '';
      deleteSourceOnMerge.value = true;
      errorMessage.value = null;
    }
  },
  { immediate: true },
);

async function handleSave(): Promise<void> {
  const trimmed = name.value.trim();
  if (!trimmed) {
    errorMessage.value = '支付方式名称不能为空';
    return;
  }

  let bNum: number | undefined;
  let rNum: number | undefined;
  if (type.value === 'credit') {
    bNum = Number(billingDay.value);
    rNum = Number(repaymentDay.value);
    if (!bNum || bNum < 1 || bNum > 31) {
      errorMessage.value = '请选择有效的账单日（1~31 日）';
      return;
    }
    if (!rNum || rNum < 1 || rNum > 31) {
      errorMessage.value = '请选择有效的还款日（1~31 日）';
      return;
    }
  }

  busy.value = true;
  errorMessage.value = null;

  try {
    if (isCreate.value) {
      await paymentMethodsApi.create({
        name: trimmed,
        type: type.value,
        icon: icon.value || undefined,
        billingDay: bNum,
        repaymentDay: rNum,
      });
    } else if (props.method) {
      const payload: {
        name: string;
        icon?: string;
        billingDay?: number;
        repaymentDay?: number;
        isEnabled?: boolean;
      } = {
        name: trimmed,
        icon: icon.value || undefined,
        isEnabled: isEnabled.value,
      };

      if (type.value === 'credit') {
        payload.billingDay = bNum;
        payload.repaymentDay = rNum;
      }

      await paymentMethodsApi.update(props.method.id, payload);
    }

    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '保存失败，请重试';
  } finally {
    busy.value = false;
  }
}

async function handleToggleEnabled(): Promise<void> {
  if (!props.method) return;
  busy.value = true;
  errorMessage.value = null;
  try {
    await paymentMethodsApi.update(props.method.id, { isEnabled: !isEnabled.value });
    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '操作失败，请重试';
  } finally {
    busy.value = false;
  }
}

async function handleMerge(): Promise<void> {
  if (!props.method || !mergeTargetId.value) return;
  const target = otherMethods.value.find((m) => m.id === mergeTargetId.value);
  if (!target) return;

  const actionText = deleteSourceOnMerge.value ? '合并至并删除当前支付方式' : '迁移至';
  if (!confirm(`确定将当前支付方式的所有支出与计划${actionText}「${target.name}」吗？`)) {
    return;
  }

  busy.value = true;
  errorMessage.value = null;
  try {
    await paymentMethodsApi.merge(props.method.id, {
      targetId: mergeTargetId.value,
      deleteSource: deleteSourceOnMerge.value,
    });
    emit('saved');
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '合并失败，请重试';
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-[var(--z-modal)] flex items-center justify-center p-3 sm:p-6"
    role="dialog"
    aria-modal="true"
  >
    <!-- 背景遮罩 -->
    <div
      class="fixed inset-0 bg-black/60 backdrop-blur-xs transition-opacity"
      @click="emit('close')"
    />

    <!-- 弹窗卡片 -->
    <div
      class="relative z-10 flex max-h-[90vh] w-full max-w-lg flex-col rounded-xl border border-line bg-surface shadow-2xl"
    >
      <!-- 顶栏 -->
      <header class="flex items-center justify-between border-b border-line px-5 py-3.5">
        <div class="flex items-center gap-2">
          <PaymentIcon :name="name" :icon="icon" :size="20" />
          <h2 class="text-base font-bold text-ink">
            {{ isCreate ? '新增支付方式' : '编辑支付方式' }}
          </h2>
        </div>
        <button
          type="button"
          class="rounded-sm p-1 text-ink-muted hover:bg-sunken hover:text-ink"
          @click="emit('close')"
        >
          <X class="h-5 w-5" />
        </button>
      </header>

      <!-- 表单内容 -->
      <div class="flex-1 overflow-y-auto px-5 py-4 space-y-4">
        <!-- 错误提示 -->
        <p v-if="errorMessage" class="rounded-sm bg-danger/10 p-3 text-xs text-danger-text">
          {{ errorMessage }}
        </p>

        <!-- 账户类型 -->
        <div>
          <label class="label-cn block mb-1.5">账户类型</label>
          <div v-if="isCreate" class="grid grid-cols-2 gap-1 rounded-md bg-sunken p-1">
            <button
              type="button"
              class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
              :class="type === 'cash' ? 'bg-canvas text-ink' : 'text-ink-muted'"
              @click="type = 'cash'"
            >
              现金 / 储蓄卡
            </button>
            <button
              type="button"
              class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
              :class="type === 'credit' ? 'bg-canvas text-ink' : 'text-ink-muted'"
              @click="type = 'credit'"
            >
              信用卡
            </button>
          </div>
          <div
            v-else
            class="rounded-md bg-sunken px-3.5 py-2.5 text-sm text-ink flex items-center justify-between"
          >
            <span>{{ type === 'credit' ? '信用卡' : '现金 / 储蓄卡' }}</span>
          </div>
        </div>

        <!-- 名称 -->
        <div>
          <label class="label-cn block mb-1.5">支付方式名称</label>
          <input
            v-model="name"
            type="text"
            maxlength="20"
            placeholder="如「招行白金卡」"
            class="w-full rounded-sm bg-sunken px-3.5 py-2.5 text-sm text-ink placeholder:text-ink-muted focus:ring-1 focus:ring-primary"
          />
        </div>

        <!-- 信用卡特有：账单日与还款日 -->
        <div v-if="type === 'credit'" class="grid grid-cols-2 gap-3 rounded-md bg-sunken p-3.5">
          <div>
            <label class="label-cn block mb-1.5">账单日</label>
            <select
              v-model="billingDay"
              class="w-full rounded-sm bg-canvas px-3 py-2 text-sm text-ink focus:ring-1 focus:ring-primary"
            >
              <option value="" disabled>选择账单日</option>
              <option v-for="d in 31" :key="d" :value="String(d)">每月 {{ d }} 日</option>
            </select>
          </div>

          <div>
            <label class="label-cn block mb-1.5">还款日</label>
            <select
              v-model="repaymentDay"
              class="w-full rounded-sm bg-canvas px-3 py-2 text-sm text-ink focus:ring-1 focus:ring-primary"
            >
              <option value="" disabled>选择还款日</option>
              <option v-for="d in 31" :key="d" :value="String(d)">每月 {{ d }} 日</option>
            </select>
          </div>
        </div>

        <!-- 图标定制 -->
        <div>
          <label class="label-cn block mb-1.5">图标定制</label>
          <PaymentIconPicker v-model="icon" :name="name" />
        </div>

        <!-- 编辑模式：迁移与合并 -->
        <div
          v-if="!isCreate && otherMethods.length > 0"
          class="rounded-md border border-line bg-sunken/40 p-3 space-y-2.5"
        >
          <label class="label-cn block">迁移或合并到其他支付方式</label>
          <div class="flex items-center gap-2">
            <select
              v-model="mergeTargetId"
              class="min-w-0 flex-1 rounded-sm bg-canvas px-3 py-2 text-sm text-ink focus:ring-1 focus:ring-primary"
            >
              <option value="" disabled>选择目标支付方式</option>
              <option v-for="m in otherMethods" :key="m.id" :value="m.id">
                {{ m.name }} ({{ m.type === 'credit' ? '信用卡' : '现金' }})
              </option>
            </select>
            <button
              type="button"
              :disabled="!mergeTargetId || busy"
              class="shrink-0 rounded-sm bg-surface px-3 py-2 text-xs font-bold text-ink hover:bg-canvas transition-colors disabled:opacity-40"
              @click="handleMerge"
            >
              {{ deleteSourceOnMerge ? '合并' : '迁移' }}
            </button>
          </div>
          <label class="flex items-center gap-2 text-xs text-ink-muted cursor-pointer select-none">
            <input
              v-model="deleteSourceOnMerge"
              type="checkbox"
              class="h-3.5 w-3.5 rounded-xs accent-primary"
            />
            <span>迁移后删除当前支付方式</span>
          </label>
        </div>
      </div>

      <!-- 底部动作条：停用最左边，取消与保存靠右 -->
      <footer class="flex items-center justify-between border-t border-line px-5 py-3.5 bg-canvas/40">
        <div>
          <button
            v-if="!isCreate"
            type="button"
            :disabled="busy"
            class="rounded-sm px-3.5 py-2 text-xs font-semibold transition-colors disabled:opacity-40"
            :class="
              isEnabled
                ? 'border border-danger/40 text-danger hover:bg-danger/10'
                : 'border border-line bg-canvas text-ink hover:bg-surface'
            "
            @click="handleToggleEnabled"
          >
            {{ isEnabled ? '停用' : '启用' }}
          </button>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm px-4 py-2 text-xs font-semibold text-ink-muted hover:bg-sunken hover:text-ink transition-colors disabled:opacity-40"
            @click="emit('close')"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm bg-primary-fill px-5 py-2 text-xs font-bold text-on-primary shadow-xs transition-opacity hover:opacity-90 disabled:opacity-40"
            @click="handleSave"
          >
            {{ busy ? '保存中...' : '保存' }}
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>
