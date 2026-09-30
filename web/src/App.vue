<script setup lang="ts">
/**
 * 应用外壳：路由出口 + 导航 + 记账抽屉。
 *
 * 铁律（§五 第 10 条 · §6.6）：
 *   1. 桌面（≥1024px）：顶栏导航（概况 / 流水 / 报表 / 设置 / 记一笔）。
 *   2. 移动端（<1024px）：单页化，彻底移除底栏，主落地页为流水页；三页（概况 / 报表 / 设置）降为二级页。
 *   3. 下拉手势唤出记账：在滚动到顶部时下拉 > 60px 触发创建抽屉。
 */
import { ArrowDown, ChartColumn, House, Plus, ReceiptText } from '@lucide/vue';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';

import ExpenseSheet from '@/components/ExpenseSheet.vue';
import UpdateDialog from '@/components/UpdateDialog.vue';
import { exitNativeApp, onAppResume, setupHardwareBack, triggerHaptic } from '@/platform';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import { useUpdateStore } from '@/stores/update';

const route = useRoute();
const router = useRouter();
const ui = useUiStore();
const syncStore = useSyncStore();
const updateStore = useUpdateStore();

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
// 移动端下拉唤出记账（A19 · §6.6 五）：阻尼跟手动效 + 视觉反馈胶囊 + 触感震动
// ---------------------------------------------------------------------------

const pullOffset = ref(0);
const isPullThreshold = ref(false);
const isPullTransitioning = ref(false);

const PULL_MAX_OFFSET = 80; // 视觉最大下移位移 (px)
const PULL_THRESHOLD_OFFSET = 36; // 判定达标的阻尼后位移阈值 (px)
const PULL_DAMPING = 0.6; // 阻尼乘数：与阈值联立，达标物理位移 ≈ 36 / 0.6 = 60px，跟手不沉重

let touchStartX = 0;
let touchStartY = 0;
let isEligiblePull = false;
let hasVibrated = false;

/** 下拉手势仅限流水页：它是移动端的主落地页；概况/报表等二级页顶部下拉不应误唤记账 */
const isLedgerRoute = computed(() => route.name === 'ledger');

function getScrollTop(): number {
  return window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
}

function onTouchStart(e: TouchEvent): void {
  // 抽屉已打开、非流水页、或列表不在最顶部时不触发
  if (ui.sheetOpen) return;
  if (!isLedgerRoute.value) return;
  if (getScrollTop() > 3) {
    isEligiblePull = false;
    return;
  }
  const touch = e.touches[0];
  if (!touch) return;
  touchStartX = touch.clientX;
  touchStartY = touch.clientY;
  isEligiblePull = true;
  hasVibrated = false;
  isPullTransitioning.value = false;
}

function onTouchMove(e: TouchEvent): void {
  if (!isEligiblePull || ui.sheetOpen) return;
  const touch = e.touches[0];
  if (!touch) return;

  const deltaX = touch.clientX - touchStartX;
  const deltaY = touch.clientY - touchStartY;

  // 若水平位移明显大于垂直位移，说明是横向滑动手势，放弃下拉响应
  if (Math.abs(deltaX) > Math.abs(deltaY) && pullOffset.value === 0) {
    isEligiblePull = false;
    return;
  }

  // 仅在向下拖拽时响应
  if (deltaY > 0) {
    // 阻止浏览器原生的过度滚动与默认拉拽
    if (e.cancelable) {
      e.preventDefault();
    }
    // 物理阻尼曲线：拉动距离越长阻力越大
    const damped = Math.min(PULL_MAX_OFFSET, deltaY * PULL_DAMPING);
    pullOffset.value = damped;

    const reached = damped >= PULL_THRESHOLD_OFFSET;
    if (reached && !isPullThreshold.value) {
      // 达到阈值瞬间触发触感震动
      if (!hasVibrated) {
        triggerHaptic(15);
        hasVibrated = true;
      }
    }
    isPullThreshold.value = reached;
  } else {
    pullOffset.value = 0;
    isPullThreshold.value = false;
  }
}

function onTouchEnd(): void {
  if (!isEligiblePull && pullOffset.value === 0) return;
  isEligiblePull = false;
  isPullTransitioning.value = true;

  const shouldTrigger = isPullThreshold.value;
  pullOffset.value = 0;
  isPullThreshold.value = false;

  if (shouldTrigger && !ui.sheetOpen) {
    // 配合回弹动效节奏，在回弹接近完成时优雅升起抽屉
    setTimeout(() => {
      ui.openCreate();
    }, 60);
  }
}

function onTouchCancel(): void {
  isEligiblePull = false;
  isPullTransitioning.value = true;
  pullOffset.value = 0;
  isPullThreshold.value = false;
}

let backButtonCleaner: (() => void) | null = null;
let resumeCleaner: (() => void) | null = null;

onMounted(() => {
  void syncStore.init();
  void updateStore.check(true);

  resumeCleaner = onAppResume(() => {
    void updateStore.check(true);
  });

  window.addEventListener('touchstart', onTouchStart, { passive: true });
  window.addEventListener('touchmove', onTouchMove, { passive: false });
  window.addEventListener('touchend', onTouchEnd, { passive: true });
  window.addEventListener('touchcancel', onTouchCancel, { passive: true });

  backButtonCleaner = setupHardwareBack({
    onBack: (canGoBack) => {
      // 1. 若当前记账抽屉处于打开状态，优先关闭抽屉
      if (ui.sheetOpen) {
        ui.closeSheet();
        return true;
      }
      // 2. 若在非主落地页（例如设置/报表等二级界面），优先返回上一页
      if (route.name !== 'ledger' && route.name !== 'dashboard' && canGoBack) {
        router.back();
        return true;
      }
      return false;
    },
    onExit: () => {
      void exitNativeApp();
    },
  });
});

onUnmounted(() => {
  window.removeEventListener('touchstart', onTouchStart);
  window.removeEventListener('touchmove', onTouchMove);
  window.removeEventListener('touchend', onTouchEnd);
  window.removeEventListener('touchcancel', onTouchCancel);
  if (backButtonCleaner) {
    backButtonCleaner();
  }
  if (resumeCleaner) {
    resumeCleaner();
  }
});
</script>

<template>
  <RouterView v-if="!showChrome" />

  <div
    v-else
    class="min-h-full bg-canvas text-ink"
    :style="{
      transform: pullOffset > 0 ? `translateY(${pullOffset}px)` : undefined,
      transition: isPullTransitioning ? 'transform 0.24s cubic-bezier(0.2, 0.8, 0.2, 1)' : undefined,
      willChange: pullOffset > 0 ? 'transform' : undefined,
    }"
  >
    <!-- 移动端下拉记账指示胶囊（跟手动效与视觉反馈） -->
    <div
      v-if="pullOffset > 0"
      class="pointer-events-none fixed inset-x-0 top-3 z-[60] flex justify-center lg:hidden"
      :style="{
        opacity: Math.min(1, pullOffset / 20),
        transform: `translateY(${Math.min(pullOffset * 0.35, 20)}px)`,
        transition: isPullTransitioning ? 'all 0.24s cubic-bezier(0.2, 0.8, 0.2, 1)' : undefined,
      }"
    >
      <div
        class="flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-xs font-semibold shadow-md backdrop-blur transition-all duration-150"
        :class="
          isPullThreshold
            ? 'border-primary/60 bg-surface text-primary scale-105 shadow-primary/10'
            : 'border-line/80 bg-surface/90 text-ink-muted'
        "
      >
        <component
          :is="isPullThreshold ? Plus : ArrowDown"
          :size="14"
          :stroke-width="2.5"
          class="transition-transform duration-200"
          :class="{ 'rotate-180': !isPullThreshold && pullOffset > 32 }"
        />
        <span>{{ isPullThreshold ? '松开立即记账' : '下拉记一笔' }}</span>
      </div>
    </div>

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

        <!-- 同步状态提示（仅在有待发队列或正在同步时展示，避免离线/在线切换引起顶栏抖动） -->
        <button
          v-if="syncStore.hasPending || syncStore.isSyncing"
          type="button"
          :title="syncStore.isSyncing ? '正在与服务器同步' : '有待发送的离线记录，点击立即同步'"
          class="mr-2 inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium transition-colors"
          :class="{
            'bg-amber-100 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300': !syncStore.isSyncing,
            'bg-sunken text-primary-text': syncStore.isSyncing,
          }"
          :disabled="syncStore.isSyncing || !syncStore.isOnline"
          @click="syncStore.runSync()"
        >
          <span
            v-if="syncStore.isSyncing"
            class="inline-block h-2 w-2 animate-ping rounded-full bg-primary"
          />
          <span v-else class="inline-block h-2 w-2 rounded-full bg-amber-500" />
          <span v-if="syncStore.isSyncing">同步中…</span>
          <span v-else>待同步 {{ syncStore.pendingCount }}</span>
        </button>

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

    <!-- 应用自动更新弹窗 -->
    <UpdateDialog />
  </div>
</template>
