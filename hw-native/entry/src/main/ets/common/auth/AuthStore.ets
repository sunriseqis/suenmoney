/**
 * 登录态（H1）。
 *
 * 令牌存 preferences（ServerConfig 负责读写），这里只管「登录 / 登出 / 是否已登录」。
 * 不缓存用户资料：资料随 /api/auth/me 取 —— 缓存了会在改显示名后仍显示旧名字。
 */
import { Api, LoginBody, UserSummary } from '../net/Api';
import { ApiError } from '../net/ApiError';
import { ServerConfig } from '../net/ServerConfig';

export class AuthStore {
  private static current: UserSummary | null = null;

  static get isAuthenticated(): boolean {
    return ServerConfig.get().authToken !== '';
  }

  static get user(): UserSummary | null {
    return AuthStore.current;
  }

  /** 登录：成功后持久化令牌 */
  static async login(username: string, password: string): Promise<UserSummary> {
    const body: LoginBody = await Api.login(username, password);
    await ServerConfig.get().saveToken(body.token);
    AuthStore.current = body.user;
    return body.user;
  }

  /** 登出：清本机令牌（不强制注销服务端会话，与 Web 一致：本机先干净） */
  static async logout(): Promise<void> {
    await ServerConfig.get().clearToken();
    AuthStore.current = null;
  }

  /** 拉当前用户（启动时校验令牌是否还有效） */
  static async refreshMe(): Promise<UserSummary | null> {
    try {
      const me: UserSummary = await Api.me();
      AuthStore.current = me;
      return me;
    } catch (e) {
      // 401 → 令牌失效，清掉；网络错 → 保留令牌，进离线
      const err = e as ApiError;
      if (err.kind === 'unauthorized') {
        await ServerConfig.get().clearToken();
      }
      return null;
    }
  }
}
