<script setup lang="ts">
/**
 * 应用外壳：路由出口 + 导航 + 记账抽屉。
 *
 * 铁律（§五 第 10 条 · §6.6）：
 *   1. 桌面（≥1024px）：顶栏导航（概况 / 流水 / 报表 / 设置 / 记一笔）。
 *   2. 移动端（<1024px）：单页化，彻底移除底栏，主落地页为流水页；三页（概况 / 报表 / 设置）降为二级页。
 *   3. 下拉手势唤出记账：在滚动到顶部时下拉 > 60px 触发创建抽屉。
 */
import { ArrowDown, ChartColumn, ChevronLeft, House, Moon, Plus, ReceiptText, Settings2, Sun } from '@lucide/vue';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { RouterLink, RouterView, useRoute, useRouter } from 'vue-router';

import BrandMark from '@/components/BrandMark.vue';
import ExpenseSheet from '@/components/ExpenseSheet.vue';
import UpdateDialog from '@/components/UpdateDialog.vue';
import { useTheme } from '@/composables/useTheme';
import { exitNativeApp, onAppResume, setupHardwareBack, triggerHaptic } from '@/platform';
import { usePlansStore } from '@/stores/plans';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import { useUpdateStore } from '@/stores/update';

const route = useRoute();
const router = useRouter();
const ui = useUiStore();
const syncStore = useSyncStore();
const updateStore = useUpdateStore();
const theme = useTheme();
const plansStore = usePlansStore();

/** 侧边栏「概况」上的待办角标 */
const pendingTodoCount = computed(() => plansStore.dueTodos.length);

/** 年度报告页把「报表」也点亮（原型同款行为） */
function isNavActive(name: string): boolean {
  const current = String(route.name);
  if (name === 'report') return current === 'report' || current === 'annual-summary';
  return current === name;
}

/** 登录页是独立的一屏，不套外壳 */
const showChrome = computed(() => route.meta['public'] !== true);

/**
 * 侧边栏主导航（原型 v7 外壳）：
 * 桌面 = 左侧 244px 栏；移动 = 横向药丸条（原型 @media 860px 规则）。
 */
const NAV = [
  { name: 'dashboard', label: '概况', icon: House, sub: 'OVERVIEW' },
  { name: 'ledger', label: '流水', icon: ReceiptText, sub: 'LEDGER' },
  { name: 'report', label: '报表', icon: ChartColumn, sub: 'REPORTS' },
  { name: 'settings', label: '设置', icon: Settings2, sub: 'SETTINGS' },
] as const;

/** 顶栏标题/副标题（原型 PAGE_META） */
const PAGE_META: Record<string, { title: string; sub: string }> = {
  dashboard: { title: '概况', sub: 'OVERVIEW · 本月支出与待办提醒' },
  ledger: { title: '流水', sub: 'LEDGER · 逐笔明细与检索' },
  report: { title: '报表', sub: 'REPORTS · 当月情况 / 构成 / 涨跌' },
  'annual-summary': { title: '年度报告', sub: 'ANNUAL SUMMARY' },
  settings: { title: '设置', sub: 'SETTINGS · 账目 / 计划与还款 / 数据 / 家庭' },
};

const pageMeta = computed(() => PAGE_META[String(route.name)] ?? { title: '', sub: '' });

/**
 * 原型双主题：candy（水果硬糖）/ cyber（赛博朋克）。
 * 应用旧主题档位（dark/light/system）映射到这里 —— 不新增用户可见选项，
 * 只是把「深色」翻译成 cyber、「浅色」翻译成 candy。
 */
const protoTheme = computed<'candy' | 'cyber'>(() => theme.proto.value);

/** 原型是「点一下就切」，所以顶栏按钮在 candy↔cyber 之间翻转 */
function toggleProtoTheme(): void {
  theme.set(protoTheme.value === 'cyber' ? 'light' : 'dark');
}

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
  // 更新检查：平台门禁在 store 内。鸿蒙下会在那里安静返回（不发请求、不弹窗），
  // 所以这里无需为鸿蒙单独分支，保持一处判断。
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
  <!-- 登录/初始化是独立一屏，不套外壳 -->
  <RouterView v-if="!showChrome" />

  <div
    v-else
    class="app"
    :data-theme="protoTheme"
    data-decor="on"
    :style="{
      transform: pullOffset > 0 ? `translateY(${pullOffset}px)` : undefined,
      transition: isPullTransitioning ? 'transform 0.24s cubic-bezier(0.2, 0.8, 0.2, 1)' : undefined,
      willChange: pullOffset > 0 ? 'transform' : undefined,
    }"
  >
    <!-- 浅色背景装饰几何（原型 .deco-a~d，深色下自动隐藏） -->
    <span class="deco deco-a" />
    <span class="deco deco-b" />
    <span class="deco deco-c" />
    <span class="deco deco-d" />

    <div class="shell">
      <!-- ═══════ 侧边栏（桌面 244px / 移动 横向药丸条）═══════ -->
      <aside class="sidebar">
        <RouterLink :to="{ name: 'ledger' }" class="brand" aria-label="回到流水">
          <BrandMark :size="46" />
          <span class="brand-txt">
            <span class="brand-name">同账</span>
            <span class="brand-sub">FAMILY LEDGER · 单账本</span>
          </span>
        </RouterLink>

        <nav class="nav" aria-label="主导航">
          <div class="nav-cap">账目</div>
          <RouterLink
            v-for="item in NAV"
            :key="item.name"
            :to="{ name: item.name }"
            class="nav-item"
            :class="{ 'is-on': isNavActive(item.name) }"
            :aria-current="isNavActive(item.name) ? 'page' : undefined"
          >
            <component :is="item.icon" :size="16" aria-hidden="true" />
            <span>{{ item.label }}</span>
            <span v-if="item.name === 'dashboard' && pendingTodoCount > 0" class="nav-dot">
              {{ pendingTodoCount }}
            </span>
          </RouterLink>
        </nav>

        <div class="side-foot">
          <!-- 同步状态（原型 .sync-dot）：有待发队列时可点立即同步 -->
          <button
            type="button"
            class="members"
            :disabled="syncStore.isSyncing || !syncStore.isOnline"
            @click="syncStore.runSync()"
          >
            <span class="members-txt">
              <b>{{ syncStore.hasPending ? `待同步 ${syncStore.pendingCount} 笔` : '已同步' }}</b>
              只记支出 · 整数分
            </span>
            <span class="sync-dot"><i />SYNC</span>
          </button>
          <div class="tiny muted" style="line-height: 1.6; padding-left: 4px">
            退款以负数冲销<br />账期按还款日归属
          </div>
        </div>
      </aside>

      <!-- ═══════ 主区 ═══════ -->
      <div class="main">
        <header class="topbar">
          <!-- 移动端：非流水页显示返回（原型 topbar-back） -->
          <button
            v-if="route.name !== 'ledger'"
            type="button"
            class="icon-btn mobile-only"
            :aria-label="route.name === 'annual-summary' ? '返回报表' : '返回流水'"
            @click="router.push({ name: route.name === 'annual-summary' ? 'report' : 'ledger' })"
          >
            <ChevronLeft :size="16" />
          </button>

          <div class="topbar-txt">
            <div class="topbar-title">{{ pageMeta.title }}</div>
            <div class="topbar-sub">{{ pageMeta.sub }}</div>
          </div>

          <div class="topbar-actions">
            <button
              type="button"
              class="icon-btn"
              :aria-label="protoTheme === 'cyber' ? '切换到水果硬糖' : '切换到赛博朋克'"
              @click="toggleProtoTheme"
            >
              <component :is="protoTheme === 'cyber' ? Sun : Moon" :size="17" />
            </button>
            <button
              type="button"
              class="btn btn--primary desktop-only"
              @click="ui.openCreate()"
            >
              <Plus :size="14" :stroke-width="2.4" aria-hidden="true" />
              记一笔
            </button>
          </div>
        </header>

        <main class="content">
          <!-- 移动端下拉记账提示（原型 .pull-hint / .pull-bar） -->
          <div class="pull-hint mobile-only">
            <span><ArrowDown :size="11" /></span>下拉记一笔
          </div>
          <div v-if="pullOffset > 0" class="pull-bar" :style="{ height: `${pullOffset}px` }" aria-hidden="true">
            {{ isPullThreshold ? '松开记一笔' : '下拉记一笔' }}
          </div>

          <RouterView v-slot="{ Component }">
            <Transition name="page" mode="out-in">
              <component :is="Component" />
            </Transition>
          </RouterView>
        </main>
      </div>
    </div>

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
