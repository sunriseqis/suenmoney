/**
 * 主题（v3）。
 *
 * 三档：**深色（默认）** / 浅色 / 跟随系统。
 * 默认深色是刻意的 —— v3 是深色设计，跟随系统会让浅色系统用户看到
 * 两套完全不同语言的界面。
 *
 * 为什么不在 store 里：`index.html` 里那段内联脚本要在 **Vue 挂载之前**
 * 读一次 localStorage，否则深色页面会先闪一下浅色。这里只负责
 * 挂载之后的读取与切换，两边共用一个 key。
 */

export type ThemeChoice = 'dark' | 'light' | 'system';

const KEY = 'suenmoney:theme';

/** 挂载前那一段脚本用的字面值，必须与它保持一致。 */
const STORABLE: ReadonlySet<string> = new Set(['dark', 'light']);

export function readStoredTheme(): ThemeChoice | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw !== null && STORABLE.has(raw)) return raw as ThemeChoice;
    if (raw === 'system') return 'system';
  } catch {
    /* 隐私模式：当没有偏好 */
  }
  return null;
}

export function applyTheme(choice: ThemeChoice): void {
  try {
    if (choice === 'system') localStorage.removeItem(KEY);
    else localStorage.setItem(KEY, choice);
  } catch {
    /* 隐私模式：本次会话内仍然生效，只是不持久 */
  }

  const root = document.documentElement;
  if (choice === 'system') {
    delete root.dataset.theme;
    return;
  }
  root.dataset.theme = choice;
}

/** 当前**实际生效**的主题（system 时按 prefers-color-scheme 解析）。 */
export function effectiveTheme(choice: ThemeChoice): 'dark' | 'light' {
  if (choice !== 'system') return choice;
  const dark =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-color-scheme: dark)').matches;
  return dark ? 'dark' : 'light';
}
