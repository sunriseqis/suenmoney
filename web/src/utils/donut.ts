/**
 * 环图（donut）的弧段计算。
 *
 * 抽成纯函数是为了**可测**：这是「错了不会报错、只会画歪」的典型 ——
 * 偏移量少累加一段，所有弧就会挤在一起或整体错位，而屏幕上依然是一片彩色，
 * 肉眼很难判断对不对。环图本身是 inline SVG，不引图表库。
 *
 * 几何约定（下面那些数字都由它决定）：
 *   r = 15.9155 → 周长 = 2πr ≈ 100，于是 `stroke-dasharray` 可以直接写百分比；
 *   `stroke-dashoffset` 从 25（四分之一圈）起步，第一段弧从 12 点方向开始画。
 *
 * 百分比保留两位小数：不做这一步的话，`0.39 * 100` 会得到
 * `39.00000000000001`，于是下一段的 offset 变成 `-14.000000000000014` ——
 * 视觉上无所谓，但它会原样写进 SVG 属性、并让这一段的测试无法断言。
 */

export interface DonutSlice {
  id: string;
  /** 0–1，由服务端给出（`ratio`）；前端不做二次聚合，否则两个口径迟早不一致 */
  ratio: number;
  /** 已解析成可用 CSS 颜色（含主题变量）的值 */
  color: string;
}

export interface DonutArc {
  id: string;
  /** 0–100 */
  percent: number;
  /** stroke-dashoffset */
  offset: number;
  color: string;
}

/** 周长正好是 100 的半径 */
export const DONUT_RADIUS = 15.9155;

/** 12 点方向对应的 offset */
const START_OFFSET = 25;

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function buildDonutArcs(slices: readonly DonutSlice[]): DonutArc[] {
  let cumulative = 0;

  return slices.map((slice) => {
    const percent = round2(slice.ratio * 100);
    const arc = {
      id: slice.id,
      percent,
      offset: round2(START_OFFSET - cumulative),
      color: slice.color,
    };

    cumulative += percent;
    return arc;
  });
}
