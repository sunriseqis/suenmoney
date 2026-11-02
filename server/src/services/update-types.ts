/**
 * 更新通道的公共类型与平台判定（与具体来源解耦）。
 *
 * 来源只有两种：GitHub Releases（`sunriseqis/suenapp`）与关闭。
 *
 * 三端产物命名**完全一致**：`suenmoney-<版本>.<ext>`（全小写、无 v 前缀、
 * 无 -release/-unsigned 后缀）。统一之后这里只需一条匹配规则，
 * 不会再出现「某个端的包名改了就静默匹配不上」。
 */

/**
 * 更新通道面向的平台。
 *
 * `android` 在 2.0 未重构、暂无计划，但枚举值保留 —— 删掉会让老客户端拿到
 * `invalid_platform`，比「已停止更新」更难懂。
 */
export type UpdatePlatform = 'android' | 'ios' | 'harmony' | 'fnos';

/** 平台 → 产物扩展名 */
export const PLATFORM_EXTENSION: Record<UpdatePlatform, string> = {
  android: 'apk',
  ios: 'ipa',
  harmony: 'hap',
  fnos: 'fpk',
};

/** 产物下载时的 MIME。-octet-stream：系统不解析、原样落盘，侧签工具按扩展名接管 */
export const PLATFORM_CONTENT_TYPE: Record<UpdatePlatform, string> = {
  android: 'application/vnd.android.package-archive',
  ios: 'application/octet-stream',
  harmony: 'application/octet-stream',
  fnos: 'application/octet-stream',
};

/** 一个已就绪的更新产物 */
export interface UpdateArtifact {
  fileName: string;
  /** 本地缓存里的绝对路径 */
  path: string;
  versionName: string;
  /** GitHub 没有 versionCode；恒为 0，路由层会退回按 versionName 比较 */
  versionCode: number;
  size: number;
  sha256: string | null;
}

export function isUpdatePlatform(value: unknown): value is UpdatePlatform {
  return value === 'android' || value === 'ios' || value === 'harmony' || value === 'fnos';
}

/** semver 比较（a>b 返回正数） */
export function compareVersionName(a: string, b: string): number {
  const aa = a.split('.').map(Number);
  const bb = b.split('.').map(Number);
  const n = Math.max(aa.length, bb.length);
  for (let i = 0; i < n; i++) {
    const av = aa[i] ?? 0;
    const bv = bb[i] ?? 0;
    if (av !== bv) return av > bv ? 1 : -1;
  }
  return 0;
}

/**
 * versionName → versionCode（与客户端 / CI 同一公式）：
 *     major*1_000_000 + minor*10_000 + patch*100
 *
 * 服务端不依赖上游给的 code（GitHub 恒 0），一律自己推导 → 版本比较只有一个轴。
 * 越界（如 minor ≥ 100）时回落 0，路由层再退回按版本名比较兜底。
 */
export function versionCodeOf(versionName: string): number {
  const parts = versionName.split('.').map(Number);
  const major = parts[0] ?? 0;
  const minor = parts[1] ?? 0;
  const patch = parts[2] ?? 0;
  if (![major, minor, patch].every(Number.isInteger)) return 0;
  if (minor >= 100 || patch >= 100) return 0;
  const code = major * 1_000_000 + minor * 10_000 + patch * 100;
  return code > 0 && code <= 2_147_483_647 ? code : 0;
}

/** 三端统一的产物名：`suenmoney-<版本>.<ext>` */
export function artifactName(versionName: string, platform: UpdatePlatform): string {
  return `suenmoney-${versionName}.${PLATFORM_EXTENSION[platform]}`;
}

/**
 * 本项目的 tag 前缀。
 *
 * ⚠ `sunriseqis/suenapp` 是 suenmusic / suenweb / suenmoney **共用**的发行仓库：
 *   suenmusic → `v2.1.3`
 *   suenweb   → `suenweb-v2.0.0`
 *   suenmoney → `suenmoney-v2.0.0`
 *
 * 不按前缀过滤的话，会把 **suenmusic 的版本号当成 suenmoney 的新版本**
 *（实测：不滤会把 v2.1.3 报成「有新版本」）。
 */
export const TAG_PREFIX = 'suenmoney-';

export function isOurTag(tag: string): boolean {
  return tag.trim().toLowerCase().startsWith(TAG_PREFIX);
}

/** 从 release tag 里取版本号（兼容 `suenmoney-v2.0.0` 与 `suenmoney-2.0.0`） */
export function versionFromTag(tag: string): string | null {
  const m = /(\d+(?:\.\d+)+)$/.exec(tag.trim());
  return m === null ? null : (m[1] ?? null);
}
