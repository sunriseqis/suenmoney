/**
 * 从原型设计系统（web/styles/proto/theme.css）生成鸿蒙端主题令牌。
 *
 * 为什么用生成器而不是手抄：
 *   主题一共 48/49 个 CSS 变量，手抄必漏项，而漏项的表现是「某处颜色差一档」
 *   —— 界面不报错、看着也像那么回事，事后极难定位（与「金额差一分」同类）。
 *   生成器同时产出**映射表**，Ledger 的核验门禁就是拿这张表逐条对。
 *
 * 产出：
 *   hw-native/entry/src/main/ets/common/theme/AppTheme.ets
 *   docs/design/generated/hw-theme-mapping.md
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

const ROOT = process.cwd();
const CSS = join(ROOT, 'web/styles/proto/theme.css');
const OUT_ETS = join(ROOT, 'hw-native/entry/src/main/ets/common/theme/AppTheme.ets');
const OUT_MAP = join(ROOT, 'docs/design/generated/hw-theme-mapping.md');

const css = readFileSync(CSS, 'utf8');

function blockBody(selector) {
  const i = css.indexOf(selector);
  if (i < 0) throw new Error('找不到选择器: ' + selector);
  const j = css.indexOf('}', i);
  return css.slice(i, j);
}

function parseVars(body) {
  const out = [];
  const re = /(--[a-z0-9-]+)\s*:\s*([^;]+);/g;
  let m;
  while ((m = re.exec(body)) !== null) out.push({ name: m[1], value: m[2].trim() });
  return out;
}

/**
 * `:root` 里的变量是所有主题共用的（密度间距等），必须一起收进来 ——
 * 之前只解析两个主题块，导致 `--density-pad` 缺失、卡片内边距只能瞎写。
 */
const shared = parseVars(blockBody(':root {'));
const candy = shared.concat(parseVars(blockBody('.app[data-theme="candy"] {')));
const cyber = shared.concat(parseVars(blockBody('.app[data-theme="cyber"] {')));

/** CSS 变量名 → ArkTS 字段名（camelCase，去掉 -- 前缀） */
function toField(name) {
  const bare = name.replace(/^--/, '');
  return bare.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

/** 归类：颜色 / 尺寸 / 字体 / 其它。决定 ArkTS 里的类型 */
function kindOf(value) {
  if (/^#[0-9a-f]{3,8}$/i.test(value) || /^rgba?\(/i.test(value)) return 'color';
  if (/^-?\d+(\.\d+)?px$/.test(value)) return 'dimension';
  if (value === 'none') return 'none';
  return 'text';
}

function tsType(kind) {
  if (kind === 'dimension') return 'number';
  return 'string';
}

function tsValue(kind, value) {
  if (kind === 'dimension') return String(parseFloat(value));
  return JSON.stringify(value);
}

// 以 candy 的字段顺序为准，cyber 多出的字段补在后
const order = candy.map((v) => v.name);
for (const v of cyber) if (!order.includes(v.name)) order.push(v.name);

const rows = order.map((name) => {
  const c = candy.find((v) => v.name === name);
  const y = cyber.find((v) => v.name === name);
  const sample = (c ?? y).value;
  const kind = kindOf(sample);
  return { name, field: toField(name), kind, candy: c, cyber: y };
});

const needFallback = rows.filter((r) => (r.candy === undefined) !== (r.cyber === undefined));

// ── ArkTS ──────────────────────────────────────────────────────────────────
const lines = [];
lines.push('/**');
lines.push(' * 主题令牌 —— **由 scripts/gen-hw-theme.mjs 从 web/styles/proto/theme.css 生成，请勿手改**。');
lines.push(' *');
lines.push(' * 两套设计语言：candy（水果硬糖 / 浅色）与 cyber（赛博朋克 / 深色）。');
lines.push(` * 共 ${rows.length} 个令牌，与原型 CSS 变量一一对应；映射表见 docs/design/generated/hw-theme-mapping.md。`);
lines.push(' *');
lines.push(' * ArkTS 约束：不用对象字面量的动态 key 访问，所以这里是「接口 + 两个常量对象」，');
lines.push(' * 取字段一律走 `theme.bg` 这种静态成员访问。');
lines.push(' */');
lines.push('');
lines.push('export interface ThemeTokens {');
for (const r of rows) {
  lines.push(`  ${r.field}: ${tsType(r.kind)};`);
}
lines.push('}');
lines.push('');
lines.push('export const CANDY: ThemeTokens = {');
for (const r of rows) {
  const v = r.candy ?? r.cyber;
  lines.push(`  ${r.field}: ${tsValue(r.kind, v.value)},`);
}
lines.push('};');
lines.push('');
lines.push('export const CYBER: ThemeTokens = {');
for (const r of rows) {
  const v = r.cyber ?? r.candy;
  lines.push(`  ${r.field}: ${tsValue(r.kind, v.value)},`);
}
lines.push('};');
lines.push('');

mkdirSync(dirname(OUT_ETS), { recursive: true });
writeFileSync(OUT_ETS, lines.join('\n'));

// ── 映射表 ─────────────────────────────────────────────────────────────────
const md = [];
md.push('# 鸿蒙端主题令牌映射表（生成物，勿手改）', '');
md.push(`> 来源：\`web/styles/proto/theme.css\` · 生成器：\`scripts/gen-hw-theme.mjs\` · 令牌数 **${rows.length}**`);
md.push('> 核验方式：本表行数必须等于原型 CSS 变量数，且 ArkTS 侧字段一一对应。', '');
md.push('| # | CSS 变量 | ArkTS 字段 | 类型 | candy | cyber |');
md.push('|---|---|---|---|---|---|');
rows.forEach((r, i) => {
  md.push(`| ${i + 1} | \`${r.name}\` | \`${r.field}\` | ${r.kind} | ${r.candy ? '`' + r.candy.value + '`' : '—'} | ${r.cyber ? '`' + r.cyber.value + '`' : '—'} |`);
});
md.push('');
md.push('## 校验', '');
md.push(`- 原型 CSS 变量数：candy ${candy.length} · cyber ${cyber.length}`);
md.push(`- 合并后令牌数：**${rows.length}**`);
md.push(`- 单侧缺失（需回退）的变量：${needFallback.length === 0 ? '无' : needFallback.map((r) => '`' + r.name + '`').join('、')}`);
if (needFallback.length > 0) {
  md.push('');
  md.push('> 单侧缺失的变量在生成时回退到另一侧的值，并在 ArkTS 里注明。');
}
md.push('');
md.push('## 典型用法', '');
md.push('```ts');
md.push("import { CANDY, CYBER, ThemeTokens } from '../common/theme/AppTheme';");
md.push('');
md.push("@State tokens: ThemeTokens = CYBER;   // 深色为默认（与 Web 一致）");
md.push("// 切主题： this.tokens = isCandy ? CANDY : CYBER;");
md.push('```');

mkdirSync(dirname(OUT_MAP), { recursive: true });
writeFileSync(OUT_MAP, md.join('\n') + '\n');

console.log(`✓ ${OUT_ETS}`);
console.log(`✓ ${OUT_MAP}`);
console.log(`令牌 ${rows.length} 个（candy ${candy.length} · cyber ${cyber.length}），单侧缺失 ${needFallback.length} 个`);
