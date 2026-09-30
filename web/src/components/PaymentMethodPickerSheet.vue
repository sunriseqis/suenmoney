<script setup lang="ts">
/**
 * 支付方式选择弹层（Sheet / Modal）。
 *
 * 替换原先平铺的 Chips，采用纵向抽屉列表：
 * - 节省屏幕空间，绝不换行堆叠；
 * - 完整展示卡片账单日与还款日细节；
 * - 单选即选即走，自动回填关闭。
 */
import { Check } from '@lucide/vue';

import PaymentIcon from '@/components/PaymentIcon.vue';
import { useDictionariesStore } from '@/stores/dictionaries';

defineProps<{
  open: boolean;
  activePaymentMethodId: string | null;
}>();

const emit = defineEmits<{
  close: [];
  select: [paymentMethodId: string];
}>();

const dict = useDictionariesStore();

function handleSelect(id: string): void {
  emit('select', id);
  emit('close');
}

function close(): void {
  emit('close');
}
</script>

<template>
  <div v-if="open" class="fixed inset-0 z-[calc(var(--z-sheet)+10)] flex flex-col justify-end lg:justify-center lg:items-center">
    <!-- 遮罩背景 -->
    <button
      type="button"
      class="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)] transition-opacity"
      aria-label="关闭支付方式选择"
      @click="close"
    />

    <!-- 弹层主体 -->
    <div
      class="relative flex max-h-[70vh] w-full flex-col rounded-t-xl bg-surface shadow-2xl transition-transform lg:w-[460px] lg:rounded-xl"
      role="dialog"
      aria-modal="true"
      @keydown.esc="close"
    >
      <!-- 弹层顶栏 -->
      <header class="flex items-center justify-between border-b border-line/60 px-4 py-3 sm:px-5">
        <span class="text-sm font-bold text-ink">选择支付方式</span>
        <button
          type="button"
          class="relative grid h-10 w-10 place-items-center rounded-sm text-sm font-bold text-ink-muted hover:bg-sunken hover:text-ink after:absolute after:-inset-0.5 after:rounded-sm after:content-['']"
          aria-label="关闭"
          @click="close"
        >
          ✕
        </button>
      </header>

      <!-- 支付方式列表 -->
      <div class="min-h-0 flex-1 overflow-y-auto p-3 sm:p-4">
        <div v-if="dict.usablePaymentMethods.length > 0" class="divide-y divide-line/40 rounded-lg border border-line/60 bg-canvas">
          <button
            v-for="method in dict.usablePaymentMethods"
            :key="method.id"
            type="button"
            class="flex w-full items-center justify-between gap-3 p-3.5 text-left transition-colors duration-150 hover:bg-sunken/40 first:rounded-t-lg last:rounded-b-lg active:bg-sunken"
            @click="handleSelect(method.id)"
          >
            <div class="flex items-center gap-3 min-w-0">
              <PaymentIcon :name="method.name" :icon="method.icon" :size="24" />
              <div class="min-w-0">
                <p class="truncate text-sm font-bold text-ink">{{ method.name }}</p>
                <p class="mt-0.5 text-xs text-ink-muted">
                  <template v-if="method.type === 'credit'">
                    信用卡 · 账单日 {{ method.billingDay }}日 / 还款日 {{ method.repaymentDay }}日
                  </template>
                  <template v-else>
                    借记卡 / 现金 / 实时扣款
                  </template>
                </p>
              </div>
            </div>

            <!-- 选中对勾 -->
            <div
              v-if="method.id === activePaymentMethodId"
              class="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-primary text-white shadow-xs"
            >
              <Check class="h-3.5 w-3.5 stroke-[3]" />
            </div>
            <div v-else class="h-6 w-6 shrink-0 rounded-full border border-line" />
          </button>
        </div>

        <div v-else class="py-8 text-center text-xs text-ink-muted">
          暂无可用支付方式，请前往设置添加。
        </div>
      </div>
    </div>
  </div>
</template>
