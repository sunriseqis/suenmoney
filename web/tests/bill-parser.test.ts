import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import type { Category, PaymentMethod } from '../src/api/types.ts';
import {
  decodeCsvBuffer,
  detectAndParseBill,
  detectBillSource,
  parseAlipayBill,
  parseCsvRows,
  parseWeChatBill,
  suggestCategory,
  suggestPaymentMethod,
} from '../src/utils/bill-parser.ts';

/** 把 JS 字符串按 UTF-8 编码成 ArrayBuffer（模拟用户上传的无 BOM UTF-8 文件） */
function utf8Buffer(text: string): ArrayBuffer {
  return new TextEncoder().encode(text).buffer as ArrayBuffer;
}

describe('decodeCsvBuffer 编码判定', () => {
  test('无 BOM 的合法 UTF-8 中文 CSV：不因缺少关键词而被误判成 GBK', () => {
    // 这份表里刻意不含「微信支付 / 支付宝 / 交易时间 / 收/支」四个词。
    // 旧实现用关键词启发式判断编码，找不到关键词就退回 GBK，于是整表乱码、
    // 金额解析不出来，而解析器一声不吭。
    const csv = `消费日,入账日,还款日,金额,分类,二级分类,支付方式,备注
2026-10-01,2026-10-01,2026-10-08,45.50,餐饮美食,堂食外卖,零钱,家庭晚餐
2026-10-02,2026-10-02,2026-10-08,128.00,居家缴费,电费,储蓄卡,物业代收
`;

    const text = decodeCsvBuffer(utf8Buffer(csv));

    assert.equal(text, csv, '合法 UTF-8 应原样解出，不应被改写成 GBK 乱码');
    assert.ok(!text.includes('\uFFFD'), '不应出现替换字符 U+FFFD');

    const rows = parseCsvRows(text);
    assert.deepEqual(rows[0], ['消费日', '入账日', '还款日', '金额', '分类', '二级分类', '支付方式', '备注']);
    assert.equal(rows[1]?.[3], '45.50');
    assert.equal(rows[1]?.[5], '堂食外卖');
    assert.equal(rows[2]?.[3], '128.00');

    // 端到端：中文与金额都要无损
    const res = detectAndParseBill(text);
    assert.equal(res.totalParsed, 2);
    assert.equal(res.items[0]!.amountCents, 4550);
    assert.equal(res.items[0]!.note, '家庭晚餐');
    assert.equal(res.items[1]!.amountCents, 12800);
    assert.equal(res.items[1]!.counterparty, '居家缴费 · 电费');
  });

  test('带 UTF-8 BOM 的文件仍按 UTF-8 正确解析', () => {
    const body = '消费日,金额,分类,二级分类\n2026-10-01,45.50,餐饮美食,堂食外卖\n';
    const buffer = utf8Buffer(`\uFEFF${body}`);
    // TextDecoder 默认吃掉 BOM，返回正文
    assert.equal(decodeCsvBuffer(buffer), body);
    assert.equal(parseCsvRows(decodeCsvBuffer(buffer))[0]?.[0], '消费日');
  });

  test('GBK 字节（非合法 UTF-8）仍能正确回退解码', () => {
    // 微信导出账单的标准编码就是 GBK。TextEncoder 造不出 GBK，这里直接用
    // 真实 GBK 字节常量（GB18030 编码，与 GBK 在这些常用汉字上完全一致）：
    // 「微信支付账单明细 / 交易时间,交易类型,交易对方,商品,收/支,金额(元) / …」
    const gbkBytes = new Uint8Array([
      0xce, 0xa2, 0xd0, 0xc5, 0xd6, 0xa7, 0xb8, 0xb6, 0xd5, 0xcb, 0xb5, 0xa5, 0xc3, 0xf7, 0xcf, 0xb8,
      0x0a, 0xbd, 0xbb, 0xd2, 0xd7, 0xca, 0xb1, 0xbc, 0xe4, 0x2c, 0xbd, 0xbb, 0xd2, 0xd7, 0xc0, 0xe0,
      0xd0, 0xcd, 0x2c, 0xbd, 0xbb, 0xd2, 0xd7, 0xb6, 0xd4, 0xb7, 0xbd, 0x2c, 0xc9, 0xcc, 0xc6, 0xb7,
      0x2c, 0xca, 0xd5, 0x2f, 0xd6, 0xa7, 0x2c, 0xbd, 0xf0, 0xb6, 0xee, 0x28, 0xd4, 0xaa, 0x29, 0x0a,
      0x32, 0x30, 0x32, 0x36, 0x2d, 0x30, 0x39, 0x2d, 0x31, 0x35, 0x20, 0x31, 0x32, 0x3a, 0x33, 0x30,
      0x3a, 0x30, 0x30, 0x2c, 0xc9, 0xcc, 0xbb, 0xa7, 0xcf, 0xfb, 0xb7, 0xd1, 0x2c, 0xc3, 0xc0, 0xcd,
      0xc5, 0xcd, 0xe2, 0xc2, 0xf4, 0x2c, 0xbb, 0xc6, 0xec, 0xcb, 0xbc, 0xa6, 0xc3, 0xd7, 0xb7, 0xb9,
      0x2c, 0xd6, 0xa7, 0xb3, 0xf6, 0x2c, 0x32, 0x38, 0x2e, 0x35, 0x30, 0x0a,
    ]);

    // 前提校验：这串字节确实不是合法 UTF-8，否则根本走不到 GBK 分支
    assert.throws(
      () => new TextDecoder('utf-8', { fatal: true }).decode(gbkBytes),
      'GBK 字节必须在严格 UTF-8 下解码失败',
    );

    const text = decodeCsvBuffer(gbkBytes.buffer as ArrayBuffer);

    assert.ok(!text.includes('\uFFFD'), 'GBK 回退后不应残留替换字符');
    assert.ok(text.startsWith('微信支付账单明细'), `实际解出：${text.slice(0, 20)}`);
    assert.ok(text.includes('黄焖鸡米饭'), `实际解出：${text}`);

    const res = detectAndParseBill(text);
    assert.equal(res.source, 'wechat');
    assert.equal(res.totalParsed, 1);
    assert.equal(res.items[0]!.amountCents, 2850);
    assert.equal(res.items[0]!.counterparty, '美团外卖');
  });
});

describe('parseCsvRows', () => {
  test('基础行列解析与空白行过滤', () => {
    const csv = 'col1,col2,col3\nval1,val2,val3\n\nval4,val5,val6';
    const rows = parseCsvRows(csv);
    assert.equal(rows.length, 3);
    assert.deepEqual(rows[0], ['col1', 'col2', 'col3']);
    assert.deepEqual(rows[2], ['val4', 'val5', 'val6']);
  });

  test('带引号包裹与包含逗号的单元格', () => {
    const csv = '"hello, world",plain,"escaped ""quote"""';
    const rows = parseCsvRows(csv);
    assert.equal(rows.length, 1);
    assert.deepEqual(rows[0], ['hello, world', 'plain', 'escaped "quote"']);
  });

  test('BOM 标记正确剥离', () => {
    const csv = '\uFEFFname,amount\ntest,100';
    const rows = parseCsvRows(csv);
    assert.deepEqual(rows[0], ['name', 'amount']);
  });
});

describe('detectBillSource', () => {
  test('识别微信账单', () => {
    assert.equal(detectBillSource('微信支付账单明细\n交易单号,金额'), 'wechat');
  });

  test('识别支付宝账单', () => {
    assert.equal(detectBillSource('支付宝交易记录明细查询\n商家订单号,金额'), 'alipay');
  });

  test('未知格式返回 unknown', () => {
    assert.equal(detectBillSource('some,random,csv,data'), 'unknown');
  });
});

describe('parseWeChatBill', () => {
  const sampleWeChat = `微信支付账单明细,,,,,,,,
微信昵称：[张三],,,,,,,,
起始时间：[2026-09-01 00:00:00] 终止时间：[2026-09-28 23:59:59],,,,,,,,
----------------------微信支付账单明细列表--------------------,,,,,,,,
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-15 12:30:00,商户消费,美团外卖,黄焖鸡米饭,支出,¥28.50,招商银行信用卡(1234),支付成功,10001,20001,/
2026-09-16 18:20:00,微信红包,李四,/,收入,¥88.00,零钱,已收钱,10002,20002,/
2026-09-17 08:45:00,扫二维码付款,全家便利店,三明治,支出,15.00,零钱,支付成功,10003,20003,早餐
`;

  test('解析微信账单提取交易与收支统计', () => {
    const res = parseWeChatBill(sampleWeChat);
    assert.equal(res.source, 'wechat');
    assert.equal(res.totalParsed, 3);
    assert.equal(res.expenseCount, 2);
    assert.equal(res.incomeCount, 1);
    assert.equal(res.otherCount, 0);

    const first = res.items[0]!;
    assert.equal(first.spendDate, '2026-09-15');
    assert.equal(first.amountCents, 2850);
    assert.equal(first.direction, 'expense');
    assert.equal(first.selected, true);
    assert.equal(first.counterparty, '美团外卖');
    assert.equal(first.note, '美团外卖 · 黄焖鸡米饭');
    assert.equal(first.paymentMethodRaw, '招商银行信用卡(1234)');

    const second = res.items[1]!;
    assert.equal(second.direction, 'income');
    assert.equal(second.selected, false);
    assert.equal(second.amountCents, 8800);

    const third = res.items[2]!;
    assert.equal(third.spendDate, '2026-09-17');
    assert.equal(third.amountCents, 1500);
    assert.equal(third.note, '全家便利店 · 三明治 · 早餐');
  });
});

describe('parseAlipayBill', () => {
  const sampleAlipay = `支付宝交易记录明细查询,,,,,,,,
账号：[test@example.com],,,,,,,,
------------------------------------------------------------------------------------,,,,,,,,
交易时间,交易分类,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注
2026-09-10 09:15:00,交通出行,滴滴出行,xxx,滴滴快车,支出,32.40,花呗,交易成功,2026091001,M001,
2026-09-11 14:00:00,日用百货,天猫超市,xxx,纸巾洗手液,支出,99.00,余额宝,交易成功,2026091102,M002,凑单
2026-09-12 20:00:00,转账,王五,xxx,转账还款,不计收支,500.00,招商银行借记卡,交易成功,2026091203,M003,
`;

  test('解析支付宝账单提取交易与收支统计', () => {
    const res = parseAlipayBill(sampleAlipay);
    assert.equal(res.source, 'alipay');
    assert.equal(res.totalParsed, 3);
    assert.equal(res.expenseCount, 2);
    assert.equal(res.incomeCount, 0);
    assert.equal(res.otherCount, 1);

    const first = res.items[0]!;
    assert.equal(first.spendDate, '2026-09-10');
    assert.equal(first.amountCents, 3240);
    assert.equal(first.direction, 'expense');
    assert.equal(first.counterparty, '滴滴出行');
    assert.equal(first.note, '滴滴出行 · 滴滴快车');

    const second = res.items[1]!;
    assert.equal(second.amountCents, 9900);
    assert.equal(second.note, '天猫超市 · 纸巾洗手液 · 凑单');

    const third = res.items[2]!;
    assert.equal(third.direction, 'other');
    assert.equal(third.selected, false);
  });
});

describe('parseSuenmoneyBill', () => {
  const sampleSuenmoney = `\uFEFF消费日,入账日,还款日,金额,分类,二级分类,支付方式,记录人,备注,来源,计划,期次
2026-09-25,2026-09-25,2026-09-25,45.50,餐饮美食,堂食外卖,微信支付,张三,家庭晚餐,手动记录,,
2026-09-26,2026-09-26,2026-09-26,12.00,交通出行,公交地铁,支付宝,张三,地铁通勤,手动记录,,
`;

  test('解析 suenmoney 导出的标准流水对账表', () => {
    const res = detectAndParseBill(sampleSuenmoney);
    assert.equal(res.source, 'suenmoney');
    assert.equal(res.totalParsed, 2);
    assert.equal(res.expenseCount, 2);

    const first = res.items[0]!;
    assert.equal(first.spendDate, '2026-09-25');
    assert.equal(first.amountCents, 4550);
    assert.equal(first.note, '家庭晚餐');
    assert.equal(first.counterparty, '餐饮美食 · 堂食外卖');
    assert.equal(first.paymentMethodRaw, '微信支付');

    const second = res.items[1]!;
    assert.equal(second.spendDate, '2026-09-26');
    assert.equal(second.amountCents, 1200);
    assert.equal(second.note, '地铁通勤');
  });

  test('✱ 支付方式包含匹配：通用名「信用卡 / 银行卡」命中库里完整名', () => {
    // 对账表常来自其他记账工具，写的是通用名；库里是「中信信用卡」「工商银行卡」。
    // 旧实现按名称完全相等匹配，全部落到「第一个可用支付方式」兜底，
    // 信用卡消费会被记成储蓄卡，账期归属（入账日/还款日）跟着算错。
    const methods: PaymentMethod[] = [
      { id: 'pm-bank', name: '工商银行卡', isEnabled: true, type: 'cash' },
      { id: 'pm-credit', name: '中信信用卡', isEnabled: true, type: 'credit' },
      { id: 'pm-cash', name: '现金', isEnabled: true, type: 'cash' },
    ] as unknown as PaymentMethod[];

    const csv = `\uFEFF消费日,入账日,还款日,金额,分类,二级分类,支付方式,记录人,备注,来源,计划,期次
2026-09-25,,,45.50,餐饮美食,堂食外卖,信用卡,,,
2026-09-26,,,12.00,交通出行,公交地铁,银行卡,,,
2026-09-27,,,3.00,餐饮美食,堂食外卖,现金,,,
`;

    const res = detectAndParseBill(csv, [], methods);
    assert.equal(res.totalParsed, 3);
    assert.equal(res.items[0]!.suggestedPaymentMethodId, 'pm-credit', '「信用卡」应包含匹配到「中信信用卡」');
    assert.equal(res.items[1]!.suggestedPaymentMethodId, 'pm-bank', '「银行卡」应包含匹配到「工商银行卡」');
    assert.equal(res.items[2]!.suggestedPaymentMethodId, 'pm-cash', '精确名仍然优先');
  });

  test('✱ 支付方式匹配不到时保持 null，不再兜底第一个可用方式', () => {
    // 对账表里的账户名是干净的、可据以创建的，匹配不到就必须保持 null：
    // 交给导入弹窗的「缺就建」按账户名创建，或让用户在预览里手选。
    // 旧实现会静默兜底到「第一个可用支付方式」，把「没有匹配」伪装成「匹配成功」——
    // 这笔会被挂到错误的支付方式上，账期归属（入账日/还款日）跟着算错且用户看不出；
    // 同时 suggestedPaymentMethodId 被填上，「缺就建」永远提议不到缺失的支付方式。
    const methods: PaymentMethod[] = [
      { id: 'pm-bank', name: '工商银行卡', isEnabled: true, type: 'cash' },
      { id: 'pm-cash', name: '现金', isEnabled: true, type: 'cash' },
    ] as unknown as PaymentMethod[];

    const csv = `\uFEFF消费日,入账日,还款日,金额,分类,二级分类,支付方式,记录人,备注,来源,计划,期次
2026-09-25,,,45.50,餐饮美食,堂食外卖,某银行信用卡,,,
`;

    const res = detectAndParseBill(csv, [], methods);
    assert.equal(res.totalParsed, 1);
    assert.equal(
      res.items[0]!.suggestedPaymentMethodId,
      null,
      '库里没有匹配的支付方式时应为 null，交由缺就建或用户手选',
    );
  });
});

describe('智能分类与渠道匹配', () => {
  const mockCategories: Category[] = [
    {
      id: 'cat-root-food',
      parentId: null,
      name: '餐饮美食',
      depth: 1,
      icon: 'utensils',
      color: '1',
      sortOrder: 1,
      isEnabled: true,
      expenseCount: 10,
      children: [],
    },
    {
      id: 'cat-child-takeout',
      parentId: 'cat-root-food',
      name: '堂食外卖',
      depth: 2,
      icon: 'utensils',
      color: '1',
      sortOrder: 1,
      isEnabled: true,
      expenseCount: 5,
      children: [],
    },
    {
      id: 'cat-root-trans',
      parentId: null,
      name: '交通出行',
      depth: 1,
      icon: 'bus',
      color: '2',
      sortOrder: 2,
      isEnabled: true,
      expenseCount: 4,
      children: [],
    },
    {
      id: 'cat-child-didi',
      parentId: 'cat-root-trans',
      name: '出行打车',
      depth: 2,
      icon: 'bus',
      color: '2',
      sortOrder: 1,
      isEnabled: true,
      expenseCount: 2,
      children: [],
    },
  ];

  const mockPaymentMethods: PaymentMethod[] = [
    {
      id: 'pm-wechat',
      name: '微信支付',
      icon: 'wechat',
      type: 'cash',
      billingDay: null,
      repaymentDay: null,
      sortOrder: 1,
      isEnabled: true,
      expenseCount: 10,
    },
    {
      id: 'pm-alipay',
      name: '支付宝',
      icon: 'alipay',
      type: 'cash',
      billingDay: null,
      repaymentDay: null,
      sortOrder: 2,
      isEnabled: true,
      expenseCount: 10,
    },
    {
      id: 'pm-credit',
      name: '招商银行信用卡',
      icon: 'credit',
      type: 'credit',
      billingDay: 10,
      repaymentDay: 28,
      sortOrder: 3,
      isEnabled: true,
      expenseCount: 5,
    },
  ];

  test('关键词自动命中二级分类', () => {
    assert.equal(suggestCategory('美团外卖 肯德基宅急送', mockCategories), 'cat-child-takeout');
    assert.equal(suggestCategory('滴滴快车 行程支付', mockCategories), 'cat-child-didi');
  });

  test('渠道智能匹配对应支付方式', () => {
    assert.equal(
      suggestPaymentMethod('招商银行信用卡(1234)', 'wechat', mockPaymentMethods),
      'pm-credit',
    );
    assert.equal(suggestPaymentMethod('零钱通', 'wechat', mockPaymentMethods), 'pm-wechat');
    assert.equal(suggestPaymentMethod('花呗', 'alipay', mockPaymentMethods), 'pm-alipay');
  });

  test('detectAndParseBill 端到端解析并附带推荐', () => {
    const csv = `微信支付账单明细,,,,,,,,
交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
2026-09-20 12:00:00,商户消费,美团外卖,外卖午餐,支出,35.00,零钱,支付成功,1,2,/
`;
    const result = detectAndParseBill(csv, mockCategories, mockPaymentMethods);
    assert.equal(result.totalParsed, 1);
    const item = result.items[0]!;
    assert.equal(item.suggestedCategoryId, 'cat-child-takeout');
    assert.equal(item.suggestedPaymentMethodId, 'pm-wechat');
  });
});
