/**
 * 服务端入口。
 *
 * 启动顺序是刻意的：**先迁移、初始化默认项、再启动快照调度与 HTTP 监听**。
 * 反过来的话，容器刚起来的一小段时间里请求会打到还没建表的库上，表现为 500。
 */
import { config } from './config.ts';
import { migrate, openDatabase } from './db/index.ts';
import { initDefaultsIfEmpty } from './db/init-defaults.ts';
import { startDailySnapshotScheduler, stopDailySnapshotScheduler } from './db/repo/snapshots.ts';
import { startDailyWebdavScheduler, stopDailyWebdavScheduler } from './db/repo/webdav.ts';
import { buildServer } from './http/server.ts';

const db = openDatabase();

const applied = migrate(db);
if (applied.length > 0) {
  console.log(`已应用 ${applied.length} 个迁移：${applied.join(', ')}`);
}

// 自动补齐基础默认分类与支付方式（仅在库为空时触发，幂等）
initDefaultsIfEmpty(db);

// 启动每日 SQLite VACUUM INTO 运维快照调度与 WebDAV 安全备份调度
startDailySnapshotScheduler(db);
startDailyWebdavScheduler(db);

const app = await buildServer();

try {
  await app.listen({ host: config.host, port: config.port });
} catch (error) {
  app.log.error(error);
  process.exit(1);
}

/**
 * 优雅退出。
 *
 * SQLite 在 WAL 模式下正常关闭会把 -wal/-shm 归并回主库文件；只关 HTTP 服务
 * 而硬退（process.exit）不会触发归并，下次容器启动必须走崩溃恢复。
 * 因此停机顺序是：停调度器 → 关 HTTP → wal_checkpoint(TRUNCATE) → 关库 → 退出。
 * 另设 5 秒兜底：HTTP 关闭挂死时也要保证库被归并关闭，不让容器卡在 stopping。
 */
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    app.log.info(`收到 ${signal}，正在关闭`);
    stopDailySnapshotScheduler();
    stopDailyWebdavScheduler();

    const hardExit = setTimeout(() => {
      try {
        db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
        db.close();
      } finally {
        process.exit(0);
      }
    }, 5_000);
    hardExit.unref();

    app
      .close()
      .then(() => {
        clearTimeout(hardExit);
        db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
        db.close();
        process.exit(0);
      })
      .catch((error) => {
        app.log.error(error);
        process.exit(1);
      });
  });
}
