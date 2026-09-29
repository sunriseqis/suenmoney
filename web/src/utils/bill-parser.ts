/**
 * 微信与支付宝账单 CSV 解析器与智能分类映射。
 *
 * 核心设计目标：
 * 1. 容错性高：微信与支付宝的导出文件包含头尾说明、GBK/UTF-8 编码差异、带逗号与换行的单元格引用；
 * 2. 智能分类：根据交易对方、商品名称、原始交易分类等关键词，自动推荐用户已有分类体系中的对应二级分类；
 * 3. 智能渠道：根据账单来源与扣款渠道（零钱、余额宝、花呗、银行卡等），自动匹配现有支付方式。
 */
import type { Category, PaymentMethod } from '@/api/types';
import { parseYuanToCents } from './money.ts';

export type BillSource = 'wechat' | 'alipay' | 'suenmoney' | 'unknown';

export interface ParsedBillItem {
  rawIndex: number;
  transactionTime: string;
  spendDate: string;
  direction: 'expense' | 'income' | 'other';
  amountCents: number;
  amountYuan: string;
  counterparty: string;
  description: string;
  paymentMethodRaw: string;
  status: string;
  note: string;
  suggestedCategoryId: string | null;
  suggestedPaymentMethodId: string | null;
  selected: boolean;
}

export interface ParseBillResult {
  source: BillSource;
  totalParsed: number;
  expenseCount: number;
  incomeCount: number;
  otherCount: number;
  items: ParsedBillItem[];
}

/**
 * 通用 CSV 文本解析（符合 RFC 4180 标准）。
 * 正确处理引号包裹、引号转义（""）及单元格内换行。
 */
export function parseCsvRows(text: string): string[][] {
  const clean = text.replace(/^\uFEFF/, '');
  const rows: string[][] = [];
  let currentRow: string[] = [];
  let currentCell = '';
  let inQuotes = false;

  for (let i = 0; i < clean.length; i += 1) {
    const char = clean[i];
    const next = clean[i + 1];

    if (inQuotes) {
      if (char === '"') {
        if (next === '"') {
          currentCell += '"';
          i += 1; // 跳过转义双引号
        } else {
          inQuotes = false;
        }
      } else {
        currentCell += char;
      }
    } else if (char === '"') {
      inQuotes = true;
    } else if (char === ',') {
      currentRow.push(currentCell.trim());
      currentCell = '';
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && next === '\n') {
        i += 1;
      }
      currentRow.push(currentCell.trim());
      currentCell = '';
      if (currentRow.some((c) => c !== '')) {
        rows.push(currentRow);
      }
      currentRow = [];
    } else {
      currentCell += char;
    }
  }

  if (currentCell !== '' || currentRow.length > 0) {
    currentRow.push(currentCell.trim());
    if (currentRow.some((c) => c !== '')) {
      rows.push(currentRow);
    }
  }

  return rows;
}

/**
 * 自动识别账单来源
 */
export function detectBillSource(text: string): BillSource {
  if (text.includes('消费日') && text.includes('还款日') && text.includes('二级分类')) {
    return 'suenmoney';
  }
  if (text.includes('微信支付账单明细') || (text.includes('微信支付') && text.includes('交易单号'))) {
    return 'wechat';
  }
  if (
    text.includes('支付宝交易记录明细查询') ||
    text.includes('商家订单号') ||
    (text.includes('支付宝') && text.includes('交易时间'))
  ) {
    return 'alipay';
  }
  return 'unknown';
}

/**
 * 解码 ArrayBuffer。自动探测 UTF-8 与 GBK。
 */
export function decodeCsvBuffer(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  // 检查 UTF-8 BOM
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
    return new TextDecoder('utf-8').decode(bytes);
  }

  // 先尝试 UTF-8 解码
  const utf8Decoder = new TextDecoder('utf-8', { fatal: false });
  const utf8Text = utf8Decoder.decode(bytes);

  // 如果包含大量替换字符 \uFFFD 或没有匹配到常见关键词，退回 GBK
  const hasReplacement = utf8Text.includes('\uFFFD');
  const hasKeywords =
    utf8Text.includes('微信支付') ||
    utf8Text.includes('支付宝') ||
    utf8Text.includes('交易时间') ||
    utf8Text.includes('收/支');

  if (hasReplacement || !hasKeywords) {
    try {
      const gbkDecoder = new TextDecoder('gbk', { fatal: false });
      return gbkDecoder.decode(bytes);
    } catch {
      return utf8Text;
    }
  }

  return utf8Text;
}

// 常用关键词到分类名称的模糊映射字典
const KEYWORD_CATEGORY_MAP: Array<{ categoryNames: string[]; keywords: string[] }> = [
  {
    categoryNames: ['外卖', '餐饮美食', '堂食外卖', '餐饮', '美食'],
    keywords: [
      '美团',
      '饿了么',
      '外卖',
      '麦当劳',
      '肯德基',
      '汉堡王',
      '星巴克',
      '瑞幸',
      '喜茶',
      '霸王茶姬',
      '奶茶',
      '咖啡',
      '饭店',
      '快餐',
      '大排档',
      '面馆',
      '米线',
      '牛肉面',
      '麻辣烫',
      '火锅',
      '烧烤',
      '烤肉',
      '食堂',
      '披萨',
      '必胜客',
      '黄焖鸡',
      '茶百道',
      '蜜雪冰城',
      '古茗',
      '奈雪',
    ],
  },
  {
    categoryNames: ['食材调料', '买菜', '生鲜', '菜市场'],
    keywords: ['买菜', '生鲜', '叮咚买菜', '朴朴', '菜市场', '农贸', '果蔬', '水果', '鲜肉'],
  },
  {
    categoryNames: ['零食饮品', '奶茶甜品', '零食'],
    keywords: ['良品铺子', '三只松鼠', '零食', '甜品', '烘焙', '面包', '蛋糕', '好利来'],
  },
  {
    categoryNames: ['生活日用', '日用百货', '购物', '日用', '百货'],
    keywords: [
      '超市',
      '便利店',
      '罗森',
      '7-11',
      '全家',
      '天猫超市',
      '京东超市',
      '山姆',
      '盒马',
      '沃尔玛',
      '屈臣氏',
      '名创优品',
      '百货',
      '杂货',
      '日用品',
    ],
  },
  {
    categoryNames: ['交通出行', '出行打车', '交通', '打车'],
    keywords: [
      '滴滴',
      '花小猪',
      '曹操',
      '高德打车',
      '打车',
      '出租车',
      '地铁',
      '公交',
      '一卡通',
      '交通卡',
      '铁路',
      '12306',
      '机票',
      '携程',
      '飞猪',
      '航旅纵横',
      '客运',
    ],
  },
  {
    categoryNames: ['汽车相关', '加油充电', '停车费用', '洗车保养'],
    keywords: [
      '加油',
      '中石化',
      '中国石化',
      '中石油',
      '中国石油',
      '充电',
      '特来电',
      '星星充电',
      '停车',
      '车场',
      '洗车',
      '保养',
      '车品',
      '车险',
      '违章',
    ],
  },
  {
    categoryNames: ['居家缴费', '水电燃气', '话费通讯', '物业缴费'],
    keywords: [
      '电费',
      '水费',
      '燃气',
      '物业',
      '宽带',
      '话费',
      '充值中心',
      '中国移动',
      '中国联通',
      '中国电信',
      '电信',
      '联通',
      '移动',
    ],
  },
  {
    categoryNames: ['医疗保健', '问诊就医', '药品保健', '医疗'],
    keywords: [
      '医院',
      '门诊',
      '药房',
      '大药房',
      '药店',
      '体检',
      '挂号',
      '卫生院',
      '诊所',
      '药业',
      '医药',
      '卫健',
    ],
  },
  {
    categoryNames: ['休闲娱乐', '娱乐', '游戏'],
    keywords: [
      '电影',
      '影城',
      '影院',
      '淘票票',
      '猫眼',
      'KTV',
      '网吧',
      '游戏',
      'Steam',
      '网易充值',
      '腾讯充值',
      '剧本杀',
      '密室',
      '游乐场',
    ],
  },
  {
    categoryNames: ['数码数码', '数码电器', '数码', '电器'],
    keywords: ['苹果', 'Apple', '小米', '华为', 'OPPO', 'vivo', '电脑', '数码', '京东电器', '顺电'],
  },
  {
    categoryNames: ['服饰装扮', '服饰鞋包', '服饰', '服装'],
    keywords: ['优衣库', 'ZARA', 'UR', '耐克', 'Nike', '阿迪达斯', 'Adidas', '服装', '鞋', '男装', '女装'],
  },
  {
    categoryNames: ['母婴亲子', '母婴用品', '母婴'],
    keywords: ['母婴', '奶粉', '孩子王', '玩具', '乐高', '童装', '婴儿'],
  },
];

/**
 * 智能推荐分类
 */
export function suggestCategory(
  searchQuery: string,
  categories: Category[],
): string | null {
  if (categories.length === 0 || searchQuery.trim() === '') return null;

  const query = searchQuery.toLowerCase();

  // 1. 先用关键词规则匹配
  for (const group of KEYWORD_CATEGORY_MAP) {
    if (group.keywords.some((kw) => query.includes(kw.toLowerCase()))) {
      // 优先在用户已有分类中寻找二级分类（更具体）
      for (const targetName of group.categoryNames) {
        const childMatch = categories.find(
          (c) =>
            c.parentId !== null &&
            c.isEnabled &&
            (c.name.includes(targetName) || targetName.includes(c.name)),
        );
        if (childMatch) return childMatch.id;
      }

      // 其次寻找一级分类
      for (const targetName of group.categoryNames) {
        const rootMatch = categories.find(
          (c) =>
            c.parentId === null &&
            c.isEnabled &&
            (c.name.includes(targetName) || targetName.includes(c.name)),
        );
        if (rootMatch) return rootMatch.id;
      }
    }
  }

  // 2. 直接根据已有分类名称模糊匹配
  for (const category of categories) {
    if (category.isEnabled && query.includes(category.name.toLowerCase())) {
      return category.id;
    }
  }

  return null;
}

/**
 * 智能推荐支付方式
 */
export function suggestPaymentMethod(
  channelRaw: string,
  source: BillSource,
  paymentMethods: PaymentMethod[],
): string | null {
  if (paymentMethods.length === 0) return null;

  const raw = channelRaw.toLowerCase();

  // 1. 根据账单提取渠道包含特定卡种或银行名匹配
  for (const method of paymentMethods) {
    if (!method.isEnabled) continue;
    const name = method.name.toLowerCase();
    if (raw.includes(name) || (name.includes('信用卡') && raw.includes('信用卡'))) {
      return method.id;
    }
  }

  // 2. 根据来源匹配微信或支付宝
  if (source === 'wechat') {
    const wx = paymentMethods.find((m) => m.isEnabled && m.name.includes('微信'));
    if (wx) return wx.id;
  } else if (source === 'alipay') {
    const ali = paymentMethods.find((m) => m.isEnabled && m.name.includes('支付宝'));
    if (ali) return ali.id;
  }

  // 3. 兜底为第一个可用的支付方式
  const usable = paymentMethods.find((m) => m.isEnabled);
  return usable?.id ?? null;
}

/**
 * 解析微信账单
 */
export function parseWeChatBill(
  csvText: string,
  categories: Category[] = [],
  paymentMethods: PaymentMethod[] = [],
): ParseBillResult {
  const rows = parseCsvRows(csvText);

  // 找到表头所在行
  let headerIndex = -1;
  for (let i = 0; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (row.includes('交易时间') && (row.includes('金额(元)') || row.includes('金额'))) {
      headerIndex = i;
      break;
    }
  }

  if (headerIndex === -1) {
    return {
      source: 'wechat',
      totalParsed: 0,
      expenseCount: 0,
      incomeCount: 0,
      otherCount: 0,
      items: [],
    };
  }

  const headers = rows[headerIndex]!;
  const timeIdx = headers.indexOf('交易时间');
  const typeIdx = headers.indexOf('交易类型');
  const peerIdx = headers.indexOf('交易对方');
  const descIdx = headers.indexOf('商品');
  const dirIdx = headers.indexOf('收/支');
  const amountIdx = headers.findIndex((h) => h.includes('金额'));
  const methodIdx = headers.indexOf('支付方式');
  const statusIdx = headers.indexOf('当前状态');
  const noteIdx = headers.indexOf('备注');

  const items: ParsedBillItem[] = [];
  let expenseCount = 0;
  let incomeCount = 0;
  let otherCount = 0;

  for (let i = headerIndex + 1; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (row.length < 5) continue;

    const timeStr = (row[timeIdx] ?? '').trim();
    if (!timeStr) continue;
    const spendDate = timeStr.slice(0, 10);

    const dirStr = (row[dirIdx] ?? '').trim();
    let direction: 'expense' | 'income' | 'other' = 'other';
    if (dirStr === '支出') {
      direction = 'expense';
      expenseCount += 1;
    } else if (dirStr === '收入') {
      direction = 'income';
      incomeCount += 1;
    } else {
      otherCount += 1;
    }

    const rawAmount = (row[amountIdx] ?? '').replace(/[¥,]/g, '').trim();
    const amountCents = parseYuanToCents(rawAmount);

    const counterparty = (row[peerIdx] ?? '').trim();
    const description = (row[descIdx] ?? '').trim();
    const paymentMethodRaw = (row[methodIdx] ?? '').trim();
    const status = (row[statusIdx] ?? '').trim();
    const rawNote = (row[noteIdx] ?? '').trim();
    const transactionType = typeIdx >= 0 ? (row[typeIdx] ?? '').trim() : '';

    // 组合备注
    const noteParts: string[] = [];
    if (counterparty) noteParts.push(counterparty);
    if (description && description !== '/' && description !== counterparty) {
      noteParts.push(description);
    }
    if (rawNote && rawNote !== '/') {
      noteParts.push(rawNote);
    }
    const note = noteParts.join(' · ');

    const combinedSearchText = `${counterparty} ${description} ${transactionType} ${note}`;
    const suggestedCategoryId = suggestCategory(combinedSearchText, categories);
    const suggestedPaymentMethodId = suggestPaymentMethod(
      paymentMethodRaw,
      'wechat',
      paymentMethods,
    );

    items.push({
      rawIndex: i + 1,
      transactionTime: timeStr,
      spendDate,
      direction,
      amountCents,
      amountYuan: rawAmount,
      counterparty,
      description,
      paymentMethodRaw,
      status,
      note,
      suggestedCategoryId,
      suggestedPaymentMethodId,
      selected: direction === 'expense', // 默认选中支出
    });
  }

  return {
    source: 'wechat',
    totalParsed: items.length,
    expenseCount,
    incomeCount,
    otherCount,
    items,
  };
}

/**
 * 解析支付宝账单
 */
export function parseAlipayBill(
  csvText: string,
  categories: Category[] = [],
  paymentMethods: PaymentMethod[] = [],
): ParseBillResult {
  const rows = parseCsvRows(csvText);

  let headerIndex = -1;
  for (let i = 0; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (
      (row.includes('交易时间') || row.includes('付款时间') || row.includes('交易创建时间')) &&
      row.some((h) => h.includes('金额'))
    ) {
      headerIndex = i;
      break;
    }
  }

  if (headerIndex === -1) {
    return {
      source: 'alipay',
      totalParsed: 0,
      expenseCount: 0,
      incomeCount: 0,
      otherCount: 0,
      items: [],
    };
  }

  const headers = rows[headerIndex]!;
  const timeIdx = headers.findIndex((h) => h.includes('时间'));
  const peerIdx = headers.indexOf('交易对方');
  const catIdx = headers.indexOf('交易分类');
  const descIdx = headers.findIndex((h) => h === '商品说明' || h === '商品名称');
  const dirIdx = headers.indexOf('收/支');
  const amountIdx = headers.findIndex((h) => h.includes('金额'));
  const methodIdx = headers.findIndex((h) => h.includes('方式') || h.includes('渠道'));
  const statusIdx = headers.indexOf('交易状态');
  const noteIdx = headers.indexOf('备注');

  const items: ParsedBillItem[] = [];
  let expenseCount = 0;
  let incomeCount = 0;
  let otherCount = 0;

  for (let i = headerIndex + 1; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (row.length < 5) continue;

    const timeStr = (row[timeIdx] ?? '').trim();
    if (!timeStr || !timeStr.match(/^\d{4}-\d{2}-\d{2}/)) continue;
    const spendDate = timeStr.slice(0, 10);

    const dirStr = (row[dirIdx] ?? '').trim();
    let direction: 'expense' | 'income' | 'other' = 'other';
    if (dirStr === '支出') {
      direction = 'expense';
      expenseCount += 1;
    } else if (dirStr === '收入') {
      direction = 'income';
      incomeCount += 1;
    } else {
      otherCount += 1;
    }

    const rawAmount = (row[amountIdx] ?? '').replace(/[¥,]/g, '').trim();
    const amountCents = parseYuanToCents(rawAmount);

    const counterparty = (row[peerIdx] ?? '').trim();
    const description = (row[descIdx] ?? '').trim();
    const categoryRaw = catIdx >= 0 ? (row[catIdx] ?? '').trim() : '';
    const paymentMethodRaw = methodIdx >= 0 ? (row[methodIdx] ?? '').trim() : '';
    const status = statusIdx >= 0 ? (row[statusIdx] ?? '').trim() : '';
    const rawNote = noteIdx >= 0 ? (row[noteIdx] ?? '').trim() : '';

    const noteParts: string[] = [];
    if (counterparty) noteParts.push(counterparty);
    if (description && description !== counterparty) noteParts.push(description);
    if (rawNote) noteParts.push(rawNote);
    const note = noteParts.join(' · ');

    const combinedSearchText = `${counterparty} ${description} ${categoryRaw} ${note}`;
    const suggestedCategoryId = suggestCategory(combinedSearchText, categories);
    const suggestedPaymentMethodId = suggestPaymentMethod(
      paymentMethodRaw,
      'alipay',
      paymentMethods,
    );

    items.push({
      rawIndex: i + 1,
      transactionTime: timeStr,
      spendDate,
      direction,
      amountCents,
      amountYuan: rawAmount,
      counterparty,
      description,
      paymentMethodRaw,
      status,
      note,
      suggestedCategoryId,
      suggestedPaymentMethodId,
      selected: direction === 'expense',
    });
  }

  return {
    source: 'alipay',
    totalParsed: items.length,
    expenseCount,
    incomeCount,
    otherCount,
    items,
  };
}

/**
 * 解析 suenmoney 导出的标准流水对账 CSV
 */
export function parseSuenmoneyBill(
  csvText: string,
  categories: Category[] = [],
  paymentMethods: PaymentMethod[] = [],
): ParseBillResult {
  const rows = parseCsvRows(csvText);

  // 表头行定位
  let headerIndex = -1;
  for (let i = 0; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (row.includes('消费日') && row.includes('金额') && (row.includes('二级分类') || row.includes('分类'))) {
      headerIndex = i;
      break;
    }
  }

  if (headerIndex === -1) {
    return {
      source: 'suenmoney',
      totalParsed: 0,
      expenseCount: 0,
      incomeCount: 0,
      otherCount: 0,
      items: [],
    };
  }

  const headers = rows[headerIndex]!;
  const spendDateIdx = headers.indexOf('消费日');
  const amountIdx = headers.indexOf('金额');
  const parentCatIdx = headers.indexOf('分类');
  const childCatIdx = headers.indexOf('二级分类');
  const methodIdx = headers.indexOf('支付方式');
  const noteIdx = headers.indexOf('备注');

  const items: ParsedBillItem[] = [];
  let expenseCount = 0;

  for (let i = headerIndex + 1; i < rows.length; i += 1) {
    const row = rows[i]!;
    if (row.length <= 1 || !row.some((cell) => cell.trim() !== '')) continue;

    const spendDate = (row[spendDateIdx] ?? '').trim().slice(0, 10);
    const rawAmount = (row[amountIdx] ?? '').trim();
    const rawParent = (row[parentCatIdx] ?? '').trim();
    const rawChild = (row[childCatIdx] ?? '').trim();
    const rawMethod = (row[methodIdx] ?? '').trim();
    const note = (row[noteIdx] ?? '').trim();

    const amountCents = parseYuanToCents(rawAmount);
    if (amountCents <= 0) continue;

    // 分类匹配：优先二级，其次一级
    let suggestedCategoryId: string | null = null;
    if (rawChild) {
      const match = categories.find((c) => c.isEnabled && c.name.toLowerCase() === rawChild.toLowerCase());
      if (match) suggestedCategoryId = match.id;
    }
    if (!suggestedCategoryId && rawParent) {
      const match = categories.find((c) => c.isEnabled && c.name.toLowerCase() === rawParent.toLowerCase());
      if (match) suggestedCategoryId = match.id;
    }
    if (!suggestedCategoryId) {
      suggestedCategoryId = suggestCategory(`${rawParent} ${rawChild} ${note}`, categories);
    }

    // 支付方式匹配
    let suggestedPaymentMethodId: string | null = null;
    if (rawMethod) {
      const match = paymentMethods.find((m) => m.isEnabled && m.name.toLowerCase() === rawMethod.toLowerCase());
      if (match) suggestedPaymentMethodId = match.id;
    }
    if (!suggestedPaymentMethodId && paymentMethods.length > 0) {
      const usable = paymentMethods.find((m) => m.isEnabled);
      suggestedPaymentMethodId = usable?.id ?? null;
    }

    const counterparty = rawParent && rawChild ? `${rawParent} · ${rawChild}` : (rawChild || rawParent || '流水');

    items.push({
      rawIndex: i + 1,
      transactionTime: spendDate,
      spendDate,
      direction: 'expense',
      amountCents,
      amountYuan: (amountCents / 100).toFixed(2),
      counterparty,
      description: note || 'suenmoney 流水',
      paymentMethodRaw: rawMethod,
      status: '成功',
      note,
      suggestedCategoryId,
      suggestedPaymentMethodId,
      selected: true,
    });
    expenseCount += 1;
  }

  return {
    source: 'suenmoney',
    totalParsed: items.length,
    expenseCount,
    incomeCount: 0,
    otherCount: 0,
    items,
  };
}

/**
 * 自动识别并解析账单
 */
export function detectAndParseBill(
  csvText: string,
  categories: Category[] = [],
  paymentMethods: PaymentMethod[] = [],
  preferredSource?: BillSource,
): ParseBillResult {
  const source = preferredSource && preferredSource !== 'unknown' ? preferredSource : detectBillSource(csvText);
  if (source === 'wechat') {
    return parseWeChatBill(csvText, categories, paymentMethods);
  }
  if (source === 'alipay') {
    return parseAlipayBill(csvText, categories, paymentMethods);
  }
  if (source === 'suenmoney') {
    return parseSuenmoneyBill(csvText, categories, paymentMethods);
  }

  // 兜底尝试
  const wechat = parseWeChatBill(csvText, categories, paymentMethods);
  if (wechat.totalParsed > 0) return wechat;
  const alipay = parseAlipayBill(csvText, categories, paymentMethods);
  if (alipay.totalParsed > 0) return alipay;
  return parseSuenmoneyBill(csvText, categories, paymentMethods);
}
