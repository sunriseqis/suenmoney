import type { DatabaseSync } from 'node:sqlite';

import { badRequest, conflict, notFound } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange } from '../sync.ts';

export interface CategoryRow {
  id: string;
  parent_id: string | null;
  name: string;
  depth: number;
  icon: string;
  color: string;
  sort_order: number;
  is_enabled: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
  /** 该分类下未被删除的支出笔数 —— 用于「停用前先转移」的提示 */
  expense_count?: number;
}

export interface CategoryNode {
  id: string;
  parentId: string | null;
  name: string;
  depth: number;
  icon: string;
  color: string;
  sortOrder: number;
  isEnabled: boolean;
  expenseCount: number;
  children: CategoryNode[];
}

const COLUMNS = `id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                 created_at, updated_at, deleted_at, rev, device_id`;

/** 分类最多两级。这里写死是因为树形选择器、报表分组都按两级设计。 */
export const MAX_CATEGORY_DEPTH = 2;

const nowIso = (): string => new Date().toISOString();

function toNode(row: CategoryRow): CategoryNode {
  return {
    id: row.id,
    parentId: row.parent_id,
    name: row.name,
    depth: row.depth,
    icon: row.icon,
    color: row.color,
    sortOrder: row.sort_order,
    isEnabled: row.is_enabled === 1,
    expenseCount: row.expense_count ?? 0,
    children: [],
  };
}

export function toSyncCategory(row: CategoryRow): Record<string, unknown> {
  return {
    id: row.id,
    parentId: row.parent_id,
    name: row.name,
    depth: row.depth,
    icon: row.icon,
    color: row.color,
    sortOrder: row.sort_order,
    isEnabled: row.is_enabled === 1,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    rev: row.rev,
  };
}

/**
 * 列出全部分类（含已停用的 —— 历史记录还要靠它显示分类名，界面只是不放进
 * 新记账的选择列表）。
 *
 * `expense_count` 的算法分两层，这是第三轮明确下来的口径：
 *
 *   一级分类 —— **累计其子分类**。原先只数直接挂在一级上的记录，于是
 *               「只往二级记账」的家庭会看到所有一级分类都写着 0 笔。
 *               字段本身没说谎，但它就印在「停用」按钮旁边，
 *               会被读成「这是个空分类，可以安全停用」。
 *   **显示口径必须服务它旁边的动作。**
 *
 *   二级分类 —— 只数自己的（`c2.parent_id = categories.id` 对二级恒为空）。
 *
 * `IN (子查询)` 而不是 JOIN：同一条记录只会命中一次，不需要 DISTINCT 去重
 * （JOIN 两个层级时会把记录数翻倍，而那个错误表现为「笔数正好是两倍」，
 * 在没有对照数据时很难看出来）。
 */
export function listCategoryRows(db: DatabaseSync): CategoryRow[] {
  const rows = db
    .prepare(
      `SELECT ${COLUMNS},
              (SELECT COUNT(*) FROM expenses e
                WHERE e.deleted_at IS NULL
                  AND e.category_id IN (
                    SELECT c2.id FROM categories c2
                     WHERE c2.deleted_at IS NULL
                       AND (c2.id = categories.id OR c2.parent_id = categories.id)
                  )) AS expense_count
         FROM categories
        WHERE deleted_at IS NULL
        -- created_at / rowid 参与排序的理由同 listPaymentMethods：name 的字节序没有语义
        ORDER BY depth, sort_order, created_at, rowid, name`,
    )
    .all();
  return rows as unknown as CategoryRow[];
}

/** 组装成两级树。一级分类按 sort_order 排，二级同样。 */
export function listCategoryTree(db: DatabaseSync): CategoryNode[] {
  const nodes = listCategoryRows(db).map(toNode);
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const roots: CategoryNode[] = [];

  for (const node of nodes) {
    if (node.parentId === null) {
      roots.push(node);
      continue;
    }
    const parent = byId.get(node.parentId);
    // 父级已被软删除时，把孤儿子项挂到根上而不是丢掉 —— 丢掉会让历史记录
    // 的分类凭空消失。正常流程下不会出现（父级有子项时不允许停用）。
    if (parent === undefined) roots.push(node);
    else parent.children.push(node);
  }

  return roots;
}

export function findCategory(db: DatabaseSync, id: string): CategoryRow | null {
  const row = db
    .prepare(`SELECT ${COLUMNS} FROM categories WHERE id = ? AND deleted_at IS NULL`)
    .get(id);
  return (row as unknown as CategoryRow | undefined) ?? null;
}

/** 取一个「可用于新记账」的分类：必须存在、必须启用。 */
export function requireUsableCategory(db: DatabaseSync, id: string): CategoryRow {
  const row = findCategory(db, id);
  if (row === null) throw badRequest(`分类不存在：${id}`);
  if (row.is_enabled !== 1) throw badRequest(`分类已停用，不能用于新记录：${row.name}`);
  return row;
}

/**
 * SQLite 唯一约束失败。
 *
 * **绝对不要靠错误信息里的索引名来判断是哪个约束** —— 实测同样写法下：
 *   单列唯一索引   → `UNIQUE constraint failed: payment_methods.name`
 *   表达式唯一索引 → `UNIQUE constraint failed: index 'ux_categories_sibling_name'`
 * 格式不统一，字符串匹配会随时失效，而且失效方式是**静默退化成 500**，
 * 测试不覆盖到就永远发现不了。
 *
 * 所以正常路径用显式 SELECT 判重（能给出准确、可读的提示），
 * 这里的识别只作兜底：任何唯一约束失败一律转成 409。
 */
function isUniqueViolation(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.startsWith('UNIQUE constraint failed');
}

/** 同层重名检查。在写事务内调用，消除「先查后写」之间的竞态窗口。 */
function assertNoSiblingName(
  db: DatabaseSync,
  parentId: string | null,
  name: string,
  excludeId?: string,
): void {
  const row = db
    .prepare(
      `SELECT id FROM categories
        WHERE COALESCE(parent_id, '') = COALESCE(?, '')
          AND name = ?
          AND deleted_at IS NULL
          AND id <> ?`,
    )
    .get(parentId, name, excludeId ?? '');

  if (row !== undefined) throw conflict(`同一层级下已存在同名分类：${name}`);
}

export interface CreateCategoryInput {
  name: string;
  parentId?: string | null;
  icon?: string | undefined;
  color?: string | undefined;
  actorId: string;
  deviceId?: string | null;
}

export function createCategory(db: DatabaseSync, input: CreateCategoryInput): CategoryNode {
  const name = input.name.trim();
  if (name === '') throw badRequest('分类名不能为空');
  if (name.length > 20) throw badRequest('分类名不能超过 20 个字');

  const parentId = input.parentId ?? null;
  let depth = 1;

  if (parentId !== null) {
    const parent = findCategory(db, parentId);
    if (parent === null) throw badRequest(`父级分类不存在：${parentId}`);
    if (parent.depth >= MAX_CATEGORY_DEPTH) {
      throw badRequest(`分类最多 ${MAX_CATEGORY_DEPTH} 级，不能在「${parent.name}」下再建子级`);
    }
    depth = parent.depth + 1;
  }

  const timestamp = nowIso();
  const row: CategoryRow = {
    id: ulid(),
    parent_id: parentId,
    name,
    depth,
    icon: input.icon ?? '',
    color: input.color ?? '',
    sort_order: 0,
    is_enabled: 1,
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: input.deviceId ?? null,
  };

  try {
    inTransaction(db, () => {
      assertNoSiblingName(db, parentId, name);

      db.prepare(
        `INSERT INTO categories (id, parent_id, name, depth, icon, color, sort_order, is_enabled,
                                 created_at, updated_at, deleted_at, rev, device_id)
         VALUES (?, ?, ?, ?, ?, ?, 0, 1, ?, ?, NULL, 1, ?)`,
      ).run(
        row.id,
        row.parent_id,
        row.name,
        row.depth,
        row.icon,
        row.color,
        row.created_at,
        row.updated_at,
        row.device_id,
      );

      recordChange(db, {
        entityType: 'category',
        entityId: row.id,
        op: 'upsert',
        actorId: input.actorId,
        payload: toSyncCategory(row),
        deviceId: row.device_id,
      });
    });
  } catch (error) {
    if (isUniqueViolation(error)) throw conflict(`同一层级下已存在同名分类：${name}`);
    throw error;
  }

  return toNode(row);
}

export interface UpdateCategoryInput {
  name?: string | undefined;
  /**
   * 移动分类。`undefined` = 不动，`null` = 移到根（仅对一级有意义，
   * 对二级传 null 会被拒）。三种状态必须能区分，所以类型里带上 null。
   */
  parentId?: string | null | undefined;
  icon?: string | undefined;
  color?: string | undefined;
  sortOrder?: number | undefined;
  isEnabled?: boolean | undefined;
  actorId: string;
  deviceId?: string | null;
}

/**
 * 判断一次移动是否合法，并把结果 depth 返回（移动前后必然相同）。
 *
 * ## 为什么允许移动、但又只允许**同深度**移动
 *
 * 原先这里写着「刻意不支持改 parentId」，理由是会连带改变子分类的 depth 与归属。
 * 那个理由是成立的，但它推导出的结论太重了：默认分类树是给所有人用的模板，
 * 必然对不上每一家，而「二级分类挂错了组」恰恰是最常见的一种不对 ——
 * 把「外卖」从「餐饮」挪到「日常」这种操作，用户一天可能就想做一次，
 * 却只能停用重建（连带丢掉历史归属）。
 *
 * 真正的风险只在**跨深度**那一种：一级变二级会让它原本汇总的所有兄弟分类
 * 集体改归属，已有记录的分析粒度跟着变，且不可预期。
 * 二级在一级之间平移则只改一个分组标签，depth 不变、子分类结构不变
 * （二级不可能有子分类，见 MAX_CATEGORY_DEPTH）。
 *
 * 所以规则收敛成一句：**移动后 depth 必须不变。**
 */
function resolveMoveParent(
  db: DatabaseSync,
  existing: CategoryRow,
  nextParentId: string | null,
): void {
  if (existing.depth === 1) {
    // 一级分类的 parentId 只能是 null；传具体的父级等于把它降成二级
    throw badRequest(
      `「${existing.name}」是一级分类，只能移动二级分类。一级与二级之间的跨深度移动会让已有记录的分析粒度发生不可预期的变化`,
    );
  }

  if (nextParentId === null) {
    throw badRequest(`「${existing.name}」是二级分类，必须挂在一个一级分类下`);
  }

  if (nextParentId === existing.id) {
    throw badRequest('不能把分类移动到它自己下面');
  }

  const parent = findCategory(db, nextParentId);
  if (parent === null) throw badRequest(`目标分类不存在：${nextParentId}`);
  if (parent.depth !== 1) {
    throw badRequest(`只能移动到一级分类下，但「${parent.name}」不是一级分类`);
  }
  if (parent.is_enabled !== 1) {
    // 让移动成功但结果「看不见」（停用的一级会整组从记账选择器里消失）
    // 比直接拒绝更像一个 bug，所以拒绝。
    throw badRequest(`「${parent.name}」已停用，不能作为移动目标`);
  }
}

/**
 * 更新分类。
 *
 * 名字 / 图标 / 颜色随时可改（它们只是显示层，不动任何记录）；
 * 移动只允许**同深度**，理由见 `resolveMoveParent`。
 */
export function updateCategory(
  db: DatabaseSync,
  id: string,
  input: UpdateCategoryInput,
): CategoryNode {
  const existing = findCategory(db, id);
  if (existing === null) throw notFound(`分类不存在：${id}`);

  const name = input.name === undefined ? existing.name : input.name.trim();
  if (name === '') throw badRequest('分类名不能为空');
  if (name.length > 20) throw badRequest('分类名不能超过 20 个字');

  const nextParentId = input.parentId === undefined ? existing.parent_id : input.parentId;

  const next: CategoryRow = {
    ...existing,
    parent_id: nextParentId,
    name,
    icon: input.icon ?? existing.icon,
    color: input.color ?? existing.color,
    sort_order: input.sortOrder ?? existing.sort_order,
    is_enabled: (input.isEnabled ?? existing.is_enabled === 1) ? 1 : 0,
    updated_at: nowIso(),
    rev: existing.rev + 1,
    device_id: input.deviceId ?? existing.device_id,
  };

  try {
    inTransaction(db, () => {
      if (nextParentId !== existing.parent_id) resolveMoveParent(db, existing, nextParentId);

      // 重名检查必须按**目标层级**做：从「餐饮 · 外卖」挪到「日常」时，
      // 要撞的是「日常」下的同名，而不是「餐饮」下的
      assertNoSiblingName(db, next.parent_id, name, next.id);

      db.prepare(
        `UPDATE categories
            SET parent_id = ?, name = ?, icon = ?, color = ?, sort_order = ?, is_enabled = ?,
                updated_at = ?, rev = ?, device_id = ?
          WHERE id = ?`,
      ).run(
        next.parent_id,
        next.name,
        next.icon,
        next.color,
        next.sort_order,
        next.is_enabled,
        next.updated_at,
        next.rev,
        next.device_id,
        next.id,
      );

      recordChange(db, {
        entityType: 'category',
        entityId: next.id,
        op: 'upsert',
        actorId: input.actorId,
        payload: toSyncCategory(next),
        deviceId: next.device_id,
      });
    });
  } catch (error) {
    if (isUniqueViolation(error)) throw conflict(`同一层级下已存在同名分类：${name}`);
    throw error;
  }

  return toNode(next);
}

/**
 * 停用前的前置检查：该分类还有支出记录或子分类时不允许停用。
 *
 * 不做「自动把这些记录改成未分类」：那会让用户在毫无察觉的情况下失去
 * 一个月的分类维度，且几乎不可能恢复。宁可拦住他，让他先决定怎么处理。
 */
export function assertCategoryDeactivatable(db: DatabaseSync, id: string): void {
  const row = db
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM expenses WHERE category_id = ? AND deleted_at IS NULL) AS expenses,
         (SELECT COUNT(*) FROM categories WHERE parent_id = ? AND deleted_at IS NULL) AS children,
         (SELECT COUNT(*) FROM plans WHERE category_id = ? AND deleted_at IS NULL AND state = 'active') AS plans`,
    )
    .get(id, id, id);

  const expenses = row === undefined ? 0 : Number(row['expenses']);
  const children = row === undefined ? 0 : Number(row['children']);
  const plans = row === undefined ? 0 : Number(row['plans']);

  if (children > 0) {
    throw conflict(`该分类下还有 ${children} 个子分类，请先停用子分类`);
  }
  if (plans > 0) {
    throw conflict(
      `还有 ${plans} 个进行中的计划在用这个分类，请先结束它们或把计划改到别的分类`,
    );
  }
  if (expenses > 0) {
    throw conflict(`该分类下还有 ${expenses} 笔支出记录，请先把它们转移到别的分类`);
  }
}

/**
 * 删除分类。
 *
 * 仅允许删除既没有子分类、也没有支出记录、更没有进行中计划的分类
 * （例如误新建、或记录已全部转移腾空）。
 * 若已有支出记录，拦截并提示使用「停用」以维护历史账单完整性。
 * 进行中的计划（房贷/分期等）引用该分类时必须级联拦截：
 * 否则后续到期自动入账会因分类不可用而抛错，计划待办卡死。
 */
export function deleteCategory(
  db: DatabaseSync,
  id: string,
  actorId: string,
  deviceId?: string | null,
): void {
  const existing = findCategory(db, id);
  if (existing === null) throw notFound(`分类不存在：${id}`);

  const row = db
    .prepare(
      `SELECT
         (SELECT COUNT(*) FROM expenses WHERE category_id = ? AND deleted_at IS NULL) AS expenses,
         (SELECT COUNT(*) FROM categories WHERE parent_id = ? AND deleted_at IS NULL) AS children,
         (SELECT COUNT(*) FROM plans WHERE category_id = ? AND deleted_at IS NULL AND state = 'active') AS plans`,
    )
    .get(id, id, id);

  const expenses = row === undefined ? 0 : Number(row['expenses']);
  const children = row === undefined ? 0 : Number(row['children']);
  const plans = row === undefined ? 0 : Number(row['plans']);

  if (children > 0) {
    throw conflict(`该分类下还有 ${children} 个子分类，请先删除或移走子分类`);
  }
  if (plans > 0) {
    throw conflict(
      `还有 ${plans} 个进行中的计划在用这个分类，请先结束它们或把计划改到别的分类`,
    );
  }
  if (expenses > 0) {
    throw conflict(`该分类下已有 ${expenses} 笔支出记录。为保证历史账单完整，无法直接删除；若不再使用，可先转移记录或将其停用。`);
  }

  const timestamp = nowIso();
  inTransaction(db, () => {
    db.prepare(
      `UPDATE categories
          SET deleted_at = ?, updated_at = ?, rev = rev + 1, device_id = ?
        WHERE id = ?`,
    ).run(timestamp, timestamp, deviceId ?? null, id);

    recordChange(db, {
      entityType: 'category',
      entityId: id,
      op: 'delete',
      actorId,
      payload: { id, deletedAt: timestamp },
      deviceId: deviceId ?? null,
    });
  });
}
