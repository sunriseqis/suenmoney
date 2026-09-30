import type { FastifyInstance, FastifyRequest } from 'fastify';

import { config } from '../config.ts';
import { getDatabase } from '../db/index.ts';
import { createSession, listSessions, revokeOtherSessions, revokeSessionByToken } from '../db/repo/sessions.ts';
import { countUsers, createUser, findUserByUsername, findUserById, updateUser, toPublicUser } from '../db/repo/users.ts';
import { forbidden, unauthorized, badRequest } from '../lib/http-error.ts';
import { hashPassword, verifyPassword } from '../lib/password.ts';
import { enforceRateLimit, resetRateLimit } from '../lib/rate-limit.ts';
import { asRecord, optionalString, requireString } from '../lib/validate.ts';
import { currentAuth, requireAuth } from './guard.ts';

/** 口令最短长度 —— 与账号管理路由保持同一标准。 */
const MIN_PASSWORD_LENGTH = 8;

/**
 * 一个固定的、不可能匹配成功的口令哈希。
 *
 * 用途：当用户名不存在时，仍然跑一次同样开销的 scrypt 校验再报错。
 * 否则「用户不存在」会立刻返回、而「密码错误」要等 ~100ms，
 * 攻击者可以据此枚举出系统里有哪些用户名（时序侧信道）。
 */
const DUMMY_HASH = hashPassword('\u0000never-matches\u0000');

/** 登录限流：同一来源 + 同一用户名，15 分钟内最多 10 次。 */
const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_ATTEMPTS = 10;

function loginKey(request: FastifyRequest, username: string): string {
  return `login:${request.ip}:${username.toLowerCase()}`;
}

export async function authRoutes(app: FastifyInstance): Promise<void> {
  /**
   * 初始化状态查询（公开，无需登录）。
   *
   * 登录页据此决定要不要展示「初始化管理员」入口：系统里已有账号时入口隐藏，
   * 免得用户点进去填完表单才被 403 打回。只暴露一个布尔值，不泄漏任何用户信息。
   */
  app.get('/api/auth/status', async () => {
    return { needsSetup: countUsers(getDatabase()) === 0 };
  });

  /**
   * 首次初始化：仅在**系统里一个用户都没有**时可用。
   *
   * 一旦存在用户，这个接口永久关闭 —— 它是「部署完第一次怎么进后台」的答案，
   * 不能成为「陌生人自己开个管理员账号」的后门。
   */
  app.post('/api/auth/setup', async (request, reply) => {
    const db = getDatabase();

    if (countUsers(db) > 0) {
      throw forbidden('系统已初始化，请直接登录。新账号请由管理员在后台创建');
    }

    const body = asRecord(request.body);
    const user = createUser(db, {
      username: requireString(body, 'username'),
      displayName: optionalString(body, 'displayName', ''),
      password: requireString(body, 'password'),
      role: 'admin',
    });

    const session = createSession(db, user.id, '首次初始化', config.sessionDays);
    return reply.code(201).send({ token: session.token, expiresAt: session.expiresAt, user });
  });

  app.post('/api/auth/login', async (request) => {
    const body = asRecord(request.body);
    const username = requireString(body, 'username');
    const password = requireString(body, 'password');
    const deviceLabel = optionalString(body, 'deviceLabel', '');

    const key = loginKey(request, username);
    enforceRateLimit(key, { windowMs: LOGIN_WINDOW_MS, max: LOGIN_MAX_ATTEMPTS });

    const db = getDatabase();
    const row = findUserByUsername(db, username);

    // 无论用户是否存在都跑一次 scrypt，避免时序泄漏（见 DUMMY_HASH 注释）
    const passwordOk = verifyPassword(password, row?.password_hash ?? DUMMY_HASH);

    if (row === null || !passwordOk) {
      // 故意不区分「用户名不存在」和「密码错误」：避免用户名枚举
      throw unauthorized('用户名或密码不正确');
    }

    resetRateLimit(key);

    const session = createSession(db, row.id, deviceLabel, config.sessionDays);
    return { token: session.token, expiresAt: session.expiresAt, user: toPublicUser(row) };
  });

  app.get('/api/auth/me', { preHandler: requireAuth }, async (request) => {
    return { user: currentAuth(request).user };
  });

  /**
   * 修改自己的显示名（自助，无需管理员）。
   *
   * 显示名是「记录人」的展示来源，两人随时可能要改（比如改了昵称）；
   * 这不该是管理员代劳的事。用户名不可改 —— 它是登录凭据的一部分，
   * 改了会让其他设备上记住的用户名失效，也方便冒充他人，交给管理员处理。
   */
  app.patch('/api/auth/me', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    const displayName = requireString(body, 'displayName').trim();
    if (displayName === '') throw badRequest('显示名不能为空');

    const user = updateUser(getDatabase(), auth.user.id, {
      displayName,
      actorId: auth.user.id,
    });
    return { user };
  });

  /**
   * 修改自己的密码（自助）：必须验证当前口令，改完吊销其他设备的会话。
   *
   * 依赖「当前口令」而不是管理员权限 —— 这是账号归属的证明；
   * 其他会话全部失效是改密的应有之义（怀疑泄漏时改密即止血）。
   */
  app.post('/api/auth/me/password', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    const currentPassword = requireString(body, 'currentPassword');
    const newPassword = requireString(body, 'newPassword');

    if (newPassword.length < MIN_PASSWORD_LENGTH) {
      throw badRequest(`口令至少 ${MIN_PASSWORD_LENGTH} 位`);
    }

    const db = getDatabase();
    const row = findUserById(db, auth.user.id);
    if (row === null || !verifyPassword(currentPassword, row.password_hash)) {
      throw badRequest('当前密码不正确');
    }

    updateUser(db, auth.user.id, { password: newPassword, actorId: auth.user.id });
    const revoked = revokeOtherSessions(db, auth.user.id, auth.sessionId);
    return { revoked, message: '密码已更新，其他设备已退出登录' };
  });

  app.post('/api/auth/logout', { preHandler: requireAuth }, async (request, reply) => {
    const db = getDatabase();
    revokeSessionByToken(db, bearerOf(request));
    return reply.code(204).send();
  });

  /** 当前登录的设备列表，用于「这是谁在登录」与单独踢下线。 */
  app.get('/api/auth/sessions', { preHandler: requireAuth }, async (request) => {
    const db = getDatabase();
    const auth = currentAuth(request);
    return {
      sessions: listSessions(db, auth.user.id).map((item) => ({
        ...item,
        current: item.id === auth.sessionId,
      })),
    };
  });

  /** 踢掉除当前设备以外的所有会话 —— 怀疑令牌泄漏时用。 */
  app.post('/api/auth/sessions/revoke-others', { preHandler: requireAuth }, async (request) => {
    const db = getDatabase();
    const auth = currentAuth(request);
    const revoked = revokeOtherSessions(db, auth.user.id, auth.sessionId);
    return { revoked };
  });
}

/** 从请求头取出 Bearer 明文令牌（仅登出等极少数场景需要明文本身）。 */
function bearerOf(request: FastifyRequest): string {
  const header = request.headers.authorization ?? '';
  const prefix = 'bearer ';
  return header.toLowerCase().startsWith(prefix) ? header.slice(prefix.length).trim() : '';
}
