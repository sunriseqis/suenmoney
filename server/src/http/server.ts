import cors from '@fastify/cors';
import fastifyStatic from '@fastify/static';
import Fastify, { type FastifyError, type FastifyInstance } from 'fastify';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { config } from '../config.ts';
import { HttpError } from '../lib/http-error.ts';
import { authRoutes } from './auth.ts';
import { categoryRoutes } from './categories.ts';
import { dataRoutes } from './data.ts';
import { expenseRoutes } from './expenses.ts';
import { paymentMethodRoutes } from './payment-methods.ts';
import { planRoutes } from './plans.ts';
import { reportRoutes } from './reports.ts';
import { syncRoutes } from './sync.ts';
import { updateRoutes } from './update.ts';
import { userRoutes } from './users.ts';
import { webdavRoutes } from './webdav.ts';

/**
 * 找出可用的前端产物目录。
 *
 * 判据只有一条：**有没有 `index.html`**。没有就当这个进程只是一台 API 服务器 ——
 * 测试、只跑接口的开发场景都走这条路，所以「产物不存在」不是错误。
 */
export function resolveWebRoot(candidate: string = config.webRoot): string | null {
  const indexPath = join(candidate, 'index.html');
  return existsSync(indexPath) ? candidate : null;
}

export async function buildServer(
  options: { logger?: boolean; webRoot?: string } = {},
): Promise<FastifyInstance> {
  const webRoot = resolveWebRoot(options.webRoot ?? config.webRoot);

  const app = Fastify({
    logger: options.logger === false ? false : { level: 'info' },
    /**
     * 只有确实挂在一层反代后面才信任 `X-Forwarded-For`（默认关）。
     * 直连形态下信任它 = 任何客户端都能伪造来源 IP，登录限流形同虚设。
     * 反代部署时用 `SUENMONEY_TRUST_PROXY=true` 显式打开。
     */
    trustProxy: config.trustProxy,
    // 客户端会提交带备注的记录，默认 1MB 够用；收紧一点减少被灌包的面积
    bodyLimit: 512 * 1024,
  });

  /**
   * 容忍「声明 JSON 但 body 为空」的请求。
   *
   * 默认的 JSON 解析器会把 `Content-Type: application/json` + 空 body 判成 400
   * `Body cannot be empty when content-type is set to 'application/json'`。
   * DELETE 天然没有 body，而某些客户端（鸿蒙原生 http 模块、部分反代）会无条件带上
   * 这个头 —— 结果就是「删一条流水」直接 400，业务代码根本没被调用。
   *
   * 这里把空体当 `{}` 处理：对 DELETE/POST 都是安全降级（真需要字段的路由自己会校验必填）。
   */
  app.addContentTypeParser('application/json', { parseAs: 'string' }, (req, body, done) => {
    const raw = typeof body === 'string' ? body.trim() : '';
    if (raw === '') {
      done(null, {});
      return;
    }
    try {
      done(null, JSON.parse(raw));
    } catch (e) {
      done(e as Error, undefined);
    }
  });

  /**
   * text/csv 原样收成字符串。
   * 流水导入是「用户上传一个 CSV」，不该逼前端先包成 JSON 再传 ——
   * 那样浏览器里多一层编码，出问题也难对。
   */
  app.addContentTypeParser('text/csv', { parseAs: 'string' }, (_req, body, done) => {
    done(null, body);
  });

  await app.register(cors, {
    origin: (origin, cb) => {
      // 允许没有 Origin 头的内部/curl 请求
      if (!origin) return cb(null, true);
      // 若配置了显式白名单，按白名单校验
      if (config.corsOrigins.length > 0) {
        if (config.corsOrigins.includes('*') || config.corsOrigins.includes(origin)) {
          return cb(null, true);
        }
        return cb(null, false);
      }
      // 默认允许 Capacitor、localhost 以及局域网客户端跨源访问
      cb(null, true);
    },
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });

  /**
   * 静态资源：同一个端口同时扮演「页面服务器」。
   *
   * `index.html` 启动时读一次：它是 SPA 的入口，缓存了也无所谓（它自己带 `no-cache`，
   * 浏览器每次都会回来问）。要换前端就重启服务 —— 这比每次请求都读盘便宜得多。
   */
  const indexHtml = webRoot === null ? null : readFileSync(join(webRoot, 'index.html'));

  if (webRoot !== null) {
    await app.register(fastifyStatic, { root: webRoot });
  }

  /**
   * 缓存策略：`/assets/*` 是 Vite 打了内容 hash 的产物，可以永久缓存；
   * HTML 一律 `no-cache` —— 否则用户会拿着旧的 index.html 去引用已经不存在的
   * hash 文件名，表现为白屏。
   *
   * 用 `onSend` 而不是 @fastify/static 的 `setHeaders`：后者的头会被 send 覆盖。
   */
  app.addHook('onSend', async (request, reply) => {
    if (request.url.startsWith('/assets/')) {
      reply.header('Cache-Control', 'public, max-age=2592000, immutable');
    } else if (request.url === '/' || request.url.endsWith('.html')) {
      reply.header('Cache-Control', 'no-cache');
    }
  });


  /**
   * 统一错误处理。
   *
   * 业务异常（HttpError）把 message 原样返回，其余一律回一句笼统的
   * 「服务器内部错误」并只记在服务端日志里 —— 否则 SQL 报错详情、
   * 表名、列名可能被拼进响应体泄漏出去。
   */
  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (error instanceof HttpError) {
      reply.code(error.statusCode).send({ error: error.message, details: error.details });
      return;
    }

    const status = error.statusCode;
    if (typeof status === 'number' && status >= 400 && status < 500) {
      // Fastify 自身的 4xx（如 JSON 解析失败、body 超限）
      reply.code(status).send({ error: error.message });
      return;
    }

    request.log.error({ err: error }, '未处理的请求错误');
    reply.code(500).send({ error: '服务器内部错误' });
  });

  /**
   * 404 分流 —— 这条边界不许含糊：
   *   `/api/*` 未命中 → **JSON** 404（前端解析错误时会说「接口不存在」，不会误判成登录失败）
   *   其余路径      → **HTML**（SPA 回退，用户直接访问 `/ledger` 也能进）
   * 两者混一次，前端就会把一坨 HTML 当 JSON 解析，故障现象与真实原因完全对不上。
   */
  app.setNotFoundHandler((request, reply) => {
    const url = String(request.url ?? '').split('?')[0] as string;
    // 静态资源 404 必须是**真的 404**：旧 bundle 被浏览器/扩展缓存引用时，
    // 如果回 HTML（且带 30 天 immutable），脚本会当 JS 解析 —— 报一堆语法错，
    // 而且这个「假 200」会粘在缓存里。SPA 回退只对「无扩展名的路由」生效。
    const isAsset =
      /^\/assets\//.test(url) ||
      /\.(js|mjs|css|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot|map|json|webp|webmanifest)$/.test(url);
    if (isAsset || url.startsWith('/api/') || indexHtml === null) {
      reply.code(404).send({ error: '接口不存在' });
      return;
    }
    reply.code(200).type('text/html; charset=utf-8').header('Cache-Control', 'no-cache');
    reply.send(indexHtml);
  });

  app.get('/api/health', async () => ({
    ok: true,
    service: 'suenmoney',
    version: config.version,
  }));


  await app.register(authRoutes);
  await app.register(categoryRoutes);
  await app.register(paymentMethodRoutes);
  await app.register(expenseRoutes);
  await app.register(reportRoutes);
  await app.register(planRoutes);
  await app.register(userRoutes);
  await app.register(dataRoutes);
  await app.register(webdavRoutes);
  await app.register(syncRoutes);
  await app.register(updateRoutes);

  return app;
}
