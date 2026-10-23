/**
 * HTTP 客户端（H0-3）。
 *
 * 三条设计约束，都来自踩过的坑：
 *   1. **超时分开设**：connect 4s / read 10s。连接阶段慢说明地址不通，快点失败
 *      才能尽快换下一个服务端；读阶段慢说明服务端在算（报表聚合），给足时间。
 *   2. **错误必须分类**（见 ApiError）：401 要跳登录，网络错误要进离线模式，
 *      两者混成一句「请求失败」会让后续逻辑全部走错分支。
 *   3. **非 2xx 也要读出服务端 message**：服务端的错误文案是中文、可读的，
 *      直接显示比我们自己编「操作失败」有用。
 *
 * 认证：`POST /api/auth/login` 拿 token，之后一律 `Authorization: Bearer <token>`。
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

import { ApiError, ApiErrorKind } from './ApiError';
import { ServerConfig } from './ServerConfig';

const CONNECT_TIMEOUT_MS = 4000;
const READ_TIMEOUT_MS = 10000;

/** 服务端统一错误体：{ error, details } */
interface ServerErrorBody {
  error?: string;
  details?: string;
  code?: string;
}

export type HttpMethod = 'GET' | 'POST' | 'PATCH' | 'DELETE';

class RequestOptions {
  method: HttpMethod = 'GET';
  body: string | null = null;
  /** 覆盖读超时（报表聚合、批量导入这类长事务型请求用） */
  readTimeoutMs: number = READ_TIMEOUT_MS;
  /** 是否带 Bearer（登录、status 不需要） */
  withAuth: boolean = true;
}

export class ApiClient {
  private static instance: ApiClient | null = null;
  private client: http.HttpRequest | null = null;

  static get(): ApiClient {
    if (ApiClient.instance === null) {
      ApiClient.instance = new ApiClient();
    }
    return ApiClient.instance;
  }

  private ensureClient(): http.HttpRequest {
    if (this.client === null) {
      this.client = http.createHttp();
    }
    return this.client;
  }

  /** 请求并反序列化成 T */
  async request<T>(path: string, options: RequestOptions): Promise<T> {
    const cfg = ServerConfig.get();
    const url = path.startsWith('http') ? path : `${cfg.baseUrl}${path}`;

    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (options.withAuth && cfg.authToken !== '') {
      headers['Authorization'] = `Bearer ${cfg.authToken}`;
    }

    // ArkTS 不允许把对象字面量展开进另一个字面量（arkts-no-spread），
    // 所以先建好再按需赋值 —— 顺手也让「有没有 body」这件事显式。
    const reqOptions: http.HttpRequestOptions = {
      method: this.toMethod(options.method),
      header: headers,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: options.readTimeoutMs,
      expectDataType: http.HttpDataType.STRING
    };
    if (options.body !== null) {
      reqOptions.extraData = options.body;
    }

    let response: http.HttpResponse;
    try {
      response = await this.ensureClient().request(url, reqOptions);
    } catch (e) {
      const err = e as BusinessError;
      throw new ApiError('network', `连不上服务端（${err.code ?? '未知'}）`, 0, String(err.code ?? ''));
    }

    const status = response.responseCode as number;
    const text = typeof response.result === 'string' ? response.result : '';

    if (status >= 200 && status < 300) {
      if (text === '') {
        // 204 / 空体：调用方按 void 用
        return undefined as T;
      }
      try {
        return JSON.parse(text) as T;
      } catch (e) {
        throw new ApiError('parse', '服务端返回的不是合法 JSON', status);
      }
    }

    throw this.toError(status, text);
  }

  /** 便捷方法 */
  get<T>(path: string): Promise<T> {
    return this.request<T>(path, this.options('GET'));
  }

  post<T>(path: string, body: object): Promise<T> {
    const o = this.options('POST');
    o.body = JSON.stringify(body);
    return this.request<T>(path, o);
  }

  patch<T>(path: string, body: object): Promise<T> {
    const o = this.options('PATCH');
    o.body = JSON.stringify(body);
    return this.request<T>(path, o);
  }

  del<T>(path: string): Promise<T> {
    return this.request<T>(path, this.options('DELETE'));
  }

  options(method: HttpMethod): RequestOptions {
    const o = new RequestOptions();
    o.method = method;
    return o;
  }

  private toMethod(method: HttpMethod): http.RequestMethod {
    if (method === 'POST') return http.RequestMethod.POST;
    if (method === 'PATCH') return http.RequestMethod.PATCH;
    if (method === 'DELETE') return http.RequestMethod.DELETE;
    return http.RequestMethod.GET;
  }

  /** 把 HTTP 状态码与错误体归到四类之一 */
  private toError(status: number, text: string): ApiError {
    let message = `请求失败（${status}）`;
    let code = '';
    if (text !== '') {
      try {
        const body = JSON.parse(text) as ServerErrorBody;
        if (body.error !== undefined && body.error !== '') {
          message = body.error;
        }
        code = body.code ?? '';
      } catch (e) {
        // 非 JSON 错误体：保留状态码文案
      }
    }

    let kind: ApiErrorKind = 'client';
    if (status === 401 || status === 403) {
      kind = 'unauthorized';
    } else if (status >= 500) {
      kind = 'server';
    }
    return new ApiError(kind, message, status, code);
  }
}
