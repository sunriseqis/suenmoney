import { config } from '../config.ts';

const META_CACHE_MS = 5 * 60 * 1000;
const MAX_SUBDIRS = 20;
const PATH_NOT_EXIST_CODE = 1365;

export type UpdatePlatform = 'android' | 'ios';

const ARTIFACT_PATTERNS: Record<UpdatePlatform, RegExp> = {
  android: /^SuenMoney-v(\d+(?:\.\d+)*)-release\.apk$/i,
  ios: /^SuenMoney-v(\d+(?:\.\d+)*)-release\.ipa$/i,
};

const MAX_ARTIFACT_BYTES: Record<UpdatePlatform, number> = {
  android: 100 * 1024 * 1024,
  ios: 200 * 1024 * 1024,
};

const ARTIFACT_LABEL: Record<UpdatePlatform, string> = {
  android: 'APK',
  ios: 'IPA',
};

export function isUpdatePlatform(value: unknown): value is UpdatePlatform {
  return value === 'android' || value === 'ios';
}

type UgreenEnvelope<T> = { code?: number; msg?: string; data?: T };
interface ShareFile {
  path?: string;
  name?: string;
  size?: number;
  file_type?: number;
}
interface FileListData {
  files?: ShareFile[];
}
interface VerifyData {
  status?: number;
  file_info?: ShareFile[];
}
interface AddPathData {
  result?: string;
}

class UgreenListError extends Error {
  readonly code: number;

  constructor(message: string, code: number) {
    super(message);
    this.name = 'UgreenListError';
    this.code = code;
  }
}

export interface UpdateArtifact {
  fileName: string;
  path: string;
  versionName: string;
  versionCode: number;
  size: number;
  sha256: string | null;
}

let shareCookie = '';
let verifyPromise: Promise<string> | null = null;
const cached: Partial<Record<UpdatePlatform, { artifact: UpdateArtifact; expiresAt: number }>> = {};

function configured(): void {
  if (!config.updateShareId) throw new Error('更新服务未配置分享 ID');
}

function apiUrl(path: string): string {
  return `${config.updateUgreenBaseUrl.replace(/\/+$/, '')}${path}`;
}

function shareReferer(): string {
  const u = new URL(config.updateUgreenBaseUrl);
  return `${u.origin}/filemgr/share-download/?id=${encodeURIComponent(config.updateShareId)}`;
}

function headers(cookie = shareCookie): Record<string, string> {
  const result: Record<string, string> = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    Origin: new URL(config.updateUgreenBaseUrl).origin,
    Referer: shareReferer(),
    'UG-Agent': 'PC/WEB',
    'X-Specify-Language': 'zh-CN',
  };
  if (cookie) result.Cookie = cookie;
  return result;
}

async function requestUgreen<T>(
  url: string,
  options: {
    method?: string;
    headers?: Record<string, string>;
    body?: unknown;
    timeoutMs?: number;
  } = {},
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? 10_000);
  const init: RequestInit = {
    method: options.method ?? 'GET',
    signal: controller.signal,
  };
  if (options.headers) init.headers = options.headers;
  if (options.body !== undefined) init.body = JSON.stringify(options.body);

  try {
    const res = await fetch(url, init);
    return res;
  } finally {
    clearTimeout(timer);
  }
}

async function readEnvelope<T>(res: Response): Promise<UgreenEnvelope<T>> {
  const text = await res.text();
  if (!res.ok) throw new Error(`UGREEN HTTP ${res.status}`);
  try {
    return JSON.parse(text) as UgreenEnvelope<T>;
  } catch {
    throw new Error('UGREEN 返回了非法 JSON');
  }
}

function cookieFromResponse(res: Response): string {
  const h = res.headers as Headers & { getSetCookie?: () => string[] };
  const values = h.getSetCookie?.() ?? [];
  const value = values.find((v) => v.startsWith('share_cookie_')) ?? '';
  return value.split(';', 1)[0] ?? '';
}

async function verifyShare(): Promise<string> {
  configured();
  if (shareCookie) return shareCookie;
  if (verifyPromise) return verifyPromise;

  verifyPromise = (async () => {
    const res = await requestUgreen(apiUrl('/filemgr/externalVerifySharePassword'), {
      method: 'POST',
      headers: headers(''),
      body: { share_id: config.updateShareId, password: '', no_count: false },
      timeoutMs: 10_000,
    });
    const envelope = await readEnvelope<VerifyData>(res);
    if (envelope.code !== 200 || envelope.data?.status !== 0) {
      throw new Error(`UGREEN 分享验证失败：${envelope.msg ?? '未知错误'}`);
    }
    const cookie = cookieFromResponse(res);
    if (!cookie) throw new Error('UGREEN 分享验证未返回访问凭据');
    shareCookie = cookie;
    return cookie;
  })();

  try {
    return await verifyPromise;
  } finally {
    verifyPromise = null;
  }
}

function parseVersion(name: string, platform: UpdatePlatform): string | null {
  const match = ARTIFACT_PATTERNS[platform].exec(name);
  return match?.[1] ?? null;
}

export function compareVersions(a: string, b: string): number {
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

async function listFiles(cookie: string, path: string): Promise<ShareFile[]> {
  const res = await requestUgreen(apiUrl('/filemgr/getShearDirFileList'), {
    method: 'POST',
    headers: headers(cookie),
    body: {
      share_id: config.updateShareId,
      password: '',
      path,
      page: 1,
      limit: 1000,
      sort_type: 1,
      as_dir: false,
      reverse: false,
      file_exts: [],
    },
    timeoutMs: 10_000,
  });
  const envelope = await readEnvelope<FileListData>(res);
  if (envelope.code !== 200 || !envelope.data?.files) {
    throw new UgreenListError(
      `UGREEN 文件列表失败(${envelope.code ?? '?'})：${envelope.msg ?? '未知错误'}`,
      envelope.code ?? 0,
    );
  }
  return envelope.data.files;
}

async function listFilesWithRetry(path: string): Promise<ShareFile[]> {
  try {
    return await listFiles(await verifyShare(), path);
  } catch (err) {
    shareCookie = '';
    try {
      return await listFiles(await verifyShare(), path);
    } catch {
      throw err;
    }
  }
}

async function collectCandidates(
  platform: UpdatePlatform,
): Promise<Array<{ file: ShareFile; versionName: string }>> {
  const root = await listFilesWithRetry(config.updateSharePath);
  const dirs = root
    .filter((dir) => dir.file_type === 1 && typeof dir.name === 'string')
    .slice(0, MAX_SUBDIRS);

  const settled = await Promise.allSettled(
    dirs.map((dir) =>
      listFilesWithRetry(dir.path ?? `${config.updateSharePath.replace(/\/$/, '')}/${dir.name}`),
    ),
  );
  const all: ShareFile[] = [...root];
  for (const result of settled) {
    if (result.status === 'fulfilled') {
      all.push(...result.value);
      continue;
    }
    if (result.reason instanceof UgreenListError && result.reason.code === PATH_NOT_EXIST_CODE) {
      continue;
    }
    throw result.reason;
  }

  return all
    .filter(
      (file) =>
        file.file_type === 0 &&
        typeof file.name === 'string' &&
        parseVersion(file.name, platform),
    )
    .map((file) => ({ file, versionName: parseVersion(file.name!, platform)! }))
    .sort((a, b) => compareVersions(b.versionName, a.versionName));
}

export async function getLatestUpdateArtifact(
  platform: UpdatePlatform = 'android',
  force = false,
): Promise<UpdateArtifact> {
  configured();
  const hit = cached[platform];
  if (!force && hit && hit.expiresAt > Date.now()) return hit.artifact;

  const candidates = await collectCandidates(platform);
  if (candidates.length === 0) {
    throw new Error(`更新目录中没有有效的 SuenMoney release ${ARTIFACT_LABEL[platform]}`);
  }

  const selected = candidates[0]!;
  const fileName = selected.file.name!;
  const path = selected.file.path ?? `${config.updateSharePath.replace(/\/$/, '')}/${fileName}`;
  if (selected.file.size && selected.file.size > MAX_ARTIFACT_BYTES[platform]) {
    throw new Error(`更新 ${ARTIFACT_LABEL[platform]} 超过允许大小`);
  }

  const artifact: UpdateArtifact = {
    fileName,
    path,
    versionName: selected.versionName,
    versionCode: platform === 'android' ? config.updateVersionCode : 0,
    size: Number(selected.file.size ?? 0),
    sha256: platform === 'android' ? config.updateSha256 || null : null,
  };
  cached[platform] = { artifact, expiresAt: Date.now() + META_CACHE_MS };
  return artifact;
}

export function clearUpdateCache(): void {
  for (const key of Object.keys(cached) as UpdatePlatform[]) delete cached[key];
  shareCookie = '';
}

export async function openUpdateDownload(
  platform: UpdatePlatform = 'android',
): Promise<{ response: Response; artifact: UpdateArtifact }> {
  const artifact = await getLatestUpdateArtifact(platform, true);
  const cookie = await verifyShare();
  const addRes = await requestUgreen(apiUrl('/filemgr/addPathsByShareId'), {
    method: 'POST',
    headers: headers(cookie),
    body: { paths: [artifact.path], share_id: config.updateShareId },
    timeoutMs: 10_000,
  });
  const add = await readEnvelope<AddPathData>(addRes);
  if (add.code !== 200 || !add.data?.result) {
    throw new Error(`UGREEN 下载任务创建失败：${add.msg ?? '未知错误'}`);
  }

  const downloadUrl = new URL(apiUrl('/filemgr/shareDownloadFile'));
  downloadUrl.searchParams.set('coding', 'true');
  downloadUrl.searchParams.set('share_id', config.updateShareId);
  downloadUrl.searchParams.set('password', '');
  downloadUrl.searchParams.set('task_id', add.data.result);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 60_000);
  try {
    const response = await fetch(downloadUrl.toString(), {
      headers: { Accept: acceptHeader(platform), Cookie: shareCookie },
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!response.ok || !response.body) {
      throw new Error(`UGREEN ${ARTIFACT_LABEL[platform]} 下载失败：HTTP ${response.status}`);
    }
    return { response, artifact };
  } catch (err) {
    clearTimeout(timer);
    throw err;
  }
}

function acceptHeader(platform: UpdatePlatform): string {
  return platform === 'android'
    ? 'application/vnd.android.package-archive'
    : 'application/octet-stream';
}
