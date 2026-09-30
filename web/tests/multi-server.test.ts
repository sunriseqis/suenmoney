import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';

// Mock localStorage in Node.js environment
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
  detectAndSwitchServer,
  getActiveServerUrl,
  probeServerUrl,
  readServerUrls,
  setActiveServerUrl,
  writeServerUrls,
} from '../src/api/client.ts';

describe('多服务端配置与按优先级自动切换', () => {
  beforeEach(() => {
    localStorage.clear();
    setActiveServerUrl(null);
  });

  test('默认及持久化读写服务端列表', () => {
    // 默认空状态
    const defaults = readServerUrls();
    assert.ok(defaults.length >= 1);

    // 写入三组地址（带斜杠、空格，应自动清洗）
    writeServerUrls([
      'http://192.168.1.100:3310/ ',
      'http://100.64.0.1:3310///',
      'https://suenmoney.mydomain.com',
    ]);

    const readBack = readServerUrls();
    assert.deepEqual(readBack, [
      'http://192.168.1.100:3310',
      'http://100.64.0.1:3310',
      'https://suenmoney.mydomain.com',
    ]);

    // 默认激活的为第一个
    assert.equal(getActiveServerUrl(), 'http://192.168.1.100:3310');
  });

  test('探测服务器连通性 probeServerUrl', async () => {
    const originalFetch = globalThis.fetch;
    try {
      // 模拟正常响应
      globalThis.fetch = (async (input: RequestInfo | URL) => {
        const urlStr = String(input);
        assert.ok(urlStr.includes('/api/health'));
        return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
      }) as typeof fetch;

      const resOk = await probeServerUrl('http://192.168.1.100:3310');
      assert.equal(resOk.ok, true);
      assert.equal(resOk.status, 200);

      // 模拟网络离线/抛出网络异常
      globalThis.fetch = (async () => {
        throw new TypeError('Failed to fetch');
      }) as typeof fetch;

      const resFail = await probeServerUrl('http://192.168.1.100:3310');
      assert.equal(resFail.ok, false);
      assert.equal(resFail.error, '无法连通');
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('按优先级 1 -> 2 -> 3 探测，优先连通服务端 1（内网）', async () => {
    const originalFetch = globalThis.fetch;
    const probedUrls: string[] = [];

    try {
      globalThis.fetch = (async (input: RequestInfo | URL) => {
        const urlStr = String(input);
        probedUrls.push(urlStr);
        // 服务端 1 直接通
        return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
      }) as typeof fetch;

      const urls = [
        'http://192.168.1.100:3310',
        'http://100.64.0.1:3310',
        'https://suenmoney.mydomain.com',
      ];
      writeServerUrls(urls);

      const switched = await detectAndSwitchServer(urls);
      assert.equal(switched.url, 'http://192.168.1.100:3310');
      assert.equal(getActiveServerUrl(), 'http://192.168.1.100:3310');
      // 应该在服务端 1 连通后立刻停止后续探测，节省资源
      assert.equal(probedUrls.length, 1);
      assert.ok(probedUrls[0]?.includes('192.168.1.100'));
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('服务端 1 不可用时自动降级无缝切换至服务端 2（Tailscale/备用）', async () => {
    const originalFetch = globalThis.fetch;
    const probedUrls: string[] = [];

    try {
      globalThis.fetch = (async (input: RequestInfo | URL) => {
        const urlStr = String(input);
        probedUrls.push(urlStr);
        if (urlStr.includes('192.168.1.100')) {
          throw new TypeError('Connection refused (not at home)');
        }
        // 服务端 2 正常
        if (urlStr.includes('100.64.0.1')) {
          return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
        }
        return new Response(null, { status: 500 });
      }) as typeof fetch;

      const urls = [
        'http://192.168.1.100:3310',
        'http://100.64.0.1:3310',
        'https://suenmoney.mydomain.com',
      ];
      writeServerUrls(urls);

      const switched = await detectAndSwitchServer(urls);
      assert.equal(switched.url, 'http://100.64.0.1:3310');
      assert.equal(getActiveServerUrl(), 'http://100.64.0.1:3310');
      // 依序尝试了 1 和 2，没有多余尝试 3
      assert.equal(probedUrls.length, 2);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('服务端 1 和 2 均不可用时自动切换至服务端 3（公网域名）', async () => {
    const originalFetch = globalThis.fetch;
    const probedUrls: string[] = [];

    try {
      globalThis.fetch = (async (input: RequestInfo | URL) => {
        const urlStr = String(input);
        probedUrls.push(urlStr);
        if (urlStr.includes('192.168.1.100') || urlStr.includes('100.64.0.1')) {
          throw new TypeError('Failed to connect');
        }
        // 服务端 3 正常
        if (urlStr.includes('suenmoney.mydomain.com')) {
          return new Response(JSON.stringify({ status: 'ok' }), { status: 200 });
        }
        return new Response(null, { status: 500 });
      }) as typeof fetch;

      const urls = [
        'http://192.168.1.100:3310',
        'http://100.64.0.1:3310',
        'https://suenmoney.mydomain.com',
      ];
      writeServerUrls(urls);

      const switched = await detectAndSwitchServer(urls);
      assert.equal(switched.url, 'https://suenmoney.mydomain.com');
      assert.equal(getActiveServerUrl(), 'https://suenmoney.mydomain.com');
      assert.equal(probedUrls.length, 3);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  test('所有服务端均离线时正确报告不可用', async () => {
    const originalFetch = globalThis.fetch;
    try {
      globalThis.fetch = (async () => {
        throw new TypeError('Network down');
      }) as typeof fetch;

      const urls = [
        'http://192.168.1.100:3310',
        'http://100.64.0.1:3310',
        'https://suenmoney.mydomain.com',
      ];

      const switched = await detectAndSwitchServer(urls);
      assert.equal(switched.url, null);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
