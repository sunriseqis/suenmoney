/**
 * 服务端地址与令牌存储。
 *
 * 多地址与自动选路（同源优先 → 内网 → 备用、4s 首试快速失败、10s 离线冷却）
 * 在 H1 里实现；H0 先把「读写地址 / 读写令牌」这层落地，且**键名与 Web 对齐**，
 * 便于将来互通与排错。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE = 'suenmoney';
const KEY_TOKEN = 'suenmoney:token';
const KEY_SERVERS = 'suenmoney:servers';
const KEY_ACTIVE = 'suenmoney:active-server';

/**
 * **不内置任何服务端地址**（用户裁决 2026-11-04）。
 *
 * 之前这里hardcode 着开发机的 `http://192.168.89.10:5310`，等于每个装包的人都
 * 自带一个他根本连不上的地址：装完就能看到「服务器」里填着一串别人的内网 IP，
 * 登录只会得到「连不上服务端」，还很难判断是自己填错了还是包的问题。
 * 首次装包应当是**空**的，地址由用户自己填。
 */
export const DEFAULT_SERVER = '';

export class ServerConfig {
  private static instance: ServerConfig | null = null;
  private store: preferences.Preferences | null = null;
  private token: string = '';
  private servers: string[] = [];
  private active: string = '';

  static get(): ServerConfig {
    if (ServerConfig.instance === null) {
      ServerConfig.instance = new ServerConfig();
    }
    return ServerConfig.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE);
      this.token = this.store.getSync(KEY_TOKEN, '') as string;
      const rawServers = this.store.getSync(KEY_SERVERS, '') as string;
      if (rawServers !== '') {
        const parsed = JSON.parse(rawServers) as string[];
        if (parsed.length > 0) {
          this.servers = parsed;
        }
      }
      const savedActive = this.store.getSync(KEY_ACTIVE, '') as string;
      // 没存过生效地址：取候选首项；候选也是空（首次装包）→ 保持空，让登录页显示占位符
      this.active = savedActive !== '' ? savedActive : (this.servers.length > 0 ? this.servers[0] : '');
    } catch (e) {
      this.token = '';
      this.servers = [];
      this.active = '';
    }
  }

  get authToken(): string {
    return this.token;
  }

  get baseUrl(): string {
    return this.active;
  }

  get allServers(): string[] {
    return this.servers;
  }

  async saveToken(token: string): Promise<void> {
    this.token = token;
    await this.persist(KEY_TOKEN, token);
  }

  async clearToken(): Promise<void> {
    this.token = '';
    await this.persist(KEY_TOKEN, '');
  }

  async setServers(servers: string[], active: string): Promise<void> {
    this.servers = servers;
    this.active = active;
    await this.persist(KEY_SERVERS, JSON.stringify(servers));
    await this.persist(KEY_ACTIVE, active);
  }

  private async persist(key: string, value: string): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
      await this.store.flush();
    } catch (e) {
      // 持久化失败不影响本次会话（与 Web 隐私模式同策略）
    }
  }
}
