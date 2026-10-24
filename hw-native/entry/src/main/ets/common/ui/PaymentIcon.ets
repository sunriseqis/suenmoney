/**
 * 支付方式图标（与 Web `payment-icons.ts` 同构）。
 *
 * 渲染方案（旧的 Lucide/品牌 Path 手绘已废弃——24 单位空间缩放后描边/抗锯齿不可控，真机发糊）：
 * - 品牌图形（支付宝 / 微信 / 云闪付 / 京东 / 抖音）：系统内置符号里没有品牌 logo，
 *   改用随包 SVG 媒体资源（`resources/base/media/pay_*.svg`，1024 坐标系矢量），
 *   `Image` 原生解码 SVG，任意尺寸都清晰，`fillColor` 运行时染品牌色。
 * - 其余（银行卡 / 信用卡 / 现金 / 银行转账 / 其它钱包）：鸿蒙内置 Symbol（`sys.symbol.*`）。
 * - 解析优先级不变：**显式 icon > 按支付方式名反推 > 兜底银行卡**。
 *
 * 注意：品牌色是**品牌识别色**（支付宝蓝、微信绿…），跟主题的 accent 无关，
 * 也不是语义色 —— 所以这里是一张固定的色表，不参与 R25 的语义配色。
 */

/** 支付图标 id（与 Web PaymentIconId 完全一致） */
export type PayIconId =
  | 'alipay' | 'wechat' | 'unionpay' | 'jd' | 'douyin'
  | 'card' | 'creditcard' | 'cash' | 'bank' | 'wallet';

export interface PayOption {
  id: PayIconId;
  label: string;
  color: string;
  /** true = 品牌 SVG 媒体资源（Image 渲染）；false = 内置 Symbol（SymbolGlyph 渲染） */
  svg: boolean;
  /** svg=true → app.media 品牌矢量；svg=false → 系统内置符号（名字必须是字面量） */
  res: Resource;
}

/** 与 Web PAYMENT_ICON_OPTIONS 一一对应 */
export const PAY_OPTIONS: PayOption[] = [
  { id: 'alipay', label: '支付宝', color: '#1677FF', svg: true, res: $r('app.media.pay_alipay') },
  { id: 'wechat', label: '微信支付', color: '#07C160', svg: true, res: $r('app.media.pay_wechat') },
  { id: 'unionpay', label: '云闪付/银联', color: '#D83B01', svg: true, res: $r('app.media.pay_unionpay') },
  { id: 'jd', label: '京东支付', color: '#E1251B', svg: true, res: $r('app.media.pay_jd') },
  { id: 'douyin', label: '抖音支付', color: '#111827', svg: true, res: $r('app.media.pay_douyin') },
  { id: 'card', label: '银行卡', color: '#4F46E5', svg: false, res: $r('sys.symbol.bank_card') },
  { id: 'creditcard', label: '信用卡', color: '#F59E0B', svg: false, res: $r('sys.symbol.creditcard') },
  { id: 'cash', label: '现金', color: '#10B981', svg: false, res: $r('sys.symbol.coins') },
  { id: 'bank', label: '银行转账', color: '#2563EB', svg: false, res: $r('sys.symbol.building') },
  { id: 'wallet', label: '其它钱包', color: '#6B7280', svg: false, res: $r('sys.symbol.wallet') }
];

/** 支付方式解析结果 */
export interface PayVisual {
  id: PayIconId;
  color: string;
  /** true = 品牌 SVG 媒体资源（Image 渲染）；false = 内置 Symbol（SymbolGlyph 渲染） */
  svg: boolean;
  /** 媒体资源或内置符号资源 */
  res: Resource;
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
  return { id: opt.id, color: opt.color, svg: opt.svg, res: opt.res };
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
