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
import { currentAuth, requireAuth } from './guard.ts';

/**
 * 支付方式管理。
 *
 * 与分类的关键差别：**停用不受历史记录阻挡**。支付方式是历史事实
 * （「这笔是招行卡付的」没有替代品），若因存在历史记录就禁止停用，
 * 这张卡将永远无法退休。只有进行中的计划还在依赖它时才拦。
 */
export async function paymentMethodRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/payment-methods', { preHandler: requireAuth }, async () => {
    return { paymentMethods: listPaymentMethods(getDatabase()) };
  });

  app.post('/api/payment-methods', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);

    const method = createPaymentMethod(getDatabase(), {
      name: requireString(body, 'name'),
      type: requireEnum<PaymentMethodType>(body, 'type', ['cash', 'credit']),
      billingDay: optionalInt(body, 'billingDay'),
      repaymentDay: optionalInt(body, 'repaymentDay'),
      icon: optionalString(body, 'icon', ''),
      sortOrder: optionalInt(body, 'sortOrder'),
      actorId: auth.user.id,
    });

    return reply.code(201).send({ paymentMethod: method });
  });

  app.patch('/api/payment-methods/:id', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);

    const patch: UpdatePaymentMethodInput = { actorId: auth.user.id };

    if (body['name'] !== undefined) patch.name = requireString(body, 'name');
    if (body['icon'] !== undefined) patch.icon = optionalString(body, 'icon', '');
    if (body['billingDay'] !== undefined) patch.billingDay = optionalInt(body, 'billingDay') ?? 0;
    if (body['repaymentDay'] !== undefined) patch.repaymentDay = optionalInt(body, 'repaymentDay') ?? 0;
    if (body['sortOrder'] !== undefined) patch.sortOrder = optionalInt(body, 'sortOrder') ?? 0;
    if (body['isEnabled'] !== undefined) patch.isEnabled = optionalBool(body, 'isEnabled', true);

    return { paymentMethod: updatePaymentMethod(getDatabase(), id, patch) };
  });

  app.post('/api/payment-methods/:id/merge', { preHandler: requireAuth }, async (request, reply) => {
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

  app.delete('/api/payment-methods/:id', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    deletePaymentMethod(getDatabase(), id, auth.user.id);
    return reply.code(200).send({ ok: true });
  });
}
