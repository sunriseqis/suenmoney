/**
 * 环图弧段计算的单元测试。
 *
 * 这一段的特点是**错了不会报错，只会画歪**：界面上永远是一片彩色，
 * 靠眼睛看不出一段弧的起点偏了 3%。所以这里断言的是几何关系，
 * 不是「看起来对不对」。
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { buildDonutArcs, DONUT_RADIUS } from '../src/utils/donut.ts';

const slice = (id: string, ratio: number) => ({ id, ratio, color: `var(--chart-${id})` });

describe('buildDonutArcs', () => {
  test('半径取到周长正好 100，dasharray 才能直接写百分比', () => {
    assert.ok(Math.abs(2 * Math.PI * DONUT_RADIUS - 100) < 0.01);
  });

  test('第一段从 12 点方向开始', () => {
    const arcs = buildDonutArcs([slice('1', 0.5)]);

    assert.equal(arcs[0]?.offset, 25);
    assert.equal(arcs[0]?.percent, 50);
  });

  test('每段的 offset = 25 −「前面各段之和」', () => {
    // 用演示数据的真实占比：餐饮 39% / 购物 22% / 交通 14%
    const arcs = buildDonutArcs([slice('1', 0.39), slice('2', 0.22), slice('3', 0.14)]);

    assert.deepEqual(
      arcs.map((arc) => arc.percent),
      [39, 22, 14],
    );
    assert.deepEqual(
      arcs.map((arc) => arc.offset),
      [25, -14, -36],
    );
  });

  test('✱ 浮点占比不把噪声写进 SVG 属性', () => {
    // 0.39 * 100 === 39.00000000000001；四舍五入后才是能直接用的 39 / -14
    const arcs = buildDonutArcs([slice('1', 0.39), slice('2', 0.22)]);

    assert.equal(arcs[1]?.offset, -14);
    assert.equal(String(arcs[1]?.percent), '22');
  });

  test('占比合计 100% 时，最后一段正好收回到起点', () => {
    const arcs = buildDonutArcs([slice('1', 0.6), slice('2', 0.4)]);
    const last = arcs[1];

    assert.equal((last?.offset ?? 0) - (last?.percent ?? 0), 25 - 100);
  });

  test('占比为 0 的段不占位置，但仍在列表里（图例与弧必须一一对应）', () => {
    const arcs = buildDonutArcs([slice('1', 0), slice('2', 0.5), slice('3', 0)]);

    assert.deepEqual(
      arcs.map((arc) => arc.offset),
      [25, 25, -25],
    );
  });

  test('✱ 负净额钳制为 0：退款大于支出时不把负数写进 stroke-dasharray', () => {
    // 服务端在某分类退款大于支出时会给出负 ratio；负 percent 会破坏 SVG 弧段语法
    const arcs = buildDonutArcs([slice('1', -0.3), slice('2', 0.6)]);

    assert.equal(arcs[0]?.percent, 0);
    assert.equal(arcs[0]?.offset, 25);
    assert.equal(arcs[1]?.percent, 60);
    assert.equal(arcs[1]?.offset, 25, '负段不占位置，后续弧的起点不被它推走');
  });

  test('空列表返回空数组', () => {
    assert.deepEqual(buildDonutArcs([]), []);
  });
});
