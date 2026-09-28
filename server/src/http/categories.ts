import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  assertCategoryDeactivatable,
  createCategory,
  listCategoryTree,
  updateCategory,
  type UpdateCategoryInput,
} from '../db/repo/categories.ts';
import { asRecord, optionalBool, optionalInt, optionalNullableString, optionalString, pathParam, requireString } from '../lib/validate.ts';
import { currentAuth, requireAuth } from './guard.ts';

/**
 * 分类管理。
 *
 * 权限：分类是**共享字典**，两人都可增可改 —— 这与支出记录不同（支出只能
 * 改自己创建的），因为分类不属于任何人。
 *
 * 没有 DELETE 接口：分类只能停用。硬删会让历史记录的分类变成空值，报表里
 * 冒出一块「未分类」黑洞，而且这个错误会随同步扩散到所有设备。
 * 重新启用复用 PATCH（传 isEnabled: true），不必单开接口。
 */
export async function categoryRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/categories', { preHandler: requireAuth }, async () => {
    return { categories: listCategoryTree(getDatabase()) };
  });

  app.post('/api/categories', { preHandler: requireAuth }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    const parentId = optionalString(body, 'parentId', '');

    const category = createCategory(getDatabase(), {
      name: requireString(body, 'name'),
      parentId: parentId === '' ? null : parentId,
      icon: optionalString(body, 'icon', ''),
      color: optionalString(body, 'color', ''),
      actorId: auth.user.id,
    });

    return reply.code(201).send({ category });
  });

  app.patch('/api/categories/:id', { preHandler: requireAuth }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);
    const db = getDatabase();

    const patch: UpdateCategoryInput = { actorId: auth.user.id };

    if (body['name'] !== undefined) patch.name = requireString(body, 'name');
    if (body['icon'] !== undefined) patch.icon = optionalString(body, 'icon', '');
    if (body['color'] !== undefined) patch.color = optionalString(body, 'color', '');
    if (body['sortOrder'] !== undefined) patch.sortOrder = optionalInt(body, 'sortOrder') ?? 0;

    /*
     * 移动分类。用 optionalNullableString 而不是 optionalString：
     * 「没传 parentId」和「传 null 把二级提升为一级」必须是两件事，
     * 后者要被明确拒绝（跨深度移动），而不是被当成"没传"悄悄放过。
     * 中间那层校验在 updateCategory 里，这里只负责把三态原样传下去。
     */
    const movedParent = optionalNullableString(body, 'parentId');
    if (movedParent !== undefined) patch.parentId = movedParent;

    if (body['isEnabled'] !== undefined) {
      const isEnabled = optionalBool(body, 'isEnabled', true);
      // 停用前确认没有子分类、也没有记录引用它 —— 否则历史报表会凭空缺一块
      if (!isEnabled) assertCategoryDeactivatable(db, id);
      patch.isEnabled = isEnabled;
    }

    return { category: updateCategory(db, id, patch) };
  });
}
