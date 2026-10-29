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
const CLIENT_BUILD = '2026-10-29.1';

export default class EntryAbility extends UIAbility {
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
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
    // 回到前台补一次同步：离线期间记的账在这里补推（与 Web 的 onAppResume 同义）
    SyncEngine.syncNow();
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}