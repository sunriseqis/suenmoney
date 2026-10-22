/**
 * IndexedDB 客户端离线存储驱动。
 *
 * 核心对象仓库：
 * - `meta`: 键值对元信息（设备 ID、最新同步版本号、上次同步时间等）
 * - `categories`: 分类全量本地副本（支持离线 0ms 秒开）
 * - `payment_methods`: 支付方式全量本地副本
 * - `expenses`: 本地支出明细副本（按 id 主键，支持按月份/日期索引筛选）
 * - `outbox`: 离线操作暂存队列（待网络恢复时补偿提交至服务端）
 */
import type { Category, Expense, PaymentMethod, Plan, PlanTodo } from '../api/types.ts';
import { ulid } from './ulid.ts';

const DB_NAME = 'suenmoney_offline_db';
const DB_VERSION = 2;

export interface OutboxItem {
  id: string; // ulid
  action:
    | 'create_expense'
    | 'update_expense'
    | 'delete_expense'
    | 'confirm_todo'
    | 'skip_todo'
    | 'ack_todo'
    | 'revert_todo'
    | 'restore_todo';
  entityId: string;
  payload: Record<string, unknown>;
  createdAt: string;
  retryCount: number;
  lastError?: string;
}

/**
 * 本地存储写入失败错误。
 *
 * 为什么写类函数必须抛出而不能静默吞掉：写入失败（配额耗尽、权限受限、隐私模式）
 * 若被吞掉，上层会以为「离线记账成功」，而这笔账既没进本地缓存、也没进待发队列，
 * 用户完全无感知地丢账。读类函数则保持静默降级 —— 读不到只是退化为空数据，
 * 隐私模式下的只读降级是可以接受的。
 */
export class OfflineStorageError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = 'OfflineStorageError';
  }
}

/** 把底层 IDB 异常统一转成可向用户展示的写入失败错误 */
function storageWriteError(op: string, cause: unknown): OfflineStorageError {
  return new OfflineStorageError(
    `本地存储写入失败（${op}）：存储空间不足或被系统清理，请检查设备存储后重试`,
    { cause },
  );
}

export function isIdbSupported(): boolean {
  return typeof window !== 'undefined' && typeof window.indexedDB !== 'undefined';
}

let dbInstancePromise: Promise<IDBDatabase> | null = null;

export function openOfflineDb(): Promise<IDBDatabase> {
  if (!isIdbSupported()) {
    return Promise.reject(new Error('当前环境不支持 IndexedDB'));
  }

  if (dbInstancePromise) {
    return dbInstancePromise;
  }

  dbInstancePromise = new Promise((resolve, reject) => {
    const request = window.indexedDB.open(DB_NAME, DB_VERSION);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;

      // 1. 元信息
      if (!db.objectStoreNames.contains('meta')) {
        db.createObjectStore('meta', { keyPath: 'key' });
      }

      // 2. 基础字典
      if (!db.objectStoreNames.contains('categories')) {
        db.createObjectStore('categories', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('payment_methods')) {
        db.createObjectStore('payment_methods', { keyPath: 'id' });
      }

      // 3. 支出明细副本
      if (!db.objectStoreNames.contains('expenses')) {
        const expenseStore = db.createObjectStore('expenses', { keyPath: 'id' });
        expenseStore.createIndex('spendDate', 'spendDate', { unique: false });
        expenseStore.createIndex('month', 'month', { unique: false });
      }

      // 4. 离线待发送队列
      if (!db.objectStoreNames.contains('outbox')) {
        const outboxStore = db.createObjectStore('outbox', { keyPath: 'id' });
        outboxStore.createIndex('createdAt', 'createdAt', { unique: false });
      }

      // 5. 计划与待办副本
      if (!db.objectStoreNames.contains('plans')) {
        db.createObjectStore('plans', { keyPath: 'id' });
      }
      if (!db.objectStoreNames.contains('plan_todos')) {
        const todoStore = db.createObjectStore('plan_todos', { keyPath: 'id' });
        todoStore.createIndex('planId', 'planId', { unique: false });
        todoStore.createIndex('status', 'status', { unique: false });
      }
    };

    request.onsuccess = () => {
      const db = request.result;
      db.onversionchange = () => {
        db.close();
        dbInstancePromise = null;
      };
      resolve(db);
    };

    request.onerror = () => {
      dbInstancePromise = null;
      reject(request.error);
    };
  });

  return dbInstancePromise;
}

// ---- 元信息管理 -------------------------------------------------------------

export async function getMeta<T>(key: string, defaultValue: T): Promise<T> {
  if (!isIdbSupported()) return defaultValue;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('meta', 'readonly');
      const store = tx.objectStore('meta');
      const req = store.get(key);
      req.onsuccess = () => {
        resolve(req.result !== undefined ? (req.result.value as T) : defaultValue);
      };
      req.onerror = () => resolve(defaultValue);
    });
  } catch {
    return defaultValue;
  }
}

export async function setMeta<T>(key: string, value: T): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('meta', 'readwrite');
      tx.objectStore('meta').put({ key, value });
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('元信息', err);
  }
}

/** 获取或生成持久化的客户端设备唯一标识 */
export async function getDeviceId(): Promise<string> {
  const existing = await getMeta<string | null>('device_id', null);
  if (existing && existing.trim() !== '') {
    return existing;
  }
  const newId = `dev_${ulid()}`;
  await setMeta('device_id', newId);
  return newId;
}

// ---- 分类与支付方式字典副本 -------------------------------------------------

export async function getCachedCategories(): Promise<Category[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('categories', 'readonly');
      const store = tx.objectStore('categories');
      const req = store.getAll();
      req.onsuccess = () => resolve((req.result as Category[]) ?? []);
      req.onerror = () => resolve([]);
    });
  } catch {
    return [];
  }
}

export async function saveCachedCategories(categories: Category[]): Promise<void> {
  if (!isIdbSupported() || categories.length === 0) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('categories', 'readwrite');
      const store = tx.objectStore('categories');
      store.clear();
      for (const cat of categories) {
        store.put(cat);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('分类字典缓存', err);
  }
}

export async function getCachedPaymentMethods(): Promise<PaymentMethod[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('payment_methods', 'readonly');
      const store = tx.objectStore('payment_methods');
      const req = store.getAll();
      req.onsuccess = () => resolve((req.result as PaymentMethod[]) ?? []);
      req.onerror = () => resolve([]);
    });
  } catch {
    return [];
  }
}

export async function saveCachedPaymentMethods(methods: PaymentMethod[]): Promise<void> {
  if (!isIdbSupported() || methods.length === 0) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('payment_methods', 'readwrite');
      const store = tx.objectStore('payment_methods');
      store.clear();
      for (const pm of methods) {
        store.put(pm);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('支付方式字典缓存', err);
  }
}

// ---- 流水本地明细副本 -------------------------------------------------------

export interface CachedExpenseRecord extends Expense {
  month?: string;
  isOfflinePending?: boolean;
}

export async function getCachedExpenses(month?: string): Promise<Expense[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('expenses', 'readonly');
      const store = tx.objectStore('expenses');

      if (month) {
        const index = store.index('month');
        const req = index.getAll(month);
        req.onsuccess = () => {
          const list = (req.result as Expense[]) ?? [];
          // 按 spendDate 降序
          list.sort((a, b) => b.spendDate.localeCompare(a.spendDate));
          resolve(list);
        };
        req.onerror = () => resolve([]);
      } else {
        const req = store.getAll();
        req.onsuccess = () => {
          const list = (req.result as Expense[]) ?? [];
          list.sort((a, b) => b.spendDate.localeCompare(a.spendDate));
          resolve(list);
        };
        req.onerror = () => resolve([]);
      }
    });
  } catch {
    return [];
  }
}

export async function saveCachedExpenses(items: Expense[]): Promise<void> {
  if (!isIdbSupported() || items.length === 0) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      for (const item of items) {
        const month = item.spendDate ? item.spendDate.slice(0, 7) : '';
        store.put({ ...item, month });
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('流水本地副本', err);
  }
}

export async function saveSingleCachedExpense(item: Expense, isOfflinePending = false): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      const month = item.spendDate ? item.spendDate.slice(0, 7) : '';
      store.put({ ...item, month, isOfflinePending });
      // 以事务提交完成为准而不是单条 request 成功：
      // 配额不足等错误常在事务提交阶段才抛出，只等 onsuccess 会把「写失败」误判成「写成功」。
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('流水本地副本', err);
  }
}

export async function getCachedExpenseById(id: string): Promise<Expense | null> {
  if (!isIdbSupported()) return null;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('expenses', 'readonly');
      const store = tx.objectStore('expenses');
      const req = store.get(id);
      req.onsuccess = () => resolve((req.result as Expense) ?? null);
      req.onerror = () => resolve(null);
    });
  } catch {
    return null;
  }
}

export async function updateCachedExpense(
  id: string,
  updates: Partial<Expense>,
  isOfflinePending = true,
): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      const req = store.get(id);
      req.onsuccess = () => {
        const existing = req.result as (Expense & { month?: string; isOfflinePending?: boolean }) | undefined;
        // 本地没有这条记录（只存在于服务端）时无需改缓存，不算写入失败
        if (!existing) {
          resolve();
          return;
        }
        const updated = {
          ...existing,
          ...updates,
          isOfflinePending,
          updatedAt: new Date().toISOString(),
        };
        if (updates.spendDate) {
          updated.month = updates.spendDate.slice(0, 7);
        }
        store.put(updated);
      };
      req.onerror = () => reject(req.error);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('流水本地副本', err);
  }
}

export async function deleteCachedExpense(id: string): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      tx.objectStore('expenses').delete(id);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('流水本地副本', err);
  }
}

// ---- 计划与待办本地副本 -----------------------------------------------------

export async function getCachedPlans(): Promise<Plan[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    if (!db.objectStoreNames.contains('plans')) return [];
    return new Promise((resolve) => {
      const tx = db.transaction('plans', 'readonly');
      const store = tx.objectStore('plans');
      const req = store.getAll();
      req.onsuccess = () => resolve((req.result as Plan[]) ?? []);
      req.onerror = () => resolve([]);
    });
  } catch {
    return [];
  }
}

export async function saveCachedPlans(plans: Plan[]): Promise<void> {
  if (!isIdbSupported() || plans.length === 0) return;
  try {
    const db = await openOfflineDb();
    if (!db.objectStoreNames.contains('plans')) return;
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('plans', 'readwrite');
      const store = tx.objectStore('plans');
      store.clear();
      for (const p of plans) {
        store.put(p);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('计划本地副本', err);
  }
}

export async function getCachedPlanTodos(status?: string): Promise<PlanTodo[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    if (!db.objectStoreNames.contains('plan_todos')) return [];
    return new Promise((resolve) => {
      const tx = db.transaction('plan_todos', 'readonly');
      const store = tx.objectStore('plan_todos');
      if (status) {
        const index = store.index('status');
        const req = index.getAll(status);
        req.onsuccess = () => resolve((req.result as PlanTodo[]) ?? []);
        req.onerror = () => resolve([]);
      } else {
        const req = store.getAll();
        req.onsuccess = () => resolve((req.result as PlanTodo[]) ?? []);
        req.onerror = () => resolve([]);
      }
    });
  } catch {
    return [];
  }
}

export async function saveCachedPlanTodos(todos: PlanTodo[]): Promise<void> {
  if (!isIdbSupported() || todos.length === 0) return;
  try {
    const db = await openOfflineDb();
    if (!db.objectStoreNames.contains('plan_todos')) return;
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('plan_todos', 'readwrite');
      const store = tx.objectStore('plan_todos');
      for (const t of todos) {
        store.put(t);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('待办本地副本', err);
  }
}

export async function updateCachedPlanTodo(
  id: string,
  updates: Partial<PlanTodo>,
): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    if (!db.objectStoreNames.contains('plan_todos')) return;
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('plan_todos', 'readwrite');
      const store = tx.objectStore('plan_todos');
      const req = store.get(id);
      req.onsuccess = () => {
        const existing = req.result as PlanTodo | undefined;
        // 本地无此待办缓存时无需更新，不算写入失败
        if (!existing) {
          resolve();
          return;
        }
        store.put({ ...existing, ...updates, updatedAt: new Date().toISOString() });
      };
      req.onerror = () => reject(req.error);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('待办本地副本', err);
  }
}

// ---- Outbox 离线待发送队列 --------------------------------------------------

export async function getOutboxItems(): Promise<OutboxItem[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    return new Promise((resolve) => {
      const tx = db.transaction('outbox', 'readonly');
      const store = tx.objectStore('outbox');
      const req = store.getAll();
      req.onsuccess = () => {
        const list = (req.result as OutboxItem[]) ?? [];
        list.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
        resolve(list);
      };
      req.onerror = () => resolve([]);
    });
  } catch {
    return [];
  }
}

/**
 * 死信（毒丸隔离）条目摘要：服务端多次拒绝、已不再自动重试的离线操作。
 *
 * 与 `getOutboxItems` 的区别：只返回重试超限的条目，并裁掉 payload 等大字段，
 * 供 UI 直接展示「哪几笔怎么都同步不上去」。
 */
export interface DeadLetterSummary {
  entityId: string;
  action: OutboxItem['action'];
  retryCount: number;
  lastError: string;
  createdAt: string;
}

/**
 * 读取死信条目摘要。
 *
 * 与写函数不同，这里保持静默降级：读不到死信只是「没有可展示的失败条目」，
 * 不该因此打断同步流程（写失败才必须让用户知道）。
 */
export async function getOutboxDeadLetters(maxRetry: number): Promise<DeadLetterSummary[]> {
  if (!isIdbSupported()) return [];
  try {
    const db = await openOfflineDb();
    return await new Promise<DeadLetterSummary[]>((resolve) => {
      const tx = db.transaction('outbox', 'readonly');
      const store = tx.objectStore('outbox');
      const req = store.getAll();
      req.onsuccess = () => {
        const list = (req.result as OutboxItem[]) ?? [];
        const dead = list
          .filter((i) => i.retryCount > maxRetry)
          .map((i) => ({
            entityId: i.entityId,
            action: i.action,
            retryCount: i.retryCount,
            lastError: i.lastError ?? '',
            createdAt: i.createdAt,
          }));
        dead.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
        resolve(dead);
      };
      req.onerror = () => resolve([]);
    });
  } catch {
    return [];
  }
}

export async function addOutboxItem(item: OutboxItem): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('outbox', 'readwrite');
      tx.objectStore('outbox').put(item);
      // 必须等事务提交成功才算写成功：离线记账的「待发队列」丢了等于账没记
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('离线待发队列', err);
  }
}

export async function removeOutboxItems(ids: string[]): Promise<void> {
  if (!isIdbSupported() || ids.length === 0) return;
  try {
    const db = await openOfflineDb();
    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('outbox', 'readwrite');
      for (const id of ids) {
        tx.objectStore('outbox').delete(id);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('离线待发队列', err);
  }
}

export async function clearAllOfflineData(): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    const stores = ['meta', 'categories', 'payment_methods', 'expenses', 'outbox'];
    if (db.objectStoreNames.contains('plans')) stores.push('plans');
    if (db.objectStoreNames.contains('plan_todos')) stores.push('plan_todos');

    return await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(stores, 'readwrite');
      for (const s of stores) {
        tx.objectStore(s).clear();
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error ?? new Error('事务被中止'));
    });
  } catch (err) {
    throw storageWriteError('离线数据清理', err);
  }
}
