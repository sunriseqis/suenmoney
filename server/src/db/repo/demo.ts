/**
 * 演示数据 —— 「重置演示数据」（危险区）唯一的数据来源。
 *
 * ## 为什么它不在路由里
 *
 * 它要写五张表、还要跨表回填外键（先落支出、再回来把 `expense_id` 写进待办），
 * 是一段真正的领域逻辑。塞进路由会让「所有写入都走 `db/sync.ts`」这条规则
 * 在**最长的一条写入路径**上失去保护。
 *
 * ## 为什么日期是**相对今天**算的，而不是写死的
 *
 * 原先的 `server/scripts/seed-demo.mjs` 写死 2026-08 / 2026-09。
 * 那是一个只在开发机上跑一次的脚本，写死没问题；而「重置演示数据」是
 * **界面上一个能按的按钮** —— 写死的话，第二年按下去会长出「去年的数据」，
 * 用户看到的是「演示数据坏了」。
 * 所以这里只保留**相对关系**（上一月 / 本月 / 往前两个月 …），日期现算。
 *
 * `today` 由**调用方传进来**，服务端从不自己推算业务日期
 * （见 `config.ts` 末尾那段说明）—— 演示数据也没有例外。
 *
 * ## 为什么返回值里有 id 清单
 *
 * 「重置演示数据」的安全前提是「库里现在只有演示数据」，而判断依据就是
 * 上一次种子留下的 id 清单。所以这个返回值不是可选信息，
 * 它是**下一次调用的前置条件**（见 `maintenance.ts` 的 `assertDemoOnly`）。
 *
 * ## 与旧脚本的差异（刻意的）
 *
 * `scripts/seed-demo.mjs` 直接 `INSERT` 灌表，跑在开发机上、跑完即弃；
 * 这里是**产品里的一个功能**，所以每一行都必须走 `recordChange` ——
 * 否则其他设备永远同步不到，而且不报错。
 */
import type { DatabaseSync, SQLInputValue } from 'node:sqlite';

import {
  clampDay,
  computeRemindDate,
  generatePeriodDates,
  monthOf,
  resolveExpenseDates,
  resolvePostingDate,
  shiftMonthString,
  toDateString,
  type PaymentCycle,
} from '../../domain/billing-cycle.ts';
import { conflict } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { recordChange, type EntityType } from '../sync.ts';

/** 一行的列 → 值。`null` 是合法的（可空列），`undefined` 在本文件里一律按 `null` 落库。 */
type Row = Record<string, SQLInputValue>;

export interface DemoCounts {
  expenses: number;
  plans: number;
  planTodos: number;
}

export interface DemoSeedResult {
  /** 这次种子**新建**的账目类实体的 id —— 下一次重置的准入依据 */
  ids: string[];
  counts: DemoCounts;
}

interface Context {
  db: DatabaseSync;
  actorId: string;
  /** 两个记录人；库里只有一个账号时两个位置指向同一个人 */
  owners: readonly [string, string];
  now: string;
  /** 本月 'YYYY-MM' —— 所有日期都相对它算 */
  cur: string;
  /** 新建的账目类 id（配置不算），下次重置的准入依据 */
  ids: string[];
  counts: DemoCounts;
}

type Tracked = 'expenses' | 'plans' | 'planTodos';

// ---------------------------------------------------------------------------
// 写入原语
// ---------------------------------------------------------------------------

/**
 * 插一行，并**通过 `db/sync.ts` 记录变更**。
 *
 * 这里没有 `ON CONFLICT`：种子只往里加新 id，不会覆盖已有行。
 * 需要「有就用、没有就建」的是配置（分类 / 支付方式），
 * 那两个各有自己的 `ensureXxx`，会先查再插。
 */
function insert(ctx: Context, table: string, entity: EntityType, row: Row): void {
  const columns = Object.keys(row);
  ctx.db
    .prepare(
      `INSERT INTO ${table} (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
    )
    .run(...columns.map((column) => row[column] ?? null));

  recordChange(ctx.db, {
    entityType: entity,
    entityId: String(row['id']),
    op: 'upsert',
    actorId: ctx.actorId,
    payload: row,
    deviceId: null,
  });
}

/** 新建一个账目类实体：记 id、计数。两件事永远一起发生，所以合成一个函数。 */
function track(ctx: Context, kind: Tracked): string {
  const id = ulid();
  ctx.ids.push(id);
  ctx.counts[kind] += 1;
  return id;
}

// ---------------------------------------------------------------------------
// 配置：有就用、没有就建
// ---------------------------------------------------------------------------

function ensurePaymentMethod(
  ctx: Context,
  name: string,
  type: 'cash' | 'credit',
  billingDay: number | null,
  repaymentDay: number | null,
  sort: number,
): string {
  const found = ctx.db
    .prepare('SELECT id FROM payment_methods WHERE name = ? AND deleted_at IS NULL')
    .get(name) as { id: string } | undefined;
  if (found !== undefined) return found.id;

  const id = ulid();
  insert(ctx, 'payment_methods', 'payment_method', {
    id,
    name,
    type,
    billing_day: billingDay,
    repayment_day: repaymentDay,
    is_enabled: 1,
    sort_order: sort,
    created_at: ctx.now,
    updated_at: ctx.now,
    deleted_at: null,
    rev: 1,
    device_id: null,
  });
  return id;
}

/**
 * `path` 形如 `'餐饮/买菜'` 或 `'居住/房贷'`。
 *
 * **二级必须挂在同名的一级下**：分类是两级树，`depth` 与 `parent_id` 要配套。
 * 只写 `depth = 2` 而 `parent_id` 落空会长出一个孤儿节点 ——
 * 而它在界面上表现为「一级二级都不出现」，最难排查。
 */
function ensureCategory(ctx: Context, path: string): string {
  const [parentName, childName] = path.split('/') as [string, string | undefined];

  let parent = ctx.db
    .prepare('SELECT id FROM categories WHERE name = ? AND depth = 1 AND deleted_at IS NULL')
    .get(parentName) as { id: string } | undefined;

  if (parent === undefined) {
    const id = ulid();
    insert(ctx, 'categories', 'category', {
      id,
      parent_id: null,
      name: parentName,
      depth: 1,
      icon: '',
      color: '',
      sort_order: 0,
      is_enabled: 1,
      created_at: ctx.now,
      updated_at: ctx.now,
      deleted_at: null,
      rev: 1,
      device_id: null,
    });
    parent = { id };
  }

  if (childName === undefined || childName === '') return parent.id;

  const child = ctx.db
    .prepare('SELECT id FROM categories WHERE name = ? AND parent_id = ? AND deleted_at IS NULL')
    .get(childName, parent.id) as { id: string } | undefined;
  if (child !== undefined) return child.id;

  const id = ulid();
  insert(ctx, 'categories', 'category', {
    id,
    parent_id: parent.id,
    name: childName,
    depth: 2,
    icon: '',
    color: '',
    sort_order: 0,
    is_enabled: 1,
    created_at: ctx.now,
    updated_at: ctx.now,
    deleted_at: null,
    rev: 1,
    device_id: null,
  });
  return id;
}

// ---------------------------------------------------------------------------
// 日期工具（相对本月）
// ---------------------------------------------------------------------------

/** 本月偏移 `delta` 个月里的第 `day` 天；该月没有这一天就取月末。 */
function dayIn(ctx: Context, delta: number, day: number): string {
  const month = shiftMonthString(ctx.cur, delta);
  const year = Number(month.slice(0, 4));
  const monthNumber = Number(month.slice(5));
  return toDateString(year, monthNumber, clampDay(year, monthNumber, day));
}

function cycleOf(ctx: Context, paymentMethodId: string): PaymentCycle {
  const row = ctx.db
    .prepare('SELECT type, billing_day, repayment_day FROM payment_methods WHERE id = ?')
    .get(paymentMethodId) as {
    type: string;
    billing_day: number | null;
    repayment_day: number | null;
  };

  if (row.type !== 'credit') return { type: 'cash' };
  if (row.billing_day === null || row.repayment_day === null) {
    throw conflict('演示数据依赖的信用卡缺少账单日 / 还款日，无法生成周期');
  }
  return { type: 'credit', billingDay: row.billing_day, repaymentDay: row.repayment_day };
}

// ---------------------------------------------------------------------------
// 支出
// ---------------------------------------------------------------------------

interface ExpenseInput {
  spendDate: string;
  categoryPath: string;
  yuan: number;
  paymentMethod: string;
  note: string;
  owner: 0 | 1;
  plan?: { id: string; periodSeq: number };
}

function insertExpense(ctx: Context, methods: Record<string, string>, input: ExpenseInput): string {
  const paymentMethodId = methods[input.paymentMethod];
  if (paymentMethodId === undefined) {
    throw conflict(`演示数据引用了未创建的支付方式：${input.paymentMethod}`);
  }

  const id = track(ctx, 'expenses');
  const cycle = cycleOf(ctx, paymentMethodId);

  // 手动记账：消费日 → 入账日 / 还款日，走全站同一套账单周期规则。
  // 计划生成的支出：`spend_date` 记的就是还款日（这笔钱是「到那天要付」的），
  // 入账日则由「还款日落在账单周期的哪一侧」反推 —— `resolvePostingDate`。
  const dates =
    input.plan === undefined
      ? resolveExpenseDates(input.spendDate, cycle)
      : {
          postingDate: resolvePostingDate(input.spendDate, cycle),
          repaymentDate: input.spendDate,
        };

  insert(ctx, 'expenses', 'expense', {
    id,
    owner_id: ctx.owners[input.owner],
    amount_cents: Math.round(input.yuan * 100),
    category_id: ensureCategory(ctx, input.categoryPath),
    payment_method_id: paymentMethodId,
    spend_date: input.spendDate,
    posting_date: dates.postingDate,
    repayment_date: dates.repaymentDate,
    note: input.note,
    source: input.plan === undefined ? 'manual' : 'plan',
    plan_id: input.plan?.id ?? null,
    plan_period_seq: input.plan?.periodSeq ?? null,
    created_at: ctx.now,
    updated_at: ctx.now,
    deleted_at: null,
    rev: 1,
    device_id: null,
  });

  return id;
}

/**
 * [月份偏移, 日, 分类路径, 金额(元), 支付方式, 备注, 记录人]
 *
 * 留空的备注写 `''`（不是 `null`）：`expenses.note` 是 `NOT NULL DEFAULT ''`。
 * 负数金额是退款，界面按支出处理 —— 报表里它自然把当月合计减回去。
 */
const SPENDINGS: ReadonlyArray<
  readonly [number, number, string, number, string, string, 0 | 1]
> = [
  [-1, 2, '餐饮/买菜', 186.5, '招行信用卡', '超市周采', 1],
  [-1, 3, '交通/地铁', 6, '现金', '', 1],
  [-1, 5, '餐饮/外卖', 43.8, '招行信用卡', '午饭', 0],
  [-1, 7, '购物/日用', 129, '现金', '洗衣液、纸巾', 1],
  [-1, 8, '餐饮/下馆子', 326, '招行信用卡', '和朋友聚餐', 0],
  [-1, 11, '交通/打车', 42, '花呗', '加班打车', 0],
  [-1, 13, '医疗/药品', 88, '现金', '感冒药', 1],
  [-1, 15, '餐饮/外卖', 39.2, '招行信用卡', '晚饭', 0],
  [-1, 16, '娱乐/订阅', 15, '花呗', '音乐会员', 0],
  [-1, 18, '购物/数码', 199, '招行信用卡', '移动电源', 1],
  [-1, 20, '居住/水电燃气', 213.6, '现金', '上月账单', 0],
  [-1, 22, '餐饮/买菜', 201.4, '招行信用卡', '周末采购', 1],
  [-1, 24, '交通/地铁', 12, '现金', '', 1],
  [-1, 26, '餐饮/外卖', 56.8, '花呗', '加班晚饭', 0],
  [-1, 28, '购物/日用', 76, '现金', '收纳盒', 1],
  [-1, 30, '餐饮/下馆子', 187, '招行信用卡', '', 0],

  [0, 1, '餐饮/外卖', 42, '招行信用卡', '午饭', 0],
  [0, 2, '交通/打车', 36, '花呗', '', 1],
  [0, 3, '餐饮/买菜', 173.8, '招行信用卡', '超市', 1],
  [0, 5, '居住/水电燃气', 189.4, '现金', '本月账单', 0],
  [0, 6, '购物/日用', 99, '招行信用卡', '洗发水、牙膏', 0],
  [0, 8, '餐饮/外卖', 46.6, '招行信用卡', '午饭', 1],
  [0, 9, '娱乐/订阅', 28, '花呗', '视频会员年付分摊', 0],
  [0, 11, '交通/地铁', 8, '现金', '', 1],
  [0, 12, '餐饮/下馆子', 264, '招行信用卡', '周末家庭聚餐', 0],
  [0, 14, '医疗/药品', 156, '现金', '体检自付部分', 1],
  [0, 15, '餐饮/买菜', 220.5, '招行信用卡', '周末采购', 1],
  [0, 17, '购物/数码', 89, '花呗', '数据线、转接头', 0],
  [0, 19, '餐饮/外卖', 51.2, '招行信用卡', '', 0],
  [0, 20, '购物/日用', -129, '招行信用卡', '退货退款', 0],
  [0, 21, '交通/打车', 53, '招行信用卡', '机场往返', 1],
  [0, 22, '娱乐/订阅', 15, '花呗', '音乐会员', 0],
  [0, 23, '餐饮/买菜', 167.2, '现金', '', 1],
  [0, 24, '购物/日用', 118, '招行信用卡', '厨房用品', 0],
  [0, 25, '餐饮/下馆子', 218, '招行信用卡', '', 1],
  [0, 26, '交通/地铁', 6, '现金', '', 0],
  [0, 26, '餐饮/外卖', 38.8, '招行信用卡', '晚饭', 0],
  [0, 27, '购物/日用', 64, '花呗', '纸巾囤货', 1],
];

// ---------------------------------------------------------------------------
// 计划与待办
// ---------------------------------------------------------------------------

interface PlanInput {
  owner: 0 | 1;
  name: string;
  categoryPath: string;
  paymentMethod: string;
  amountCents: number;
  totalCents: number | null;
  /** 购买日：相对本月偏移几个月 + 几号；null = 不写 */
  purchase: readonly [number, number] | null;
  firstDue: readonly [number, number];
  periods: number;
  remindDays: number;
  /** 前 N 期已经入账；剩下的留 `pending`，最早的那一期就成了「该处理了」 */
  confirmFirst: number;
  autoPost: 0 | 1;
  source: 'manual' | 'installment';
  note: string;
}

/**
 * 计划 + 逐期待办。**顺序不能反**：
 * 待办的确认态要求 `expense_id` 非空，所以必须先落支出、再写那一行。
 */
function insertPlan(ctx: Context, methods: Record<string, string>, input: PlanInput): string {
  const paymentMethodId = methods[input.paymentMethod];
  if (paymentMethodId === undefined) {
    throw conflict(`演示数据引用了未创建的支付方式：${input.paymentMethod}`);
  }

  const planId = track(ctx, 'plans');
  const firstDue = dayIn(ctx, input.firstDue[0], input.firstDue[1]);

  insert(ctx, 'plans', 'plan', {
    id: planId,
    owner_id: ctx.owners[input.owner],
    name: input.name,
    category_id: ensureCategory(ctx, input.categoryPath),
    payment_method_id: paymentMethodId,
    amount_cents: input.amountCents,
    total_amount_cents: input.totalCents,
    purchase_date: input.purchase === null ? null : dayIn(ctx, input.purchase[0], input.purchase[1]),
    first_due_date: firstDue,
    remind_days_before: input.remindDays,
    auto_post: input.autoPost,
    source: input.source,
    state: 'active',
    note: input.note,
    created_at: ctx.now,
    updated_at: ctx.now,
    deleted_at: null,
    rev: 1,
    device_id: null,
  });

  const cycle = cycleOf(ctx, paymentMethodId);

  generatePeriodDates(firstDue, input.periods).forEach((repaymentDate, index) => {
    const periodSeq = index + 1;
    const confirmed = periodSeq <= input.confirmFirst;

    const expenseId = confirmed
      ? insertExpense(ctx, methods, {
          spendDate: repaymentDate,
          categoryPath: input.categoryPath,
          yuan: input.amountCents / 100,
          paymentMethod: input.paymentMethod,
          note: `${input.name} 第 ${periodSeq} 期`,
          owner: input.owner,
          plan: { id: planId, periodSeq },
        })
      : null;

    insert(ctx, 'plan_todos', 'plan_todo', {
      id: track(ctx, 'planTodos'),
      plan_id: planId,
      period_seq: periodSeq,
      amount_cents: input.amountCents,
      posting_date: resolvePostingDate(repaymentDate, cycle),
      repayment_date: repaymentDate,
      remind_date: computeRemindDate(repaymentDate, input.remindDays),
      status: confirmed ? 'confirmed' : 'pending',
      posted_date: confirmed ? repaymentDate : null,
      confirmed_by: confirmed ? ctx.owners[input.owner] : null,
      confirmed_at: confirmed ? ctx.now : null,
      expense_id: expenseId,
      hold_auto_post: 0,
      ack_at: null,
      created_at: ctx.now,
      updated_at: ctx.now,
      deleted_at: null,
      rev: 1,
      device_id: null,
    });
  });

  return planId;
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

/**
 * 灌一份演示数据。
 *
 * 调用方（`maintenance.ts`）负责：先确认库里只有演示数据、先落一份存档、
 * 先软删掉旧的那一批。这里只管「建」，不管「清」——
 * 把重置的两半分在两个函数里，是为了让各自可读。
 */
export function seedDemoData(db: DatabaseSync, actorId: string, today: string): DemoSeedResult {
  const users = db
    .prepare('SELECT id FROM users WHERE deleted_at IS NULL ORDER BY created_at')
    .all() as Array<{ id: string }>;

  if (users.length === 0) {
    throw conflict('库里还没有任何账号。请先在「家庭与账号」里建好账号，再来灌演示数据。');
  }

  const first = users[0]!.id;
  const second = users[1]?.id ?? first;

  const ctx: Context = {
    db,
    actorId,
    owners: [first, second],
    now: new Date().toISOString(),
    cur: monthOf(today),
    ids: [],
    counts: { expenses: 0, plans: 0, planTodos: 0 },
  };

  const methods: Record<string, string> = {
    现金: ensurePaymentMethod(ctx, '现金', 'cash', null, null, 1),
    招行信用卡: ensurePaymentMethod(ctx, '招行信用卡', 'credit', 10, 28, 2),
    花呗: ensurePaymentMethod(ctx, '花呗', 'credit', 1, 9, 3),
    工资卡: ensurePaymentMethod(ctx, '工资卡', 'cash', null, null, 4),
  };

  for (const [delta, day, path, yuan, method, note, owner] of SPENDINGS) {
    insertExpense(ctx, methods, {
      spendDate: dayIn(ctx, delta, day),
      categoryPath: path,
      yuan,
      paymentMethod: method,
      note,
      owner,
    });
  }

  // 本年度 1 月 = 相对本月偏移 `1 - 当月` 个月
  const monthNumber = Number(ctx.cur.slice(5));

  // 房贷：本年度 1 月起 12 期，已经还到上个月 ——
  // 所以**本月那一期是逾期未确认**的，首页的「该处理了」一进来就有东西
  insertPlan(ctx, methods, {
    owner: 0,
    name: '房贷',
    categoryPath: '居住/房贷',
    paymentMethod: '工资卡',
    amountCents: 528_000,
    totalCents: null,
    purchase: null,
    firstDue: [1 - monthNumber, 20],
    periods: 12,
    remindDays: 5,
    confirmFirst: Math.max(0, monthNumber - 1),
    autoPost: 0,
    source: 'manual',
    note: '等额本息，LPR 每季度复核一次',
  });

  // 京东分期：上个月是第 1 期，本月第 2 期自动入账 —— 演示「自动入账」那一档
  insertPlan(ctx, methods, {
    owner: 1,
    name: '京东分期 · iPhone',
    categoryPath: '购物/数码',
    paymentMethod: '招行信用卡',
    amountCents: 50_000,
    totalCents: 600_000,
    purchase: [-2, 5],
    firstDue: [-1, 28],
    periods: 12,
    remindDays: 3,
    confirmFirst: 1,
    autoPost: 1,
    source: 'installment',
    note: '12 期免息',
  });

  // 健身年卡：两个月前开的卡，已还 2 期 —— 演示「需手动入账」那一档
  insertPlan(ctx, methods, {
    owner: 0,
    name: '健身年卡分期',
    categoryPath: '娱乐/健身',
    paymentMethod: '花呗',
    amountCents: 20_000,
    totalCents: 240_000,
    purchase: [-3, 15],
    firstDue: [-2, 9],
    periods: 12,
    remindDays: 3,
    confirmFirst: 2,
    autoPost: 0,
    source: 'installment',
    note: '12 期免息',
  });

  return { ids: [...ctx.ids], counts: { ...ctx.counts } };
}
