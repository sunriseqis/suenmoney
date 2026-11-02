/**
 * 运行时配置。
 *
 * 全部来自环境变量，每项都有安全的内置默认值 —— 没写 .env 也能直接跑起来。
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function str(name: string, fallback: string): string {
  const raw = process.env[name];
  return raw === undefined || raw.trim() === '' ? fallback : raw.trim();
}

function num(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) {
    throw new Error(`环境变量 ${name} 不是有效数字：${raw}`);
  }
  return parsed;
}

function bool(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw.trim().toLowerCase());
}

function list(name: string): string[] {
  return str(name, '')
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item !== '');
}

/**
 * 取版本号：仓库根目录的 `VERSION` 文件（`npm --prefix server run start` 时 cwd 是 server/，
 * 容器里 cwd 是 /app/server，两种都覆盖）。读不到不算错误 —— 版本只用于展示与探活。
 */
function readVersionFile(): string {
  for (const candidate of ['../VERSION', 'VERSION', '../../VERSION']) {
    try {
      const raw = readFileSync(resolve(process.cwd(), candidate), 'utf8').trim();
      if (raw !== '') return raw;
    } catch {
      // 下一个候选
    }
  }
  return 'unknown';
}

export const config = {
  host: str('SUENMONEY_HOST', '0.0.0.0'),
  port: num('SUENMONEY_PORT', 3310),

  /**
   * 前端产物目录。服务端同时充当静态服务器（一个端口 = 页面 + 接口）。
   *
   * 目录里没有 `index.html` 时**自动退化为纯 API 服务** —— 测试、只跑接口的调试场景
   * 都靠这条规则（见 `src/http/server.ts`），因此它缺失不是错误。
   */
  webRoot: resolve(str('SUENMONEY_WEB_ROOT', '../web/dist')),

  /**
   * 是否信任 `X-Forwarded-For`。
   *
   * 默认**关**：单容器部署时服务端就在最前面，信任 XFF 等于允许任何客户端伪造来源 IP，
   * 从而绕过登录限流（`lib/rate-limit.ts` 按 IP 计数）。
   * 只有「前面还挂着一层反代」（用户自己加 Caddy / nginx 做 TLS）时才显式打开。
   */
  trustProxy: bool('SUENMONEY_TRUST_PROXY', false),

  /**
   * 对外呈现的版本号，用于 `/api/health`。原生端探活要校验「是不是本产品、版本对不对」，
   * 飞牛套件升级后的健康检查也读它。构建时用 `SUENMONEY_VERSION` 注入，
   * 取不到退回仓库根目录的 `VERSION` 文件，再取不到就是 `unknown`。
   */
  version: str('SUENMONEY_VERSION', readVersionFile()),

  /** SQLite 单文件库。备份 = 复制这一个文件。 */
  dbPath: resolve(str('SUENMONEY_DB_PATH', './data/suenmoney.sqlite')),

  corsOrigins: list('SUENMONEY_CORS_ORIGINS'),

  /**
   * 会话令牌有效期。很长是有意的 —— 家庭自用，「过几天就要求重新登录」是纯粹的骚扰。
   * 安全性由「令牌只存哈希 + 可单独吊销」保证，而不是靠短有效期。
   */
  sessionDays: num('SUENMONEY_SESSION_DAYS', 180),

  /** 默认关闭：账号只由管理员在 Web 后台创建，不对公网开放注册。 */
  allowRegistration: bool('SUENMONEY_ALLOW_REGISTRATION', false),

  backupDir: resolve(str('SUENMONEY_BACKUP_DIR', './data/backups')),
  backupKeep: num('SUENMONEY_BACKUP_KEEP', 14),

  /**
   * 更新通道。来源只有两种：`github`（Releases）与 `off`。
   *
   * 三端产物都在 `sunriseqis/suenapp`，命名统一为 `suenmoney-<版本>.<ext>`。
   * 服务端把产物拉到本地缓存，客户端从本地下载 —— 不直连 GitHub（国内极不稳定，
   * 且系统浏览器/侧签工具发不出鉴权头）。
   */
  updateSource: (str('SUENMONEY_UPDATE_SOURCE', 'github').trim().toLowerCase() === 'off'
    ? 'off'
    : 'github') as 'github' | 'off',
  /** GitHub 仓库（`owner/repo`） */
  updateGithubRepo: str('SUENMONEY_UPDATE_GITHUB_REPO', 'sunriseqis/suenapp').trim(),
  /** 私有仓库才需要；公开仓库留空即可（未配时走匿名，限额 60 次/小时） */
  updateGithubToken: str('SUENMONEY_UPDATE_GITHUB_TOKEN', '').trim(),
  /** API 基地址（国内反代用）；默认官方地址 */
  updateGithubApiBase: str('SUENMONEY_UPDATE_GITHUB_API_BASE', '').trim(),
  /** 产物缓存目录（每个平台一个子目录） */
  updateCacheDir: resolve(str('SUENMONEY_UPDATE_CACHE_DIR', './data/updates')),
  /**
   * 下载令牌签名密钥。留空则每次启动随机生成（进程重启后旧令牌失效，
   * 但令牌只有 30 分钟寿命，影响可忽略）。多副本部署时应显式配置。
   */
  updateSecret: str('SUENMONEY_UPDATE_SECRET', ''),
} as const;

/**
 * 注意：这里**没有时区配置**，是刻意的。
 *
 * 业务日期一律以 'YYYY-MM-DD' 字符串落库，「今天」由客户端按本地时区判定后传入，
 * 服务端从不自行推算业务日期，也不做任何时区换算 —— 所以不存在
 * 「容器跑 UTC 导致日切错位」这类问题，不需要 TZ 兜底代码。
 * 审计时间戳（created_at/updated_at）统一 UTC ISO8601，只用于排序与追溯。
 */
