type NetworkChangeListener = (isOnline: boolean) => void;

interface NetworkInformation extends EventTarget {
  type?: string;
  effectiveType?: string;
  downlink?: number;
  rtt?: number;
  saveData?: boolean;
  onchange?: EventListener;
}

/**
 * 监听网络状态变更（断网、连网、以及 移动网络 ↔ Wi-Fi 切换）。
 *
 * 核心设计：
 * 当网络从移动蜂窝切到家庭 Wi-Fi 时，内网服务器（如 192.168.x.x）可能变得可达；
 * 当从 Wi-Fi 切到蜂窝时，内网不可达，需降级至公网/Tailscale。
 * 本模块全面捕获这两种切换，并提供防抖通知。
 */
export function onNetworkChange(callback: NetworkChangeListener): () => void {
  let debounceTimer: ReturnType<typeof setTimeout> | undefined;

  const triggerChange = () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const online = typeof navigator !== 'undefined' ? navigator.onLine : true;
      callback(online);
    }, 200);
  };

  const handleOnline = () => triggerChange();
  const handleOffline = () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    callback(false);
  };

  if (typeof window !== 'undefined') {
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
  }

  // 监听 NetworkInformation 连接类型变更（支持 Wi-Fi 与移动网络互相切换感知）
  const nav = typeof navigator !== 'undefined' ? (navigator as unknown as { connection?: NetworkInformation }) : undefined;
  const connection = nav?.connection;

  if (connection && typeof connection.addEventListener === 'function') {
    connection.addEventListener('change', triggerChange);
  }

  // 安卓 WebView 里 online/offline 事件常常完全不触发（真机实测：断网恢复后
  // 应用仍自认为离线，待同步提醒不消失）。所以注册时若 navigator 自报在线，
  // 就乐观放行一次回调，让上层立刻安排一次真实探测；连通性最终由 sync 的心跳校正。
  if (typeof navigator !== 'undefined' && navigator.onLine) {
    triggerChange();
  }

  return () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    if (typeof window !== 'undefined') {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    }
    if (connection && typeof connection.removeEventListener === 'function') {
      connection.removeEventListener('change', triggerChange);
    }
  };
}
