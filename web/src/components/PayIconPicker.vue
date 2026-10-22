<script setup lang="ts">
/**
 * 支付方式图标选择。
 *
 * 图标登记表在 `utils/payment-icons.ts`：里面既有品牌矢量（支付宝/微信/银联…），
 * 也有兜底的 Lucide 图标。**存的是 id 字符串**（不是组件），这样能过 JSON、
 * 能被服务端校验，也能在导入导出时保持稳定。
 *
 * 空字符串 = 没设过，由 `resolvePaymentIcon(name)` 按名称猜一个 ——
 * 猜的规则集中在那一个函数里，前端各处不再各猜各的。
 */
import PPayIcon from '@/components/PPayIcon.vue';
import { PAYMENT_ICON_OPTIONS } from '@/utils/payment-icons';

defineProps<{ modelValue: string }>();
const emit = defineEmits<{ 'update:modelValue': [value: string] }>();
</script>

<template>
  <div class="pay-icon-picker">
    <button
      type="button"
      class="pip-auto"
      :class="{ 'is-on': modelValue === '' }"
      title="按名称自动识别"
      @click="emit('update:modelValue', '')"
    >
      自动
    </button>
    <button
      v-for="opt in PAYMENT_ICON_OPTIONS"
      :key="opt.id"
      type="button"
      class="pip-cell"
      :class="{ 'is-on': modelValue === opt.id }"
      :title="opt.label"
      :aria-label="opt.label"
      @click="emit('update:modelValue', opt.id)"
    >
      <PPayIcon :name="opt.label" :icon="opt.id" :size="18" />
      <span class="pip-l">{{ opt.label }}</span>
    </button>
  </div>
</template>

<style scoped>
.pay-icon-picker {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(84px, 1fr));
  gap: 6px;
}
.pip-cell {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 8px;
  border: 1px solid var(--line);
  border-radius: var(--r-sm);
  background: var(--surface);
  color: var(--ink-2);
  transition: all 0.16s;
  min-width: 0;
}
.pip-cell:hover {
  border-color: var(--ink-3);
  color: var(--ink);
}
.pip-cell.is-on {
  border-color: var(--accent);
  color: var(--ink);
  box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent);
}
.pip-l {
  font-size: 10.5px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.pip-auto {
  padding: 7px 12px;
  border: 1px solid var(--line);
  border-radius: 999px;
  font-size: 11px;
  font-family: var(--font-mono);
  color: var(--ink-2);
}
.pip-auto.is-on {
  border-color: var(--accent);
  color: var(--accent);
}
</style>
