/**
 * 报表响应缓存。
 *
 * ## 为什么缓存而不是本地重算
 *
 * 报表逻辑在服务端（月报/汇总/年报合计 800+ 行 SQL：分类桶、环比、去年同期、
 * 维度排行…）。在客户端重写一份，两套实现必然随时间跑偏 —— 而「三端数字一致」
 * 是硬要求。所以口径仍由服务端唯一提供，本地只**缓存它最后一次的响应**。
 *
 * 离线时展示缓存并标注「数据截至 X」，用户知道这不是实时数。
 *
 * 存储：`meta` 表，键 `report:<类型>:<参数>`，值是原始 JSON。
 * 放 meta 而不是新表，是因为它本来就是「键值对元信息」，不值得为缓存建表。
 */
import { Db } from './Db';

/** 一份缓存的报表 + 它是什么时候拿到的 */
export interface CachedReport<T> {
  data: T;
  fetchedAt: string;
}

export class ReportCache {
  private static async read(key: string): Promise<string> {
    const rs = await Db.get().querySql('SELECT value FROM meta WHERE key = ?', [key]);
    let value = '';
    if (rs.goToFirstRow()) {
      value = rs.getString(rs.getColumnIndex('value'));
    }
    rs.close();
    return value;
  }

  /** 读缓存（没有就返回 null） */
  static async get<T>(key: string): Promise<CachedReport<T> | null> {
    const raw = await ReportCache.read(`report:${key}`);
    if (raw === '') {
      return null;
    }
    try {
      return JSON.parse(raw) as CachedReport<T>;
    } catch (e) {
      return null;
    }
  }

  /** 写缓存（拿服务端新响应时调） */
  static async put(key: string, data: Object): Promise<void> {
    const payload: CachedReport<Object> = {
      data: data,
      fetchedAt: new Date().toISOString()
    };
    await Db.get().executeSql(
      'INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)',
      [`report:${key}`, JSON.stringify(payload)]
    );
  }
}

/**
 * 报表取数：**先用缓存，再后台刷新**。
 *
 * `fetch` 是拿服务端新值的函数；成功就写缓存并回调 `onFresh`。
 * 缓存为空且请求失败时返回 null（调用方显示空态），不会抛错打断页面。
 */
export async function reportWithCache<T>(
  key: string,
  fetch: () => Promise<T>,
  onFresh: (data: T) => void
): Promise<T | null> {
  const cached = await ReportCache.get<T>(key);
  if (cached === null || Date.now() - new Date(cached.fetchedAt).getTime() > 5 * 60 * 1000) {
    try {
      const fresh = await fetch();
      await ReportCache.put(key, fresh as Object);
      onFresh(fresh);
      return fresh;
    } catch (e) {
      // 失败就用旧缓存
    }
  }
  return cached === null ? null : cached.data;
}
