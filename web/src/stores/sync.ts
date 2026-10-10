import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

import {
  sync as syncApi,
  ApiError,
  detectAndSwitchServer,
  getActiveServerUrl,
  onConnectivityChange,
} from '@/api';
import { onAppResume, onNetworkChange } from '@/platform';
import type { Expense } from '@/api/types';
import {
  addOutboxItem,
  deleteCachedExpense,
  getDeviceId,
  getMeta,
  getOutboxDeadLetters,
  getOutboxItems,
  getCachedPlanTodos,
  isIdbSupported,
  removeOutboxItems,
  saveSingleCachedExpense,
  setMeta,
  updateCachedExpense,
  updateCachedPlanTodo,
  OfflineStorageError,
  type DeadLetterSummary,
  type OutboxItem,
} from '@/utils/idb';
import { ulid } from '@/utils/ulid';
import { useAuthStore } from './auth';
import { useDictionariesStore } from './dictionaries';
import { usePlansStore } from './plans';

/**
 * Outbox 单条推送失败的重试上限：
 * 超过后该条进入死信隔离（不再参与推送），防止毒丸数据永久卡死队列。
 */
const OUTBOX_MAX_RETRY = 3;

/**
 * 离线写入失败时抛给上层的错误。
 *
 * 为什么必须冒泡：离线写路径是「先落本地、再排队、后同步」，任何一步写失败都意味着
 * 这一笔操作既没进本地缓存、也没进待发队列。若这里假装成功，UI 会照常提示「记好了」，
 * 用户以为账记上了，实际设备上根本不存在这笔账 —— 无感知丢账。
 *
 * 消息写成人话是为了让组件层直接展示（组件层负责弹提示，本层不弹）。
 */
export class OfflineWriteError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = 'OfflineWriteError';
  }
}

/** 把底层存储异常统一转成可直接展示给用户的文案 */
function toOfflineWriteError(action: string, err: unknown): OfflineWriteError {
  const detail =
    err instanceof OfflineStorageError ? err.message : '存储空间不足或被系统清理，请检查设备存储后重试';
  return new OfflineWriteError(`${action}失败：${detail}`, { cause: err });
}

/**
 * 包裹离线写路径：写入失败时抛出可展示的错误，且不触发 scheduleSync。
 *
 * 不做「写失败也照样调度同步」是因为队列里根本没有这笔操作，
 * 调度同步只会做一次无意义的网络往返，并让 UI 误以为已入队。
 */
async function writeOffline(action: string, run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (err) {
    throw toOfflineWriteError(action, err);
  }
}

export const useSyncStore = defineStore('sync', () => {
  // 必须基于实际服务端探测，不能仅凭 navigator.onLine 判定连通
  const isOnline = ref(false);
  const activeServerUrl = ref<string | null>(getActiveServerUrl());
  const isSyncing = ref(false);
  const pendingCount = ref(0);
  const lastSyncedAt = ref<string | null>(null);
  const lastSyncVersion = ref(0);
  const lastError = ref<string | null>(null);
  const initialized = ref(false);

  /**
   * 死信条目（服务端多次拒绝、已不再自动重试的离线操作）摘要，只读供 UI 展示。
   *
   * 语义：这些条目既不会被 pushOutbox 推送（已被 retryCount 过滤），
   * 也不会计入 pendingCount（那会让「待同步」数字虚高、且暗示还在重试）。
   * 但它们是用户真实存在、且永远同步不上去的账，绝不能悄悄藏起来 ——
   * 所以单独计数、单独暴露，让用户至少知道有这么几笔需要手工处理。
   */
  const deadLetters = ref<DeadLetterSummary[]>([]);

  const hasPending = computed(() => pendingCount.value > 0);
  const deadLetterCount = computed(() => deadLetters.value.length);

  let syncDebounceTimer: ReturnType<typeof setTimeout> | undefined;
  let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
  let retryTimer: ReturnType<typeof setTimeout> | undefined;

  /**
   * 失败退避重试节奏：5s -> 10s -> 30s 封顶。
   *
   * 存在的理由：安卓 WebView 里 online/offline 事件不可靠，若 push 一次性失败后
   * 只记 lastError 而不重试，离线队列会永久卡住、待同步角标一直不消失。
   * 失败后主动安排重试；逐级拉长的间隔避免在确实离线时疯狂打网络。
   */
  const RETRY_BACKOFF_MS = [5000, 10000, 30000];
  let retryAttempt = 0;

  /** 复位退避节奏（同步成功或队列已清空时调用），并取消尚未触发的重试 */
  function resetRetry(): void {
    retryAttempt = 0;
    if (retryTimer) {
      clearTimeout(retryTimer);
      retryTimer = undefined;
    }
  }

  /** 同步失败后安排一次退避重试；队列已空则不再重试 */
  function scheduleRetry(): void {
    if (!hasPending.value) {
      resetRetry();
      return;
    }
    const delay = RETRY_BACKOFF_MS[Math.min(retryAttempt, RETRY_BACKOFF_MS.length - 1)] ?? 30000;
    retryAttempt++;
    if (retryTimer) clearTimeout(retryTimer);
    retryTimer = setTimeout(() => {
      retryTimer = undefined;
      void runSync();
    }, delay);
  }

  /**
   * 心跳兜底探测：每 10s 一次，仅在「当前认为离线」或「还有待同步数据」时才真正探测。
   *
   * 不能依赖 WebView 的网络事件来判断恢复（真机实测断网再恢复后应用仍停留在离线态），
   * 所以用定时轮询兜底：网络真回来时最多 10s 内自动恢复连通、补推离线队列。
   * 先清理旧的句柄，保证重复调用不会注册出两份定时器。
   */
  function startHeartbeat(): void {
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    heartbeatTimer = setInterval(() => {
      if (!isOnline.value || hasPending.value) {
        void checkConnectivity().then((connected) => {
          if (connected && hasPending.value) void runSync();
        });
      }
    }, 10000);
  }

  /**
   * 客户端本地操作主动触发防抖同步（默认 300ms）。
   * 连续操作（如多笔记账、分类调整、计划确认）合并为单次批量同步，避免网络请求风暴。
   */
  function scheduleSync(delayMs = 300): void {
    if (syncDebounceTimer) clearTimeout(syncDebounceTimer);
    syncDebounceTimer = setTimeout(() => {
      if (isOnline.value) {
        void runSync();
      } else {
        void checkConnectivity().then((connected) => {
          if (connected) void runSync();
        });
      }
    }, delayMs);
  }

  /**
   * 刷新待发送 Outbox 队列条数与死信列表。
   *
   * pendingCount 刻意排除死信：它们不会再被推送，算进去会让「待同步 N 条」虚高，
   * 让人误以为还有 N 笔在排队。死信改由 deadLetterCount 独立呈现。
   */
  async function refreshPendingCount(): Promise<void> {
    if (!isIdbSupported()) return;
    const items = await getOutboxItems();
    pendingCount.value = items.filter((i) => i.retryCount <= OUTBOX_MAX_RETRY).length;
    deadLetters.value = await getOutboxDeadLetters(OUTBOX_MAX_RETRY);
  }

  /**
   * 探测服务端连通性：按服务端 1 -> 2 -> 3 顺序依次检测，自动寻找并切换至第一个可用地址
   */
  async function checkConnectivity(): Promise<boolean> {
    const result = await detectAndSwitchServer();
    const connected = result.url !== null;
    isOnline.value = connected;
    activeServerUrl.value = result.url;
    return connected;
  }

  /**
   * 初始化同步管理器：
   * 1. 恢复本地 IndexedDB 记录的同步版本号与时间；
   * 2. 挂载网络切换监听（含离线/在线以及 移动网络 ↔ Wi-Fi 切换）；
   * 3. 挂载应用前台唤醒监听（打开软件、切回前台）；
   * 4. 启动心跳兜底轮询（WebView 网络事件不可靠）；
   * 5. 实时探测最优服务端真实连通性；
   * 6. 触发首次补偿与增量拉取。
   */
  async function init(): Promise<void> {
    if (initialized.value || !isIdbSupported()) return;

    try {
      lastSyncVersion.value = await getMeta<number>('last_sync_version', 0);
      lastSyncedAt.value = await getMeta<string | null>('last_synced_at', null);
      await refreshPendingCount();
    } catch {
      // 忽略本地元信息读取失败
    }

    // 监听网络底层状态变更
    onConnectivityChange((online, activeUrl) => {
      isOnline.value = online;
      activeServerUrl.value = activeUrl;
    });

    // 1. 监听网络切换（移动切wifi、wifi切移动、离线切在线）
    onNetworkChange((online) => {
      if (online) {
        void checkConnectivity().then((connected) => {
          if (connected) void runSync();
        });
      } else {
        isOnline.value = false;
      }
    });

    // 2. 监听前台恢复（打开软件、切回前台、页面可见）
    onAppResume(() => {
      void checkConnectivity().then((connected) => {
        if (connected) void runSync();
      });
    });

    initialized.value = true;

    // 4. 启动心跳兜底（WebView 网络事件不可靠，靠它发现「其实已经能连上」）
    startHeartbeat();

    // 5. 启动时主动探测服务端并同步
    await checkConnectivity();

    const auth = useAuthStore();
    if (auth.isAuthenticated && isOnline.value) {
      void runSync();
    }
  }

  /**
   * 离线记账暂存：
   * 生成全局唯一 ULID，先落库 IndexedDB 支出明细（标记 isOfflinePending），
   * 同时写入 Outbox 待发队列。
   *
   * 任一步写入失败都直接抛出，绝不返回成功：这笔账若没落盘又没入队，
   * 用户看到的「记好了」就是假的。
   */
  async function addOfflineExpense(input: {
    amountCents: number;
    categoryId: string;
    paymentMethodId: string;
    spendDate: string;
    note?: string;
  }): Promise<string> {
    const auth = useAuthStore();
    const dict = useDictionariesStore();
    const expenseId = ulid();
    const nowIso = new Date().toISOString();

    const cat = dict.findCategory(input.categoryId);
    const parentCat = cat?.parentId ? dict.findCategory(cat.parentId) : null;
    const pm = dict.findPaymentMethod(input.paymentMethodId);

    const localRecord: Expense = {
      id: expenseId,
      ownerId: auth.user?.id ?? '',
      ownerName: auth.user?.displayName ?? '我',
      amountCents: input.amountCents,
      categoryId: input.categoryId,
      // 查不到字典项时留空，不要伪造「未知分类」之类的名字：
      // 这些字段会随同步扩散到其他设备、进入报表，形成永久的分类黑洞（见 docs/decisions.md）。
      // 空名由渲染层兜底显示为「未分类」，语义正确且不会脏化数据。
      categoryName: cat?.name ?? '',
      categoryIcon: cat?.icon ?? '',
      categoryColor: cat?.color ?? '',
      parentCategoryColor: parentCat?.color ?? null,
      parentCategoryName: parentCat?.name ?? null,
      paymentMethodId: input.paymentMethodId,
      paymentMethodName: pm?.name ?? '',
      paymentMethodType: pm?.type ?? 'cash',
      spendDate: input.spendDate,
      postingDate: input.spendDate,
      repaymentDate: input.spendDate,
      source: 'manual',
      planId: null,
      planPeriodSeq: null,
      note: input.note ?? '',
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    await writeOffline('离线保存', async () => {
      if (isIdbSupported()) {
        await saveSingleCachedExpense(localRecord, true);
        await addOutboxItem({
          id: ulid(),
          action: 'create_expense',
          entityId: expenseId,
          payload: {
            id: expenseId,
            amountCents: input.amountCents,
            categoryId: input.categoryId,
            paymentMethodId: input.paymentMethodId,
            spendDate: input.spendDate,
            note: input.note ?? '',
          },
          createdAt: nowIso,
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });

    // 主动触发 300ms 防抖同步
    scheduleSync(300);

    return expenseId;
  }

  /**
   * 离线修改账单：
   * 立即更新本地 IndexedDB 缓存（支持离线即刻呈现），
   * 若该记录仅存在于本地离线待发队列中，直接更新该队列项；
   * 若为已同步记录，则写入 update_expense 暂存队列。
   *
   * 写入失败直接抛出：本地缓存与待发队列必须同时更新，只成功一半等于数据不一致。
   */
  async function updateOfflineExpense(
    id: string,
    input: {
      amountCents?: number;
      categoryId?: string;
      paymentMethodId?: string;
      spendDate?: string;
      note?: string;
    },
  ): Promise<void> {
    const dict = useDictionariesStore();
    const partial: Partial<Expense> = {};

    if (input.amountCents !== undefined) partial.amountCents = input.amountCents;
    if (input.categoryId !== undefined) {
      partial.categoryId = input.categoryId;
      const cat = dict.findCategory(input.categoryId);
      const parentCat = cat?.parentId ? dict.findCategory(cat.parentId) : null;
      // 同 addOfflineExpense：查不到就留空，不伪造会被同步扩散的名字
      partial.categoryName = cat?.name ?? '';
      partial.categoryIcon = cat?.icon ?? '';
      partial.categoryColor = cat?.color ?? '';
      partial.parentCategoryColor = parentCat?.color ?? null;
      partial.parentCategoryName = parentCat?.name ?? null;
    }
    if (input.paymentMethodId !== undefined) {
      partial.paymentMethodId = input.paymentMethodId;
      const pm = dict.findPaymentMethod(input.paymentMethodId);
      partial.paymentMethodName = pm?.name ?? '';
      partial.paymentMethodType = pm?.type ?? 'cash';
    }
    if (input.spendDate !== undefined) {
      partial.spendDate = input.spendDate;
      partial.postingDate = input.spendDate;
      partial.repaymentDate = input.spendDate;
    }
    if (input.note !== undefined) partial.note = input.note;

    await writeOffline('离线修改', async () => {
      if (isIdbSupported()) {
        await updateCachedExpense(id, partial, true);

        const items = await getOutboxItems();
        const existingCreate = items.find(
          (item) => item.action === 'create_expense' && item.entityId === id,
        );

        if (existingCreate) {
          // 如果这笔账还在离线新建队列里，直接合并修改该新建项
          await addOutboxItem({
            ...existingCreate,
            payload: {
              ...existingCreate.payload,
              ...input,
            },
          });
        } else {
          // 已经推送到服务端的记录，写入一条 update_expense
          await addOutboxItem({
            id: ulid(),
            action: 'update_expense',
            entityId: id,
            payload: {
              id,
              ...input,
            },
            createdAt: new Date().toISOString(),
            retryCount: 0,
          });
        }
        await refreshPendingCount();
      }
    });

    scheduleSync(300);
  }

  /**
   * 离线删除账单：
   * 本地立即移除（秒删），若是离线新建队列中的记录，直接作废该创建队列项；
   * 若是服务端历史记录，写入 delete_expense 队列待补偿。
   *
   * 写入失败直接抛出：否则本地已删、队列里却没有 delete，
   * 服务端会把这笔账一直留着，而用户以为已经删了。
   */
  async function deleteOfflineExpense(id: string): Promise<void> {
    await writeOffline('离线删除', async () => {
      if (isIdbSupported()) {
        await deleteCachedExpense(id);

        const items = await getOutboxItems();
        const localRelated = items.filter((item) => item.entityId === id);

        const wasPendingCreate = localRelated.some((item) => item.action === 'create_expense');
        if (wasPendingCreate) {
          // 该记录还从未同步上云，直接撤销相关的所有离线队列项
          await removeOutboxItems(localRelated.map((i) => i.id));
        } else {
          // 已存在于服务端的记录，写入 delete_expense
          await addOutboxItem({
            id: ulid(),
            action: 'delete_expense',
            entityId: id,
            payload: { id },
            createdAt: new Date().toISOString(),
            retryCount: 0,
          });
        }
        await refreshPendingCount();
      }
    });

    scheduleSync(300);
  }

  /**
   * 离线确认待办（confirm_todo）：写失败直接抛出，避免服务端状态与本地不一致
   */
  async function confirmOfflineTodo(todoId: string, spendDate?: string): Promise<void> {
    await writeOffline('离线确认待办', async () => {
      if (isIdbSupported()) {
        await updateCachedPlanTodo(todoId, {
          status: 'confirmed',
          postedDate: spendDate,
          confirmedAt: new Date().toISOString(),
        });
        await addOutboxItem({
          id: ulid(),
          action: 'confirm_todo',
          entityId: todoId,
          payload: { id: todoId, spendDate },
          createdAt: new Date().toISOString(),
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });
    scheduleSync(300);
  }

  /**
   * 离线跳过待办（skip_todo）
   */
  async function skipOfflineTodo(todoId: string): Promise<void> {
    await writeOffline('离线跳过待办', async () => {
      if (isIdbSupported()) {
        await updateCachedPlanTodo(todoId, { status: 'skipped' });
        await addOutboxItem({
          id: ulid(),
          action: 'skip_todo',
          entityId: todoId,
          payload: { id: todoId },
          createdAt: new Date().toISOString(),
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });
    scheduleSync(300);
  }

  /**
   * 离线知晓待办（ack_todo）
   */
  async function ackOfflineTodo(todoId: string): Promise<void> {
    await writeOffline('离线知晓待办', async () => {
      if (isIdbSupported()) {
        await updateCachedPlanTodo(todoId, { ackAt: new Date().toISOString() });
        await addOutboxItem({
          id: ulid(),
          action: 'ack_todo',
          entityId: todoId,
          payload: { id: todoId },
          createdAt: new Date().toISOString(),
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });
    scheduleSync(300);
  }

  /**
   * 离线撤销确认（revert_todo）：待办回 pending，本地缓存的生成支出软删
   */
  async function revertOfflineTodo(todoId: string): Promise<void> {
    await writeOffline('离线撤销确认', async () => {
      if (isIdbSupported()) {
        // 先读缓存待办拿到 expenseId，把本地已入账的支出移除（服务端 push 时会软删）
        const todos = await getCachedPlanTodos();
        const todo = todos.find((t) => t.id === todoId);
        if (todo?.expenseId) {
          await deleteCachedExpense(todo.expenseId);
        }
        await updateCachedPlanTodo(todoId, {
          status: 'pending',
          postedDate: null,
          confirmedBy: null,
          confirmedAt: null,
          expenseId: null,
          holdAutoPost: true,
        });
        await addOutboxItem({
          id: ulid(),
          action: 'revert_todo',
          entityId: todoId,
          payload: { id: todoId },
          createdAt: new Date().toISOString(),
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });
    scheduleSync(300);
  }

  /**
   * 离线恢复跳过（restore_todo）：skipped → pending
   */
  async function restoreOfflineTodo(todoId: string): Promise<void> {
    await writeOffline('离线恢复待办', async () => {
      if (isIdbSupported()) {
        await updateCachedPlanTodo(todoId, { status: 'pending', holdAutoPost: true });
        await addOutboxItem({
          id: ulid(),
          action: 'restore_todo',
          entityId: todoId,
          payload: { id: todoId },
          createdAt: new Date().toISOString(),
          retryCount: 0,
        });
        await refreshPendingCount();
      }
    });
    scheduleSync(300);
  }

  /**
   * 推送 Outbox 离线待发送队列至服务端（支持新增、修改、删除支出以及计划待办状态）
   */
  async function pushOutbox(): Promise<number> {
    if (!isIdbSupported() || !isOnline.value) return 0;
    const auth = useAuthStore();
    if (!auth.isAuthenticated) return 0;

    const allItems = await getOutboxItems();
    // 死信隔离：重试超限的毒丸条目不再参与推送，避免阻塞后续队列
    const items = allItems.filter((i) => i.retryCount <= OUTBOX_MAX_RETRY);
    if (items.length === 0) return 0;

    const expenseCreates = items.filter((i) => i.action === 'create_expense');
    const expenseUpdates = items.filter((i) => i.action === 'update_expense');
    const expenseDeletes = items.filter((i) => i.action === 'delete_expense');
    const todoConfirms = items.filter((i) => i.action === 'confirm_todo');
    const todoSkips = items.filter((i) => i.action === 'skip_todo');
    const todoAcks = items.filter((i) => i.action === 'ack_todo');
    const todoReverts = items.filter((i) => i.action === 'revert_todo');
    const todoRestores = items.filter((i) => i.action === 'restore_todo');

    const deviceId = await getDeviceId();

    const pushPayload = {
      deviceId,
      expenses:
        expenseCreates.length > 0
          ? expenseCreates.map((item) => ({
              id: typeof item.payload['id'] === 'string' ? item.payload['id'] : undefined,
              amountCents: Number(item.payload['amountCents']),
              categoryId: String(item.payload['categoryId']),
              paymentMethodId: String(item.payload['paymentMethodId']),
              spendDate: String(item.payload['spendDate']),
              note: typeof item.payload['note'] === 'string' ? item.payload['note'] : undefined,
            }))
          : undefined,
      updatedExpenses:
        expenseUpdates.length > 0
          ? expenseUpdates.map((item) => ({
              id: String(item.payload['id'] || item.entityId),
              amountCents:
                item.payload['amountCents'] !== undefined
                  ? Number(item.payload['amountCents'])
                  : undefined,
              categoryId:
                typeof item.payload['categoryId'] === 'string'
                  ? item.payload['categoryId']
                  : undefined,
              paymentMethodId:
                typeof item.payload['paymentMethodId'] === 'string'
                  ? item.payload['paymentMethodId']
                  : undefined,
              spendDate:
                typeof item.payload['spendDate'] === 'string'
                  ? item.payload['spendDate']
                  : undefined,
              note: typeof item.payload['note'] === 'string' ? item.payload['note'] : undefined,
            }))
          : undefined,
      deletedExpenseIds:
        expenseDeletes.length > 0
          ? expenseDeletes.map((item) => String(item.payload['id'] || item.entityId))
          : undefined,
      confirmedTodos:
        todoConfirms.length > 0
          ? todoConfirms.map((item) => ({
              id: String(item.payload['id'] || item.entityId),
              spendDate:
                typeof item.payload['spendDate'] === 'string'
                  ? item.payload['spendDate']
                  : undefined,
            }))
          : undefined,
      skippedTodoIds:
        todoSkips.length > 0
          ? todoSkips.map((item) => String(item.payload['id'] || item.entityId))
          : undefined,
      ackedTodoIds:
        todoAcks.length > 0
          ? todoAcks.map((item) => String(item.payload['id'] || item.entityId))
          : undefined,
      revertedTodoIds:
        todoReverts.length > 0
          ? todoReverts.map((item) => String(item.payload['id'] || item.entityId))
          : undefined,
      restoredTodoIds:
        todoRestores.length > 0
          ? todoRestores.map((item) => String(item.payload['id'] || item.entityId))
          : undefined,
    };

    const result = await syncApi.push(pushPayload);

    // 新增支出按服务端逐条校验的结果分流：
    // 成功的正常清理；被拒绝的（毒丸，如关联了已失效分类）保留在 Outbox 并累计重试次数，
    // 超过上限后进入死信隔离 —— 不再参与推送，避免单条坏数据永久卡死整个队列。
    const failedCreateIdx = new Set(result.failedExpenseIndexes ?? []);
    const succeededOutboxIds: string[] = [];
    const rejectedCreates: OutboxItem[] = [];
    expenseCreates.forEach((item, idx) => {
      if (failedCreateIdx.has(idx)) {
        rejectedCreates.push(item);
      } else {
        succeededOutboxIds.push(item.id);
      }
    });

    // 其余动作（修改/删除/待办）服务端已逐条容错接收，全部清理
    const otherOutboxIds = items
      .filter((i) => i.action !== 'create_expense')
      .map((i) => i.id);
    await removeOutboxItems([...succeededOutboxIds, ...otherOutboxIds]);

    for (const item of rejectedCreates) {
      const nextRetry = item.retryCount + 1;
      if (nextRetry > OUTBOX_MAX_RETRY) {
        await addOutboxItem({
          ...item,
          retryCount: nextRetry,
          lastError: '多次被服务端拒绝，已隔离（死信）',
        });
      } else {
        await addOutboxItem({ ...item, retryCount: nextRetry, lastError: '服务端拒绝该笔新增' });
      }
    }

    await refreshPendingCount();

    return result.pushedExpensesCount + result.updatedExpensesCount + result.deletedExpensesCount;
  }

  /**
   * 增量拉取服务端变更并写入 IndexedDB 本地副本
   */
  async function pullChanges(): Promise<number> {
    if (!isIdbSupported() || !isOnline.value) return 0;
    const auth = useAuthStore();
    if (!auth.isAuthenticated) return 0;

    let hasMore = true;
    let currentVer = lastSyncVersion.value;
    let totalPulled = 0;
    let anyDictChanged = false;
    let anyPlanChanged = false;

    while (hasMore) {
      const result = await syncApi.pull(currentVer, 200);
      if (result.changes.length === 0) break;

      for (const change of result.changes) {
        totalPulled++;
        if (change.entityType === 'category' || change.entityType === 'payment_method') {
          anyDictChanged = true;
        } else if (change.entityType === 'plan' || change.entityType === 'plan_todo') {
          anyPlanChanged = true;
        } else if (change.entityType === 'expense') {
          if (change.op === 'delete') {
            await deleteCachedExpense(change.entityId);
          } else if (change.op === 'upsert' && change.payload) {
            const p = change.payload;
            const dict = useDictionariesStore();
            const cat = dict.findCategory(String(p['category_id'] ?? ''));
            const parentCat = cat?.parentId ? dict.findCategory(cat.parentId) : null;
            const pm = dict.findPaymentMethod(String(p['payment_method_id'] ?? ''));
            await saveSingleCachedExpense(
              {
                id: change.entityId,
                ownerId: String(p['owner_id'] ?? ''),
                ownerName: '',
                amountCents: Number(p['amount_cents'] ?? 0),
                categoryId: String(p['category_id'] ?? ''),
                categoryName: cat?.name ?? '',
                categoryIcon: cat?.icon ?? '',
                categoryColor: cat?.color ?? '',
                parentCategoryColor: parentCat?.color ?? null,
                parentCategoryName: parentCat?.name ?? null,
                paymentMethodId: String(p['payment_method_id'] ?? ''),
                paymentMethodName: pm?.name ?? '',
                paymentMethodType: pm?.type ?? 'cash',
                spendDate: String(p['spend_date'] ?? ''),
                postingDate: String(p['posting_date'] ?? p['spend_date'] ?? ''),
                repaymentDate: String(p['repayment_date'] ?? p['spend_date'] ?? ''),
                source: p['source'] === 'plan' ? 'plan' : 'manual',
                planId: (p['plan_id'] as string) ?? null,
                planPeriodSeq:
                  typeof p['plan_period_seq'] === 'number' ? p['plan_period_seq'] : null,
                note: String(p['note'] ?? ''),
                createdAt: String(p['created_at'] ?? ''),
                updatedAt: String(p['updated_at'] ?? ''),
              },
              false,
            );
          }
        }
        currentVer = Math.max(currentVer, change.version);
      }

      hasMore = result.hasMore;
    }

    lastSyncVersion.value = currentVer;
    await setMeta('last_sync_version', currentVer);

    const nowIso = new Date().toISOString();
    lastSyncedAt.value = nowIso;
    await setMeta('last_synced_at', nowIso);

    // 若分类或支付方式有变动，通知字典 store 静默重刷并更新本地缓存
    if (anyDictChanged) {
      const dict = useDictionariesStore();
      void dict.load(true);
    }

    // 若计划或待办有变动，通知计划 store 静默重刷并更新本地缓存
    if (anyPlanChanged) {
      const plans = usePlansStore();
      void plans.refresh();
    }

    return totalPulled;
  }

  /**
   * 触发双向完整同步（先补偿 Push，再拉取 Pull）
   */
  async function runSync(): Promise<void> {
    if (isSyncing.value) return;
    const auth = useAuthStore();
    if (!auth.isAuthenticated) return;

    if (!isOnline.value) {
      const connected = await checkConnectivity();
      if (!connected) {
        lastError.value = '无法连接到任何配置的服务端';
        // 连通失败也算一次失败：只要还有待同步数据，就按退避节奏再试，避免永久卡住
        scheduleRetry();
        return;
      }
    }

    isSyncing.value = true;
    lastError.value = null;

    try {
      await pushOutbox();
      await pullChanges();
      // 同步成功：复位退避节奏；若仍有残留（如被服务端拒绝的条目）交给心跳按需再试
      resetRetry();
    } catch (err) {
      lastError.value = err instanceof ApiError ? err.message : '网络同步未完成';
      scheduleRetry();
    } finally {
      isSyncing.value = false;
    }
  }

  return {
    isOnline,
    activeServerUrl,
    isSyncing,
    pendingCount,
    hasPending,
    deadLetters,
    deadLetterCount,
    lastSyncedAt,
    lastSyncVersion,
    lastError,
    initialized,
    init,
    checkConnectivity,
    refreshPendingCount,
    addOfflineExpense,
    updateOfflineExpense,
    deleteOfflineExpense,
    confirmOfflineTodo,
    skipOfflineTodo,
    ackOfflineTodo,
    revertOfflineTodo,
    restoreOfflineTodo,
    pushOutbox,
    pullChanges,
    runSync,
    scheduleSync,
  };
});
