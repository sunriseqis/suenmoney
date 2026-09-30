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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('meta', 'readwrite');
      const store = tx.objectStore('meta');
      const req = store.put({ key, value });
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('categories', 'readwrite');
      const store = tx.objectStore('categories');
      store.clear();
      for (const cat of categories) {
        store.put(cat);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('payment_methods', 'readwrite');
      const store = tx.objectStore('payment_methods');
      store.clear();
      for (const pm of methods) {
        store.put(pm);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      for (const item of items) {
        const month = item.spendDate ? item.spendDate.slice(0, 7) : '';
        store.put({ ...item, month });
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
  }
}

export async function saveSingleCachedExpense(item: Expense, isOfflinePending = false): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      const month = item.spendDate ? item.spendDate.slice(0, 7) : '';
      const req = store.put({ ...item, month, isOfflinePending });
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      const req = store.get(id);
      req.onsuccess = () => {
        const existing = req.result as (Expense & { month?: string; isOfflinePending?: boolean }) | undefined;
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
        resolve();
      };
      req.onerror = () => resolve();
    });
  } catch {
    // 忽略异常
  }
}

export async function deleteCachedExpense(id: string): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('expenses', 'readwrite');
      const store = tx.objectStore('expenses');
      const req = store.delete(id);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('plans', 'readwrite');
      const store = tx.objectStore('plans');
      store.clear();
      for (const p of plans) {
        store.put(p);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve, reject) => {
      const tx = db.transaction('plan_todos', 'readwrite');
      const store = tx.objectStore('plan_todos');
      for (const t of todos) {
        store.put(t);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
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
    return new Promise((resolve) => {
      const tx = db.transaction('plan_todos', 'readwrite');
      const store = tx.objectStore('plan_todos');
      const req = store.get(id);
      req.onsuccess = () => {
        const existing = req.result as PlanTodo | undefined;
        if (!existing) {
          resolve();
          return;
        }
        store.put({ ...existing, ...updates, updatedAt: new Date().toISOString() });
        resolve();
      };
      req.onerror = () => resolve();
    });
  } catch {
    // 忽略异常
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

export async function addOutboxItem(item: OutboxItem): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('outbox', 'readwrite');
      const store = tx.objectStore('outbox');
      const req = store.put(item);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  } catch {
    // 忽略异常
  }
}

export async function removeOutboxItems(ids: string[]): Promise<void> {
  if (!isIdbSupported() || ids.length === 0) return;
  try {
    const db = await openOfflineDb();
    return new Promise((resolve, reject) => {
      const tx = db.transaction('outbox', 'readwrite');
      const store = tx.objectStore('outbox');
      for (const id of ids) {
        store.delete(id);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
  }
}

export async function clearAllOfflineData(): Promise<void> {
  if (!isIdbSupported()) return;
  try {
    const db = await openOfflineDb();
    const stores = ['meta', 'categories', 'payment_methods', 'expenses', 'outbox'];
    if (db.objectStoreNames.contains('plans')) stores.push('plans');
    if (db.objectStoreNames.contains('plan_todos')) stores.push('plan_todos');

    return new Promise((resolve, reject) => {
      const tx = db.transaction(stores, 'readwrite');
      for (const s of stores) {
        tx.objectStore(s).clear();
      }
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    // 忽略异常
  }
}
