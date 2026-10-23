/**
 * 分类配色：把「色号」翻译成当前主题的 chart 颜色。
 *
 * 三端口径一致：**存色号不存色值**。换主题时账本色整体重排，
 * 存死色值会让同一分类在深浅主题下颜色对不上。
 * 没设过色号时按分类 id 哈希取一个稳定值（同一分类永远同一个颜色）。
 */
import { ThemeTokens } from './AppTheme';

const PALETTE_SIZE = 8;

/** 色号（'1'..'16' 或 ''）→ 0..7 的槽位 */
export function slotOf(colorField: string, categoryId: string): number {
  const n = Number(colorField);
  if (Number.isFinite(n) && n >= 1) {
    return (Math.floor(n) - 1) % PALETTE_SIZE;
  }
  return hashIndex(categoryId);
}

export function chartColor(tokens: ThemeTokens, slot: number): string {
  const s = slot % PALETTE_SIZE;
  if (s === 0) return tokens.chart1;
  if (s === 1) return tokens.chart2;
  if (s === 2) return tokens.chart3;
  if (s === 3) return tokens.chart4;
  if (s === 4) return tokens.chart5;
  if (s === 5) return tokens.chart6;
  if (s === 6) return tokens.chart7;
  return tokens.chart8;
}

/** 稳定哈希：同一 id 在任何设备上取到同一槽位 */
export function hashIndex(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) {
    h = (h * 31 + id.charCodeAt(i)) % 100000;
  }
  return h % PALETTE_SIZE;
}
