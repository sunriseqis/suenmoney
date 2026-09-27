/**
 * 分类颜色。
 *
 * ## 为什么数据库里存的是「色号」，不是色值
 *
 * `categories.color` 会随同步下发到所有设备。如果存 `#3b82f6` 这种具体色值，
 * 深色主题就没救了 —— 浅色底下刚好够对比的颜色，在深色卡片上往往只有 2:1，
 * 而**同一个分类在两套主题里必须用两套明度**。所以这里存 `1`–`8`（调色板序号），
 * 具体色值由 `tokens.css` 的 `--chart-1..8` 按主题给出。
 *
 * ## 为什么要有「按分类名推导」
 *
 * 默认分类是很久以前种下的，`color` 全是空字符串。让用户一个个去设置里挑颜色
 * 不现实 —— 所以沿用图标那套优先级：
 *
 *     显式设置的色号 > 按分类名稳定推导
 *
 * 名字相同的分类**永远**得到同一个色号（跨设备、跨时间都一致），
 * 于是存量数据不用迁移就有颜色，用户手动选过的永远优先。
 */

/** 调色板大小，与 tokens.css 里的 `--chart-1..8` 一一对应 */
export const CATEGORY_COLOR_COUNT = 8;

export const CATEGORY_COLORS = Array.from(
  { length: CATEGORY_COLOR_COUNT },
  (_, i) => ({ index: i + 1, varName: `--chart-${i + 1}` }),
);

/**
 * 把存储值解析成 1–8。
 *
 * 返回 null 的三种情况：没设过（空字符串）、超出范围、根本不是数字。
 * 第三种很重要 —— 服务端对 color 只做长度校验，任何旧客户端都可能写进来
 * 一个 `#ff0000`；解析失败就当「没设置」处理，回落到按名字推导，
 * **绝不能让一条脏数据把整行图标变成 invalid color**。
 */
export function parseCategoryColor(raw: string | null | undefined): number | null {
  const value = (raw ?? '').trim();
  if (value === '') return null;
  const n = Number(value);
  return Number.isInteger(n) && n >= 1 && n <= CATEGORY_COLOR_COUNT ? n : null;
}

/**
 * 按分类名稳定推导色号。
 *
 * 用乘散列而不是引库，是为了不为了这个功能多拉一个依赖；
 * `>>> 0` 把结果钳回无符号 32 位，避免长名字溢出成负数。
 */
export function deriveCategoryColor(name: string): number {
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  }
  return (hash % CATEGORY_COLOR_COUNT) + 1;
}

/** 显式设置 > 按名字推导 */
export function resolveCategoryColor(name: string, raw?: string | null): number {
  return parseCategoryColor(raw) ?? deriveCategoryColor(name);
}

/** 拿到可直接写进 `style.color` 的值 */
export function categoryColorVar(index: number): string {
  return `var(--chart-${index})`;
}
