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
const FALLBACK_SYMBOL: Resource = $r('sys.symbol.doc_text');

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
