/**
 * 运维数据库快照（SQLite VACUUM INTO）测试。
 */
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import { DatabaseSync } from 'node:sqlite';

import type { FastifyInstance } from 'fastify';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-snapshots-'));
const backupDir = join(tempDir, 'backups');

process.env['SUENMONEY_DB_PATH'] = join(tempDir, 'test.sqlite');
process.env['SUENMONEY_BACKUP_DIR'] = backupDir;
process.env['SUENMONEY_BACKUP_KEEP'] = '3';

const { migrate, openDatabase } = await import('../../src/db/index.ts');
const { createUser } = await import('../../src/db/repo/users.ts');
const { buildServer } = await import('../../src/http/server.ts');
const { pruneOldSnapshots } = await import('../../src/db/repo/snapshots.ts');

let app: FastifyInstance;
let adminToken = '';
let memberToken = '';

const auth = (token: string) => ({ authorization: `Bearer ${token}` });

before(async () => {
  const db = openDatabase();
  migrate(db);

  createUser(db, {
    username: 'admin',
    displayName: '管理员',
    password: 'password123',
    role: 'admin',
  });

  createUser(db, {
    username: 'member',
    displayName: '家庭成员',
    password: 'password123',
    role: 'member',
  });

  app = await buildServer({ logger: false });

  const adminLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    body: { username: 'admin', password: 'password123' },
  });
  adminToken = (adminLogin.json() as { token: string }).token;

  const memberLogin = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    body: { username: 'member', password: 'password123' },
  });
  memberToken = (memberLogin.json() as { token: string }).token;
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

describe('运维快照 API（VACUUM INTO）', () => {
  test('权限拦截：未登录 401，普通成员 403', async () => {
    const unauth = await app.inject({ method: 'GET', url: '/api/snapshots' });
    assert.equal(unauth.statusCode, 401);

    const forbidden = await app.inject({
      method: 'GET',
      url: '/api/snapshots',
      headers: auth(memberToken),
    });
    assert.equal(forbidden.statusCode, 403);

    const postForbidden = await app.inject({
      method: 'POST',
      url: '/api/snapshots',
      headers: auth(memberToken),
    });
    assert.equal(postForbidden.statusCode, 403);
  });

  let createdFilename = '';

  test('管理员 POST /api/snapshots 触发物理快照并生成可用 SQLite 库', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/snapshots',
      headers: auth(adminToken),
    });

    assert.equal(res.statusCode, 200);
    const body = res.json() as { snapshot: { filename: string; sizeBytes: number; createdAt: string } };
    assert.ok(body.snapshot.filename.startsWith('suenmoney-snapshot-'));
    assert.ok(body.snapshot.sizeBytes > 0);
    createdFilename = body.snapshot.filename;

    const snapshotFilePath = join(backupDir, 'snapshots', createdFilename);
    assert.ok(existsSync(snapshotFilePath));

    // 验证生成的快照是完整可读取的 SQLite 数据库
    const snapDb = new DatabaseSync(snapshotFilePath);
    const row = snapDb.prepare('SELECT COUNT(*) AS n FROM users').get() as { n: number };
    assert.equal(row.n, 2);
    snapDb.close();
  });

  test('管理员 GET /api/snapshots 列出快照', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/snapshots',
      headers: auth(adminToken),
    });

    assert.equal(res.statusCode, 200);
    const body = res.json() as { snapshots: Array<{ filename: string; sizeBytes: number }> };
    assert.ok(body.snapshots.length >= 1);
    assert.ok(body.snapshots.some((s) => s.filename === createdFilename));
  });

  test('管理员 GET /api/snapshots/:filename 下载快照', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/snapshots/${createdFilename}`,
      headers: auth(adminToken),
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['content-type'], 'application/x-sqlite3');
    assert.ok(res.headers['content-disposition']?.includes(createdFilename));
    assert.ok(res.rawPayload.length > 0);
  });

  test('路径穿越防线与不存在文件：404', async () => {
    const traversal = await app.inject({
      method: 'GET',
      url: '/api/snapshots/..%2F..%2Fetc%2Fpasswd',
      headers: auth(adminToken),
    });
    assert.equal(traversal.statusCode, 404);

    const notExist = await app.inject({
      method: 'GET',
      url: '/api/snapshots/suenmoney-snapshot-99999999-999999.sqlite',
      headers: auth(adminToken),
    });
    assert.equal(notExist.statusCode, 404);
  });

  test('管理员 DELETE /api/snapshots/:filename 删除快照', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/snapshots/${createdFilename}`,
      headers: auth(adminToken),
    });

    assert.equal(res.statusCode, 200);
    assert.equal(existsSync(join(backupDir, 'snapshots', createdFilename)), false);

    // 再次删除返回 404
    const res2 = await app.inject({
      method: 'DELETE',
      url: `/api/snapshots/${createdFilename}`,
      headers: auth(adminToken),
    });
    assert.equal(res2.statusCode, 404);
  });

  test('超出配额时自动清理最旧的快照', async () => {
    // 连续触发 4 次快照，配额是 3
    for (let i = 0; i < 4; i += 1) {
      await app.inject({
        method: 'POST',
        url: '/api/snapshots',
        headers: auth(adminToken),
      });
    }

    const listRes = await app.inject({
      method: 'GET',
      url: '/api/snapshots',
      headers: auth(adminToken),
    });
    const body = listRes.json() as { snapshots: Array<{ filename: string }> };
    // 配额是 3，保留最多 3 份
    assert.ok(body.snapshots.length <= 3);
  });
});
