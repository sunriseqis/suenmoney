/**
 * 安装包下载短期令牌（30 分钟）。
 *
 * 为什么需要它：
 *   - 原生端或外部下载工具（如浏览器或某些网络客户端）在通过 URL 访问
 *     `/api/update/download` 时无法附加 Authorization: Bearer 头；
 *   - 经由已登录的 `/api/update/check` 顺带签发一个 30 分钟短期令牌，
 *     客户端将 `?token=` 拼入下载链接完成鉴权，避免安装包下载被未授权人员遍历。
 *   - 签名覆盖平台（platform），防止跨平台伪造。
 */

import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { config } from '../config.ts';

export const UPDATE_TOKEN_TTL_MS = 30 * 60 * 1000;

const ephemeralSecret = randomBytes(32).toString('hex');
const getSecret = (): string => config.updateSecret || ephemeralSecret;

function sign(platform: string, expiresAt: number): string {
  return createHmac('sha256', getSecret())
    .update(`update:${platform}:${expiresAt}`)
    .digest('hex')
    .slice(0, 32);
}

export function signUpdateToken(
  platform: string,
  ttlMs: number = UPDATE_TOKEN_TTL_MS,
): string {
  const expiresAt = Date.now() + ttlMs;
  return `${expiresAt}.${sign(platform, expiresAt)}`;
}

export function verifyUpdateToken(platform: string, token: string | undefined): boolean {
  if (!token) return false;

  const dot = token.indexOf('.');
  if (dot <= 0) return false;

  const expiresAt = Number(token.slice(0, dot));
  const provided = token.slice(dot + 1);

  if (!Number.isFinite(expiresAt)) return false;
  if (expiresAt <= Date.now()) return false;

  const expected = sign(platform, expiresAt);

  try {
    const providedBuf = Buffer.from(provided);
    if (expected.length !== providedBuf.length) return false;
    return timingSafeEqual(Buffer.from(expected), providedBuf);
  } catch {
    return false;
  }
}
