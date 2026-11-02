import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { signUpdateToken, verifyUpdateToken } from '../../src/lib/update-token.ts';
import { compareVersionName, isOurTag, versionFromTag, versionCodeOf, artifactName } from '../../src/services/update-types.ts';

describe('Update Token (短期下载令牌)', () => {
  it('正确签发并验证令牌', () => {
    const token = signUpdateToken('android', 60_000);
    assert.strictEqual(verifyUpdateToken('android', token), true);
  });

  it('跨平台无法使用同一令牌', () => {
    const token = signUpdateToken('android', 60_000);
    assert.strictEqual(verifyUpdateToken('ios', token), false);
  });

  it('篡改令牌无法通过校验', () => {
    const token = signUpdateToken('android', 60_000);
    const tampered = token.slice(0, -3) + 'abc';
    assert.strictEqual(verifyUpdateToken('android', tampered), false);
  });

  it('过期令牌无法通过校验', () => {
    const expiredToken = signUpdateToken('android', -1000);
    assert.strictEqual(verifyUpdateToken('android', expiredToken), false);
  });

  it('空或非法格式令牌安全返回 false', () => {
    assert.strictEqual(verifyUpdateToken('android', undefined), false);
    assert.strictEqual(verifyUpdateToken('android', ''), false);
    assert.strictEqual(verifyUpdateToken('android', 'not-a-token'), false);
    assert.strictEqual(verifyUpdateToken('android', 'invalid.signature'), false);
  });
});

describe('Version Comparison (版本比较)', () => {
  it('主次版本正确比较', () => {
    assert.strictEqual(compareVersionName('1.0.1', '1.0.0') > 0, true);
    assert.strictEqual(compareVersionName('1.1.0', '1.0.9') > 0, true);
    assert.strictEqual(compareVersionName('2.0.0', '1.9.99') > 0, true);
    assert.strictEqual(compareVersionName('1.0.0', '1.0.0'), 0);
    assert.strictEqual(compareVersionName('1.0.0', '1.0.1') < 0, true);
  });

  it('不同位数的版本正确比较', () => {
    assert.strictEqual(compareVersionName('1.1', '1.0.5') > 0, true);
    assert.strictEqual(compareVersionName('1.0.0.1', '1.0.0') > 0, true);
    assert.strictEqual(compareVersionName('1.0', '1.0.0'), 0);
  });
});

describe('Update API Routes (Fastify 路由级测试)', () => {
  it('非法版本格式请求返回 400', async () => {
    const { buildServer } = await import('../../src/http/server.ts');
    const app = await buildServer({ logger: false });
    await app.ready();

    const res = await app.inject({
      method: 'GET',
      url: '/api/update/check?version_name=invalid_v&version_code=0',
    });
    assert.strictEqual(res.statusCode, 400);
    const body = JSON.parse(res.payload);
    assert.match(body.error, /版本号格式不正确/);
  });

  it('不支持的平台返回 400', async () => {
    const { buildServer } = await import('../../src/http/server.ts');
    const app = await buildServer({ logger: false });
    await app.ready();

    const res = await app.inject({
      method: 'GET',
      url: '/api/update/check?version_name=1.0.0&version_code=1&platform=windows',
    });
    assert.strictEqual(res.statusCode, 400);
    const body = JSON.parse(res.payload);
    assert.match(body.error, /不支持的更新平台/);
  });

  it('未提供凭据或非法 token 下载返回 401', async () => {
    const { buildServer } = await import('../../src/http/server.ts');
    const app = await buildServer({ logger: false });
    await app.ready();

    const res = await app.inject({
      method: 'GET',
      url: '/api/update/download?token=fake-token',
    });
    assert.strictEqual(res.statusCode, 401);
  });

  it('iOS 平台参数正确校验且版本号 1.5 被合法识别', async () => {
    const { buildServer } = await import('../../src/http/server.ts');
    const app = await buildServer({ logger: false });
    await app.ready();

    // 当更新源未配置时返回 503，但表明已经通过了 platform 和 version 的 400 校验
    const res = await app.inject({
      method: 'GET',
      url: '/api/update/check?version_name=1.5&version_code=10023&platform=ios',
    });
    assert.notStrictEqual(res.statusCode, 400);
  });
});


describe('发行仓库是多项目共用，必须按 tag 前缀过滤', () => {
  // sunriseqis/suenapp 同时承载 suenmusic / suenweb / suenmoney。
  // 不过滤会把 suenmusic 的 v2.1.3 当成 suenmoney 的新版本（实测踩到过）。
  it('只认 suenmoney- 前缀的 tag', () => {
    assert.equal(isOurTag('suenmoney-v2.0.0'), true);
    assert.equal(isOurTag('suenmoney-2.0.0'), true);
    assert.equal(isOurTag('v2.1.3'), false, 'suenmusic 的 tag 不能被认成我们的');
    assert.equal(isOurTag('suenweb-v2.0.0'), false, 'suenweb 的 tag 也不能');
  });

  it('版本号能从两种 tag 写法里取出来', () => {
    assert.equal(versionFromTag('suenmoney-v2.0.0'), '2.0.0');
    assert.equal(versionFromTag('suenmoney-2.0.0'), '2.0.0');
  });

  it('三端产物名统一为 suenmoney-<版本>.<ext>', () => {
    assert.equal(artifactName('2.0.0', 'fnos'), 'suenmoney-2.0.0.fpk');
    assert.equal(artifactName('2.0.0', 'ios'), 'suenmoney-2.0.0.ipa');
    assert.equal(artifactName('2.0.0', 'harmony'), 'suenmoney-2.0.0.hap');
  });

  it('versionCode 公式与客户端/CI 同源', () => {
    assert.equal(versionCodeOf('2.0.0'), 2_000_000);
    assert.equal(versionCodeOf('2.1.3'), 2_010_300);
    assert.equal(versionCodeOf('1.0.0'), 1_000_000);
  });
});
