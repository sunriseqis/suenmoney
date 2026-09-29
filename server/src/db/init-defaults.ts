/**
 * 数据库默认值初始化：分类、支付方式与初始管理员。
 *
 * 仅在对应表为空时写入，幂等安全，不覆盖现有数据。
 */
import { DatabaseSync } from 'node:sqlite';

import { inTransaction, recordChange } from './sync.ts';
import { ulid } from '../lib/ulid.ts';
import { countUsers, createUser } from './repo/users.ts';

export const DEFAULT_CATEGORIES: ReadonlyArray<{ name: string; children: readonly string[] }> = [
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

export const DEFAULT_PAYMENT_METHODS: ReadonlyArray<{ name: string; type: 'cash' }> = [
  { name: '现金', type: 'cash' },
];

function countOf(db: DatabaseSync, table: string): number {
  const row = db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE deleted_at IS NULL`).get() as { n: number } | undefined;
  return row === undefined ? 0 : Number(row.n);
}

export function seedPaymentMethodsIfEmpty(db: DatabaseSync): number {
  if (countOf(db, 'payment_methods') > 0) return 0;

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

export function seedCategoriesIfEmpty(db: DatabaseSync): number {
  if (countOf(db, 'categories') > 0) return 0;

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

export function seedInitialAdminFromEnvIfEmpty(db: DatabaseSync): boolean {
  const adminUser = process.env.SUENMONEY_ADMIN_USER?.trim();
  const adminPass = process.env.SUENMONEY_ADMIN_PASSWORD?.trim();

  if (!adminUser || !adminPass) return false;
  if (countUsers(db) > 0) return false;

  const adminName = process.env.SUENMONEY_ADMIN_NAME?.trim() || adminUser;

  createUser(db, {
    username: adminUser,
    displayName: adminName,
    password: adminPass,
    role: 'admin',
  });
  console.log(`[初始化] 已根据环境变量创建初始管理员：${adminUser}（${adminName}）`);
  return true;
}

export function initDefaultsIfEmpty(db: DatabaseSync): { methods: number; categories: number; adminCreated: boolean } {
  const methods = seedPaymentMethodsIfEmpty(db);
  const categories = seedCategoriesIfEmpty(db);
  const adminCreated = seedInitialAdminFromEnvIfEmpty(db);
  return { methods, categories, adminCreated };
}
