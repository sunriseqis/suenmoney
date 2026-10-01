/**
 * HTTP 客户端。
 *
 * 三件事值得说明：
 *
 * 1. **网络失败要给出人话的提示**。「服务端连不上」是这个项目立项的起因，
 *    所以 `fetch` 抛错时不能让它变成一个裸 TypeError 冒到界面上，
 *    而要变成「无法连接到服务器」这种用户能据以行动的信息。
 *
 * 2. **401 统一处理**。任何请求遇到 401 都意味着令牌失效（被踢下线、
 *    会话过期、服务端数据库被重置），此时必须清掉本地令牌并回到登录页。
 *    把这个判断散在每个调用点必然会漏。
 *
 * 3. **响应体不一定是 JSON**。反向代理返回的 502/504 是 HTML，
 *    直接 `res.json()` 会抛出语法错误，把一个「服务不可用」伪装成「解析失败」。
 */

const TOKEN_KEY = 'suenmoney:token';
const SERVER_URL_KEY = 'suenmoney:server-url';
const SERVER_URLS_KEY = 'suenmoney:server-urls';
const ACTIVE_SERVER_URL_KEY = 'suenmoney:active-server-url';

let memoryActiveServerUrl: string | null = null;
let connectivityListeners: Array<(isOnline: boolean, activeUrl: string | null) => void> = [];

export function onConnectivityChange(
  listener: (isOnline: boolean, activeUrl: string | null) => void,
): () => void {
  connectivityListeners.push(listener);
  return () => {
    connectivityListeners = connectivityListeners.filter((l) => l !== listener);
  };
}

export function notifyConnectivity(isOnline: boolean, activeUrl: string | null): void {
  for (const listener of connectivityListeners) {
    try {
      listener(isOnline, activeUrl);
    } catch {
      // 忽略监听器异常
    }
  }
}

/**
 * 离线闸门时间戳。任一次网络层失败（ApiError.status === 0）后置为 now + 10s。
 *
 * 存在的理由：候选地址往往不止一个（内网/Tailscale/公网），离线时逐个都要等满超时，
 * 一次记账要卡 6~18s，界面像是死了。已知离线时直接失败、不发任何网络包，
 * 用户的操作早已落本地，立即给出「已保存在本地」比空转等待有用得多。
 * 之所以是「时间窗」而不是「布尔开关」：手机网络恢复没有可靠事件通知，
 * 用一个会过期的窗口让请求定期重新试探，才能真正恢复。
 */
let offlineUntil = 0;
const OFFLINE_COOLDOWN_MS = 10000;

/**
 * 单次候选地址的请求超时：首个 4s、其余 2.5s，且全部候选合计不超过 6s。
 *
 * 这么短是**刻意为离线场景**设计的：手机在多个候选地址间逐个空等会让界面像卡死，
 * 宁可立刻失败、让操作落本地。但它只适合短小的读写请求 —— 长事务型请求
 * （如数行/数百 KB 的批量导入）本身就可能跑几十秒，默认值会在服务端其实已写入时
 * abort 掉请求，表现为「界面报失败、数据却已进库」。这类请求用 `RequestOptions.timeoutMs`
 * 单独放宽，不要改这里的默认值。
 */
const REQUEST_FIRST_TIMEOUT_MS = 4000;
const REQUEST_RETRY_TIMEOUT_MS = 2500;
const REQUEST_TOTAL_BUDGET_MS = 6000;

/**
 * 探测/健康检查类请求不受离线闸门约束。
 * 否则闸门生效期间没有任何请求能走网络，就永远等不到探测成功来清零闸门。
 */
function isConnectivityProbe(path: string): boolean {
  return path.includes('/api/health');
}

/**
 * 读取配置的服务端地址列表（按优先级由高到低排序，通常服务端 1 为内网，2 为 Tailscale/异地，3 为公网域名）。
 */
export function readServerUrls(): string[] {
  try {
    const raw = localStorage.getItem(SERVER_URLS_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        const cleaned = parsed
          .map((u) => String(u).trim().replace(/\/+$/, ''))
          .filter(Boolean);
        if (cleaned.length > 0) return cleaned;
      }
    }
    // 兼容旧版单地址配置
    const legacy = localStorage.getItem(SERVER_URL_KEY);
    if (legacy && legacy.trim() !== '') {
      return [legacy.trim().replace(/\/+$/, '')];
    }
  } catch {
    // 隐私模式或解析失败
  }
  const defaultOrigin =
    typeof window !== 'undefined' && window.location.origin
      ? window.location.origin
      : 'http://localhost';
  return [defaultOrigin];
}

/**
 * 写入服务端地址列表并重置当前激活地址。
 */
export function writeServerUrls(urls: string[]): void {
  try {
    const cleaned = urls.map((u) => u.trim().replace(/\/+$/, '')).filter(Boolean);
    if (cleaned.length === 0) {
      localStorage.removeItem(SERVER_URLS_KEY);
      localStorage.removeItem(SERVER_URL_KEY);
      localStorage.removeItem(ACTIVE_SERVER_URL_KEY);
      memoryActiveServerUrl = null;
    } else {
      localStorage.setItem(SERVER_URLS_KEY, JSON.stringify(cleaned));
      const first = cleaned[0];
      if (first) {
        localStorage.setItem(SERVER_URL_KEY, first);
        // 若当前激活地址不在新列表内，首选第一个
        if (!cleaned.includes(memoryActiveServerUrl ?? '')) {
          setActiveServerUrl(first);
        }
      }
    }
  } catch {
    // 忽略异常
  }
}

/**
 * 读取当前激活使用的服务端地址（首选已激活的，否则退回列表第一个）。
 */
export function getActiveServerUrl(): string {
  if (memoryActiveServerUrl) return memoryActiveServerUrl;
  try {
    const saved = localStorage.getItem(ACTIVE_SERVER_URL_KEY);
    if (saved && saved.trim() !== '') {
      memoryActiveServerUrl = saved.trim().replace(/\/+$/, '');
      return memoryActiveServerUrl;
    }
  } catch {
    // 忽略异常
  }
  const urls = readServerUrls();
  memoryActiveServerUrl = urls[0] ?? 'http://localhost';
  return memoryActiveServerUrl;
}

/**
 * 切换/设定当前激活的服务端地址。
 */
export function setActiveServerUrl(url: string | null): void {
  if (url === null || url.trim() === '') {
    memoryActiveServerUrl = null;
    try {
      localStorage.removeItem(ACTIVE_SERVER_URL_KEY);
    } catch {
      // 忽略异常
    }
  } else {
    const clean = url.trim().replace(/\/+$/, '');
    memoryActiveServerUrl = clean;
    try {
      localStorage.setItem(ACTIVE_SERVER_URL_KEY, clean);
      localStorage.setItem(SERVER_URL_KEY, clean);
    } catch {
      // 忽略异常
    }
  }
}

export function readServerUrl(): string {
  return getActiveServerUrl();
}

export function writeServerUrl(url: string | null): void {
  if (url === null || url.trim() === '') {
    writeServerUrls([]);
  } else {
    const existing = readServerUrls().filter((u) => u !== url.trim());
    writeServerUrls([url.trim(), ...existing]);
  }
}

/**
 * 测试单个服务端地址连通性（带超时控制，默认 2500ms）。
 */
export async function probeServerUrl(
  url: string,
  timeoutMs = 2500,
): Promise<{ ok: boolean; status?: number; latencyMs?: number; error?: string }> {
  const clean = url.trim().replace(/\/+$/, '');
  const testUrl = `${clean}/api/health`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const start = Date.now();
  try {
    const resp = await fetch(testUrl, {
      method: 'GET',
      signal: controller.signal,
    });
    clearTimeout(timer);
    const latencyMs = Date.now() - start;
    if (resp.status >= 200 && resp.status < 500) {
      // 探测成功 => 网络确实可用，立刻解除离线闸门，让积压的请求马上重试
      offlineUntil = 0;
      return { ok: true, status: resp.status, latencyMs };
    }
    return { ok: false, status: resp.status, latencyMs, error: `HTTP ${resp.status}` };
  } catch (err) {
    clearTimeout(timer);
    const latencyMs = Date.now() - start;
    const msg =
      err instanceof Error && err.name === 'AbortError' ? '连接超时' : '无法连通';
    return { ok: false, latencyMs, error: msg };
  }
}

/**
 * 按服务端列表顺序（服务端 1 -> 服务端 2 -> 服务端 3）依次探测连通性，自动寻找并切换到第一个可用地址。
 * 当需要联网时，优先看服务端 1（内网）是否可用，不可用时无缝切换到 2、3。
 */
export async function detectAndSwitchServer(
  urls?: string[],
  timeoutMs = 2500,
): Promise<{ url: string | null; latencyMs?: number }> {
  const candidateUrls = urls && urls.length > 0 ? urls : readServerUrls();
  if (candidateUrls.length === 0) {
    notifyConnectivity(false, null);
    return { url: null };
  }

  for (const candidate of candidateUrls) {
    const res = await probeServerUrl(candidate, timeoutMs);
    if (res.ok) {
      setActiveServerUrl(candidate);
      notifyConnectivity(true, candidate);
      return { url: candidate, latencyMs: res.latencyMs };
    }
  }

  notifyConnectivity(false, null);
  return { url: null };
}

export function readToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    // 隐私模式下 localStorage 可能不可用；此时退化为「每次都要重新登录」
    return null;
  }
}

export function writeToken(token: string | null): void {
  try {
    if (token === null) localStorage.removeItem(TOKEN_KEY);
    else localStorage.setItem(TOKEN_KEY, token);
  } catch {
    /* 同上 */
  }
}

export class ApiError extends Error {
  /** HTTP 状态码；0 表示根本没连上服务器（网络层失败） */
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
  }
}

let unauthorizedHandler: (() => void) | null = null;

/** 注册 401 时的全局处理（由 auth store 注册，用于清理登录态并跳转登录页）。 */
export function setUnauthorizedHandler(handler: (() => void) | null): void {
  unauthorizedHandler = handler;
}

type QueryValue = string | number | boolean | undefined | null;

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  query?: Record<string, QueryValue>;
  /**
   * 单次请求的超时覆盖（毫秒）。
   *
   * 传入后，它同时作为**单次尝试的等待上限**与**该次请求的总预算** ——
   * 即首个候选就有这么长的等待时间，且一旦超时，后续候选不会再被尝试
   * （`remaining <= 0` 会立即 break）。离线闸门与候选地址轮换逻辑不受影响。
   *
   * 仅长事务型请求需要它（见上方默认超时的说明），普通请求不要传。
   */
  timeoutMs?: number;
}

function buildUrlFor(
  base: string,
  path: string,
  query: Record<string, QueryValue> | undefined,
): string {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  const url = new URL(normalizedPath, base.endsWith('/') ? base : `${base}/`);

  if (query !== undefined) {
    for (const [key, value] of Object.entries(query)) {
      if (value === undefined || value === null || value === '') continue;
      url.searchParams.set(key, String(value));
    }
  }

  return url.toString();
}

/** 将相对路径基于当前激活的服务端基地址解析为绝对 URL */
export function resolveUrl(path: string): string {
  const base = getActiveServerUrl();
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return new URL(normalizedPath, base.endsWith('/') ? base : `${base}/`).toString();
}

/** 读出一个非 2xx 响应里的那句话，并转成 `ApiError`。 */
function toApiError(response: Response, raw: string): ApiError {
  let message = `请求失败（${response.status}）`;

  if (raw !== '') {
    try {
      const payload: unknown = JSON.parse(raw);
      if (typeof payload === 'object' && payload !== null && 'error' in payload) {
        message = String((payload as { error: unknown }).error);
      }
    } catch {
      // 反向代理的错误页是 HTML —— 走到这里说明错误信息本来就不可读，
      // 与其把一坨 HTML 塞进界面，不如只说「服务器返回了异常响应」
      message = `服务器返回了异常响应（${response.status}）`;
    }
  }

  if (response.status === 401) {
    writeToken(null);
    unauthorizedHandler?.();
  }

  return new ApiError(response.status, message);
}

export async function request<T>(path: string, options: RequestOptions = {}): Promise<T> {
  // 离线闸门：已知离线时立即失败，异常语义仍是 ApiError(status=0)，
  // 调用方无需改动，UI 也能立刻响应而不是干等超时。
  if (Date.now() < offlineUntil && !isConnectivityProbe(path)) {
    throw new ApiError(0, '当前处于离线状态，操作已保存在本地');
  }

  const headers: Record<string, string> = {};

  const token = readToken();
  if (token !== null) headers['authorization'] = `Bearer ${token}`;
  if (options.body !== undefined) headers['content-type'] = 'application/json';

  const bodyStr = options.body === undefined ? undefined : JSON.stringify(options.body);

  // 候选地址列表：当前激活的排在最前，其余按配置顺序紧随其后
  const configuredUrls = readServerUrls();
  const currentActive = getActiveServerUrl();
  const candidateUrls = configuredUrls.includes(currentActive)
    ? [currentActive, ...configuredUrls.filter((u) => u !== currentActive)]
    : [currentActive, ...configuredUrls];

  // 总预算：全候选合计不超过 6s，超预算就不再尝试后续候选。
  // 首个候选给 4s（内网/公网首次握手可能稍慢），其余 2.5s，再长就没意义了。
  // 调用方传入 timeoutMs 时，用它统一覆盖首/重试等待上限与总预算（长事务型请求专用）。
  const firstTimeoutMs = options.timeoutMs ?? REQUEST_FIRST_TIMEOUT_MS;
  const retryTimeoutMs = options.timeoutMs ?? REQUEST_RETRY_TIMEOUT_MS;
  const totalBudgetMs = options.timeoutMs ?? REQUEST_TOTAL_BUDGET_MS;
  const budgetStart = Date.now();
  for (let i = 0; i < candidateUrls.length; i++) {
    const baseUrl = candidateUrls[i];
    if (!baseUrl) continue;
    const remaining = totalBudgetMs - (Date.now() - budgetStart);
    if (i > 0 && remaining <= 0) break;
    const fullUrl = buildUrlFor(baseUrl, path, options.query);
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Math.min(i === 0 ? firstTimeoutMs : retryTimeoutMs, remaining),
    );

    try {
      const response = await fetch(fullUrl, {
        method: options.method ?? 'GET',
        headers,
        body: bodyStr,
        signal: controller.signal,
      });
      clearTimeout(timeout);

      // 请求成功送达（服务端有响应）=> 网络可用，解除离线闸门
      offlineUntil = 0;

      // 请求成功送达（服务端有响应）
      if (baseUrl !== currentActive) {
        setActiveServerUrl(baseUrl);
        notifyConnectivity(true, baseUrl);
      }

      if (response.status === 204) return undefined as T;

      const raw = await response.text();
      let payload: unknown = null;

      if (raw !== '') {
        try {
          payload = JSON.parse(raw);
        } catch {
          if (!response.ok) throw toApiError(response, '');
          throw new ApiError(response.status, '服务器返回的内容无法解析');
        }
      }

      if (!response.ok) throw toApiError(response, raw);

      return payload as T;
    } catch (err) {
      clearTimeout(timeout);
      // 业务错误（非网络层错误，如 400/401/403/409）直接抛出，不切换服务器重试
      if (err instanceof ApiError && err.status !== 0) {
        throw err;
      }
      // 网络层失败（连不上、超时等）：落闸，防止后续请求逐候选空转；
      // 如果有其它备选服务器，继续循环重试下一个（成功会自动清闸）
      offlineUntil = Date.now() + OFFLINE_COOLDOWN_MS;
    }
  }

  // 全部候选服务端均无法连通
  throw new ApiError(0, '网络连接失败');
}

export interface DownloadedFile {
  blob: Blob;
  filename: string;
}

/** 从 `content-disposition` 里抠文件名；抠不到就用调用方给的兜底名。 */
function filenameFrom(header: string | null, fallback: string): string {
  if (header === null) return fallback;
  const matched = /filename="?([^";]+)"?/.exec(header);
  return matched?.[1] ?? fallback;
}

export async function downloadFile(
  path: string,
  query?: Record<string, QueryValue>,
): Promise<DownloadedFile> {
  // 与 request 共用同一个离线闸门：已知离线时立即失败，不空等 10s×候选数
  if (Date.now() < offlineUntil) {
    throw new ApiError(0, '当前处于离线状态，操作已保存在本地');
  }

  const headers: Record<string, string> = {};
  const token = readToken();
  if (token !== null) headers['authorization'] = `Bearer ${token}`;

  const configuredUrls = readServerUrls();
  const currentActive = getActiveServerUrl();
  const candidateUrls = configuredUrls.includes(currentActive)
    ? [currentActive, ...configuredUrls.filter((u) => u !== currentActive)]
    : [currentActive, ...configuredUrls];

  for (const baseUrl of candidateUrls) {
    if (!baseUrl) continue;
    const fullUrl = buildUrlFor(baseUrl, path, query);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    try {
      const response = await fetch(fullUrl, { headers, signal: controller.signal });
      clearTimeout(timeout);

      // 下载成功送达 => 网络可用，解除离线闸门
      offlineUntil = 0;

      if (baseUrl !== currentActive) {
        setActiveServerUrl(baseUrl);
        notifyConnectivity(true, baseUrl);
      }

      if (!response.ok) throw toApiError(response, await response.text());

      return {
        blob: await response.blob(),
        filename: filenameFrom(response.headers.get('content-disposition'), 'suenmoney-download'),
      };
    } catch (err) {
      clearTimeout(timeout);
      if (err instanceof ApiError && err.status !== 0) throw err;
      // 网络层失败：落闸，后续请求在本轮冷却期内直接失败
      offlineUntil = Date.now() + OFFLINE_COOLDOWN_MS;
    }
  }

  throw new ApiError(0, '网络连接失败');
}

/** 把下载到的 Blob 交给浏览器存盘。 */
export function saveDownload(file: DownloadedFile): void {
  const url = URL.createObjectURL(file.blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = file.filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();

  // 立刻 revoke 会让部分浏览器取消掉刚开始的下载，等这一帧走完再撤
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
