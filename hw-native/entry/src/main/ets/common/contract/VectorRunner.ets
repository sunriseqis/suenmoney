/**
 * 三端共用测试向量的 ArkTS runner —— **由 scripts/gen-hw-vectors.mjs 生成，请勿手改**。
 *
 * 数据源：docs/test-vectors/vectors.json（与 Web、iOS 同一份）。
 * 用法：`VectorRunner.runAll()` 返回 PASS/FAIL 报告字符串，直接贴进验收包。
 */
import {
  buildDonutArcs, centsToInput, daysUntil, DonutArc, formatCents, formatYuan,
  parseYuanToCents, shiftMonth, splitInstallment, urgencyLabel, urgencyOf
} from './Contract';

export class VectorReport {
  total: number = 0;
  passed: number = 0;
  failures: string[] = [];

  check(name: string, actual: string, expect: string): void {
    this.total += 1;
    if (actual === expect) {
      this.passed += 1;
    } else {
      this.failures.push(`${name}: 期望 ${expect}，实际 ${actual}`);
    }
  }

  summary(): string {
    const head = this.failures.length === 0
      ? `向量 PASS：${this.passed}/${this.total}`
      : `向量 FAIL：${this.passed}/${this.total}`;
    return this.failures.length === 0 ? head : head + "\n" + this.failures.join("\n");
  }
}

export class VectorRunner {
  static runAll(): string {
    const r = new VectorReport();
    VectorRunner.money(r);
    VectorRunner.dates(r);
    VectorRunner.urgency(r);
    VectorRunner.donut(r);
    return r.summary();
  }

  private static money(r: VectorReport): void {
    r.check("常规两位小数", String(parseYuanToCents('12.34')), '1234');
    r.check("一位小数补齐", String(parseYuanToCents('0.5')), '50');
    r.check("负数不得翻正（历史 bug）", String(parseYuanToCents('-15.50')), '-1550');
    r.check("-0 必须仍是负", String(parseYuanToCents('-0.50')), '-50');
    r.check("空串为 0", String(parseYuanToCents('')), '0');
    r.check("浮点陷阱：19.99*100=1998.99…", String(parseYuanToCents('19.99')), '1999');
    r.check("千分位 + 两位小数", formatCents(1234), '12.34');
    r.check("退款为负", formatCents(-1550), '-15.50');
    r.check("带 ¥ 前缀", formatYuan(1234), '¥12.34');
    r.check("整元不带小数", centsToInput(1200), '12');
    r.check("补零", centsToInput(1205), '12.05');
    r.check("各期之和必须恰好等于总额（末期补差）", splitInstallment(100000, 3).join(','), '33333,33333,33334');
    r.check("总额（2 分）小于期数（3）→ 空数组；注意 100 分分 3 期是合法的", splitInstallment(2, 3).join(','), '');
  }

  private static dates(r: VectorReport): void {
    r.check("跨年回退", String(shiftMonth('2026-01', -1)), '2025-12');
    r.check("跨年前进", String(shiftMonth('2026-12', 1)), '2027-01');
    r.check("普通回退", String(shiftMonth('2026-10', -1)), '2026-09');
    r.check("同一天为 0", String(daysUntil('2026-10-22', '2026-10-22')), '0');
    r.check("过去为负", String(daysUntil('2026-10-20', '2026-10-22')), '-2');
    r.check("未来为正", String(daysUntil('2026-11-01', '2026-10-22')), '10');
  }

  private static urgency(r: VectorReport): void {
    r.check("迟于还款日", String(urgencyOf('2026-10-21', '2026-10-22')), 'overdue');
    r.check("今天到期", String(urgencyOf('2026-10-22', '2026-10-22')), 'due');
    r.check("0–1 天都算 due", String(urgencyOf('2026-10-23', '2026-10-22')), 'due');
    r.check("2 天起为 later", String(urgencyOf('2026-10-24', '2026-10-22')), 'later');
    r.check("逾期文案", String(urgencyLabel('2026-10-20', '2026-10-22')), '已逾期 2 天');
    r.check("当天文案", String(urgencyLabel('2026-10-22', '2026-10-22')), '今天到期');
    r.check("未来文案", String(urgencyLabel('2026-10-25', '2026-10-22')), '还有 3 天');
  }

  private static donut(r: VectorReport): void {
    {
      const arcs: DonutArc[] = buildDonutArcs([{ id: 'a', ratio: 0.5, color: '#111111' }, { id: 'b', ratio: 0.3, color: '#222222' }, { id: 'c', ratio: 0.2, color: '#333333' }]);
      const a: DonutArc = arcs[0];
      r.check("offset 严格递增（首段 25 起步，逐段减 percent）；比例 50/30/20", `${a.id}:${a.percent}:${a.offset}`, 'a:50:25');
    }
    {
      const arcs: DonutArc[] = buildDonutArcs([{ id: 'only', ratio: 1, color: '#111111' }]);
      const a: DonutArc = arcs[0];
      r.check("单一分类占满 100", `${a.id}:${a.percent}:${a.offset}`, 'only:100:25');
    }
    r.check("空输入返回空数组", String(buildDonutArcs([]).length), '0');
    {
      const arcs: DonutArc[] = buildDonutArcs([{ id: 'neg', ratio: -0.4, color: '#000000' }]);
      const a: DonutArc = arcs[0];
      r.check("负 ratio 钳到 0（否则 stroke-dasharray 语法被破坏）", `${a.id}:${a.percent}:${a.offset}`, 'neg:0:25');
    }
  }
}
