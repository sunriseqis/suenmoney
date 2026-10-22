import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

// client.ts 会读写 localStorage 保存服务端配置，Node CLI 下需要 mock
const store: Record<string, string> = {};
globalThis.localStorage = {
  getItem: (key: string) => store[key] ?? null,
  setItem: (key: string, value: string) => {
    store[key] = String(value);
  },
  removeItem: (key: string) => {
    delete store[key];
  },
  clear: () => {
    for (const k of Object.keys(store)) delete store[k];
  },
  key: (index: number) => Object.keys(store)[index] ?? null,
  length: 0,
};

import {
  ApiError,
  probeServerUrl,
  request,
  setActiveServerUrl,
  writeServerUrls,
} from '../src/api/client.ts';

describe('离线闸门：已知离线时请求立即失败（fail-fast）', () => {
  test('网络失败后落闸，后续请求不再发起 fetch；探测成功则清零闸门重新放行', async () => {
    localStorage.clear();
    setActiveServerUrl(null);
    writeServerUrls(['http://192.168.1.100:3310']);

    const originalFetch = globalThis.fetch;
    let networkCalls = 0;
    let serverUp = false;

    globalThis.fetch = (async (input: RequestInfo | URL) => {
      const urlStr = String(input);
      // 探测/健康检查走 fetch 但不计入业务请求次数
      if (urlStr.includes('/api/health')) {
        return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
      }
      networkCalls++;
      if (!serverUp) throw new TypeError('Failed to fetch');
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as typeof fetch;

    try {
      // 第一次：真实打到网络并失败 => 落闸；异常语义保持 ApiError(status=0)
      await assert.rejects(
        () => request('/api/expenses'),
        (err: unknown) => err instanceof ApiError && err.status === 0,
      );
      const callsAfterFailure = networkCalls;
      assert.equal(callsAfterFailure, 1);

      // 第二次：闸门生效，立即失败且不再发起任何网络请求（这是消除卡顿的关键）
      await assert.rejects(
        () => request('/api/expenses'),
        (err: unknown) => err instanceof ApiError && err.status === 0,
      );
      assert.equal(networkCalls, callsAfterFailure);

      // 探测成功 => 清零闸门，业务请求重新放行
      const probe = await probeServerUrl('http://192.168.1.100:3310');
      assert.equal(probe.ok, true);

      serverUp = true;
      const result = await request<{ ok: boolean }>('/api/expenses');
      assert.equal(result.ok, true);
      assert.equal(networkCalls, callsAfterFailure + 1);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
