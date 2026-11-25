// .vue 结构体检：SFC 顶层块（行首无缩进的 <template>/<script>/<style>）+ 模板标签配平
//
// 用法：
//   node scripts/vue-check.mjs                  # 体检 web/src/**/*.vue 全部文件
//   node scripts/vue-check.mjs <path/to.x.vue>  # 只体检单个文件
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const VOID_TAGS = new Set([
  'br', 'hr', 'img', 'input', 'meta', 'link', 'path', 'rect', 'circle', 'line',
  'polyline', 'polygon', 'use', 'stop', 'ellipse', 'col', 'area', 'source', 'track', 'wbr',
]);

function checkFile(f) {
  const s = readFileSync(f, 'utf8');
  const lines = s.split('\n');
  const problems = [];

  // 1) SFC 顶层块必须成对（行首无缩进）
  for (const blk of ['template', 'script', 'style']) {
    const opens = lines
      .filter((l) => l.trimEnd() === `<${blk}>` || l.startsWith(`<${blk} `) || l.startsWith(`<${blk}>`))
      .filter((l) => !/^\s/.test(l)).length;
    const closes = lines.filter((l) => l.trimEnd() === `</${blk}>`).filter((l) => !/^\s/.test(l)).length;
    if (blk === 'template' && opens !== 1) problems.push(`顶层 <template> 数 = ${opens}（应为 1）`);
    if (blk === 'template' && closes !== 1) problems.push(`顶层 </template> 数 = ${closes}（应为 1）`);
    if (blk !== 'template' && opens !== closes) problems.push(`顶层 <${blk}> ${opens}/${closes}`);
  }

  // 2) 模板体标签配平
  const t0 = lines.findIndex((l) => !/^\s/.test(l) && l.trimEnd() === '<template>');
  const t1 = lines.findIndex((l, i) => i > t0 && !/^\s/.test(l) && l.trimEnd() === '</template>');
  if (t0 < 0 || t1 < 0) {
    problems.push('找不到顶层 template 块');
  } else {
    const body = lines.slice(t0 + 1, t1).join('\n');
    const stack = [];
    const re = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;
    let m;
    let bad = null;
    while ((m = re.exec(body))) {
      const [, close, name, , self] = m;
      const n = name.toLowerCase();
      if (VOID_TAGS.has(n) || self) continue;
      if (close) {
        if (stack.length && stack[stack.length - 1] === n) stack.pop();
        else { bad = `不匹配 </${n}>，此时栈顶 ${stack.slice(-3).join(' > ') || '空'}`; break; }
      } else stack.push(n);
    }
    if (bad) problems.push(bad);
    else if (stack.length) problems.push(`未闭合 ${stack.slice(-4).join(' > ')}`);
  }

  if (problems.length) {
    console.log(`✗ ${f}`);
    problems.forEach((p) => console.log('  - ' + p));
    return false;
  }
  console.log(`✓ ${f}`);
  return true;
}

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (p.endsWith('.vue')) out.push(p);
  }
  return out;
}

const explicit = process.argv[2] ? resolve(process.argv[2]) : null;
const targets = explicit ? [explicit] : walk(join(ROOT, 'web/src'), []);

if (targets.length === 0) {
  console.error('未找到 .vue 文件（请先构建前端，或传入具体文件路径）');
  process.exit(1);
}

let bad = 0;
for (const f of targets) if (!checkFile(f)) bad++;

if (bad > 0) {
  console.error(`\n${bad} 个文件未通过`);
  process.exit(1);
}
console.log(`\n${targets.length} 个 .vue 文件全部通过`);
