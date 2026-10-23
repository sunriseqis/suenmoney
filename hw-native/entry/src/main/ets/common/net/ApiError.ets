/**
 * 接口错误分类。
 *
 * 为什么要分类而不是统一抛「网络错误」：
 *   - unauthorized（401）→ 跳登录，而不是提示「网络不好」
 *   - network（连不上/超时）→ 进入离线模式、写入走 Outbox
 *   - server（5xx）→ 可重试，提示「稍后再试」
 *   - client（4xx）→ 是请求写错了，重试也没用，直接把服务端的 message 显示出来
 * 四类混成一句「请求失败」会让用户和我们都无法判断下一步该做什么。
 */
export type ApiErrorKind = 'network' | 'unauthorized' | 'client' | 'server' | 'parse';

export class ApiError extends Error {
  readonly kind: ApiErrorKind;
  readonly status: number;
  readonly code: string;

  constructor(kind: ApiErrorKind, message: string, status: number = 0, code: string = '') {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
    this.code = code;
  }

  /** 是否值得重试（网络与服务端错误可重试，其余不可） */
  get retryable(): boolean {
    return this.kind === 'network' || this.kind === 'server';
  }
}
