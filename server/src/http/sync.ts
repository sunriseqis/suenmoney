import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import type { BatchExpenseItem } from '../db/repo/expenses.ts';
import {
  currentSyncVersion,
  pullChanges,
  pushChanges,
  snapshotState,
  type BatchConfirmTodoItem,
  type BatchPlanItem,
  type BatchUpdateExpenseItem,
  type BatchUpdatePlanItem,
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
   * 冷启动全量快照：`GET /api/sync/snapshot`
   *
   * 客户端首装 / 清库后调一次，把当前状态整块灌进本地库；之后只走增量 pull。
   * 返回的 `version` 就是快照点的游标 —— 客户端直接记成它，下次 pull 从这里往后取。
   */
  app.get('/api/sync/snapshot', { preHandler: requireAuth }, async () => {
    return snapshotState(getDatabase());
  });

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

    const updatedRaw = body['updatedExpenses'];
    const updatedExpenses: BatchUpdateExpenseItem[] = [];

    if (updatedRaw !== undefined) {
      if (!Array.isArray(updatedRaw)) {
        throw badRequest('updatedExpenses 必须是数组');
      }
      for (let i = 0; i < updatedRaw.length; i++) {
        const item = asRecord(updatedRaw[i]);
        updatedExpenses.push({
          id: requireString(item, 'id'),
          amountCents:
            item['amountCents'] !== undefined ? requireInt(item, 'amountCents') : undefined,
          categoryId: optionalString(item, 'categoryId', '') || undefined,
          paymentMethodId: optionalString(item, 'paymentMethodId', '') || undefined,
          spendDate: optionalString(item, 'spendDate', '') || undefined,
          note: item['note'] !== undefined ? optionalString(item, 'note', '') : undefined,
        });
      }
    }

    const deletedRaw = body['deletedExpenseIds'];
    const deletedExpenseIds: string[] = [];
    if (deletedRaw !== undefined) {
      if (!Array.isArray(deletedRaw)) {
        throw badRequest('deletedExpenseIds 必须是数组');
      }
      for (const id of deletedRaw) {
        if (typeof id === 'string' && id) {
          deletedExpenseIds.push(id);
        }
      }
    }

    const confirmedRaw = body['confirmedTodos'];
    const confirmedTodos: BatchConfirmTodoItem[] = [];
    if (confirmedRaw !== undefined) {
      if (!Array.isArray(confirmedRaw)) {
        throw badRequest('confirmedTodos 必须是数组');
      }
      for (const item of confirmedRaw) {
        const rec = asRecord(item);
        confirmedTodos.push({
          id: requireString(rec, 'id'),
          spendDate: optionalString(rec, 'spendDate', '') || undefined,
        });
      }
    }

    const skippedRaw = body['skippedTodoIds'];
    const skippedTodoIds: string[] = [];
    if (skippedRaw !== undefined) {
      if (!Array.isArray(skippedRaw)) {
        throw badRequest('skippedTodoIds 必须是数组');
      }
      for (const id of skippedRaw) {
        if (typeof id === 'string' && id) {
          skippedTodoIds.push(id);
        }
      }
    }

    const ackedRaw = body['ackedTodoIds'];
    const ackedTodoIds: string[] = [];
    if (ackedRaw !== undefined) {
      if (!Array.isArray(ackedRaw)) {
        throw badRequest('ackedTodoIds 必须是数组');
      }
      for (const id of ackedRaw) {
        if (typeof id === 'string' && id) {
          ackedTodoIds.push(id);
        }
      }
    }

    const revertedRaw = body['revertedTodoIds'];
    const revertedTodoIds: string[] = [];
    if (revertedRaw !== undefined) {
      if (!Array.isArray(revertedRaw)) {
        throw badRequest('revertedTodoIds 必须是数组');
      }
      for (const id of revertedRaw) {
        if (typeof id === 'string' && id) {
          revertedTodoIds.push(id);
        }
      }
    }

    const restoredRaw = body['restoredTodoIds'];
    const restoredTodoIds: string[] = [];
    if (restoredRaw !== undefined) {
      if (!Array.isArray(restoredRaw)) {
        throw badRequest('restoredTodoIds 必须是数组');
      }
      for (const id of restoredRaw) {
        if (typeof id === 'string' && id) {
          restoredTodoIds.push(id);
        }
      }
    }

    /*
     * 计划：新建 / 修改 / 删除。
     *
     * 逐字段 optional —— 与 PATCH /api/plans/:id 一致：只传要改的字段。
     * 归属由 `createPlan` / `updatePlan` / `deletePlan` 内部的 `requireOwnPlan` 保证。
     */
    const plansRaw = body['plans'];
    const plans: BatchPlanItem[] = [];
    if (plansRaw !== undefined) {
      if (!Array.isArray(plansRaw)) {
        throw badRequest('plans 必须是数组');
      }
      for (let i = 0; i < plansRaw.length; i++) {
        const item = asRecord(plansRaw[i]);
        plans.push({
          id: optionalString(item, 'id', '') || undefined,
          name: requireString(item, 'name'),
          categoryId: requireString(item, 'categoryId'),
          paymentMethodId: requireString(item, 'paymentMethodId'),
          source: optionalString(item, 'source', 'manual') || 'manual',
          amountCents: item['amountCents'] !== undefined ? requireInt(item, 'amountCents') : undefined,
          totalAmountCents:
            item['totalAmountCents'] !== undefined ? requireInt(item, 'totalAmountCents') : undefined,
          purchaseDate: optionalString(item, 'purchaseDate', '') || undefined,
          periods: requireInt(item, 'periods'),
          firstDueDate: requireString(item, 'firstDueDate'),
          remindDaysBefore:
            item['remindDaysBefore'] !== undefined ? requireInt(item, 'remindDaysBefore') : undefined,
          autoPost: item['autoPost'] !== undefined ? item['autoPost'] === true : undefined,
          note: optionalString(item, 'note', '') || undefined,
        });
      }
    }

    const updatedPlansRaw = body['updatedPlans'];
    const updatedPlans: BatchUpdatePlanItem[] = [];
    if (updatedPlansRaw !== undefined) {
      if (!Array.isArray(updatedPlansRaw)) {
        throw badRequest('updatedPlans 必须是数组');
      }
      for (let i = 0; i < updatedPlansRaw.length; i++) {
        const item = asRecord(updatedPlansRaw[i]);
        updatedPlans.push({
          id: requireString(item, 'id'),
          name: optionalString(item, 'name', '') || undefined,
          categoryId: optionalString(item, 'categoryId', '') || undefined,
          paymentMethodId: optionalString(item, 'paymentMethodId', '') || undefined,
          amountCents: item['amountCents'] !== undefined ? requireInt(item, 'amountCents') : undefined,
          firstDueDate: optionalString(item, 'firstDueDate', '') || undefined,
          remindDaysBefore:
            item['remindDaysBefore'] !== undefined ? requireInt(item, 'remindDaysBefore') : undefined,
          autoPost: item['autoPost'] !== undefined ? item['autoPost'] === true : undefined,
          note: item['note'] !== undefined ? optionalString(item, 'note', '') : undefined,
          remainingPeriods:
            item['remainingPeriods'] !== undefined ? requireInt(item, 'remainingPeriods') : undefined,
        });
      }
    }

    const deletedPlansRaw = body['deletedPlanIds'];
    const deletedPlanIds: string[] = [];
    if (deletedPlansRaw !== undefined) {
      if (!Array.isArray(deletedPlansRaw)) {
        throw badRequest('deletedPlanIds 必须是数组');
      }
      for (const id of deletedPlansRaw) {
        if (typeof id === 'string' && id) {
          deletedPlanIds.push(id);
        }
      }
    }

    const deviceId = optionalString(body, 'deviceId', '') || undefined;

    const result = pushChanges(
      getDatabase(),
      {
        expenses,
        updatedExpenses,
        deletedExpenseIds,
        confirmedTodos,
        skippedTodoIds,
        ackedTodoIds,
        revertedTodoIds,
        restoredTodoIds,
        plans,
        updatedPlans,
        deletedPlanIds,
      },
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
