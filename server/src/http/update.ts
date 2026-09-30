import type { FastifyInstance } from 'fastify';
import { Readable } from 'node:stream';

import { config } from '../config.ts';
import { badGateway, badRequest, serviceUnavailable } from '../lib/http-error.ts';
import { signUpdateToken, verifyUpdateToken } from '../lib/update-token.ts';
import {
  getLatestUpdateArtifact,
  isUpdatePlatform,
  openUpdateDownload,
  type UpdatePlatform,
} from '../services/ugreen-update.ts';
import { requireAuth } from './guard.ts';

const CONTENT_TYPE: Record<UpdatePlatform, string> = {
  android: 'application/vnd.android.package-archive',
  ios: 'application/octet-stream',
};

function versionName(value: unknown): string {
  const text = String(value ?? '').trim();
  if (!/^\d+(?:\.\d+)*$/.test(text)) throw badRequest('当前版本号格式不正确', 'invalid_version');
  return text;
}

function versionCode(value: unknown): number {
  const n = Number(value ?? 0);
  if (!Number.isInteger(n) || n < 0) throw badRequest('当前版本号格式不正确', 'invalid_version');
  return n;
}

function platform(value: unknown): UpdatePlatform {
  const text = String(value ?? 'android').trim().toLowerCase();
  if (!isUpdatePlatform(text)) throw badRequest('不支持的更新平台', 'invalid_platform');
  return text;
}

function updateError(err: unknown): never {
  const message = err instanceof Error ? err.message : String(err);
  if (!config.updateShareId) throw serviceUnavailable('更新服务尚未配置', 'update_not_configured');
  throw badGateway(`更新源暂时不可用：${message}`, 'update_upstream_failed');
}

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

export async function updateRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/update/check', async (req) => {
    // 允许已登录或未登录状态下检查更新，优先尝试注入 auth 上下文
    try {
      await requireAuth(req);
    } catch {
      // 允许离线或未登录端检查客户端更新
    }

    const query = (req.query ?? {}) as Record<string, unknown>;
    const currentName = versionName(query.version_name);
    const currentCode = versionCode(query.version_code);
    const force = ['1', 'true', 'yes'].includes(String(query.force ?? '').toLowerCase());
    const target = platform(query.platform);

    let artifact;
    try {
      artifact = await getLatestUpdateArtifact(target, force);
    } catch (err) {
      return updateError(err);
    }

    const available =
      artifact.versionCode > 0 && currentCode > 0
        ? artifact.versionCode > currentCode
        : compareVersionName(artifact.versionName, currentName) > 0;

    return {
      available,
      current: { versionName: currentName, versionCode: currentCode },
      latest: artifact,
      downloadPath: '/api/update/download',
      downloadToken: signUpdateToken(target),
    };
  });

  app.get('/api/update/download', async (req, reply) => {
    const query = (req.query ?? {}) as Record<string, unknown>;
    const target = platform(query.platform);

    const rawToken = typeof query.token === 'string' ? query.token : undefined;
    if (!verifyUpdateToken(target, rawToken)) {
      await requireAuth(req);
    }

    let result;
    try {
      result = await openUpdateDownload(target);
    } catch (err) {
      return updateError(err);
    }

    const { response, artifact } = result;
    const stream = Readable.fromWeb(response.body as any);
    reply.code(200);
    reply.header('Content-Type', CONTENT_TYPE[target]);
    reply.header('Content-Disposition', `attachment; filename="${artifact.fileName}"`);
    reply.header('Cache-Control', 'no-store');
    if (response.headers.get('content-length')) {
      reply.header('Content-Length', response.headers.get('content-length'));
    }

    stream.on('error', () => {
      try {
        (reply.raw.socket ?? reply.raw).destroy();
      } catch {
        /* 客户端已断开 */
      }
    });

    reply.raw.on('close', () => {
      if (!stream.destroyed) stream.destroy();
    });

    return reply.send(stream);
  });
}
