/**
 * 分类图标登记表。
 *
 * ## 为什么数据库里存的是「名字」，不是组件或索引
 *
 * `categories.icon` 会随同步下发到所有设备。如果存的是组件名或数组下标，
 * 那么任何一个客户端换了图标库版本、或者调整了登记表顺序，都会让**别的设备**
 * 解析不出图标。存一个稳定的字符串（kebab-case 名字），解析表留在前端：
 * 遇到不认识的名字就回落到通用图标 —— **永远不会崩，最差只是不够好看**。
 *
 * ## 为什么还要一张「按分类名反查」的表
 *
 * 默认分类是在很久以前种下的，那 34 条记录的 `icon` 全是空字符串。
 * 补一次数据迁移当然可以，但只要前端还认得这些名字，存量数据不用动就能立刻有图标，
 * 而且用户在别处新建的「早餐」「宠物」这类常见名也能自动命中。
 *
 * 优先级：**显式存储的 icon > 按名字反查 > 通用图标**。
 * 用户手动选过的图标永远优先，不会被名字反查覆盖。
 */
import {
  Armchair,
  Baby,
  Banknote,
  Bed,
  Beer,
  Bike,
  BookOpen,
  Briefcase,
  Building2,
  Bus,
  CakeSlice,
  Camera,
  Car,
  CarFront,
  CreditCard,
  Cat,
  Church,
  Cigarette,
  Clapperboard,
  Coffee,
  Dog,
  Dumbbell,
  Film,
  Flame,
  Flower2,
  Footprints,
  Fuel,
  Gamepad2,
  Gift,
  GraduationCap,
  HandCoins,
  HeartPulse,
  House,
  HousePlug,
  IceCreamCone,
  Lamp,
  Landmark,
  Laptop,
  Mic,
  MonitorSmartphone,
  Music,
  Newspaper,
  Package,
  Palette,
  PartyPopper,
  Phone,
  Pill,
  Plane,
  Plug,
  Printer,
  Sandwich,
  Scissors,
  Shirt,
  ShoppingBasket,
  ShoppingCart,
  ShowerHead,
  Smartphone,
  Sofa,
  Soup,
  Sparkles,
  SquareParking,
  Stethoscope,
  Store,
  Syringe,
  Tag,
  Theater,
  Ticket,
  TrainFront,
  Trash2,
  TreePine,
  Truck,
  Utensils,
  UtensilsCrossed,
  Video,
  Wallet,
  Wifi,
  Wine,
  Wrench,
  Zap,
  CircleEllipsis,
} from '@lucide/vue';
import type { Component } from 'vue';

/**
 * 名字 → 组件。名字是**持久化格式**，改名等于让已有数据的图标全部失效，
 * 所以增删要谨慎；只增不改是安全的。
 */
export const ICON_REGISTRY = {
  // 餐饮
  utensils: Utensils,
  'utensils-crossed': UtensilsCrossed,
  coffee: Coffee,
  'cake-slice': CakeSlice,
  sandwich: Sandwich,
  soup: Soup,
  'ice-cream': IceCreamCone,
  wine: Wine,
  beer: Beer,

  // 交通
  bus: Bus,
  car: Car,
  'car-front': CarFront,
  fuel: Fuel,
  parking: SquareParking,
  bike: Bike,
  train: TrainFront,
  plane: Plane,
  truck: Truck,

  // 居住
  house: House,
  'house-plug': HousePlug,
  building: Building2,
  landmark: Landmark,
  plug: Plug,
  zap: Zap,
  flame: Flame,
  wifi: Wifi,
  lamp: Lamp,
  bed: Bed,
  sofa: Sofa,
  armchair: Armchair,
  'shower-head': ShowerHead,
  wrench: Wrench,

  // 购物 / 穿着
  'shopping-cart': ShoppingCart,
  'shopping-basket': ShoppingBasket,
  shirt: Shirt,
  footprints: Footprints,
  scissors: Scissors,
  package: Package,
  store: Store,

  // 通讯 / 数码
  smartphone: Smartphone,
  phone: Phone,
  laptop: Laptop,
  'monitor-smartphone': MonitorSmartphone,
  printer: Printer,
  newspaper: Newspaper,

  // 医疗
  stethoscope: Stethoscope,
  pill: Pill,
  syringe: Syringe,
  'heart-pulse': HeartPulse,

  // 娱乐
  sparkles: Sparkles,
  film: Film,
  clapperboard: Clapperboard,
  'gamepad-2': Gamepad2,
  music: Music,
  mic: Mic,
  theater: Theater,
  ticket: Ticket,
  'party-popper': PartyPopper,
  palette: Palette,
  camera: Camera,
  video: Video,

  // 人情 / 金融
  gift: Gift,
  'hand-coins': HandCoins,
  wallet: Wallet,
  banknote: Banknote,
  'credit-card': CreditCard,

  // 其他
  tag: Tag,
  'circle-ellipsis': CircleEllipsis,
  briefcase: Briefcase,
  'graduation-cap': GraduationCap,
  'book-open': BookOpen,
  baby: Baby,
  cat: Cat,
  dog: Dog,
  dumbbell: Dumbbell,
  cigarette: Cigarette,
  'tree-pine': TreePine,
  flower: Flower2,
  church: Church,
  'trash-2': Trash2,
} as const;

export type IconName = keyof typeof ICON_REGISTRY;

/** 用户没选过图标时的兜底 —— 一个中性的标签形状，任何分类名都不违和。 */
const FALLBACK_ICON: Component = Tag;

/**
 * 默认分类名 → 图标名。
 *
 * 覆盖 db-init 种下的那 34 个默认分类，外加几个家庭记账里高频的自建名。
 * 查不到就走 FALLBACK_ICON。
 */
const ICON_BY_CATEGORY_NAME: Record<string, IconName> = {
  餐饮: 'utensils',
  外卖: 'utensils-crossed',
  买菜: 'shopping-basket',
  下馆子: 'soup',
  零食饮料: 'ice-cream',
  早餐: 'coffee',
  咖啡: 'coffee',
  奶茶: 'beer',

  交通: 'bus',
  公交地铁: 'bus',
  地铁: 'train',
  打车: 'car-front',
  加油: 'fuel',
  停车: 'parking',
  骑车: 'bike',
  火车: 'train',
  机票: 'plane',
  货运: 'truck',

  居住: 'house',
  房贷: 'landmark',
  房租: 'house',
  物业: 'building',
  水电燃气: 'zap',
  水电: 'zap',
  燃气: 'flame',
  宽带: 'wifi',
  家电: 'lamp',
  家具: 'sofa',
  装修: 'wrench',

  日用: 'package',
  超市: 'shopping-cart',
  洗护: 'shower-head',
  家居: 'armchair',
  母婴: 'baby',

  购物: 'shopping-cart',
  服饰: 'shirt',
  鞋: 'footprints',
  美妆: 'sparkles',
  理发: 'scissors',
  快递: 'package',

  通讯: 'smartphone',
  话费: 'smartphone',
  流量: 'wifi',
  数码: 'monitor-smartphone',
  电脑: 'laptop',
  打印: 'printer',
  订阅: 'newspaper',

  医疗: 'stethoscope',
  门诊: 'stethoscope',
  药品: 'pill',
  住院: 'syringe',
  体检: 'heart-pulse',

  娱乐: 'gamepad-2',
  会员订阅: 'ticket',
  电影: 'clapperboard',
  游戏: 'gamepad-2',
  音乐: 'music',
  演出: 'theater',
  旅游: 'plane',
  运动: 'dumbbell',
  健身: 'dumbbell',
  摄影: 'camera',

  人情: 'gift',
  礼物: 'gift',
  红包: 'hand-coins',
  请客: 'utensils',

  学习: 'graduation-cap',
  书籍: 'book-open',
  教育: 'graduation-cap',
  宠物: 'cat',
  植物: 'flower',
  捐赠: 'hand-coins',
  烟酒: 'cigarette',
  罚款: 'banknote',

  其他: 'circle-ellipsis',
  未分类: 'circle-ellipsis',
};

/**
 * 取分类图标。
 *
 * 传入整个分类对象而不是 icon 字段，是为了让「按名字反查」这条兜底路径
 * 不必由调用方重复实现 —— 五个视图各写一遍的话，迟早有一处忘记兜底、
 * 于是那一页的分类全是空白方块。
 */
export function resolveCategoryIcon(category: { name: string; icon: string }): Component {
  const stored = category.icon;

  if (stored !== '' && stored in ICON_REGISTRY) {
    return ICON_REGISTRY[stored as IconName];
  }

  const guessed = ICON_BY_CATEGORY_NAME[category.name];
  if (guessed !== undefined) return ICON_REGISTRY[guessed];

  return FALLBACK_ICON;
}

/**
 * 支付方式图标。
 *
 * 按**类型**推断，不给 payment_methods 加字段 —— 它只有「现金类 / 信用类」
 * 两种，图标完全由类型决定，加一列 icon 只是让用户有机会把「现金」配成信用卡。
 * （分类不一样：分类有成百种语义，图标必须可自定义。）
 */
export function resolvePaymentMethodIcon(type: 'cash' | 'credit'): Component {
  return type === 'credit' ? ICON_REGISTRY['credit-card'] : ICON_REGISTRY.banknote;
}

/** 图标选择器的候选，按用途分组 —— 平铺 80 个图标是选不动的。 */
export const ICON_GROUPS: ReadonlyArray<{ label: string; icons: readonly IconName[] }> = [
  {
    label: '餐饮',
    icons: ['utensils', 'utensils-crossed', 'coffee', 'cake-slice', 'sandwich', 'soup', 'ice-cream', 'wine', 'beer'],
  },
  { label: '交通', icons: ['bus', 'train', 'car', 'car-front', 'parking', 'fuel', 'bike', 'plane', 'truck'] },
  {
    label: '居住',
    icons: ['house', 'landmark', 'building', 'zap', 'flame', 'wifi', 'house-plug', 'lamp', 'bed', 'sofa', 'shower-head', 'wrench'],
  },
  {
    label: '购物',
    icons: ['shopping-cart', 'shopping-basket', 'shirt', 'footprints', 'scissors', 'sparkles', 'package', 'store'],
  },
  {
    label: '通讯与数码',
    icons: ['smartphone', 'phone', 'laptop', 'monitor-smartphone', 'printer', 'newspaper'],
  },
  { label: '医疗', icons: ['stethoscope', 'pill', 'syringe', 'heart-pulse'] },
  {
    label: '娱乐',
    icons: ['gamepad-2', 'clapperboard', 'film', 'music', 'mic', 'theater', 'ticket', 'party-popper', 'palette', 'camera', 'video'],
  },
  { label: '人情与金融', icons: ['gift', 'hand-coins', 'wallet', 'banknote'] },
  {
    label: '其他',
    icons: ['tag', 'circle-ellipsis', 'briefcase', 'graduation-cap', 'book-open', 'baby', 'cat', 'dog', 'dumbbell', 'cigarette', 'tree-pine', 'flower', 'church'],
  },
];
