/**
 * 分类的**本地个性化**（颜色 / 图标）。
 *
 * ## 为什么存在
 *
 * 服务端只把「分类名 + 层级」当契约：`color` / `icon` 是各端的渲染细节，
 * 跨端本来就无法统一（Web 用 lucide + `--chart-N`，原生用 `sys.symbol.*` + 本地调色板）。
 * 若允许写服务端，两端会互相覆盖对方的配色。
 *
 * 所以 Web 的颜色/图标偏好存在**浏览器本地**（localStorage）：
 *   · 只影响这台设备上的这个浏览器；
 *   · 不同步、不回推服务端；
 *   · 换设备/清缓存后回到「服务端存量值 → 按名字派生」的默认表现。
 *
 * 读取优先级：本地偏好 → 服务端存量值 → 按名字推导。
 */
import { ref } from 'vue';

const STORAGE_KEY = 'suenmoney:cat-prefs';

export interface CategoryPref {
  /** 色号 1..16，空串表示没设过 */
  color?: string;
  /** 图标名，空串表示没设过 */
  icon?: string;
}

function readStorage(): Record<string, CategoryPref> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return {};
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== 'object') return {};
    return parsed as Record<string, CategoryPref>;
  } catch {
    // 隐私模式 / 配额满 / 脏数据：当作没有偏好，不影响页面渲染
    return {};
  }
}

/** 响应式镜像：改了之后依赖它的组件（分类徽位）会重绘 */
export const categoryPrefs = ref<Record<string, CategoryPref>>(readStorage());

function persist(): void {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(categoryPrefs.value));
  } catch {
    // 写不进去也不该阻塞操作：本次会话内仍然生效
  }
}

export function prefOf(id: string | null | undefined): CategoryPref {
  if (!id) return {};
  return categoryPrefs.value[id] ?? {};
}

/** 设置颜色/图标偏好（传空串表示恢复默认） */
export function setPref(id: string, patch: CategoryPref): void {
  const current = { ...(categoryPrefs.value[id] ?? {}) };
  if (patch.color !== undefined) current.color = patch.color;
  if (patch.icon !== undefined) current.icon = patch.icon;
  const next = { ...categoryPrefs.value };
  if ((current.color ?? '') === '' && (current.icon ?? '') === '') {
    delete next[id];
  } else {
    next[id] = current;
  }
  categoryPrefs.value = next;
  persist();
}

/** 清空全部本地偏好（诊断/重置用） */
export function clearPrefs(): void {
  categoryPrefs.value = {};
  persist();
}
