/**
 * 运行时配置。
 *
 * 全部来自环境变量，每项都有安全的内置默认值 —— 没写 .env 也能直接跑起来。
 */
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

export const config = {
  host: str('SUENMONEY_HOST', '0.0.0.0'),
  port: num('SUENMONEY_PORT', 3310),

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

  /** Android / iOS 客户端自动更新（对接 UGREEN 私有云分享源） */
  updateUgreenBaseUrl: str(
    'SUENMONEY_UPDATE_UGREEN_BASE_URL',
    'https://suenqi.cn35.ug.link/ugreen/v1',
  ),
  updateShareId: str(
    'SUENMONEY_UPDATE_SHARE_ID',
    '87870bfaf0cf4e078326b43c063afa1e',
  ),
  updateSharePath: str(
    'SUENMONEY_UPDATE_SHARE_PATH',
    '/home/suenqi/应用/SuenApp/SuenMoney',
  ),
  updateVersionCode: num('SUENMONEY_UPDATE_VERSION_CODE', 0),
  updateSha256: str('SUENMONEY_UPDATE_SHA256', '').toLowerCase(),
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
