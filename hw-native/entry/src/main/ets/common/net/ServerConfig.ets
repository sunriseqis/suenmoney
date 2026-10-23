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

/** 开发期默认地址：本机能直连的实例 */
export const DEFAULT_SERVER = 'http://192.168.89.10:5310';

export class ServerConfig {
  private static instance: ServerConfig | null = null;
  private store: preferences.Preferences | null = null;
  private token: string = '';
  private servers: string[] = [DEFAULT_SERVER];
  private active: string = DEFAULT_SERVER;

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
      this.active = savedActive !== '' ? savedActive : this.servers[0];
    } catch (e) {
      this.token = '';
      this.servers = [DEFAULT_SERVER];
      this.active = DEFAULT_SERVER;
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
