/**
 * 带状态码的业务异常。
 *
 * 路由里直接 `throw new HttpError(403, '只能修改自己记录的支出')`，
 * 由统一的错误处理器转成 JSON —— 避免每个路由各写一遍 res.code(4xx).send()，
 * 也避免把「权限校验」这件事埋在控制流里看不出来。
 */
export class HttpError extends Error {
  readonly statusCode: number;
  readonly details: unknown;

  constructor(statusCode: number, message: string, details?: unknown) {
    super(message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.details = details ?? null;
  }
}

export const badRequest = (message: string, details?: unknown): HttpError =>
  new HttpError(400, message, details);

export const unauthorized = (message = '请先登录'): HttpError => new HttpError(401, message);

export const forbidden = (message = '没有权限执行该操作'): HttpError => new HttpError(403, message);

export const notFound = (message = '资源不存在'): HttpError => new HttpError(404, message);

export const conflict = (message: string): HttpError => new HttpError(409, message);
