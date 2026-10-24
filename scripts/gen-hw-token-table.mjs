/**
 * 从 theme.css 直接生成令牌对照表（**机器抄，不手抄**）。
 *
 * 为什么需要：规范 v1 里颜色只写了部分变量、还有 5 组值抄错，
 * 覆盖核验因此判 FAIL。颜色是"抄错一个就看得出不对"的东西，
 * 所以这张表由脚本从源文件生成，规范只引用它。
 *
 * 产出：docs/design/generated/hw-token-table.md
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const css = readFileSync('web/styles/proto/theme.css', 'utf8');
function block(sel) {
  const i = css.indexOf(sel);
  if (i < 0) throw new Error('missing ' + sel);
  return css.slice(i, css.indexOf('}', i));
}
function vars(body) {
  const out = [];
  const re = /(--[a-z0-9-]+)\s*:\s*([^;]+);/g;
  let m;
  while ((m = re.exec(body)) !== null) out.push({ k: m[1], v: m[2].trim() });
  return out;
}

const root = vars(block(':root {'));
const candy = new Map(vars(block('.app[data-theme="candy"] {')).map((x) => [x.k, x.v]));
const cyber = new Map(vars(block('.app[data-theme="cyber"] {')).map((x) => [x.k, x.v]));

const keys = [];
for (const x of root) keys.push(x.k);
for (const k of candy.keys()) if (!keys.includes(k)) keys.push(k);
for (const k of cyber.keys()) if (!keys.includes(k)) keys.push(k);

const lines = [];
lines.push('# 令牌对照表（生成物，勿手改）', '');
lines.push('> 来源：`web/styles/proto/theme.css` · 生成器：`scripts/gen-hw-token-table.mjs`');
lines.push(`> 令牌数 **${keys.length}**（:root ${root.length} · candy ${candy.size} · cyber ${cyber.size}）`, '');
lines.push('| # | CSS 变量 | candy | cyber |');
lines.push('|---|---|---|---|');
keys.forEach((k, i) => {
  const c = candy.get(k) ?? (root.find((r) => r.k === k)?.v ?? '—');
  const y = cyber.get(k) ?? (root.find((r) => r.k === k)?.v ?? '—');
  lines.push(`| ${i + 1} | \`${k}\` | \`${c}\` | \`${y}\` |`);
});
lines.push('');
lines.push('## 分类色的两种用法');
lines.push('- `--chart-1..8` 是**色板**；分类只存**色号**（1–16），显示时取 `chart[(n-1) % 8]`。');
lines.push('- 图标底色是 `color-mix(色 12%, transparent)`、描边 `color-mix(色 45%, transparent)`；');
lines.push('  ArkUI 没有 `color-mix()`，实现用 `common/ui/UiStyle.ets` 的 `mixHex(hex, bg, ratio)` 运行时算。');

mkdirSync('docs/design/generated', { recursive: true });
writeFileSync('docs/design/generated/hw-token-table.md', lines.join('\n') + '\n');
console.log(`✓ docs/design/generated/hw-token-table.md（${keys.length} 个令牌）`);
