/**
 * 多服务端选路（H1）。
 *
 * 语义照 Web 的 `web/src/api/client.ts` 重写，不是重新发明：
 *   1. 按用户配置的**顺序**逐个探活（同源优先 → 内网 → 备用/公网）
 *   2. 每次探活 **connect 4s 失败即换下一个** —— 地址不通时快速失败，
 *      否则用户要等 3 个 10s 才看到「连不上」
 *   3. 选定后记住，后续请求直接用；再次失败才重新选路
 *   4. 全部失败 → 进离线冷却（10s 内不再探，避免每个请求都等一圈）
 *
 * 为什么不用「并发探活取最快」：家用环境里备用地址通常不可达，
 * 并发会让每次启动都白等最慢的那个超时；顺序 + 快失败更可预测。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ServerConfig } from './ServerConfig';

const DOMAIN = 0x0003;
const TAG = 'ServerRouter';
const PROBE_TIMEOUT_MS = 4000;
const COOLDOWN_MS = 10000;

export interface ProbeResult {
  url: string;
  ok: boolean;
  latencyMs: number;
  /** 失败原因（ok=false 时） */
  reason: string;
}

export class ServerRouter {
  private static chosen: string = '';
  private static cooldownUntil: number = 0;

  /** 当前是否处于离线冷却期 */
  static get isCoolingDown(): boolean {
    return Date.now() < ServerRouter.cooldownUntil;
  }

  static get current(): string {
    return ServerRouter.chosen !== '' ? ServerRouter.chosen : ServerConfig.get().baseUrl;
  }

  /** 单地址探活（登录页「测试」按钮也用它） */
  static async probe(url: string): Promise<ProbeResult> {
    const client = http.createHttp();
    const start = Date.now();
    try {
      const res = await client.request(`${url}/api/health`, {
        method: http.RequestMethod.GET,
        connectTimeout: PROBE_TIMEOUT_MS,
        readTimeout: PROBE_TIMEOUT_MS
      });
      const ms = Date.now() - start;
      const ok = (res.responseCode as number) === 200;
      return { url: url, ok: ok, latencyMs: ms, reason: ok ? '' : `HTTP ${res.responseCode}` };
    } catch (e) {
      const err = e as BusinessError;
      return { url: url, ok: false, latencyMs: Date.now() - start, reason: `连接失败(${err.code ?? '?'})` };
    } finally {
      client.destroy();
    }
  }

  /**
   * 按顺序选路：返回第一个可用的地址，全失败返回 ''。
   * 结果写入 ServerConfig（active），后续 ApiClient 直接用它。
   */
  static async choose(servers: string[]): Promise<string> {
    for (const url of servers) {
      const result = await ServerRouter.probe(url);
      hilog.info(DOMAIN, TAG, 'probe %{public}s → %{public}s %{public}dms',
        url, result.ok ? 'ok' : result.reason, result.latencyMs);
      if (result.ok) {
        ServerRouter.chosen = url;
        ServerRouter.cooldownUntil = 0;
        const cfg = ServerConfig.get();
        await cfg.setServers(servers, url);
        return url;
      }
    }
    ServerRouter.cooldownUntil = Date.now() + COOLDOWN_MS;
    return '';
  }

  /** 请求失败时调用：清掉当前选择，下次请求会重新选路 */
  static invalidate(): void {
    ServerRouter.chosen = '';
    ServerRouter.cooldownUntil = Date.now() + COOLDOWN_MS;
  }
}
