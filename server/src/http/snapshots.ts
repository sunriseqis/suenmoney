/**
 * 运维数据库快照 API（仅限管理员）。
 */
import { createReadStream } from 'node:fs';
import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  createSnapshot,
  deleteSnapshot,
  getSnapshotPath,
  listSnapshots,
} from '../db/repo/snapshots.ts';
import { notFound } from '../lib/http-error.ts';
import { asRecord, requireString } from '../lib/validate.ts';
import { requireAdmin, requireAuth } from './guard.ts';

export async function snapshotRoutes(app: FastifyInstance): Promise<void> {
  /** 列出所有运维快照 */
  app.get('/api/snapshots', { preHandler: [requireAuth, requireAdmin] }, async () => {
    return { snapshots: listSnapshots() };
  });

  /** 立即触发一次 VACUUM INTO 快照 */
  app.post('/api/snapshots', { preHandler: [requireAuth, requireAdmin] }, async () => {
    const db = getDatabase();
    const snapshot = createSnapshot(db);
    return { snapshot };
  });

  /** 下载指定的快照文件 */
  app.get('/api/snapshots/:filename', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const params = asRecord(request.params);
    const filename = requireString(params, 'filename');

    const path = getSnapshotPath(filename);
    if (!path) {
      throw notFound('快照文件不存在或名称非法');
    }

    reply.header('content-disposition', `attachment; filename="${filename}"`);
    reply.type('application/x-sqlite3');
    return reply.send(createReadStream(path));
  });

  /** 删除指定的快照文件 */
  app.delete('/api/snapshots/:filename', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const params = asRecord(request.params);
    const filename = requireString(params, 'filename');

    const success = deleteSnapshot(filename);
    if (!success) {
      throw notFound('快照文件不存在或无法删除');
    }

    return { success: true };
  });
}
