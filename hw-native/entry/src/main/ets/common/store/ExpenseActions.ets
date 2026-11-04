/**
 * 记账动作：**本地先写 + 入队 + 触发同步**。
 *
 * ## 为什么本地要自己算账单日期
 *
 * `posting_date` / `repayment_date` 决定这笔账归属哪个月（报表按还款日聚合），
 * 不能留空等同步回填 —— 否则本地列表在同步前会把它归到错误的月份。
 * 算法与服务端 `domain/billing-cycle.ts` 一一对应（见 `BillingCycle.ets`），
 * 同步回推后服务端会再算一次并以它为准。
 *
 * ## 归属
 *
 * `owner_id` 取当前登录用户 —— **谁记归谁**。服务端补推时用令牌里的 actor 再确认一次。
 */
import { Db } from './Db';
import { Outbox } from '../sync/Outbox';
import { SyncEngine } from '../sync/SyncEngine';
import { ReportCache } from './ReportCache';
import { AuthStore } from '../auth/AuthStore';
import { ulid } from '../contract/Contract';
import { PaymentCycle, resolveExpenseDates, ResolvedDates } from '../contract/BillingCycle';
import { PaymentMethodItem } from '../net/Api';

/** 本地修改的字段集合（ArkTS 不接受内联对象字面量作参数，必须具名） */
export interface LocalExpensePatch {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
}

export interface LocalExpenseInput {
  amountCents: number;
  categoryId: string;
  paymentMethodId: string;
  spendDate: string;
  note: string;
  /** 该支付方式的账单周期（从本地 payment_methods 取） */
  cycle: PaymentCycle;
}

export class ExpenseActions {
  /** 本地新增：算日期 → 写本地 → 入队 → 触发同步，返回新记录 id */
  static async create(input: LocalExpenseInput): Promise<string> {
    const id = ulid();
    const dates: ResolvedDates = resolveExpenseDates(input.spendDate, input.cycle);
    // 离线启动时 AuthStore.user 为 null，用登录时落库的 id 兜底 ——
    // 归属不能空，否则这笔账在服务端归不到人。
    let ownerId = AuthStore.user === null ? '' : AuthStore.user.id;
    if (ownerId === '') {
      ownerId = await ExpenseActions.cachedUserId();
    }
    const now = new Date().toISOString();

    await Db.get().executeSql(
      `INSERT OR REPLACE INTO expenses
        (id, owner_id, amount_cents, category_id, payment_method_id, spend_date,
         posting_date, repayment_date, note, source, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, ownerId, input.amountCents, input.categoryId, input.paymentMethodId,
        input.spendDate, dates.postingDate, dates.repaymentDate, input.note, 'manual', now]
    );

    const payload = JSON.stringify({
      id: id,
      amountCents: input.amountCents,
      categoryId: input.categoryId,
      paymentMethodId: input.paymentMethodId,
      spendDate: input.spendDate,
      note: input.note
    });
    await Outbox.enqueue('create_expense', id, payload);
    await ReportCache.invalidateAll();
    SyncEngine.schedulePush();
    return id;
  }

  /** 本地修改：先改本地再入队。金额/分类/支付方式/消费日改动会重算账单日期 */
  static async update(id: string, patch: LocalExpensePatch, cycle: PaymentCycle): Promise<void> {
    const dates: ResolvedDates = resolveExpenseDates(patch.spendDate, cycle);
    await Db.get().executeSql(
      `UPDATE expenses SET amount_cents = ?, category_id = ?, payment_method_id = ?,
         spend_date = ?, posting_date = ?, repayment_date = ?, note = ?, updated_at = ?
       WHERE id = ?`,
      [patch.amountCents, patch.categoryId, patch.paymentMethodId, patch.spendDate,
        dates.postingDate, dates.repaymentDate, patch.note, new Date().toISOString(), id]
    );
    await Outbox.enqueue('update_expense', id, JSON.stringify({
      id: id,
      amountCents: patch.amountCents,
      categoryId: patch.categoryId,
      paymentMethodId: patch.paymentMethodId,
      spendDate: patch.spendDate,
      note: patch.note
    }));
    await ReportCache.invalidateAll();
    SyncEngine.schedulePush();
  }

  /** 本地删除：先删本地再入队 */
  static async remove(id: string): Promise<void> {
    await Db.get().executeSql('DELETE FROM expenses WHERE id = ?', [id]);
    await Outbox.enqueue('delete_expense', id, JSON.stringify({ id: id }));
    await ReportCache.invalidateAll();
    SyncEngine.schedulePush();
  }

  /** 上次登录的用户 id（登录时写进 meta） */
  private static async cachedUserId(): Promise<string> {
    const rs = await Db.get().querySql('SELECT value FROM meta WHERE key = ?', ['current_user_id']);
    let id = '';
    if (rs.goToFirstRow()) {
      id = rs.getString(rs.getColumnIndex('value'));
    }
    rs.close();
    return id;
  }

  /** 从本地支付方式表取账单周期；查不到按现金处理（入账日=还款日=消费日） */
  static async cycleOf(paymentMethodId: string): Promise<PaymentCycle> {
    const rs = await Db.get().querySql(
      'SELECT type, billing_day, repayment_day FROM payment_methods WHERE id = ?',
      [paymentMethodId]
    );
    let cycle: PaymentCycle = { type: 'cash', billingDay: 0, repaymentDay: 0 };
    if (rs.goToFirstRow()) {
      cycle = {
        type: rs.getString(rs.getColumnIndex('type')),
        billingDay: rs.getLong(rs.getColumnIndex('billing_day')),
        repaymentDay: rs.getLong(rs.getColumnIndex('repayment_day'))
      };
    }
    rs.close();
    return cycle;
  }
}
