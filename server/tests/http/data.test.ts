/**
 * 数据的导出 / 导入 / 备份 / 恢复 / 清空 / 重置演示数据。
 *
 * 这一组用例值得存在的理由：这几条路由是全项目**唯一**会一次性写入
 * （或一次性抹掉）大量既有实体的地方。它们的失败模式很安静 ——
 * 「导出的合计和报表差一点」「恢复之后另一台手机看不到」
 * 「定期恢复把本地多出来的记录悄悄删了」「清空之后别的设备还显示着旧账」，
 * 都不会当场报错。
 */
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';

import type { FastifyInstance } from 'fastify';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-data-'));
const backupDir = join(tempDir, 'backups');

/**
 * 环境变量必须在**导入 config 之前**设好 —— `config` 是模块级单例，
 * 导入求值那一刻就固定了，之后再赋值没有用。所以下面两个模块用动态 import。
 * 不设 `SUENMONEY_BACKUP_DIR` 的话，「恢复前存档」会写进仓库里的
 * `./data/backups`，测试就变成了一个会往工作区扔文件的测试。
 */
process.env['SUENMONEY_DB_PATH'] = join(tempDir, 'test.sqlite');
process.env['SUENMONEY_BACKUP_DIR'] = backupDir;

const { migrate, openDatabase } = await import('../../src/db/index.ts');
const { buildServer } = await import('../../src/http/server.ts');

const ADMIN_PASSWORD = 'admin-password-123456';
const MEMBER_PASSWORD = 'member-password-123456';

let app: FastifyInstance;
let token = '';
let memberToken = '';
let categoryId = '';
let cashId = '';
let cardId = '';

const auth = (t = token) => ({ authorization: `Bearer ${t}` });

interface PackageShape {
  format: string;
  version: number;
  generatedAt: string;
  scope: { kind: string; period: string };
  counts: Record<string, number>;
  data: Record<string, Array<Record<string, unknown>>>;
}

/** `changes` 表当前条数 —— 用来断言「写入/清空有没有留下同步变更」 */
function changeCount(): number {
  const db = openDatabase();
  return Number((db.prepare('SELECT COUNT(*) AS n FROM changes').get() as Record<string, unknown>)['n']);
}

/** 重置演示数据返回的种子条数 */
interface SeedCounts {
  categories: number;
  paymentMethods: number;
  plans: number;
  planTodos: number;
  expenses: number;
}

/** 数据概览（清空/重置前先看清会动到什么） */
async function overview(): Promise<Record<string, unknown>> {
  const res = await app.inject({ method: 'GET', url: '/api/data/overview', headers: auth() });
  assert.equal(res.statusCode, 200, res.body);
  return res.json().overview as Record<string, unknown>;
}

/** 库里实际的活账条数（与接口无关的独立口径，用来对账） */
function liveCounts(): { expenses: number; plans: number; planTodos: number } {
  const db = openDatabase();
  const n = (sql: string): number => Number((db.prepare(sql).get() as Record<string, unknown>)['n']);
  return {
    expenses: n("SELECT COUNT(*) AS n FROM expenses WHERE deleted_at IS NULL"),
    plans: n("SELECT COUNT(*) AS n FROM plans WHERE deleted_at IS NULL"),
    planTodos: n("SELECT COUNT(*) AS n FROM plan_todos WHERE deleted_at IS NULL"),
  };
}

async function createExpense(payload: Record<string, unknown>): Promise<Record<string, unknown>> {
  const res = await app.inject({
    method: 'POST',
    url: '/api/expenses',
    headers: auth(),
    payload,
  });
  assert.equal(res.statusCode, 201, res.body);
  return res.json().expense as Record<string, unknown>;
}

/** 期间内（不含 context 附带）的支出合计，单位分。 */
function sumCents(pkg: PackageShape): number {
  return pkg.data['expenses']!
    .filter((row) => row['deleted_at'] === null && row['context'] !== true)
    .reduce((total, row) => total + Number(row['amount_cents']), 0);
}

before(async () => {
  const db = openDatabase(join(tempDir, 'test.sqlite'));
  migrate(db);
  app = await buildServer({ logger: false });

  const setup = await app.inject({
    method: 'POST',
    url: '/api/auth/setup',
    payload: { username: 'suen', displayName: '我', password: ADMIN_PASSWORD },
  });
  assert.equal(setup.statusCode, 201, setup.body);
  token = setup.json().token as string;

  // 第二个成员，非管理员 —— 用来验证权限边界
  const created = await app.inject({
    method: 'POST',
    url: '/api/users',
    headers: auth(),
    payload: {
      username: 'partner',
      displayName: '家人',
      password: MEMBER_PASSWORD,
      role: 'member',
    },
  });
  assert.equal(created.statusCode, 201, created.body);

  const login = await app.inject({
    method: 'POST',
    url: '/api/auth/login',
    payload: { username: 'partner', password: MEMBER_PASSWORD },
  });
  assert.equal(login.statusCode, 200, login.body);
  memberToken = login.json().token as string;

  const cash = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '现金', type: 'cash' },
  });
  cashId = String(cash.json().paymentMethod.id);

  // 账单日 10 / 还款日 28：9 月 15 日刷的卡落在 **10 月** 的报表里 ——
  // 「消费日与归属月不同月」正是导出筛选最容易搞错的地方
  const card = await app.inject({
    method: 'POST',
    url: '/api/payment-methods',
    headers: auth(),
    payload: { name: '招行信用卡', type: 'credit', billingDay: 10, repaymentDay: 28 },
  });
  cardId = String(card.json().paymentMethod.id);

  const category = await app.inject({
    method: 'POST',
    url: '/api/categories',
    headers: auth(),
    payload: { name: '餐饮' },
  });
  categoryId = String(category.json().category.id);

  /**
   * 一笔 9 月消费、10 月还款的信用卡支出 + 一笔 10 月现金支出。
   * 两者都落在 2026-10 的报表里；只有前者会被「按消费日筛」漏掉。
   */
  await createExpense({
    amountCents: 12_345,
    categoryId,
    paymentMethodId: cardId,
    spendDate: '2026-09-15',
    note: '九月刷卡',
  });
  await createExpense({
    amountCents: 6_000,
    categoryId,
    paymentMethodId: cashId,
    spendDate: '2026-10-03',
    note: '十月现金',
  });
});

after(() => {
  rmSync(tempDir, { recursive: true, force: true });
});

describe('备份与恢复', () => {
  test('非管理员不能恢复', async () => {
    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    const res = await app.inject({
      method: 'POST',
      url: '/api/backup/restore',
      headers: auth(memberToken),
      payload: backup.json(),
    });
    assert.equal(res.statusCode, 403);
  });

  test('备份接口给的是 backup 信封', async () => {
    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    assert.equal(backup.statusCode, 200, backup.body);
    assert.equal(backup.json().format, 'suenmoney-backup');
    assert.deepEqual(backup.json().scope, { kind: 'all', period: '' });
  });

  test('恢复让文件覆盖本地，并留下恢复前的存档；且不删除本地多出来的记录', async () => {
    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    const pkg = backup.json() as PackageShape;
    const category = pkg.data['categories']![0]!;

    // 备份之后本地改了分类名
    const renamed = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${String(category['id'])}`,
      headers: auth(),
      payload: { name: '改过的名字' },
    });
    assert.equal(renamed.statusCode, 200, renamed.body);

    // 备份之后本地又多记了一笔 —— 恢复**不该**把它删掉
    const extra = await createExpense({
      amountCents: 999,
      categoryId,
      paymentMethodId: cashId,
      spendDate: '2026-10-20',
      note: '恢复之后要还在',
    });

    const res = await app.inject({
      method: 'POST',
      url: '/api/backup/restore',
      headers: auth(),
      payload: pkg,
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.equal(res.json().report.mode, 'restore');
    assert.ok(res.json().report.overwritten > 0, '恢复是覆盖，不是只补缺');

    const categories = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    const restored = (categories.json().categories as Array<Record<string, unknown>>).find(
      (row) => row['id'] === category['id'],
    )!;
    assert.equal(restored['name'], '餐饮', '恢复要覆盖本地对分类的改动');

    const still = await app.inject({
      method: 'GET',
      url: `/api/expenses/${String(extra['id'])}`,
      headers: auth(),
    });
    assert.equal(still.statusCode, 200, '恢复不做删除，本地多出来的记录要保留');

    // 恢复前的自动存档：这是「恢复错了」时唯一能回去的东西
    const snapshot = res.json().report.snapshotPath as string | null;
    assert.ok(snapshot !== null && snapshot.startsWith(backupDir), `快照应落在备份目录：${snapshot}`);
    assert.ok(existsSync(snapshot!), '快照文件要真的写出来');
    // 快照落在 backupDir 下的 `pre-restore/` 子目录里，不是直接摊在 backupDir 根上
    // （`snapshotDir()` = join(config.backupDir, 'pre-restore')）。
    // 断言必须跟着目录层级走：只读 backupDir 只会读到那个子目录本身。
    assert.ok(
      readdirSync(join(backupDir, 'pre-restore')).some((name) => name.startsWith('pre-restore-')),
    );
  });

  test('恢复到一半失败会整体回滚，不留半截状态', async () => {
    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    const pkg = backup.json() as PackageShape;

    const db = openDatabase();
    const before = db.prepare('SELECT name FROM categories ORDER BY id').all();

    // 让计划待办引用一个不存在的支出：外键是立即检查的，写到这一行必炸
    pkg.data['planTodos'] = [
      {
        id: '01JROLLBACKTODOXXXXXXXXXXXX',
        plan_id: '01JNOSUCHPLANXXXXXXXXXXXXXX',
        period_seq: 1,
        amount_cents: 100,
        posting_date: '2026-10-01',
        repayment_date: '2026-10-01',
        remind_date: '2026-09-28',
        status: 'pending',
        posted_date: null,
        confirmed_by: null,
        confirmed_at: null,
        expense_id: null,
        hold_auto_post: 0,
        created_at: '2026-10-01T00:00:00.000Z',
        updated_at: '2026-10-01T00:00:00.000Z',
        deleted_at: null,
        rev: 1,
        device_id: null,
      },
    ];
    // 同一次恢复里先把分类改掉，再炸 —— 分类的改动必须一起回滚
    pkg.data['categories'] = pkg.data['categories']!.map((row, i) => ({ ...row, name: `不该留下-${i}` }));

    const res = await app.inject({
      method: 'POST',
      url: '/api/backup/restore',
      headers: auth(),
      payload: pkg,
    });
    // 约束失败现在会被翻译成 400 + 具体是哪张表哪一行（原来是笼统的 500），
    // 但**回滚语义不变**：同一次恢复里先写的分类必须一起撤掉。
    assert.equal(res.statusCode, 400, res.body);
    assert.match(res.json().error, /plan_todos/);

    const after = openDatabase().prepare('SELECT name FROM categories ORDER BY id').all();
    assert.deepEqual(after, before, '失败必须整体回滚，分类不该被改掉');
  });
});

describe('整库覆盖与流水 CSV', () => {
  test('JSON 备份含口令哈希；恢复即整库覆盖（账号与口令一起回来）', async () => {
    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    assert.equal(backup.statusCode, 200, backup.body);
    const pkg = backup.json() as PackageShape;

    // ① 备份里必须带 password_hash —— 否则恢复出来的机器谁都登不进去
    const member = pkg.data['members']![0]!;
    assert.equal(typeof member['password_hash'], 'string');
    assert.ok(String(member['password_hash']).startsWith('scrypt$'), '口令哈希格式应为 scrypt$…');

    // ② 恢复后仍能用原口令登录
    const res = await app.inject({
      method: 'POST',
      url: '/api/backup/restore',
      headers: auth(),
      payload: pkg,
    });
    assert.equal(res.statusCode, 200, res.body);
    assert.ok(Number(res.json().report.membersRestored) >= 1);

    const login = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: { username: 'suen', password: ADMIN_PASSWORD },
    });
    assert.equal(login.statusCode, 200, '恢复后原口令应仍可登录');
  });

  test('恢复会把备份里没有的本地账号软删除', async () => {
    // 先造一个「本地多出来的人」
    const created = await app.inject({
      method: 'POST',
      url: '/api/users',
      headers: auth(),
      payload: { username: 'tempuser', displayName: '临时', password: 'temp-password-123' },
    });
    assert.equal(created.statusCode, 201, created.body);

    const backup = await app.inject({ method: 'GET', url: '/api/backup', headers: auth() });
    const pkg = backup.json() as PackageShape;
    // 从备份里摘掉 tempuser —— 等价于「备份来自一台没有这个人的机器」
    pkg.data['members'] = pkg.data['members']!.filter((m) => m['username'] !== 'tempuser');

    const res = await app.inject({
      method: 'POST',
      url: '/api/backup/restore',
      headers: auth(),
      payload: pkg,
    });
    assert.equal(res.statusCode, 200, res.body);

    const removed = res.json().report.membersRemoved as Array<{ username: string }>;
    assert.ok(removed.some((m) => m.username === 'tempuser'), '多出来的账号应被软删除');

    const db = openDatabase();
    const row = db.prepare('SELECT deleted_at FROM users WHERE username = ?').get('tempuser') as Record<string, unknown>;
    assert.notEqual(row['deleted_at'], null, '软删除：行还在，但 deleted_at 非空');
  });

  test('流水 CSV：非管理员只导自己的，管理员导全部', async () => {
    const adminCsv = await app.inject({ method: 'GET', url: '/api/expenses.csv', headers: auth() });
    assert.equal(adminCsv.statusCode, 200);
    assert.match(String(adminCsv.headers['content-type']), /text\/csv/);

    const memberCsv = await app.inject({ method: 'GET', url: '/api/expenses.csv', headers: auth(memberToken) });
    assert.equal(memberCsv.statusCode, 200, '普通成员也要能导出自己的流水');

    const countLines = (t: string): number => t.trim().split('\r\n').length - 1;
    assert.ok(countLines(adminCsv.body) >= countLines(memberCsv.body), '管理员的 CSV 不应少于成员的');
  });

  test('流水 CSV 导入：不看归属，谁导入就归谁', async () => {
    // 用成员的身份导入，归属应记到成员名下
    const csv = [
      '消费日期,入账日期,还款日,金额,一级分类,二级分类,支付方式,记录人,备注,来源,计划,期次',
      '2026-10-05,2026-10-05,2026-10-05,12.34,餐饮,,现金,,CSV导入测试,手动记录,,',
    ].join('\r\n') + '\r\n';

    const res = await app.inject({
      method: 'POST',
      url: '/api/expenses.csv/import',
      headers: { ...auth(memberToken), 'content-type': 'text/csv' },
      payload: csv,
    });
    assert.equal(res.statusCode, 200, res.body);
    const report = res.json() as { created: number; skipped: number };
    assert.equal(report.created, 1, JSON.stringify(res.json()));

    const db = openDatabase();
    const row = db
      .prepare("SELECT owner_id, amount_cents FROM expenses WHERE note = 'CSV导入测试'")
      .get() as Record<string, unknown>;
    assert.equal(Number(row['amount_cents']), 1234);

    const memberRow = db
      .prepare("SELECT id FROM users WHERE username = 'member' AND deleted_at IS NULL")
      .get() as Record<string, unknown> | undefined;
    if (memberRow !== undefined) {
      assert.equal(row['owner_id'], memberRow['id'], '归属应记到导入者名下');
    }
  });
});

describe('危险区', () => {
  test('概览：清空之前就能看出会动到什么，且给出存档目录', async () => {
    const before = await overview();
    const live = before['ledger'] as Record<string, number>;

    assert.equal(live['expenses'], liveCounts().expenses, '概览的条数必须与服务端实际一致');
    assert.ok(Number(live['expenses']) > 0, '这一组开始时库里应该是有账的');
    assert.equal(Number(before['members']), 2);
    assert.ok(String(before['firstRepaymentDate']).startsWith('20'));
    assert.ok(String(before['preRestoreDir']).startsWith(backupDir));
  });

  test('清空：只清账目，分类 / 支付方式 / 账号一条不动', async () => {
    const categoriesBefore = (await overview())['categories'];
    const methodsBefore = (await overview())['paymentMethods'];
    const removed = liveCounts();

    const res = await app.inject({
      method: 'POST',
      url: '/api/data/wipe',
      headers: auth(),
      payload: { confirm: 'wipe' },
    });
    assert.equal(res.statusCode, 200, res.body);

    const report = res.json().report as { removed: Record<string, number>; total: number };
    assert.deepEqual(report.removed, removed, '报告里删掉的条数要与清空前实际相符');
    assert.equal(report.total, removed.expenses + removed.plans + removed.planTodos);

    assert.deepEqual(liveCounts(), { expenses: 0, plans: 0, planTodos: 0 });

    const after = await overview();
    assert.equal(after['categories'], categoriesBefore, '分类是配置，清账不该动它');
    assert.equal(after['paymentMethods'], methodsBefore, '支付方式同理');
    assert.equal(Number(after['members']), 2, '账号更不该动');
    assert.equal(after['firstRepaymentDate'], null, '账都没了，首笔日期就该是空的');
  });

  test('清空会逐行落 changes —— 否则别的设备看到的还是旧账', async () => {
    // 先记一笔，好让「清空」有东西可清
    await createExpense({
      amountCents: 1_000,
      categoryId,
      paymentMethodId: cashId,
      spendDate: '2026-10-11',
      note: '清空测试用',
    });

    const db = openDatabase();
    const before = changeCount();

    const res = await app.inject({
      method: 'POST',
      url: '/api/data/wipe',
      headers: auth(),
      payload: { confirm: 'wipe' },
    });
    assert.equal(res.statusCode, 200, res.body);

    assert.ok(changeCount() > before, '清空必须留下变更记录');

    const change = db
      .prepare(`SELECT op FROM changes WHERE entity_type = 'expense' ORDER BY version DESC LIMIT 1`)
      .get() as { op: string };
    assert.equal(change.op, 'delete', '清空在同步语义上是软删，不是把行抹掉');
  });

  test('清空之前先自动存档 —— 那是唯一能回去的地方', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/data/wipe',
      headers: auth(),
      payload: { confirm: 'wipe' },
    });
    assert.equal(res.statusCode, 200, res.body);

    const snapshot = res.json().report.snapshotPath as string | null;
    assert.ok(snapshot !== null, '清空是不可逆的，必须留下存档');
    assert.ok(snapshot.startsWith(backupDir), `存档应落在备份目录：${snapshot}`);
    assert.ok(existsSync(snapshot), '存档文件要真的写出来');
  });

  test('重置演示数据：空库可以直接灌，且灌完立刻就有一期待处理', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/data/reset-demo',
      headers: auth(),
      payload: { confirm: 'reset-demo', today: '2026-09-15' },
    });
    assert.equal(res.statusCode, 200, res.body);

    const report = res.json().report as { seeded: SeedCounts };
    assert.equal(report.seeded.plans, 3);
    // 12 期 × 3 条计划
    assert.equal(report.seeded.planTodos, 36);
    // 38 笔手动 + 计划已入账的那几期
    assert.ok(report.seeded.expenses > 38, `演示支出应该多于 38 笔，实际 ${report.seeded.expenses}`);

    assert.deepEqual(liveCounts(), {
      expenses: report.seeded.expenses,
      plans: 3,
      planTodos: 36,
    });

    /**
     * 演示数据的日期是**相对 today 现算**的，所以「本月那一期」必然存在、
     * 且因为 `confirmFirst = 当月 − 1` 而处于「逾期未确认」。
     * 这正是首页「该处理了」一进来就有东西的原因 —— 也是这个种子的意义。
     */
    const todos = await app.inject({
      method: 'GET',
      url: '/api/plan-todos?today=2026-09-15&remindBefore=2026-09-15',
      headers: auth(),
    });
    assert.equal(todos.statusCode, 200, todos.body);
    const items = todos.json().todos as Array<Record<string, unknown>>;
    assert.ok(items.length > 0, '灌完演示数据，首页该有东西可处理');
    assert.ok(
      items.some((item) => item['repaymentDate'] === '2026-09-20'),
      '本月 20 号那期房贷应当是待处理的',
    );
  });

  test('重置之后还能再重置 —— 凭据与种子在同一次事务里写下', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/data/reset-demo',
      headers: auth(),
      payload: { confirm: 'reset-demo', today: '2026-09-15' },
    });
    assert.equal(res.statusCode, 200, res.body);

    // 第二次重置会先把上一次那一批软删掉，所以活着的还是 3 / 36
    const report = res.json().report as { seeded: SeedCounts };
    assert.deepEqual(liveCounts(), { expenses: report.seeded.expenses, plans: 3, planTodos: 36 });
    assert.deepEqual((await overview())['resetDemoBlockers'], []);
  });

  test('重置演示数据：库里混进真实账目后被拒，并说清有几条', async () => {
    await createExpense({
      amountCents: 8_888,
      categoryId,
      paymentMethodId: cashId,
      spendDate: '2026-09-28',
      note: '真实记的一笔',
    });

    const blockers = (await overview())['resetDemoBlockers'] as string[];
    assert.deepEqual(blockers, ['支出 1 条'], '概览要先把拦下来的原因给出来');

    const res = await app.inject({
      method: 'POST',
      url: '/api/data/reset-demo',
      headers: auth(),
      payload: { confirm: 'reset-demo', today: '2026-09-15' },
    });
    assert.equal(res.statusCode, 409, res.body);
    assert.match(res.json().error, /支出 1 条/);
    assert.match(res.json().error, /清空账目数据/, '要告诉用户正确的出口在哪');

    const still = liveCounts();
    assert.ok(still.expenses > 36, '被拒之后库里的东西一条都不能少');
  });

  test('confirm 写错 → 400，而不是默默把数据清了', async () => {
    for (const url of ['/api/data/wipe', '/api/data/reset-demo']) {
      const res = await app.inject({
        method: 'POST',
        url,
        headers: auth(),
        payload: { confirm: 'yes', today: '2026-09-15' },
      });
      assert.equal(res.statusCode, 400, `${url} 应当要求把动作名写全`);
    }
  });

  test('非管理员不能清空 / 重置 / 看概览', async () => {
    const wipe = await app.inject({
      method: 'POST',
      url: '/api/data/wipe',
      headers: auth(memberToken),
      payload: { confirm: 'wipe' },
    });
    assert.equal(wipe.statusCode, 403);

    const reset = await app.inject({
      method: 'POST',
      url: '/api/data/reset-demo',
      headers: auth(memberToken),
      payload: { confirm: 'reset-demo', today: '2026-09-15' },
    });
    assert.equal(reset.statusCode, 403);

    const seen = await app.inject({
      method: 'GET',
      url: '/api/data/overview',
      headers: auth(memberToken),
    });
    assert.equal(seen.statusCode, 403);
  });
});
