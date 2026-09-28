/**
 * 分类与支付方式的端到端测试。
 *
 * 重点覆盖「业务规则」而非「CRUD 能不能跑」—— 这类接口真正会出问题的地方
 * 是边界：同层重名、层级上限、停用前置条件、现金类不许有账单周期。
 */
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, describe, test } from 'node:test';
import type { FastifyInstance } from 'fastify';

import { migrate, openDatabase } from '../../src/db/index.ts';
import { buildServer } from '../../src/http/server.ts';

const tempDir = mkdtempSync(join(tmpdir(), 'suenmoney-res-'));
const db = openDatabase(join(tempDir, 'test.sqlite'));
migrate(db);

let app: FastifyInstance;
let token = '';

const auth = () => ({ authorization: `Bearer ${token}` });

before(async () => {
  app = await buildServer({ logger: false });

  const setup = await app.inject({
    method: 'POST',
    url: '/api/auth/setup',
    payload: { username: 'suen', displayName: '我', password: 'correct-horse' },
  });
  token = setup.json().token as string;
});

after(async () => {
  await app.close();
  rmSync(tempDir, { recursive: true, force: true });
});

describe('分类', () => {
  test('未登录一律 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/categories' });
    assert.equal(res.statusCode, 401);
  });

  test('未登录不能创建', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      payload: { name: '餐饮' },
    });
    assert.equal(res.statusCode, 401);
  });

  let parentId = '';
  let childId = '';
  /** 第三轮的移动测试用它当目标父级 */
  let trafficId = '';

  test('创建一级分类', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '餐饮' },
    });
    assert.equal(res.statusCode, 201);

    const category = res.json().category;
    assert.equal(category.depth, 1);
    assert.equal(category.parentId, null);
    assert.equal(category.isEnabled, true);
    parentId = category.id;
  });

  test('创建二级分类', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '外卖', parentId },
    });
    assert.equal(res.statusCode, 201);

    const category = res.json().category;
    assert.equal(category.depth, 2);
    assert.equal(category.parentId, parentId);
    childId = category.id;
  });

  test('同层重名 → 409（而不是 500）', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '餐饮' },
    });
    assert.equal(res.statusCode, 409);
    assert.match(res.json().error, /同名/);
  });

  test('不同层可以同名', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '餐饮', parentId },
    });
    assert.equal(res.statusCode, 201, '二级分类叫「餐饮」应当允许，唯一性只按同层判定');
  });

  test('最多两级：不能在二级分类下再建子级', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '三级分类', parentId: childId },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /最多 2 级/);
  });

  test('父级不存在 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '孤儿', parentId: '01M3FARY3CT5HGYJ37PB1E2TW7' },
    });
    assert.equal(res.statusCode, 400);
  });

  test('列表返回树形结构', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    assert.equal(res.statusCode, 200);

    const roots = res.json().categories as Array<Record<string, unknown>>;
    const food = roots.find((item) => item['id'] === parentId);
    assert.ok(food !== undefined, '应能找到一级分类「餐饮」');
    assert.equal((food['children'] as unknown[]).length, 2, '其下应有 2 个二级分类');
  });

  test('改名', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { name: '外卖点餐', icon: '🍜' },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().category.name, '外卖点餐');
    assert.equal(res.json().category.icon, '🍜');
  });

  test('有子分类的一级分类不能停用', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${parentId}`,
      headers: auth(),
      payload: { isEnabled: false },
    });
    assert.equal(res.statusCode, 409);
    assert.match(res.json().error, /子分类/);
  });

  test('停用二级分类后可以再启用', async () => {
    const disable = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { isEnabled: false },
    });
    assert.equal(disable.statusCode, 200);
    assert.equal(disable.json().category.isEnabled, false);

    const enable = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { isEnabled: true },
    });
    assert.equal(enable.statusCode, 200);
    assert.equal(enable.json().category.isEnabled, true);
  });

  test('不存在的分类 → 404', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: '/api/categories/01M3FARY3CT5HGYJ37PB1E2TW8',
      headers: auth(),
      payload: { name: 'x' },
    });
    assert.equal(res.statusCode, 404);
  });

  /* ---- 第三轮新增：笔数口径 + 同深度移动 ------------------------------- */

  test('一级分类的笔数**累计子分类**，二级只数自己', async () => {
    const method = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '口径测试用现金', type: 'cash' },
    });
    const paymentMethodId = method.json().paymentMethod.id;

    const before = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    const food = (before.json().categories as Array<Record<string, unknown>>).find(
      (item) => item['id'] === parentId,
    );
    assert.ok(food !== undefined);
    const childIds = (food['children'] as Array<Record<string, unknown>>).map((item) => item['id']);
    assert.equal(childIds.length, 2, '「餐饮」下应有 2 个二级分类');

    // 两个子分类各记一笔
    for (const [index, categoryId] of childIds.entries()) {
      const created = await app.inject({
        method: 'POST',
        url: '/api/expenses',
        headers: auth(),
        payload: {
          amountCents: 100 + index,
          categoryId,
          paymentMethodId,
          spendDate: '2026-09-12',
        },
      });
      assert.equal(created.statusCode, 201);
    }

    const after = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    const foodAfter = (after.json().categories as Array<Record<string, unknown>>).find(
      (item) => item['id'] === parentId,
    );
    assert.ok(foodAfter !== undefined);

    // 只往二级记账的家庭，一级分类不该显示 0 笔 —— 而它旁边就是「停用」按钮
    assert.equal(foodAfter['expenseCount'], 2, '一级分类应累计子分类的笔数');

    const children = foodAfter['children'] as Array<Record<string, unknown>>;
    assert.deepEqual(
      children.map((item) => item['expenseCount']),
      [1, 1],
      '二级分类只数直接挂在它下面的记录',
    );
  });

  test('二级分类可以在两个一级分类之间移动（同深度）', async () => {
    const traffic = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '交通' },
    });
    trafficId = traffic.json().category.id;

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { parentId: trafficId },
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.json().category.parentId, trafficId);
    assert.equal(res.json().category.depth, 2, '同深度移动，depth 不变');

    const tree = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    const roots = tree.json().categories as Array<Record<string, unknown>>;
    const moved = roots.find((item) => item['id'] === trafficId);
    assert.equal((moved?.['children'] as unknown[]).length, 1, '移动后应挂在新的父级下');
  });

  test('移动到目标层级后撞上同名 → 409', async () => {
    const tree = await app.inject({ method: 'GET', url: '/api/categories', headers: auth() });
    const traffic = (tree.json().categories as Array<Record<string, unknown>>).find(
      (item) => item['id'] === trafficId,
    );
    const movedName = ((traffic?.['children'] as Array<Record<string, unknown>>)[0] ?? {})['name'];

    await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: String(movedName), parentId },
    });

    // 把已移动的那条挪回「餐饮」：那边现在也有一条同名了
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { parentId },
    });
    assert.equal(res.statusCode, 409, '重名要按**目标**层级判定，不是原来那一层');
    assert.match(res.json().error, /同名/);
  });

  test('一级分类不能跨深度移动 → 400', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${parentId}`,
      headers: auth(),
      payload: { parentId: trafficId },
    });
    assert.equal(res.statusCode, 400, '一级变二级会让它原本汇总的兄弟分类集体改归属');
    assert.match(res.json().error, /跨深度/);
  });

  test('二级分类不能提升为一级 → 400', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { parentId: null },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /必须挂在一个一级分类下/);
  });

  test('不能移动到二级分类下 → 400', async () => {
    const anotherChild = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '另一个二级', parentId: trafficId },
    });
    assert.equal(anotherChild.statusCode, 201);

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { parentId: anotherChild.json().category.id },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /只能移动到一级分类下/);
  });

  test('不能移动到已停用的一级分类下 → 400', async () => {
    const archived = await app.inject({
      method: 'POST',
      url: '/api/categories',
      headers: auth(),
      payload: { name: '归档' },
    });
    const archivedId = archived.json().category.id;

    await app.inject({
      method: 'PATCH',
      url: `/api/categories/${archivedId}`,
      headers: auth(),
      payload: { isEnabled: false },
    });

    const res = await app.inject({
      method: 'PATCH',
      url: `/api/categories/${childId}`,
      headers: auth(),
      payload: { parentId: archivedId },
    });
    assert.equal(res.statusCode, 400, '移进停用的一级会让这个二级整组从记账选择器里消失');
    assert.match(res.json().error, /已停用/);
  });
});

describe('支付方式', () => {
  let cashId = '';
  let creditId = '';

  test('现金类：账单日与还款日必须为空', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '现金', type: 'cash' },
    });
    assert.equal(res.statusCode, 201);

    const method = res.json().paymentMethod;
    assert.equal(method.type, 'cash');
    assert.equal(method.billingDay, null);
    assert.equal(method.repaymentDay, null);
    cashId = method.id;
  });

  test('现金类传了账单日 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '怪现金', type: 'cash', billingDay: 10, repaymentDay: 28 },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /现金/);
  });

  test('信用类：账单日 10、还款日 28', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '招行信用卡', type: 'credit', billingDay: 10, repaymentDay: 28 },
    });
    assert.equal(res.statusCode, 201);
    assert.equal(res.json().paymentMethod.billingDay, 10);
    creditId = res.json().paymentMethod.id;
  });

  test('信用类缺还款日 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '半截卡', type: 'credit', billingDay: 10 },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /必须同时提供/);
  });

  test('账单日越界 → 400，且是能看懂的提示', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '越界卡', type: 'credit', billingDay: 32, repaymentDay: 28 },
    });
    assert.equal(res.statusCode, 400);
    assert.match(res.json().error, /1–31/);
    assert.doesNotMatch(res.json().error, /CHECK constraint/, '不该把数据库约束原文抛给用户');
  });

  test('type 取值非法 → 400', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '怪类型', type: 'crypto' },
    });
    assert.equal(res.statusCode, 400);
  });

  test('同名 → 409', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/payment-methods',
      headers: auth(),
      payload: { name: '现金', type: 'cash' },
    });
    assert.equal(res.statusCode, 409);
  });

  test('可以改账单周期（银行调整账单日是真实会发生的）', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/payment-methods/${creditId}`,
      headers: auth(),
      payload: { billingDay: 25, repaymentDay: 10 },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().paymentMethod.billingDay, 25);
    assert.equal(res.json().paymentMethod.repaymentDay, 10);
  });

  test('可以停用（即使将来有历史记录也不该被挡住）', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/payment-methods/${cashId}`,
      headers: auth(),
      payload: { isEnabled: false },
    });
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().paymentMethod.isEnabled, false);
  });

  test('列表包含停用项（历史记录还要靠它显示）', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/payment-methods',
      headers: auth(),
    });
    assert.equal(res.statusCode, 200);

    const methods = res.json().paymentMethods as Array<Record<string, unknown>>;
    const cash = methods.find((item) => item['id'] === cashId);
    assert.ok(cash !== undefined, '停用的支付方式仍应出现在列表里');
    assert.equal(cash['isEnabled'], false);
  });
});
