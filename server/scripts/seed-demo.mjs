/**
 * 演示数据种子 —— 用来在**不碰真实库**的前提下预览界面的真实观感。
 *
 *   SUENMONEY_DB_PATH=/tmp/suenmoney-demo.sqlite node scripts/seed-demo.mjs
 *
 * 为什么需要它：空库或者只有一两笔数据时，流水列表、报表饼图、计划进度条
 * 全都是空壳，根本判断不出排版、字号、对齐、留白是否成立。设计评审必须
 * 在有真实数据密度的情况下做，否则「看起来还行」和「一片糊」都看不出来。
 *
 * 这个脚本只写演示数据，**不参与生产**，也不该被 API 调用。
 */
import { DatabaseSync } from 'node:sqlite';

const B32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
function ulid() {
  let t = Date.now();
  let time = '';
  for (let i = 0; i < 10; i += 1) {
    time = B32[t % 32] + time;
    t = Math.floor(t / 32);
  }
  let rand = '';
  for (let i = 0; i < 16; i += 1) rand += B32[Math.floor(Math.random() * 32)];
  return time + rand;
}

const pad = (n) => String(n).padStart(2, '0');
const ymd = (y, m, d) => `${y}-${pad(m)}-${pad(d)}`;
const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
function addMonths(y, m, delta) {
  const t = m - 1 + delta;
  return [y + Math.floor(t / 12), (t % 12) + 1];
}

/** 账单周期：消费日 d ≤ 账单日 B → 本期；否则次期。与 domain/billing-cycle.ts 同规则。 */
function bill(spendDate, billingDay, repaymentDay) {
  const [y, m, d] = spendDate.split('-').map(Number);
  const [ty, tm] = d <= billingDay ? [y, m] : addMonths(y, m, 1);
  return {
    posting: ymd(ty, tm, Math.min(billingDay, daysInMonth(ty, tm))),
    repayment: ymd(ty, tm, Math.min(repaymentDay, daysInMonth(ty, tm))),
  };
}

const dbPath = process.env['SUENMONEY_DB_PATH'];
if (!dbPath) {
  console.error('必须显式指定 SUENMONEY_DB_PATH，避免误写真实库');
  process.exit(1);
}

const db = new DatabaseSync(dbPath);
db.exec('PRAGMA foreign_keys = ON');

const now = new Date().toISOString();

// ---------------------------------------------------------------------------
// 用户（由 user:add 脚本创建，这里只查出来用）
// ---------------------------------------------------------------------------
const users = db
  .prepare('SELECT id, username, display_name FROM users WHERE deleted_at IS NULL ORDER BY created_at')
  .all();
if (users.length < 2) {
  console.error('请先用 user:add 创建两个账号再跑种子');
  process.exit(1);
}
const [me, partner] = users;

// ---------------------------------------------------------------------------
// 支付方式
// ---------------------------------------------------------------------------
const pm = {};
function ensurePm(name, type, billingDay, repaymentDay, sort) {
  const found = db
    .prepare('SELECT id FROM payment_methods WHERE name = ? AND deleted_at IS NULL')
    .get(name);
  if (found) {
    pm[name] = found.id;
    return;
  }
  const id = ulid();
  db.prepare(
    `INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, is_enabled, sort_order,
                                  created_at, updated_at, deleted_at, rev, device_id)
     VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, NULL, 1, NULL)`,
  ).run(id, name, type, billingDay, repaymentDay, sort, now, now);
  pm[name] = id;
}

ensurePm('现金', 'cash', null, null, 1);
ensurePm('招行信用卡', 'credit', 10, 28, 2);
ensurePm('花呗', 'credit', 1, 9, 3);
ensurePm('工资卡', 'cash', null, null, 4);

// ---------------------------------------------------------------------------
// 分类（两级，找不到就建）
// ---------------------------------------------------------------------------
const cat = {};
function ensureCat(path) {
  if (cat[path]) return cat[path];
  const [parentName, childName] = path.split('/');
  let parent = db
    .prepare("SELECT id FROM categories WHERE name = ? AND depth = 1 AND deleted_at IS NULL")
    .get(parentName);
  if (!parent) {
    const id = ulid();
    db.prepare(
      `INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                               created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, NULL, ?, 1, '', '', 0, 1, ?, ?, NULL, 1, NULL)`,
    ).run(id, parentName, now, now);
    parent = { id };
  }
  if (childName === undefined) {
    cat[path] = parent.id;
    return parent.id;
  }
  let child = db
    .prepare(
      'SELECT id FROM categories WHERE name = ? AND parent_id = ? AND deleted_at IS NULL',
    )
    .get(childName, parent.id);
  if (!child) {
    const id = ulid();
    db.prepare(
      `INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                               created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, ?, ?, 2, '', '', 0, 1, ?, ?, NULL, 1, NULL)`,
    ).run(id, parent.id, childName, now, now);
    child = { id };
  }
  cat[path] = child.id;
  return child.id;
}

const OWNERS = [me.id, partner.id];

// ---------------------------------------------------------------------------
// 支出记录
// ---------------------------------------------------------------------------
// [消费日, 分类路径, 金额(元), 支付方式, 备注, 记录人 0/1]
const SPENDINGS = [
  ['2026-08-02', '餐饮/买菜', 186.5, '招行信用卡', '超市周采', 1],
  ['2026-08-03', '交通/地铁', 6, '现金', '', 1],
  ['2026-08-05', '餐饮/外卖', 43.8, '招行信用卡', '午饭', 0],
  ['2026-08-07', '购物/日用', 129, '现金', '洗衣液、纸巾', 1],
  ['2026-08-08', '餐饮/下馆子', 326, '招行信用卡', '和朋友聚餐', 0],
  ['2026-08-11', '交通/打车', 42, '花呗', '加班打车', 0],
  ['2026-08-13', '医疗/药品', 88, '现金', '感冒药', 1],
  ['2026-08-15', '餐饮/外卖', 39.2, '招行信用卡', '晚饭', 0],
  ['2026-08-16', '娱乐/订阅', 15, '花呗', '音乐会员', 0],
  ['2026-08-18', '购物/数码', 199, '招行信用卡', '移动电源', 1],
  ['2026-08-20', '居住/水电燃气', 213.6, '现金', '7 月账单', 0],
  ['2026-08-22', '餐饮/买菜', 201.4, '招行信用卡', '周末采购', 1],
  ['2026-08-24', '交通/地铁', 12, '现金', '', 1],
  ['2026-08-26', '餐饮/外卖', 56.8, '花呗', '加班晚饭', 0],
  ['2026-08-28', '购物/日用', 76, '现金', '收纳盒', 1],
  ['2026-08-30', '餐饮/下馆子', 187, '招行信用卡', '', 0],

  ['2026-09-01', '餐饮/外卖', 42, '招行信用卡', '午饭', 0],
  ['2026-09-02', '交通/打车', 36, '花呗', '', 1],
  ['2026-09-03', '餐饮/买菜', 173.8, '招行信用卡', '超市', 1],
  ['2026-09-05', '居住/水电燃气', 189.4, '现金', '8 月账单', 0],
  ['2026-09-06', '购物/日用', 99, '招行信用卡', '洗发水、牙膏', 0],
  ['2026-09-08', '餐饮/外卖', 46.6, '招行信用卡', '午饭', 1],
  ['2026-09-09', '娱乐/订阅', 28, '花呗', '视频会员年付分摊', 0],
  ['2026-09-11', '交通/地铁', 8, '现金', '', 1],
  ['2026-09-12', '餐饮/下馆子', 264, '招行信用卡', '周末家庭聚餐', 0],
  ['2026-09-14', '医疗/药品', 156, '现金', '体检自付部分', 1],
  ['2026-09-15', '餐饮/买菜', 220.5, '招行信用卡', '周末采购', 1],
  ['2026-09-17', '购物/数码', 89, '花呗', '数据线、转接头', 0],
  ['2026-09-19', '餐饮/外卖', 51.2, '招行信用卡', '', 0],
  ['2026-09-20', '购物/日用', -129, '招行信用卡', '退货退款', 0],
  ['2026-09-21', '交通/打车', 53, '招行信用卡', '机场往返', 1],
  ['2026-09-22', '娱乐/订阅', 15, '花呗', '音乐会员', 0],
  ['2026-09-23', '餐饮/买菜', 167.2, '现金', '', 1],
  ['2026-09-24', '购物/日用', 118, '招行信用卡', '厨房用品', 0],
  ['2026-09-25', '餐饮/下馆子', 218, '招行信用卡', '', 1],
  ['2026-09-26', '交通/地铁', 6, '现金', '', 0],
  ['2026-09-26', '餐饮/外卖', 38.8, '招行信用卡', '晚饭', 0],
  ['2026-09-27', '购物/日用', 64, '花呗', '纸巾囤货', 1],
];

function insertExpense({ date, categoryPath, yuan, pmName, note, owner, source, planId, periodSeq }) {
  const method = db
    .prepare('SELECT type, billing_day, repayment_day FROM payment_methods WHERE id = ?')
    .get(pm[pmName]);
  const cycle =
    method.type === 'credit'
      ? bill(date, method.billing_day, method.repayment_day)
      : { posting: date, repayment: date };

  const id = ulid();
  db.prepare(
    `INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                           spend_date, posting_date, repayment_date, note, source,
                           plan_id, plan_period_seq, created_at, updated_at, deleted_at, rev, device_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 1, NULL)`,
  ).run(
    id,
    OWNERS[owner],
    Math.round(yuan * 100),
    ensureCat(categoryPath),
    pm[pmName],
    date,
    cycle.posting,
    cycle.repayment,
    note,
    source ?? 'manual',
    planId ?? null,
    periodSeq ?? null,
    now,
    now,
  );
  return id;
}

for (const [date, path, yuan, pmName, note, owner] of SPENDINGS) {
  insertExpense({ date, categoryPath: path, yuan, pmName, note, owner });
}

// ---------------------------------------------------------------------------
// 计划 + 待办
// ---------------------------------------------------------------------------
function insertPlan(cfg) {
  const planId = ulid();
  db.prepare(
    `INSERT INTO plans (id, owner_id, name, category_id, payment_method_id, amount_cents,
                        total_amount_cents, purchase_date, first_due_date,
                        remind_days_before, auto_post, source, state, note,
                        created_at, updated_at, deleted_at, rev, device_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, NULL, 1, NULL)`,
  ).run(
    planId,
    OWNERS[cfg.owner],
    cfg.name,
    ensureCat(cfg.categoryPath),
    pm[cfg.pmName],
    cfg.amountCents,
    cfg.totalCents ?? null,
    cfg.purchaseDate ?? null,
    cfg.firstDue,
    cfg.remindDays,
    cfg.autoPost ?? 0,
    cfg.source,
    cfg.note ?? '',
    now,
    now,
  );

  const [fy, fm, fd] = cfg.firstDue.split('-').map(Number);
  const method = db
    .prepare('SELECT type, billing_day, repayment_day FROM payment_methods WHERE id = ?')
    .get(pm[cfg.pmName]);

  return { planId, fy, fm, fd, method, cfg };
}

function generateTodos(plan) {
  const { planId, fy, fm, fd, cfg } = plan;
  for (let k = 0; k < cfg.periods; k += 1) {
    const [y, m] = addMonths(fy, fm, k);
    const day = Math.min(fd, daysInMonth(y, m));
    const repayment = ymd(y, m, day);
    // 还款日往前推 remindDays 天（可能跨月）
    const t0 = new Date(Date.UTC(y, m - 1, day));
    t0.setUTCDate(t0.getUTCDate() - cfg.remindDays);
    const remind = t0.toISOString().slice(0, 10);

    // 分期走信用卡：入账日 = 该期账单日所在月的账单日
    const posting =
      plan.method.type === 'credit'
        ? ymd(y, m, Math.min(plan.method.billing_day, daysInMonth(y, m)))
        : repayment;

    const todoId = ulid();
    db.prepare(
      `INSERT INTO plan_todos (id, plan_id, period_seq, amount_cents, posting_date, repayment_date,
                               remind_date, status, posted_date, confirmed_by, confirmed_at,
                               expense_id, created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, ?, ?, NULL, 1, NULL)`,
    ).run(todoId, planId, k + 1, cfg.amountCents, posting, repayment, remind, 'pending', now, now);

    if (k + 1 <= cfg.confirmFirst) {
      // 先入支出记录，再回填待办 —— 顺序不能反，待办确认态要求 expense_id 非空
      const expenseId = insertExpense({
        date: repayment,
        categoryPath: cfg.categoryPath,
        yuan: cfg.amountCents / 100,
        pmName: cfg.pmName,
        note: `${cfg.name} 第 ${k + 1} 期`,
        owner: cfg.owner,
        source: 'plan',
        planId,
        periodSeq: k + 1,
      });
      db.prepare(
        `UPDATE plan_todos
            SET status = 'confirmed', posted_date = ?, confirmed_by = ?, confirmed_at = ?,
                expense_id = ?, updated_at = ?
          WHERE id = ?`,
      ).run(repayment, OWNERS[cfg.owner], now, expenseId, now, todoId);
    }
  }
}

generateTodos(
  insertPlan({
    owner: 0,
    name: '房贷',
    categoryPath: '居住/房贷',
    pmName: '工资卡',
    amountCents: 528000, // 5280 元/月
    firstDue: '2026-01-20',
    periods: 12,
    remindDays: 5,
    confirmFirst: 8, // 1–8 月已还，9 月逾期未确认，10–12 月未到期
    source: 'manual',
    note: '等额本息，LPR 每季度复核一次',
  }),
);

generateTodos(
  insertPlan({
    owner: 1,
    name: '京东分期 · iPhone',
    categoryPath: '购物/数码',
    pmName: '招行信用卡',
    amountCents: 50000, // 500 元/期
    totalCents: 600000, // 原价 6000 元
    purchaseDate: '2026-07-05',
    firstDue: '2026-08-28',
    periods: 12,
    remindDays: 3,
    confirmFirst: 1,
    autoPost: 1,
    source: 'installment',
    note: '12 期免息',
  }),
);

generateTodos(
  insertPlan({
    owner: 0,
    name: '健身年卡分期',
    categoryPath: '娱乐/健身',
    pmName: '花呗',
    amountCents: 20000, // 200 元/期
    totalCents: 240000, // 原价 2400 元
    purchaseDate: '2026-06-15',
    firstDue: '2026-07-09',
    periods: 12,
    remindDays: 3,
    confirmFirst: 2,
    source: 'installment',
    note: '12 期免息',
  }),
);

// ---------------------------------------------------------------------------
const summary = {
  users: db.prepare('SELECT COUNT(*) n FROM users').get().n,
  categories: db.prepare('SELECT COUNT(*) n FROM categories').get().n,
  payment_methods: db.prepare('SELECT COUNT(*) n FROM payment_methods').get().n,
  expenses: db.prepare('SELECT COUNT(*) n FROM expenses').get().n,
  plans: db.prepare('SELECT COUNT(*) n FROM plans').get().n,
  plan_todos: db.prepare('SELECT COUNT(*) n FROM plan_todos').get().n,
};
const byMonth = db
  .prepare(
    `SELECT substr(repayment_date,1,7) ym, COUNT(*) n, printf('%.2f', SUM(amount_cents)/100.0) yuan
       FROM expenses WHERE deleted_at IS NULL GROUP BY ym ORDER BY ym`,
  )
  .all();

console.log('演示数据已写入', dbPath);
console.log(summary);
console.log('按还款日归属月份的合计：');
for (const r of byMonth) console.log(`  ${r.ym}  ${r.n} 笔  ¥${r.yuan}`);

db.close();
