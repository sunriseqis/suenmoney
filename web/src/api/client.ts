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
}

function buildUrl(path: string, query: Record<string, QueryValue> | undefined): string {
  const url = new URL(path, window.location.origin);

  if (query !== undefined) {
    for (const [key, value] of Object.entries(query)) {
      // 空值一律不发：既避免 `?month=` 这种空参数触发服务端的格式校验，
      // 也让调用方可以直接写 `{ month: maybeMonth }` 而不必先过滤
      if (value === undefined || value === null || value === '') continue;
      url.searchParams.set(key, String(value));
    }
  }

  return url.toString();
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
  const headers: Record<string, string> = {};

  const token = readToken();
  if (token !== null) headers['authorization'] = `Bearer ${token}`;
  if (options.body !== undefined) headers['content-type'] = 'application/json';

  let response: Response;
  try {
    response = await fetch(buildUrl(path, options.query), {
      method: options.method ?? 'GET',
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
  } catch {
    throw new ApiError(0, '无法连接到服务器，请检查网络或服务端状态');
  }

  // 204 没有响应体，直接返回
  if (response.status === 204) return undefined as T;

  const raw = await response.text();
  let payload: unknown = null;

  if (raw !== '') {
    try {
      payload = JSON.parse(raw);
    } catch {
      // 反向代理的错误页是 HTML，走不到这里就会把「服务不可用」误报成「解析失败」
      if (!response.ok) throw toApiError(response, '');
      throw new ApiError(response.status, '服务器返回的内容无法解析');
    }
  }

  if (!response.ok) throw toApiError(response, raw);

  return payload as T;
}

export interface DownloadedFile {
  blob: Blob;
  filename: string;
}

/** 从 `content-disposition` 里抠文件名；抠不到就用调用方给的兜底名。 */
function filenameFrom(header: string | null, fallback: string): string {
  if (header === null) return fallback;
  // 服务端只发 ASCII 文件名（suenmoney-export-all-20260928.json），
  // 所以不需要 RFC 5987 的 `filename*=UTF-8''…` 那一支
  const matched = /filename="?([^";]+)"?/.exec(header);
  return matched?.[1] ?? fallback;
}

/**
 * 下载一份文件（导出包 / 对账表 / 备份）。
 *
 * ## 为什么不能用 `<a href="/api/export">`
 *
 * 令牌存在 `localStorage` 里、走 `Authorization` 头，而 `<a>` 发出的请求
 * **不带这个头**。结果是：浏览器乖乖下载了一个文件，文件名也对，
 * 但内容是 401 的 JSON —— 用户会以为「导出成功了，只是文件坏了」，
 * 然后拿着它去导入。必须走 `fetch` + `Blob` + 临时 object URL。
 *
 * 失败时走与 `request` 相同的错误路径，界面拿到的仍然是服务端那句原话
 * （例如「scope=year 需要 period=YYYY」），而不是「下载失败」。
 */
export async function downloadFile(
  path: string,
  query?: Record<string, QueryValue>,
): Promise<DownloadedFile> {
  const headers: Record<string, string> = {};
  const token = readToken();
  if (token !== null) headers['authorization'] = `Bearer ${token}`;

  let response: Response;
  try {
    response = await fetch(buildUrl(path, query), { headers });
  } catch {
    throw new ApiError(0, '无法连接到服务器，请检查网络或服务端状态');
  }

  if (!response.ok) throw toApiError(response, await response.text());

  return {
    blob: await response.blob(),
    filename: filenameFrom(response.headers.get('content-disposition'), 'suenmoney-download'),
  };
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
