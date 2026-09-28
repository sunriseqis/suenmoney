import type { FastifyInstance } from 'fastify';

import { getDatabase } from '../db/index.ts';
import { monthlyReport, summaryReport, yearlyReport } from '../db/repo/reports.ts';
import { badRequest } from '../lib/http-error.ts';
import { asRecord, optionalStrParam } from '../lib/validate.ts';
import { requireAuth } from './guard.ts';

/**
 * 报表。
 *
 * 月份 / 年份**必须由调用方显式传入**，服务端不会自己推算「今天是几号」。
 * 这是刻意的：服务端的时区不可信（容器常年跑 UTC），而客户端的本地日期
 * 才是用户认知里的「今天」。让服务端去猜，就会出现「跨零点时月度报表
 * 归属错位」这类只在特定时刻复现的问题。
 */
export async function reportRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/reports/monthly', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);
    const month = optionalStrParam(query['month'], 'month');

    if (month === undefined) {
      throw badRequest('必须显式传入 month（格式 YYYY-MM）。服务端不推算当前月份，以免受服务器时区影响');
    }
    if (!/^\d{4}-\d{2}$/.test(month)) {
      throw badRequest(`month 格式必须是 YYYY-MM，收到：${month}`);
    }

    return {
      report: monthlyReport(getDatabase(), month, optionalStrParam(query['ownerId'], 'ownerId')),
    };
  });

  app.get('/api/reports/yearly', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);
    const year = optionalStrParam(query['year'], 'year');

    if (year === undefined) {
      throw badRequest('必须显式传入 year（格式 YYYY）');
    }
    if (!/^\d{4}$/.test(year)) {
      throw badRequest(`year 格式必须是 YYYY，收到：${year}`);
    }

    return {
      report: yearlyReport(getDatabase(), year, optionalStrParam(query['ownerId'], 'ownerId')),
    };
  });

  app.get('/api/reports/summary', { preHandler: requireAuth }, async (request) => {
    const query = asRecord(request.query);
    return {
      report: summaryReport(getDatabase(), optionalStrParam(query['ownerId'], 'ownerId')),
    };
  });
}
