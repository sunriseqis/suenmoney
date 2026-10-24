/**
 * 字体注册（H0-6）。
 *
 * 原型用四套字体表达两种设计语言：
 *   candy：标题 Outfit / 正文 Plus Jakarta Sans
 *   cyber：标题 Orbitron / 正文 JetBrains Mono
 * 中文统一回落 MiSans（与 Web 一致）。
 *
 * 资产：`resources/rawfile/fonts/*.ttf`。这些 TTF 是从 @fontsource 的 woff2
 * **离线转换**来的（wawoff2），因为原生端只认 ttf/otf。字体本身是 OFL，
 * 与 Web 用的是同一份字形 —— 两端排版才能对齐。
 *
 * 注册在 Ability 启动时调一次；失败只记日志不阻塞启动（字体退化不等于不能用）。
 */
import { font } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'Fonts';

/** 逻辑族名 → rawfile 路径。ArkTS 侧用逻辑名，将来换字体只改这张表 */
export const FONT_FILES: Record<string, string> = {
  'Outfit': 'fonts/Outfit.ttf',
  'Orbitron': 'fonts/Orbitron-700.ttf',
  'PlayJakarta': 'fonts/PlusJakartaSans.ttf',
  'JetBrains': 'fonts/JetBrainsMono.ttf',
  // 别名：UiStyle 里的 fontMonoOf()/fontBodyOf() 用的是 CSS 原名（带空格），
  // 两边必须能对上，否则会静默回落系统字体（曾经就是这样，mono 一直没生效）
  'JetBrains Mono': 'fonts/JetBrainsMono.ttf',
  'Plus Jakarta Sans': 'fonts/PlusJakartaSans.ttf'
};

export class Fonts {
  static async register(context: common.Context): Promise<void> {
    const names = Object.keys(FONT_FILES);
    for (const name of names) {
      try {
        await font.registerFont({
          familyName: name,
          familySrc: `rawfile/${FONT_FILES[name]}`
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'font %{public}s 注册失败（将回落系统字体）', name);
      }
    }
  }
}

/** 按主题给出「标题 / 正文」字体族（与 Web 的 --font-display / --font-body 同义） */
export function displayFont(themeIsCandy: boolean): string {
  return themeIsCandy ? 'Outfit' : 'Orbitron';
}

export function bodyFont(themeIsCandy: boolean): string {
  return themeIsCandy ? 'PlayJakarta' : 'JetBrains';
}
