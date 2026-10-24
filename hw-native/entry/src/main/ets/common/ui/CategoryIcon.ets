/**
 * 分类图标解析链（R134）。
 *
 * 与 Web `web/src/utils/icons.ts` 同构的**稳定性原则**：数据库里 `categories.icon`
 * 存的是 kebab-case 名字（跨设备同步的是名字，不是组件/下标），解析表留在客户端：
 *
 *   优先级：**显式存储的 icon > 按分类名反查 > 通用兜底**
 *
 * 差别：Web 用 Lucide 组件，鸿蒙端目前**没有随包图标资产**，也没有内建图标字体，
 * 因此这里解析成一个**单字标记**（不是 Emoji —— F 系列明令禁止）。
 * 将来接入图标资产时，只需替换 `glyphFor()` 的实现，调用点不用动。
 */

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
  if (explicit !== '' && ICON_GLYPH[explicit] !== undefined) {
    return explicit;
  }
  const byName = NAME_TO_ICON[(name ?? '').trim()];
  if (byName !== undefined) {
    return byName;
  }
  return explicit;
}

/** 名字 → 单字标记；解析不到时回落到分类名首字（永不为空） */
export function categoryGlyph(icon: string, name: string): string {
  const key = resolveIconKey(icon, name);
  const glyph = ICON_GLYPH[key];
  if (glyph !== undefined) {
    return glyph;
  }
  if (glyph !== undefined) {
    return glyph;
  }
  return name.length > 0 ? name.substring(0, 1) : '·';
}
