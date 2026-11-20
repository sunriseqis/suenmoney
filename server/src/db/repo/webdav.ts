/**
 * WebDAV 远程安全备份管理。
 *
 * 核心机制：
 * 1. 采用 SQLite 原生 VACUUM INTO 生成完整的一致性物理库快照；
 * 2. 通过 WebDAV 协议（PUT）上传至用户自建/托管的 WebDAV 存储（如坚果云、Nextcloud、NAS、Alist 等）；
 * 3. 严格保留最近 3 天（3 份）的远程备份，通过 PROPFIND 与 DELETE 自动轮转删除超期备份；
 * 4. 每日定时后台轮询自动备份，防止服务器单点灾难。
 */
import type { DatabaseSync } from 'node:sqlite';

import { badGateway, badRequest } from '../../lib/http-error.ts';
import { buildPackage } from './transfer.ts';
import { MnFormatError, mnFileName, packMn, unpackMn } from '../../lib/backup-crypto.ts';

export interface WebdavConfig {
  url: string;
  username: string;
  password?: string;
  path: string;
  isEnabled: boolean;
  /**
   * 备份加密口令。**必填**：推到远端的 JSON 含整库与口令哈希，
   * 不明文落第三方存储（见 lib/backup-crypto.ts）。
   */
  passphrase?: string;
}

export interface WebdavStatus {
  lastBackupAt: string | null;
  lastBackupStatus: 'success' | 'error' | null;
  lastBackupMessage: string | null;
  lastBackupFilename: string | null;
}

const CONFIG_KEY = 'webdav_backup_config';
const STATUS_KEY = 'webdav_backup_status';

/**
 * 备份口令最短长度。
 *
 * 6 位是**产品裁决**（2026-11-19）：口令只防「备份文件落到第三方存储后被直接读」，
 * 家庭场景下再长用户就记不住了，记不住 = 备份解不开 = 比不加密更糟。
 * 前端提示与服务端校验共用这一个常量，避免两处各写一个数字后悄悄漂移。
 */
export const MIN_PASSPHRASE_LENGTH = 6;

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

/**
 * 出网请求的统一超时。
 *
 * 没有超时的话，远端 WebDAV 挂住（防火墙吞包、反代不回）会让「立即备份」那个
 * 请求一直悬着、前端无限转圈，定时任务也一样卡死。15s 是「家庭 NAS 走公网」的
 * 经验上限，正常上传大文件不受影响 —— 超时只约束「拿到响应头」之前。
 */
const WEBDAV_TIMEOUT_MS = 15_000;

/**
 * 把 fetch 抛出的底层错误翻译成人能看懂的一句话。
 *
 * Node 的 fetch 只给 `TypeError: fetch failed`，真正的原因埋在 `cause` 里
 * （`getaddrinfo ENOTFOUND` / `ECONNREFUSED` / 证书错误 …）。不翻译的话，
 * 用户只能看到一个 500「服务器内部错误」，完全不知道该改地址、改端口还是改证书。
 */
function describeFetchError(error: unknown): string {
  const cause = (error as { cause?: { code?: string; message?: string } } | undefined)?.cause;
  const code = cause?.code ?? '';
  const raw = cause?.message ?? (error instanceof Error ? error.message : String(error));

  if (error instanceof Error && (error.name === 'TimeoutError' || error.name === 'AbortError')) {
    return `请求超时（${WEBDAV_TIMEOUT_MS / 1000}s 内没有响应）`;
  }
  if (code === 'ENOTFOUND' || code === 'EAI_AGAIN') {
    return '域名解析失败，检查 WebDAV 地址是否写错';
  }
  if (code === 'ECONNREFUSED') {
    return '连接被拒绝，检查主机端口与 WebDAV 服务是否在运行';
  }
  if (code === 'ECONNRESET' || code === 'ETIMEDOUT') {
    return '连接被重置或超时，检查网络与反向代理';
  }
  if (code === 'EHOSTUNREACH' || code === 'ENETUNREACH') {
    return '主机不可达，检查网络路由';
  }
  if (/CERT|SELF_SIGNED|UNABLE_TO_VERIFY/i.test(code) || /certificate/i.test(raw)) {
    return '证书校验失败（自签证书需要在服务端受信，或改用 http）';
  }
  return raw;
}

/**
 * 所有 WebDAV 出网请求的唯一入口。
 *
 * 统一做两件事：**加超时**、**把失败翻译成有信息量的 HttpError**。
 * 之前各调用点直接 `fetch` + `throw new Error(...)`，被 Fastify 兜成
 * `500 服务器内部错误` —— 用户拿不到「认证失败 / 404 / 空间不足」这种可行动提示，
 * 而且没有超时，远端挂住时请求会一直悬着。
 */
async function webdavFetch(url: string, init: RequestInit, action: string): Promise<Response> {
  try {
    return await fetch(url, { ...init, signal: AbortSignal.timeout(WEBDAV_TIMEOUT_MS) });
  } catch (error) {
    throw badGateway(`无法连接 WebDAV 服务器（${action}）：${describeFetchError(error)}`);
  }
}

/**
 * 远端返回非预期状态码时的提示。
 *
 * 分两类：**用户能自己修的**（地址/账号/权限/空间）给 400，让前端原样展示；
 * **远端自己出问题**（5xx）给 502 —— 那是「上游挂了」，不是用户配错了。
 */
function throwForStatus(status: number, action: string): never {
  if (status === 401 || status === 403) {
    throw badRequest(
      `WebDAV 拒绝认证（HTTP ${status}，${action}）：用户名或密码不对，或该账号没有这个目录的读写权限`,
    );
  }
  if (status === 404) {
    throw badRequest(`远端路径不存在（HTTP 404，${action}）：检查 WebDAV 地址与「远端目录」是否填错`);
  }
  if (status === 405) {
    throw badRequest(`远端不允许该操作（HTTP 405，${action}）：该地址可能不是 WebDAV 端点`);
  }
  if (status === 409) {
    throw badRequest(`远程目录的上级不存在（HTTP 409，${action}）：先建好上级目录，或把「远端目录」改浅一层`);
  }
  if (status === 423) {
    throw badRequest(`远端文件被锁定（HTTP 423，${action}）：稍后重试，或先删掉同名的锁文件`);
  }
  if (status === 507) {
    throw badRequest(`远端存储空间不足（HTTP 507，${action}）：清理网盘空间后重试`);
  }
  if (status >= 500) {
    throw badGateway(`WebDAV 服务器内部错误（HTTP ${status}，${action}）：稍后重试，或检查网盘服务状态`);
  }
  throw badRequest(`WebDAV 返回了意外的状态码 HTTP ${status}（${action}）`);
}

/** 确保远程 WebDAV 目录存在，若不存在则创建 */
async function ensureRemoteDir(dirUrl: string, authHeader: string): Promise<void> {
  const checkRes = await webdavFetch(
    dirUrl,
    { method: 'PROPFIND', headers: { Authorization: authHeader, Depth: '0' } },
    '检查远程目录',
  );

  if (checkRes.status === 200 || checkRes.status === 207) {
    return;
  }
  if (checkRes.status === 404) {
    const mkRes = await webdavFetch(
      dirUrl,
      { method: 'MKCOL', headers: { Authorization: authHeader } },
      '创建远程目录',
    );
    // 405 = 已存在（有些服务端不用 201）；200 也当成功
    if (mkRes.status === 201 || mkRes.status === 200 || mkRes.status === 405) {
      return;
    }
    throwForStatus(mkRes.status, '创建远程目录');
  }
  /*
   * ⚠ 除 207/404 之外的任何状态都必须抛。
   * 旧实现只处理 401/403/404，其它（405/409/500…）会**直接 return**，
   * 于是校验「假装通过」、后面 PUT 再莫名失败，报错位置离真因很远。
   */
  throwForStatus(checkRes.status, '检查远程目录');
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
  const putRes = await webdavFetch(
    probeUrl,
    {
      method: 'PUT',
      headers: {
        Authorization: authHeader,
        'Content-Type': 'text/plain; charset=utf-8',
      },
      body: 'probe',
    },
    '写入探针文件',
  );

  if (putRes.status !== 200 && putRes.status !== 201 && putRes.status !== 204) {
    throwForStatus(putRes.status, '写入探针文件');
  }

  // 清除探针文件（失败不影响结论：能写不能删是「可写目录」的常见形态）
  await webdavFetch(probeUrl, { method: 'DELETE', headers: { Authorization: authHeader } }, '清理探针文件').catch(
    () => {},
  );

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
  // 门禁：没有口令就不许往远端推 —— 明文 JSON 含账号与口令哈希
  if (cfg.passphrase === undefined || cfg.passphrase.trim() === '') {
    throw badRequest('请先设置「备份口令」：推送到 WebDAV 的备份会被口令加密，口令为空不允许上传');
  }

  const { dirUrl } = normalizeWebdavUrls(cfg.url, cfg.path);
  const authHeader = basicAuthHeader(cfg.username, cfg.password);

  /*
   * 目录检查失败也要落一条失败状态。
   * 否则「上次备份」永远停在上一次成功的时间，用户以为一直在正常备份 ——
   * 而实际上从某天起每天都是 401，只是没人看日志。
   */
  try {
    await ensureRemoteDir(dirUrl, authHeader);
  } catch (error) {
    saveWebdavStatus(db, {
      lastBackupAt: new Date().toISOString(),
      lastBackupStatus: 'error',
      lastBackupMessage: error instanceof Error ? error.message : String(error),
      lastBackupFilename: null,
    });
    throw error;
  }

  // 生成「整库 JSON」→ gzip → 口令加密 → .mn
  const pkg = buildPackage(db, { kind: 'all', period: '' }, 'suenmoney-backup');
  const fileBuffer = packMn(JSON.stringify(pkg), cfg.passphrase);

  const targetFilename = mnFileName();
  const targetFileUrl = `${dirUrl}${targetFilename}`;

  const putRes = await webdavFetch(
    targetFileUrl,
    {
      method: 'PUT',
      headers: {
        Authorization: authHeader,
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(fileBuffer.length),
      },
      body: fileBuffer,
    },
    '上传加密备份',
  );

  if (putRes.status !== 200 && putRes.status !== 201 && putRes.status !== 204) {
    const errorText = (await putRes.text().catch(() => '')).trim().slice(0, 100);
    const err = `上传加密备份到 WebDAV 失败（HTTP ${putRes.status}）${errorText ? `：${errorText}` : ''}`;
    saveWebdavStatus(db, {
      lastBackupAt: new Date().toISOString(),
      lastBackupStatus: 'error',
      lastBackupMessage: err,
      lastBackupFilename: targetFilename,
    });
    // 走统一映射：认证/路径/空间问题给 400（用户可自己修），5xx 给 502
    throwForStatus(putRes.status, '上传加密备份');
  }

  // 轮转清理远程旧备份：只保留最近 3 天（3 份）
  try {
    const listRes = await webdavFetch(
      dirUrl,
      { method: 'PROPFIND', headers: { Authorization: authHeader, Depth: '1' } },
      '列出远程备份',
    );
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
            /*
             * ⚠ 后缀必须与 `mnFileName()` 的产物一致（`.mn`）。
             * 曾经的正则是 `\.sqlite$` —— 与实际产物 `.mn` 永远匹配不上，
             * 于是 `backupNames` 恒为空数组、`KEEP_COUNT` 分支永不执行，
             * 远端备份**只增不删**，"只保留最近 3 份"从未生效。
             * 保留 `\.sqlite$` 分支只为清理早期版本留下的旧文件。
             */
            .filter((name) => /^suenmoney-(?:backup|snapshot)-[\w.-]+\.(?:mn|sqlite)$/.test(name)),
        ),
      ];
      backupNames.sort((a, b) => b.localeCompare(a)); // 按时间倒序，最新的在前

      const KEEP_COUNT = 3;
      if (backupNames.length > KEEP_COUNT) {
        const toDelete = backupNames.slice(KEEP_COUNT);
        for (const oldFile of toDelete) {
          // 删旧备份失败不阻断本次备份：留着只是占空间，丢的是「轮转」不是「备份」
          await webdavFetch(
            `${dirUrl}${oldFile}`,
            { method: 'DELETE', headers: { Authorization: authHeader } },
            '删除超期备份',
          ).catch(() => {});
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

/**
 * 取「服务器本地时区」的今天，格式 YYYY-MM-DD。
 *
 * 为什么不能用 `new Date().toISOString().slice(0, 10)`：那是 **UTC** 日期。
 * 容器时区固定为东八区（`server/Dockerfile` 的 `TZ=Asia/Shanghai`），比 UTC 快 8 小时，
 * 于是北京时间 00:00–08:00 之间 UTC 还停在前一天，`todayStr` 会比本地日期晚一天。
 * 「今天已备份」的判断就会把昨天的成功记录当成今天的 → 当天的定时备份被静默跳过，
 * 且不报错（备份列表停在昨天，看起来像正常轮转）。
 *
 * 这里刻意用 Date 的本地 getter（`getFullYear`/`getMonth`/`getDate`）而不是把
 * `Asia/Shanghai` 写死进代码：本地 getter 读的就是进程 TZ，与容器 `TZ` 保持同一口径，
 * 将来改 `TZ` 不用改代码，也不会出现「代码写死 +08:00、容器换时区」两处打架。
 * 每日物理快照调度（`snapshots.ts` 的 `todaySnapshotPrefix`）用的是同一套本地 getter，
 * 两边口径一致。
 */
export function localDateString(d: Date = new Date()): string {
  const yyyy = d.getFullYear();
  const MM = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${MM}-${dd}`;
}

/**
 * 判断「今天是否已成功备份过」。
 *
 * `lastBackupAt` 存的是 UTC ISO 时间戳（`toISOString()`），所以不能直接拿它的日期前缀
 * 和本地日期比 —— 那样等于把「UTC 的今天」和「本地的今天」混在一起。这里统一转成
 * 本地日期再比较，两边同一口径。
 */
export function hasBackedUpToday(status: WebdavStatus, now: Date = new Date()): boolean {
  if (!status.lastBackupAt || status.lastBackupStatus !== 'success') return false;
  const lastBackupDate = new Date(status.lastBackupAt);
  if (Number.isNaN(lastBackupDate.getTime())) return false;
  return localDateString(lastBackupDate) === localDateString(now);
}

/** 检查今天是否已有 WebDAV 备份，若无且已启用则执行 */
export async function runDailyWebdavBackupCheck(db: DatabaseSync): Promise<void> {
  try {
    const cfg = getWebdavConfig(db);
    if (!cfg || !cfg.isEnabled || !cfg.url || !cfg.username || !cfg.password) {
      return;
    }

    if (hasBackedUpToday(getWebdavStatus(db))) {
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
