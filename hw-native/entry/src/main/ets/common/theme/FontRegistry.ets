/**
 * 自定义字体注册（修 bug 用：之前全部静默失败）。
 *
 * 错误写法：`fontSrc: 'rawfile/fonts/Outfit.ttf'`（字符串）→ 注册不生效、
 * 被 catch 吞掉，于是**所有文字都是系统字体**（用户反馈「字体完全一样」）。
 *
 * 正确写法：`familySrc: $rawfile('fonts/Outfit.ttf')`（Resource），
 * 且要用 UIContext 的 font 接口。注册一次即可，用静态标记防重复。
 */
import { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

let registered = false;

export interface FontSpec {
  family: string;
  file: string;
}

/** 与原型 --font-display / --font-body / --font-mono 对应 */
export const FONT_SPECS: FontSpec[] = [
  { family: 'Outfit', file: 'fonts/Outfit.ttf' },
  { family: 'Orbitron', file: 'fonts/Orbitron-700.ttf' },
  { family: 'Plus Jakarta Sans', file: 'fonts/PlusJakartaSans.ttf' },
  { family: 'JetBrains Mono', file: 'fonts/JetBrainsMono.ttf' }
];

/** 在 @Entry 页面的 aboutToAppear 里调一次 */
export function ensureFonts(ui: UIContext): void {
  if (registered) {
    return;
  }
  registered = true;
  const fontApi = ui.getFont();
  fontApi.registerFont({ familyName: 'Outfit', familySrc: $rawfile('fonts/Outfit.ttf') });
  fontApi.registerFont({ familyName: 'Orbitron', familySrc: $rawfile('fonts/Orbitron-700.ttf') });
  fontApi.registerFont({ familyName: 'Plus Jakarta Sans', familySrc: $rawfile('fonts/PlusJakartaSans.ttf') });
  fontApi.registerFont({ familyName: 'JetBrains Mono', familySrc: $rawfile('fonts/JetBrainsMono.ttf') });
  hilog.info(0x000A, 'Fonts', '四套自定义字体已注册');
}
