/**
 * 支付方式图标（与 Web `payment-icons.ts` 同构）。
 *
 * 规则与 Web 一致：
 * - 品牌图形（支付宝 / 微信 / 云闪付 / 京东 / 抖音 / 银行卡）有自带的 1024 坐标系填充路径，
 *   在 `PAY_BRAND_PATHS` 里（已归一化到 24 单位），品牌色固定写在选项表里。
 * - 另外四种（信用卡 / 现金 / 银行转账 / 其它钱包）没有品牌图形，退回 Lucide 描边图标。
 * - 解析优先级：**显式 icon > 按支付方式名反推 > 兜底银行卡**。
 *
 * 注意：品牌色是**品牌识别色**（支付宝蓝、微信绿…），跟主题的 accent 无关，
 * 也不是语义色 —— 所以这里是一张固定的色表，不参与 R25 的语义配色。
 */
import { ICON_PATHS, PAY_BRAND_PATHS } from './IconPaths';

/** 支付图标 id（与 Web PaymentIconId 完全一致） */
export type PayIconId =
  | 'alipay' | 'wechat' | 'unionpay' | 'jd' | 'douyin'
  | 'card' | 'creditcard' | 'cash' | 'bank' | 'wallet';

interface PayOption {
  id: PayIconId;
  label: string;
  color: string;
  /** true = 品牌填充图形；false = Lucide 描边 */
  brand: boolean;
  /** 可选：绑定的 Lucide 名（非品牌图形时用） */
  lucide: string;
}

/** 与 Web PAYMENT_ICON_OPTIONS 一一对应 */
export const PAY_OPTIONS: PayOption[] = [
  { id: 'alipay', label: '支付宝', color: '#1677FF', brand: true, lucide: '' },
  { id: 'wechat', label: '微信支付', color: '#07C160', brand: true, lucide: '' },
  { id: 'unionpay', label: '云闪付/银联', color: '#D83B01', brand: true, lucide: '' },
  { id: 'jd', label: '京东支付', color: '#E1251B', brand: true, lucide: '' },
  { id: 'douyin', label: '抖音支付', color: '#111827', brand: true, lucide: '' },
  { id: 'card', label: '银行卡', color: '#4F46E5', brand: true, lucide: '' },
  { id: 'creditcard', label: '信用卡', color: '#F59E0B', brand: false, lucide: 'credit-card' },
  { id: 'cash', label: '现金', color: '#10B981', brand: false, lucide: 'banknote' },
  { id: 'bank', label: '银行转账', color: '#2563EB', brand: false, lucide: 'landmark' },
  { id: 'wallet', label: '其它钱包', color: '#6B7280', brand: false, lucide: 'wallet' }
];

/** 支付方式解析结果 */
export interface PayVisual {
  id: PayIconId;
  color: string;
  /** 24 单位空间的 path d */
  path: string;
  /** true = 填充型 */
  brand: boolean;
}

function optionOf(id: PayIconId): PayOption {
  for (const o of PAY_OPTIONS) {
    if (o.id === id) {
      return o;
    }
  }
  return PAY_OPTIONS[5];
}

function visualOf(id: PayIconId): PayVisual {
  const opt = optionOf(id);
  let d = '';
  if (opt.brand) {
    const hit = PAY_BRAND_PATHS[id];
    d = hit === undefined ? '' : hit;
  } else {
    const hit = ICON_PATHS[opt.lucide];
    d = hit === undefined ? '' : hit;
  }
  return { id: id, color: opt.color, path: d, brand: opt.brand };
}

function has(hay: string, needle: string): boolean {
  return hay.indexOf(needle) >= 0;
}

/**
 * 支付方式名/显式 icon → 图标 + 品牌色（复刻 Web `resolvePaymentIcon` 的判定顺序）。
 */
export function resolvePayVisual(name: string, explicitIcon: string): PayVisual {
  const explicit = (explicitIcon ?? '').trim().toLowerCase();
  if (explicit !== '') {
    for (const o of PAY_OPTIONS) {
      if (o.id === explicit) {
        return visualOf(o.id);
      }
    }
  }
  const n = (name ?? '').toLowerCase();
  if (has(n, '支付宝') || has(n, '花呗') || has(n, 'alipay')) {
    return visualOf('alipay');
  }
  if (has(n, '微信') || has(n, '财付通') || has(n, 'wechat') || has(n, 'wx')) {
    return visualOf('wechat');
  }
  if (has(n, '银联') || has(n, '云闪付') || has(n, 'unionpay')) {
    return visualOf('unionpay');
  }
  if (has(n, '京东') || has(n, '白条') || has(n, 'jd')) {
    return visualOf('jd');
  }
  if (has(n, '抖音') || has(n, 'douyin')) {
    return visualOf('douyin');
  }
  if (has(n, '现金') || has(n, 'cash')) {
    return visualOf('cash');
  }
  if (has(n, '信用卡') || has(n, '贷记卡') || has(n, 'credit')) {
    return visualOf('creditcard');
  }
  if (has(n, '储蓄卡') || has(n, '借记卡') || has(n, '银行卡') || has(n, '卡')) {
    return visualOf('card');
  }
  if (has(n, '银行') || has(n, '转账') || has(n, '汇款')) {
    return visualOf('bank');
  }
  return visualOf('card');
}
