import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  assertCategoryDeactivatable,
  createCategory,
  deleteCategory,
  listCategoryTree,
  updateCategory,
  type UpdateCategoryInput,
} from '../db/repo/categories.ts';
import { asRecord, optionalBool, optionalInt, optionalNullableString, optionalString, pathParam, requireString } from '../lib/validate.ts';
import { currentAuth, requireAdmin, requireAuth } from './guard.ts';

/**
 * 分类管理。
 *
 * ## 权限：**只有管理员能改**
 *
 * 分类是共享字典（无 owner），过去任何登录用户都能增改。现在改为：
 *   · 读（GET）—— 所有登录用户；
 *   · 增 / 改 / 删 —— **仅管理员**（移动端不承载管理功能，只在 Web 管理页做）。
 *
 * ## color / icon 不再写入
 *
 * 这两项是**各端的渲染细节**，跨端本就无法统一（Web 用 lucide + `--chart-N`，
 * 原生用 `sys.symbol.*` + 本地调色板）。若允许写入，两端会互相覆盖对方的配色。
 * 因此服务端只把「名称 + 层级」当契约：
 *   · 入参里的 color/icon **直接忽略**（老客户端还在发，不报错）；
 *   · 列保留（Web 仍读存量值），但永远不再被更新。
 *   · 各端要个性化配色，存本地、不回推。
 *
 * 没有 DELETE 接口：分类只能停用。硬删会让历史记录的分类变成空值，报表里
 * 冒出一块「未分类」黑洞，而且这个错误会随同步扩散到所有设备。
 * 重新启用复用 PATCH（传 isEnabled: true），不必单开接口。
 */
export async function categoryRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/categories', { preHandler: requireAuth }, async () => {
    return { categories: listCategoryTree(getDatabase()) };
  });

  app.post('/api/categories', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    const parentId = optionalString(body, 'parentId', '');

    const category = createCategory(getDatabase(), {
      name: requireString(body, 'name'),
      parentId: parentId === '' ? null : parentId,
      // color/icon 刻意不取：见文件头注释（各端渲染细节，服务端不再保存）
      actorId: auth.user.id,
    });

    return reply.code(201).send({ category });
  });

  app.patch('/api/categories/:id', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    const body = asRecord(request.body);
    const db = getDatabase();

    const patch: UpdateCategoryInput = { actorId: auth.user.id };

    if (body['name'] !== undefined) patch.name = requireString(body, 'name');
    // icon / color：**故意不处理**（各端个性化，存本地，不回推）
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

  app.delete('/api/categories/:id', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const auth = currentAuth(request);
    const id = pathParam(request.params, 'id');
    deleteCategory(getDatabase(), id, auth.user.id);
    return reply.code(200).send({ ok: true });
  });
}
