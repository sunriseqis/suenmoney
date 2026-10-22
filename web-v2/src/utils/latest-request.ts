/**
 * 「只认最新一次」请求守卫。
 *
 * ## 为什么需要
 * 视图层的刷新入口有很多：`watch(ui.dataVersion)`、`watch(month/scope)`、
 * 网络恢复后的 `watch(syncStore.isOnline)`、页面内手动刷新/下拉。
 * 每一个都会发请求，而 HTTP 不保证返回顺序 —— 慢网下先发的慢请求可能后到，
 * 把后发请求拿到的新数据**覆盖掉**，用户看到金额「跳回去」，
 * 且列表与合计对不上（一个来自旧请求、一个来自新请求），比单纯的慢更难解释。
 *
 * ## 用法
 * ```ts
 * const guard = createLatestGuard();
 * async function load() {
 *   const token = guard.begin();          // 发请求前捕获当前序号
 *   const data = await api();
 *   if (!guard.isLatest(token)) return;  // 已经不是最新一次 → 丢弃，连 loading 都不碰
 *   apply(data);
 * }
 * ```
 *
 * 关键在`finally` 里的 loading 收尾也必须判序号：
 * 否则被丢弃的旧请求会提前把 loading 关掉，界面在数据还没到时就不再显示加载态。
 */

export interface LatestGuard {
  /** 发请求前调用：取一个新序号并返回它。 */
  begin(): number;
  /** 响应回来后调用：token 仍是最新的一次才允许写状态。 */
  isLatest(token: number): boolean;
}

export function createLatestGuard(): LatestGuard {
  let latest = 0;
  return {
    begin(): number {
      latest += 1;
      return latest;
    },
    isLatest(token: number): boolean {
      return token === latest;
    },
  };
}