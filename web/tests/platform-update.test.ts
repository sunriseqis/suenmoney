import assert from 'node:assert/strict';
import { beforeEach, describe, it } from 'node:test';

import {
  downloadAndInstallUpdate,
  getNativeAppVersion,
  getPlatform,
  isAndroid,
  isIos,
  isNativePlatform,
  isNativeUpdateSupported,
} from '../src/platform/index.ts';

describe('Platform Environment Detection (平台环境判断)', () => {
  beforeEach(() => {
    // 重置全局 window 环境
    const g = globalThis as any;
    g.window = {};
  });

  it('无 Capacitor 对象时默认为 web', () => {
    assert.strictEqual(getPlatform(), 'web');
    assert.strictEqual(isIos(), false);
    assert.strictEqual(isAndroid(), false);
    assert.strictEqual(isNativePlatform(), false);
    assert.strictEqual(isNativeUpdateSupported(), false);
  });

  it('Capacitor.getPlatform() 为 ios 时正确识别', () => {
    const g = globalThis as any;
    g.window = {
      Capacitor: {
        isNativePlatform: () => true,
        getPlatform: () => 'ios',
      },
    };
    assert.strictEqual(getPlatform(), 'ios');
    assert.strictEqual(isIos(), true);
    assert.strictEqual(isAndroid(), false);
    assert.strictEqual(isNativePlatform(), true);
    assert.strictEqual(isNativeUpdateSupported(), true);
  });

  it('Capacitor.getPlatform() 为 android 时正确识别', () => {
    const g = globalThis as any;
    g.window = {
      Capacitor: {
        isNativePlatform: () => true,
        getPlatform: () => 'android',
      },
    };
    assert.strictEqual(getPlatform(), 'android');
    assert.strictEqual(isIos(), false);
    assert.strictEqual(isAndroid(), true);
    assert.strictEqual(isNativePlatform(), true);
    assert.strictEqual(isNativeUpdateSupported(), true);
  });
});

describe('Native App Version Detection (原生应用版本读取)', () => {
  beforeEach(() => {
    const g = globalThis as any;
    g.window = {};
  });

  it('iOS 客户端从 Capacitor App 插件正确读取版本 1.5', async () => {
    const g = globalThis as any;
    g.window = {
      Capacitor: {
        isNativePlatform: () => true,
        getPlatform: () => 'ios',
        Plugins: {
          App: {
            getInfo: async () => ({
              name: 'SuenMoney',
              id: 'com.suenmoney.app',
              build: '10023',
              version: '1.5',
            }),
          },
        },
      },
    };

    const ver = await getNativeAppVersion();
    assert.notStrictEqual(ver, null);
    assert.strictEqual(ver?.versionName, '1.5');
    assert.strictEqual(ver?.versionCode, 10023);
  });

  it('纯 Web 平台无法读取原生版本返回 null', async () => {
    const ver = await getNativeAppVersion();
    assert.strictEqual(ver, null);
  });
});

describe('iOS Update Download Action (iOS 原生更新动作)', () => {
  it('iOS 平台调用 downloadAndInstallUpdate 唤起浏览器下载', async () => {
    let openedUrl = '';
    const g = globalThis as any;
    g.window = {
      Capacitor: {
        isNativePlatform: () => true,
        getPlatform: () => 'ios',
      },
      open: (url: string) => {
        openedUrl = url;
      },
    };

    const result = await downloadAndInstallUpdate({
      url: 'https://suenmoney.internal/api/update/download?platform=ios&token=abc',
      fileName: 'SuenMoney-v1.6-release.ipa',
      expectedVersionName: '1.6',
    });

    assert.strictEqual(result.status, 'installer_opened');
    assert.strictEqual(
      openedUrl,
      'https://suenmoney.internal/api/update/download?platform=ios&token=abc',
    );
  });
});
