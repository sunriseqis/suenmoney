/**
 * 初始化数据库：应用迁移。**不写任何预置分类与支付方式** ——
 * 全新部署就是一张空白体系，由用户自己建立，或由「导入流水」
 * 按 CSV 里的名字自动创建（见 web/src/components/BillImportModal.vue）。
 *
 *   npm run db:init
 */
import { config } from '../config.ts';
import { migrate, openDatabase } from '../db/index.ts';

const db = openDatabase();
console.log(`数据库：${config.dbPath}`);

const applied = migrate(db);
if (applied.length === 0) {
  console.log('迁移：已是最新，无需要执行');
} else {
  console.log(`迁移：已应用 ${applied.join(', ')}`);
}

console.log('\n完成。下一步：npm run user:add -- --username 你的登录名 --name 显示名 --admin');
console.log('分类与支付方式为空属正常：可在应用内创建，或导入流水时按名字自动补齐。');
