// .vue 结构体检：SFC 顶层块（行首无缩进的 <template>/<script>/<style>）+ 模板标签配平
import { readFileSync } from 'node:fs';
const f = process.argv[2];
const s = readFileSync(f, 'utf8');
const lines = s.split('\n');
const problems = [];

// 1) SFC 顶层块必须成对（行首无缩进）
for (const blk of ['template', 'script', 'style']) {
  const opens = lines.filter(l => l.trimEnd() === `<${blk}>` || l.startsWith(`<${blk} `) || l.startsWith(`<${blk}>`)).filter(l => !/^\s/.test(l)).length;
  const closes = lines.filter(l => l.trimEnd() === `</${blk}>`).filter(l => !/^\s/.test(l)).length;
  if (blk === 'template' && opens !== 1) problems.push(`顶层 <template> 数 = ${opens}（应为 1）`);
  if (blk === 'template' && closes !== 1) problems.push(`顶层 </template> 数 = ${closes}（应为 1）`);
  if (blk !== 'template' && opens !== closes) problems.push(`顶层 <${blk}> ${opens}/${closes}`);
}

// 2) 模板体标签配平
const t0 = lines.findIndex(l => !/^\s/.test(l) && l.trimEnd() === '<template>');
const t1 = lines.findIndex((l, i) => i > t0 && !/^\s/.test(l) && l.trimEnd() === '</template>');
if (t0 < 0 || t1 < 0) { problems.push('找不到顶层 template 块'); }
else {
  const body = lines.slice(t0 + 1, t1).join('\n');
  const voidTags = new Set(['br','hr','img','input','meta','link','path','rect','circle','line','polyline','polygon','use','stop','ellipse','col','area','source','track','wbr']);
  const stack = [];
  const re = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;
  let m, bad = null;
  while ((m = re.exec(body))) {
    const [, close, name, , self] = m;
    const n = name.toLowerCase();
    if (voidTags.has(n) || self) continue;
    if (close) {
      if (stack.length && stack[stack.length - 1] === n) stack.pop();
      else { bad = `不匹配 </${n}>，此时栈顶 ${stack.slice(-3).join(' > ') || '空'}`; break; }
    } else stack.push(n);
  }
  if (bad) problems.push(bad);
  else if (stack.length) problems.push(`未闭合 ${stack.slice(-4).join(' > ')}`);
}
if (problems.length) { console.log(`✗ ${f}`); problems.forEach(p => console.log('  - ' + p)); process.exit(1); }
console.log(`✓ ${f}`);
