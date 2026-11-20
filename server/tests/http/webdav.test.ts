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

/**
 * 远端错误必须给出可行动提示。
 *
 * 旧实现里所有网络/协议失败都是 `throw new Error(...)`，被 Fastify 兜成
 * `500 服务器内部错误` —— 用户只能看到这句没信息量的话，不知道是地址错、
 * 账号错、还是网盘挂了。这里用本地假 WebDAV 服务端逐条锁住映射关系。
 */
const { createServer } = await import('node:http');
const { testWebdav, runWebdavBackup, saveWebdavConfig, getWebdavStatus } = await import(
  '../../src/db/repo/webdav.ts'
);

describe('WebDAV 远端错误的可行动提示', () => {
  let server: import('node:http').Server;
  let base = '';
  let mode: 'ok' | 'auth' | 'boom' | 'notfound' = 'ok';

  before(async () => {
    server = createServer((req, res) => {
      if (mode === 'auth') {
        res.writeHead(401);
        res.end();
        return;
      }
      if (mode === 'boom') {
        res.writeHead(500);
        res.end('boom');
        return;
      }
      if (mode === 'notfound') {
        // PROPFIND 404 → 走 MKCOL，MKCOL 也 404 → 应报「远端路径不存在」
        res.writeHead(404);
        res.end();
        return;
      }
      if (req.method === 'PROPFIND') {
        res.writeHead(207, { 'Content-Type': 'application/xml' });
        res.end('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"/>');
        return;
      }
      res.writeHead(201);
      res.end();
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const addr = server.address() as import('node:net').AddressInfo;
    base = `http://127.0.0.1:${addr.port}`;
  });

  after(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  const cfg = () => ({
    url: base,
    username: 'u',
    password: 'pw-123456',
    path: '/dav',
    isEnabled: true,
    passphrase: 'abc123',
  });

  test('正常站点：连通性测试通过', async () => {
    mode = 'ok';
    const res = await testWebdav(cfg());
    assert.equal(res.ok, true);
  });

  test('远端 401 → 400，且提示「拒绝认证」（不是 500）', async () => {
    mode = 'auth';
    await assert.rejects(testWebdav(cfg()), (err: { statusCode?: number; message?: string }) => {
      assert.equal(err.statusCode, 400);
      assert.match(err.message ?? '', /拒绝认证|401/);
      return true;
    });
  });

  test('远端 5xx → 502（上游问题，不是用户配错）', async () => {
    mode = 'boom';
    await assert.rejects(testWebdav(cfg()), (err: { statusCode?: number; message?: string }) => {
      assert.equal(err.statusCode, 502);
      assert.match(err.message ?? '', /服务器内部错误|500/);
      return true;
    });
  });

  test('远端 404（含自动建目录也失败）→ 400，提示路径不存在', async () => {
    mode = 'notfound';
    await assert.rejects(testWebdav(cfg()), (err: { statusCode?: number; message?: string }) => {
      assert.equal(err.statusCode, 400);
      assert.match(err.message ?? '', /路径不存在|404/);
      return true;
    });
  });

  test('连不上（端口关闭）→ 502，提示无法连接', async () => {
    mode = 'ok';
    // 拿一个「确实没人监听」的端口：先开再关
    const probe = createServer();
    await new Promise<void>((resolve) => probe.listen(0, '127.0.0.1', resolve));
    const deadPort = (probe.address() as import('node:net').AddressInfo).port;
    await new Promise<void>((resolve) => probe.close(() => resolve()));

    await assert.rejects(
      testWebdav({ ...cfg(), url: `http://127.0.0.1:${deadPort}` }),
      (err: { statusCode?: number; message?: string }) => {
        assert.equal(err.statusCode, 502);
        assert.match(err.message ?? '', /无法连接 WebDAV 服务器/);
        return true;
      },
    );
  });

  test('备份失败会把原因写进「上次备份」状态（定时任务也不至于静默）', async () => {
    mode = 'auth';
    saveWebdavConfig(getDatabase(), cfg());
    await assert.rejects(runWebdavBackup(getDatabase()), (err: { statusCode?: number }) => {
      assert.equal(err.statusCode, 400);
      return true;
    });
    const status = getWebdavStatus(getDatabase());
    assert.equal(status.lastBackupStatus, 'error');
    assert.match(status.lastBackupMessage ?? '', /拒绝认证|401/);
  });
});

/**
 * 备份轮转正则（回归）。
 *
 * v2.1.1 之前的正则是 `\.sqlite$`，而实际产物是 `mnFileName()` 生成的 `.mn` ——
 * 两者永远匹配不上，`backupNames` 恒为空数组，"只保留最近 3 份"从未生效，
 * 远端 `.mn` 备份无限堆积。这里锁死正则必须认 `.mn`（且保留 `.sqlite` 清旧档）。
 */
describe('备份轮转正则（.mn 产物）', () => {
  // 与 webdav.ts 里的过滤正则保持一致 —— 若那边改了这里必须跟着改
  const ROTATION_RE = /^suenmoney-(?:backup|snapshot)-[\w.-]+\.(?:mn|sqlite)$/;

  test('匹配 .mn 产物（mnFileName 生成的格式）', () => {
    assert.match('suenmoney-backup-2026-11-20.mn', ROTATION_RE);
    assert.match('suenmoney-backup-2026-12-01.mn', ROTATION_RE);
    assert.match('suenmoney-snapshot-2026-11-20.mn', ROTATION_RE);
  });

  test('匹配 .sqlite 旧档（清理遗留）', () => {
    assert.match('suenmoney-backup-2026-11-20.sqlite', ROTATION_RE);
    assert.match('suenmoney-snapshot-2026-11-20.sqlite', ROTATION_RE);
  });

  test('不匹配无关文件（避免误删用户其他文件）', () => {
    assert.doesNotMatch('photo.jpg', ROTATION_RE);
    assert.doesNotMatch('suenmoney-backup-2026-11-20.zip', ROTATION_RE);
    assert.doesNotMatch('other-app-backup.mn', ROTATION_RE);
    assert.doesNotMatch('suenmoney-2.1.1.fpk', ROTATION_RE);
    assert.doesNotMatch('suenmoney-2.1.1.hap', ROTATION_RE);
    assert.doesNotMatch('suenmoney-2.1.1.ipa', ROTATION_RE);
  });

  test('mnFileName 产物名被正则认出（真正的契约对齐）', async () => {
    const { mnFileName } = await import('../../src/lib/backup-crypto.ts');
    const name = mnFileName(new Date('2026-11-20'));
    assert.match(name, ROTATION_RE, `mnFileName 产物 ${name} 必须被轮转正则认出`);
    assert.match(name, /\.mn$/, '产物后缀必须是 .mn');
  });
});
