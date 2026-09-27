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
