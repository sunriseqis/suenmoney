import { request, resolveUrl } from './client';

export type UpdatePlatform = 'android' | 'ios' | 'harmony' | 'fnos';

export interface UpdateArtifact {
  fileName: string;
  path: string;
  versionName: string;
  versionCode: number;
  size: number;
  sha256: string | null;
}

export interface UpdateCheckResult {
  available: boolean;
  current: { versionName: string; versionCode: number };
  latest: UpdateArtifact | null;
  downloadPath: string;
  downloadToken: string;
}

export function checkUpdate(
  version: { versionName: string; versionCode: number },
  opts: { force?: boolean; platform?: UpdatePlatform } = {},
): Promise<UpdateCheckResult> {
  return request<UpdateCheckResult>('/api/update/check', {
    method: 'GET',
    query: {
      version_name: version.versionName,
      version_code: version.versionCode,
      platform: opts.platform ?? 'android',
      force: opts.force ? 1 : undefined,
    },
  });
}

export function getFullDownloadUrl(checkResult: UpdateCheckResult, platform: UpdatePlatform = 'android'): string {
  const query = `platform=${encodeURIComponent(platform)}&token=${encodeURIComponent(checkResult.downloadToken)}`;
  const connector = checkResult.downloadPath.includes('?') ? '&' : '?';
  return resolveUrl(`${checkResult.downloadPath}${connector}${query}`);
}

/**
 * **服务端自身（套件）**的更新检查。
 *
 * 与上面 `checkUpdate`（原生壳检查 App 更新）是两件事：
 *   · fnOS 部署 → 服务端把新 `.fpk` 拉到本地缓存，界面提示下载后手动覆盖安装；
 *   · Docker 部署 → 只比对版本，提示「去拉新镜像」，不下载 `.fpk`。
 */
export interface ServerUpdateResult {
  available: boolean;
  currentVersion: string;
  latestVersion: string;
  deployMode: 'fnos' | 'docker';
  artifact: { fileName: string; size: number } | null;
}

export function checkServerUpdate(force = false): Promise<ServerUpdateResult> {
  return request<ServerUpdateResult>('/api/admin/server-update', {
    method: 'GET',
    query: { force: force ? 1 : undefined },
  });
}

/** 套件包下载直链（带短期令牌；浏览器发不出鉴权头） */
export function serverDownloadUrl(result: ServerUpdateResult): string {
  if (!result.artifact) return '';
  return resolveUrl(
    `/api/update/download/${encodeURIComponent(result.artifact.fileName)}`
    + `?platform=fnos&token=${encodeURIComponent((result as unknown as { downloadToken?: string }).downloadToken ?? '')}`,
  );
}
