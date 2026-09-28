import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router';

import { useAuthStore } from '@/stores/auth';
import DashboardView from '@/views/DashboardView.vue';
import LedgerView from '@/views/LedgerView.vue';
import LoginView from '@/views/LoginView.vue';
import ReportView from '@/views/ReportView.vue';
import SettingsView from '@/views/SettingsView.vue';

/**
 * 底部导航只放三个高频入口（首页 / 流水 / 报表）加一个「记一笔」。
 * 计划与设置是「低频但重要」的页面，从首页头部进入 —— 塞进底栏会让
 * 每天要点几十次的那几个入口变窄，得不偿失。
 */
const routes: RouteRecordRaw[] = [
  { path: '/login', name: 'login', component: LoginView, meta: { public: true } },
  {
    path: '/',
    redirect: () => {
      const isMobile = typeof window !== 'undefined' && window.innerWidth < 1024;
      return isMobile ? { name: 'ledger' } : { name: 'dashboard' };
    },
  },
  { path: '/dashboard', name: 'dashboard', component: DashboardView },
  { path: '/ledger', name: 'ledger', component: LedgerView },
  { path: '/report', name: 'report', component: ReportView },
  { path: '/settings', name: 'settings', component: SettingsView },
  // 记账抽屉是「动作」而不是「页面」，所以没有独立路由 —— 见 components/ExpenseSheet.vue
  { path: '/:pathMatch(.*)*', redirect: '/' },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
});

/**
 * 登录守卫。
 *
 * 第一次导航时先 `bootstrap()` 恢复登录态（用它内部的 ready 标记保证只跑一次）。
 * 这一步不能放在组件里做：放在 App.vue 里会导致「刷新页面时先渲染一帧主页、
 * 再跳登录页」的闪烁，而放在这里可以在渲染之前就决定去哪。
 */
router.beforeEach(async (to) => {
  const authStore = useAuthStore();

  if (!authStore.ready) {
    await authStore.bootstrap();
  }

  if (to.meta['public'] !== true && !authStore.isAuthenticated) {
    return { name: 'login', query: to.fullPath === '/' ? {} : { next: to.fullPath } };
  }

  if (to.name === 'login' && authStore.isAuthenticated) {
    const isMobile = typeof window !== 'undefined' && window.innerWidth < 1024;
    return isMobile ? { name: 'ledger' } : { name: 'dashboard' };
  }

  return true;
});
