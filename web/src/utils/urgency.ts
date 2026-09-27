/**
 * 紧急度 —— 待办卡与「本月待还」共用同一套规则。
 *
 * 抽出来的原因：这两处都在回答同一个问题「哪天要付、还差几天」，
 * 各写一遍的话「几天算紧急」迟早只在一处生效，同一屏上出现两种口径。
 *
 * 只分三档，刻意不细分 —— 再多的档位就没法用**颜色**表达了，
 * 而颜色是这里唯一能在扫视时被瞬间读懂的手段。
 *
 *
 * ## 为什么最终不用「满色填充」，而用「色条 + 状态文字」
 *
 * 这一段是被推翻过两次的结果，值得记下来：
 *
 *   第一版：所有待办卡一律琥珀满色。结果一屏五块饱和色，读起来像五条并列的
 *          警告横幅，紧急度反而消失了 —— 因为**全都一样刺眼**。
 *   第二版：按紧急度分色填充（逾期红 / ≤1 天琥珀 / 更远中性）。语义对了，
 *          但演示数据里恰好有两笔逾期，于是变成三块红加两块琥珀，
 *          **比第一版更花**。问题从来不是「用什么颜色」，是「填了多少面积」。
 *   现在：颜色只出现在**左侧 4px 色条**与**状态文字**上，卡片本体一律中性。
 *
 * 这样一来，饱和色的总面积从屏幕的 ~65% 压到 ~2%，而语义一点没丢：
 * 扫一眼左条的颜色就知道哪几笔要现在处理。视觉重量重新回到首页那个
 * 「本月支出」大数字身上 —— 那才是这个应用存在的理由。
 *
 * 另一条硬约束：**饱和色面积必须与「必须现在处理的事」的多少成正比。**
 * 满色卡片方案在待办只有 1 笔时看着还行，积到 5 笔就变成一堵色墙，
 * 而待办积起来恰恰是最常见的状态。中性卡 + 色条在 1 笔和 20 笔时都成立。
 */
import { daysUntil } from './dates';

export type Urgency = 'overdue' | 'due' | 'later';

/** 迟于还款日 = overdue；0–1 天 = due；更远 = later。 */
export function urgencyOf(date: string): Urgency {
  const days = daysUntil(date);

  if (days < 0) return 'overdue';
  if (days <= 1) return 'due';
  return 'later';
}

export function urgencyLabel(date: string): string {
  const days = daysUntil(date);

  if (days === 0) return '今天到期';
  if (days < 0) return `已逾期 ${-days} 天`;
  return `还有 ${days} 天`;
}

/**
 * 没有还款日的（现金、储蓄卡）按 later 处理。
 *
 * 不另设一个「不适用」档：那只是把「无需关注」表达得更复杂，
 * 而且会让后面每一个 `Record<Urgency, …>` 都多一个分支要填。
 */
export function urgencyOfOptional(date: string | null): Urgency {
  return date === null ? 'later' : urgencyOf(date);
}

/**
 * 卡片本体。三档**完全一致** —— 底色不参与表达紧急度，这是刻意的。
 * 写在映射里而不是直接写类名，是为了让「卡片长什么样」只有一处定义，
 * 待办卡与待还行不会各自漂移。
 */
export const URGENCY_CARD: Record<Urgency, string> = {
  overdue: 'bg-surface text-ink',
  due: 'bg-surface text-ink',
  later: 'bg-surface text-ink',
};

/**
 * 左侧 4px 色条 —— 紧急度**唯一**的着色位置。
 *
 * later 用 --line（灰），也就是「视觉上等于没有色条」，
 * 这样只有真正需要注意的条目才"亮"起来，中性条目自然沉下去。
 */
export const URGENCY_BAR: Record<Urgency, string> = {
  overdue: 'bg-danger',
  due: 'bg-accent',
  later: 'bg-line',
};

/**
 * 日期 / 状态那一行的颜色。
 *
 * 这里用 `-text` 后缀的令牌，而不是 `--danger` / `--accent` 本身：
 * 后者在浅色底上只有 2–4:1，当文字用不达标（见 tokens.css 的分色说明）。
 */
export const URGENCY_META: Record<Urgency, string> = {
  overdue: 'text-danger-text',
  due: 'text-accent-text',
  later: 'text-ink-muted',
};

/**
 * 卡片内的动作按钮。
 *
 * 底色既然统一成中性，按钮也就只有一种形态了：主按钮用主色填充 ——
 * 它现在是整页**唯一**的强色块，用户扫视时的落点从「一片红黄」收敛到
 * 「那个蓝按钮」，这才是动作该有的视觉优先级。
 */
export const URGENCY_ACTION = {
  primary: 'bg-primary-fill text-on-primary',
  ghost: 'text-ink-muted hover:bg-canvas hover:text-ink',
} as const;
