/**
 * 本地草稿存取 —— 记账抽屉的「记一半被系统杀掉」保险。
 *
 * ## 为什么需要
 * 抽屉里的金额/分类/支付方式/日期/备注全是内存 ref。移动端切后台被系统回收进程、
 * 或用户从别的 App 回来时页面重新加载，这些值直接归零 —— 记到一半的账就这么丢了。
 * 而「切后台顺手记一笔」恰恰是这个应用最高频的动作，丢的是用户刚输入的真实数据。
 *
 * ## 边界（刻意做小）
 * - 只做**存取 + 过期**，不做 diff、不做冲突合并、不做多端同步；
 * - 存在 localStorage（同步、够快、够小），**不碰 utils/idb.ts**：
 *   草稿是「一次性、丢了就丢了的临时数据」，不值得为它引入 IndexedDB 的异步与容量管理；
 * - storage 可注入，于是整个模块在 Node 下可测（浏览器里才有的 localStorage 只是默认值）。
 *
 * ## key的形状
 * `suenmoney:draft:<scope>:<context>` —— 按「用途 + 上下文」分桶：
 * 新建记账与「编辑某一笔」是两个上下文，账期切换又是另一层，
 * 混在一个 key 里会出现「打开编辑 A 却弹出上一笔新建的草稿」这种张冠李戴。
 */

export interface DraftStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

/** 草稿有效期：24 小时。跨天还在的半截账，多半是用户已经放弃了。 */
export const DRAFT_TTL_MS = 24 * 60 * 60 * 1000;

const KEY_PREFIX = 'suenmoney:draft';

/** 存盘的版本号：结构变了就 +1，旧草稿读出来直接作废，不会喂给新代码。 */
const DRAFT_VERSION = 1;

interface Envelope<T> {
  v: number;
  savedAt: number;
  data: T;
}

export interface DraftOptions {
  storage?: DraftStorage | null;
  now?: number;
}

/**
 * 默认 storage：浏览器里用 localStorage，拿不到（Node、隐私模式）就退化成 null ——
 * 退化后所有读返回 null、所有写静默跳过，记账流程照常走，只是不再有草稿恢复。
 */
function defaultStorage(): DraftStorage | null {
  try {
    const ls = (globalThis as { localStorage?: DraftStorage }).localStorage;
    return ls ?? null;
  } catch {
    return null;
  }
}

function resolveStorage(override: DraftStorage | null | undefined): DraftStorage | null {
  if (override === undefined) return defaultStorage();
  return override;
}

/** scope：用途（如 'expense'）；context：该用途下的具体上下文（如 'edit:<id>' / 'new:<YYYY-MM>'）。 */
export function draftKey(scope: string, context: string): string {
  return `${KEY_PREFIX}:${scope}:${context}`;
}

/** 读草稿。已过期 / 版本不符 / 解析失败一律当作「没有草稿」，并顺手把坏数据清掉。 */
export function readDraft<T>(scope: string, context: string, options: DraftOptions = {}): T | null {
  const storage = resolveStorage(options.storage);
  if (storage === null) return null;

  const key = draftKey(scope, context);
  let raw: string | null;
  try {
    raw = storage.getItem(key);
  } catch {
    return null;
  }
  if (raw === null || raw === '') return null;

  const now = options.now ?? Date.now();
  const parsed = safeParse<Envelope<T>>(raw);
  if (parsed === null || parsed.v !== DRAFT_VERSION || typeof parsed.savedAt !== 'number') {
    clearDraft(scope, context, options);
    return null;
  }

  if (now - parsed.savedAt > DRAFT_TTL_MS) {
    // 过期即清：留着只会在下次读取时白付一次 JSON.parse，也容易让用户以为「一直丢数据」。
    clearDraft(scope, context, options);
    return null;
  }

  return parsed.data;
}

/** 写草稿。任何异常（配额满、隐私模式）都静默吞掉 —— 草稿是加分项，不能因此让记账失败。 */
export function writeDraft<T>(scope: string, context: string, data: T, options: DraftOptions = {}): void {
  const storage = resolveStorage(options.storage);
  if (storage === null) return;

  const envelope: Envelope<T> = {
    v: DRAFT_VERSION,
    savedAt: options.now ?? Date.now(),
    data,
  };
  try {
    storage.setItem(draftKey(scope, context), JSON.stringify(envelope));
  } catch {
    // 忽略写入失败
  }
}

/** 清草稿。提交成功后必须调用，否则下次打开会弹出一份已经入账的「未提交草稿」。 */
export function clearDraft(scope: string, context: string, options: DraftOptions = {}): void {
  const storage = resolveStorage(options.storage);
  if (storage === null) return;
  try {
    storage.removeItem(draftKey(scope, context));
  } catch {
    // 忽略清除失败
  }
}

/**
 * 草稿里是否有用户真正输入过的东西。
 *
 * 空表单（刚打开、什么都没填）不该存也不该提示恢复 —— 否则每次打开记账都会弹一次
 * 「上次有未提交的草稿」，几次之后用户就会闭着眼睛点「丢弃」，真出事时也一起点掉。
 */
export function isDraftMeaningful(draft: {
  totalCents?: number;
  note?: string;
  categoryChanged?: boolean;
  paymentMethodChanged?: boolean;
  spendDate?: string;
} | null): boolean {
  if (draft === null) return false;
  if ((draft.totalCents ?? 0) > 0) return true;
  if ((draft.note ?? '').trim() !== '') return true;
  return draft.categoryChanged === true || draft.paymentMethodChanged === true;
}

function safeParse<T>(raw: string): T | null {
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}