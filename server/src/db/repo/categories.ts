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
 * 新记账的选择列表）。expense_count 用相关子查询一次带出，避免前端 N+1。
 */
export function listCategoryRows(db: DatabaseSync): CategoryRow[] {
  const rows = db
    .prepare(
      `SELECT ${COLUMNS},
              (SELECT COUNT(*) FROM expenses e
                WHERE e.category_id = categories.id AND e.deleted_at IS NULL) AS expense_count
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
  icon?: string | undefined;
  color?: string | undefined;
  sortOrder?: number | undefined;
  isEnabled?: boolean | undefined;
  actorId: string;
  deviceId?: string | null;
}

/**
 * 更新分类。
 *
 * 刻意**不支持改 parentId**：移动分类会连带改变其子分类的 depth 与
 * 归属，而分类树同时被历史记录、报表分组、权限展示引用着。这个功能
 * 的收益（换个分组）远小于它可能造成的错乱，需要时手动停用旧的、建新的。
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

  const next: CategoryRow = {
    ...existing,
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
      assertNoSiblingName(db, next.parent_id, name, next.id);

      db.prepare(
        `UPDATE categories
            SET name = ?, icon = ?, color = ?, sort_order = ?, is_enabled = ?,
                updated_at = ?, rev = ?, device_id = ?
          WHERE id = ?`,
      ).run(
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
         (SELECT COUNT(*) FROM categories WHERE parent_id = ? AND deleted_at IS NULL) AS children`,
    )
    .get(id, id);

  const expenses = row === undefined ? 0 : Number(row['expenses']);
  const children = row === undefined ? 0 : Number(row['children']);

  if (children > 0) {
    throw conflict(`该分类下还有 ${children} 个子分类，请先停用子分类`);
  }
  if (expenses > 0) {
    throw conflict(`该分类下还有 ${expenses} 笔支出记录，请先把它们转移到别的分类`);
  }
}
