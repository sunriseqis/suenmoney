/**
 * 发行页 SECTION 合并的回归测试。
 *
 * 为什么值得单独测：这段逻辑决定「四个平台各自的 workflow 会不会互相覆盖发行页」。
 * 2026-10-31 就因为 tag 前缀用错，把 suenmusic 的同名发行页改成了「SuenMoney」，
 * 还混进了 suenmoney 的附件 —— 事后手工恢复。这类错误**不会报错**，
 * 只会安静地把别人的发行页改坏，所以必须有断言兜着。
 *
 * 纯函数、零网络：`mergeBody(existingBody, platform, tag)`。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

const { mergeBody } = await import('./prepare-release-notes.mjs');

const TAG = 'suenmoney-v2.1.1';

const section = (id, title, line) =>
  `<!-- SECTION:${id} -->\n### SuenMoney v2.1.1 ${title}\n- ${line}\n<!-- /SECTION:${id} -->`;

const fnos = () => section('FNOS', '飞牛私有云（fnOS）原生套件', 'fpk');
const ios = () => section('IOS', 'iOS 原生客户端', 'ipa');
const harmony = () => section('HARMONY', '鸿蒙 NEXT 原生客户端', 'hap');

const countOf = (body, id) => (body.match(new RegExp(`<!-- SECTION:${id} -->`, 'g')) ?? []).length;

describe('发行页 SECTION 合并', () => {
  test('已有三节时加 DOCKER：四节共存，且原有三节内容不动', () => {
    const existing = [fnos(), ios(), harmony()].join('\n\n');
    const merged = mergeBody(existing, 'docker', TAG);

    for (const id of ['FNOS', 'IOS', 'HARMONY', 'DOCKER']) {
      assert.equal(countOf(merged, id), 1, `${id} 应恰好一节`);
    }
    assert.ok(merged.includes(fnos()), 'FNOS 内容必须原样保留');
    assert.ok(merged.includes(ios()), 'IOS 内容必须原样保留');
    assert.ok(merged.includes(harmony()), 'HARMONY 内容必须原样保留');
    assert.match(merged, /ghcr\.io\/sunriseqis\/suenmoney/);
  });

  test('重复触发幂等：同一平台再合并一次不会堆叠', () => {
    const existing = [fnos(), ios(), harmony()].join('\n\n');
    const once = mergeBody(existing, 'docker', TAG);
    const twice = mergeBody(once, 'docker', TAG);
    assert.equal(countOf(twice, 'DOCKER'), 1);
    assert.equal(twice, once);
  });

  test('顺序无关：镜像先发（只有 DOCKER）之后三端仍能各自追加', () => {
    let body = mergeBody('', 'docker', TAG);
    body = mergeBody(body, 'fnos', TAG);
    body = mergeBody(body, 'ios', TAG);
    body = mergeBody(body, 'harmony', TAG);
    for (const id of ['FNOS', 'IOS', 'HARMONY', 'DOCKER']) {
      assert.equal(countOf(body, id), 1);
    }
  });

  test('DOCKER 节里的版本号来自 tag，且拉取命令不带 v 前缀', () => {
    const merged = mergeBody('', 'docker', TAG);
    assert.match(merged, /### SuenMoney v2\.1\.1 Docker 镜像/);
    assert.match(merged, /suenmoney:2\.1\.1`/);
    assert.ok(!merged.includes('suenmoney:v2.1.1'), 'docker tag 不能带 v 前缀');
  });

  test('不认识的平台名直接抛错（避免静默写成空节）', () => {
    assert.throws(() => mergeBody('', 'android', TAG), /Unsupported platform/);
  });
});
