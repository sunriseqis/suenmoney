/**
 * 运维侧 SQLite 物理快照管理。
 *
 * 区别于用户侧的 JSON 备份包（`transfer.ts`）：
 * - 用户侧备份包：JSON 格式，明文跨版本、按实体导入合并/恢复，可在 Web 端跨设备分享。
 * - 运维侧快照：通过 SQLite 原生 `VACUUM INTO` 生成的一致性物理 `.sqlite` 库文件，
 *   保留 WAL 归并后的完整 B-Tree，保留系统全部 schema 与索引，可用于容器灾备替换、离线还原。
 */
import { DatabaseSync } from 'node:sqlite';
import { existsSync, mkdirSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

import { config } from '../../config.ts';

export interface SnapshotInfo {
  filename: string;
  sizeBytes: number;
  createdAt: string;
}

const SNAPSHOT_REGEX = /^suenmoney-snapshot-[\w.-]+\.sqlite$/;

export function getSnapshotsDir(): string {
  const dir = join(config.backupDir, 'snapshots');
  mkdirSync(dir, { recursive: true });
  return dir;
}

function formatStamp(d: Date = new Date()): string {
  const yyyy = d.getFullYear();
  const MM = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const HH = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return `${yyyy}${MM}${dd}-${HH}${mm}${ss}`;
}

export function todaySnapshotPrefix(d: Date = new Date()): string {
  const yyyy = d.getFullYear();
  const MM = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `suenmoney-snapshot-${yyyy}${MM}${dd}`;
}

/**
 * 触发一次即时 VACUUM INTO 快照。
 *
 * SQLite 要求目标文件不能已存在，否则抛出异常。
 */
export function createSnapshot(db: DatabaseSync): SnapshotInfo {
  const dir = getSnapshotsDir();
  let filename = `suenmoney-snapshot-${formatStamp()}.sqlite`;
  let targetPath = join(dir, filename);

  if (existsSync(targetPath)) {
    filename = `suenmoney-snapshot-${formatStamp()}-${Math.random().toString(36).slice(2, 6)}.sqlite`;
    targetPath = join(dir, filename);
  }

  db.prepare('VACUUM INTO ?').run(targetPath);

  pruneOldSnapshots();

  const stat = statSync(targetPath);
  return {
    filename,
    sizeBytes: stat.size,
    createdAt: (stat.birthtime ?? stat.mtime).toISOString(),
  };
}

/** 列出所有快照，按时间倒序排列（最新在前） */
export function listSnapshots(): SnapshotInfo[] {
  const dir = getSnapshotsDir();
  const entries = readdirSync(dir);

  const list: SnapshotInfo[] = [];
  for (const name of entries) {
    if (!SNAPSHOT_REGEX.test(name)) continue;
    const fullPath = join(dir, name);
    try {
      const stat = statSync(fullPath);
      list.push({
        filename: name,
        sizeBytes: stat.size,
        createdAt: (stat.birthtime ?? stat.mtime).toISOString(),
      });
    } catch {
      // 忽略无法读取的临时文件
    }
  }

  // 按文件名倒序（因为文件名内含 YYYYMMDD-HHmmss 时间戳）
  list.sort((a, b) => b.filename.localeCompare(a.filename));
  return list;
}

/** 安全校验并获取快照的绝对路径，防止路径穿越攻击 */
export function getSnapshotPath(filename: string): string | null {
  if (!SNAPSHOT_REGEX.test(filename)) {
    return null;
  }
  const dir = getSnapshotsDir();
  const fullPath = join(dir, filename);
  if (!existsSync(fullPath)) {
    return null;
  }
  return fullPath;
}

/** 删除指定的快照文件 */
export function deleteSnapshot(filename: string): boolean {
  const fullPath = getSnapshotPath(filename);
  if (!fullPath) return false;
  try {
    unlinkSync(fullPath);
    return true;
  } catch {
    return false;
  }
}

/** 保留最近 backupKeep 份快照，清理超出配额的旧文件 */
export function pruneOldSnapshots(keepCount: number = config.backupKeep): number {
  const dir = getSnapshotsDir();
  const files = readdirSync(dir)
    .filter((f) => SNAPSHOT_REGEX.test(f))
    .sort(); // 升序，最旧的在前面

  const removeCount = Math.max(0, files.length - keepCount);
  let deleted = 0;
  for (const name of files.slice(0, removeCount)) {
    try {
      unlinkSync(join(dir, name));
      deleted += 1;
    } catch {
      // 忽略清理异常
    }
  }
  return deleted;
}

let schedulerTimer: NodeJS.Timeout | null = null;

/** 检查今天是否已有快照，若无则执行 */
export function runDailySnapshotCheck(db: DatabaseSync): void {
  try {
    const dir = getSnapshotsDir();
    const prefix = todaySnapshotPrefix();
    const files = readdirSync(dir).filter((f) => f.startsWith(prefix));
    if (files.length === 0) {
      createSnapshot(db);
    }
  } catch (error) {
    console.error('执行每日自动快照失败：', error);
  }
}

/** 启动每日快照轮询定时器（每小时检查一次今天是否有快照） */
export function startDailySnapshotScheduler(db: DatabaseSync): NodeJS.Timeout {
  runDailySnapshotCheck(db);

  if (schedulerTimer) {
    clearInterval(schedulerTimer);
  }
  // 每小时检查一次
  schedulerTimer = setInterval(() => {
    runDailySnapshotCheck(db);
  }, 60 * 60 * 1000);

  schedulerTimer.unref();
  return schedulerTimer;
}

export function stopDailySnapshotScheduler(): void {
  if (schedulerTimer) {
    clearInterval(schedulerTimer);
    schedulerTimer = null;
  }
}
