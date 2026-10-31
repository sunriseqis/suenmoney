/**
 * WebDAV 每日备份的「今天」判定（本地时区）测试。
 *
 * 背景：容器 TZ 固定为 Asia/Shanghai（见 server/Dockerfile），而旧实现用
 * `new Date().toISOString().slice(0, 10)` 取「今天」—— 那是 UTC 日期。
 * 北京时间 00:00–08:00 之间 UTC 还停在前一天，于是「今天已备份」误判成立，
 * 当天的定时备份被静默跳过且不报错。
 *
 * 本文件只测这一个行为，不重复 webdav.test.ts 里的 HTTP 用例。
 * 注意：TZ 是进程级环境变量，node --test 每个测试文件独立进程，所以在这里
 * 设 TZ 不会影响其它测试文件。
 */
process.env['TZ'] = 'Asia/Shanghai';

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { hasBackedUpToday, localDateString } from '../../src/db/repo/webdav.ts';
import { mnFileName } from '../../src/lib/backup-crypto.ts';

const status = (lastBackupAt: string | null, lastBackupStatus: 'success' | 'error' | null = 'success') => ({
  lastBackupAt,
  lastBackupStatus,
  lastBackupMessage: null,
  lastBackupFilename: null,
});

describe('localDateString 取服务器本地时区的今天', () => {
  test('凌晨 0 点后取到的是本地日期，不是 UTC 日期', () => {
    // 2026-10-01T00:30+08:00 === 2026-09-30T16:30Z
    const d = new Date('2026-10-01T00:30:00+08:00');
    assert.equal(d.toISOString().slice(0, 10), '2026-09-30', '前提：UTC 日期确实晚一天');
    assert.equal(localDateString(d), '2026-10-01');
  });

  test('UTC 午后（本地已是次日）同样按本地日期', () => {
    // 2026-10-01T16:30Z === 2026-10-02T00:30+08:00
    assert.equal(localDateString(new Date('2026-10-01T16:30:00Z')), '2026-10-02');
  });

  test('非凌晨时段与 UTC 日期一致', () => {
    assert.equal(localDateString(new Date('2026-10-01T04:00:00Z')), '2026-10-01');
  });

  test('与每日备份的文件名同一口径', () => {
    // WebDAV 每日调度的文件名也按「本地今天」，凌晨不应退回昨天
    assert.equal(mnFileName(new Date('2026-10-01T00:30:00+08:00')), 'suenmoney-backup-2026-10-01.mn');
  });
});

describe('hasBackedUpToday 凌晨不误判「今天已备份」', () => {
  test('凌晨 0 点：昨天 23:00 的备份不算今天已备份', () => {
    // 昨天 23:00 本地 === 2026-09-30T15:00Z，落在 UTC 的 9-30
    const now = new Date('2026-10-01T00:30:00+08:00');
    assert.equal(hasBackedUpToday(status('2026-09-30T15:00:00.000Z'), now), false);
  });

  test('凌晨 0 点：UTC 日期前缀相同也不得跳过', () => {
    // 这正是旧实现的误判现场：todayStr 取到 '2026-09-30'，
    // lastBackupAt 也是 '2026-09-30T…Z'，startsWith 成立 → 当天备份被跳过
    const now = new Date('2026-10-01T00:30:00+08:00');
    const lastBackupAt = '2026-09-30T15:00:00.000Z';
    assert.ok(lastBackupAt.startsWith('2026-09-30'));
    assert.equal(hasBackedUpToday(status(lastBackupAt), now), false, '必须仍需执行当天备份');
  });

  test('同一天内已成功备份则跳过（含凌晨）', () => {
    const now = new Date('2026-10-01T00:30:00+08:00');
    // 今天 00:10 本地 === 2026-09-30T16:10Z
    assert.equal(hasBackedUpToday(status('2026-09-30T16:10:00.000Z'), now), true);
  });

  test('普通时段：今天已成功备份则跳过', () => {
    const now = new Date('2026-10-01T10:00:00+08:00');
    assert.equal(hasBackedUpToday(status('2026-10-01T01:00:00.000Z'), now), true);
    assert.equal(hasBackedUpToday(status('2026-09-30T15:00:00.000Z'), now), false);
  });

  test('从未备份过 / 上次失败 / 时间戳损坏，都不跳过', () => {
    const now = new Date('2026-10-01T00:30:00+08:00');
    assert.equal(hasBackedUpToday(status(null), now), false);
    assert.equal(hasBackedUpToday(status('2026-09-30T16:10:00.000Z', 'error'), now), false);
    assert.equal(hasBackedUpToday(status('not-a-date'), now), false);
  });
});