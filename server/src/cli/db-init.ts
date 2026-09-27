/**
 * 初始化数据库：应用迁移，并在**首次**初始化时写入一套默认分类与一个默认支付方式。
 *
 *   npm run db:init
 *
 * 只在对应的表为空时写入。已经建过账后重复执行不会重复灌入，
 * 也不会覆盖你自己加的分类与支付方式。
 */
import { config } from '../config.ts';
import { migrate, openDatabase } from '../db/index.ts';
import { inTransaction, recordChange } from '../db/sync.ts';
import { ulid } from '../lib/ulid.ts';

/**
 * 默认分类。二级分类留空的一级项（如「居住」下的「房贷」）后面跟的是
 * 常用子项 —— 房贷单列出来是为了让「计划」有地方挂。
 */
const DEFAULT_CATEGORIES: ReadonlyArray<{ name: string; children: readonly string[] }> = [
  { name: '餐饮', children: ['外卖', '买菜', '下馆子', '零食饮料'] },
  { name: '交通', children: ['公交地铁', '打车', '加油', '停车'] },
  { name: '居住', children: ['房贷', '房租', '物业', '水电燃气', '宽带'] },
  { name: '日用', children: ['超市', '洗护', '家居'] },
  { name: '通讯', children: ['话费', '流量'] },
  { name: '医疗', children: ['门诊', '药品'] },
  { name: '娱乐', children: ['会员订阅', '电影', '游戏'] },
  { name: '人情', children: ['礼物', '红包'] },
  { name: '其他', children: [] },
];

/**
 * 默认支付方式。
 *
 * **这一个是必须的，不是锦上添花**：分类为空只是记账时不方便，
 * 而支付方式为空会让「记一笔」直接走不通 —— 抽屉里会显示
 * 「还没有可用的支付方式」，保存按钮永远点不动。全新部署的人
 * 第一步就卡住，而且不知道要去设置里建。
 *
 * 只播种「现金」：它是唯一普适的默认值。信用卡的账单日/还款日因卡而异，
 * 替用户猜一个反而会让他记错账。
 */
const DEFAULT_PAYMENT_METHODS: ReadonlyArray<{ name: string; type: 'cash' }> = [
  { name: '现金', type: 'cash' },
];

function seedPaymentMethods(db: ReturnType<typeof openDatabase>): number {
  const timestamp = new Date().toISOString();
  let count = 0;

  inTransaction(db, () => {
    for (const [index, method] of DEFAULT_PAYMENT_METHODS.entries()) {
      const id = ulid();

      db.prepare(
        `INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, is_enabled,
                                      sort_order, created_at, updated_at, deleted_at, rev, device_id)
         VALUES (?, ?, ?, NULL, NULL, 1, ?, ?, ?, NULL, 1, NULL)`,
      ).run(id, method.name, method.type, index, timestamp, timestamp);

      recordChange(db, {
        entityType: 'payment_method',
        entityId: id,
        op: 'upsert',
        actorId: null,
        payload: { id, name: method.name, type: method.type, isEnabled: true },
        deviceId: null,
      });
      count += 1;
    }
  });

  return count;
}

function seedCategories(db: ReturnType<typeof openDatabase>): number {
  const timestamp = new Date().toISOString();
  let count = 0;

  inTransaction(db, () => {
    for (const [groupIndex, group] of DEFAULT_CATEGORIES.entries()) {
      const parentId = ulid();

      db.prepare(
        `INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                                 created_at, updated_at, deleted_at, rev, device_id)
         VALUES (?, NULL, ?, 1, '', '', ?, 1, ?, ?, NULL, 1, NULL)`,
      ).run(parentId, group.name, groupIndex, timestamp, timestamp);

      recordChange(db, {
        entityType: 'category',
        entityId: parentId,
        op: 'upsert',
        actorId: null,
        payload: { id: parentId, parentId: null, name: group.name, depth: 1 },
        deviceId: null,
      });
      count += 1;

      for (const [childIndex, childName] of group.children.entries()) {
        const childId = ulid();

        db.prepare(
          `INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                                   created_at, updated_at, deleted_at, rev, device_id)
           VALUES (?, ?, ?, 2, '', '', ?, 1, ?, ?, NULL, 1, NULL)`,
        ).run(childId, parentId, childName, childIndex, timestamp, timestamp);

        recordChange(db, {
          entityType: 'category',
          entityId: childId,
          op: 'upsert',
          actorId: null,
          payload: { id: childId, parentId, name: childName, depth: 2 },
          deviceId: null,
        });
        count += 1;
      }
    }
  });

  return count;
}

const db = openDatabase();
console.log(`数据库：${config.dbPath}`);

const applied = migrate(db);
if (applied.length === 0) {
  console.log('迁移：已是最新，无需要执行');
} else {
  console.log(`迁移：已应用 ${applied.join(', ')}`);
}

const countOf = (table: string): number => {
  const row = db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE deleted_at IS NULL`).get();
  return row === undefined ? 0 : Number(row['n']);
};

const existingMethods = countOf('payment_methods');
if (existingMethods === 0) {
  const created = seedPaymentMethods(db);
  console.log(`默认支付方式：已写入 ${created} 个（${DEFAULT_PAYMENT_METHODS.map((m) => m.name).join('、')}）`);
} else {
  console.log(`默认支付方式：已存在 ${existingMethods} 个，跳过`);
}

const existingCategories = countOf('categories');
if (existingCategories === 0) {
  const created = seedCategories(db);
  console.log(`默认分类：已写入 ${created} 个（一级 ${DEFAULT_CATEGORIES.length} 个）`);
} else {
  console.log(`默认分类：已存在 ${existingCategories} 个，跳过（不会覆盖你自己的分类）`);
}

console.log('\n完成。下一步：npm run user:add -- --username 你的登录名 --name 显示名 --admin');
