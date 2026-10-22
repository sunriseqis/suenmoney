import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import { ApiError, auth, readToken, setUnauthorizedHandler, writeToken, type User } from '@/api';
import { deviceLabel } from '@/utils/device';

const USER_KEY = 'suenmoney:user';

export function readCachedUser(): User | null {
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? (JSON.parse(raw) as User) : null;
  } catch {
    return null;
  }
}

export function writeCachedUser(user: User | null): void {
  try {
    if (user === null) localStorage.removeItem(USER_KEY);
    else localStorage.setItem(USER_KEY, JSON.stringify(user));
  } catch {
    // 忽略异常
  }
}

export const useAuthStore = defineStore('auth', () => {
  const token = ref<string | null>(readToken());
  const user = ref<User | null>(readCachedUser());

  /** 是否已尝试过恢复登录态。路由守卫靠它避免每次跳转都打一次 /me */
  const ready = ref(false);

  const isAuthenticated = computed(() => token.value !== null && user.value !== null);

  function apply(session: { token: string; user: User }): void {
    writeToken(session.token);
    writeCachedUser(session.user);
    token.value = session.token;
    user.value = session.user;
  }

  function clear(): void {
    writeToken(null);
    writeCachedUser(null);
    token.value = null;
    user.value = null;
  }

  /** 重新拉取当前用户信息（修改显示名后调用，保持缓存与展示一致） */
  async function refreshUser(): Promise<void> {
    const res = await auth.me();
    user.value = res.user;
    writeCachedUser(res.user);
  }

  /**
   * 任何请求遇到 401 都会走到这里。
   *
   * 只在「令牌确实失效」时清登录态；**网络错误不清** —— 服务端临时连不上
   * 只是暂时连不上，把用户登出会让他连「看一眼上次记的账」都做不到，
   * 而这恰恰是这个项目要解决的问题。
   */
  setUnauthorizedHandler(clear);

  async function bootstrap(): Promise<void> {
    if (token.value === null) {
      ready.value = true;
      return;
    }

    try {
      const res = await auth.me();
      user.value = res.user;
      writeCachedUser(res.user);
    } catch (error) {
      if (error instanceof ApiError && error.status === 401) clear();
      // 其余情况（网络失败、5xx）保留本地令牌与用户信息缓存，支持离线进入
    } finally {
      ready.value = true;
    }
  }

  async function login(username: string, password: string): Promise<void> {
    apply(await auth.login(username, password, deviceLabel()));
  }

  async function setup(username: string, displayName: string, password: string): Promise<void> {
    apply(await auth.setup(username, displayName, password));
  }

  async function logout(): Promise<void> {
    try {
      await auth.logout();
    } catch {
      // 令牌可能已经失效；无论服务端是否成功吊销，本地都必须清干净
    }
    clear();
  }

  return { token, user, ready, isAuthenticated, bootstrap, login, setup, logout, clear, refreshUser };
});
