import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { isUlid, ulid } from '../src/utils/ulid.ts';

describe('客户端 ULID 生成与校验', () => {
  test('ULID 长度严格为 26 字符且匹配正则', () => {
    const id = ulid();
    assert.equal(id.length, 26);
    assert.equal(isUlid(id), true);
  });

  test('连续生成的 ULID 保持字典序单调递增或等时随机构建', () => {
    const id1 = ulid(1000);
    const id2 = ulid(2000);
    assert.ok(id1 < id2);
  });

  test('非标准字符串被 isUlid 正确拒绝', () => {
    assert.equal(isUlid(''), false);
    assert.equal(isUlid('12345'), false);
    // 包含小写字母或非法字符
    assert.equal(isUlid('01AN4Z07BY79KA1307SR9X4MVi'), false);
  });
});
