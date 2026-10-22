<script setup lang="ts">
/** 原型轻提示（prototype `.toast`）：底部居中、糖果硬边 / 霓虹发光。 */
import { Check } from '@lucide/vue';

import { useToast } from '@/composables/useToast';

const { message } = useToast();
</script>

<template>
  <div v-if="message" class="toast" role="status">
    <Check :size="14" />
    {{ message }}
  </div>
</template>
