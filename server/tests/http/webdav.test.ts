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

/**
 * 备份口令落库（回归）。
 *
 * v2.1.1 之前 `PUT /api/backup/webdav` 压根没读 body 里的 `passphrase`：
 * 前端发了、服务端建 newConfig 时丢了，于是界面「保存成功」之后点备份
 * 永远返回「请先设置备份口令」—— 用户设多少次都没用。
 */
describe('备份口令落库（v2.1.1 回归）', () => {
  const put = (payload: Record<string, unknown>) =>
    app.inject({
      method: 'PUT',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
      payload,
    });

  test('保存时带上 passphrase → 真的落库，GET 只回 hasPassphrase=true（不回明文）', async () => {
    const res = await put({
      url: 'https://dav.example.com/dav',
      username: 'u',
      password: 'pw-123456',
      path: '/b',
      isEnabled: true,
      passphrase: 'abc123',
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().config.hasPassphrase, true);

    const cfg = getWebdavConfig(getDatabase());
    assert.ok(cfg);
    assert.equal(cfg.passphrase, 'abc123', '口令必须落库，否则上传前门禁永远判定未设置');

    const got = await app.inject({
      method: 'GET',
      url: '/api/backup/webdav',
      headers: auth(adminToken),
    });
    assert.equal(got.json().config.hasPassphrase, true);
    // 口令是加密密钥，任何接口都不许回传
    assert.equal(got.json().config.passphrase, undefined);
  });

  test('二次保存不带 passphrase（只改地址/路径）→ 保留原口令', async () => {
    const res = await put({
      url: 'https://nas.local:5005/dav',
      username: 'u',
      password: '******',
      path: '/suenmoney',
      isEnabled: true,
    });
    assert.equal(res.statusCode, 200);

    const cfg = getWebdavConfig(getDatabase());
    assert.ok(cfg);
    assert.equal(cfg.passphrase, 'abc123', '不带口令 = 不改，不能被清空');
    assert.equal(cfg.password, 'pw-123456');
  });

  test('口令少于 6 位 → 400', async () => {
    const res = await put({
      url: 'https://nas.local:5005/dav',
      username: 'u',
      password: '******',
      path: '/suenmoney',
      isEnabled: true,
      passphrase: 'abc12',
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /至少 6 位/);
  });

  test('启用但库里没有口令 → 仍可保存，且 hasPassphrase 如实为 false', async () => {
    const db = getDatabase();
    db.prepare("DELETE FROM settings WHERE key = 'webdav_backup_config'").run();

    const res = await put({
      url: 'https://nas.local/dav',
      username: 'u',
      password: 'pw-123456',
      path: '/suenmoney',
      isEnabled: true,
    });
    // 保存配置与能不能上传是两件事：不在这里拒绝，由 runWebdavBackup 在上传时拦
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().config.hasPassphrase, false);

    const cfg = getWebdavConfig(getDatabase());
    assert.ok(cfg);
    assert.equal(cfg.passphrase, undefined, '没设过就是没设过，不能凭空造一个');
  });
});
