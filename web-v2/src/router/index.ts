import { createRouter, createWebHistory, type RouteRecordRaw } from 'vue-router';

import { useAuthStore } from '@/stores/auth';

/**
 * 路由骨架（重构版）。
 *
 * 与旧版的差异只有一处：移动端判定阈值从 1024 改成 **860**，
 * 与原型 `.sidebar` 折叠成横向药丸条的断点一致 —— 两个断点不同步会出现
 * 「侧边栏已经是移动形态、路由还当桌面」的错位。
 *
 * 视图用**懒加载**：首屏只需要登录/流水，报表与设置按需拉取，
 * 移动端弱网下首屏更快。
 */
const MOBILE_MAX = 860;

function isMobile(): boolean {
  return typeof window !== 'undefined' && window.innerWidth <= MOBILE_MAX;
}

const routes: RouteRecordRaw[] = [
  { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue'), meta: { public: true } },
  {
    path: '/',
    redirect: () => (isMobile() ? { name: 'ledger' } : { name: 'dashboard' }),
  },
  { path: '/dashboard', name: 'dashboard', component: () => import('@/views/DashboardView.vue') },
  { path: '/ledger', name: 'ledger', component: () => import('@/views/LedgerView.vue') },
  { path: '/report', name: 'report', component: () => import('@/views/ReportView.vue') },
  { path: '/settings', name: 'settings', component: () => import('@/views/SettingsView.vue') },
  {
    path: '/annual-summary',
    name: 'annual-summary',
    component: () => import('@/views/AnnualSummaryView.vue'),
  },
  // 记账是「动作」不是页面，用抽屉承载，没有独立路由
  { path: '/:pathMatch(.*)*', redirect: '/' },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
});

/**
 * 登录守卫。
 * 放在守卫里而不是组件里：否则刷新时会先渲染一帧主页再跳登录，肉眼可见闪一下。
 */
router.beforeEach(async (to) => {
  const auth = useAuthStore();

  if (!auth.ready) {
    await auth.bootstrap();
  }

  if (to.meta['public'] !== true && !auth.isAuthenticated) {
    return { name: 'login', query: to.fullPath === '/' ? {} : { next: to.fullPath } };
  }

  if (to.name === 'login' && auth.isAuthenticated) {
    return isMobile() ? { name: 'ledger' } : { name: 'dashboard' };
  }

  return true;
});
