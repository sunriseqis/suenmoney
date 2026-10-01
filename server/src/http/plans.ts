import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  ackTodo,
  confirmTodo,
  createPlan,
  deletePlan,
  endPlan,
  findPlan,
  listPlans,
  listTodos,
  restoreSkippedTodo,
  revertTodoConfirm,
  settleAutoPost,
  skipTodo,
  updatePlan,
  type PlanSource,
  type PlanTodoStatus,
  type UpdatePlanInput,
} from '../db/repo/plans.ts';
import { notFound } from '../lib/http-error.ts';
import {
  asRecord,
  optionalBool,
  optionalBoolParam,
  optionalDateParam,
  optionalEnumParam,
  optionalInt,
  optionalIntParam,
  optionalRecord,
  optionalStrParam,
  optionalString,
  pathParam,
  requireEnum,
  requireInt,
  requireString,
} from '../lib/validate.ts';
import { currentAuth, requireAuth } from './guard.ts';

/**
 * 计划（房贷 / 免息分期）与待办。
 *
 * 权限：读两人都能看；**创建与修改仅限创建者**（与支出同一条规则）。
 * 但**确认待办两人都能做** —— 房贷是家庭的共同事务，谁看到都能顺手确认，
 * 归属由 `(plan_id, period_seq)` 唯一约束决定（先写入者胜）。
 */
export async function planRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/plans', { preHandler: requireAuth }, async () => {
    return { plans: listPlans(getDatabase()) };
  });

  app.get('/api/plans/:id', { preHandler: requireAuth }, async (request) => {
    const db = getDatabase();
    const id = pathParam(request.params, 'id');

    const plan = findPlan(db, id);
    if (plan === null) throw notFound(`计划不存在：${id}`);

    return { plan, todos: listTodos(db, { planId: id, limit: 600, orderBy: 'period_seq' }) };
  });

  app.post('/api/plans', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);

    const plan = createPlan(getDatabase(), {
      name: requireString(body, 'name'),
      categoryId: requireString(body, 'categoryId'),
      paymentMethodId: requireString(body, 'paymentMethodId'),
      source: requireEnum<PlanSource>(body, 'source', ['manual', 'installment']),
      amountCents: optionalInt(body, 'amountCents'),
      totalAmountCents: optionalInt(body, 'totalAmountCents'),
      purchaseDate: optionalString(body, 'purchaseDate', '') || undefined,
      periods: requireInt(body, 'periods'),
      firstDueDate: requireString(body, 'firstDueDate'),
      remindDaysBefore: optionalInt(body, 'remindDaysBefore'),
      autoPost: optionalBool(body, 'autoPost', false),
      note: optionalString(body, 'note', ''),
      ownerId: auth.user.id,
      confirmFirst: optionalBool(body, 'confirmFirst', false),
      confirmSpendDate: optionalString(body, 'confirmSpendDate', '') || undefined,
      // 可选：把这条已有支出转成该计划（同事务内软删原支出），见 CreatePlanInput
      consumeExpenseId: optionalString(body, 'consumeExpenseId', '') || undefined,
    });

    return reply.code(201).send({ plan });
  });

  /**
   * 改计划。LPR 调整、提前还款都走这里。
   *
   * `remainingPeriods` 是「从最后一期已确认期之后还要多少期」。
   * 它对应界面上的语义：「房贷还剩 18 年」而不是「总共 240 期」——
   * 用户改计划时想的是「接下来还要还多久」，而不是去倒推总期数。
   */
  app.patch('/api/plans/:id', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);

    const patch: UpdatePlanInput = { actorId: auth.user.id };

    if (body['name'] !== undefined) patch.name = requireString(body, 'name');
    if (body['categoryId'] !== undefined) patch.categoryId = requireString(body, 'categoryId');
    if (body['paymentMethodId'] !== undefined) {
      patch.paymentMethodId = requireString(body, 'paymentMethodId');
    }
    if (body['amountCents'] !== undefined) patch.amountCents = requireInt(body, 'amountCents');
    if (body['firstDueDate'] !== undefined) patch.firstDueDate = requireString(body, 'firstDueDate');
    if (body['remindDaysBefore'] !== undefined) {
      patch.remindDaysBefore = requireInt(body, 'remindDaysBefore');
    }
    if (body['autoPost'] !== undefined) patch.autoPost = optionalBool(body, 'autoPost', false);
    if (body['note'] !== undefined) patch.note = optionalString(body, 'note', '');
    if (body['remainingPeriods'] !== undefined) {
      patch.remainingPeriods = requireInt(body, 'remainingPeriods');
    }

    return { plan: updatePlan(getDatabase(), id, patch) };
  });

  /** 终止计划：未执行的待办全部删除，已确认的历史原地保留。 */
  app.post('/api/plans/:id/end', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    return { plan: endPlan(getDatabase(), pathParam(request.params, 'id'), auth.user.id) };
  });

  /** 删除计划：软删计划与相关待办，已生成的支出记录保留。 */
  app.delete('/api/plans/:id', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    deletePlan(getDatabase(), pathParam(request.params, 'id'), auth.user.id);
    return reply.code(204).send();
  });

  /**
   * 待办列表。
   *
   * 传 `today` 会**先结算到期的自动入账待办**再返回列表。
   * 服务端没有定时任务，所以「到期就自动入账」这件事需要一个触发点，
   * 而「打开仪表盘」是最自然、也最不会漏的触发点。
   *
   * ⚠️ **结算是全局的，不受 `planId` 等筛选条件影响** ——
   * 打开一次首页就该把所有到期的都结清，而不是「只有当前这个计划的被结掉了」。
   * 筛选条件只作用于返回的列表。幂等由待办的状态机保证，所以多结几次不会重复生成。
   *
   * `today` 刻意不设默认值：服务端常年跑 UTC，猜「今天是几号」会让
   * 结算在错误的时刻发生。由客户端按本地时区传入。
   */
  app.get('/api/plan-todos', { preHandler: requireAuth }, async (request) => {
    const db = getDatabase();
    const query = asRecord(request.query);

    const today = optionalDateParam(query['today'], 'today');
    const settled = today === undefined ? 0 : settleAutoPost(db, today);

    return {
      settled,
      todos: listTodos(db, {
        planId: optionalStrParam(query['planId'], 'planId'),
        status: optionalEnumParam<PlanTodoStatus>(query['status'], 'status', [
          'pending',
          'confirmed',
          'skipped',
          'cancelled',
        ]),
        remindBefore: optionalDateParam(query['remindBefore'], 'remindBefore'),
        from: optionalDateParam(query['from'], 'from'),
        to: optionalDateParam(query['to'], 'to'),
        /**
         * 「该处理了」列表传 `hideAcked=1`：已经点过「确认」的期次不该再占位置。
         * 默认 false —— 计划详情要看得见它们（那一期仍然是 `pending`）。
         */
        hideAcked: optionalBoolParam(query['hideAcked'], 'hideAcked'),
        limit: optionalIntParam(query['limit'], 'limit'),
      }),
    };
  });

  /**
   * 确认一期 → 生成支出记录。
   *
   * `spendDate` 是「实际哪天付的」，**不影响报表月份归属** ——
   * 归属仍以待办的还款日为准。隔了几天才补点确认，不该把历史报表改到别的月份去。
   */
  app.post('/api/plan-todos/:id/confirm', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    // spendDate 是可选的，所以允许客户端干脆不带请求体
    const body = optionalRecord(request.body);
    const spendDate = optionalString(body, 'spendDate', '');

    const result = confirmTodo(
      getDatabase(),
      pathParam(request.params, 'id'),
      auth.user.id,
      spendDate === '' ? undefined : spendDate,
    );

    return { todo: result.todo, expenseId: result.expenseId };
  });

  /** 跳过某一期（这个月没有这笔支出）。 */
  app.post('/api/plan-todos/:id/skip', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    return { todo: skipTodo(getDatabase(), pathParam(request.params, 'id'), auth.user.id) };
  });

  /**
   * 「我知道了」—— 确认一条**会自动入账**的提醒。
   *
   * 与 `/confirm` 的区别是本质性的，别合并：
   *   · `/confirm` 生成那笔支出（业务状态从 `pending` 变成 `confirmed`）；
   *   · `/ack` **什么业务状态都不改**，只记下「用户看过了」，
   *     让这条从「该处理了」里消失，到还款日照旧自动入账。
   *
   * 两者还必须落在**互斥的两类期次**上（会 / 不会自动入账，见 repo 的
   * `willAutoPost`）。用错了不会报错，只会让账目静默地少一笔或多一笔。
   */
  app.post('/api/plan-todos/:id/ack', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    return { todo: ackTodo(getDatabase(), pathParam(request.params, 'id'), auth.user.id) };
  });

  /**
   * 恢复一个被跳过的期次（撤销「跳过」）。
   *
   * 与下面的 `revert` 分开是刻意的：两者前端入口相邻、都叫「撤销」，
   * 但一个是把已入账的支出撤回来，一个只是把跳过标记去掉。
   * 合并成一个 `pending` 路由会让「撤销一笔已花的钱」和「取消一个没花的标记」
   * 走同一条路径，将来任何一处加校验都会误伤另一边。
   */
  app.post('/api/plan-todos/:id/restore', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    return { todo: restoreSkippedTodo(getDatabase(), pathParam(request.params, 'id'), auth.user.id) };
  });

  /**
   * 撤销一次确认 → 把该期生成的支出软删，待办回到 `pending`。
   *
   * 返回被撤销的 `expenseId`，客户端据此提示「已撤销 ¥X 的入账」，
   * 并可在需要时回读该支出确认它已是墓碑状态。
   */
  app.post('/api/plan-todos/:id/revert', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const result = revertTodoConfirm(getDatabase(), pathParam(request.params, 'id'), auth.user.id);
    return { todo: result.todo, expenseId: result.expenseId };
  });
}
