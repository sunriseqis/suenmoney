import type { FastifyRequest } from 'fastify';

import { getDatabase } from '../db/index.ts';
import { findSessionByToken, touchSession } from '../db/repo/sessions.ts';
import { toPublicUser, type PublicUser, type UserRow } from '../db/repo/users.ts';
import { forbidden, unauthorized } from '../lib/http-error.ts';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: {
      user: PublicUser;
      /** 原始行，权限判定与领域逻辑需要它（如 owner_id 比对） */
      userRow: UserRow;
      sessionId: string;
    };
  }
}

function extractToken(request: FastifyRequest): string | null {
  const header = request.headers.authorization;
  if (typeof header !== 'string') return null;

  const prefix = 'bearer ';
  if (header.toLowerCase().startsWith(prefix)) {
    const token = header.slice(prefix.length).trim();
    return token === '' ? null : token;
  }
  return null;
}

/**
 * 鉴权 preHandler。挂在需要登录的路由上。
 *
 * 令牌走 `Authorization: Bearer`，不用 Cookie：移动端（Capacitor WebView）
 * 对第三方 Cookie 与 SameSite 的处理各版本不一，Bearer 头在所有平台行为一致。
 */
export async function requireAuth(request: FastifyRequest): Promise<void> {
  const token = extractToken(request);
  if (token === null) throw unauthorized();

  const db = getDatabase();
  const found = findSessionByToken(db, token);
  if (found === null) throw unauthorized('登录已失效，请重新登录');

  touchSession(db, found.session.id, found.session.last_seen_at);

  request.auth = {
    user: toPublicUser(found.user),
    userRow: found.user,
    sessionId: found.session.id,
  };
}

/** 取当前登录者；未登录即抛 401（而非返回 undefined 让调用方去判断）。 */
export function currentAuth(request: FastifyRequest): NonNullable<FastifyRequest['auth']> {
  if (request.auth === undefined) throw unauthorized();
  return request.auth;
}

/**
 * 管理员校验。
 *
 * 注意：**客户端隐藏按钮不算权限控制**。所有写接口都必须在服务端
 * 重新判定一次，否则任何能发 HTTP 请求的人都能绕过界面。
 *
 * ⚠️ 必须是 `async`，不能写成同步函数。
 * Fastify 通过「hook 是否返回 Promise」来判定它的风格：同步函数返回
 * `undefined`，Fastify 会认为它在等回调结束，于是**永远等一个不会被调用的
 * done** —— 请求既不返回也不报错，就这么挂在原地。这个坑的排查成本极高，
 * 因为没有任何错误信息，表现出来只是「这个接口一直转圈」。
 */
export async function requireAdmin(request: FastifyRequest): Promise<void> {
  if (currentAuth(request).user.role !== 'admin') {
    throw forbidden('只有管理员可以执行该操作');
  }
}
