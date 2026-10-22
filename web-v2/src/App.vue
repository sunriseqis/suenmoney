<script setup lang="ts">
/**
 * 应用外壳（重构版）—— 对照原型 `app.jsx` 的 `.shell` 结构。
 *
 *   桌面：左侧 244px 固定侧边栏 + 右侧主区（顶栏 + 内容）
 *   移动（≤860px）：侧边栏变横向药丸条，顶栏保留标题与主题按钮
 *
 * 外壳**只管三件事**：导航、主题、记账入口。数据一律由页面自己取，
 * 外壳不持有业务状态（旧版把待办数量、同步状态都塞进外壳，结果每改一处
 * 都要动外壳，越改越乱）。
 */
import { ArrowDown, ChevronLeft, ChartColumn, House, Moon, Plus, ReceiptText, Settings2, Sun } from '@lucide/vue';
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { RouterView, useRoute, useRouter } from 'vue-router';

import BrandMark from '@/components/BrandMark.vue';
import ExpenseSheet from '@/components/ExpenseSheet.vue';
import { useTheme } from '@/composables/useTheme';
import { useSyncStore } from '@/stores/sync';
import { useUiStore } from '@/stores/ui';
import { PIconBtn, PBtn } from '@/ui';

const route = useRoute();
const router = useRouter();
const ui = useUiStore();
const sync = useSyncStore();
const theme = useTheme();

const buildStamp = __BUILD_STAMP__;

/** 登录/初始化是独立一屏，不套外壳 */
const showChrome = computed(() => route.meta['public'] !== true);

const NAV = [
  { name: 'dashboard', label: '概况', icon: House },
  { name: 'ledger', label: '流水', icon: ReceiptText },
  { name: 'report', label: '报表', icon: ChartColumn },
  { name: 'settings', label: '设置', icon: Settings2 },
] as const;

/** 顶栏标题（原型 PAGE_META） */
const PAGE_META: Record<string, { title: string; sub: string }> = {
  dashboard: { title: '概况', sub: 'OVERVIEW · 本月支出与待办提醒' },
  ledger: { title: '流水', sub: 'LEDGER · 逐笔明细与检索' },
  report: { title: '报表', sub: 'REPORTS · 当月情况 / 构成 / 涨跌' },
  'annual-summary': { title: '年度报告', sub: 'ANNUAL SUMMARY' },
  settings: { title: '设置', sub: 'SETTINGS · 账目 / 计划与还款 / 数据 / 家庭' },
};

const pageMeta = computed(() => PAGE_META[String(route.name)] ?? { title: '', sub: '' });

function isNavActive(name: string): boolean {
  const current = String(route.name);
  if (name === 'report') return current === 'report' || current === 'annual-summary';
  return current === name;
}

function toggleTheme(): void {
  theme.set(theme.proto.value === 'cyber' ? 'light' : 'dark');
}

/** 移动端：非流水页显示返回（流水是移动端落地页，无处可返回） */
function goBack(): void {
  router.push({ name: route.name === 'annual-summary' ? 'report' : 'ledger' });
}

// ── 移动端下拉记一笔（唯一入口，无兜底按钮：用户明确裁决过）──────────────
const PULL_THRESHOLD = 54; // 松手判定阈值（px）
const PULL_DAMPING = 0.62;
const PULL_MAX = 84;

const pull = ref(0);
const isMobile = ref(false);
let startY: number | null = null;
let mq: MediaQueryList | null = null;

function onMq(): void {
  isMobile.value = mq ? mq.matches : false;
  if (!isMobile.value) pull.value = 0;
}

function onDown(e: TouchEvent | MouseEvent): void {
  if (!isMobile.value || window.scrollY > 2) return;
  startY = 'touches' in e ? (e.touches[0]?.clientY ?? null) : e.clientY;
}

function onMove(e: TouchEvent | MouseEvent): void {
  if (startY === null || !isMobile.value || window.scrollY > 2) return;
  const y = 'touches' in e ? (e.touches[0]?.clientY ?? startY) : e.clientY;
  const dy = y - startY;
  if (dy > 8) pull.value = Math.min(PULL_MAX, dy * PULL_DAMPING);
}

function onUp(): void {
  if (startY === null) return;
  const reached = pull.value >= PULL_THRESHOLD;
  pull.value = 0;
  startY = null;
  if (reached) ui.openCreate();
}

onMounted(() => {
  mq = window.matchMedia('(max-width: 860px)');
  onMq();
  mq.addEventListener('change', onMq);
  window.addEventListener('touchstart', onDown, { passive: true });
  window.addEventListener('touchmove', onMove, { passive: true });
  window.addEventListener('touchend', onUp);
  window.addEventListener('mousedown', onDown);
  window.addEventListener('mousemove', onMove);
  window.addEventListener('mouseup', onUp);
});

onUnmounted(() => {
  mq?.removeEventListener('change', onMq);
  window.removeEventListener('touchstart', onDown);
  window.removeEventListener('touchmove', onMove);
  window.removeEventListener('touchend', onUp);
  window.removeEventListener('mousedown', onDown);
  window.removeEventListener('mousemove', onMove);
  window.removeEventListener('mouseup', onUp);
});
</script>

<template>
  <RouterView v-if="!showChrome" />

  <div v-else class="app" :data-theme="theme.proto.value" data-decor="on" data-density="cozy">
    <!-- 浅色背景装饰几何（原型 .deco-a~d；深色下 CSS 自动隐藏） -->
    <span class="deco deco-a" />
    <span class="deco deco-b" />
    <span class="deco deco-c" />
    <span class="deco deco-d" />

    <div class="shell">
      <aside class="sidebar">
        <RouterLink :to="{ name: 'ledger' }" class="brand" aria-label="回到流水">
          <BrandMark :size="46" />
          <span class="brand-txt">
            <span class="brand-name">SuenMoney</span>
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
          </RouterLink>
        </nav>

        <div class="side-foot">
          <div class="tiny muted" style="line-height: 1.6; padding-left: 4px">
            只记支出 · 整数分<br />退款以负数冲销
          </div>
          <div class="build-stamp">{{ buildStamp }}</div>
        </div>
      </aside>

      <div class="main">
        <header class="topbar">
          <PIconBtn
            v-if="route.name !== 'ledger'"
            :icon="ChevronLeft"
            :label="route.name === 'annual-summary' ? '返回报表' : '返回流水'"
            @click="goBack"
          />
          <div class="topbar-txt">
            <div class="topbar-title">{{ pageMeta.title }}</div>
            <div class="topbar-sub">{{ pageMeta.sub }}</div>
          </div>
          <div class="topbar-actions">
            <PIconBtn
              :icon="theme.proto.value === 'cyber' ? Sun : Moon"
              :label="theme.proto.value === 'cyber' ? '切换到水果硬糖' : '切换到赛博朋克'"
              @click="toggleTheme"
            />
            <PBtn variant="primary" :icon="Plus" @click="ui.openCreate()">记一笔</PBtn>
          </div>
        </header>

        <main class="content">
          <!-- 移动端下拉提示与下拉进度条（原型 .pull-hint / .pull-bar） -->
          <div class="pull-hint">
            <span><ArrowDown :size="11" /></span>下拉记一笔
          </div>
          <div v-if="pull > 0" class="pull-bar" :style="{ height: `${pull}px` }" aria-hidden="true">
            {{ pull >= PULL_THRESHOLD ? '松开记一笔' : '下拉记一笔' }}
          </div>

          <RouterView v-slot="{ Component }">
            <Transition name="page" mode="out-in">
              <component :is="Component" />
            </Transition>
          </RouterView>

          <div class="build-stamp">
            SuenMoney · 单账本家庭记账 · {{ buildStamp }}
            <span v-if="sync.hasPending"> · 待同步 {{ sync.pendingCount }}</span>
          </div>
        </main>
      </div>
    </div>

    <ExpenseSheet
      :open="ui.sheetOpen"
      :expense="ui.editingExpense"
      @close="ui.closeSheet()"
      @saved="ui.markDataChanged()"
    />
  </div>
</template>
