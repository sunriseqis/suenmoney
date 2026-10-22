<script setup lang="ts">
import PaymentIcon from '@/components/PaymentIcon.vue';
import { PAYMENT_ICON_OPTIONS, type PaymentIconId } from '@/utils/payment-icons';

defineProps<{
  modelValue: string;
  name?: string;
}>();

const emit = defineEmits<{
  'update:modelValue': [string];
}>();

function pick(id: PaymentIconId): void {
  emit('update:modelValue', id);
}
</script>

<template>
  <div class="rounded-md bg-sunken p-2.5">
    <div class="flex items-center justify-between pb-2">
      <span class="text-xs font-medium text-ink-muted">支付方式图标</span>
      <button
        type="button"
        class="text-xs font-semibold text-primary hover:underline"
        @click="emit('update:modelValue', '')"
      >
        设为自动
      </button>
    </div>

    <!-- 自动选项 -->
    <button
      type="button"
      class="mb-2 flex w-full items-center justify-center gap-2 rounded-sm py-1.5 text-xs font-semibold transition-colors duration-200"
      :class="
        modelValue === ''
          ? 'bg-primary-fill text-on-primary'
          : 'bg-canvas text-ink-muted hover:text-ink'
      "
      :aria-pressed="modelValue === ''"
      @click="emit('update:modelValue', '')"
    >
      <PaymentIcon :name="name || '卡'" :icon="''" :size="16" />
      <span>自动（根据名称推断）</span>
    </button>

    <!-- 图标网格 -->
    <div class="grid grid-cols-2 gap-1.5 sm:grid-cols-5">
      <button
        v-for="opt in PAYMENT_ICON_OPTIONS"
        :key="opt.id"
        type="button"
        class="flex items-center gap-1.5 rounded-sm p-2 text-xs transition-colors duration-200"
        :class="
          modelValue === opt.id
            ? 'bg-primary-fill text-on-primary font-bold'
            : 'bg-canvas text-ink-muted hover:text-ink'
        "
        :aria-pressed="modelValue === opt.id"
        @click="pick(opt.id)"
      >
        <PaymentIcon :icon="opt.id" :size="16" :colored="modelValue !== opt.id" />
        <span class="truncate">{{ opt.label }}</span>
      </button>
    </div>
  </div>
</template>
