/**
 * 主题管理器（candy / cyber 两套设计语言）。
 *
 * 与 Web 保持一致：
 *   - **默认深色（cyber）** —— 不跟随系统。跟随系统会让浅色系统用户看到两套
 *     完全不同的语言，而默认态必须是设计者指定的那个。
 *   - 选择持久化在 preferences 里（key 与 Web 的 localStorage 键名同源，便于将来互通）。
 *
 * ArkTS 约束：类字段必须显式类型；不用动态 key 访问对象。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

import { CANDY, CYBER, ThemeTokens } from './AppTheme';

export type ThemeName = 'candy' | 'cyber';

const STORE_NAME = 'suenmoney';
const KEY_THEME = 'suenmoney:theme';

export class ThemeManager {
  private static instance: ThemeManager | null = null;
  private store: preferences.Preferences | null = null;
  private current: ThemeName = 'cyber';

  static get(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /** 在 Ability.onCreate 里调一次；读不到就用默认深色 */
  async init(context: common.Context): Promise<void> {
    try {
      this.store = await preferences.getPreferences(context, STORE_NAME);
      const saved = this.store.getSync(KEY_THEME, 'cyber') as string;
      this.current = saved === 'candy' ? 'candy' : 'cyber';
    } catch (e) {
      this.current = 'cyber';
    }
  }

  get name(): ThemeName {
    return this.current;
  }

  /** 当前主题的令牌对象 */
  get tokens(): ThemeTokens {
    return this.current === 'candy' ? CANDY : CYBER;
  }

  /** 切换并持久化 */
  async set(name: ThemeName): Promise<void> {
    this.current = name;
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(KEY_THEME, name);
      await this.store.flush();
    } catch (e) {
      // 持久化失败不影响本次会话内的切换（与 Web 隐私模式同策略）
    }
  }
}
