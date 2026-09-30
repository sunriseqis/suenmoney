import { request, resolveUrl } from './client';

export type UpdatePlatform = 'android' | 'ios';

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
  latest: UpdateArtifact;
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
