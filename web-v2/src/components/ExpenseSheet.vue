<script setup lang="ts">
/**
 * 记账抽屉 —— P0 骨架阶段占位。
 * P4 按原型 `views/ExpenseSheet.jsx` 重写（分类双列 / 支付抽屉 / 键盘 / 退款 / 分期）。
 */
import { PBtn } from '@/ui';

defineProps<{ open: boolean; expense?: unknown }>();
const emit = defineEmits<{ close: []; saved: [] }>();
</script>

<template>
  <div v-if="open" class="scrim" @click="emit('close')">
    <div class="sheet" @click.stop>
      <div class="sheet-head">
        <span class="sheet-title">记一笔</span>
        <span style="margin-left: auto" />
        <PBtn variant="ghost" size="sm" @click="emit('close')">关闭</PBtn>
      </div>
      <div class="sheet-body">
        <p class="hint">记账抽屉将在 P4 阶段按原型实现。</p>
      </div>
    </div>
  </div>
</template>
