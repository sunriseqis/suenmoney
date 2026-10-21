/**
 * 「同一个端口既是页面又是接口」这条边界的回归测试。
 *
 * 两条判据必须同时成立，且**不许互相污染**：
 *   1. `/api/*` 未命中 → JSON 404。混成 HTML，前端会把一坨标签当 JSON 解析，
 *      报出来的错是「登录失败，请重试」，与真实原因完全对不上。
 *   2. 其余路径未命中 → HTML（SPA 回退）。用户直接访问 `/ledger` 必须能进。
 *
 * 第三个断言组是「没有产物时退化成纯 API」—— 这条让 10 个现存集成测试
 * 不用为了静态托管改一个字。
 */
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer, resolveWebRoot } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-static-test-'));
const webRoot = join(tempDir, 'dist');

// 一个最小的前端产物目录：入口 HTML + 一个带内容 hash 的资源
mkdirSync(join(webRoot, 'assets'), { recursive: true });
writeFileSync(
  join(webRoot, 'index.html'),
  '<!doctype html><html><body><div id="app">SUENMONEY_SPA_SHELL</div></body></html>',
);
writeFileSync(join(webRoot, 'assets', 'index-a1b2c3.js'), 'console.log("suenmoney");');

const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;

before(async () => {
  app = await buildServer({ logger: false, webRoot });
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

describe('静态托管：页面与接口同源同端口', () => {
  test('/ 返回 SPA 外壳，且禁止缓存', async () => {
    const res = await app.inject({ method: 'GET', url: '/' });
    assert.equal(res.statusCode, 200);
    assert.match(String(res.headers['content-type']), /text\/html/);
    assert.equal(res.headers['cache-control'], 'no-cache');
    assert.match(res.body, /SUENMONEY_SPA_SHELL/);
  });

  test('不存在的静态资源必须真 404，不能回 HTML（旧 bundle 被缓存引用时防语法错误雪崩）', async () => {
    const res = await app.inject({ method: 'GET', url: '/assets/index-GONE.js' });
    assert.equal(res.statusCode, 404);
    assert.match(String(res.headers['content-type']), /application\/json/);
  });

  test('前端路由（/ledger）走 SPA 回退，不是 404', async () => {
    const res = await app.inject({ method: 'GET', url: '/ledger' });
    assert.equal(res.statusCode, 200);
    assert.match(String(res.headers['content-type']), /text\/html/);
    assert.match(res.body, /SUENMONEY_SPA_SHELL/);
  });

  test('/api 下的未命中必须是 JSON 404，不能回 HTML', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/nope' });
    assert.equal(res.statusCode, 404);
    assert.match(String(res.headers['content-type']), /application\/json/);
    assert.equal(typeof res.json().error, 'string');
    assert.doesNotMatch(res.body, /SUENMONEY_SPA_SHELL/);
  });

  test('/assets 下的产物带内容 hash，可以永久缓存', async () => {
    const res = await app.inject({ method: 'GET', url: '/assets/index-a1b2c3.js' });
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['cache-control'], 'public, max-age=2592000, immutable');
    assert.match(res.body, /suenmoney/);
  });

  test('/api/health 带版本号（原生端探活与套件自检要读它）', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/health' });
    assert.equal(res.statusCode, 200);
    const body = res.json();
    assert.equal(body.ok, true);
    assert.equal(body.service, 'suenmoney');
    assert.equal(typeof body.version, 'string');
    assert.notEqual(body.version, '');
  });
});

describe('没有前端产物时退化为纯 API（现存集成测试依赖这条）', () => {
  test('resolveWebRoot 对不存在的目录返回 null', () => {
    assert.equal(resolveWebRoot(join(tempDir, 'no-such-dist')), null);
    assert.equal(resolveWebRoot(webRoot), webRoot);
  });

  test('纯 API 模式下 / 也是 JSON 404，而不是 500 或 HTML', async () => {
    const apiOnly = await buildServer({ logger: false, webRoot: join(tempDir, 'no-such-dist') });
    try {
      const res = await apiOnly.inject({ method: 'GET', url: '/' });
      assert.equal(res.statusCode, 404);
      assert.match(String(res.headers['content-type']), /application\/json/);
    } finally {
      await apiOnly.close();
    }
  });
});
