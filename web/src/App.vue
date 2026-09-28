<script setup lang="ts">
/**
 * 应用外壳：路由出口 + 导航 + 记账抽屉。
 *
 * 记账抽屉挂在外壳上而不是某个视图里，因为它是**全局动作**：
 * 首页、流水页都能唤起它，而它弹出后要盖住导航。
 *
 * 导航有两套，靠 CSS 断点切换而不是 JS 判断窗口宽度：
 *   手机（<1024px）—— 底部固定栏，拇指够得到
 *   桌面（≥1024px）—— 顶部粘性栏，鼠标/键盘顺手，也才放得下文字标签
 * 用 CSS 的好处是首屏不会先渲染出一套再跳成另一套，也不需要监听 resize。
 */
import { ChartColumn, House, Plus, ReceiptText } from '@lucide/vue';
import { computed } from 'vue';
import { RouterLink, RouterView, useRoute } from 'vue-router';

import ExpenseSheet from '@/components/ExpenseSheet.vue';
import { useUiStore } from '@/stores/ui';

const route = useRoute();
const ui = useUiStore();

/** 登录页是独立的一屏，不套外壳 */
const showChrome = computed(() => route.meta['public'] !== true);

/**
 * 主导航。
 *
 * 图标是必需的，不是装饰：纯文字时这几个词全靠读字才能分辨，
 * 而图标让手指（和眼睛）在读懂文字之前就先记住了位置。
 */
const NAV = [
  { name: 'dashboard', label: '首页', icon: House },
  { name: 'ledger', label: '流水', icon: ReceiptText },
  { name: 'report', label: '报表', icon: ChartColumn },
] as const;

function onSaved(): void {
  ui.markDataChanged();
}
</script>

<template>
  <RouterView v-if="!showChrome" />

  <div v-else class="min-h-full bg-canvas text-ink">
    <!--
      桌面顶部导航。
      「计划」与「设置」放在这里而不是主 tab 里：它们是低频但重要的页面，
      不该占手机底部栏的格子；而在桌面上横向空间充裕，直接平铺开即可。
    -->
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

    <!--
      页面切换：淡入 + 轻微上浮。
      out-in 是必须的 —— 不加的话两屏会同时存在一帧，窄屏上肉眼可见地"闪"一下。
    -->
    <RouterView v-slot="{ Component }">
      <Transition name="page" mode="out-in">
        <component :is="Component" />
      </Transition>
    </RouterView>

    <!--
      手机底部入口（桌面隐藏）。没有悬浮球：悬浮按钮会盖住列表最后一条，
      且滚动时始终悬在内容上。
    -->
    <nav
      class="fixed inset-x-0 bottom-0 z-[var(--z-bottom-bar)] bg-surface pb-[var(--safe-bottom)] lg:hidden"
      aria-label="主导航"
    >
      <div
        class="mx-auto flex h-[var(--bottom-bar-h)] w-full max-w-[var(--content-max)] items-center gap-1 px-3"
      >
      <!--
        「记一笔」在最右，且**不是**普通 tab。

        （上一轮的注释在这里写着「记一笔是普通 tab，不是特殊按钮」，那句在当时是对的，
        现在不对了 —— 位置与底衬都特殊化了，所以这段注释必须跟着改，
        否则下一个人会照旧注释把它改回去。）

        位置：从中间第 3 格移到最右第 4 格。夹在「流水」与「报表」之间时，
        它是三个 tab 中间的一个洞 —— 想切到报表得绕过它，而它本身又不是页面。

        样式：**软色底衬**（32px 圆角色块）而不是实心主色。
        它常驻不高亮（点开就进抽屉，没有「选中」这个状态），但需要比另外三个
        tab 醒目。软底衬正好表达「同一组里的特殊项」，又不会像实心主色那样
        与三个 tab 的激活态打架。
        桌面顶栏那枚（见上）用的是实心主色，这个差异是**刻意的**：它在顶栏右侧
        独立成块、不与任何 tab 同组；底栏这枚与三个 tab 同组，才必须区分层级。
      -->
      <template v-for="item in NAV" :key="item.name">
        <RouterLink
          :to="{ name: item.name }"
          class="flex flex-1 flex-col items-center justify-center rounded-md text-xs font-semibold transition-colors duration-200"
          :class="route.name === item.name ? 'text-primary-text' : 'text-ink-muted hover:text-ink'"
        >
          <!--
            选中项用更粗的描边（2 → 2.5）而不是换色或加背景：
            Flat 没有阴影可用，颜色又已经承担了语义，粗细是这里唯一干净的手段。
          -->
          <component
            :is="item.icon"
            :size="20"
            :stroke-width="route.name === item.name ? 2.5 : 2"
            aria-hidden="true"
          />
          <span class="mt-0.5">{{ item.label }}</span>
        </RouterLink>
      </template>

      <button
        type="button"
        class="flex flex-1 flex-col items-center justify-center rounded-md text-xs font-semibold text-primary-text transition-transform duration-200 active:scale-95"
        aria-label="记一笔"
        @click="ui.openCreate()"
      >
        <span class="grid h-8 w-8 place-items-center rounded-sm bg-primary-fill/12">
          <Plus :size="20" :stroke-width="2.5" aria-hidden="true" />
        </span>
        <span class="mt-0.5">记一笔</span>
      </button>
      </div>
    </nav>

    <ExpenseSheet
      :open="ui.sheetOpen"
      :expense="ui.editingExpense"
      @close="ui.closeSheet()"
      @saved="onSaved"
    />
  </div>
</template>
