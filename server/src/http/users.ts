import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import { revokeOtherSessions } from '../db/repo/sessions.ts';
import { createUser, listUsers, updateUser, type UserRole } from '../db/repo/users.ts';
import { badRequest } from '../lib/http-error.ts';
import { asRecord, optionalString, pathParam, requireEnum, requireString } from '../lib/validate.ts';
import { currentAuth, requireAdmin, requireAuth } from './guard.ts';

/** 口令最短长度。家庭自用不必强求复杂度，但太短就毫无意义。 */
const MIN_PASSWORD_LENGTH = 8;

function validatePassword(password: string): string {
  if (password.length < MIN_PASSWORD_LENGTH) {
    throw badRequest(`口令至少 ${MIN_PASSWORD_LENGTH} 位`);
  }
  return password;
}

/**
 * 账号管理。
 *
 * 列表对所有登录者开放（界面要显示「记录人」，两人需要互相看到对方的显示名），
 * 但**创建与修改仅限管理员**。注意这是服务端强制 —— 客户端隐藏按钮不算权限控制，
 * 任何能发 HTTP 请求的人都能绕过界面。
 */
export async function userRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/users', { preHandler: requireAuth }, async () => {
    return { users: listUsers(getDatabase()) };
  });

  app.post('/api/users', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const body = asRecord(request.body);

    /**
     * 新建用户的变更以**新用户自己**为 actor（createUser 内部如此约定）：
     * 在这条记录产生之前，该用户还不存在，让管理员充当 actor 会让
     * 「这个账号是谁建的」与「这条记录属于谁」两件事混在同一个字段里。
     */
    const user = createUser(getDatabase(), {
      username: requireString(body, 'username'),
      displayName: optionalString(body, 'displayName', ''),
      password: validatePassword(requireString(body, 'password')),
      role:
        body['role'] === undefined
          ? 'member'
          : requireEnum<UserRole>(body, 'role', ['admin', 'member']),
      deviceId: null,
    });

    return reply.code(201).send({ user });
  });

  app.patch('/api/users/:id', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);
    const db = getDatabase();

    const patch: Parameters<typeof updateUser>[2] = { actorId: auth.user.id };

    if (body['displayName'] !== undefined) patch.displayName = requireString(body, 'displayName');
    if (body['role'] !== undefined) {
      patch.role = requireEnum<UserRole>(body, 'role', ['admin', 'member']);
    }
    if (body['password'] !== undefined) {
      patch.password = validatePassword(requireString(body, 'password'));
    }

    const user = updateUser(db, id, patch);

    /**
     * 改了口令就把该用户的其他会话全部吊销，但保留管理员自己当前的会话
     * （管理员通常正是在自己设备上操作；若是改自己的口令，也不该把自己踢下线）。
     */
    if (patch.password !== undefined) {
      revokeOtherSessions(db, id, id === auth.user.id ? auth.sessionId : '');
    }

    return { user };
  });
}
