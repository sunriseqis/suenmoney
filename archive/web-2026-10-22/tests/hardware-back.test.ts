/**
 * 鸿蒙返回键链路的单元测试。
 *
 * 这条链路错起来**不报错、也不打日志**：壳的 onBackPress 把返回键转发给
 * `window.__suenmoneyOnNativeBack && ...`，Web 没注册就短路成undefined，
 * 原生这边照样 return true「已消费」—— 用户按返回键毫无反应，
 * 而控制台干干净净。所以必须在这里钉死三个不变量：
 *
 *  1. 不等壳注入就注册（壳只注入 __suenmoneyExit，从不注入 __suenmoney 桥对象）；
 *  2. 有未保存内容时拦截，且草稿确实落了盘；
 *  3. 没人应答时能真的退出（走壳注入的 __suenmoneyExit）。
 */
import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import { BEFORE_BACK_EVENT, exitNativeApp, setupHardwareBack } from '../src/platform/index.ts';

type TestWindow = Record<string, unknown> & {
  addEventListener?: (type: string, cb: (e: Event) => void) => void;
  removeEventListener?: (type: string, cb: (e: Event) => void) => void;
  dispatchEvent?: (e: Event) => boolean;
  history?: { length: number };
};

/** 最小可用的 window 替身：只实现本模块用到的那几个 API。 */
function makeWindow(): TestWindow {
  const listeners = new Map<string, Array<(e: Event) => void>>();
  const win: TestWindow = {
    history: { length: 1 },
    addEventListener(type: string, cb: (e: Event) => void) {
      const arr = listeners.get(type) ?? [];
      arr.push(cb);
      listeners.set(type, arr);
    },
    removeEventListener(type: string, cb: (e: Event) => void) {
      const arr = listeners.get(type) ?? [];
      const i = arr.indexOf(cb);
      if (i >= 0) arr.splice(i, 1);
    },
    dispatchEvent(e: Event) {
      const arr = listeners.get(e.type) ?? [];
      for (const cb of arr) cb(e);
      return e.defaultPrevented ? false : true;
    },
  };
  return win;
}

describe('鸿蒙返回键（hardware.ts）', () => {
  let savedWindow: unknown;

  beforeEach(() => {
    savedWindow = (globalThis as { window?: unknown }).window;
  });

  it('壳没注入能力桥时也立即注册处理器（不再等5 秒轮询）', () => {
    const g = globalThis as { window?: unknown };
    g.window = makeWindow();
    //关键前提：window.__suenmoney 永远不存在（真机就是这样，壳只注入 __suenmoneyExit）
    assert.strictEqual((g.window as TestWindow).__suenmoney, undefined);

    const cleanup = setupHardwareBack({ onBack: () => false, onExit: () => {} });

    const handler = (g.window as TestWindow).__suenmoneyOnNativeBack;
    assert.strictEqual(
      typeof handler,
      'function',
      '处理器必须在调用后立刻存在，否则壳转发的是 undefined，返回键静默失灵',
    );
    cleanup();
  });

  it('没有能力桥时清理会摘掉处理器，不留残留', () => {
    const g = globalThis as { window?: unknown };
    g.window = makeWindow();
    const cleanup = setupHardwareBack({ onBack: () => false, onExit: () => {} });
    cleanup();
    assert.strictEqual((g.window as TestWindow).__suenmoneyOnNativeBack, undefined);
  });

  it('业务声明有未保存内容时拦截返回键', () => {
    const g = globalThis as { window?: unknown };
    const win = makeWindow();
    g.window = win;

    let exited = false;
    let backCalled = false;
    const cleanup = setupHardwareBack({
      onBack: () => {
        backCalled = true;
        return true;
      },
      onExit: () => {
        exited = true;
      },
    });

    // 模拟「草稿面板声明有未保存内容」
    win.addEventListener!(BEFORE_BACK_EVENT, (e) => e.preventDefault());

    const handler = win.__suenmoneyOnNativeBack as () => boolean;
    assert.strictEqual(handler(), true, '返回 true 表示已拦截，不退出');
    assert.strictEqual(backCalled, false, '拦截后不该再走路由返回');
    assert.strictEqual(exited, false, '拦截后不该退出应用');
    cleanup();
  });

  it('没人应答且onBack 不消费时返回 false，交回壳退出', () => {
    const g = globalThis as { window?: unknown };
    const win = makeWindow();
    g.window = win;

    let exited = false;
    const cleanup = setupHardwareBack({
      onBack: () => false,
      onExit: () => {
        exited = true;
      },
    });

    const handler = win.__suenmoneyOnNativeBack as () => boolean;
    assert.strictEqual(handler(), false);
    assert.strictEqual(exited, true, '必须走到退出，而不是卡在中间态');
    cleanup();
  });

  it('detail.shouldIntercept 与 preventDefault 两条通道都认', () => {
    const g = globalThis as { window?: unknown };
    const win = makeWindow();
    g.window = win;

    const cleanup = setupHardwareBack({ onBack: () => true, onExit: () => {} });
    win.addEventListener!(BEFORE_BACK_EVENT, (e) => {
      (e as CustomEvent<{ shouldIntercept?: boolean }>).detail.shouldIntercept = true;
    });

    const handler = win.__suenmoneyOnNativeBack as () => boolean;
    assert.strictEqual(handler(), true);
    cleanup();
  });

  it('卸载后处理器被摘掉：面板关着时不该再被拦截', () => {
    const g = globalThis as { window?: unknown };
    const win = makeWindow();
    g.window = win;
    const cleanup = setupHardwareBack({ onBack: () => false, onExit: () => {} });
    cleanup();
    assert.strictEqual(win.__suenmoneyOnNativeBack, undefined);
    (globalThis as { window?: unknown }).window = savedWindow;
  });
});

describe('鸿蒙退出（exitNativeApp）', () => {
  let savedWindow: unknown;

  beforeEach(() => {
    savedWindow = (globalThis as { window?: unknown }).window;
  });

  it('壳注入了 __suenmoneyExit 时走它（能力桥不存在时的唯一出路）', async () => {
    const g = globalThis as { window?: unknown };
    let exited = false;
    g.window = {
      __HARMONY_NEXT__: true,
      __suenmoneyExit: () => {
        exited = true;
      },
    };

    await exitNativeApp();
    assert.strictEqual(exited, true, '返回键的「退出应用」必须真的退出，否则按了没反应');
    (globalThis as { window?: unknown }).window = savedWindow;
  });

  it('壳退出函数抛错时静默降级，不把异常抛回调用方', async () => {
    const g = globalThis as { window?: unknown };
    g.window = {
      __HARMONY_NEXT__: true,
      __suenmoneyExit: () => {
        throw new Error('shell boom');
      },
    };

    await exitNativeApp(); // 不应reject
    (globalThis as { window?: unknown }).window = savedWindow;
  });
});