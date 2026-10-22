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
/**
 * 后缀必须写全（`./dates.ts` 而不是 `./dates`）。
 *
 * 这是 `utils/` 里唯一一个引用别的 util 的模块，而它因此**曾经是唯一
 * 没法跑单元测试的 util**：`npm --prefix web test` 走的是 Node 的类型剥离，
 * 不做无后缀解析，`./dates` 会直接 `ERR_MODULE_NOT_FOUND`。
 * 于是「三档紧急度的边界」只能靠肉眼 —— 而它错了界面不报错，只是颜色不对。
 *
 * tsconfig 已开 `allowImportingTsExtensions`，Vite 与 vue-tsc 都认这个写法，
 * 所以这是一行没有副作用的改动。**utils 之间互相引用时请照此写全后缀。**
 */
import { daysUntil } from './dates.ts';

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

/* ==========================================================================
   提醒容器上的那一个箭头（`A25` / §6.5 三·补）
   --------------------------------------------------------------------------
   紧急度在这套界面里由**两样不同的东西**分别表达，别混：

     · **这一个箭头（一个染色的三角）** —— 回答「**这叠里有没有要你动手的**」。
       它是一个三元的、稳定的属性，收起态就能看见，不用展开。
     · **每一条的紧急度文字 + 它的颜色** —— 回答「**这一条多急**」。
       它随日期连续变化，只有展开后才需要知道。

   前一版把逐条紧急度提到收起态（每条前面一个彩色圆点），结果是
   **用「展开后才看得懂的东西」去打扰还没展开的人** —— 而且圆点一多，
   整列看起来像一串标签，收起态反而更吵。

   注意「中性」是**一个合法取值**，不是「漏了没画」：自动入账的那一叠
   确实不需要你动手，箭头就该沉下去。图例里仍然要给它画一个可见的箭头，
   否则看图例的人会以为少了一格。
   ========================================================================== */

export type ReminderTone = 'none' | 'manual' | 'late';

/** 箭头颜色。与列表里的文字色同一套令牌，不另开色板。 */
export const REMINDER_CHEV: Record<ReminderTone, string> = {
  none: 'text-ink-muted',
  manual: 'text-accent-text',
  late: 'text-danger-text',
};

/**
 * 由一叠提醒推出箭头的档位。**逾期优先于「需手动」** ——
 * 一叠里只要有一条逾期，这个箭头就该是红的：
 * 它回答的是「要不要现在处理」，而逾期是这里面唯一不容推迟的。
 *
 * 参数写成结构化类型而不是 `PlanTodo`：这个判断只用到两个字段，
 * 允许调用方（以及测试）直接传一个字面量，不必凑齐整个待办对象。
 */
export function reminderToneOf(
  todos: readonly { willAutoPost: boolean; repaymentDate: string }[],
): ReminderTone {
  let tone: ReminderTone = 'none';

  for (const todo of todos) {
    if (urgencyOf(todo.repaymentDate) === 'overdue') return 'late';
    // 不会自动入账 = 必须由人做决定 = 需要动手
    if (!todo.willAutoPost) tone = 'manual';
  }

  return tone;
}

/** 一行提醒之所以不能自动完成的原因，直接当状态词用（见 §6.2.二「只说是什么」）。 */
export function reminderStateLabel(willAutoPost: boolean): string {
  return willAutoPost ? '自动入账' : '需手动入账';
}

/**
 * 这一条现在该给哪个动作。**判据是 `willAutoPost` 本身，
 * 不是「计划有没有开自动入账」** —— 两者的差别见 repo 里的注释。
 */
export type ReminderAction = 'ack' | 'decide';

export function reminderActionOf(willAutoPost: boolean): ReminderAction {
  return willAutoPost ? 'ack' : 'decide';
}

/** 主操作按钮的文案。`ack` 那一类只有「确认」一个，所以它旁边不可能出现「入账」被读混。 */
export function reminderPrimaryLabel(action: ReminderAction): string {
  return action === 'ack' ? '确认' : '入账';
}

/**
 * 一条提醒被处理掉了 —— 三个动作的合集。
 *
 * 单独定义在 utils 里而不是组件里：`<script setup>` 不能有具名导出，
 * 而父组件（提醒条）需要这个类型来渲染「撤销」那一条。
 *
 * 注意 `ack` **不可撤销**（没有 un-ack 的端点），这不是疏漏：
 * 它不产生任何账目，误点最坏的结果只是这条提醒今天不再出现，
 * 而到还款日它照旧自动入账 —— 没有任何东西需要被「撤回来」。
 * `confirm` / `skip` 都会改变账目，两者都可撤销（`revert` / `restore`）。
 */
export type ReminderDone = 'ack' | 'confirm' | 'skip';



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
