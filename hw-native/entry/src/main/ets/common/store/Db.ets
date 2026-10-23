/**
 * 本地库（H0-4）：关系型数据库 relationalStore。
 *
 * 设计依据 docs/plan/2026-10-21-客户端全原生化方案.md §七「离线契约」：
 *   表名与 Web 的 IndexedDB 完全同名，**列名用 snake_case**，与同步快照一致 ——
 *   这样「本地算出来的」和「服务端下发/上传的」是同一套字段，不需要中间的映射层。
 *   映射层是最容易悄悄错位的地方（改一边忘一边），所以干脆不设。
 *
 * 七张表：meta / categories / payment_methods / expenses / plans / plan_todos / outbox
 * 另加两个索引：expenses(repayment_date)（报表按月取数）、plan_todos(status)。
 *
 * 金额一律 INTEGER（整数分）；日期一律 TEXT（YYYY-MM-DD）；布尔一律 INTEGER(0/1)。
 */
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'Db';
const DB_NAME = 'suenmoney.db';
/** 表结构版本，改表时 +1 并在 migrate 里补分支 */
export const SCHEMA_VERSION = 1;

const CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S2
};

interface TableSpec {
  name: string;
  columns: string[];
}

/** 建表语句（IF NOT EXISTS，可反复执行） */
const CREATE_TABLES: string[] = [
  `CREATE TABLE IF NOT EXISTS meta (
     key TEXT PRIMARY KEY,
     value TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS categories (
     id TEXT PRIMARY KEY,
     parent_id TEXT,
     name TEXT NOT NULL,
     depth INTEGER NOT NULL DEFAULT 1,
     icon TEXT NOT NULL DEFAULT '',
     color TEXT NOT NULL DEFAULT '',
     sort_order INTEGER NOT NULL DEFAULT 0,
     is_enabled INTEGER NOT NULL DEFAULT 1
   )`,
  `CREATE TABLE IF NOT EXISTS payment_methods (
     id TEXT PRIMARY KEY,
     name TEXT NOT NULL,
     type TEXT NOT NULL,
     icon TEXT NOT NULL DEFAULT '',
     billing_day INTEGER,
     repayment_day INTEGER,
     is_enabled INTEGER NOT NULL DEFAULT 1,
     sort_order INTEGER NOT NULL DEFAULT 0
   )`,
  `CREATE TABLE IF NOT EXISTS expenses (
     id TEXT PRIMARY KEY,
     owner_id TEXT NOT NULL,
     amount_cents INTEGER NOT NULL,
     category_id TEXT NOT NULL,
     payment_method_id TEXT NOT NULL,
     spend_date TEXT NOT NULL,
     posting_date TEXT NOT NULL,
     repayment_date TEXT NOT NULL,
     note TEXT NOT NULL DEFAULT '',
     source TEXT NOT NULL DEFAULT 'manual',
     updated_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS plans (
     id TEXT PRIMARY KEY,
     name TEXT NOT NULL,
     category_id TEXT NOT NULL,
     payment_method_id TEXT NOT NULL,
     amount_cents INTEGER NOT NULL,
     total_amount_cents INTEGER,
     purchase_date TEXT,
     first_due_date TEXT NOT NULL,
     remind_days_before INTEGER NOT NULL DEFAULT 3,
     auto_post INTEGER NOT NULL DEFAULT 0,
     source TEXT NOT NULL DEFAULT 'manual',
     state TEXT NOT NULL DEFAULT 'active',
     note TEXT NOT NULL DEFAULT '',
     updated_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS plan_todos (
     id TEXT PRIMARY KEY,
     plan_id TEXT NOT NULL,
     plan_name TEXT NOT NULL,
     period_seq INTEGER NOT NULL,
     amount_cents INTEGER NOT NULL,
     repayment_date TEXT NOT NULL,
     status TEXT NOT NULL DEFAULT 'pending',
     will_auto_post INTEGER NOT NULL DEFAULT 0,
     updated_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS outbox (
     id TEXT PRIMARY KEY,
     action TEXT NOT NULL,
     entity_id TEXT NOT NULL,
     payload TEXT NOT NULL,
     created_at TEXT NOT NULL,
     retry_count INTEGER NOT NULL DEFAULT 0,
     last_error TEXT
   )`
];

const CREATE_INDEXES: string[] = [
  'CREATE INDEX IF NOT EXISTS idx_expenses_repayment ON expenses(repayment_date)',
  'CREATE INDEX IF NOT EXISTS idx_todos_status ON plan_todos(status)',
  'CREATE INDEX IF NOT EXISTS idx_outbox_created ON outbox(created_at)'
];

export class Db {
  private static store: relationalStore.RdbStore | null = null;

  /** 打开（首次会创建）并迁移到当前表结构版本 */
  static async open(context: common.Context): Promise<relationalStore.RdbStore> {
    if (Db.store !== null) {
      return Db.store;
    }
    const opened = await relationalStore.getRdbStore(context, CONFIG);
    for (const sql of CREATE_TABLES) {
      await opened.executeSql(sql);
    }
    for (const sql of CREATE_INDEXES) {
      await opened.executeSql(sql);
    }
    await opened.executeSql(
      'INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)',
      ['schema_version', String(SCHEMA_VERSION)]
    );
    Db.store = opened;
    hilog.info(DOMAIN, TAG, 'db ready, schema v%{public}d', SCHEMA_VERSION);
    return opened;
  }

  static get(): relationalStore.RdbStore {
    if (Db.store === null) {
      throw new Error('Db.open() 尚未调用');
    }
    return Db.store;
  }

  /**
   * 表结构自检：返回「表 → 列名数组」。
   *
   * 这是 H0-4 的上机验收证据：在设备上跑一次，把输出贴进回执，
   * 就能确认七张表与列名真的照契约建出来了（而不是「应该建了」）。
   */
  static async schemaReport(): Promise<string> {
    const store = Db.get();
    const lines: string[] = [];
    for (const table of TABLES) {
      const rs = await store.querySql(`PRAGMA table_info(${table.name})`);
      const cols: string[] = [];
      while (rs.goToNextRow()) {
        cols.push(rs.getString(rs.getColumnIndex('name')));
      }
      rs.close();
      lines.push(`${table.name}(${cols.join(',')})`);
    }
    return lines.join('\n');
  }
}

/** 期望的表与列（自检用，与上面的建表语句一一对应） */
export const TABLES: TableSpec[] = [
  { name: 'meta', columns: ['key', 'value'] },
  { name: 'categories', columns: ['id', 'parent_id', 'name', 'depth', 'icon', 'color', 'sort_order', 'is_enabled'] },
  { name: 'payment_methods', columns: ['id', 'name', 'type', 'icon', 'billing_day', 'repayment_day', 'is_enabled', 'sort_order'] },
  { name: 'expenses', columns: ['id', 'owner_id', 'amount_cents', 'category_id', 'payment_method_id', 'spend_date', 'posting_date', 'repayment_date', 'note', 'source', 'updated_at'] },
  { name: 'plans', columns: ['id', 'name', 'category_id', 'payment_method_id', 'amount_cents', 'total_amount_cents', 'purchase_date', 'first_due_date', 'remind_days_before', 'auto_post', 'source', 'state', 'note', 'updated_at'] },
  { name: 'plan_todos', columns: ['id', 'plan_id', 'plan_name', 'period_seq', 'amount_cents', 'repayment_date', 'status', 'will_auto_post', 'updated_at'] },
  { name: 'outbox', columns: ['id', 'action', 'entity_id', 'payload', 'created_at', 'retry_count', 'last_error'] }
];
