/**
 * 极简入参校验。
 *
 * 不引入 zod / ajv 的理由：本项目一共十来个接口、参数形状稳定，而引入
 * 校验库意味着「schema 定义」与「SQL 列」两套形状要手工保持一致。
 * 这里只做「拿到正确类型的值，否则抛出 400」，把复杂度留在业务里。
 *
 * 但有一条不能省：**所有从请求里取的值都必须过这里**。直接
 * `body.amountCents as number` 会让一个字符串金额一路走到 SQL 里。
 */
import { badRequest } from './http-error.ts';

export function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw badRequest('请求体必须是一个对象');
  }
  return value as Record<string, unknown>;
}

/**
 * 取请求体，**允许整个请求体缺失**。
 *
 * 用于「所有字段都是可选的」接口。Fastify 在不带 body 的 POST 上会把
 * `request.body` 置为 `undefined`，而 `asRecord(undefined)` 会抛 400 ——
 * 一个「可选参数」的接口却要求客户端必须发个空对象，是没道理的。
 * 确认待办（spendDate 可选）就踩过这个坑。
 */
export function optionalRecord(value: unknown): Record<string, unknown> {
  if (value === undefined || value === null) return {};
  return asRecord(value);
}

export function requireString(body: Record<string, unknown>, field: string): string {
  const value = body[field];
  if (typeof value !== 'string' || value.trim() === '') {
    throw badRequest(`缺少参数或类型错误：${field}`);
  }
  return value.trim();
}

export function optionalString(
  body: Record<string, unknown>,
  field: string,
  fallback: string,
): string {
  const value = body[field];
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'string') {
    throw badRequest(`参数类型错误：${field}`);
  }
  return value.trim();
}

export function requireInt(body: Record<string, unknown>, field: string): number {
  const value = body[field];
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw badRequest(`缺少参数或类型错误（应为整数）：${field}`);
  }
  return value;
}

/**
 * 取一个「可空字符串」，**保留 undefined 与 null 的区别**：
 *
 *   字段缺失      → `undefined`（这次请求不动它）
 *   null 或 ''    → `null`（这次请求把它清空）
 *   其它字符串    → 去空格后的值
 *
 * 与 `optionalString` 的区别就在这里。后者把 undefined 和 null 一起映射到
 * 同一个 fallback，于是「把它清空」和「不动它」变成了同一件事 ——
 * PATCH 接口一旦这么写，清空操作永远做不到，而且不会报错。
 */
export function optionalNullableString(
  body: Record<string, unknown>,
  field: string,
): string | null | undefined {
  const value = body[field];
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') throw badRequest(`参数类型错误：${field}`);

  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

export function optionalInt(
  body: Record<string, unknown>,
  field: string,
): number | undefined {
  const value = body[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isInteger(value)) {
    throw badRequest(`参数类型错误（应为整数）：${field}`);
  }
  return value;
}

export function requireEnum<T extends string>(
  body: Record<string, unknown>,
  field: string,
  allowed: readonly T[],
): T {
  const value = body[field];
  if (typeof value !== 'string' || !allowed.includes(value as T)) {
    throw badRequest(`参数取值非法：${field}（可选：${allowed.join(' / ')}）`);
  }
  return value as T;
}

export function optionalBool(
  body: Record<string, unknown>,
  field: string,
  fallback: boolean,
): boolean {
  const value = body[field];
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'boolean') {
    throw badRequest(`参数类型错误（应为布尔值）：${field}`);
  }
  return value;
}

/** 从查询串里取可选的字符串。 */
export function optionalStrParam(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string') throw badRequest(`查询参数类型错误：${field}`);
  return value.trim();
}

/** 从查询串里取可选的整数。 */
export function optionalIntParam(value: unknown, field: string): number | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) throw badRequest(`查询参数必须是整数：${field}`);
  return parsed;
}

/**
 * 从查询串里取可选的枚举值。
 *
 * 不用 `as` 直接断言：拼错一个状态值会静默匹配到空结果集，
 * 界面上表现为「待办明明是有的却一条都不显示」，而没有任何报错。
 */
export function optionalEnumParam<T extends string>(
  value: unknown,
  field: string,
  allowed: readonly T[],
): T | undefined {
  const raw = optionalStrParam(value, field);
  if (raw === undefined) return undefined;
  if (!allowed.includes(raw as T)) {
    throw badRequest(`查询参数取值非法：${field}（可选：${allowed.join(' / ')}）`);
  }
  return raw as T;
}

/**
 * 从查询串里取可选的布尔值。
 *
 * 查询串里一切都是字符串，所以只认 `1` / `0` / `true` / `false` 这四种写法
 * （`request()` 客户端就是按 `1` / `0` 序列化的）。
 * **不认识的写法一律 400**，不做「非空即真」的宽松解析 ——
 * 后者会让 `?hideAcked=0` 变成 true，界面上表现为「勾掉一项筛选却多筛掉了东西」。
 */
export function optionalBoolParam(value: unknown, field: string): boolean | undefined {
  const raw = optionalStrParam(value, field);
  if (raw === undefined) return undefined;
  if (raw === '1' || raw === 'true') return true;
  if (raw === '0' || raw === 'false') return false;
  throw badRequest(`查询参数必须是布尔值（1 / 0）：${field}`);
}

/** 从路径参数里取值（`/api/expenses/:id`）。 */
export function pathParam(params: unknown, field: string): string {
  if (typeof params !== 'object' || params === null) {
    throw badRequest(`缺少路径参数：${field}`);
  }
  const value = (params as Record<string, unknown>)[field];
  if (typeof value !== 'string' || value.trim() === '') {
    throw badRequest(`缺少路径参数：${field}`);
  }
  return value.trim();
}

/** 从查询串里取可选的日期字符串。 */
export function optionalDateParam(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw badRequest(`日期参数格式必须是 YYYY-MM-DD：${field}`);
  }
  return value;
}

/** 从查询串里取可选的月份字符串。 */
export function optionalMonthParam(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}$/.test(value)) {
    throw badRequest(`月份参数格式必须是 YYYY-MM：${field}`);
  }
  return value;
}
