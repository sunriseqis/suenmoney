/**
 * 把三端共用测试向量（docs/test-vectors/vectors.json）生成为 ArkTS runner。
 *
 * 为什么生成：向量是**契约**，不该在两端各抄一遍。手抄一份 ArkTS 用例，
 * 等于契约有了第二份副本；以后 Web 加了用例、鸿蒙没跟上，就再也发现不了。
 *
 * 产出：hw-native/entry/src/main/ets/common/contract/VectorRunner.ets
 *   - runAll(): string —— 跑全部用例，返回 PASS/FAIL 报告（可直接贴进验收包）
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';

const ROOT = process.cwd();
const SRC = join(ROOT, 'docs/test-vectors/vectors.json');
const OUT = join(ROOT, 'hw-native/entry/src/main/ets/common/contract/VectorRunner.ets');

const v = JSON.parse(readFileSync(SRC, 'utf8'));
const lines = [];
const push = (s) => lines.push(s);

push('/**');
push(' * 三端共用测试向量的 ArkTS runner —— **由 scripts/gen-hw-vectors.mjs 生成，请勿手改**。');
push(' *');
push(' * 数据源：docs/test-vectors/vectors.json（与 Web、iOS 同一份）。');
push(' * 用法：`VectorRunner.runAll()` 返回 PASS/FAIL 报告字符串，直接贴进验收包。');
push(' */');
push("import {");
push("  buildDonutArcs, centsToInput, daysUntil, DonutArc, formatCents, formatYuan,");
push("  parseYuanToCents, shiftMonth, splitInstallment, urgencyLabel, urgencyOf");
push("} from './Contract';");
push('');
push('export class VectorReport {');
push('  total: number = 0;');
push('  passed: number = 0;');
push('  failures: string[] = [];');
push('');
push('  check(name: string, actual: string, expect: string): void {');
push('    this.total += 1;');
push('    if (actual === expect) {');
push('      this.passed += 1;');
push('    } else {');
push('      this.failures.push(`${name}: 期望 ${expect}，实际 ${actual}`);');
push('    }');
push('  }');
push('');
push('  summary(): string {');
push('    const head = this.failures.length === 0');
push('      ? `向量 PASS：${this.passed}/${this.total}`');
push('      : `向量 FAIL：${this.passed}/${this.total}`;');
push('    return this.failures.length === 0 ? head : head + "\\n" + this.failures.join("\\n");');
push('  }');
push('}');
push('');

// 每个 suite 一个静态方法
function suiteName(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/** 把 JSON 值转成 ArkTS 调用参数与期望值字面量 */
function lit(value) {
  if (typeof value === 'string') return `'${value.replace(/'/g, "\\'")}'`;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  if (value === null) return 'null';
  if (Array.isArray(value)) return `[${value.map(lit).join(', ')}]`;
  // 对象（donut 用）按字段显式构造
  return JSON.stringify(value);
}

push('export class VectorRunner {');
push('  static runAll(): string {');
push('    const r = new VectorReport();');
push('    VectorRunner.money(r);');
push('    VectorRunner.dates(r);');
push('    VectorRunner.urgency(r);');
push('    VectorRunner.donut(r);');
push('    return r.summary();');
push('  }');
push('');

// money
push('  private static money(r: VectorReport): void {');
for (const c of v.money) {
  const name = JSON.stringify(c.note);
  if (c.fn === 'splitInstallment') {
    const [total, periods] = c.input;
    const expect = c.expect.length === 0 ? "''" : `'${c.expect.join(',')}'`;
    push(`    r.check(${name}, splitInstallment(${total}, ${periods}).join(','), ${expect});`);
  } else {
    const arg = lit(c.input[0]);
    const fn = c.fn;
    const expect = `'${String(c.expect)}'`;
    const actual = fn === 'parseYuanToCents' || fn === 'splitInstallment'
      ? `String(${fn}(${arg}))`
      : `${fn}(${arg})`;
    push(`    r.check(${name}, ${actual}, ${expect});`);
  }
}
push('  }');
push('');

// dates
push('  private static dates(r: VectorReport): void {');
for (const c of v.dates) {
  const [a, b] = c.input;
  push(`    r.check(${JSON.stringify(c.note)}, String(${c.fn}(${lit(a)}, ${lit(b)})), '${String(c.expect)}');`);
}
push('  }');
push('');

// urgency
push('  private static urgency(r: VectorReport): void {');
for (const c of v.urgency) {
  const [date, today] = c.input;
  push(`    r.check(${JSON.stringify(c.note)}, String(${c.fn}(${lit(date)}, ${lit(today)})), '${String(c.expect)}');`);
}
push('  }');
push('');

// donut
push('  private static donut(r: VectorReport): void {');
for (const c of v.donut) {
  const slices = c.input[0];
  const arg = `[${slices.map((s) => `{ id: '${s.id}', ratio: ${s.ratio}, color: '${s.color}' }`).join(', ')}]`;
  if (c.expect.length === 0) {
    push(`    r.check(${JSON.stringify(c.note)}, String(buildDonutArcs(${arg}).length), '0');`);
  } else {
    const first = c.expect[0];
    const expectStr = `${first.id}:${first.percent}:${first.offset}`;
    push(`    {`);
    push(`      const arcs: DonutArc[] = buildDonutArcs(${arg});`);
    push(`      const a: DonutArc = arcs[0];`);
    push(`      r.check(${JSON.stringify(c.note)}, \`\${a.id}:\${a.percent}:\${a.offset}\`, '${expectStr}');`);
    push(`    }`);
  }
}
push('  }');
push('}');
push('');

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, lines.join('\n'));

const count =
  v.money.length + v.dates.length + v.urgency.length + v.donut.length;
console.log(`✓ ${OUT}`);
console.log(`生成 ${count} 条用例（money ${v.money.length} · dates ${v.dates.length} · urgency ${v.urgency.length} · donut ${v.donut.length}）`);
