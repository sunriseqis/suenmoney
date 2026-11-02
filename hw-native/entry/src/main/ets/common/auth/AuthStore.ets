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

  /**
   * 拉当前用户（启动时校验令牌是否还有效）。
   *
   * ⚠ 只有 **401** 才清令牌。403（权限不足）、5xx（服务端重启/网关 502）、
   *   网络错误都**必须保留令牌** —— 否则一次瞬时故障就把人踢回登录页，
   *   用户看到的就是「莫名其妙掉登录」。
   *
   * 对「没结果」的失败（network / server）重试两次：服务端重启、WiFi 切 4G
   * 这类抖动通常几秒内自愈，重试比让用户重新输密码划算得多。
   */
  static async refreshMe(): Promise<UserSummary | null> {
    const MAX_ATTEMPTS = 3;
    let lastKind = '';
    for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
      try {
        const me: UserSummary = await Api.me();
        AuthStore.current = me;
        return me;
      } catch (e) {
        const err = e as ApiError;
        lastKind = err.kind;
        if (err.kind === 'unauthorized') {
          // 令牌真的失效了 —— 只有这一条路清令牌
          await ServerConfig.get().clearToken();
          AuthStore.current = null;
          return null;
        }
        // 403 / 4xx / 解析错误：登录状态没问题，直接返回，不重试也不清令牌
        if (!err.retryable) {
          return null;
        }
        // network / server：退避后重试
        if (attempt < MAX_ATTEMPTS - 1) {
          await new Promise<void>((resolve) => setTimeout(resolve, 400 * (attempt + 1)));
        }
      }
    }
    // 重试用尽仍是瞬时故障：保留令牌，按离线处理（用户仍是登录态）
    console.log(`[AuthStore] refreshMe 重试 ${MAX_ATTEMPTS} 次仍失败（${lastKind}），保留令牌走离线`);
    return null;
  }
}
