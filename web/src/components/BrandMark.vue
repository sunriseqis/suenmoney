<script setup lang="ts">
/**
 * 品牌位：计算器 mark + 字标。
 *
 * mark 是真矢量（web/public/logo.svg，与 favicon/iOS/鸿蒙图标同一母版），
 * 以 <img> 引入而非内联 —— 顶栏 34px 与登录页 40px 共用一份文件。
 * 字标不是自绘 SVG：直接字体排（Outfit 粗体），改字形只动 mark 母版。
 */
withDefaults(defineProps<{ size?: number; wordmark?: boolean }>(), {
  size: 34,
  wordmark: true,
});
</script>

<template>
  <span class="inline-flex items-center gap-2.5">
    <img src="/logo.svg" alt="SuenMoney" :width="size" :height="size" class="block" />
    <span
      v-if="wordmark"
      class="text-base font-bold tracking-tight text-on-surface"
    >Suen<b class="font-extrabold">Money</b></span>
  </span>
</template>
