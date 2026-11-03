import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  createPaymentMethod,
  deletePaymentMethod,
  listPaymentMethods,
  mergePaymentMethod,
  updatePaymentMethod,
  type PaymentMethodType,
  type UpdatePaymentMethodInput,
} from '../db/repo/payment-methods.ts';
import { asRecord, optionalBool, optionalInt, optionalString, pathParam, requireEnum, requireString } from '../lib/validate.ts';
import { currentAuth, requireAdmin, requireAuth } from './guard.ts';

/**
 * 支付方式管理。
 *
 * ## 权限：**只有管理员能改**
 *
 * 与分类同样处理：读（GET）所有登录用户可用；增 / 改 / 删 / 合并 —— 仅管理员。
 * 移动端只读，不承载管理功能。
 *
 * ## icon 不再写入
 *
 * 图标是各端渲染细节（Web 用 lucide，原生用 `sys.symbol.*`），跨端无法统一。
 * 入参里的 icon **直接忽略**；列保留但永不更新。各端要个性化就存本地、不回推。
 *（支付方式没有 color 字段，颜色由各端按图标/名称派生。）
 *
 * 与分类的关键差别：**停用不受历史记录阻挡**。支付方式是历史事实
 * （「这笔是招行卡付的」没有替代品），若因存在历史记录就禁止停用，
 * 这张卡将永远无法退休。只有进行中的计划还在依赖它时才拦。
 */
export async function paymentMethodRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/payment-methods', { preHandler: requireAuth }, async () => {
    return { paymentMethods: listPaymentMethods(getDatabase()) };
  });

  app.post('/api/payment-methods', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);

    const method = createPaymentMethod(getDatabase(), {
      name: requireString(body, 'name'),
      type: requireEnum<PaymentMethodType>(body, 'type', ['cash', 'credit']),
      billingDay: optionalInt(body, 'billingDay'),
      repaymentDay: optionalInt(body, 'repaymentDay'),
      // icon 刻意不取：见文件头注释（各端渲染细节，服务端不再保存）
      sortOrder: optionalInt(body, 'sortOrder'),
      actorId: auth.user.id,
    });

    return reply.code(201).send({ paymentMethod: method });
  });

  app.patch('/api/payment-methods/:id', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);

    const patch: UpdatePaymentMethodInput = { actorId: auth.user.id };

    if (body['name'] !== undefined) patch.name = requireString(body, 'name');
    // icon：**故意不处理**（各端个性化，存本地，不回推）
    if (body['billingDay'] !== undefined) patch.billingDay = optionalInt(body, 'billingDay') ?? 0;
    if (body['repaymentDay'] !== undefined) patch.repaymentDay = optionalInt(body, 'repaymentDay') ?? 0;
    if (body['sortOrder'] !== undefined) patch.sortOrder = optionalInt(body, 'sortOrder') ?? 0;
    if (body['isEnabled'] !== undefined) patch.isEnabled = optionalBool(body, 'isEnabled', true);

    return { paymentMethod: updatePaymentMethod(getDatabase(), id, patch) };
  });

  app.post('/api/payment-methods/:id/merge', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);

    const result = mergePaymentMethod(getDatabase(), id, {
      targetId: requireString(body, 'targetId'),
      deleteSource: optionalBool(body, 'deleteSource', false),
      actorId: auth.user.id,
    });

    return reply.code(200).send(result);
  });

  app.delete('/api/payment-methods/:id', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    deletePaymentMethod(getDatabase(), id, auth.user.id);
    return reply.code(200).send({ ok: true });
  });
}
