/**
 * 将 docss/ 下的 BeeCount 真实家庭账本导入到 SuenMoney SQLite 数据库中。
 *
 * 遵循用户裁决：
 * 1. 演示数据完全丢弃；
 * 2. 智能分类，提取真实 12 个一级分类与 46 个二级分类；
 * 3. 信用卡规则：账单日 10 号，还款日 29 号；
 * 4. 仅将 5 笔「杂项退款」作为负数支出导入（冲销），7 笔纯收入忽略；
 * 5. 记录人归属管理员 admin。
 */
import { copyFileSync, existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
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

const dbPath = resolve(process.env['SUENMONEY_DB_PATH'] ?? './data/suenmoney.sqlite');
const csvPath = resolve('../docss/beecount-家庭账本-20260928-215725.csv');

if (!existsSync(csvPath)) {
  console.error(`未找到账本文件：${csvPath}`);
  process.exit(1);
}

// 1. 备份当前库
if (existsSync(dbPath)) {
  const backupPath = resolve('./data/suenmoney-demo-backup.sqlite');
  copyFileSync(dbPath, backupPath);
  console.log(`已备份当前数据库至：${backupPath}`);
}

const db = new DatabaseSync(dbPath);
db.exec('PRAGMA foreign_keys = ON');

const now = new Date().toISOString();

// 查询 admin 用户
const adminUser = db.prepare("SELECT id, username FROM users WHERE username = 'admin'").get();
if (!adminUser) {
  console.error('未在数据库中找到 admin 用户，请先运行 user:add 创建 admin 用户！');
  process.exit(1);
}
const adminId = adminUser.id;

// 分类体系定义
const CATEGORY_DEFS = [
  {
    name: '餐饮美食',
    icon: 'utensils',
    color: '1',
    children: ['堂食外卖', '食材调料', '零食饮品', '奶茶甜品'],
  },
  {
    name: '生活日用',
    icon: 'package',
    color: '2',
    children: ['日用百货', '厨房用品', '清洁用品', '个护美妆', '其他杂项'],
  },
  {
    name: '母婴亲子',
    icon: 'baby',
    color: '3',
    children: ['奶粉辅食', '宝宝穿搭', '教娱玩具', '母婴用品'],
  },
  {
    name: '交通出行',
    icon: 'bus',
    color: '4',
    children: ['出行打车', '公交地铁'],
  },
  {
    name: '汽车相关',
    icon: 'car',
    color: '5',
    children: ['停车费用', '加油充电', '洗车保养', '车品配件', '车辆保险', '违章罚款'],
  },
  {
    name: '居家缴费',
    icon: 'zap',
    color: '6',
    children: ['水电燃气', '话费通讯', '物业缴费'],
  },
  {
    name: '医疗保健',
    icon: 'heart-pulse',
    color: '7',
    children: ['问诊就医', '药品保健', '疫苗体检', '医疗器械'],
  },
  {
    name: '服饰美容',
    icon: 'shirt',
    color: '8',
    children: ['服装鞋帽', '美妆个护', '美容护肤', '箱包配饰'],
  },
  {
    name: '数码家电',
    icon: 'laptop',
    color: '9',
    children: ['手机数码', '家用电器', '电脑配件', '会员服务'],
  },
  {
    name: '贷款还款',
    icon: 'landmark',
    color: '10',
    children: ['房屋贷款', '汽车贷款', '信用分期'],
  },
  {
    name: '人情往来',
    icon: 'gift',
    color: '11',
    children: ['孝敬长辈', '人情礼金', '婚庆开支', '其他花费'],
  },
  {
    name: '休闲娱乐',
    icon: 'gamepad-2',
    color: '12',
    children: ['游戏娱乐', '文娱活动', '旅行出游', '摄影写真'],
  },
];

// CSV 到两级分类的映射规则
const CATEGORY_MAP = {
  // 餐饮美食
  堂食外卖: { parent: '餐饮美食', child: '堂食外卖' },
  食材调料: { parent: '餐饮美食', child: '食材调料' },
  零食饮品: { parent: '餐饮美食', child: '零食饮品' },
  奶茶甜品: { parent: '餐饮美食', child: '奶茶甜品' },

  // 生活日用
  日用百货: { parent: '生活日用', child: '日用百货' },
  厨房用品: { parent: '生活日用', child: '厨房用品' },
  清洁用品: { parent: '生活日用', child: '清洁用品' },
  个护美妆: { parent: '生活日用', child: '个护美妆' },
  其他杂项: { parent: '生活日用', child: '其他杂项' },

  // 母婴亲子
  奶粉辅食: { parent: '母婴亲子', child: '奶粉辅食' },
  宝宝穿搭: { parent: '母婴亲子', child: '宝宝穿搭' },
  教娱玩具: { parent: '母婴亲子', child: '教娱玩具' },
  母婴用品: { parent: '母婴亲子', child: '母婴用品' },

  // 交通出行
  出行打车: { parent: '交通出行', child: '出行打车' },
  公交地铁: { parent: '交通出行', child: '公交地铁' },

  // 汽车相关
  停车费用: { parent: '汽车相关', child: '停车费用' },
  加油充电: { parent: '汽车相关', child: '加油充电' },
  洗车保养: { parent: '汽车相关', child: '洗车保养' },
  车品配件: { parent: '汽车相关', child: '车品配件' },
  车辆保险: { parent: '汽车相关', child: '车辆保险' },
  违章罚款: { parent: '汽车相关', child: '违章罚款' },

  // 居家缴费
  水电燃气: { parent: '居家缴费', child: '水电燃气' },
  话费通讯: { parent: '居家缴费', child: '话费通讯' },
  物业缴费: { parent: '居家缴费', child: '物业缴费' },

  // 医疗保健
  问诊就医: { parent: '医疗保健', child: '问诊就医' },
  药品保健: { parent: '医疗保健', child: '药品保健' },
  疫苗体检: { parent: '医疗保健', child: '疫苗体检' },
  医疗器械: { parent: '医疗保健', child: '医疗器械' },

  // 服饰美容
  服装鞋帽: { parent: '服饰美容', child: '服装鞋帽' },
  美妆个护: { parent: '服饰美容', child: '美妆个护' },
  美容护肤: { parent: '服饰美容', child: '美容护肤' },
  箱包配饰: { parent: '服饰美容', child: '箱包配饰' },

  // 数码家电
  手机数码: { parent: '数码家电', child: '手机数码' },
  家用电器: { parent: '数码家电', child: '家用电器' },
  电脑配件: { parent: '数码家电', child: '电脑配件' },
  会员服务: { parent: '数码家电', child: '会员服务' },

  // 贷款还款
  房屋贷款: { parent: '贷款还款', child: '房屋贷款' },
  汽车贷款: { parent: '贷款还款', child: '汽车贷款' },
  信用分期: { parent: '贷款还款', child: '信用分期' },

  // 人情往来
  孝敬长辈: { parent: '人情往来', child: '孝敬长辈' },
  人情礼金: { parent: '人情往来', child: '人情礼金' },
  婚庆开支: { parent: '人情往来', child: '婚庆开支' },
  其他花费: { parent: '人情往来', child: '其他花费' },

  // 休闲娱乐
  游戏娱乐: { parent: '休闲娱乐', child: '游戏娱乐' },
  文娱活动: { parent: '休闲娱乐', child: '文娱活动' },
  旅行出游: { parent: '休闲娱乐', child: '旅行出游' },
  摄影写真: { parent: '休闲娱乐', child: '摄影写真' },
};

// 支付方式定义
const PAYMENT_METHOD_DEFS = [
  { name: '银行卡', type: 'cash', billingDay: null, repaymentDay: null, sortOrder: 1 },
  { name: '信用卡', type: 'credit', billingDay: 10, repaymentDay: 29, sortOrder: 2 },
  { name: '微信', type: 'cash', billingDay: null, repaymentDay: null, sortOrder: 3 },
  { name: '支付宝', type: 'cash', billingDay: null, repaymentDay: null, sortOrder: 4 },
  { name: '现金', type: 'cash', billingDay: null, repaymentDay: null, sortOrder: 5 },
];

function daysInMonth(y, m) {
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

function resolveCreditDates(spendDate, billingDay, repaymentDay) {
  const [y, m, d] = spendDate.split('-').map(Number);
  let by, bm;
  if (d <= billingDay) {
    by = y;
    bm = m;
  } else {
    bm = m + 1;
    by = y;
    if (bm > 12) {
      bm = 1;
      by += 1;
    }
  }
  const pad = (n) => String(n).padStart(2, '0');
  const postingDate = `${by}-${pad(bm)}-${pad(Math.min(billingDay, daysInMonth(by, bm)))}`;
  const repaymentDate = `${by}-${pad(bm)}-${pad(Math.min(repaymentDay, daysInMonth(by, bm)))}`;
  return { postingDate, repaymentDate };
}

console.log('开始在数据库事务中执行全量转换与导入...');
db.exec('BEGIN TRANSACTION');

try {
  // 1. 清空旧数据（严格按外键依赖逆序删除）
  db.exec('DELETE FROM plan_todos');
  db.exec('DELETE FROM plan_revisions');
  db.exec('DELETE FROM expenses');
  db.exec('DELETE FROM plans');
  db.exec('DELETE FROM categories WHERE parent_id IS NOT NULL');
  db.exec('DELETE FROM categories');
  db.exec('DELETE FROM payment_methods');
  db.exec('DELETE FROM changes');
  db.exec("DELETE FROM settings WHERE key = 'demo_seed'");
  console.log('已清空现有演示账目、分类与支付方式。');

  // 2. 插入支付方式
  const pmIds = new Map();
  const insertPmStmt = db.prepare(`
    INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, is_enabled, sort_order, created_at, updated_at, rev)
    VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, 1)
  `);
  for (const pm of PAYMENT_METHOD_DEFS) {
    const id = ulid();
    insertPmStmt.run(id, pm.name, pm.type, pm.billingDay, pm.repaymentDay, pm.sortOrder, now, now);
    pmIds.set(pm.name, id);
  }
  console.log(`已初始化 ${PAYMENT_METHOD_DEFS.length} 个真实支付方式。`);

  // 3. 插入分类
  const catChildIds = new Map(); // "parent/child" -> childId
  const insertCatStmt = db.prepare(`
    INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled, created_at, updated_at, rev)
    VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?, 1)
  `);

  let catTotal = 0;
  for (let pIdx = 0; pIdx < CATEGORY_DEFS.length; pIdx++) {
    const pDef = CATEGORY_DEFS[pIdx];
    const parentId = ulid();
    insertCatStmt.run(parentId, null, pDef.name, 1, pDef.icon, pDef.color, pIdx, now, now);
    catTotal++;

    for (let cIdx = 0; cIdx < pDef.children.length; cIdx++) {
      const childName = pDef.children[cIdx];
      const childId = ulid();
      insertCatStmt.run(childId, parentId, childName, 2, '', pDef.color, cIdx, now, now);
      catChildIds.set(`${pDef.name}/${childName}`, childId);
      catTotal++;
    }
  }
  console.log(`已初始化 ${CATEGORY_DEFS.length} 个一级分类，共 ${catTotal} 个两级分类节点。`);

  // 4. 解析 CSV 并插入支出
  const csvContent = readFileSync(csvPath, 'utf-8');
  const lines = csvContent.trim().split('\n');

  const insertExpenseStmt = db.prepare(`
    INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id, spend_date, posting_date, repayment_date, note, source, created_at, updated_at, rev)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'manual', ?, ?, 1)
  `);

  let expenseCount = 0;
  let refundCount = 0;
  let skippedIncomeCount = 0;
  let totalExpenseCents = 0;
  let totalRefundCents = 0;
  let minDate = '9999-99-99';
  let maxDate = '0000-00-00';

  for (let i = 1; i < lines.length; i++) {
    const parts = lines[i].split(',');
    if (parts.length < 10) continue;

    const type = parts[0].trim();
    const cat = parts[1].trim();
    const subCat = parts[2].trim();
    const amountStr = parts[3].trim();
    const accountStr = parts[5].trim() || '银行卡';
    const note = parts[8].trim();
    const dateStr = parts[9].trim().slice(0, 10);

    let amountCents = 0;
    let targetCat;

    if (type === '支出') {
      const key = subCat || cat;
      targetCat = CATEGORY_MAP[key];
      if (!targetCat) {
        throw new Error(`未知分类：${key}（第 ${i + 1} 行）`);
      }
      amountCents = Math.round(Math.abs(parseFloat(amountStr)) * 100);
      expenseCount++;
      totalExpenseCents += amountCents;
    } else if (type === '收入') {
      if (cat === '杂项退款') {
        if (note.includes('车险')) {
          targetCat = CATEGORY_MAP['车辆保险'];
        } else if (note.includes('意外险')) {
          targetCat = CATEGORY_MAP['药品保健'];
        } else {
          targetCat = CATEGORY_MAP['其他杂项'];
        }
        amountCents = -Math.round(Math.abs(parseFloat(amountStr)) * 100);
        refundCount++;
        totalRefundCents += amountCents;
      } else {
        skippedIncomeCount++;
        continue;
      }
    } else {
      continue;
    }

    const categoryId = catChildIds.get(`${targetCat.parent}/${targetCat.child}`);
    if (!categoryId) {
      throw new Error(`找不到子分类 ID：${targetCat.parent}/${targetCat.child}`);
    }

    const pmId = pmIds.get(accountStr) || pmIds.get('银行卡');
    let postingDate = dateStr;
    let repaymentDate = dateStr;

    if (accountStr === '信用卡') {
      const dates = resolveCreditDates(dateStr, 10, 29);
      postingDate = dates.postingDate;
      repaymentDate = dates.repaymentDate;
    }

    if (dateStr < minDate) minDate = dateStr;
    if (dateStr > maxDate) maxDate = dateStr;

    const id = ulid();
    const rowTimestamp = `${dateStr}T12:00:00.000Z`;

    insertExpenseStmt.run(
      id,
      adminId,
      amountCents,
      categoryId,
      pmId,
      dateStr,
      postingDate,
      repaymentDate,
      note,
      rowTimestamp,
      rowTimestamp,
    );
  }

  db.exec('COMMIT');
  console.log('数据库事务提交成功！');

  const netCents = totalExpenseCents + totalRefundCents;
  console.log('\n================ 导入结果统计 ================');
  console.log(`支出总笔数：${expenseCount} 笔`);
  console.log(`支出总金额：¥${(totalExpenseCents / 100).toFixed(2)}`);
  console.log(`退款/冲销笔数：${refundCount} 笔（¥${(totalRefundCents / 100).toFixed(2)}）`);
  console.log(`净支出金额：¥${(netCents / 100).toFixed(2)}`);
  console.log(`跳过纯收入：${skippedIncomeCount} 笔（红包/工资/结余）`);
  console.log(`账本时间跨度：${minDate} 至 ${maxDate}`);
  console.log('==============================================\n');
} catch (error) {
  db.exec('ROLLBACK');
  console.error('导入失败，已回滚事务：', error);
  process.exit(1);
}
