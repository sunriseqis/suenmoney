import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  createExpense,
  findExpense,
  listExpenses,
  previewExpenseDates,
  softDeleteExpense,
  transferExpenses,
  updateExpense,
  type UpdateExpenseInput,
} from '../db/repo/expenses.ts';
import { notFound } from '../lib/http-error.ts';
import {
  asRecord,
  optionalDateParam,
  optionalIntParam,
  optionalMonthParam,
  optionalStrParam,
  optionalString,
  pathParam,
  requireInt,
  requireString,
} from '../lib/validate.ts';
import { currentAuth, requireAuth } from './guard.ts';

/**
 * 支出记录。
 *
 * 权限规则（贯穿全文件）：**读全开放，写仅限创建者**。
 * 这条规则不只是权限，它同时是离线冲突的消解机制 —— 每条记录只有一个
 * 写入者，两个人各自离线修改的永远是不同记录，编辑冲突在结构上不存在。
 */
export async function expenseRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/expenses', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);

    return listExpenses(getDatabase(), {
      month: optionalMonthParam(query['month'], 'month'),
      from: optionalDateParam(query['from'], 'from'),
      to: optionalDateParam(query['to'], 'to'),
      categoryId: optionalStrParam(query['categoryId'], 'categoryId'),
      paymentMethodId: optionalStrParam(query['paymentMethodId'], 'paymentMethodId'),
      ownerId: optionalStrParam(query['ownerId'], 'ownerId'),
      keyword: optionalStrParam(query['q'], 'q'),
      limit: optionalIntParam(query['limit'], 'limit'),
      cursor: optionalStrParam(query['cursor'], 'cursor'),
    });
  });

  /**
   * 预览账单日期（不落库）。
   *
   * 路由必须注册在 `/api/expenses/:id` **之前** 吗？不需要 —— 两者方法不同
   * （这里是 POST，`:id` 是 GET/PATCH/DELETE），Fastify 按「方法 + 路径」匹配，
   * 不存在把 `preview` 当成 id 的歧义。这里靠前放只是为了让阅读顺序更自然。
   */
  app.post('/api/expenses/preview', { preHandler: requireAuth }, async (request) => {
    const body = asRecord(request.body);
    return previewExpenseDates(getDatabase(), {
      spendDate: requireString(body, 'spendDate'),
      paymentMethodId: requireString(body, 'paymentMethodId'),
    });
  });

  app.get('/api/expenses/:id', { preHandler: requireAuth }, async (request) => {
    const expense = findExpense(getDatabase(), pathParam(request.params, 'id'));
    if (expense === null) throw notFound('支出记录不存在');
    return { expense };
  });

  app.post('/api/expenses', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);

    const expense = createExpense(getDatabase(), {
      amountCents: requireInt(body, 'amountCents'),
      categoryId: requireString(body, 'categoryId'),
      paymentMethodId: requireString(body, 'paymentMethodId'),
      spendDate: requireString(body, 'spendDate'),
      note: optionalString(body, 'note', ''),
      ownerId: auth.user.id,
    });

    return reply.code(201).send({ expense });
  });

  app.patch('/api/expenses/:id', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);

    const patch: UpdateExpenseInput = { actorId: auth.user.id };

    if (body['amountCents'] !== undefined) patch.amountCents = requireInt(body, 'amountCents');
    if (body['categoryId'] !== undefined) patch.categoryId = requireString(body, 'categoryId');
    if (body['paymentMethodId'] !== undefined) {
      patch.paymentMethodId = requireString(body, 'paymentMethodId');
    }
    if (body['spendDate'] !== undefined) patch.spendDate = requireString(body, 'spendDate');
    if (body['note'] !== undefined) patch.note = optionalString(body, 'note', '');

    return { expense: updateExpense(getDatabase(), id, patch) };
  });

  app.delete('/api/expenses/:id', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    softDeleteExpense(getDatabase(), pathParam(request.params, 'id'), auth.user.id);
    return reply.code(204).send();
  });

  /**
   * 转移某分类下的全部支出到另一个分类。
   *
   * 挂在支出路由下而不是分类路由下：被修改的实体是**支出记录**，
   * 它记录的是「这些账换了分类」，而不是「分类被改了」。
   */
  app.post('/api/expenses/transfer', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    const fromCategoryId = requireString(body, 'fromCategoryId');
    const toCategoryId = requireString(body, 'toCategoryId');

    if (fromCategoryId === toCategoryId) {
      return { moved: 0 };
    }

    const moved = transferExpenses(getDatabase(), fromCategoryId, toCategoryId, auth.user.id);
    return { moved };
  });
}
