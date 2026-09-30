import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import type { BatchExpenseItem } from '../db/repo/expenses.ts';
import {
  currentSyncVersion,
  pullChanges,
  pushChanges,
} from '../db/repo/sync.ts';
import { badRequest } from '../lib/http-error.ts';
import {
  asRecord,
  optionalIntParam,
  optionalString,
  requireInt,
  requireString,
} from '../lib/validate.ts';
import { currentAuth, requireAuth } from './guard.ts';

export async function syncRoutes(app: FastifyInstance): Promise<void> {
  /**
   * 增量拉取变更：
   * GET /api/sync/pull?since=:version&limit=:limit
   */
  app.get('/api/sync/pull', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);
    const since = optionalIntParam(query['since'], 'since') ?? 0;
    const limit = optionalIntParam(query['limit'], 'limit') ?? 200;

    return pullChanges(getDatabase(), since, limit);
  });

  /**
   * 增量拉取别名（兼容直接请求 /api/sync）：
   * GET /api/sync?since=:version
   */
  app.get('/api/sync', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);
    const since = optionalIntParam(query['since'], 'since') ?? 0;
    const limit = optionalIntParam(query['limit'], 'limit') ?? 200;

    return pullChanges(getDatabase(), since, limit);
  });

  /**
   * 离线变更补偿推送：
   * POST /api/sync/push
   *
   * 接收客户端在无网离线环境下产生的实体写入（主要为离线记账），
   * 事务落库并返回全局确认版本号。
   */
  app.post('/api/sync/push', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);

    const expensesRaw = body['expenses'];
    const expenses: BatchExpenseItem[] = [];

    if (expensesRaw !== undefined) {
      if (!Array.isArray(expensesRaw)) {
        throw badRequest('expenses 必须是数组');
      }

      for (let i = 0; i < expensesRaw.length; i++) {
        const item = asRecord(expensesRaw[i]);
        expenses.push({
          id: optionalString(item, 'id', '') || undefined,
          amountCents: requireInt(item, 'amountCents'),
          categoryId: requireString(item, 'categoryId'),
          paymentMethodId: requireString(item, 'paymentMethodId'),
          spendDate: requireString(item, 'spendDate'),
          note: optionalString(item, 'note', '') || undefined,
        });
      }
    }

    const deviceId = optionalString(body, 'deviceId', '') || undefined;

    const result = pushChanges(
      getDatabase(),
      { expenses },
      auth.user.id,
      deviceId,
    );

    return reply.code(200).send(result);
  });

  /**
   * 查看当前服务器同步版本：
   * GET /api/sync/status
   */
  app.get('/api/sync/status', { preHandler: requireAuth }, async () => {
    return {
      latestVersion: currentSyncVersion(getDatabase()),
    };
  });
}
