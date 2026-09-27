import type { DatabaseSync } from 'node:sqlite';

import type { PaymentCycle } from '../../domain/billing-cycle.ts';
import { badRequest, conflict, notFound } from '../../lib/http-error.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange } from '../sync.ts';

export type PaymentMethodType = 'cash' | 'credit';

export interface PaymentMethodRow {
  id: string;
  name: string;
  type: PaymentMethodType;
  billing_day: number | null;
  repayment_day: number | null;
  is_enabled: number;
  sort_order: number;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
  expense_count?: number;
}

export interface PaymentMethod {
  id: string;
  name: string;
  type: PaymentMethodType;
  /** 账单日 / 入账日。仅信用类有值 */
  billingDay: number | null;
  /** 还款日。仅信用类有值 */
  repaymentDay: number | null;
  isEnabled: boolean;
  sortOrder: number;
  expenseCount: number;
}

const COLUMNS = `id, name, type, billing_day, repayment_day, is_enabled, sort_order,
                 created_at, updated_at, deleted_at, rev, device_id`;

const nowIso = (): string => new Date().toISOString();

function toApi(row: PaymentMethodRow): PaymentMethod {
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    billingDay: row.billing_day,
    repaymentDay: row.repayment_day,
    isEnabled: row.is_enabled === 1,
    sortOrder: row.sort_order,
    expenseCount: row.expense_count ?? 0,
  };
}

export function toSyncPaymentMethod(row: PaymentMethodRow): Record<string, unknown> {
  return {
    id: row.id,
    name: row.name,
    type: row.type,
    billingDay: row.billing_day,
    repaymentDay: row.repayment_day,
    isEnabled: row.is_enabled === 1,
    sortOrder: row.sort_order,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    rev: row.rev,
  };
}

/**
 * 把支付方式转成账单周期描述，交给 `domain/billing-cycle` 去推算日期。
 *
 * 这是「配置」与「算法」之间唯一的接缝：支付方式表只描述事实（账单日几号、
 * 还款日几号），「消费日怎么映射到入账日与还款日」的规则全部在领域层，
 * 且被单元测试覆盖。任何一边改动都不会让另一边悄悄失去约束。
 */
export function toPaymentCycle(row: PaymentMethodRow): PaymentCycle {
  if (row.type === 'cash') return { type: 'cash' };
  if (row.billing_day === null || row.repayment_day === null) {
    // schema 的 CHECK 已保证不会出现，这里是防止将来有人绕过约束写数据的兜底
    throw badRequest(`信用类支付方式「${row.name}」缺少账单日或还款日`);
  }
  return { type: 'credit', billingDay: row.billing_day, repaymentDay: row.repayment_day };
}

/**
 * 列表顺序即「新记账时的默认选项顺序」，所以要慎重。
 *
 * **不要只按 name 排**：中文在 SQLite 里走 BINARY 排序，即按 UTF-8 字节序比较，
 * 「招行信用卡」的「招」(U+62DB) 会排在「现金」的「现」(U+73B0) 前面 ——
 * 结果是「现金」不是第一个，而记账抽屉默认选中第一项，于是用户随手记的一笔
 * 用了信用卡，还款日落到下个月，本月报表纹丝不动（看起来就像没记上）。
 *
 * 改用 `created_at`：它的先后顺序反映了用户自己的建立顺序，
 * 而「先建的排前面」也符合直觉。
 */
export function listPaymentMethods(db: DatabaseSync): PaymentMethod[] {
  const rows = db
    .prepare(
      `SELECT ${COLUMNS},
              (SELECT COUNT(*) FROM expenses e
                WHERE e.payment_method_id = payment_methods.id AND e.deleted_at IS NULL) AS expense_count
         FROM payment_methods
        WHERE deleted_at IS NULL
        -- rowid 是精确的插入序兜底：created_at 只到毫秒，同一毫秒内建的两条会打平，
        -- 一打平就退回按 name 比，上面那个坑就会复现。rowid 不会打平。
        ORDER BY sort_order, created_at, rowid, name`,
    )
    .all();
  return (rows as unknown as PaymentMethodRow[]).map(toApi);
}

export function findPaymentMethod(db: DatabaseSync, id: string): PaymentMethodRow | null {
  const row = db
    .prepare(`SELECT ${COLUMNS} FROM payment_methods WHERE id = ? AND deleted_at IS NULL`)
    .get(id);
  return (row as unknown as PaymentMethodRow | undefined) ?? null;
}

/** 取一个「可用于新记账」的支付方式：必须存在、必须启用。 */
export function requireUsablePaymentMethod(db: DatabaseSync, id: string): PaymentMethodRow {
  const row = findPaymentMethod(db, id);
  if (row === null) throw badRequest(`支付方式不存在：${id}`);
  if (row.is_enabled !== 1) throw badRequest(`支付方式已停用，不能用于新记录：${row.name}`);
  return row;
}

/**
 * 见 categories.ts 里同类注释：SQLite 对唯一约束的报错格式**不统一**
 * （单列索引报 `table.column`，表达式索引报 `index '名字'`），
 * 所以正常路径用显式 SELECT 判重，错误识别只作兜底。
 */
function isUniqueViolation(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.startsWith('UNIQUE constraint failed');
}

/** 重名检查。在写事务内调用，消除「先查后写」之间的竞态窗口。 */
function assertNoNameTaken(db: DatabaseSync, name: string, excludeId?: string): void {
  const row = db
    .prepare('SELECT id FROM payment_methods WHERE name = ? AND deleted_at IS NULL AND id <> ?')
    .get(name, excludeId ?? '');

  if (row !== undefined) throw conflict(`已存在同名支付方式：${name}`);
}

/**
 * 校验账单周期参数。
 *
 * 「现金类不许填账单日/还款日」这条同样在 schema 里用 CHECK 兜着，这里
 * 提前拦住是为了给出人话的错误提示 —— 数据库约束报错长这样：
 * `CHECK constraint failed: (type = 'cash' AND billing_day IS N`，用户看不懂。
 */
function normalizeCycle(
  type: PaymentMethodType,
  billingDay: number | undefined,
  repaymentDay: number | undefined,
): { billing: number | null; repayment: number | null } {
  if (type === 'cash') {
    if (billingDay !== undefined || repaymentDay !== undefined) {
      throw badRequest('现金 / 储蓄卡没有账单周期，不需要账单日与还款日');
    }
    return { billing: null, repayment: null };
  }

  if (billingDay === undefined || repaymentDay === undefined) {
    throw badRequest('信用卡必须同时提供账单日与还款日');
  }

  for (const [label, value] of [
    ['账单日', billingDay],
    ['还款日', repaymentDay],
  ] as const) {
    if (value < 1 || value > 31) {
      throw badRequest(`${label}必须在 1–31 之间，收到 ${value}`);
    }
  }

  return { billing: billingDay, repayment: repaymentDay };
}

export interface CreatePaymentMethodInput {
  name: string;
  type: PaymentMethodType;
  /**
   * 可选字段显式写上 `| undefined`：tsconfig 开了 exactOptionalPropertyTypes，
   * 不加这一句的话「调用方传了一个值为 undefined 的字段」会被当成类型错误。
   * 而路由层从请求体里取值时，「字段不存在」与「字段存在但为空」都得能传进来。
   */
  billingDay?: number | undefined;
  repaymentDay?: number | undefined;
  sortOrder?: number | undefined;
  actorId: string;
  deviceId?: string | null;
}

export function createPaymentMethod(
  db: DatabaseSync,
  input: CreatePaymentMethodInput,
): PaymentMethod {
  const name = input.name.trim();
  if (name === '') throw badRequest('支付方式名称不能为空');
  if (name.length > 20) throw badRequest('支付方式名称不能超过 20 个字');

  const cycle = normalizeCycle(input.type, input.billingDay, input.repaymentDay);
  const timestamp = nowIso();

  const row: PaymentMethodRow = {
    id: ulid(),
    name,
    type: input.type,
    billing_day: cycle.billing,
    repayment_day: cycle.repayment,
    is_enabled: 1,
    sort_order: input.sortOrder ?? 0,
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: input.deviceId ?? null,
  };

  try {
    inTransaction(db, () => {
      assertNoNameTaken(db, name);

      db.prepare(
        `INSERT INTO payment_methods (id, name, type, billing_day, repayment_day, is_enabled,
                                      sort_order, created_at, updated_at, deleted_at, rev, device_id)
         VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, NULL, 1, ?)`,
      ).run(
        row.id,
        row.name,
        row.type,
        row.billing_day,
        row.repayment_day,
        row.sort_order,
        row.created_at,
        row.updated_at,
        row.device_id,
      );

      recordChange(db, {
        entityType: 'payment_method',
        entityId: row.id,
        op: 'upsert',
        actorId: input.actorId,
        payload: toSyncPaymentMethod(row),
        deviceId: row.device_id,
      });
    });
  } catch (error) {
    if (isUniqueViolation(error)) throw conflict(`已存在同名支付方式：${name}`);
    throw error;
  }

  return toApi(row);
}

export interface UpdatePaymentMethodInput {
  name?: string | undefined;
  billingDay?: number | undefined;
  repaymentDay?: number | undefined;
  sortOrder?: number | undefined;
  isEnabled?: boolean | undefined;
  actorId: string;
  deviceId?: string | null;
}

/**
 * 更新支付方式。
 *
 * 允许改账单日与还款日 —— 银行调整账单周期是真实会发生的。已入账记录里
 * 冗余存的 posting_date / repayment_date **不会**被回溯修改，这是有意的：
 * 历史记录反映的是当时的账单规则，改配置不该让上个月的报表数字变化。
 */
export function updatePaymentMethod(
  db: DatabaseSync,
  id: string,
  input: UpdatePaymentMethodInput,
): PaymentMethod {
  const existing = findPaymentMethod(db, id);
  if (existing === null) throw notFound(`支付方式不存在：${id}`);

  const name = input.name === undefined ? existing.name : input.name.trim();
  if (name === '') throw badRequest('支付方式名称不能为空');

  const cycle = normalizeCycle(
    existing.type,
    input.billingDay ?? existing.billing_day ?? undefined,
    input.repaymentDay ?? existing.repayment_day ?? undefined,
  );

  const next: PaymentMethodRow = {
    ...existing,
    name,
    billing_day: cycle.billing,
    repayment_day: cycle.repayment,
    sort_order: input.sortOrder ?? existing.sort_order,
    is_enabled: (input.isEnabled ?? existing.is_enabled === 1) ? 1 : 0,
    updated_at: nowIso(),
    rev: existing.rev + 1,
    device_id: input.deviceId ?? existing.device_id,
  };

  if (next.is_enabled === 0) {
    assertPaymentMethodDeactivatable(db, id);
  }

  try {
    inTransaction(db, () => {
      assertNoNameTaken(db, name, next.id);

      db.prepare(
        `UPDATE payment_methods
            SET name = ?, billing_day = ?, repayment_day = ?, sort_order = ?, is_enabled = ?,
                updated_at = ?, rev = ?, device_id = ?
          WHERE id = ?`,
      ).run(
        next.name,
        next.billing_day,
        next.repayment_day,
        next.sort_order,
        next.is_enabled,
        next.updated_at,
        next.rev,
        next.device_id,
        next.id,
      );

      recordChange(db, {
        entityType: 'payment_method',
        entityId: next.id,
        op: 'upsert',
        actorId: input.actorId,
        payload: toSyncPaymentMethod(next),
        deviceId: next.device_id,
      });
    });
  } catch (error) {
    if (isUniqueViolation(error)) throw conflict(`已存在同名支付方式：${name}`);
    throw error;
  }

  return toApi(next);
}

/**
 * 停用支付方式的前置检查。
 *
 * 这里**只拦「进行中的计划」**，不拦历史支出 —— 这一点与分类不同：
 *
 *   分类可以「转移记录」（把「餐饮 / 外卖」下的记录挪到「餐饮 / 下馆子」）
 *   支付方式不行：它是**历史事实**，「这笔是招行卡付的」没有替代品，
 *   也不该被改写。若因为存在历史记录就禁止停用，那这张卡将永远无法退休。
 *
 * 所以只要没有活跃计划继续依赖它，就允许停用。停用后它从新记账的选择列表
 * 消失，但历史记录的显示与报表统计完全不受影响。
 */
export function assertPaymentMethodDeactivatable(db: DatabaseSync, id: string): void {
  const row = db
    .prepare(
      `SELECT COUNT(*) AS plans
         FROM plans
        WHERE payment_method_id = ? AND deleted_at IS NULL AND state = 'active'`,
    )
    .get(id);

  const plans = row === undefined ? 0 : Number(row['plans']);

  if (plans > 0) {
    throw conflict(`还有 ${plans} 个进行中的计划在用这个支付方式，请先结束它们或把计划改到别的支付方式`);
  }
}
