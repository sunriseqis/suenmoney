/**
 * 把原型 CSS（web/styles/proto/*.css）里的样式值翻译成 ArkUI 可用的参数。
 *
 * 为什么要有这一层：原型里 `--shadow-card: 6px 6px 0 #E9EEF6` 这种 CSS 简写
 * 在 ArkUI 里对应 `.shadow({radius, offsetX, offsetY, color})`，arks 没有等价简写；
 * 每个屏各写一遍就会各处走形。**所有视觉数值都以原型为准**，不自己发明。
 */
import { ThemeTokens } from '../theme/AppTheme';

export interface ParsedShadow {
  radius: number;
  offsetX: number;
  offsetY: number;
  color: string;
}

/**
 * 解析 CSS box-shadow 简写（只支持原型里出现的形式）：
 *   "6px 6px 0 #E9EEF6"      → 硬阴影（radius=0）
 *   "0 0 0 1px rgba(...)"     → 细描边环（用 0 偏移 + 0 模糊近似）
 */
export function parseShadow(css: string): ParsedShadow {
  const parts = css.trim().split(/\s+(?![^(]*\))/);
  const nums: number[] = [];
  let color = '#000000';
  for (const p of parts) {
    if (p.startsWith('#') || p.startsWith('rgb')) {
      color = p;
    } else if (p.endsWith('px')) {
      nums.push(Number(p.replace('px', '')));
    } else if (/^-?\d+(\.\d+)?$/.test(p)) {
      nums.push(Number(p));
    }
  }
  // 原型里没有 inset，顺序固定为 X Y [blur] [spread]
  return {
    offsetX: nums.length > 0 ? nums[0] : 0,
    offsetY: nums.length > 1 ? nums[1] : 0,
    radius: nums.length > 2 ? nums[2] : 0,
    color: color
  };
}

/** 卡片阴影：candy 硬阴影 / cyber 细环（原型 .card 的两种写法） */
export function cardShadow(tokens: ThemeTokens, isCyber: boolean): ParsedShadow {
  return parseShadow(isCyber ? '0px 0px 0px rgba(0, 212, 255, 0.04)' : tokens.shadowCard);
}

/** 按钮阴影：candy 硬阴影 / cyber 无（原型 .btn 在 cyber 下 box-shadow: none） */
export function btnShadow(tokens: ThemeTokens, isCyber: boolean): ParsedShadow {
  return parseShadow(isCyber ? '0px 0px 0px rgba(0,0,0,0)' : tokens.shadowBtn);
}

/** cyber 的切角（原型 clip-path: polygon(0 7px, 7px 0, 100% 0, 100% calc(100%-7px), calc(100%-7px) 100%, 0 100%)） */
export const CYBER_CUT = 7;

/** 圆角：cyber 一律 0（原型用 clip-path 切角），candy 用 token */
export function radiusOf(tokens: ThemeTokens, isCyber: boolean, candyValue: number): number {
  return isCyber ? 0 : candyValue;
}

/** 字体族：标题 / 正文 / 等宽，与 --font-display / --font-body / --font-mono 同义 */
export function fontDisplayOf(isCyber: boolean): string {
  return isCyber ? 'Orbitron' : 'Outfit';
}

export function fontBodyOf(isCyber: boolean): string {
  return isCyber ? 'JetBrains Mono' : 'Plus Jakarta Sans';
}

export function fontMonoOf(): string {
  return 'JetBrains Mono';
}
