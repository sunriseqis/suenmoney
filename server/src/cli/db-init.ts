/**
 * 初始化数据库：应用迁移，并在首次初始化时写入一套默认分类与默认支付方式。
 *
 *   npm run db:init
 */
import { config } from '../config.ts';
import { migrate, openDatabase } from '../db/index.ts';
import {
  DEFAULT_CATEGORIES,
  DEFAULT_PAYMENT_METHODS,
  initDefaultsIfEmpty,
} from '../db/init-defaults.ts';

const db = openDatabase();
console.log(`数据库：${config.dbPath}`);

const applied = migrate(db);
if (applied.length === 0) {
  console.log('迁移：已是最新，无需要执行');
} else {
  console.log(`迁移：已应用 ${applied.join(', ')}`);
}

const { methods, categories } = initDefaultsIfEmpty(db);
if (methods > 0) {
  console.log(`默认支付方式：已写入 ${methods} 个（${DEFAULT_PAYMENT_METHODS.map((m) => m.name).join('、')}）`);
} else {
  console.log('默认支付方式：已存在，跳过');
}

if (categories > 0) {
  console.log(`默认分类：已写入 ${categories} 个（一级 ${DEFAULT_CATEGORIES.length} 个）`);
} else {
  console.log('默认分类：已存在，跳过（不会覆盖已有分类）');
}

console.log('\n完成。下一步：npm run user:add -- --username 你的登录名 --name 显示名 --admin');
