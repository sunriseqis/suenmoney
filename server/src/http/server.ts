import cors from '@fastify/cors';
import Fastify, { type FastifyError, type FastifyInstance } from 'fastify';

import { config } from '../config.ts';
import { HttpError } from '../lib/http-error.ts';
import { authRoutes } from './auth.ts';
import { categoryRoutes } from './categories.ts';
import { expenseRoutes } from './expenses.ts';
import { paymentMethodRoutes } from './payment-methods.ts';
import { planRoutes } from './plans.ts';
import { reportRoutes } from './reports.ts';
import { userRoutes } from './users.ts';

export async function buildServer(options: { logger?: boolean } = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: options.logger === false ? false : { level: 'info' },
    /**
     * 信任反向代理传来的 X-Forwarded-For。
     * 部署形态是 nginx / Docker 反代在前面，不设这个的话所有请求的 ip
     * 都是 127.0.0.1，登录限流会把所有人算作同一个来源而互相误伤。
     */
    trustProxy: true,
    // 客户端会提交带备注的记录，默认 1MB 够用；收紧一点减少被灌包的面积
    bodyLimit: 512 * 1024,
  });

  await app.register(cors, {
    // 留空 = 同源部署（Web 由 nginx 一起托管），此时无需 CORS
    origin: config.corsOrigins.length > 0 ? config.corsOrigins : false,
    credentials: false,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
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

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).send({ error: '接口不存在' });
  });

  app.get('/api/health', async () => ({ ok: true, service: 'suenmoney' }));

  await app.register(authRoutes);
  await app.register(categoryRoutes);
  await app.register(paymentMethodRoutes);
  await app.register(expenseRoutes);
  await app.register(reportRoutes);
  await app.register(planRoutes);
  await app.register(userRoutes);

  return app;
}
