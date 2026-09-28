/**
 * schema 约束回归测试。
 *
 * 为什么值得单独存在：schema 里的 CHECK / 部分唯一索引 / 外键都不是装饰，
 * 它们是「代码写错时最后一道拦网」。约束被写松（比如 CHECK 写成单向的
 * `A OR B`，或者唯一索引漏了 `WHERE deleted_at IS NULL`）时**不会有任何报错**，
 * 只会静默放行脏数据 —— 所以每一条都必须有断言钉住。
 *
 * 全部在内存库上跑，不碰真实的 data/suenmoney.sqlite。
 */
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { describe, test } from 'node:test';

import { migrate } from '../src/db/index.ts';

const MIGRATIONS_DIR = join(import.meta.dirname, '..', 'src', 'db', 'migrations');

/** 目录下的迁移文件，按文件名前缀的字典序 —— 与执行器的调度顺序一致。 */
function migrationFiles(): string[] {
  return readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort((a, b) => a.localeCompare(b, 'en'));
}

/**
 * 一个跑过**全部**迁移的内存库（不是只跑 001）。
 *
 * 之前这里只 `exec` 了 `001_init.sql`：002 之后这个库就不是真实 schema 了，
 * 而下面所有「约束」用例都跑在它上面 —— 会出现「测试全绿、线上 schema 已经不一样」
 * 的裂缝。改成按目录顺序全量应用，加迁移就不必回来改这里。
 */
function freshDatabase(): DatabaseSync {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys = ON');
  for (const file of migrationFiles()) {
    db.exec(readFileSync(join(MIGRATIONS_DIR, file), 'utf8'));
  }
  return db;
}

const db = freshDatabase();
const NOW = '2026-01-01T00:00:00.000Z';

function tableNames(target: DatabaseSync): string[] {
  return target
    .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
    .all()
    .map((row) => String(row['name']));
}

/** 一套最小可用数据：用户 / 一级与二级分类 / 现金与信用卡 / 一个计划 */
function seed(): void {
  db.exec(`INSERT INTO users (id, username, display_name, password_hash, role, created_at, updated_at)
           VALUES ('u1','suen','我','x','admin','${NOW}','${NOW}')`);
  db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
           VALUES ('c1', NULL, '餐饮', 1, '${NOW}', '${NOW}')`);
  db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
           VALUES ('c2', 'c1', '外卖', 2, '${NOW}', '${NOW}')`);
  db.exec(`INSERT INTO payment_methods (id, name, type, created_at, updated_at)
           VALUES ('p1', '现金', 'cash', '${NOW}', '${NOW}')`);
  db.exec(`INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, created_at, updated_at)
           VALUES ('p2', '招行信用卡', 'credit', 10, 28, '${NOW}', '${NOW}')`);
  db.exec(`INSERT INTO plans (id, owner_id, name, category_id, payment_method_id, amount_cents,
                              first_due_date, created_at, updated_at)
           VALUES ('pl1','u1','房贷','c1','p1',1000000,'2026-02-20','${NOW}','${NOW}')`);
}

/**
 * 迁移执行器与迁移文件是两件事：
 *   001_init.sql         建业务表
 *   db/index.ts 的 migrate()  建 schema_migrations、按版本号调度、用事务包裹
 * 所以这里分开测 —— 只验证 SQL 会漏掉「幂等」「版本记录」这类执行器本身的职责。
 */
describe('迁移执行器', () => {
  const runner = new DatabaseSync(':memory:');

  test('首次执行应用全部迁移文件并记录版本', () => {
    const expected = migrationFiles();
    assert.ok(expected.length >= 1, '至少要有一个迁移文件');

    assert.deepEqual(migrate(runner), expected);

    const versions = runner
      .prepare('SELECT version FROM schema_migrations ORDER BY version')
      .all()
      .map((row) => Number(row['version']));
    // 版本号取自文件名前缀，必须与文件列表一一对应（001 → 1、002 → 2 …）
    assert.deepEqual(
      versions,
      expected.map((name) => Number(/^(\d+)_/.exec(name)![1])),
    );
  });

  test('002 给 plan_todos 加了「本期不再自动入账」标记，且默认不改变存量行为', () => {
    const columns = runner
      .prepare('PRAGMA table_info(plan_todos)')
      .all()
      .map((row) => String(row['name']));
    assert.ok(
      columns.includes('hold_auto_post'),
      '少了这一列，撤销确认与恢复跳过在有自动入账的计划上会静默失效',
    );

    const info = runner
      .prepare(
        "SELECT dflt_value AS d, \"notnull\" AS nn FROM pragma_table_info('plan_todos') WHERE name = 'hold_auto_post'",
      )
      .get() as unknown as Record<string, unknown>;
    // 默认 0 = 照旧自动入账：升级不能把存量计划悄悄变成手动
    assert.equal(String(info['d']), '0');
    assert.equal(Number(info['nn']), 1, '不允许为 NULL，否则 WHERE hold_auto_post = 0 会漏掉存量行');
  });

  test('003 给 plan_todos 加了「我知道了」标记，且不改变存量行', () => {
    const info = runner
      .prepare(
        "SELECT dflt_value AS d, \"notnull\" AS nn FROM pragma_table_info('plan_todos') WHERE name = 'ack_at'",
      )
      .get() as unknown as Record<string, unknown>;

    assert.ok(info !== undefined, '少了 ack_at，「确认」只能做成前端隐藏，换设备又会冒出来');
    // 可空且无默认值：存量待办全部落在「未确认」，行为与加这一列之前一致
    assert.equal(info['d'], null);
    assert.equal(Number(info['nn']), 0, '必须可空 —— NOT NULL 会让存量行无法满足约束');
  });

  test('重复执行是幂等的，不会重放迁移', () => {
    assert.deepEqual(migrate(runner), [], '第二次执行不应再应用任何迁移');
  });

  test('执行后建出全部表（含执行器自己建的 schema_migrations）', () => {
    const tables = tableNames(runner);
    for (const expected of [
      'categories',
      'changes',
      'expenses',
      'payment_methods',
      'plan_revisions',
      'plan_todos',
      'plans',
      'schema_migrations',
      'sessions',
      'settings',
      'sync_sequence',
      'users',
    ]) {
      assert.ok(tables.includes(expected), `缺少表：${expected}`);
    }
  });

  test('迁移文件本身不建 schema_migrations（那是执行器的职责）', () => {
    // db 直接跑过全部迁移文件，但没走过 migrate() 执行器
    assert.equal(
      tableNames(db).includes('schema_migrations'),
      false,
      'schema_migrations 应由 migrate() 建立，迁移文件里不该出现',
    );
  });
});

describe('约束', () => {
  test('基础实体可以写入', () => {
    assert.doesNotThrow(() => seed());
  });
});

describe('同步版本号', () => {
  test('单调递增，且不随写入次数堆积行', () => {
    const bump = () =>
      db.prepare('UPDATE sync_sequence SET value = value + 1 WHERE id = 1 RETURNING value').get();

    const sequence = [bump(), bump(), bump()].map((row) => Number(row?.['value']));

    // 与具体起始值无关，只要求严格递增
    assert.ok(sequence[1]! > sequence[0]!, `版本号应递增，实际 ${sequence.join(',')}`);
    assert.ok(sequence[2]! > sequence[1]!, `版本号应递增，实际 ${sequence.join(',')}`);

    const rows = db.prepare('SELECT COUNT(*) AS n FROM sync_sequence').get();
    assert.equal(Number(rows?.['n']), 1, 'sync_sequence 是单行计数器，不该累积行');
  });
});

describe('支付方式约束', () => {
  test('现金类不能填账单日/还款日', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, created_at, updated_at)
                 VALUES ('px1','怪现金','cash',10,28,'${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('信用类必须同时有账单日与还款日', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO payment_methods (id, name, type, created_at, updated_at)
                 VALUES ('px2','半截卡','credit','${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('账单日必须在 1–31 之间', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, created_at, updated_at)
                 VALUES ('px3','越界卡','credit',32,28,'${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('同名支付方式不可重复', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO payment_methods (id, name, type, created_at, updated_at)
                 VALUES ('px4','现金','cash','${NOW}','${NOW}')`),
      /UNIQUE constraint failed/,
    );
  });
});

describe('分类约束', () => {
  test('二级分类必须有父级', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
                 VALUES ('cx1',NULL,'孤儿',2,'${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('一级分类不能有父级', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
                 VALUES ('cx2','c1','假一级',1,'${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('同层不可重名', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
                 VALUES ('cx3',NULL,'餐饮',1,'${NOW}','${NOW}')`),
      /UNIQUE constraint failed/,
    );
  });

  test('不同层可以重名（唯一性按「同层」判定）', () => {
    assert.doesNotThrow(() =>
      db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
               VALUES ('cx4','c1','餐饮',2,'${NOW}','${NOW}')`),
    );
  });
});

describe('支出约束', () => {
  test('金额不能为 0', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                                       spend_date, posting_date, repayment_date, created_at, updated_at)
                 VALUES ('ex0','u1',0,'c1','p1','2026-01-01','2026-01-01','2026-01-01','${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });

  test('外键拦住不存在的分类', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                                       spend_date, posting_date, repayment_date, created_at, updated_at)
                 VALUES ('ex1','u1',100,'nope','p1','2026-01-01','2026-01-01','2026-01-01','${NOW}','${NOW}')`),
      /FOREIGN KEY constraint failed/,
    );
  });

  /**
   * 这条防的是「CHECK 被写成单向的 `A OR B`」：
   * 单向写法下，source='manual' 的记录挂上真实存在的 plan_id 也能通过。
   */
  test('手动记录不能挂计划（双向 CHECK，而非单向 A OR B）', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                                       spend_date, posting_date, repayment_date, source,
                                       plan_id, plan_period_seq, created_at, updated_at)
                 VALUES ('ex2','u1',100,'c1','p1','2026-01-01','2026-01-01','2026-01-01','manual',
                         'pl1',1,'${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });
});

describe('核心业务行为：报表月份按「还款日」归属', () => {
  test('账单日 10 / 还款日 28 的卡：9 日消费落本月、11 日消费落次月', () => {
    db.exec(`INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                                   spend_date, posting_date, repayment_date, note, created_at, updated_at)
             VALUES ('ex3','u1',3200,'c2','p2','2026-01-09','2026-01-10','2026-01-28','午饭','${NOW}','${NOW}')`);
    db.exec(`INSERT INTO expenses (id, owner_id, amount_cents, category_id, payment_method_id,
                                   spend_date, posting_date, repayment_date, note, created_at, updated_at)
             VALUES ('ex4','u1',1800,'c2','p2','2026-01-11','2026-02-10','2026-02-28','11 日消费','${NOW}','${NOW}')`);

    const rows = db
      .prepare(`SELECT substr(repayment_date,1,7) AS ym, SUM(amount_cents) AS cents
                  FROM expenses WHERE deleted_at IS NULL GROUP BY ym ORDER BY ym`)
      .all();

    assert.deepEqual(
      rows.map((row) => `${String(row['ym'])}=${String(row['cents'])}`),
      ['2026-01=3200', '2026-02=1800'],
    );
  });
});

describe('计划待办约束', () => {
  test('同计划同期不可重复（离线并发确认的幂等键）', () => {
    db.exec(`INSERT INTO plan_todos (id, plan_id, period_seq, amount_cents, posting_date,
                                     repayment_date, remind_date, created_at, updated_at)
             VALUES ('t25','pl1',25,1000000,'2026-02-20','2026-02-20','2026-02-17','${NOW}','${NOW}')`);

    assert.throws(
      () =>
        db.exec(`INSERT INTO plan_todos (id, plan_id, period_seq, amount_cents, posting_date,
                                         repayment_date, remind_date, created_at, updated_at)
                 VALUES ('tX','pl1',25,1000000,'2026-02-20','2026-02-20','2026-02-17','${NOW}','${NOW}')`),
      /UNIQUE constraint failed/,
    );
  });

  test('已确认的待办必须有支出记录与确认人', () => {
    assert.throws(
      () => db.exec("UPDATE plan_todos SET status='confirmed' WHERE id='t25'"),
      /CHECK constraint failed/,
    );
  });

  test('待办期序必须从 1 起', () => {
    assert.throws(
      () =>
        db.exec(`INSERT INTO plan_todos (id, plan_id, period_seq, amount_cents, posting_date,
                                         repayment_date, remind_date, created_at, updated_at)
                 VALUES ('t0','pl1',0,1000000,'2026-01-20','2026-01-20','2026-01-17','${NOW}','${NOW}')`),
      /CHECK constraint failed/,
    );
  });
});

describe('软删除与命名空间', () => {
  /**
   * 部分唯一索引（`WHERE deleted_at IS NULL`）的意义就在于此：
   * 没有它的话，软删除掉的分类名会永久占用命名空间，再也建不出同名的。
   * 用独立的名字而不是复用「餐饮」，避免与前面的用例产生顺序耦合。
   */
  test('软删除后可以重建同名分类', () => {
    db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
             VALUES ('cd1',NULL,'临时分类',1,'${NOW}','${NOW}')`);
    db.exec("UPDATE categories SET deleted_at = '2026-02-01T00:00:00.000Z' WHERE id='cd1'");

    assert.doesNotThrow(() =>
      db.exec(`INSERT INTO categories (id, parent_id, name, depth, created_at, updated_at)
               VALUES ('cd2',NULL,'临时分类',1,'${NOW}','${NOW}')`),
    );
  });
});
