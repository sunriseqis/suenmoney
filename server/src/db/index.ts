/**
 * 数据库连接与迁移。
 *
 * 用 Node 内置的 `node:sqlite`（同步 API）而非 better-sqlite3：
 * 后者是原生模块，需要本地编译工具链；同步 API 在单机服务端场景完全够用，
 * 还省掉了连接池。家庭 2 人账本的数据量下，同步读写的吞吐远超需求。
 *
 * Node 22.12 需要 `--experimental-sqlite`（见 package.json 脚本）。
 */
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { config } from '../config.ts';

/** 迁移文件目录（本文件位于 src/db/） */
const MIGRATIONS_DIR = join(import.meta.dirname, 'migrations');

let instance: DatabaseSync | null = null;

/** 打开（或复用）数据库连接。重复调用返回同一实例。 */
export function openDatabase(path: string = config.dbPath): DatabaseSync {
  if (instance) return instance;

  mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);

  // WAL：读写不互相阻塞（HTTP 请求与后台备份/快照任务并存时必需）
  db.exec('PRAGMA journal_mode = WAL');
  // 外键默认关闭，必须每个连接显式打开，否则 REFERENCES 全是摆设
  db.exec('PRAGMA foreign_keys = ON');
  // 写锁等待 5 秒再报 SQLITE_BUSY，而不是立即失败
  db.exec('PRAGMA busy_timeout = 5000');
  // WAL 下 NORMAL 是安全且快的档位（掉电最多丢最后一个事务，不会损坏库）
  db.exec('PRAGMA synchronous = NORMAL');

  instance = db;
  return db;
}

export function getDatabase(): DatabaseSync {
  return instance ?? openDatabase();
}

export function closeDatabase(): void {
  if (!instance) return;
  try {
    instance.close();
  } finally {
    instance = null;
  }
}

/**
 * 应用未执行的迁移。
 *
 * 只认文件名前缀的数字（`001_init.sql` → 版本 1），并保证顺序。
 * 每个迁移在独立事务里执行：失败则整体回滚且不写入版本记录，
 * 避免出现「表建了一半、版本却记上了」的半成品状态。
 */
export function migrate(db: DatabaseSync = getDatabase()): string[] {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    INTEGER PRIMARY KEY,
      name       TEXT NOT NULL,
      applied_at TEXT NOT NULL
    )
  `);

  const appliedRows = db.prepare('SELECT version FROM schema_migrations').all();
  const appliedVersions = new Set(appliedRows.map((row) => Number(row['version'])));

  const files = readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort((a, b) => a.localeCompare(b, 'en'));

  const applied: string[] = [];

  for (const file of files) {
    const matched = /^(\d+)_/.exec(file);
    if (matched === null || matched[1] === undefined) {
      throw new Error(`迁移文件名必须以数字版本号开头（如 001_init.sql）：${file}`);
    }

    const version = Number(matched[1]);
    if (appliedVersions.has(version)) continue;

    const sql = readFileSync(join(MIGRATIONS_DIR, file), 'utf8');

    db.exec('BEGIN');
    try {
      db.exec(sql);
      db.prepare('INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)').run(
        version,
        file,
        new Date().toISOString(),
      );
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw new Error(`迁移 ${file} 执行失败：${(error as Error).message}`, { cause: error });
    }

    applied.push(file);
  }

  return applied;
}

/**
 * 分配一个全局单调递增的同步版本号。
 *
 * 所有写操作都必须在一个事务里「先拿版本号 → 写实体 → 写 changes 记录」。
 * 客户端用这个版本号做增量游标 —— **绝不用时间戳**，因为客户端时钟与
 * 系统时区都不可信，用时间戳做游标迟早丢数据。
 *
 * sync_sequence 是单行计数器（不是自增表），所以不会随写入次数堆积行。
 */
export function nextSyncVersion(db: DatabaseSync): number {
  const row = db
    .prepare('UPDATE sync_sequence SET value = value + 1 WHERE id = 1 RETURNING value')
    .get();
  if (row === undefined) {
    throw new Error('sync_sequence 缺少 id=1 的计数行，数据库可能被外部改动过');
  }
  return Number(row['value']);
}
