<script setup lang="ts">
/**
 * 应用外壳：路由出口 + 导航 + 记账抽屉。
 *
 * 铁律（§五 第 10 条 · §6.6）：
 *   1. 桌面（≥1024px）：顶栏导航（概况 / 流水 / 报表 / 设置 / 记一笔）。
 *   2. 移动端（<1024px）：单页化，彻底移除底栏，主落地页为流水页；三页（概况 / 报表 / 设置）降为二级页。
 *   3. 下拉手势唤出记账：在滚动到顶部时下拉 > 60px 触发创建抽屉。
 */
import { ChartColumn, House, Plus, ReceiptText } from '@lucide/vue';
import { computed, onMounted, onUnmounted } from 'vue';
import { RouterLink, RouterView, useRoute } from 'vue-router';

import ExpenseSheet from '@/components/ExpenseSheet.vue';
import { useUiStore } from '@/stores/ui';

const route = useRoute();
const ui = useUiStore();

/** 登录页是独立的一屏，不套外壳 */
const showChrome = computed(() => route.meta['public'] !== true);

/** 桌面端主导航（「首页」重命名为「概况」） */
const NAV = [
  { name: 'dashboard', label: '概况', icon: House },
  { name: 'ledger', label: '流水', icon: ReceiptText },
  { name: 'report', label: '报表', icon: ChartColumn },
] as const;

function onSaved(): void {
  ui.markDataChanged();
}

// ---------------------------------------------------------------------------
// 移动端下拉唤出记账（A19 · §6.6 五）
// ---------------------------------------------------------------------------

let touchStartY = 0;
let isPulling = false;

function onTouchStart(e: TouchEvent): void {
  // 仅在列表处于顶部且抽屉未开时触发
  if (window.scrollY > 0 || ui.sheetOpen) return;
  const touch = e.touches[0];
  if (!touch) return;
  touchStartY = touch.clientY;
  isPulling = true;
}

function onTouchEnd(e: TouchEvent): void {
  if (!isPulling) return;
  isPulling = false;
  const touch = e.changedTouches[0];
  if (!touch) return;
  const deltaY = touch.clientY - touchStartY;
  // 阈值 60px
  if (deltaY > 60 && window.scrollY <= 0 && !ui.sheetOpen) {
    ui.openCreate();
  }
}

onMounted(() => {
  window.addEventListener('touchstart', onTouchStart, { passive: true });
  window.addEventListener('touchend', onTouchEnd, { passive: true });
});

onUnmounted(() => {
  window.removeEventListener('touchstart', onTouchStart);
  window.removeEventListener('touchend', onTouchEnd);
});
</script>

<template>
  <RouterView v-if="!showChrome" />

  <div v-else class="min-h-full bg-canvas text-ink">
    <!-- 桌面顶部导航（≥1024px） -->
    <header class="sticky top-0 z-[var(--z-sticky)] hidden bg-surface lg:block">
      <nav
        class="mx-auto flex h-16 w-full max-w-[var(--content-max)] items-center gap-1 px-6"
        aria-label="主导航"
      >
        <span class="mr-5 text-base font-bold tracking-tight">SuenMoney</span>

        <RouterLink
          v-for="item in NAV"
          :key="item.name"
          :to="{ name: item.name }"
          class="inline-flex items-center gap-2 rounded-md px-3 py-2 text-sm font-semibold transition-colors duration-200"
          :class="
            route.name === item.name
              ? 'bg-canvas text-primary-text'
              : 'text-ink-muted hover:bg-canvas hover:text-ink'
          "
        >
          <component :is="item.icon" :size="18" aria-hidden="true" />
          {{ item.label }}
        </RouterLink>

        <span class="flex-1" />

        <RouterLink
          :to="{ name: 'settings' }"
          class="rounded-md px-3 py-2 text-sm font-semibold transition-colors duration-200"
          :class="
            route.name === 'settings'
              ? 'bg-canvas text-primary-text'
              : 'text-ink-muted hover:bg-canvas hover:text-ink'
          "
        >
          设置
        </RouterLink>

        <button
          type="button"
          class="ml-2 inline-flex items-center gap-1.5 rounded-md bg-primary-fill px-4 py-2.5 text-sm font-bold text-on-primary transition-transform duration-200 hover:scale-105 active:scale-95"
          @click="ui.openCreate()"
        >
          <Plus :size="18" :stroke-width="2.5" aria-hidden="true" />
          记一笔
        </button>
      </nav>
    </header>

    <!-- 页面切换路由出口 -->
    <RouterView v-slot="{ Component }">
      <Transition name="page" mode="out-in">
        <component :is="Component" />
      </Transition>
    </RouterView>

    <!-- 记账抽屉 -->
    <ExpenseSheet
      :open="ui.sheetOpen"
      :expense="ui.editingExpense"
      @close="ui.closeSheet()"
      @saved="onSaved"
    />
  </div>
</template>
