import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-webdav-test-'));
process.env['SUENMONEY_DB_PATH'] = join(tempDir, 'test.sqlite');
process.env['SUENMONEY_BACKUP_DIR'] = join(tempDir, 'backups');

const { migrate, openDatabase, getDatabase } = await import('../../src/db/index.ts');
const { createUser } = await import('../../src/db/repo/users.ts');
const { buildServer } = await import('../../src/http/server.ts');
const { getWebdavConfig, normalizeWebdavUrls } = await import('../../src/db/repo/webdav.ts');

let app: FastifyInstance;
let adminToken = '';
let memberToken = '';

const auth = (token: string) => ({ authorization: `Bearer ${token}` });

before(async () => {
  const db = openDatabase();
  migrate(db);

  createUser(db, {
    username: 'webdav-admin',
    displayName: '管理员',
    password: 'password123',
    role: 'admin',
  });

  createUser(db, {
    username: 'webdav-member',
    displayName: '家庭成员',
    password: 'password123',
    role: 'member',
  });

  app = await buildServer({ logger: false });

  const adminLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    body: { username: 'webdav-admin', password: 'password123' },
  });
  adminToken = (adminLogin.json() as { token: string }).token;

  const memberLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    body: { username: 'webdav-member', password: 'password123' },
  });
  memberToken = (memberLogin.json() as { token: string }).token;
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

describe('WebDAV 远程安全备份 API', () => {
  test('权限检查：未登录 401，普通用户 403', async () => {
    const unauth = await app.inject({
      method: 'GET',
      url: '/api/backup/webdav',
    });
    assert.equal(unauth.statusCode, 401);

    const forbidden = await app.inject({
      method: 'GET',
      url: '/api/backup/webdav',
      headers: auth(memberToken),
    });
    assert.equal(forbidden.statusCode, 403);
  });

  test('URL 规范化工具', () => {
    const r1 = normalizeWebdavUrls('https://dav.example.com/', '/suenmoney/');
    assert.equal(r1.dirUrl, 'https://dav.example.com/suenmoney/');
    assert.equal(r1.baseAuthUrl, 'https://dav.example.com');

    const r2 = normalizeWebdavUrls('https://dav.example.com/dav', 'backup');
    assert.equal(r2.dirUrl, 'https://dav.example.com/dav/backup/');
  });

  test('管理员获取配置（初次为空）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
    });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.config, null);
    assert.ok(body.status);
  });

  test('管理员保存 WebDAV 配置', async () => {
    const saveRes = await app.inject({
      method: 'PUT',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
      payload: {
        url: 'https://dav.jianguoyun.com/dav',
        username: 'test@example.com',
        password: 'mySecretPassword',
        path: '/suenmoney_backup',
        isEnabled: true,
      },
    });

    assert.equal(saveRes.statusCode, 200);
    const body = saveRes.json();
    assert.equal(body.ok, true);
    assert.equal(body.config.password, '******');
    assert.equal(body.config.hasPassword, true);

    // 再次 GET 确认密码被掩码，且存储正确
    const getRes = await app.inject({
      method: 'GET',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
    });
    assert.equal(getRes.statusCode, 200);
    const saved = getRes.json();
    assert.equal(saved.config.url, 'https://dav.jianguoyun.com/dav');
    assert.equal(saved.config.username, 'test@example.com');
    assert.equal(saved.config.password, '******');
    assert.equal(saved.config.hasPassword, true);
    assert.equal(saved.config.path, '/suenmoney_backup');
  });

  test('更新配置时传入 ****** 会保留原密码', async () => {
    const updateRes = await app.inject({
      method: 'PUT',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
      payload: {
        url: 'https://nas.local:5005/dav',
        username: 'nas-user',
        password: '******',
        path: '/suenmoney',
        isEnabled: false,
      },
    });

    assert.equal(updateRes.statusCode, 200);

    const db = getDatabase();
    const config = getWebdavConfig(db);
    assert.ok(config);
    assert.equal(config.url, 'https://nas.local:5005/dav');
    assert.equal(config.username, 'nas-user');
    assert.equal(config.password, 'mySecretPassword'); // 原密码保持完好
    assert.equal(config.isEnabled, false);
  });
});
