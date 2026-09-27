/**
 * 认证链路的端到端测试。
 *
 * 用 Fastify 的 `app.inject()` 而不是真监听端口 —— 不占端口、不依赖网络、
 * 不会因为本机已有一个开发中的服务占着 3310 而失败。
 *
 * 每个测试文件跑在独立进程里，所以这里用一个临时目录下的一次性 DB，
 * 不会碰你真实的 data/suenmoney.sqlite。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-test-'));
const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;

before(async () => {
  app = await buildServer({ logger: false });
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

const login = (username: string, password: string) =>
  app.inject({ method: 'POST', url: '/api/auth/login', payload: { username, password } });

describe('健康检查与 404', () => {
  test('GET /api/health', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/health' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().ok, true);
  });

  test('未知路径返回结构化 404', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/nope' });
    assert.equal(res.statusCode, 404);
    assert.equal(typeof res.json().error, 'string');
  });
});

describe('首次初始化', () => {
  let token = '';

  test('系统无用户时 /api/auth/setup 可创建管理员并直接发令牌', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/setup',
      payload: { username: 'Suen', displayName: '我', password: 'correct-horse' },
    });

    assert.equal(res.statusCode, 201);
    const body = res.json();
    assert.equal(body.user.role, 'admin');
    assert.equal(body.user.username, 'suen', '用户名应统一转小写存储');
    assert.ok(typeof body.token === 'string' && body.token.length > 20);
    assert.equal(body.user.password_hash, undefined, '响应里绝不能出现口令哈希');

    token = body.token;
  });

  test('已有用户后 /api/auth/setup 永久关闭', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/setup',
      payload: { username: 'intruder', password: 'whatever' },
    });
    assert.equal(res.statusCode, 403);
  });

  test('带令牌可读取自己的信息', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().user.username, 'suen');
  });
});

describe('鉴权', () => {
  test('不带令牌访问受保护接口 → 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/auth/me' });
    assert.equal(res.statusCode, 401);
  });

  test('伪造令牌 → 401', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: 'Bearer not-a-real-token' },
    });
    assert.equal(res.statusCode, 401);
  });

  test('Authorization 头格式不对 → 401', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: 'Token abc' },
    });
    assert.equal(res.statusCode, 401);
  });
});

describe('登录', () => {
  test('大小写不同的用户名也能登录（存的是小写）', async () => {
    const res = await login('SUEN', 'correct-horse');
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().user.displayName, '我');
  });

  test('密码错误 → 401，且提示不区分「用户不存在」与「密码错误」', async () => {
    const wrongPassword = await login('suen', 'wrong-password');
    const noSuchUser = await login('nobody', 'wrong-password');

    assert.equal(wrongPassword.statusCode, 401);
    assert.equal(noSuchUser.statusCode, 401);
    assert.equal(
      wrongPassword.json().error,
      noSuchUser.json().error,
      '两种失败的提示必须一致，否则可被用来枚举用户名',
    );
  });

  test('缺少参数 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { username: 'suen' },
    });
    assert.equal(res.statusCode, 400);
  });

  test('登出后令牌立即失效', async () => {
    const loginRes = await login('suen', 'correct-horse');
    const token = loginRes.json().token as string;

    const before = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(before.statusCode, 200);

    const logout = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(logout.statusCode, 204);

    const after = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(after.statusCode, 401);
  });
});

describe('登录限流', () => {
  test('连续失败超过阈值后返回 429', async () => {
    const attempts: number[] = [];
    for (let index = 0; index < 12; index += 1) {
      const res = await login('ratelimit-victim', 'guess');
      attempts.push(res.statusCode);
    }

    assert.ok(attempts.includes(429), `期望出现 429，实际状态码：${attempts.join(',')}`);
    assert.equal(attempts[0], 401, '第一次失败应是 401 而非直接限流');
  });

  test('限流按用户名隔离，不会误伤其他账号', async () => {
    const res = await login('suen', 'correct-horse');
    assert.equal(res.statusCode, 200, '另一个账号不该被前一个账号的失败次数牵连');
  });
});
