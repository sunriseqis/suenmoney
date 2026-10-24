/**
 * 分类图标解析链（R134）。
 *
 * 与 Web `web/src/utils/icons.ts` 同构的**稳定性原则**：数据库里 `categories.icon`
 * 存的是 kebab-case 名字（跨设备同步的是名字，不是组件/下标），解析表留在客户端：
 *
 *   优先级：**显式存储的 icon > 按分类名反查 > 通用兜底**
 *
 * 解析结果给两种渲染：
 * - `categoryIconPath()` → SVG path d，交给 `IconView` 用 `Path` 组件画（与 Web 同一份 Lucide 几何）
 * - `categoryGlyph()`    → 单字标记，仅作 `IconView` 不可用时的兜底 / 无障碍文本
 */

import { ICON_PATHS } from './IconPaths';

/** 兜底图标：解析不到时用它（永不为空，保证徽位不出现空洞） */
const FALLBACK_ICON: string = 'circle-ellipsis';

/** 分类色 16 色槽（与 web `--chart-1..16` 一一对应，v3 账本色，深底对比度 ≥3.69:1） */
export const CATEGORY_COLORS: string[] = [
  '#00ff88', '#ff00ff', '#00d4ff', '#FBBF24',
  '#5FD6A8', '#66C4CC', '#E07060', '#93A5F0',
  '#C8D656', '#5AD4C4', '#E37FB2', '#A8C056',
  '#E0A878', '#9D8FF5', '#74A8D6', '#8C8C8C'
];

/** 把任意色号解析成 1-16；脏数据/未设时返回 null（按名字推导，不要让脏数据毁整行） */
export function parseCategoryColorIndex(raw: string | undefined): number | null {
  const v = (raw ?? '').trim();
  if (v === '') {
    return null;
  }
  const n = Number(v);
  return Number.isInteger(n) && n >= 1 && n <= 16 ? n : null;
}

/** 按名字哈希推导一个 1-16 的色号（未设色时的兜底） */
export function deriveColorIndex(name: string): number {
  let h = 0;
  for (let i = 0; i < name.length; i++) {
    h = (h * 31 + name.charCodeAt(i)) % 1000003;
  }
  return (h % 16) + 1;
}

/** 分类色：显式设置 > 按名字推导 */
export function categoryColorOf(name: string, explicit: string | undefined): string {
  const idx = parseCategoryColorIndex(explicit);
  return idx === null ? CATEGORY_COLORS[deriveColorIndex(name) - 1] : CATEGORY_COLORS[idx - 1];
}

/** kebab 名 → 单字标记（覆盖 Web icons.ts 里最常用的那一批） */
const ICON_GLYPH: Record<string, string> = {
  'utensils': '食',
  'coffee': '饮',
  'shopping-bag': '购',
  'shopping-cart': '购',
  'car': '车',
  'bus': '交',
  'bike': '骑',
  'plane': '飞',
  'home': '居',
  'house': '居',
  'zap': '电',
  'droplet': '水',
  'phone': '通',
  'wifi': '网',
  'heart-pulse': '医',
  'pill': '药',
  'stethoscope': '医',
  'gamepad-2': '娱',
  'clapperboard': '影',
  'film': '影',
  'music': '乐',
  'book-open': '书',
  'graduation-cap': '学',
  'shirt': '衣',
  'gift': '礼',
  'baby': '童',
  'cat': '宠',
  'paw-print': '宠',
  'dumbbell': '健',
  'scissors': '美',
  'cigarette': '烟',
  'beer': '酒',
  'cake-slice': '糕',
  'briefcase': '工',
  'building-2': '办',
  'banknote': '薪',
  'credit-card': '卡',
  'receipt': '账',
  'wrench': '修',
  'sparkles': '洁',
  'armchair': '家',
  'bed': '宿',
  'camera': '摄',
  'church': '信'
};

/** 分类名 → kebab 名（存量数据 icon 为空时按名字反查，不用改数据库） */
const NAME_TO_ICON: Record<string, string> = {
  '餐饮': 'utensils',
  '买菜': 'shopping-cart',
  '外卖': 'utensils',
  '下馆子': 'utensils',
  '交通': 'bus',
  '打车': 'car',
  '加油': 'droplet',
  '购物': 'shopping-bag',
  '衣物': 'shirt',
  '数码': 'phone',
  '居住': 'home',
  '房租': 'home',
  '水电': 'zap',
  '医疗': 'stethoscope',
  '药品': 'pill',
  '娱乐': 'gamepad-2',
  '电影': 'clapperboard',
  '游戏': 'gamepad-2',
  '健身': 'dumbbell',
  '学习': 'book-open',
  '教育': 'graduation-cap',
  '人情': 'gift',
  '宠物': 'paw-print',
  '通讯': 'phone',
  '工资': 'banknote',
  '还款': 'credit-card'
};

/**
 * 解析链（R134）：显式 icon > 按名字反查 > 通用兜底。
 * 返回的 key 只会是登记表里的名字或空串。
 */
export function resolveIconKey(icon: string, name: string): string {
  const explicit = (icon ?? '').trim();
  if (explicit !== '' && ICON_PATHS[explicit] !== undefined) {
    return explicit;
  }
  const byName = NAME_TO_ICON[(name ?? '').trim()];
  if (byName !== undefined) {
    return byName;
  }
  return explicit;
}

/**
 * 名字/显式 icon → Lucide path d（R134 解析链）。
 * 显式 icon 优先（且必须在图标表里），否则按分类名反查，最后落到通用兜底。
 */
export function categoryIconPath(icon: string, name: string): string {
  const key = resolveIconKey(icon, name);
  const hit = ICON_PATHS[key];
  if (hit !== undefined) {
    return hit;
  }
  const fb = ICON_PATHS[FALLBACK_ICON];
  return fb === undefined ? '' : fb;
}

/** 名字 → 单字标记；解析不到时回落到分类名首字（永不为空） */
export function categoryGlyph(icon: string, name: string): string {
  const key = resolveIconKey(icon, name);
  const glyph = ICON_GLYPH[key];
  if (glyph !== undefined) {
    return glyph;
  }
  return name.length > 0 ? name.substring(0, 1) : '·';
}
