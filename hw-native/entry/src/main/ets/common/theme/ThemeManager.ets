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
import { common } from '@kit.AbilityKit';
import { mediaquery } from '@kit.ArkUI';

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

  static get(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const saved = this.store.getSync(KEY_MODE, 'dark') as string;
      this.mode = saved === 'light' ? 'light' : (saved === 'system' ? 'system' : 'dark');
    } catch (e) {
      this.mode = 'dark';
      this.store = null;
    }
    // 订阅系统深浅：跟随系统档要实时响应
    try {
      this.listener = mediaquery.matchMediaSync('(dark-mode: true)');
      this.systemDark = this.listener.matches;
      this.listener.on('change', (result: mediaquery.MediaQueryResult) => {
        this.systemDark = result.matches;
        if (this.mode === 'system') {
          this.broadcast();
        }
      });
    } catch (e) {
      this.systemDark = true;
    }
    this.broadcast();
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
