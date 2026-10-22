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

/** 调色板大小，与 tokens.css 里的 `--chart-1..16` 一一对应 */
export const CATEGORY_COLOR_COUNT = 16;

export const CATEGORY_COLORS = Array.from(
  { length: CATEGORY_COLOR_COUNT },
  (_, i) => ({ index: i + 1, varName: `--chart-${i + 1}` }),
);

/**
 * 把存储值解析成 1–16。
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
 * 32位 FNV-1a 字符串散列函数。
 * 具备优异的离散性与雪崩效应，消除 UTF-16 汉字编码在小质数乘加下的模数周期冲突。
 */
export function hashCategoryName(name: string): number {
  let hash = 2166136261;
  for (let i = 0; i < name.length; i += 1) {
    hash ^= name.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * 按分类名推导在给定池大小（poolSize）中的索引 (0 .. poolSize - 1)。
 */
export function deriveCategoryIndex(name: string, poolSize: number): number {
  if (poolSize <= 0) return 0;
  return hashCategoryName(name) % poolSize;
}

/**
 * 按分类名推导色号。
 *
 * 优先使用尚未被已有分类使用的颜色（若传入 usedColors）。
 * 当有闲置颜色时，映射到闲置颜色池中；
 * 当 16 色全被占满时，散列回落到全量色池 (1..16)。
 */
export function deriveCategoryColor(name: string, usedColors?: Iterable<number>): number {
  if (usedColors) {
    const usedSet = new Set(usedColors);
    const unused: number[] = [];
    for (let c = 1; c <= CATEGORY_COLOR_COUNT; c += 1) {
      if (!usedSet.has(c)) {
        unused.push(c);
      }
    }
    if (unused.length > 0) {
      const idx = deriveCategoryIndex(name, unused.length);
      return unused[idx] ?? unused[0]!;
    }
  }

  return deriveCategoryIndex(name, CATEGORY_COLOR_COUNT) + 1;
}

/** 显式设置 > 按名字推导（优先未使用色） */
export function resolveCategoryColor(
  name: string,
  raw?: string | null,
  usedColors?: Iterable<number>,
): number {
  return parseCategoryColor(raw) ?? deriveCategoryColor(name, usedColors);
}

/**
 * 稳定且唯一的分类颜色全局分配算法。
 *
 * 核心原则：
 * 1. 显式指定的色号（1..16）绝对优先保留。
 * 2. 未指定颜色（自动）的一级分类，从剩余空闲色池中按顺序稳定取出分配，绝对不产生重复色（在 <=16 个一级分类时保证 0 撞色）。
 * 3. 任何弹窗预览、新增预览和保存后的列表渲染，统一走此函数，保证「预览色 === 保存色」。
 */
export function allocateCategoryColors(
  roots: Array<{ id: string; name: string; color?: string | null }>,
): {
  idMap: Map<string, number>;
  usedColors: Set<number>;
  availablePool: number[];
} {
  const idMap = new Map<string, number>();
  const usedColors = new Set<number>();

  // 第一轮：登记显式设置了有效色号的一级分类
  for (const root of roots) {
    const explicit = parseCategoryColor(root.color);
    if (explicit !== null) {
      idMap.set(root.id, explicit);
      usedColors.add(explicit);
    }
  }

  // 可用的空闲颜色池（1..16 中未被显式占用的）
  const availablePool: number[] = [];
  for (let c = 1; c <= CATEGORY_COLOR_COUNT; c += 1) {
    if (!usedColors.has(c)) {
      availablePool.push(c);
    }
  }

  // 第二轮：为未设置颜色（自动）的一级分类分配空闲色
  for (const root of roots) {
    if (!idMap.has(root.id)) {
      let assigned: number;
      if (availablePool.length > 0) {
        assigned = availablePool.shift()!;
        usedColors.add(assigned);
      } else {
        // 16 色全用尽后的兜底：按名称散列
        assigned = deriveCategoryColor(root.name);
      }
      idMap.set(root.id, assigned);
    }
  }

  return { idMap, usedColors, availablePool };
}

/** 拿到可直接写进 `style.color` 的值 */
export function categoryColorVar(index: number): string {
  return `var(--chart-${index})`;
}

