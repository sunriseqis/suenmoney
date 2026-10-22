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

/** 语义化关键词自动匹配规则表 */
const SEMANTIC_ICON_RULES: Array<{ keywords: string[]; icon: IconName }> = [
  // 咖啡 / 早餐
  { keywords: ['咖啡', '拿铁', '美式', '早饭', '早餐', '星巴克', '瑞幸'], icon: 'coffee' },
  // 奶茶 / 酒水饮料
  { keywords: ['奶茶', '啤酒', '精酿', '清吧', '酒吧', '汽水', '可乐', '饮料', '喜茶', '奈雪', '蜜雪', '果汁', '饮品'], icon: 'beer' },
  // 蛋糕 / 甜点 / 烘焙
  { keywords: ['蛋糕', '甜点', '面包', '烘焙', '糕点', '甜品', '冰淇淋', '雪糕'], icon: 'cake-slice' },
  // 汉堡 / 简餐
  { keywords: ['汉堡', '三明治', '简餐', '快餐', '麦当劳', '肯德基', '赛百味'], icon: 'sandwich' },
  // 火锅 / 聚餐 / 堂食
  { keywords: ['火锅', '下馆', '正餐', '聚餐', '料理', '烧烤', '串串', '夜市', '小吃', '大排档'], icon: 'soup' },
  // 外卖 / 配送
  { keywords: ['外卖', '美团', '饿了么', '配送', '跑腿'], icon: 'utensils-crossed' },
  // 买菜 / 生鲜
  { keywords: ['买菜', '生鲜', '菜场', '果蔬', '蔬菜', '水果', '海鲜', '肉禽', '蛋奶'], icon: 'shopping-basket' },
  // 餐饮通用
  { keywords: ['餐', '吃', '饭', '食', '宴', '零食', '宵夜'], icon: 'utensils' },

  // 航空出行
  { keywords: ['飞机', '机票', '航班', '机场', '飞行', '空运', '航司'], icon: 'plane' },
  // 铁路 / 轨道
  { keywords: ['高铁', '动车', '火车', '铁路', '地铁', '轻轨', '轨道'], icon: 'train' },
  // 公交大巴
  { keywords: ['公交', '大巴', '巴士', '班车'], icon: 'bus' },
  // 网约车 / 出租车
  { keywords: ['打车', '滴滴', '出租', '叫车', '专车', '高德', '顺风车', '快车'], icon: 'car-front' },
  // 加油 / 充电
  { keywords: ['加油', '油费', '汽油', '柴油', '加气', '充电桩'], icon: 'fuel' },
  // 停车
  { keywords: ['停车', '车位', '车库'], icon: 'parking' },
  // 骑行
  { keywords: ['骑行', '单车', '自行车', '共享单车', '电动车', '电瓶车', '摩托'], icon: 'bike' },
  // 汽车相关
  { keywords: ['汽车', '车辆', '车险', '检车', '保养', '洗车', '过路费', '高速', 'etc', 'ETC', '修车', '驾校'], icon: 'car' },
  // 货运
  { keywords: ['货运', '搬家', '货拉拉'], icon: 'truck' },

  // 房贷 / 银行
  { keywords: ['房贷', '按揭', '首付', '银行', '利息'], icon: 'landmark' },
  // 租房 / 住所
  { keywords: ['房租', '租房', '租金', '押金', '房屋', '租客'], icon: 'house' },
  // 物业
  { keywords: ['物业', '管理费', '居委', '小区'], icon: 'building' },
  // 水电
  { keywords: ['水费', '电费', '供电', '用电', '自来水', '供水'], icon: 'zap' },
  // 燃气 / 暖气
  { keywords: ['燃气', '煤气', '天然气', '暖气', '供暖', '取暖'], icon: 'flame' },
  // 宽带
  { keywords: ['宽带', '光纤', '网费', '路由器', 'wifi', 'WiFi', '网络'], icon: 'wifi' },
  // 家电
  { keywords: ['家电', '电器', '冰箱', '空调', '洗衣机', '电视', '灯', '照明'], icon: 'lamp' },
  // 卧室
  { keywords: ['床', '寝具', '床单', '被子', '枕头'], icon: 'bed' },
  // 客厅家具
  { keywords: ['沙发', '家具', '茶几', '桌椅', '柜子'], icon: 'sofa' },
  // 卫浴
  { keywords: ['卫浴', '花洒', '热水器', '马桶', '洗澡', '沐浴', '洗护', '洗头'], icon: 'shower-head' },
  // 维修工具
  { keywords: ['装修', '五金', '工具', '维修', '修理', '改造', '建材'], icon: 'wrench' },

  // 商超购物
  { keywords: ['超市', '商场', '便利店', '山姆', '盒马', '沃尔玛', '大润发', '购物', '网购', '淘宝', '京东', '拼多多'], icon: 'shopping-cart' },
  // 服装
  { keywords: ['衣服', '服装', '上衣', '裤子', '外套', '羽绒服', '裙子', '内衣', '衬衫', 'T恤', '服饰', '包包'], icon: 'shirt' },
  // 鞋袜
  { keywords: ['鞋', '运动鞋', '靴', '凉鞋', '拖鞋', '袜子'], icon: 'footprints' },
  // 美妆护肤
  { keywords: ['美妆', '化妆', '护肤', '面膜', '口红', '香水', '防晒', '医美', '美容'], icon: 'sparkles' },
  // 理发美发
  { keywords: ['理发', '美发', '剪发', '烫染', '洗剪吹'], icon: 'scissors' },
  // 快递
  { keywords: ['快递', '包裹', '顺丰', '邮费', '寄件', '菜鸟', '转运', '物流'], icon: 'package' },
  // 日百百货
  { keywords: ['日用', '百货', '杂货', '纸巾', '清洁', '生活用品'], icon: 'store' },

  // 手机通讯
  { keywords: ['手机', '话费', '充值', '通信', '移动', '联通', '电信'], icon: 'smartphone' },
  // 电脑
  { keywords: ['电脑', '笔记本', '主机', '键盘', '鼠标', '显卡', 'mac', 'Mac'], icon: 'laptop' },
  // 数码产品
  { keywords: ['显示器', '平板', 'ipad', 'iPad', '数码', '智能'], icon: 'monitor-smartphone' },
  // 打印办公
  { keywords: ['打印', '复印', '墨盒', '文具', '办公'], icon: 'printer' },
  // 订阅资讯
  { keywords: ['报刊', '杂志', '订阅', '资讯', '新闻', '知识库'], icon: 'newspaper' },

  // 医疗门诊
  { keywords: ['门诊', '挂号', '医院', '医生', '看病', '就医', '诊所'], icon: 'stethoscope' },
  // 药品
  { keywords: ['药', '西药', '中药', '药店', '感冒', '消炎', '处方'], icon: 'pill' },
  // 治疗手术
  { keywords: ['住院', '手术', '针灸', '打针', '输液', '化验'], icon: 'syringe' },
  // 体检健康
  { keywords: ['体检', '心脏', '血压', '保健', '康复', '心理'], icon: 'heart-pulse' },

  // 游戏
  { keywords: ['游戏', '电竞', 'steam', 'Steam', '主机', 'switch', 'Switch', 'ps5', 'PS5', '手柄', '网游', '手游'], icon: 'gamepad-2' },
  // 电影
  { keywords: ['电影', '影院', '万达', '看片'], icon: 'clapperboard' },
  // 视频影视
  { keywords: ['视频', '影视', '剧集', '爱奇艺', '腾讯视频', 'bilibili', 'B站'], icon: 'film' },
  // 音乐
  { keywords: ['音乐', '歌曲', '网易云', 'qq音乐', 'QQ音乐', '耳机', '音响', '唱片'], icon: 'music' },
  // K歌
  { keywords: ['ktv', 'KTV', '唱歌', '麦克风', '演唱会', 'live', 'Live'], icon: 'mic' },
  // 剧场演出
  { keywords: ['话剧', '音乐剧', '展览', '展会', '博物馆', '演出', '剧场'], icon: 'theater' },
  // 门票景区
  { keywords: ['门票', '景区', '游乐园', '迪士尼', '环球影城'], icon: 'ticket' },
  // 聚会庆典
  { keywords: ['聚会', '派对', '庆祝', '生日', '年会', '团建'], icon: 'party-popper' },
  // 美术手工
  { keywords: ['美术', '绘画', '颜料', '手工', '陶艺', '插画', '设计'], icon: 'palette' },
  // 摄影
  { keywords: ['摄影', '相机', '镜头', '拍照', '写真', '摄像'], icon: 'camera' },

  // 人情礼金
  { keywords: ['礼物', '送礼', '礼品', '纪念品', '礼盒'], icon: 'gift' },
  { keywords: ['红包', '份子', '压岁钱', '打赏', '转账', '随礼'], icon: 'hand-coins' },
  { keywords: ['钱包', '零花钱', '备用金'], icon: 'wallet' },
  { keywords: ['现金', '钞票', '提现', '取款'], icon: 'banknote' },
  { keywords: ['信用卡', '还款', '借款', '贷款', '还贷', '分期'], icon: 'credit-card' },

  // 宠物生活
  { keywords: ['猫', '喵'], icon: 'cat' },
  { keywords: ['狗', '汪'], icon: 'dog' },
  { keywords: ['宠物', '兽医', '宠粮', '疫苗'], icon: 'cat' },

  // 母婴早教
  { keywords: ['母婴', '婴儿', '宝宝', '儿童', '奶粉', '尿不湿', '玩具', '早教', '幼托'], icon: 'baby' },
  // 学习进修
  { keywords: ['学习', '考研', '考公', '培训', '学费', '网课', '学历', '考证', '教育'], icon: 'graduation-cap' },
  // 书籍
  { keywords: ['书', '图书', '阅读', '教材', '小说', '借书'], icon: 'book-open' },
  // 运动健身
  { keywords: ['运动', '健身', '私教', '跑步', '羽毛球', '篮球', '足球', '游泳', '瑜伽', '普拉提', '球类'], icon: 'dumbbell' },
  // 植物花卉
  { keywords: ['花', '绿植', '植物', '盆栽', '园艺', '鲜花'], icon: 'flower' },
  // 烟草
  { keywords: ['烟', '香烟', '电子烟'], icon: 'cigarette' },
  // 户外露营旅游
  { keywords: ['露营', '户外', '登山', '徒步', '公园', '旅游', '旅行'], icon: 'tree-pine' },
  // 家政保洁
  { keywords: ['家政', '保洁', '阿姨', '垃圾', '废品'], icon: 'trash-2' },
  // 工作商务
  { keywords: ['工作', '商务', '差旅', '出差'], icon: 'briefcase' },
];

/** 多样化兜底图标池（避免所有未知分类都展示同一种 Tag 图标） */
const VARIED_FALLBACKS: readonly IconName[] = [
  'tag',
  'circle-ellipsis',
  'sparkles',
  'package',
  'wallet',
  'store',
  'briefcase',
  'party-popper',
];

export function resolveCategoryIconName(category: { name: string; icon: string }): IconName {
  const stored = category.icon;
  if (stored !== '' && stored in ICON_REGISTRY) {
    return stored as IconName;
  }

  const trimmed = (category.name || '').trim();
  if (!trimmed) return 'tag';

  // 1. 精确匹配
  const exact = ICON_BY_CATEGORY_NAME[trimmed];
  if (exact !== undefined) return exact;

  // 2. 语义关键词包含匹配
  const lower = trimmed.toLowerCase();
  for (const rule of SEMANTIC_ICON_RULES) {
    for (const kw of rule.keywords) {
      if (lower.includes(kw.toLowerCase())) {
        return rule.icon;
      }
    }
  }

  // 3. 根据名称散列，均匀分散到不同兜底图标
  let hash = 0;
  for (let i = 0; i < trimmed.length; i += 1) {
    hash = (hash * 31 + trimmed.charCodeAt(i)) >>> 0;
  }
  return VARIED_FALLBACKS[hash % VARIED_FALLBACKS.length] ?? 'tag';
}

/**
 * 取分类图标。
 *
 * 优先级：显式设置 > 精确匹配 > 语义关键词推导 > 多样散列兜底。
 */
export function resolveCategoryIcon(category: { name: string; icon: string }): Component {
  const iconName = resolveCategoryIconName(category);
  return ICON_REGISTRY[iconName] ?? FALLBACK_ICON;
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
