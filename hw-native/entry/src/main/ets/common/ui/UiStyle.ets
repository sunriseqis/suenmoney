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
/**
 * 卡片阴影。
 *
 * **移动端不是桌面那套**：app.css:759 的移动 `.card` 规则（单类、位置更后）
 * 把 `--shadow-card`(6px) 覆盖成 `3px 3px 0 #E9EEF6`，连 `.card--pop` 也一起覆盖。
 */
export function cardShadow(tokens: ThemeTokens, isCyber: boolean, mobile: boolean = true): ParsedShadow {
  if (isCyber) {
    return parseShadow('0px 0px 0px rgba(0, 212, 255, 0.04)');
  }
  return parseShadow(mobile ? '3px 3px 0 #E9EEF6' : tokens.shadowCard);
}

/** 图标描边：cyber 1.6 / candy 2.4（原型 `.ic` 与主题覆盖） */
export function strokeWidthOf(isCyber: boolean): number {
  return isCyber ? 1.6 : 2.4;
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

/**
 * hex 混色（替代 CSS `color-mix()`，ArkUI 没有这个函数）。
 *
 * 用法与原型一致：`mixHex(色, 底, 0.12)` 等价 `color-mix(色 12%, 透明底)`，
 * 用于分类图标底色（12%）与描边（45%）。
 */
export function mixHex(hex: string, base: string, ratio: number): string {
  const a = toRgb(hex);
  const b = toRgb(base);
  const r = Math.round(a[0] * ratio + b[0] * (1 - ratio));
  const g = Math.round(a[1] * ratio + b[1] * (1 - ratio));
  const bl = Math.round(a[2] * ratio + b[2] * (1 - ratio));
  return `#${[r, g, bl].map((v) => v.toString(16).padStart(2, '0')).join('')}`;
}

function toRgb(hex: string): number[] {
  const h = hex.replace('#', '');
  const full = h.length === 3
    ? `${h.charAt(0)}${h.charAt(0)}${h.charAt(1)}${h.charAt(1)}${h.charAt(2)}${h.charAt(2)}`
    : h.substring(0, 6);
  return [
    parseInt(full.substring(0, 2), 16),
    parseInt(full.substring(2, 4), 16),
    parseInt(full.substring(4, 6), 16)
  ];
}

/**
 * cyber 切角四档（原型 clip-path 的四种尺寸，**不是统一的 7px**）：
 * 卡片 14 / 按钮 7 / orb 6 / logo 与主题缩略 8。
 */
export const CUT_CARD = 14;
export const CUT_BTN = 7;
export const CUT_ORB = 6;
export const CUT_LOGO = 8;

/** 生成 cyber 切角路径命令（ArkUI Path 用），等价 clip-path: polygon(0 n, n 0, 100% 0, 100% calc(100%-n), calc(100%-n) 100%, 0 100%) */
export function cutPathCommands(w: number, h: number, n: number): string {
  return `M0 ${n} L${n} 0 L${w} 0 L${w} ${h - n} L${w - n} ${h} L0 ${h} Z`;
}
