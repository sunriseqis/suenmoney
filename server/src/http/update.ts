/**
 * 更新通道 HTTP 面。**唯一来源是 GitHub Releases（`sunriseqis/suenapp`）**，
 * 服务端拉回本地缓存后由客户端从这里下载。
 *
 *   GET /api/update/check               查是否有新版本（**只读本地完整包**，零上游、零等待、零报错）
 *   GET /api/update/download            下载产物（本地文件流式发送，**支持 Range/206**）
 *   GET /api/update/download/:fileName  同上，路径里带扩展名（见下方注释）
 *   GET /api/admin/server-update        套件自身更新（fnOS 拉 .fpk / Docker 只比版本）
 *
 * 为什么客户端不直连 GitHub：
 *   ① 国内访问 objects.githubusercontent.com 极不稳定；
 *   ② 鸿蒙 / iOS 客户端把下载交给**系统浏览器或侧签工具**，那些调用方发不出鉴权头；
 *   ③ 缓存到本地后才能支持断点续传。
 */

import { createReadStream } from 'node:fs';
import type { FastifyInstance } from 'fastify';

import { config } from '../config.ts';
import { badRequest, serviceUnavailable } from '../lib/http-error.ts';
import { signUpdateToken, verifyUpdateToken } from '../lib/update-token.ts';
import {
  PLATFORM_CONTENT_TYPE,
  compareVersionName,
  isUpdatePlatform,
  versionCodeOf,
  type UpdatePlatform,
} from '../services/update-types.ts';
import {
  cachedFilePath,
  checkServerUpdate,
  readCachedArtifact,
  refreshPlatform,
} from '../services/github-update.ts';
import { createLogger } from '../lib/logger.ts';
import { currentAuth, requireAdmin, requireAuth } from './guard.ts';

const log = createLogger('update');

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

/** 平台参数。缺省按 harmony —— 我们的客户端都会显式传，缺省只防老客户端。 */
function platform(value: unknown): UpdatePlatform {
  const text = String(value ?? 'harmony').trim().toLowerCase();
  if (!isUpdatePlatform(text)) throw badRequest('不支持的更新平台', 'invalid_platform');
  return text;
}

export async function updateRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/update/check', async (req) => {
    // 允许未登录状态下检查客户端更新（登录页也要能提示新版）
    try {
      await requireAuth(req);
    } catch {
      // 忽略
    }

    const query = (req.query ?? {}) as Record<string, unknown>;
    const currentName = versionName(query['version_name']);
    const currentCode = versionCode(query['version_code']);
    const force = ['1', 'true', 'yes'].includes(String(query['force'] ?? '').toLowerCase());
    const target = platform(query['platform']);

    if (config.updateSource === 'off') {
      return serviceUnavailable('更新服务已关闭', 'update_not_configured');
    }

    /**
     * **检查更新 = 只读本地完整包**：零上游、零等待、零报错。
     *
     * 客户端只问一件事：「我本地有没有比我版本更高的完整安装包？」
     * 下载是**服务端自己的事** —— 手动触发后在后台下，下完并校验通过才落盘生效。
     * 这里若等下载，整包传输时间就压进客户端超时（54MB 的 fpk 足够让「点检查更新」直接报错）。
     *
     * `force=1` = **触发一次后台刷新，但立即返回**当前本地结论。
     * 任何情况下都不因「没有包 / 网络失败」返回 5xx：无包就 available=false。
     */
    if (force) {
      void refreshPlatform(target, true).catch((err: unknown) => {
        log.warn(`后台刷新更新产物失败（${target}）：${err instanceof Error ? err.message : String(err)}`);
      });
    }

    const artifact = readCachedArtifact(target);
    const base = {
      current: { versionName: currentName, versionCode: currentCode },
      downloadPath: '/api/update/download',
      downloadToken: signUpdateToken(target),
    };

    if (artifact === null) {
      return { available: false, latest: null, ...base };
    }

    // 比对**单一轴**：versionCode。latest 的 code 由 versionName 推导（上游恒 0）；
    // 兜底：任一侧拿不到 code（越界 / 老客户端上报 0）才退回按版本名比较。
    const latestCode = artifact.versionCode > 0
      ? artifact.versionCode
      : versionCodeOf(artifact.versionName);
    const available = latestCode > 0 && currentCode > 0
      ? latestCode > currentCode
      : compareVersionName(artifact.versionName, currentName) > 0;

    return { available, latest: artifact, ...base };
  });

  /**
   * 下载处理：`/api/update/download` 与 `/api/update/download/:fileName` 共用。
   *
   * 为什么要有带文件名的别名路由：
   *   iOS 侧签工具（AltStore / SideStore / 轻松签）**只看 URL 的路径后缀**判断类型，
   *   而 `/api/update/download?platform=ios&token=...` 的路径里没有 `.ipa`，
   *   工具把文件名识别成 "download" 就拒绝安装。
   *   Content-Disposition 能救浏览器，救不了这些按 URL 猜类型的工具。
   *
   * `:fileName` 只用于让 URL 看起来像安装包：**实际文件以本地缓存为准**，
   * 不信任入参（防伪造 / 穿越），响应头里的 fileName 始终是真实的那个。
   */
  const serveDownload = async (req: any, reply: any) => {
    const query = (req.query ?? {}) as Record<string, unknown>;
    const target = platform(query['platform']);

    /**
     * 两条鉴权入口，满足其一即可：
     *   - `?token=` —— check 签发的短期令牌，给**发不出请求头**的调用方；
     *   - `Authorization: Bearer` —— 原生客户端自己下载时走这条。
     */
    const rawToken = typeof query['token'] === 'string' ? query['token'] : undefined;
    if (!verifyUpdateToken(target, rawToken)) {
      await requireAuth(req);
    }

    if (config.updateSource === 'off') {
      return serviceUnavailable('更新服务已关闭', 'update_not_configured');
    }

    const file = cachedFilePath(target);
    if (file === null) {
      return serviceUnavailable('更新产物尚未就绪', 'update_not_ready');
    }

    /**
     * Range 支持（断点续传）。移动网络断一次不能从 0 重下。
     *
     * 起点越界必须回 **416**，不能夹到最后一个字节 —— 夹住会让客户端把 1 字节
     * 当「续传成功」，文件静默残缺。
     */
    const total = file.size;
    const rangeHeader = typeof req.headers.range === 'string' ? req.headers.range : '';
    const m = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
    let start = 0;
    let end = total - 1;
    let partial = false;

    if (m !== null && total > 0) {
      const rawStart = m[1] === '' ? null : Number(m[1]);
      const rawEnd = m[2] === '' ? null : Number(m[2]);
      if (rawStart === null && rawEnd !== null) {
        start = Math.max(0, total - rawEnd);
      } else if (rawStart !== null) {
        if (rawStart >= total) {
          reply.code(416);
          reply.header('Content-Range', `bytes */${String(total)}`);
          return { error: { code: 'invalid_range', message: '请求的字节范围无效' } };
        }
        start = rawStart;
        if (rawEnd !== null) end = Math.min(rawEnd, total - 1);
      }
      partial = true;
      if (start > end) {
        reply.code(416);
        reply.header('Content-Range', `bytes */${String(total)}`);
        return { error: { code: 'invalid_range', message: '请求的字节范围无效' } };
      }
    }

    reply.header('Content-Type', PLATFORM_CONTENT_TYPE[target]);
    reply.header('Content-Disposition', `attachment; filename="${file.fileName}"`);
    reply.header('Cache-Control', 'no-store');
    reply.header('Accept-Ranges', 'bytes');
    reply.header('Content-Length', String(end - start + 1));
    if (partial) {
      reply.code(206);
      reply.header('Content-Range', `bytes ${String(start)}-${String(end)}/${String(total)}`);
    } else {
      reply.code(200);
    }

    const local = createReadStream(file.path, { start, end });
    local.on('error', () => {
      try {
        (reply.raw.socket ?? reply.raw).destroy();
      } catch {
        // 客户端已断开
      }
    });
    reply.raw.on('close', () => {
      if (!local.destroyed) local.destroy();
    });
    return reply.send(local);
  };

  app.get('/api/update/download', serveDownload);
  app.get('/api/update/download/:fileName', serveDownload);

  /**
   * 套件自身更新（Web 管理页用）。
   *
   * fnOS 部署 → 把新 `.fpk` 拉到本地缓存，界面提示下载后手动覆盖安装；
   * Docker 部署 → 只比对版本，提示「去拉新镜像」，不下载 `.fpk`。
   */
  app.get('/api/admin/server-update', { preHandler: [requireAuth, requireAdmin] }, async (req) => {
    const query = (req.query ?? {}) as Record<string, unknown>;
    const force = ['1', 'true', 'yes'].includes(String(query['force'] ?? '').toLowerCase());
    const auth = currentAuth(req);
    void auth;
    return checkServerUpdate(force);
  });
}
