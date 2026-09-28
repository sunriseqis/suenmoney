/**
 * 数据的导出 / 导入 / 备份 / 恢复（HTTP）。
 *
 * ## 为什么是纯 HTTP + 查询参数，而不是「Web 后台专用接口」
 *
 * 这层解耦成本为零，但不写清楚就会被做成「必须带浏览器会话态」——
 * 而这个接口最可能的第二个消费者恰恰不是浏览器：cron 归档、CLI 备份、
 * 迁移脚本。它们只会发 `GET /api/export?scope=month&period=2026-09`。
 *
 * ## 全部仅 admin
 *
 * 导出含**全家**的数据（不只是自己的），导入会改全家数据。
 * 客户端隐藏按钮不算权限控制，所以每一条路由都挂 `requireAdmin`。
 *
 * ## 移动端没有这一页
 *
 * 落地方式是移动端的设置页**根本不挂**这个面板（见 `web/src/utils/platform.ts`），
 * 不是隐藏按钮。代价要明说：手机本地副本一旦损坏，用户只能回到电脑上恢复。
 */
import type { FastifyInstance, FastifyReply } from 'fastify';

import { getDatabase } from '../db/index.ts';
import {
  buildPackage,
  mergePackage,
  packageFileName,
  parseScope,
  toExpenseCsv,
  validatePackage,
  writePreRestoreSnapshot,
} from '../db/repo/transfer.ts';
import { dataOverview, resetDemoData, wipeLedger } from '../db/repo/maintenance.ts';
import { badRequest } from '../lib/http-error.ts';
import { asRecord, requireEnum, requireString } from '../lib/validate.ts';
import { currentAuth, requireAdmin, requireAuth } from './guard.ts';

/**
 * 上传包的大小上限。
 *
 * 全局 `bodyLimit` 是 512KB（防灌包），但一个几年的账本数据包轻易超过它 ——
 * 不单独放宽的话，导入会以 **413 请求体过大**失败，而错误信息里
 * 完全看不出「这是你自己设的 limit」。这两个路由是 admin-only 的，
 * 放宽的风险面很小。
 */
const UPLOAD_LIMIT = 32 * 1024 * 1024;

function attachment(reply: FastifyReply, filename: string): void {
  // 文件名全是 ASCII（suenmoney-export-2026-09-20260928.json），不需要 RFC 5987 编码
  reply.header('content-disposition', `attachment; filename="${filename}"`);
}

export async function dataRoutes(app: FastifyInstance): Promise<void> {
  /**
   * 导出数据包（JSON，可再导入）。
   *
   * `scope=all` 全量；`scope=year&period=2026`；`scope=month&period=2026-09`。
   */
  app.get('/api/export', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const query = asRecord(request.query);
    const scope = parseScope(query['scope'], query['period']);

    const pkg = buildPackage(getDatabase(), scope, 'suenmoney-export');

    reply.type('application/json; charset=utf-8');
    attachment(reply, packageFileName(pkg, 'json'));
    return pkg;
  });

  /**
   * 导出对账表（CSV，给 Excel 看）。
   *
   * 与上面的 JSON 包是**同一份数据的两种投影**，不是两个功能：
   * JSON 负责「能再导回来」，CSV 负责「人能看懂、能核对」。
   * 合成一个文件就要么丢结构（CSV 表达不了分类层级与待办状态），
   * 要么 Excel 打不开（JSON）。
   */
  app.get(
    '/api/export/expenses.csv',
    { preHandler: [requireAuth, requireAdmin] },
    async (request, reply) => {
      const query = asRecord(request.query);
      const scope = parseScope(query['scope'], query['period']);

      const pkg = buildPackage(getDatabase(), scope, 'suenmoney-export');

      reply.type('text/csv; charset=utf-8');
      attachment(reply, packageFileName(pkg, 'csv'));
      return toExpenseCsv(pkg);
    },
  );

  /**
   * 导入数据包 —— **合并去重，不覆盖**。
   *
   * 指纹是 `entity_type + id`（主键全部是客户端生成的 ULID），
   * 所以同一份文件重复导入不会产生重复记录，也不会改动已有记录。
   * 这一点是刻意的：导入是一个可以放心按两次的按钮。
   */
  app.post(
    '/api/import',
    { preHandler: [requireAuth, requireAdmin], bodyLimit: UPLOAD_LIMIT },
    async (request) => {
      const auth = currentAuth(request);
      const pkg = validatePackage(request.body);

      const report = mergePackage(getDatabase(), pkg, auth.user.id, { overwrite: false });
      return { report, counts: pkg.counts, scope: pkg.scope, generatedAt: pkg.generatedAt };
    },
  );

  /**
   * 下载全量备份。
   *
   * 与「导出全部」的数据**完全相同**，只是信封不同 —— 这不是重复：
   * `format` 决定它能不能被恢复接口接受。把两者摆成两个按钮、两个文件名，
   * 是为了让「按月导出」永远不会被误当成备份拿去恢复而**静默丢掉其他月份**。
   */
  app.get('/api/backup', { preHandler: [requireAuth, requireAdmin] }, async (request, reply) => {
    const pkg = buildPackage(getDatabase(), { kind: 'all', period: '' }, 'suenmoney-backup');

    reply.type('application/json; charset=utf-8');
    attachment(reply, packageFileName(pkg, 'json'));
    return pkg;
  });

  /**
   * 一键恢复 —— **文件覆盖本地**，且**不删除**本地多出来的记录。
   *
   * 只接受 `format: 'suenmoney-backup'` 的包：这是「按月导出被当备份恢复」
   * 那条防线的最后一道。一个 9 月的导出包在这条路上会被直接拒掉，
   * 而不是把 9 月的数据覆盖上去、让其他月份看起来「没丢但其实没被恢复」。
   *
   * 恢复前自动存档一份当前全量（见 `writePreRestoreSnapshot`），
   * 路径随响应返回 —— 用户需要知道万一恢复错了去哪儿找回来。
   */
  app.post(
    '/api/backup/restore',
    { preHandler: [requireAuth, requireAdmin], bodyLimit: UPLOAD_LIMIT },
    async (request) => {
      const auth = currentAuth(request);
      const pkg = validatePackage(request.body);

      if (pkg.format !== 'suenmoney-backup') {
        throw badRequest(
          '这不是备份文件，而是导出包。导出包可能只含某一年/某一个月，'
            + '用它恢复会静默丢掉其他期间的数据。请用「导出」页里的功能，'
            + '或改用备份文件。',
        );
      }

      const db = getDatabase();
      const report = mergePackage(db, pkg, auth.user.id, {
        overwrite: true,
        snapshot: () => writePreRestoreSnapshot(db),
      });

      return { report, counts: pkg.counts, scope: pkg.scope, generatedAt: pkg.generatedAt };
    },
  );

  /**
   * 数据概览 —— 「数据」面板一进来看到的那一片。
   *
   * 三样东西都要给：
   *   · 现在库里有什么（条数 + 首笔日期）—— 让「清空」和「重置」**在做之前**
   *     就能看出会动到什么；
   *   · 恢复前的存档在哪 —— 减少「出事了不知道去哪儿找」的概率；
   *   · `resetDemoBlockers`：现在能不能重置，不能时该对用户说什么。
   *
   * 刻意**不列出历史快照文件清单**：那会变成一个新的 API 面
   * （下载指定的历史快照、删除旧快照…），而这一轮不需要它。
   */
  app.get('/api/data/overview', { preHandler: [requireAuth, requireAdmin] }, async () => {
    return { overview: dataOverview(getDatabase()) };
  });

  /**
   * 清空全部**账目** —— 支出 / 计划 / 待办。
   *
   * 保留分类、支付方式、账号：它们是配置，删掉会让记账当场没法用
   * （没有分类可选），而且它们本来就不是「账」。
   *
   * `confirm` 是**字面量而不是布尔**：一个 `POST` 打过来就把全家的账清空，
   * 太容易被一个手滑的 curl、或者一段没有上下文的脚本触发。
   * 要求调用方把动作名写出来，误触的成本就从「一次请求」变成了「一次思考」。
   */
  app.post('/api/data/wipe', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const auth = currentAuth(request);
    requireEnum(asRecord(request.body), 'confirm', ['wipe'] as const);

    const db = getDatabase();
    return {
      report: wipeLedger(db, auth.user.id, { snapshot: () => writePreRestoreSnapshot(db) }),
    };
  });

  /**
   * 重置演示数据 —— 清掉旧的，再灌一份新的。
   *
   * **只在库里只有演示数据时才允许**（判据见 `maintenance.ts` 顶部）。
   * 一个叫「重置」的按钮最容易被理解成「把我的数据整理一下」；
   * 若它照跑，用户会丢掉全部真实账目、换来一堆假账单，而且以为自己在重置。
   *
   * `today` 由客户端传：服务端从不自己推算业务日期。
   * 演示数据的每一个日期都是相对它现算的，写死的话第二年按下去
   * 会得到一份「去年的数据」。
   */
  app.post('/api/data/reset-demo', { preHandler: [requireAuth, requireAdmin] }, async (request) => {
    const auth = currentAuth(request);
    const body = asRecord(request.body);
    requireEnum(body, 'confirm', ['reset-demo'] as const);
    const today = requireString(body, 'today');

    const db = getDatabase();
    return {
      report: resetDemoData(db, auth.user.id, today, {
        snapshot: () => writePreRestoreSnapshot(db),
      }),
    };
  });
}
