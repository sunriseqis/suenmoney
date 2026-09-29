/**
 * WebDAV 远程安全备份管理。
 *
 * 核心机制：
 * 1. 采用 SQLite 原生 VACUUM INTO 生成完整的一致性物理库快照；
 * 2. 通过 WebDAV 协议（PUT）上传至用户自建/托管的 WebDAV 存储（如坚果云、Nextcloud、NAS、Alist 等）；
 * 3. 严格保留最近 3 天（3 份）的远程备份，通过 PROPFIND 与 DELETE 自动轮转删除超期备份；
 * 4. 每日定时后台轮询自动备份，防止服务器单点灾难。
 */
import { existsSync, mkdirSync, readFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import type { DatabaseSync } from 'node:sqlite';

import { badRequest } from '../../lib/http-error.ts';
import { createSnapshot, getSnapshotPath } from './snapshots.ts';

export interface WebdavConfig {
  url: string;
  username: string;
  password?: string;
  path: string;
  isEnabled: boolean;
}

export interface WebdavStatus {
  lastBackupAt: string | null;
  lastBackupStatus: 'success' | 'error' | null;
  lastBackupMessage: string | null;
  lastBackupFilename: string | null;
}

const CONFIG_KEY = 'webdav_backup_config';
const STATUS_KEY = 'webdav_backup_status';

export function getWebdavConfig(db: DatabaseSync): WebdavConfig | null {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(CONFIG_KEY) as
    | { value: string }
    | undefined;
  if (!row) return null;
  try {
    return JSON.parse(row.value) as WebdavConfig;
  } catch {
    return null;
  }
}

export function saveWebdavConfig(db: DatabaseSync, config: WebdavConfig): void {
  const now = new Date().toISOString();
  db.prepare(
    `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  ).run(CONFIG_KEY, JSON.stringify(config), now);
}

export function getWebdavStatus(db: DatabaseSync): WebdavStatus {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(STATUS_KEY) as
    | { value: string }
    | undefined;
  if (!row) {
    return {
      lastBackupAt: null,
      lastBackupStatus: null,
      lastBackupMessage: null,
      lastBackupFilename: null,
    };
  }
  try {
    return JSON.parse(row.value) as WebdavStatus;
  } catch {
    return {
      lastBackupAt: null,
      lastBackupStatus: null,
      lastBackupMessage: null,
      lastBackupFilename: null,
    };
  }
}

export function saveWebdavStatus(db: DatabaseSync, status: WebdavStatus): void {
  const now = new Date().toISOString();
  db.prepare(
    `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  ).run(STATUS_KEY, JSON.stringify(status), now);
}

export function normalizeWebdavUrls(
  url: string,
  path: string,
): { dirUrl: string; baseAuthUrl: string } {
  const cleanUrl = url.trim().replace(/\/+$/, '');
  const cleanPath = path.trim()
    ? (path.trim().startsWith('/') ? path.trim() : `/${path.trim()}`).replace(/\/+$/, '')
    : '';
  const dirUrl = `${cleanUrl}${cleanPath}/`;
  return { dirUrl, baseAuthUrl: cleanUrl };
}

export function basicAuthHeader(username: string, password?: string): string {
  const token = Buffer.from(`${username}:${password ?? ''}`).toString('base64');
  return `Basic ${token}`;
}

/** 提取 WebDAV XML 响应中的所有 href 路径 */
export function extractBackupHrefs(xmlText: string): string[] {
  const matches = [
    ...xmlText.matchAll(/<(?:[a-zA-Z0-9_-]+:)?href>([^<]+)<\/(?:[a-zA-Z0-9_-]+:)?href>/gi),
  ];
  const hrefs: string[] = [];
  for (const match of matches) {
    if (match[1]) {
      hrefs.push(decodeURIComponent(match[1]));
    }
  }
  return hrefs;
}

/** 确保远程 WebDAV 目录存在，若不存在则创建 */
async function ensureRemoteDir(dirUrl: string, authHeader: string): Promise<void> {
  let checkRes: Response;
  try {
    checkRes = await fetch(dirUrl, {
      method: 'PROPFIND',
      headers: {
        Authorization: authHeader,
        Depth: '0',
      },
    });
  } catch (networkError) {
    throw new Error(`无法连接到 WebDAV 服务器：${networkError instanceof Error ? networkError.message : String(networkError)}`);
  }

  if (checkRes.status === 200 || checkRes.status === 207) {
    return;
  }
  if (checkRes.status === 401 || checkRes.status === 403) {
    throw new Error('WebDAV 认证失败：用户名或密码错误');
  }
  if (checkRes.status === 404) {
    const mkRes = await fetch(dirUrl, {
      method: 'MKCOL',
      headers: { Authorization: authHeader },
    });
    if (mkRes.status === 201 || mkRes.status === 405 || mkRes.status === 200) {
      return;
    }
    throw new Error(`无法创建 WebDAV 远程备份目录（HTTP ${mkRes.status}）`);
  }
}

/**
 * 测试 WebDAV 连通性与读写权限。
 */
export async function testWebdav(config: WebdavConfig): Promise<{ ok: boolean; message: string }> {
  if (!config.url) throw badRequest('WebDAV 地址不能为空');
  if (!config.username) throw badRequest('WebDAV 账号不能为空');
  if (!config.password) throw badRequest('WebDAV 密码不能为空');

  const { dirUrl } = normalizeWebdavUrls(config.url, config.path);
  const authHeader = basicAuthHeader(config.username, config.password);

  await ensureRemoteDir(dirUrl, authHeader);

  // 写入探针文件测试写权限
  const probeName = `suenmoney-probe-${Date.now()}.tmp`;
  const probeUrl = `${dirUrl}${probeName}`;
  const putRes = await fetch(probeUrl, {
    method: 'PUT',
    headers: {
      Authorization: authHeader,
      'Content-Type': 'text/plain; charset=utf-8',
    },
    body: 'probe',
  });

  if (putRes.status !== 200 && putRes.status !== 201 && putRes.status !== 204) {
    throw new Error(`WebDAV 写入测试失败（HTTP ${putRes.status}）`);
  }

  // 清除探针文件
  await fetch(probeUrl, {
    method: 'DELETE',
    headers: { Authorization: authHeader },
  }).catch(() => {});

  return { ok: true, message: 'WebDAV 连接与写入权限测试成功' };
}

/**
 * 执行一次 WebDAV 备份并轮转清理（仅保留最近 3 天备份）。
 */
export async function runWebdavBackup(
  db: DatabaseSync,
  configOverride?: WebdavConfig,
): Promise<{ filename: string; sizeBytes: number; uploadedAt: string }> {
  const cfg = configOverride ?? getWebdavConfig(db);
  if (!cfg || !cfg.url || !cfg.username || !cfg.password) {
    throw badRequest('尚未配置 WebDAV 服务器或配置不完整');
  }

  const { dirUrl } = normalizeWebdavUrls(cfg.url, cfg.path);
  const authHeader = basicAuthHeader(cfg.username, cfg.password);

  await ensureRemoteDir(dirUrl, authHeader);

  // 生成本地一致性快照
  const snapshot = createSnapshot(db);
  const localFilePath = getSnapshotPath(snapshot.filename);
  if (!localFilePath) {
    throw new Error('生成数据库快照失败');
  }

  const fileBuffer = readFileSync(localFilePath);
  const targetFilename = snapshot.filename.replace(/^suenmoney-snapshot-/, 'suenmoney-backup-');
  const targetFileUrl = `${dirUrl}${targetFilename}`;

  const putRes = await fetch(targetFileUrl, {
    method: 'PUT',
    headers: {
      Authorization: authHeader,
      'Content-Type': 'application/x-sqlite3',
      'Content-Length': String(fileBuffer.length),
    },
    body: fileBuffer,
  });

  if (putRes.status !== 200 && putRes.status !== 201 && putRes.status !== 204) {
    const errorText = await putRes.text().catch(() => '');
    const err = `上传快照到 WebDAV 失败（HTTP ${putRes.status}）：${errorText.slice(0, 100)}`;
    saveWebdavStatus(db, {
      lastBackupAt: new Date().toISOString(),
      lastBackupStatus: 'error',
      lastBackupMessage: err,
      lastBackupFilename: targetFilename,
    });
    throw new Error(err);
  }

  // 轮转清理远程旧备份：只保留最近 3 天（3 份）
  try {
    const listRes = await fetch(dirUrl, {
      method: 'PROPFIND',
      headers: {
        Authorization: authHeader,
        Depth: '1',
      },
    });
    if (listRes.status === 207 || listRes.status === 200) {
      const xml = await listRes.text();
      const hrefs = extractBackupHrefs(xml);
      const backupNames = [
        ...new Set(
          hrefs
            .map((h) => {
              const segs = h.split('/');
              return segs[segs.length - 1] || segs[segs.length - 2] || '';
            })
            .filter((name) => /^suenmoney-(?:backup|snapshot)-[\w.-]+\.sqlite$/.test(name)),
        ),
      ];
      backupNames.sort((a, b) => b.localeCompare(a)); // 按时间倒序，最新的在前

      const KEEP_COUNT = 3;
      if (backupNames.length > KEEP_COUNT) {
        const toDelete = backupNames.slice(KEEP_COUNT);
        for (const oldFile of toDelete) {
          await fetch(`${dirUrl}${oldFile}`, {
            method: 'DELETE',
            headers: { Authorization: authHeader },
          }).catch(() => {});
        }
      }
    }
  } catch (pruneErr) {
    console.warn('WebDAV 远程旧备份清理警告：', pruneErr);
  }

  const uploadedAt = new Date().toISOString();
  saveWebdavStatus(db, {
    lastBackupAt: uploadedAt,
    lastBackupStatus: 'success',
    lastBackupMessage: '备份成功',
    lastBackupFilename: targetFilename,
  });

  return {
    filename: targetFilename,
    sizeBytes: fileBuffer.length,
    uploadedAt,
  };
}

let webdavSchedulerTimer: NodeJS.Timeout | null = null;

/** 检查今天是否已有 WebDAV 备份，若无且已启用则执行 */
export async function runDailyWebdavBackupCheck(db: DatabaseSync): Promise<void> {
  try {
    const cfg = getWebdavConfig(db);
    if (!cfg || !cfg.isEnabled || !cfg.url || !cfg.username || !cfg.password) {
      return;
    }

    const status = getWebdavStatus(db);
    const todayStr = new Date().toISOString().slice(0, 10);
    if (status.lastBackupAt && status.lastBackupAt.startsWith(todayStr) && status.lastBackupStatus === 'success') {
      return;
    }

    await runWebdavBackup(db, cfg);
  } catch (error) {
    console.error('执行 WebDAV 每日自动备份失败：', error);
  }
}

/** 启动每日 WebDAV 备份轮询调度器（每小时检查一次今天是否已备份） */
export function startDailyWebdavScheduler(db: DatabaseSync): NodeJS.Timeout {
  void runDailyWebdavBackupCheck(db);

  if (webdavSchedulerTimer) {
    clearInterval(webdavSchedulerTimer);
  }
  webdavSchedulerTimer = setInterval(() => {
    void runDailyWebdavBackupCheck(db);
  }, 60 * 60 * 1000);

  webdavSchedulerTimer.unref();
  return webdavSchedulerTimer;
}

export function stopDailyWebdavScheduler(): void {
  if (webdavSchedulerTimer) {
    clearInterval(webdavSchedulerTimer);
    webdavSchedulerTimer = null;
  }
}
