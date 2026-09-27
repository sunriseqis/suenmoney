/**
 * 服务端入口。
 *
 * 启动顺序是刻意的：**先迁移、再监听**。反过来的话，容器刚起来的一小段时间里
 * 请求会打到还没建表的库上，表现为 500 —— 而这恰好是健康检查最可能来访问的时刻。
 */
import { config } from './config.ts';
import { migrate, openDatabase } from './db/index.ts';
import { buildServer } from './http/server.ts';

const db = openDatabase();

const applied = migrate(db);
if (applied.length > 0) {
  console.log(`已应用 ${applied.length} 个迁移：${applied.join(', ')}`);
}

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
 * SQLite 在 WAL 模式下正常关闭会把 -wal/-shm 归并回主库文件；直接 kill
 * 虽然不会损坏数据库，但会留下需要下次打开时恢复的 WAL，备份脚本若在
 * 那个窗口抓走文件就会拿到需要恢复的副本。给一点时间收尾更稳妥。
 */
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    app.log.info(`收到 ${signal}，正在关闭`);
    void app.close().then(() => process.exit(0));
  });
}
