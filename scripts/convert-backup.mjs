#!/usr/bin/env node
/**
 * 把一份 SuenMoney 备份转换成「能在另一个 2.0 实例上导入」的备份。
 *
 * 为什么需要它
 * ------------
 * 备份里每条计划/流水/期次都用 **ULID 引用成员**（`owner_id` / `confirmed_by`）。
 * 而 `mergePackage` 的 `requireMembers` 会逐条校验这些 id 在目标库里是否存在，
 * 不存在就整包拒绝 —— 因为备份**不含口令哈希**，导入不会替你建账号
 *（否则会造出一批没有可用口令、也没人能登录的账号）。
 *
 * 结果就是：A 实例导出的备份，拿到 B 实例导入必然失败，哪怕两边是同一对账号
 *（换库/重装/换 NAS 之后 ULID 一定会变）。
 *
 * 这个脚本做的事：把旧 id 替换成目标实例里真实存在的 id，其余数据原样保留。
 *
 * 用法
 * ----
 *   # 1) 先看清备份里有谁
 *   node scripts/convert-backup.mjs --input bk.json --list
 *
 *   # 2) 再按「旧=新」做映射（可重复多次，一个成员一条）
 *   node scripts/convert-backup.mjs --input bk.json --output bk-2.0.json \
 *     --map 01M3TWW6B2XBNHBZZPCD20AW2P=01M5E9YA2CJPQGQ59V4ZCGVSHE \
 *     --map 01M3V08HRYW8X2Q8WFYJR15KRK=01M5EV4896226TSXMQ5ZRQV785
 *
 *   # 3) 也可以把所有成员合并到同一个账号（单人使用、或懒得对齐多个账号时）
 *   node scripts/convert-backup.mjs --input bk.json --output bk-2.0.json \
 *     --collapse 01M5E9YA2CJPQGQ59V4ZCGVSHE
 *
 * 目标实例的成员 id 怎么拿：
 *   curl -s http://<地址>:<端口>/api/users -H "Authorization: Bearer <token>"
 *   或在 Web 端「家庭与账号」页查看。
 *
 * 转换后仍然保持 `format: 'suenmoney-backup'`、`version: 1`，
 * 和当前服务端导出的一模一样（`PACKAGE_VERSION` 目前仍是 1）。
 */

import { readFileSync, writeFileSync } from 'node:fs';

const COLUMNS = {
  members: ['id', 'username', 'display_name', 'role', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
  categories: ['id', 'parent_id', 'name', 'depth', 'icon', 'color', 'sort_order', 'is_enabled', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
  // 2.0 里 payment_methods 多了 icon 列（迁移 004）；老备份没有这一列，补空串。
  // 导入端只按 PAYMENT_COLUMNS 写，不读 icon，所以补它不影响导入 —— 但补上之后
  // 这份文件用任何工具对比都更接近现网导出的样子。
  paymentMethods: ['id', 'name', 'type', 'icon', 'billing_day', 'repayment_day', 'is_enabled', 'sort_order', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
  plans: ['id', 'owner_id', 'name', 'category_id', 'payment_method_id', 'amount_cents', 'total_amount_cents', 'purchase_date', 'first_due_date', 'remind_days_before', 'auto_post', 'source', 'state', 'note', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
  planTodos: ['id', 'plan_id', 'period_seq', 'amount_cents', 'posting_date', 'repayment_date', 'remind_date', 'status', 'posted_date', 'confirmed_by', 'confirmed_at', 'expense_id', 'hold_auto_post', 'ack_at', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
  expenses: ['id', 'owner_id', 'amount_cents', 'category_id', 'payment_method_id', 'spend_date', 'posting_date', 'repayment_date', 'note', 'source', 'plan_id', 'plan_period_seq', 'created_at', 'updated_at', 'deleted_at', 'rev', 'device_id'],
};

/** 备份里所有「指向成员」的字段 */
const MEMBER_REFS = [
  ['plans', 'owner_id'],
  ['expenses', 'owner_id'],
  ['planTodos', 'confirmed_by'],
];

function fail(msg) {
  console.error(`\n✖ ${msg}\n`);
  process.exit(1);
}

function parseArgs() {
  const argv = process.argv.slice(2);
  const out = { input: '', output: '', maps: [], collapse: '', list: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--input' && argv[i + 1]) out.input = argv[++i];
    else if (a === '--output' && argv[i + 1]) out.output = argv[++i];
    else if (a === '--map' && argv[i + 1]) out.maps.push(argv[++i]);
    else if (a === '--collapse' && argv[i + 1]) out.collapse = argv[++i];
    else if (a === '--list') out.list = true;
    else if (a === '--help' || a === '-h') out.list = true;
  }
  if (!out.input) fail('缺少 --input <备份文件>');
  return out;
}

const { input, output, maps, collapse, list } = parseArgs();

let pkg;
try {
  pkg = JSON.parse(readFileSync(input, 'utf8'));
} catch (err) {
  fail(`读不了备份文件：${err.message}`);
}

if (pkg.format !== 'suenmoney-backup') {
  fail(`这不是备份文件（format='${pkg.format}'）。导出包（suenmoney-export）不能用来恢复。`);
}
if (!pkg.data || typeof pkg.data !== 'object') fail('备份缺少 data 字段');

const data = pkg.data;
const members = Array.isArray(data.members) ? data.members : [];

// ── --list：只打印，不改文件 ───────────────────────────────────────────────
if (list) {
  console.log(`\n备份文件：${input}`);
  console.log(`导出时间：${pkg.generatedAt}　范围：${pkg.scope?.kind} ${pkg.scope?.period || ''}`);
  console.log('\n成员（旧 id → 需要在目标实例里找到对应的新 id）：');
  for (const m of members) {
    console.log(`  ${m.id}  ${String(m.username).padEnd(12)} ${String(m.display_name).padEnd(10)} ${m.role}`);
  }
  console.log('\n数据量：');
  for (const [k, v] of Object.entries(pkg.counts ?? {})) console.log(`  ${k.padEnd(18)} ${v}`);
  console.log('\n下一步：');
  console.log('  node scripts/convert-backup.mjs --input <备份> --output <输出> \\');
  for (const m of members) {
    console.log(`    --map ${m.id}=<目标实例里对应成员的 id> \\`);
  }
  console.log('');
  process.exit(0);
}

// ── 构建映射表 oldId → newId ───────────────────────────────────────────────
const mapping = new Map();
if (collapse) {
  for (const m of members) mapping.set(String(m.id), collapse);
  console.log(`· 合并模式：${members.length} 个成员全部映射到 ${collapse}`);
} else {
  for (const pair of maps) {
    const eq = pair.indexOf('=');
    if (eq <= 0) fail(`--map 格式应为 OLD=NEW，收到 '${pair}'`);
    mapping.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
  }
}

if (mapping.size === 0) {
  fail('没有给任何 --map 或 --collapse。先用 --list 看清备份里有谁。\n'
    + '  （导入端会校验成员引用，不重映射的话在另一个实例上必然被拒。）');
}

// 备份里出现、但没给映射的成员 —— 不直接失败，先列出来，让引用校验去兜底
const unmapped = members.filter((m) => !mapping.has(String(m.id)));
if (unmapped.length > 0) {
  console.log('· 注意：以下成员没有映射，若数据里引用了它们，导入仍会被拒：');
  for (const m of unmapped) console.log(`    ${m.id}  ${m.username}（${m.display_name}）`);
}

// 新 id 必须是合法的 ULID 形状（26 位 Crockford Base32），避免手抄错
const ULID_RE = /^[0-9A-HJKMNP-TV-Z]{26}$/i;
for (const [oldId, newId] of mapping) {
  if (!ULID_RE.test(newId)) fail(`目标 id 不像 ULID：'${newId}'（应为 26 位大写字母数字）`);
  if (oldId === newId) console.log(`· 提醒：${oldId} 的新旧 id 相同，等于没改`);
}

// ── 改写成员表 ─────────────────────────────────────────────────────────────
// 保留被映射成员的「用户名/昵称/角色」，只换 id；被合并掉的成员从 members 里剔除。
const seen = new Set();
const nextMembers = [];
for (const m of members) {
  const oldId = String(m.id);
  const newId = mapping.get(oldId) ?? oldId;
  if (seen.has(newId)) continue;
  seen.add(newId);
  const copy = { ...m, id: newId };
  // 合并模式下，第一个成员的名字/角色保留下来；后续被合并的用第一个的
  nextMembers.push(copy);
}

// ── 改写引用 ───────────────────────────────────────────────────────────────
const stats = { members: nextMembers.length, replaced: 0, dangling: [] };

for (const [tableKey, field] of MEMBER_REFS) {
  const rows = data[tableKey];
  if (!Array.isArray(rows)) continue;
  for (const row of rows) {
    const v = row[field];
    if (typeof v !== 'string' || v === '') continue;
    const mapped = mapping.get(v);
    if (mapped !== undefined) {
      row[field] = mapped;
      stats.replaced += 1;
    } else if (!mapping.has(v) && !members.some((m) => String(m.id) === v)) {
      stats.dangling.push(`${tableKey}.${field} = ${v}`);
    }
  }
}

// 转换后重新体检：所有引用必须能解析到 members 里的某个 id
const memberIds = new Set(nextMembers.map((m) => String(m.id)));
for (const [tableKey, field] of MEMBER_REFS) {
  const rows = data[tableKey];
  if (!Array.isArray(rows)) continue;
  for (const row of rows) {
    const v = row[field];
    if (typeof v !== 'string' || v === '') continue;
    if (!memberIds.has(v)) {
      fail(`转换后仍有悬空引用：${tableKey}.${field} = ${v}\n`
        + '　这行数据指向的成员不在本次映射里，导入会被 requireMembers 拒绝。');
    }
  }
}

// ── 补齐 2.0 新增列 ────────────────────────────────────────────────────────
// payment_methods.icon（迁移 004）：老备份没有，补空串（= 由前端按名称推导图标）
let filled = 0;
if (Array.isArray(data.paymentMethods)) {
  for (const row of data.paymentMethods) {
    if (row.icon === undefined) {
      row.icon = '';
      filled += 1;
    }
  }
}

// ── 按当前服务端的列顺序重排（人眼 diff 更友好；导入本身不依赖顺序）───────
for (const [key, cols] of Object.entries(COLUMNS)) {
  const rows = data[key];
  if (!Array.isArray(rows)) continue;
  data[key] = rows.map((row) => {
    const ordered = {};
    for (const c of cols) if (row[c] !== undefined) ordered[c] = row[c];
    for (const c of Object.keys(row)) if (!(c in ordered)) ordered[c] = row[c];
    return ordered;
  });
}

data.members = nextMembers;

// 更新 counts，让它与真实数据一致（服务端会原样回显）
pkg.counts = {
  ...(pkg.counts ?? {}),
  members: nextMembers.length,
  categories: Array.isArray(data.categories) ? data.categories.length : 0,
  paymentMethods: Array.isArray(data.paymentMethods) ? data.paymentMethods.length : 0,
  plans: Array.isArray(data.plans) ? data.plans.length : 0,
  planTodos: Array.isArray(data.planTodos) ? data.planTodos.length : 0,
  expenses: Array.isArray(data.expenses) ? data.expenses.length : 0,
};

const json = JSON.stringify(pkg);
try {
  writeFileSync(output, json, 'utf8');
} catch (err) {
  fail(`写不了输出文件：${err.message}`);
}

console.log(`\n✔ 已生成：${output}`);
console.log(`  成员：${members.length} → ${nextMembers.length}`);
console.log(`  改写的成员引用：${stats.replaced} 处`);
if (filled > 0) console.log(`  补齐 payment_methods.icon：${filled} 行`);
console.log('  数据量：' + Object.entries(pkg.counts).map(([k, v]) => `${k}=${v}`).join('  '));
console.log('\n导入方式（Web 端「数据」→「恢复备份」上传该文件，或）：');
console.log('  curl -X POST http://<地址>:<端口>/api/backup/restore \\');
console.log('    -H "Authorization: Bearer <token>" \\');
console.log('    -H "Content-Type: application/json" \\');
console.log(`    --data-binary @${output}\n`);
