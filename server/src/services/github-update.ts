/**
 * 更新产物来源：**GitHub Releases（`sunriseqis/suenapp`）**。
 *
 * 流程：列 releases → 找该平台最新产物 → 下到本地缓存 → 客户端从本地下载。
 *
 * 为什么客户端不直连 GitHub：
 *   ① 国内访问 `objects.githubusercontent.com` 极不稳定；
 *   ② 鸿蒙 / iOS 客户端把下载交给**系统浏览器或侧签工具**，那些调用方发不出鉴权头；
 *   ③ 缓存到本地后才能支持断点续传（Range）。
 *
 * 产物命名与 CI 一致：`suenmoney-<版本>.<ext>`（见 `update-types.artifactName`）。
 */

import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { config } from '../config.ts';
import {
  PLATFORM_EXTENSION,
  artifactName,
  compareVersionName,
  isOurTag,
  versionCodeOf,
  versionFromTag,
  type UpdateArtifact,
  type UpdatePlatform,
} from './update-types.ts';
import { getDeployMode } from './deploy-mode.ts';
import { downloadWithMirrors } from './update-mirrors.ts';
import { createLogger } from '../lib/logger.ts';

const log = createLogger('update');

const PER_PAGE = 30;
/** 未完成下载的 `*.part` 保留时长：超过即视为残留（进程被杀 / 断网 / 磁盘满） */
const STALE_PART_MS = 60 * 60 * 1000;

interface GithubAsset {
  name?: string;
  size?: number;
  browser_download_url?: string;
  /** 新版 API 会带 `sha256:<hex>`；没有则留空 */
  digest?: string | null;
}

interface GithubRelease {
  tag_name?: string;
  draft?: boolean;
  prerelease?: boolean;
  published_at?: string;
  assets?: GithubAsset[];
}

function apiBase(): string {
  return (config.updateGithubApiBase || 'https://api.github.com').replace(/\/+$/, '');
}

export function cacheDir(platform: UpdatePlatform): string {
  return resolve(config.updateCacheDir, platform);
}

function latestJsonPath(platform: UpdatePlatform): string {
  return join(cacheDir(platform), 'latest.json');
}

function githubHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'suenmoney-server',
  };
  if (config.updateGithubToken) headers.Authorization = `Bearer ${config.updateGithubToken}`;
  return headers;
}

/**
 * 该平台的产物名是否匹配这个版本。
 *
 * 标准名（2026-11-02 起，CI 统一产出）：`suenmoney-<版本>.<ext>`
 *
 * 同时兼容**统一命名之前**发布的历史产物，否则「改命名那一刻，旧版本用户
 * 就再也检查不到更新了」：
 *
 *     suenmoney-v<版本>.fpk              （fpk 原来带 v）
 *     SuenMoney-v<版本>-release.ipa      （ipa 原来大写 + -release）
 *     SuenMoney-v<版本>-unsigned.hap     （hap 原来大写 + -unsigned）
 *
 * ⚠ 下一次发版（产物已是新名）之后，这三条可以删掉。
 */
const LEGACY_PATTERNS: Record<UpdatePlatform, (v: string) => string[]> = {
  fnos: (v) => [`suenmoney-v${v}.fpk`],
  ios: (v) => [`SuenMoney-v${v}-release.ipa`, `suenmoney-v${v}-release.ipa`],
  harmony: (v) => [`SuenMoney-v${v}-unsigned.hap`, `suenmoney-v${v}-unsigned.hap`],
  android: (v) => [`SuenMoney-v${v}-release.apk`, `suenmoney-v${v}-release.apk`],
};

function isAssetMatch(assetName: string, versionName: string, platform: UpdatePlatform): boolean {
  const name = assetName.toLowerCase();
  const ext = PLATFORM_EXTENSION[platform];
  const standard = [
    `suenmoney-${versionName}.${ext}`,
    `suenmoney-v${versionName}.${ext}`,
  ];
  const legacy = LEGACY_PATTERNS[platform](versionName);
  return [...standard, ...legacy].some((c) => c.toLowerCase() === name);
}

/** 在 release 列表里找该平台**版本最高**的产物 */
function pickAsset(
  releases: readonly GithubRelease[],
  platform: UpdatePlatform,
): { versionName: string; asset: GithubAsset; publishedAt: string | null } | null {
  let best: { versionName: string; asset: GithubAsset; publishedAt: string | null } | null = null;
  for (const release of releases) {
    const versionName = versionFromTag(release.tag_name ?? '');
    if (versionName === null) continue;
    const asset = (release.assets ?? []).find(
      (a) => typeof a.name === 'string' && isAssetMatch(a.name, versionName, platform),
    );
    if (asset === undefined || typeof asset.browser_download_url !== 'string') continue;
    if (best === null || compareVersionName(versionName, best.versionName) > 0) {
      best = { versionName, asset, publishedAt: release.published_at ?? null };
    }
  }
  return best;
}

/** 列 releases（过滤 draft；prerelease 也收，因为我们的 CI 从不发 prerelease） */
export async function listReleases(): Promise<GithubRelease[]> {
  const repo = config.updateGithubRepo;
  if (!repo) throw new Error('未配置 SUENMONEY_UPDATE_GITHUB_REPO');

  const url = `${apiBase()}/repos/${repo}/releases?per_page=${String(PER_PAGE)}`;
  const res = await fetch(url, {
    headers: githubHeaders(),
    signal: AbortSignal.timeout(15_000),
  } as never);

  if (res.status === 404) {
    // 无 Release 或私有仓库未配 token —— 按无包处理，让 check 回 available=false
    log.warn(`Releases 查询回 404（无 Release 或私有仓库未配 token）：${repo}`);
    return [];
  }
  if (!res.ok) throw new Error(`GitHub Releases 查询失败：HTTP ${String(res.status)}`);

  const parsed: unknown = await res.json();
  if (!Array.isArray(parsed)) throw new Error('GitHub Releases 返回的不是数组');
  return (parsed as GithubRelease[]).filter(
    (x) =>
      x.draft !== true
      && Array.isArray(x.assets)
      // ⚠ 只认本项目 tag：suenapp 是 suenmusic / suenweb / suenmoney 共用的发行仓库，
      //   不过滤会把 suenmusic 的 v2.1.3 当成我们的新版本。
      && isOurTag(x.tag_name ?? ''),
  );
}

/** 清理下载残留（`*.part`）：只清超过 1 小时的，正在写的不动 */
export function pruneStaleParts(platform: UpdatePlatform): void {
  const dir = cacheDir(platform);
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return;
  }
  const now = Date.now();
  for (const name of names) {
    if (!name.endsWith('.part')) continue;
    const file = join(dir, name);
    try {
      const st = statSync(file);
      if (now - st.mtimeMs < STALE_PART_MS) continue;
      rmSync(file, { force: true });
      log.info(`清理下载残留：${platform}/${name}（${String(Math.max(1, Math.round(st.size / 1024)))} KB）`);
    } catch {
      // 并发被清掉 / 权限不足：都不该影响主流程
    }
  }
}

/** 只保留当前版本的文件，删掉历史产物 */
function pruneOldFiles(platform: UpdatePlatform, keep: string): void {
  const dir = cacheDir(platform);
  let names: string[];
  try {
    names = readdirSync(dir);
  } catch {
    return;
  }
  const ext = `.${PLATFORM_EXTENSION[platform]}`;
  for (const name of names) {
    if (name === keep || name === 'latest.json') continue;
    if (!name.endsWith(ext) && !name.endsWith(`${ext}.part`)) continue;
    try {
      rmSync(join(dir, name), { force: true });
    } catch {
      // 忽略
    }
  }
}

/**
 * 已缓存的产物（无缓存返回 null）。**不发起任何网络请求**。
 *
 * 只认「已完整落盘」的包 —— 客户端拿到 available=true 就去下载安装，
 * 半个包比没有包更坏。三条校验：文件存在、size>0、size 与实际一致。
 */
export function readCachedArtifact(platform: UpdatePlatform): UpdateArtifact | null {
  try {
    const raw = readFileSync(latestJsonPath(platform), 'utf8');
    const meta = JSON.parse(raw) as UpdateArtifact;
    if (!meta || typeof meta.fileName !== 'string' || meta.fileName === '') return null;

    const file = typeof meta.path === 'string' && meta.path !== ''
      ? meta.path
      : join(cacheDir(platform), meta.fileName);
    const declared = Number(meta.size);
    if (!existsSync(file) || !Number.isFinite(declared) || declared <= 0) {
      pruneStaleParts(platform);
      return null;
    }
    const size = statSync(file).size;
    if (size <= 0 || size !== declared) {
      log.warn(`缓存包大小不符，视为没有包：${platform}/${meta.fileName}（声明 ${String(declared)}，实际 ${String(size)}）`);
      pruneStaleParts(platform);
      return null;
    }

    const code = meta.versionCode > 0 ? meta.versionCode : versionCodeOf(meta.versionName);
    return { ...meta, versionCode: code, path: file, size };
  } catch {
    return null;
  }
}

/** 下载用的本地文件（供路由层做 Range 流式发送） */
export function cachedFilePath(
  platform: UpdatePlatform,
): { path: string; fileName: string; size: number } | null {
  const artifact = readCachedArtifact(platform);
  if (artifact === null) return null;
  return { path: artifact.path, fileName: artifact.fileName, size: artifact.size };
}

/**
 * 检查并把最新产物拉到本地。
 *
 * @param force true = 忽略「已是最新」的短路，强制重新核对
 */
export async function refreshPlatform(
  platform: UpdatePlatform,
  force = false,
): Promise<UpdateArtifact | null> {
  pruneStaleParts(platform);
  const cached = readCachedArtifact(platform);
  const releases = await listReleases();
  const picked = pickAsset(releases, platform);
  if (picked === null) {
    log.warn(`GitHub 上没有 ${platform} 的产物（期望 ${artifactName('<版本>', platform)}）`);
    return cached;
  }

  if (!force && cached !== null && compareVersionName(cached.versionName, picked.versionName) >= 0) {
    return cached;
  }

  const fileName = artifactName(picked.versionName, platform);
  const dir = cacheDir(platform);
  mkdirSync(dir, { recursive: true });
  const target = join(dir, fileName);

  const digestRaw = typeof picked.asset.digest === 'string' ? picked.asset.digest : '';
  /**
   * 产物下载走**多镜像自动择优**（services/update-mirrors.ts）。
   *
   * 为什么不能直连：54 MB 的 .fpk 直连实测只有 20~50 KB/s，半小时级、中途必断，
   * 缓存永远建不起来 —— 表现就是「检查更新永远说已是最新」。
   * 镜像只用于下载：先并发探活测速取最快，失败自动换下一条，并做 sha256 校验防投毒。
   */
  await downloadWithMirrors(picked.asset.browser_download_url!, target, {
    expectedSize: typeof picked.asset.size === 'number' ? picked.asset.size : undefined,
    sha256: digestRaw.startsWith('sha256:') ? digestRaw.slice(7) : null,
  });

  const size = statSync(target).size;
  pruneOldFiles(platform, fileName);

  const artifact: UpdateArtifact = {
    fileName,
    path: target,
    versionName: picked.versionName,
    versionCode: versionCodeOf(picked.versionName),
    size,
    sha256: digestRaw.startsWith('sha256:') ? digestRaw.slice(7) : null,
  };
  writeFileSync(latestJsonPath(platform), JSON.stringify(artifact, null, 2), 'utf8');
  log.info(`更新产物已缓存：${platform} v${artifact.versionName}（${String(Math.round(size / 1024 / 1024))} MB）`);
  return artifact;
}

export interface ServerUpdateResult {
  available: boolean;
  currentVersion: string;
  latestVersion: string;
  deployMode: 'fnos' | 'docker';
  artifact: { fileName: string; size: number } | null;
}

/**
 * 检查**服务端自身**（套件）的更新。
 *
 * · fnOS 套件部署：把新 `.fpk` 拉到本地缓存，界面提示下载后手动覆盖安装；
 * · Docker 部署：只比对版本，提示「去拉新镜像」—— 容器里没有覆盖安装这回事，不下载 `.fpk`。
 */
export async function checkServerUpdate(force = false): Promise<ServerUpdateResult> {
  const mode = getDeployMode();
  const current = config.version;

  if (mode === 'fnos') {
    const artifact = force ? await refreshPlatform('fnos', true) : readCachedArtifact('fnos');
    const latest = artifact?.versionName ?? current;
    return {
      available: artifact !== null && compareVersionName(latest, current) > 0,
      currentVersion: current,
      latestVersion: latest,
      deployMode: mode,
      artifact: artifact === null ? null : { fileName: artifact.fileName, size: artifact.size },
    };
  }

  // Docker：只比版本，不拉产物
  let latestVersion = current;
  try {
    const releases = await listReleases();
    for (const release of releases) {
      if (!isOurTag(release.tag_name ?? '')) continue;
      const v = versionFromTag(release.tag_name ?? '');
      if (v === null) continue;
      if (compareVersionName(v, latestVersion) > 0) latestVersion = v;
    }
  } catch (err) {
    log.warn(`查询最新版本失败（docker 模式）：${err instanceof Error ? err.message : String(err)}`);
  }
  return {
    available: compareVersionName(latestVersion, current) > 0,
    currentVersion: current,
    latestVersion,
    deployMode: mode,
    artifact: null,
  };
}
