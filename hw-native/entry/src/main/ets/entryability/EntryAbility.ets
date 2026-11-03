/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { Configuration } from '@ohos.app.ability.Configuration';
import { Db } from '../common/store/Db';
import { ServerConfig } from '../common/net/ServerConfig';
import { ThemeManager } from '../common/theme/ThemeManager';
import { Fonts } from '../common/theme/Fonts';
import { AuthStore } from '../common/auth/AuthStore';
import { LastPick } from '../common/store/LastPick';
import { SyncEngine } from '../common/sync/SyncEngine';
import { NetworkMonitor } from '../common/sync/NetworkMonitor';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

/**
 * 客户端构建标记：每次出包改一次。
 * 用途：装机后 `hdc shell hilog -x | grep SuenMoneyBuild` 就能确认「设备上跑的到底是哪一版」，
 * 不用再去比对 hap 哈希（设备上 /data/app 下的 hap 没权限读）。
 */
const CLIENT_BUILD = '2026-10-29.2';

/**
 * 冷启动的异步初始化。
 *
 * ⚠️ **`onWindowStageCreate` 必须等它完成**，否则会出现「令牌明明存在却进登录页」。
 *
 * 病根：ArkTS 的 `onCreate` 即使声明成 `async`，框架也**不会 await 返回的 Promise** ——
 * 它只把回调当同步函数调用一次就继续走 `onWindowStageCreate`。
 * 于是 `loadContent(AuthStore.isAuthenticated ? ...)` 可能在 `ServerConfig.init()`
 * 读完令牌之前就求值：此时 `authToken === ''` → 判定未登录 → 进登录页。
 * 这是个**竞态**（取决于 prefs 读盘快慢），表现为「偶尔掉登录」。
 *
 * 所以这里把初始化收进一个 Promise，`onWindowStageCreate` 显式 await 它。
 */
let initPromise: Promise<void> = Promise.resolve();

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 同步把初始化挂起成 Promise（不能 await —— 那等于回到原来的竞态）
    initPromise = this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    hilog.info(DOMAIN, 'SuenMoneyBuild', 'client build %{public}s', CLIENT_BUILD);
    // 底座三件套：主题、服务端与令牌、本地库。
    // 顺序无关，但都必须在这里完成 —— 页面 aboutToAppear 时就要能拿到。
    await Fonts.register(this.context);
    await ThemeManager.get().init(this.context);
    await ServerConfig.get().init(this.context);
    await LastPick.init(this.context);
    NetworkMonitor.start();
    try {
      await Db.open(this.context);
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'DB open failed: %{public}s', JSON.stringify(e));
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    NetworkMonitor.stop();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    /**
     * 等初始化完成再决定进哪个页面。
     *
     * 不等的话就是竞态：`AuthStore.isAuthenticated` 读的是 `ServerConfig.authToken`，
     * 而它要等 `ServerConfig.init()` 从 preferences 读出来 —— 谁先跑不确定。
     * 令牌在、却进登录页，就是这么来的（实测可复现）。
     */
    void initPromise.then(() => {
      this.loadRoot(windowStage);
    }).catch((e: Object) => {
      hilog.error(DOMAIN, 'testTag', '初始化失败，仍尝试进入: %{public}s', JSON.stringify(e));
      this.loadRoot(windowStage);
    });
  }

  private loadRoot(windowStage: window.WindowStage): void {
    // 冷启动：先让界面用本地数据渲染出来，再拉一次更新（不阻塞首屏）
    setTimeout(() => {
      void SyncEngine.syncNow().catch(() => {
      });
    }, 0);
    windowStage.loadContent(AuthStore.isAuthenticated ? 'pages/MainPage' : 'pages/LoginPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    /*
     * 热启动（后台回前台）：**先推后拉**。
     *
     * 推 = 离线期间记的账补传；拉 = 别的设备/服务端的变更同步下来。
     * 冷启动在 `loadRoot` 里也做同样一次，两者合起来覆盖
     * 「无进程启动 / 挂起后唤醒 / 后台回前台」三种情况。
     */
    void SyncEngine.syncNow().catch(() => {
    });
    // 校准系统深浅：后台期间系统可能已经切过，而 environment 回调未必送达
    ThemeManager.get().refreshFromContext(this.context);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * 系统配置变化（深浅切换、字体缩放、语言…）。
   *
   * 这里只处理深浅，且只是**双保险** —— 主路径是 ThemeManager 里订阅的
   * `ApplicationContext.on('environment')`（本回调在后台时经常收不到）。
   */
  onConfigurationUpdate(config: Configuration): void {
    ThemeManager.get().onConfigurationUpdate(config);
  }
}