/**
 * WebDAV 远程安全备份 HTTP API（仅管理员）。
 */
import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  getWebdavConfig,
  getWebdavStatus,
  MIN_PASSPHRASE_LENGTH,
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
            /**
             * 备份口令是否已设置。**绝不回传口令本身** —— 前端只需要知道
             * 「要不要再让用户填一次」，回传值等于把加密密钥摊在接口里。
             */
            hasPassphrase: Boolean(config.passphrase),
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

    /*
     * 备份口令：**必须落库**，否则 runWebdavBackup 的门禁永远判定「未设置」。
     *
     * v2.1.1 之前的实现压根没读这个字段：前端发了（SettingsView 的 saveWebdav），
     * 服务端建 newConfig 时没有它，于是「保存成功」之后点备份永远返回
     * 「请先设置备份口令」。密码那边有「掩码/空 → 保留旧值」的逻辑，口令照抄一份，
     * 否则以后改地址、开关都会把口令冲掉。
     *
     * 注意这里**不**因为「启用了但没口令」就 400：保存配置和能不能上传是两件事，
     * 先填地址、回头再设口令是合理流程。真上传时由 runWebdavBackup 拦下并给出
     * 与事实一致的提示（前端另有 `hasPassphrase` 用来提前显示「尚未设置」）。
     */
    let passphrase = body['passphrase'] !== undefined ? String(body['passphrase']).trim() : '';
    if (passphrase === '******' || passphrase === '') {
      passphrase = existing?.passphrase ?? '';
    } else if (passphrase.length < MIN_PASSPHRASE_LENGTH) {
      throw badRequest(`备份口令至少 ${MIN_PASSPHRASE_LENGTH} 位`);
    }

    const newConfig: WebdavConfig = {
      url,
      username,
      password,
      ...(passphrase !== '' ? { passphrase } : {}),
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
        hasPassphrase: Boolean(newConfig.passphrase),
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
