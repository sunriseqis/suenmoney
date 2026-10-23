/**
 * 网络恢复触发同步（H8）。
 *
 * 为什么需要它：`onForeground` 只能覆盖「切回前台」这一种情况。
 * Wi-Fi 断掉又恢复时应用一直在前台，不会触发任何生命周期回调 ——
 * 那三笔离线账会一直躺在队列里，直到用户手动点「立即同步」或切后台再回来。
 *
 * 所以订阅 `connection` 的 netAvailable 事件：从「无网」变「有网」时补一次推送。
 */
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { SyncEngine } from './SyncEngine';

const DOMAIN = 0x0004;
const TAG = 'NetworkMonitor';

export class NetworkMonitor {
  private static netHandle: connection.NetConnection | null = null;
  private static wasAvailable: boolean = true;

  static start(): void {
    if (NetworkMonitor.netHandle !== null) {
      return;
    }
    const handle = connection.createNetConnection();
    handle.on('netAvailable', () => {
      hilog.info(DOMAIN, TAG, '网络可用');
      if (!NetworkMonitor.wasAvailable) {
        NetworkMonitor.wasAvailable = true;
        SyncEngine.syncNow();
      }
    });
    handle.on('netLost', () => {
      hilog.info(DOMAIN, TAG, '网络断开');
      NetworkMonitor.wasAvailable = false;
    });
    handle.on('netUnavailable', () => {
      NetworkMonitor.wasAvailable = false;
    });
    try {
      handle.register((err: BusinessError) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, '注册网络监听失败：%{public}s', JSON.stringify(err));
        }
      });
      NetworkMonitor.netHandle = handle;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '注册网络监听异常');
    }
  }

  static stop(): void {
    const handle = NetworkMonitor.netHandle;
    if (handle === null) {
      return;
    }
    try {
      handle.unregister((err: BusinessError) => {
        if (err) {
          hilog.warn(DOMAIN, TAG, '注销网络监听失败');
        }
      });
    } catch (e) {
      // 忽略：进程即将退出
    }
    NetworkMonitor.netHandle = null;
  }
}
