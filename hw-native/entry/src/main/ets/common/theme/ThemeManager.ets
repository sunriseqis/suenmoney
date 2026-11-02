/**
 * 主题管理（docs R129–R131，三档）。
 *
 * **三档**：深色（Cyberpunk）/ 浅色（Playful Geometric）/ **跟随系统**。
 * 未显式选择时实时跟随系统（R130）：系统切深色，界面跟着变。
 *
 * 广播机制：`AppStorage[themeName]` 存**生效主题**（'candy' | 'cyber'），
 * 各屏用 `@StorageLink` 订阅 —— 不能存 tokens 快照，否则切主题只有设置页自己变。
 */
import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant, EnvironmentCallback } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Configuration } from '@ohos.app.ability.Configuration';

import { CANDY, CYBER, ThemeTokens } from './AppTheme';

export type ThemeMode = 'dark' | 'light' | 'system';
/** 生效主题（两套设计语言） */
export type ThemeName = 'candy' | 'cyber';

const STORE_NAME = 'suenmoney';
const KEY_MODE = 'suenmoney:theme-mode';
export const THEME_STORAGE_KEY = 'themeName';

export class ThemeManager {
  private static instance: ThemeManager | null = null;
  private store: preferences.Preferences | null = null;
  private mode: ThemeMode = 'dark';
  private systemDark: boolean = true;
  private listener: mediaquery.MediaQueryListener | null = null;
  /**
   * 应用级环境订阅。
   *
   * ⚠ 为什么不用 `Ability.onConfigurationUpdate`：那个回调在应用**后台时经常收不到**，
   *   于是「切系统深浅 → 只有把 app 唤回前台才变色」（suenmusic 2026-10-24 实测，
   *   见其 Theme.ets 注释）。`ApplicationContext.on('environment')` 是应用级订阅，
   *   退到后台也会回调。
   */
  private envCallback: EnvironmentCallback | null = null;

  static get(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const saved = this.store.getSync(KEY_MODE, 'dark') as string;
      this.mode = saved === 'light' ? 'light' : (saved === 'system' ? 'system' : 'dark');
    } catch (e) {
      this.mode = 'dark';
      this.store = null;
    }

    // ① 初值从 context.config.colorMode 取 —— 这是系统真实深浅，比 mediaquery 可靠
    this.readFromConfig(context);

    // ② 变化订阅走应用级 environment（后台也回调）
    this.subscribeEnvironment(context);

    // ③ mediaquery 作为兜底（某些设备/版本上 environment 不触发时还能救一下）
    try {
      this.listener = mediaquery.matchMediaSync('(dark-mode: true)');
      this.systemDark = this.listener.matches;
      this.listener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.applySystemDark(result.matches);
      });
    } catch (e) {
      hilog.warn(0x0000, 'ThemeManager', 'mediaquery 不可用: %{public}s', JSON.stringify(e));
    }

    this.broadcast();
  }

  /** 从 Context 的 config 读系统深浅 */
  private readFromConfig(context: common.UIAbilityContext): void {
    try {
      const cfg: Configuration = context.config;
      const cm: ConfigurationConstant.ColorMode | undefined = cfg.colorMode;
      if (cm !== undefined) {
        this.systemDark = cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
    } catch (e) {
      hilog.warn(0x0000, 'ThemeManager', '读 config.colorMode 失败: %{public}s', JSON.stringify(e));
    }
  }

  /** 订阅应用级环境变化（系统深浅切换时回调） */
  private subscribeEnvironment(context: common.UIAbilityContext): void {
    try {
      const appCtx = context.getApplicationContext();
      this.envCallback = {
        onConfigurationUpdated: (config: Configuration): void => {
          const cm = config.colorMode;
          if (cm !== undefined) {
            this.applySystemDark(cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
          }
        },
        onMemoryLevel: (): void => {
          // 不关心
        }
      } as EnvironmentCallback;
      appCtx.on('environment', this.envCallback);
    } catch (e) {
      hilog.warn(0x0000, 'ThemeManager', '订阅 environment 失败: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 系统深浅变了：只有 **跟随系统** 档才广播，否则用户手选的主题会被系统覆盖。
   * 去重：值没变就不广播，避免无谓重绘。
   */
  private applySystemDark(dark: boolean): void {
    if (this.systemDark === dark) {
      return;
    }
    this.systemDark = dark;
    if (this.mode === 'system') {
      this.broadcast();
    }
  }

  /**
   * EntryAbility.onConfigurationUpdate 也调一次（与 environment 双保险）。
   * 单独 environment 在某些 ROM 上偶发不回调；两条路都通更稳。
   */
  onConfigurationUpdate(config: Configuration): void {
    const cm = config.colorMode;
    if (cm !== undefined) {
      this.applySystemDark(cm === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    }
  }

  /** 进前台时校准一次：后台期间系统可能已经切过，而我们没收到回调 */
  refreshFromContext(context: common.UIAbilityContext): void {
    this.readFromConfig(context);
    if (this.mode === 'system') {
      this.broadcast();
    }
  }

  get themeMode(): ThemeMode {
    return this.mode;
  }

  /** 生效主题名（candy 浅色 / cyber 深色） */
  get name(): ThemeName {
    if (this.mode === 'light') {
      return 'candy';
    }
    if (this.mode === 'dark') {
      return 'cyber';
    }
    return this.systemDark ? 'cyber' : 'candy';
  }

  get tokens(): ThemeTokens {
    return this.name === 'candy' ? CANDY : CYBER;
  }

  /** 切换三档并持久化 */
  async setMode(mode: ThemeMode): Promise<void> {
    this.mode = mode;
    this.broadcast();
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(KEY_MODE, mode);
      await this.store.flush();
    } catch (e) {
      // 持久化失败不影响本次会话
    }
  }

  private broadcast(): void {
    AppStorage.setOrCreate(THEME_STORAGE_KEY, this.name);
  }
}
