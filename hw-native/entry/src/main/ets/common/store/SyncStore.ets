/**
 * 快照落地：把服务端全量状态写进本地库。
 *
 * ## 什么时候用
 *
 * 只在「本地是空的 / 换了账号 / 用户手动重建」时调一次。日常增量走
 * `SyncEngine` 的 pull（它复用同一套 `toBucket` 映射）。
 *
 * ## 关键约束：分类的 color / icon 不能覆盖
 *
 * 这两列在本地是**个性化偏好**（各端自己渲染），服务端不再存也不再下发。
 * 所以写分类时**只更新名称/层级/排序/启用状态**，颜色和图标保持本地值不动 ——
 * 否则每次同步都会把用户挑的配色冲掉。
 *
 * ## 为什么先清空再写入
 *
 * 快照是「当前全量状态」。若只做 upsert，服务端已删除的记录会永远留在本地
 * （离线看到早就删掉的账）。字典表与支出/计划表都先清空再灌。
 * 本地独有的东西（outbox 队列、meta 游标）**不清**。
 */
import { relationalStore } from '@kit.ArkData';

import { Db } from './Db';
import {
  Api,
  CategoryNode,
  ExpenseItem,
  PaymentMethodItem,
  PlanItem,
  PlanTodoItem,
  SyncSnapshotBody,
} from '../net/Api';

export class SyncStore {
  /** 拉快照并落库，返回快照点版本号（作为后续增量的游标） */
  static async bootstrap(): Promise<number> {
    const body: SyncSnapshotBody = await Api.syncSnapshot();
    await SyncStore.applySnapshot(body);
    return body.version;
  }

  static async applySnapshot(body: SyncSnapshotBody): Promise<void> {
    const store = Db.get();

    // 0. 用户：流水行的「记录人」靠它；不缓存的话整列是 ULID
    await store.executeSql('DELETE FROM users');
    for (const u of body.users) {
      const userBucket: relationalStore.ValuesBucket = {
        'id': u.id,
        'display_name': u.displayName,
        'role': u.role === undefined ? 'member' : u.role,
        'updated_at': new Date().toISOString()
      };
      await store.insert('users', userBucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }

    // 1. 分类：**保留本地 color/icon**（个性化），只同步名称与结构
    await SyncStore.mergeCategories(body.categories);

    // 2. 支付方式：同样保留本地 icon
    await SyncStore.mergePayments(body.paymentMethods);

    // 3. 支出 / 计划 / 待办：先清后灌（快照即全量）
    await store.executeSql('DELETE FROM expenses');
    for (const item of body.expenses) {
      await store.insert('expenses', SyncStore.expenseBucket(item),
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }

    await store.executeSql('DELETE FROM plan_todos');
    await store.executeSql('DELETE FROM plans');
    for (const plan of body.plans) {
      await store.insert('plans', SyncStore.planBucket(plan),
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
    for (const todo of body.planTodos) {
      await store.insert('plan_todos', SyncStore.todoBucket(todo),
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
    }
  }

  /**
   * 分类合并：**只更新契约字段**，color/icon 保留本地。
   *
   * 用「查已有 → 有则 UPDATE 名称类字段 / 无则 INSERT」而不是 REPLACE：
   * REPLACE 会把整行覆盖掉，本地配色就没了。
   */
  private static async mergeCategories(categories: CategoryNode[]): Promise<void> {
    const store = Db.get();
    const flatten: CategoryNode[] = [];
    for (const root of categories) {
      flatten.push(root);
      for (const child of root.children) {
        flatten.push(child);
      }
    }
    const seen: Set<string> = new Set<string>();
    for (const node of flatten) {
      seen.add(node.id);
      const rs = await store.querySql('SELECT id FROM categories WHERE id = ?', [node.id]);
      const exists = rs.goToFirstRow();
      rs.close();
      if (exists) {
        await store.executeSql(
          'UPDATE categories SET parent_id = ?, name = ?, depth = ?, sort_order = ?, is_enabled = ? WHERE id = ?',
          [node.parentId === null ? '' : node.parentId, node.name, node.depth, node.sortOrder,
            node.isEnabled ? 1 : 0, node.id]
        );
      } else {
        const bucket: relationalStore.ValuesBucket = {
          'id': node.id,
          'parent_id': node.parentId === null ? '' : node.parentId,
          'name': node.name,
          'depth': node.depth,
          // 新分类没有本地偏好：留空，由各端按名称派生颜色/图标
          'icon': '',
          'color': '',
          'sort_order': node.sortOrder,
          'is_enabled': node.isEnabled ? 1 : 0
        };
        await store.insert('categories', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    }
    // 服务端已不存在的分类：删掉（否则会残留在选择器里）
    const all = await store.querySql('SELECT id FROM categories');
    const stale: string[] = [];
    while (all.goToNextRow()) {
      const id = all.getString(all.getColumnIndex('id'));
      if (!seen.has(id)) {
        stale.push(id);
      }
    }
    all.close();
    for (const id of stale) {
      await store.executeSql('DELETE FROM categories WHERE id = ?', [id]);
    }
  }

  /** 支付方式合并：同样保留本地 icon */
  private static async mergePayments(items: PaymentMethodItem[]): Promise<void> {
    const store = Db.get();
    const seen: Set<string> = new Set<string>();
    for (const p of items) {
      seen.add(p.id);
      const rs = await store.querySql('SELECT id FROM payment_methods WHERE id = ?', [p.id]);
      const exists = rs.goToFirstRow();
      rs.close();
      if (exists) {
        await store.executeSql(
          'UPDATE payment_methods SET name = ?, type = ?, billing_day = ?, repayment_day = ?, is_enabled = ?, sort_order = ? WHERE id = ?',
          [p.name, p.type, p.billingDay === null ? 0 : p.billingDay,
            p.repaymentDay === null ? 0 : p.repaymentDay, p.isEnabled ? 1 : 0, p.sortOrder, p.id]
        );
      } else {
        const bucket: relationalStore.ValuesBucket = {
          'id': p.id,
          'name': p.name,
          'type': p.type,
          'icon': '',
          'billing_day': p.billingDay === null ? 0 : p.billingDay,
          'repayment_day': p.repaymentDay === null ? 0 : p.repaymentDay,
          'is_enabled': p.isEnabled ? 1 : 0,
          'sort_order': p.sortOrder
        };
        await store.insert('payment_methods', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    }
    const all = await store.querySql('SELECT id FROM payment_methods');
    const stale: string[] = [];
    while (all.goToNextRow()) {
      const id = all.getString(all.getColumnIndex('id'));
      if (!seen.has(id)) {
        stale.push(id);
      }
    }
    all.close();
    for (const id of stale) {
      await store.executeSql('DELETE FROM payment_methods WHERE id = ?', [id]);
    }
  }

  private static expenseBucket(item: ExpenseItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': item.id,
      'owner_id': item.ownerId,
      'amount_cents': item.amountCents,
      'category_id': item.categoryId,
      'payment_method_id': item.paymentMethodId,
      'spend_date': item.spendDate,
      'posting_date': item.postingDate,
      'repayment_date': item.repaymentDate,
      'note': item.note,
      'source': item.source,
      'plan_id': item.planId === undefined || item.planId === null ? '' : item.planId,
      'plan_period_seq': item.planPeriodSeq === undefined || item.planPeriodSeq === null ? 0 : item.planPeriodSeq,
      'updated_at': new Date().toISOString()
    };
    return bucket;
  }

  private static planBucket(plan: PlanItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': plan.id,
      'name': plan.name,
      'category_id': plan.categoryId,
      'payment_method_id': plan.paymentMethodId,
      'amount_cents': plan.amountCents,
      'first_due_date': plan.firstDueDate,
      'auto_post': plan.autoPost ? 1 : 0,
      'source': plan.source,
      'state': plan.state,
      'updated_at': new Date().toISOString()
    };
    return bucket;
  }

  private static todoBucket(todo: PlanTodoItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': todo.id,
      'plan_id': todo.planId,
      'plan_name': todo.planName,
      'period_seq': todo.periodSeq,
      'amount_cents': todo.amountCents,
      'repayment_date': todo.repaymentDate,
      'status': todo.status,
      'will_auto_post': todo.willAutoPost ? 1 : 0,
      'expense_id': todo.expenseId === undefined || todo.expenseId === null ? '' : todo.expenseId,
      'posted_date': todo.postedDate === undefined || todo.postedDate === null ? '' : todo.postedDate,
      'ack_at': todo.ackAt === undefined || todo.ackAt === null ? '' : todo.ackAt,
      'updated_at': new Date().toISOString()
    };
    return bucket;
  }
}
