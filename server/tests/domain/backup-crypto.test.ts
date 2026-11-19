/**
 * 备份加密格式（.mn）的最小往返测试。
 *
 * 存在的意义：WebDAV 推的是 `packMn(整库 JSON, 口令)`，用户**手头只有口令**。
 * 如果 pack/unpack 不是一对（比如换口令能解开、或错口令也能解开），
 * 备份就等于废纸 —— 而这条链路在 CI 里没有任何别的覆盖点。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

const { packMn, unpackMn, MnFormatError, mnFileName } = await import('../../src/lib/backup-crypto.ts');

describe('备份口令加密（.mn）', () => {
  test('同一个口令能解回原文', () => {
    const json = JSON.stringify({ kind: 'all', expenses: [{ id: '01', amountCents: 100 }] });
    const packed = packMn(json, 'abc123');
    assert.ok(packed.length > 0);
    assert.equal(unpackMn(packed, 'abc123'), json);
  });

  test('错口令解不开（抛 MnFormatError，而不是返回乱码）', () => {
    const packed = packMn('{"a":1}', 'abc123');
    assert.throws(() => unpackMn(packed, 'abc124'), MnFormatError);
  });

  test('空口令拒绝打包（空口令等于不加密）', () => {
    assert.throws(() => packMn('{"a":1}', '   '), MnFormatError);
  });

  test('产物名带 .mn 后缀，可被 WebDAV 轮转规则识别', () => {
    assert.match(mnFileName(), /\.mn$/);
  });
});
