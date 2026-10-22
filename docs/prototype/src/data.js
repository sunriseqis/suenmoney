/* ==========================================================
   同账 · 数据层（金额一律整数分 / 只记支出 / 退款为负数）
   ========================================================== */

const USERS = [
  { id: 'u1', name: '阿禾', initial: '禾', color: '#8B5CF6', role: '管理员', active: true },
  { id: 'u2', name: '小满', initial: '满', color: '#F472B6', role: '成员', active: true }
];

/* 分类颜色 16 槽，按索引存储（换色零迁移） */
const CAT_COLORS = [
  '#8B5CF6', '#F472B6', '#FBBF24', '#34D399',
  '#38BDF8', '#FB7185', '#A78BFA', '#22D3EE',
  '#F59E0B', '#10B981', '#EC4899', '#6366F1',
  '#84CC16', '#F97316', '#14B8A6', '#64748B'
];

const CAT_TREE = [
  ['餐饮', 'fork', ['早餐', '午餐', '晚餐', '外卖', '咖啡饮品', '零食水果']],
  ['交通', 'car', ['地铁公交', '打车', '加油', '停车', '火车机票']],
  ['居住', 'home', ['房租', '物业', '水电燃气', '家居维修', '家政保洁']],
  ['购物', 'bag', ['服饰', '数码', '美妆', '家具']],
  ['日用', 'basket', ['超市', '清洁用品', '厨房用品']],
  ['医疗', 'heart', ['门诊', '药品', '体检', '牙科']],
  ['教育', 'book', ['课程', '书籍', '培训', '考试报名']],
  ['娱乐', 'game', ['电影演出', '旅行', '会员订阅', '运动']],
  ['通讯', 'phone', ['手机费', '宽带']],
  ['人情', 'gift', ['红包', '礼物', '聚餐请客']],
  ['育儿', 'baby', ['奶粉尿布', '玩具', '托育']],
  ['其他', 'dots', ['杂项', '手续费', '保险']]
];

const BASE_CATS = (() => {
  const out = [];
  CAT_TREE.forEach(([name, icon, kids], i) => {
    const id = 'c' + String(i + 1).padStart(2, '0');
    out.push({ id, name, icon, color: i, parent: null, active: true });
    kids.forEach((kname, j) => {
      out.push({ id: id + String(j + 1).padStart(2, '0'), name: kname, icon, color: i, parent: id, active: true });
    });
  });
  return out;
})();

let CATS = BASE_CATS.map((c) => ({ ...c }));
let CAT_BY_ID = Object.fromEntries(CATS.map((c) => [c.id, c]));
let ROOT_CATS = CATS.filter((c) => !c.parent);
const kidsOf = (id) => CATS.filter((c) => c.parent === id);
const catColor = (id) => {
  const c = CAT_BY_ID[id];
  return CAT_COLORS[c ? c.color : 15];
};
const catName = (id) => (CAT_BY_ID[id] ? CAT_BY_ID[id].name : '未分类');
const catPath = (id) => {
  const c = CAT_BY_ID[id];
  if (!c) return '未分类';
  return c.parent && CAT_BY_ID[c.parent] ? CAT_BY_ID[c.parent].name + ' / ' + c.name : c.name;
};

/* 设置页对分类的增改会就地重建注册表，二級继承父级图标与颜色 */
function applyCatOverrides(overrides) {
  const merged = BASE_CATS.map((c) => (overrides[c.id] ? { ...c, ...overrides[c.id] } : { ...c }));
  Object.keys(overrides).forEach((id) => {
    if (!BASE_CATS.some((c) => c.id === id)) merged.push({ ...overrides[id] });
  });
  CATS.length = 0;
  merged.forEach((c) => CATS.push(c));
  CAT_BY_ID = Object.fromEntries(CATS.map((c) => [c.id, c]));
  CATS.forEach((c) => {
    if (c.parent && CAT_BY_ID[c.parent]) {
      c.icon = CAT_BY_ID[c.parent].icon;
      c.color = CAT_BY_ID[c.parent].color;
    }
  });
  ROOT_CATS.length = 0;
  CATS.filter((c) => !c.parent).forEach((c) => ROOT_CATS.push(c));
  return CATS;
}

const PAYS = [
  { id: 'p1', name: '微信支付', icon: 'wallet', type: '余额', billing: false, active: true },
  { id: 'p2', name: '支付宝', icon: 'wallet', type: '余额', billing: false, active: true },
  { id: 'p3', name: '招商信用卡', icon: 'card', type: '信用卡', billing: true, billDay: 21, dueDay: 8, grace: 18, active: true },
  { id: 'p4', name: '花呗', icon: 'card', type: '信用支付', billing: true, billDay: 1, dueDay: 10, grace: 8, active: true },
  { id: 'p5', name: '现金', icon: 'coins', type: '现金', billing: false, active: true },
  { id: 'p6', name: '家庭储蓄卡', icon: 'bank', type: '借记卡', billing: false, active: true }
];

const PAY_BY_ID = Object.fromEntries(PAYS.map((p) => [p.id, p]));

/* ---------------- 日期工具 ---------------- */
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
const parseYmd = (s) => new Date(Number(s.slice(0, 4)), Number(s.slice(5, 7)) - 1, Number(s.slice(8, 10)));
const TODAY = new Date();
const TODAY_KEY = ymd(TODAY);
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const addMonths = (d, n) => new Date(d.getFullYear(), d.getMonth() + n, d.getDate());
const startOfMonth = (d) => new Date(d.getFullYear(), d.getMonth(), 1);
const endOfMonth = (d) => new Date(d.getFullYear(), d.getMonth() + 1, 0);
const sameMonth = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth();
const monthLabel = (d) => d.getFullYear() + ' 年 ' + (d.getMonth() + 1) + ' 月';
const monthShort = (d) => (d.getMonth() + 1) + ' 月';
const WEEK = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

const money = (cents) => {
  const v = Math.abs(cents) / 100;
  return '¥' + v.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
};
const moneyPlain = (cents) => (cents / 100).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const signedMoney = (cents) => (cents < 0 ? '-' : '') + money(cents);
const wan = (cents) => {
  const v = cents / 100;
  if (Math.abs(v) >= 10000) return (v / 10000).toFixed(1) + ' 万';
  return v.toLocaleString('zh-CN', { maximumFractionDigits: 0 });
};

/* 日期简化显示：今日星期一 / 昨日星期日 / 26日星期六 */
const ledgerDate = (d) => {
  const base = parseYmd(d);
  const diff = Math.round((startOfMonth(TODAY) - startOfMonth(base)) / 86400000);
  const dayDiff = Math.round((parseYmd(TODAY_KEY) - base) / 86400000);
  if (dayDiff === 0) return '今日' + WEEK[base.getDay()];
  if (dayDiff === 1) return '昨日' + WEEK[base.getDay()];
  return base.getDate() + '日' + WEEK[base.getDay()];
};

/* 账期：信用卡看还款日（免息期 / 固定还款日） */
const repaymentOf = (payId, spendDate) => {
  const pay = PAY_BY_ID[payId];
  if (!pay || !pay.billing) return spendDate;
  let d = addDays(parseYmd(spendDate), pay.grace);
  const target = new Date(d.getFullYear(), d.getMonth(), pay.dueDay);
  if (target < d) d = new Date(d.getFullYear(), d.getMonth() + 1, pay.dueDay);
  else d = target;
  return ymd(d);
};

const creditPeriodLabel = (payId) => {
  const pay = PAY_BY_ID[payId];
  if (!pay || !pay.billing) return '即时入账';
  return '每月 ' + pay.dueDay + ' 日还款 · 账单日 ' + pay.billDay + ' 日';
};

/* ---------------- 生成流水 ---------------- */
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const RANGE = {
  c01: [1500, 12000], c02: [300, 8000], c03: [5000, 260000], c04: [3000, 68000],
  c05: [900, 18000], c06: [2000, 42000], c07: [5000, 128000], c08: [2000, 52000],
  c09: [3000, 12000], c10: [5000, 88000], c11: [2800, 46000], c12: [500, 12000]
};

const NOTES = {
  c01: ['楼下小面', '公司食堂', '和满满一起吃', '加班夜宵', '周末早午餐'],
  c02: ['通勤地铁', '晚高峰打车', '加满一箱', '商场停车', '回老家高铁'],
  c03: ['本月房租', '物业费', '电费+燃气', '换水龙头', '周末保洁'],
  c04: ['换季衣物', '键盘鼠标', '面霜补货', '书桌', '手机壳'],
  c05: ['超市采购', '洗衣液', '厨房收纳', '抽纸囤货'],
  c06: ['感冒门诊', '常备药', '年度体检', '洗牙'],
  c07: ['线上课程', '专业书', '英语培训', '资格考试'],
  c08: ['周末电影', '露营装备', '视频会员', '羽毛球场地'],
  c09: ['手机套餐', '家庭宽带'],
  c10: ['同事婚礼红包', '妈妈生日礼物', '朋友聚餐', '过年红包'],
  c11: ['奶粉尿布', '积木玩具', '托育费'],
  c12: ['杂项支出', '跨行手续费', '家庭保险']
};

const CAT_WEIGHTS = [
  ['c01', 26], ['c02', 13], ['c03', 9], ['c04', 10], ['c05', 8], ['c06', 4],
  ['c07', 6], ['c08', 7], ['c09', 3], ['c10', 4], ['c11', 4], ['c12', 3]
];
const WEIGHTED = CAT_WEIGHTS.reduce((acc, [id, w]) => {
  for (let i = 0; i < w; i++) acc.push(id);
  return acc;
}, []);

const PAY_WEIGHTS = ['p1', 'p1', 'p1', 'p1', 'p1', 'p1', 'p2', 'p2', 'p2', 'p2', 'p3', 'p3', 'p4', 'p5', 'p6'];

const SEED_EXPENSES = (() => {
  const rnd = mulberry32(20250618);
  const out = [];
  let seq = 0;
  for (let m = -13; m <= 0; m++) {
    const cursor = new Date(TODAY.getFullYear(), TODAY.getMonth() + m, 1);
    const y = cursor.getFullYear();
    const mo = cursor.getMonth();
    const days = endOfMonth(cursor).getDate();
    const count = m === 0 ? Math.min(26, TODAY.getDate() + 12) : 26 + Math.floor(rnd() * 12);

    // 每月房租（居住 / 支付宝）
    if (m !== 0 || TODAY.getDate() >= 3) {
      const rentDay = new Date(y, mo, 3);
      if (rentDay <= TODAY) {
        out.push({
          id: 'e' + (++seq), amount_cents: 420000, spend_date: ymd(rentDay),
          cat_id: 'c0301', note: '本月房租', pay_id: 'p2', owner_id: 'u1',
          repayment_date: ymd(rentDay), installment: null, source: 'seed'
        });
      }
    }

    for (let i = 0; i < count; i++) {
      const day = 1 + Math.floor(rnd() * (m === 0 ? TODAY.getDate() : days));
      const date = new Date(y, mo, day);
      if (date > TODAY) continue;
      const root = WEIGHTED[Math.floor(rnd() * WEIGHTED.length)];
      const kids = kidsOf(root);
      const cat = kids[Math.floor(rnd() * kids.length)] || CAT_BY_ID[root];
      const payId = PAY_WEIGHTS[Math.floor(rnd() * PAY_WEIGHTS.length)];
      const [lo, hi] = RANGE[root];
      let amount = lo + Math.floor(rnd() * (hi - lo));
      amount = Math.round(amount / 100) * 100;
      const refund = rnd() < 0.018 && !(payId === 'p3' || payId === 'p4');
      const notes = NOTES[root];
      const note = notes[Math.floor(rnd() * notes.length)];
      out.push({
        id: 'e' + (++seq),
        amount_cents: refund ? -amount : amount,
        spend_date: ymd(date),
        cat_id: cat.id,
        note: refund ? note + ' · 退款' : note,
        pay_id: payId,
        owner_id: rnd() < 0.58 ? 'u1' : 'u2',
        repayment_date: repaymentOf(payId, ymd(date)),
        installment: null,
        source: 'seed'
      });
    }
  }

  // 一笔信用卡装修分期（12 期）
  const inst = new Date(TODAY.getFullYear(), TODAY.getMonth() - 3, 12);
  out.push({
    id: 'e-inst', amount_cents: 1440000, spend_date: ymd(inst),
    cat_id: 'c0304', note: '装修尾款 · 12 期免息', pay_id: 'p3', owner_id: 'u1',
    repayment_date: repaymentOf('p3', ymd(inst)),
    installment: { periods: 12, paid: 3, per_cents: 120000 }, source: 'seed'
  });

  return out.sort((a, b) => (a.spend_date < b.spend_date ? 1 : -1));
})();

/* ---------------- 计划与待办 ---------------- */
const SEED_PLANS = [
  {
    id: 'pl1', name: '房贷', kind: '房贷', amount_cents: 850000, dueDay: 5,
    total: 360, paid: 132, auto: true, active: true, pay_id: 'p6', owner_id: 'u1'
  },
  {
    id: 'pl2', name: '车贷', kind: '车贷', amount_cents: 238000, dueDay: 15,
    total: 36, paid: 18, auto: true, active: true, pay_id: 'p6', owner_id: 'u2'
  },
  {
    id: 'pl3', name: '装修分期', kind: '分期', amount_cents: 120000, dueDay: 8,
    total: 12, paid: 3, auto: false, active: true, pay_id: 'p3', owner_id: 'u1'
  }
];

const todoDate = (plan, offsetMonths) => {
  const base = new Date(TODAY.getFullYear(), TODAY.getMonth() + offsetMonths, plan.dueDay);
  return ymd(base);
};

const SEED_TODOS = (() => {
  const [pl1, pl2, pl3] = SEED_PLANS;
  return [
    { id: 't1', plan_id: 'pl1', title: '房贷 · ' + (pl1.paid + 1) + '/' + pl1.total + ' 期', amount_cents: pl1.amount_cents, due_date: todoDate(pl1, -1), state: 'pending', kind: 'auto' },
    { id: 't2', plan_id: 'pl2', title: '车贷 · ' + (pl2.paid + 1) + '/' + pl2.total + ' 期', amount_cents: pl2.amount_cents, due_date: todoDate(pl2, 0), state: 'done', kind: 'auto' },
    { id: 't3', plan_id: 'pl3', title: '装修分期 · ' + (pl3.paid + 1) + '/' + pl3.total + ' 期', amount_cents: pl3.amount_cents, due_date: todoDate(pl3, 0), state: 'pending', kind: 'manual' },
    { id: 't4', plan_id: 'pl1', title: '房贷 · ' + (pl1.paid + 2) + '/' + pl1.total + ' 期', amount_cents: pl1.amount_cents, due_date: todoDate(pl1, 1), state: 'pending', kind: 'auto' },
    { id: 't5', plan_id: 'pl2', title: '车贷 · ' + (pl2.paid + 2) + '/' + pl2.total + ' 期', amount_cents: pl2.amount_cents, due_date: todoDate(pl2, 1), state: 'pending', kind: 'auto' },
    { id: 't6', plan_id: 'pl3', title: '装修分期 · ' + pl3.paid + '/' + pl3.total + ' 期', amount_cents: pl3.amount_cents, due_date: todoDate(pl3, -1), state: 'skipped', kind: 'manual' }
  ];
})();

/* ---------------- 聚合 ---------------- */
const sumCents = (list) => list.reduce((a, x) => a + x.amount_cents, 0);

const inRange = (list, start, end) => {
  const s = ymd(start);
  const e = ymd(end);
  return list.filter((x) => x.spend_date >= s && x.spend_date <= e);
};

const periodOf = (mode, anchor) => {
  if (mode === 'all') return { start: new Date(2018, 0, 1), end: endOfMonth(TODAY) };
  if (mode === 'year') return { start: new Date(anchor.getFullYear(), 0, 1), end: new Date(anchor.getFullYear(), 11, 31) };
  return { start: startOfMonth(anchor), end: endOfMonth(anchor) };
};

const shiftPeriod = (mode, anchor, dir) => {
  if (mode === 'all') return anchor;
  if (mode === 'year') return new Date(anchor.getFullYear() + dir, 0, 1);
  return new Date(anchor.getFullYear(), anchor.getMonth() + dir, 1);
};

const periodLabel = (mode, anchor) => {
  if (mode === 'all') return '全部记录';
  if (mode === 'year') return anchor.getFullYear() + ' 年';
  return monthLabel(anchor);
};

const prevPeriodExpenses = (list, mode, anchor) => {
  const prev = shiftPeriod(mode, anchor, -1);
  return inRange(list, periodOf(mode, prev).start, periodOf(mode, prev).end);
};

const rootTotals = (list) => {
  const map = {};
  list.forEach((x) => {
    const cat = CAT_BY_ID[x.cat_id];
    if (!cat) return;
    const root = cat.parent || cat.id;
    if (!map[root]) map[root] = { cat: CAT_BY_ID[root], cents: 0, count: 0, kids: {} };
    map[root].cents += x.amount_cents;
    map[root].count += 1;
    const kid = cat.parent ? cat.id : root;
    map[root].kids[kid] = (map[root].kids[kid] || 0) + x.amount_cents;
  });
  return Object.values(map).sort((a, b) => b.cents - a.cents);
};

const byMonth = (list, months) => {
  const out = [];
  for (let i = months - 1; i >= 0; i--) {
    const d = new Date(TODAY.getFullYear(), TODAY.getMonth() - i, 1);
    const rows = list.filter((x) => sameMonth(parseYmd(x.spend_date), d));
    out.push({ date: d, cents: sumCents(rows), count: rows.length });
  }
  return out;
};

const weekdayDist = (list) => {
  const arr = [0, 0, 0, 0, 0, 0, 0];
  list.forEach((x) => { arr[parseYmd(x.spend_date).getDay()] += x.amount_cents; });
  return arr;
};

const payTotals = (list) => {
  const map = {};
  list.forEach((x) => { map[x.pay_id] = (map[x.pay_id] || 0) + x.amount_cents; });
  return Object.keys(map).map((id) => ({ pay: PAY_BY_ID[id], cents: map[id] })).sort((a, b) => b.cents - a.cents);
};

const ownerTotals = (list) => {
  const map = {};
  list.forEach((x) => { map[x.owner_id] = (map[x.owner_id] || 0) + x.amount_cents; });
  return USERS.map((u) => ({ user: u, cents: map[u.id] || 0 }));
};

const dueRows = (list, monthDate) => {
  return list
    .filter((x) => x.repayment_date && sameMonth(parseYmd(x.repayment_date), monthDate))
    .filter((x) => PAY_BY_ID[x.pay_id] && PAY_BY_ID[x.pay_id].billing);
};

const STATIC_DATA = {
  serverSlots: [
    { id: 's1', url: 'https://suen.local:5310', state: '在线', ping: 12, primary: true },
    { id: 's2', url: 'http://192.168.1.8:5310', state: '备用', ping: 34, primary: false },
    { id: 's3', url: 'https://nas.fnos.lan:5310', state: '未探活', ping: null, primary: false }
  ],
  snapshots: [
    { id: 'sn1', name: '自动快照', at: '今日 03:00', size: '4.2 MB' },
    { id: 'sn2', name: '导入微信账单前', at: '6 月 12 日 21:04', size: '4.1 MB' },
    { id: 'sn3', name: '手动快照', at: '6 月 1 日 09:12', size: '3.9 MB' }
  ],
  sessions: [
    { id: 'd1', name: 'MacBook Pro · Safari', at: '当前设备', current: true },
    { id: 'd2', name: 'iPhone 15 · 同账 App', at: '2 小时前', current: false },
    { id: 'd3', name: 'iPad · Safari', at: '3 天前', current: false }
  ]
};

Object.assign(window, {
  USERS, CAT_COLORS, CATS, CAT_BY_ID, ROOT_CATS, kidsOf, catColor, catName, catPath,
  applyCatOverrides, BASE_CATS,
  PAYS, PAY_BY_ID, SEED_EXPENSES, SEED_PLANS, SEED_TODOS, STATIC_DATA,
  TODAY, TODAY_KEY, ymd, parseYmd, addDays, addMonths, startOfMonth, endOfMonth,
  sameMonth, monthLabel, monthShort, WEEK, pad, money, moneyPlain, signedMoney, wan,
  ledgerDate, repaymentOf, creditPeriodLabel, sumCents, inRange, periodOf,
  shiftPeriod, periodLabel, prevPeriodExpenses, rootTotals, byMonth, weekdayDist,
  payTotals, ownerTotals, dueRows
});
