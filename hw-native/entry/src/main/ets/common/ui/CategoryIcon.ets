/**
 * 分类图标与分类色（R134）。
 *
 * 图标：鸿蒙系统内置 Symbol（`sys.symbol` 系列 + `SymbolGlyph` 渲染）。
 * 旧的 Lucide SVG 路径方案（IconPaths/IconView + Path 手绘）在真机上描边发糊，已废弃。
 *
 * 解析原则：**按分类名直接命中内置符号 > 通用兜底**。
 * 分类可能是用户在数据库里自建的（名字不在表里），所以必须有兜底符号，不能出现空徽位。
 * 分类色仍走 `categoryColorOf(name, explicit)`（16 色槽，与 Web 对齐）——只换图形，不动颜色逻辑。
 */

/** 兜底符号：名字不在表里时用它（永不为空，保证徽位不出现空洞） */
import { ThemeManager } from '../theme/ThemeManager';

const FALLBACK_SYMBOL: Resource = $r('sys.symbol.doc_text');

/**
 * 深色（cyber）分类色 16 色槽。
 *
 * **前 8 槽严格等于 Web `.app[data-theme="cyber"]` 的 `--chart-1..8`**
 * （#00ff88 / #ff00ff / #00d4ff / #ffb020 / #8b5cff / #00a3ff / #ff3366 / #7dffd0）。
 * 之前 4~8 槽是另一套（#FBBF24/#5FD6A8/#66C4CC/#E07060/#93A5F0），
 * 于是同一个分类在 Web 赛博下和原生端是两种颜色 —— 用户 2026-11-04 反馈「色卡尽量一致」。
 * Web 只定义到 8，后 8 个是原生扩展的补充色（同一荧光家族，保证 16 槽不重复）。
 */
export const CATEGORY_COLORS: string[] = [
  '#00ff88', '#ff00ff', '#00d4ff', '#ffb020',
  '#8b5cff', '#00a3ff', '#ff3366', '#7dffd0',
  '#C8D656', '#5AD4C4', '#E37FB2', '#A8C056',
  '#E0A878', '#9D8FF5', '#74A8D6', '#8C8C8C',
];

/**
 * 浅色（candy）分类色 8 槽。
 *
 * 与 Web `.app`（默认 candy）的 `--chart-1..8` 完全一致。
 *
 * ⚠ 旧实现**不分主题**，candy 下也照用 cyber 那套荧光色 —— 于是同一分类
 * 在 Web 浅色主题和原生端是两个颜色。这是「分类颜色各端不一致」的根因之一。
 */
export const CANDY_CATEGORY_COLORS: string[] = [
  '#8B5CF6', '#F472B6', '#FBBF24', '#34D399',
  '#38BDF8', '#A78BFA', '#FB7185', '#22D3EE'
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

/**
 * 分类色：显式设置 > 按名字推导。
 *
 * **按当前主题取调色板**（candy 用 Web 那套 8 色，cyber 用荧光 16 色）。
 * 主题从 `ThemeManager` 直接读 —— 调用点太多，逐个传参会到处漏。
 */
/** 当前主题的分类调色板（颜色选择器也要用它，否则 candy 下会显示 16 个荧光色） */
export function categoryPalette(): string[] {
  return ThemeManager.get().name === 'candy' ? CANDY_CATEGORY_COLORS : CATEGORY_COLORS;
}

export function categoryColorOf(name: string, explicit: string | undefined): string {
  const palette = ThemeManager.get().name === 'candy' ? CANDY_CATEGORY_COLORS : CATEGORY_COLORS;
  const idx = parseCategoryColorIndex(explicit);
  if (idx === null) {
    return palette[(deriveColorIndex(name) - 1) % palette.length];
  }
  return palette[(idx - 1) % palette.length];
}

/**
 * 分类名 → 内置 Symbol 资源（R134）。
 * 注意：`$r` 引用系统符号的名字必须是字面量（不能拼接变量），所以这里是写死的字面量表。
 */
const CATEGORY_SYMBOLS: Record<string, Resource> = {
  '餐饮': $r('sys.symbol.fork_knife'),
  '外卖': $r('sys.symbol.fork_knife'),
  '下馆子': $r('sys.symbol.fork_knife'),
  '买菜': $r('sys.symbol.cart'),
  '交通': $r('sys.symbol.subway'),
  '打车': $r('sys.symbol.car'),
  '加油': $r('sys.symbol.fuelpump'),
  '购物': $r('sys.symbol.bag'),
  '衣物': $r('sys.symbol.shirt'),
  '数码': $r('sys.symbol.computer'),
  '居住': $r('sys.symbol.house'),
  '房租': $r('sys.symbol.house'),
  '水电': $r('sys.symbol.bolt'),
  '医疗': $r('sys.symbol.hospital'),
  '药品': $r('sys.symbol.drug'),
  '娱乐': $r('sys.symbol.gamecontroller'),
  '游戏': $r('sys.symbol.gamecontroller'),
  '电影': $r('sys.symbol.movie'),
  '健身': $r('sys.symbol.dumbbell'),
  '学习': $r('sys.symbol.book'),
  '教育': $r('sys.symbol.graduationcap'),
  '人情': $r('sys.symbol.gift'),
  '宠物': $r('sys.symbol.pawprint'),
  '通讯': $r('sys.symbol.phone'),
  '工资': $r('sys.symbol.moneybag'),
  '还款': $r('sys.symbol.creditcard')
};

/** 分类名 → 内置 Symbol；自建分类回落到兜底符号（永不为空） */
export function categorySymbolOf(name: string): Resource {
  const hit = CATEGORY_SYMBOLS[(name ?? '').trim()];
  return hit === undefined ? FALLBACK_SYMBOL : hit;
}
