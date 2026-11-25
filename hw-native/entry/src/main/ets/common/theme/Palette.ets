/**
 * 图表槽位色：把 0..7 的槽位翻译成当前主题的 chart1..8 颜色。
 *
 * 分类色（色号 → 颜色）统一走 `common/ui/CategoryIcon`；这里只保留
 * 「支付 / 记录人等按序号取色」的图表槽位映射，避免与分类色两套算法跑偏。
 */
import { ThemeTokens } from './AppTheme';

const PALETTE_SIZE = 8;

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
