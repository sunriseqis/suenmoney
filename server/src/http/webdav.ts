/**
 * WebDAV 远程安全备份 HTTP API（仅管理员）。
 */
import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  getWebdavConfig,
  getWebdavStatus,
  runWebdavBackup,
  saveWebdavConfig,
  testWebdav,
  type WebdavConfig,
} from '../db/repo/webdav.ts';
import { badRequest } from '../lib/http-error.ts';
import { asRecord, optionalBoolean, requireString } from '../lib/validate.ts';
import { requireAdmin, requireAuth } from './guard.ts';

export async function webdavRoutes(app: FastifyInstance): Promise<void> {
  /** 获取 WebDAV 配置及最新备份状态 */
  app.get('/api/backup/webdav', { preHandler: [requireAuth, requireAdmin] }, async () => {
    const db = getDatabase();
    const config = getWebdavConfig(db);
    const status = getWebdavStatus(db);

    return {
      config: config
        ? {
            url: config.url,
            username: config.username,
            password: config.password ? '******' : '',
            hasPassword: Boolean(config.password),
            path: config.path || '/suenmoney',
            isEnabled: config.isEnabled,
          }
        : null,
      status,
    };
  });

  /** 保存 WebDAV 配置 */
  app.put('/api/backup/webdav', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const db = getDatabase();
    const body = asRecord(request.body);
    const existing = getWebdavConfig(db);

    const url = requireString(body, 'url').trim();
    const username = requireString(body, 'username').trim();
    let password = body['password'] !== undefined ? String(body['password']).trim() : '';
    const path = (body['path'] !== undefined ? String(body['path']) : '/suenmoney').trim();
    const isEnabled = optionalBoolean(body, 'isEnabled') ?? true;

    // 若传入的是掩码 '******' 或未传，保留已有密码
    if (password === '******' || !password) {
      if (!existing?.password) {
        throw badRequest('请填写 WebDAV 密码');
      }
      password = existing.password;
    }

    const newConfig: WebdavConfig = {
      url,
      username,
      password,
      path: path.startsWith('/') ? path : `/${path}`,
      isEnabled,
    };

    saveWebdavConfig(db, newConfig);

    return {
      ok: true,
      config: {
        url: newConfig.url,
        username: newConfig.username,
        password: '******',
        hasPassword: true,
        path: newConfig.path,
        isEnabled: newConfig.isEnabled,
      },
    };
  });

  /** 测试 WebDAV 连通性 */
  app.post('/api/backup/webdav/test', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const db = getDatabase();
    const body = asRecord(request.body);
    const existing = getWebdavConfig(db);

    const url = (body['url'] !== undefined ? String(body['url']) : (existing?.url ?? '')).trim();
    const username = (body['username'] !== undefined ? String(body['username']) : (existing?.username ?? '')).trim();
    let password = body['password'] !== undefined ? String(body['password']).trim() : '';
    const path = (body['path'] !== undefined ? String(body['path']) : (existing?.path ?? '/suenmoney')).trim();

    if (password === '******' || !password) {
      if (!existing?.password) {
        throw badRequest('请填写 WebDAV 密码');
      }
      password = existing.password;
    }

    const result = await testWebdav({
      url,
      username,
      password,
      path: path.startsWith('/') ? path : `/${path}`,
      isEnabled: true,
    });

    return result;
  });

  /** 手动立即触发一次 WebDAV 备份 */
  app.post('/api/backup/webdav/run', { preHandler: [requireAuth, requireAdmin] }, async () => {
    const db = getDatabase();
    const result = await runWebdavBackup(db);
    return { ok: true, ...result };
  });
}
