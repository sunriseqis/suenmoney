import { HttpError } from './http-error.ts';

/**
 * 进程内滑动窗口限流。
 *
 * 只用来保护登录接口，不追求精确 —— 目的很具体：不要让「一个脚本不断
 * 猜口令」这件事变得可行。家庭自用服务暴露在公网上时，这是最低限度的防线。
 *
 * 进程内存储的局限要说清楚：多副本部署时各自计数。本项目是单容器单进程，
 * 所以够用；哪天要横向扩展，这里必须换成共享存储，否则限流形同虚设。
 */
interface Bucket {
  hits: number[];
}

const buckets = new Map<string, Bucket>();

export interface RateLimitOptions {
  /** 窗口长度（毫秒） */
  windowMs: number;
  /** 窗口内允许的最大次数 */
  max: number;
}

export function enforceRateLimit(key: string, options: RateLimitOptions): void {
  const now = Date.now();
  const since = now - options.windowMs;

  const bucket = buckets.get(key) ?? { hits: [] };
  bucket.hits = bucket.hits.filter((at) => at > since);

  if (bucket.hits.length >= options.max) {
    const retryAfterMs = (bucket.hits[0] ?? now) + options.windowMs - now;
    const retryAfterSec = Math.max(1, Math.ceil(retryAfterMs / 1000));
    buckets.set(key, bucket);
    throw new HttpError(429, `尝试过于频繁，请 ${retryAfterSec} 秒后重试`);
  }

  bucket.hits.push(now);
  buckets.set(key, bucket);

  // 顺手清理过期的桶，避免长期运行后 Map 无限增长
  if (buckets.size > 1000) {
    for (const [bucketKey, value] of buckets) {
      if (value.hits.every((at) => at <= since)) buckets.delete(bucketKey);
    }
  }
}

export function resetRateLimit(key: string): void {
  buckets.delete(key);
}
