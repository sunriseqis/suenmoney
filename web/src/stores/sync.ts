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
  getOutboxItems,
  isIdbSupported,
  removeOutboxItems,
  saveSingleCachedExpense,
  setMeta,
} from '@/utils/idb';
import { ulid } from '@/utils/ulid';
import { useAuthStore } from './auth';
import { useDictionariesStore } from './dictionaries';

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

  const hasPending = computed(() => pendingCount.value > 0);

  let syncDebounceTimer: ReturnType<typeof setTimeout> | undefined;

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

  /** 刷新待发送 Outbox 队列条数 */
  async function refreshPendingCount(): Promise<void> {
    if (!isIdbSupported()) return;
    const items = await getOutboxItems();
    pendingCount.value = items.length;
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
   * 4. 实时探测最优服务端真实连通性；
   * 5. 触发首次补偿与增量拉取。
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

    // 3. 启动时主动探测服务端并同步
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
      categoryName: cat?.name ?? '未知分类',
      categoryIcon: cat?.icon ?? '',
      categoryColor: cat?.color ?? '',
      parentCategoryColor: parentCat?.color ?? null,
      parentCategoryName: parentCat?.name ?? null,
      paymentMethodId: input.paymentMethodId,
      paymentMethodName: pm?.name ?? '未知支付方式',
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

    // 主动触发 300ms 防抖同步
    scheduleSync(300);

    return expenseId;
  }

  /**
   * 推送 Outbox 离线待发送队列至服务端
   */
  async function pushOutbox(): Promise<number> {
    if (!isIdbSupported() || !isOnline.value) return 0;
    const auth = useAuthStore();
    if (!auth.isAuthenticated) return 0;

    const items = await getOutboxItems();
    if (items.length === 0) return 0;

    const expenseCreates = items.filter((i) => i.action === 'create_expense');
    if (expenseCreates.length === 0) return 0;

    const deviceId = await getDeviceId();
    const batchList = expenseCreates.map((item) => ({
      id: typeof item.payload['id'] === 'string' ? item.payload['id'] : undefined,
      amountCents: Number(item.payload['amountCents']),
      categoryId: String(item.payload['categoryId']),
      paymentMethodId: String(item.payload['paymentMethodId']),
      spendDate: String(item.payload['spendDate']),
      note: typeof item.payload['note'] === 'string' ? item.payload['note'] : undefined,
    }));

    const result = await syncApi.push({ expenses: batchList, deviceId });

    // 服务端确认接收后，安全清理这些 outbox 记录
    await removeOutboxItems(expenseCreates.map((i) => i.id));
    await refreshPendingCount();

    return result.pushedExpensesCount;
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

    while (hasMore) {
      const result = await syncApi.pull(currentVer, 200);
      if (result.changes.length === 0) break;

      for (const change of result.changes) {
        totalPulled++;
        if (change.entityType === 'category' || change.entityType === 'payment_method') {
          anyDictChanged = true;
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
      await dict.load(true);
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
        return;
      }
    }

    isSyncing.value = true;
    lastError.value = null;

    try {
      await pushOutbox();
      await pullChanges();
    } catch (err) {
      lastError.value = err instanceof ApiError ? err.message : '网络同步未完成';
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
    lastSyncedAt,
    lastSyncVersion,
    lastError,
    initialized,
    init,
    checkConnectivity,
    refreshPendingCount,
    addOfflineExpense,
    pushOutbox,
    pullChanges,
    runSync,
    scheduleSync,
  };
});
