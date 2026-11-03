/**
 * 登录态（H1）。
 *
 * 令牌存 preferences（ServerConfig 负责读写），这里只管「登录 / 登出 / 是否已登录」。
 * 不缓存用户资料：资料随 /api/auth/me 取 —— 缓存了会在改显示名后仍显示旧名字。
 */
import { Api, LoginBody, UserSummary } from '../net/Api';
import { ApiError } from '../net/ApiError';
import { Db } from '../store/Db';
import { ServerConfig } from '../net/ServerConfig';

/** AppStorage 键：会话是否已失效（令牌被服务端拒了，但本地数据照常可用） */
export const SESSION_EXPIRED_KEY = 'sessionExpired';
/** meta 键：当前登录用户 id（离线记账判归属用） */
export const CURRENT_USER_KEY = 'current_user_id';

export class AuthStore {
  private static current: UserSummary | null = null;

  /**
   * 会话是否已失效（服务端不认这个令牌了）。
   *
   * ⚠ 失效**不等于**要把人踢去登录页 —— 记账软件的核心数据在本地，
   *   令牌失效只意味着「暂时不能同步」。本地照常看、照常记，
   *   界面上给一条「登录已失效，重新登录后可同步」的提示就够了。
   *   真正回登录页只有两种：用户主动登出，或本地从来没登录过。
   */
  static sessionExpired: boolean = false;

  static get isAuthenticated(): boolean {
    return ServerConfig.get().authToken !== '';
  }

  static get user(): UserSummary | null {
    return AuthStore.current;
  }

  /** 登录成功：清掉「会话失效」标记（本地数据与同步都恢复正常） */
  static clearSessionExpired(): void {
    AuthStore.sessionExpired = false;
    AppStorage.setOrCreate(SESSION_EXPIRED_KEY, false);
  }

  /** 登录：成功后持久化令牌 */
  static async login(username: string, password: string): Promise<UserSummary> {
    const body: LoginBody = await Api.login(username, password);
    await ServerConfig.get().saveToken(body.token);
    AuthStore.current = body.user;
    // 把用户 id 落到 meta：离线启动时 AuthStore.current 是 null，
    // 记账要拿 owner_id（谁记归谁），没有它归属就是空。
    try {
      await Db.get().executeSql(
        'INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)',
        [CURRENT_USER_KEY, body.user.id]
      );
    } catch (e) {
      // 落库失败不影响登录
    }
    AuthStore.clearSessionExpired();
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
          /**
           * 令牌失效：**保留令牌与本地数据**，只打一个标记。
           *
           * 清掉令牌 = 把人踢回登录页 = 看不到自己的账 —— 对一个记账软件
           * 这是最糟的失败方式（服务器一挂，历史全「消失」）。
           * 保留令牌后 App 仍然进主界面、照常用本地库，只是同步暂停。
           */
          AuthStore.sessionExpired = true;
          AppStorage.setOrCreate(SESSION_EXPIRED_KEY, true);
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
