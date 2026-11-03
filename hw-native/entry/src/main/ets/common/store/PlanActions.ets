/**
 * 待办动作：**本地先写 + 入队 + 触发同步**。
 *
 * ## 为什么不再直接调接口
 *
 * 本地优先之后，任何写操作都必须先落到本地 —— 否则断网时点了「入账」没反应，
 * 或者要等网络往返才有反馈。这里统一做三件事：
 *   1. 改本地 `plan_todos` 的状态（界面立刻变）；
 *   2. 把动作塞进 outbox（关掉 App 也不会丢）；
 *   3. 触发一次同步（联网时几秒内回推，断网时留在队列里）。
 *
 * ## 为什么先写本地、再入队
 *
 * 顺序不能反：先入队再写本地的话，如果本地写失败，队列里会有一条
 * 「服务端会执行、但本地状态没变」的动作 —— 界面和服务端长期不一致。
 * 本地写失败就直接抛错，队列不动。
 *
 * ## 失败补偿
 *
 * 回推成功后由 `SyncEngine` 的 pull 把服务端的权威状态拉回来覆盖本地，
 * 所以这里不需要写复杂的回滚逻辑。
 */
import { Db } from './Db';
import { Outbox } from '../sync/Outbox';
import { SyncEngine } from '../sync/SyncEngine';

export class PlanActions {
  /** 入账（手动确认）。`spendDate` 为空时按还款日入账（与服务端一致） */
  static async confirm(id: string, spendDate: string = ''): Promise<void> {
    const today = new Date().toISOString().substring(0, 10);
    await Db.get().executeSql(
      "UPDATE plan_todos SET status = 'confirmed', posted_date = ?, updated_at = ? WHERE id = ?",
      [spendDate === '' ? today : spendDate, new Date().toISOString(), id]
    );
    await Outbox.enqueue('confirm_todo', id, JSON.stringify({ id: id, spendDate: spendDate }));
    SyncEngine.schedulePush();
  }

  /** 跳过本期（「这次别提醒我」；逾期后非自动入账的还会重现） */
  static async skip(id: string): Promise<void> {
    await Db.get().executeSql(
      "UPDATE plan_todos SET status = 'skipped', updated_at = ? WHERE id = ?",
      [new Date().toISOString(), id]
    );
    await Outbox.enqueue('skip_todo', id, JSON.stringify({ id: id }));
    SyncEngine.schedulePush();
  }

  /** 我知道了（摘掉提醒，不改期次状态） */
  static async ack(id: string): Promise<void> {
    await Db.get().executeSql(
      'UPDATE plan_todos SET ack_at = ?, updated_at = ? WHERE id = ?',
      [new Date().toISOString(), new Date().toISOString(), id]
    );
    await Outbox.enqueue('ack_todo', id, JSON.stringify({ id: id }));
    SyncEngine.schedulePush();
  }

  /** 撤销确认（confirmed → pending，服务端会顺带软删生成的支出） */
  static async revert(id: string): Promise<void> {
    await Db.get().executeSql(
      "UPDATE plan_todos SET status = 'pending', posted_date = NULL, expense_id = NULL, updated_at = ? WHERE id = ?",
      [new Date().toISOString(), id]
    );
    await Outbox.enqueue('revert_todo', id, JSON.stringify({ id: id }));
    SyncEngine.schedulePush();
  }

  /** 恢复跳过（skipped → pending） */
  static async restore(id: string): Promise<void> {
    await Db.get().executeSql(
      "UPDATE plan_todos SET status = 'pending', updated_at = ? WHERE id = ?",
      [new Date().toISOString(), id]
    );
    await Outbox.enqueue('restore_todo', id, JSON.stringify({ id: id }));
    SyncEngine.schedulePush();
  }
}
