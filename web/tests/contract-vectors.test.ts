/**
 * 三端共用测试向量（计划三 S0-2）。
 *
 * 这份 JSON（`docs/test-vectors/vectors.json`）是 iOS / 鸿蒙 / Web **共同的契约**：
 * 三个端各自写一个 runner，同一份文件必须全过。
 *
 * 这里就是 Web 端的 runner —— 它只做「读 JSON → 调实现 → 断言」，
 * 不在测试里复述任何一条业务规则。规则写在 JSON 的 note 里，
 * 任何一端改实现都必须先让这份文件继续全过。
 *
 * 为什么值得这么做：这些函数错了都不报错，只会显示成另一个数字
 * （金额差一分、月份差一月、紧急度差一档），靠肉眼几乎发现不了。
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';

import { buildDonutArcs } from '../src/utils/donut.ts';
import { daysUntil, shiftMonth } from '../src/utils/dates.ts';
import {
  centsToInput,
  formatCents,
  formatYuan,
  parseYuanToCents,
  splitInstallment,
} from '../src/utils/money.ts';
import { urgencyLabel, urgencyOf } from '../src/utils/urgency.ts';
import { isUlid, ulid } from '../src/utils/ulid.ts';

interface VectorCase {
  fn: string;
  input: unknown[];
  expect: unknown;
  note: string;
}

const FILE = new URL('../../docs/test-vectors/vectors.json', import.meta.url);
const vectors = JSON.parse(readFileSync(FILE, 'utf8')) as Record<string, VectorCase[] | unknown>;

/** 每个 fn 名字映射到实际实现；输入用展开传参，保证「向量即调用」 */
const IMPL: Record<string, (...args: never[]) => unknown> = {
  parseYuanToCents: parseYuanToCents as unknown as (...args: never[]) => unknown,
  formatCents: formatCents as unknown as (...args: never[]) => unknown,
  formatYuan: formatYuan as unknown as (...args: never[]) => unknown,
  centsToInput: centsToInput as unknown as (...args: never[]) => unknown,
  splitInstallment: splitInstallment as unknown as (...args: never[]) => unknown,
  shiftMonth: shiftMonth as unknown as (...args: never[]) => unknown,
  daysUntil: daysUntil as unknown as (...args: never[]) => unknown,
  urgencyOf: urgencyOf as unknown as (...args: never[]) => unknown,
  urgencyLabel: urgencyLabel as unknown as (...args: never[]) => unknown,
  buildDonutArcs: buildDonutArcs as unknown as (...args: never[]) => unknown,
};

for (const suite of ['money', 'dates', 'urgency', 'donut']) {
  const cases = vectors[suite] as VectorCase[];
  describe(`契约向量 · ${suite}`, () => {
    for (const c of cases) {
      test(`${c.fn}(${JSON.stringify(c.input).slice(1, -1)}) — ${c.note}`, () => {
        const impl = IMPL[c.fn];
        assert.ok(impl !== undefined, `向量引用了未注册的函数: ${c.fn}`);
        const actual = impl(...(c.input as never[]));
        assert.deepEqual(actual, c.expect);
      });
    }
  });
}

describe('契约向量 · ulid', () => {
  const spec = (vectors['ulid'] as VectorCase[])[0];
  assert.ok(spec !== undefined, 'vectors.json 缺 ulid 用例');
  test('长度 26 且只含 Crockford 字符集', () => {
    const id = ulid();
    assert.equal(id.length, (spec.expect as { length: number }).length);
    const charset = (spec.expect as { charset: string }).charset;
    for (const ch of id) assert.ok(charset.includes(ch), `非法字符: ${ch}`);
    assert.ok(isUlid(id));
  });

  test('同一毫秒内唯一；跨毫秒按时间序排序', () => {
    const now = 1_767_000_000_000;
    const sameMs = [ulid(now), ulid(now), ulid(now)];
    // 同毫秒内随机后缀，不保证单调，但必须唯一
    assert.equal(new Set(sameMs).size, 3);

    // 跨毫秒时前缀是时间戳，字符串序即时间序
    const a = ulid(now);
    const b = ulid(now + 1000);
    assert.ok(a < b, '后一毫秒的 id 必须排在前面');
  });
});
