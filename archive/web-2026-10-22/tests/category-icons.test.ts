import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { resolveCategoryIconName } from '../src/utils/icons.ts';

describe('分类图标（语义匹配与非重复兜底）', () => {
  test('显式设置的图标优先于推导', () => {
    assert.equal(resolveCategoryIconName({ name: '早餐', icon: 'utensils' }), 'utensils');
  });

  test('精确匹配默认分类', () => {
    assert.equal(resolveCategoryIconName({ name: '餐饮', icon: '' }), 'utensils');
    assert.equal(resolveCategoryIconName({ name: '外卖', icon: '' }), 'utensils-crossed');
    assert.equal(resolveCategoryIconName({ name: '房贷', icon: '' }), 'landmark');
  });

  test('常见中文词语义化自动匹配', () => {
    // 饮食类
    assert.equal(resolveCategoryIconName({ name: '猫粮', icon: '' }), 'cat');
    assert.equal(resolveCategoryIconName({ name: '狗粮罐头', icon: '' }), 'dog');
    assert.equal(resolveCategoryIconName({ name: '外卖订单', icon: '' }), 'utensils-crossed');
    assert.equal(resolveCategoryIconName({ name: '星巴克咖啡', icon: '' }), 'coffee');
    assert.equal(resolveCategoryIconName({ name: '买菜生鲜', icon: '' }), 'shopping-basket');
    assert.equal(resolveCategoryIconName({ name: '火锅聚餐', icon: '' }), 'soup');

    // 交通出行
    assert.equal(resolveCategoryIconName({ name: '打车费', icon: '' }), 'car-front');
    assert.equal(resolveCategoryIconName({ name: '汽车加油', icon: '' }), 'fuel');
    assert.equal(resolveCategoryIconName({ name: '高铁票', icon: '' }), 'train');
    assert.equal(resolveCategoryIconName({ name: '飞机票', icon: '' }), 'plane');
    assert.equal(resolveCategoryIconName({ name: '共享单车骑行', icon: '' }), 'bike');

    // 居家与水电
    assert.equal(resolveCategoryIconName({ name: '水费缴纳', icon: '' }), 'zap');
    assert.equal(resolveCategoryIconName({ name: '天然气充值', icon: '' }), 'flame');
    assert.equal(resolveCategoryIconName({ name: '房屋租金', icon: '' }), 'house');
    assert.equal(resolveCategoryIconName({ name: '宽带网络费', icon: '' }), 'wifi');

    // 医疗与健康
    assert.equal(resolveCategoryIconName({ name: '感冒药', icon: '' }), 'pill');
    assert.equal(resolveCategoryIconName({ name: '门诊挂号', icon: '' }), 'stethoscope');

    // 休闲与文娱
    assert.equal(resolveCategoryIconName({ name: 'Steam游戏', icon: '' }), 'gamepad-2');
    assert.equal(resolveCategoryIconName({ name: '看电影', icon: '' }), 'clapperboard');
    assert.equal(resolveCategoryIconName({ name: '演唱会门票', icon: '' }), 'mic');

    // 购物与穿着
    assert.equal(resolveCategoryIconName({ name: '买衣服', icon: '' }), 'shirt');
    assert.equal(resolveCategoryIconName({ name: '运动鞋', icon: '' }), 'footprints');
    assert.equal(resolveCategoryIconName({ name: '护肤品化妆品', icon: '' }), 'sparkles');
    assert.equal(resolveCategoryIconName({ name: '理发剪发', icon: '' }), 'scissors');
    assert.equal(resolveCategoryIconName({ name: '顺丰快递', icon: '' }), 'package');
  });

  test('未知分类不再统一匹配为单个标签图标，而是散列分散', () => {
    const unknown1 = resolveCategoryIconName({ name: '项目Alpha', icon: '' });
    const unknown2 = resolveCategoryIconName({ name: '自定义支出Beta', icon: '' });
    const unknown3 = resolveCategoryIconName({ name: '无规矩测试Gamma', icon: '' });

    // 它们应该有效，并且不应该所有未知名称都完全是同一个
    const set = new Set([unknown1, unknown2, unknown3]);
    assert.ok(set.size > 1, '未知名称应被散列分散到不同的中性图标上，而不是全部撞到同一个');
  });
});
