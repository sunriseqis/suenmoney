<script setup lang="ts">
/**
 * 本月构成卡（v3 · 2026-10-21 用户新增）。
 *
 * 堆叠条 + 明细行，**可按四个维度切换配色**：
 *   分类（默认，16 槽用户色）/ 支付方式（结算属性四色）/
 *   记录人（成员固定色）/ 日期节奏（单色深浅四档，越近越深）。
 *
 * 规则（tokens.json `dimensions.$meta`）：
 *   同一屏只渲染一个维度的色带；切换维度 = 整排色块一起换，不叠加。
 *   这保证「粉永远意味着霓虹粉那一族」，不会同一段既是粉又是绿。
 */
import { computed, ref } from 'vue';

type Dim = 'category' | 'payment' | 'owner' | 'rhythm';

interface Segment {
  key: string;
  label: string;
  cents: number;
  count: number;
  color: string;
}

const props = defineProps<{
  /** 本期总支出（分） */
  totalCents: number;
  /** 分类聚合：[{name, cents, count, colorIndex}] —— colorIndex 是 1–16 槽 */
  byCategory: Array<{ name: string; cents: number; count: number; colorIndex: number }>;
  /** 支付方式聚合：[{name, cents, count, kind}] kind ∈ credit|installment|cash|other */
  byPayment: Array<{ name: string; cents: number; count: number; kind: string }>;
  /** 记录人聚合：[{name, cents, count, ownerIndex}] ownerIndex 0 起 */
  byOwner: Array<{ name: string; cents: number; count: number; ownerIndex: number }>;
  /** 日期节奏聚合：[{label, cents, count, slot}] slot 1–4（越近越大） */
  byRhythm: Array<{ label: string; cents: number; count: number; slot: number }>;
}>();

const DIMS: Array<{ value: Dim; label: string }> = [
  { value: 'category', label: '分类' },
  { value: 'payment', label: '支付' },
  { value: 'owner', label: '记录人' },
  { value: 'rhythm', label: '节奏' },
];

const dim = ref<Dim>('category');

/** 维度 → 色带（与 tokens.json dimensions 对齐） */
const BANDS: Record<Exclude<Dim, 'category'>, Record<string, string>> = {
  payment: { credit: '#B388FF', installment: '#FF7AB8', cash: '#4DFFD2', other: '#706D96' },
  owner: { '0': '#5DB8FF', '1': '#E5FF41', '2': '#FF7AB8', '3': '#B388FF' },
  rhythm: { '1': 'rgba(76,141,255,.25)', '2': 'rgba(76,141,255,.45)', '3': 'rgba(76,141,255,.70)', '4': 'rgba(76,141,255,1)' },
};

const fmt = (cents: number) => (cents / 100).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const segments = computed<Segment[]>(() => {
  const top = (rows: Array<{ label: string; cents: number; count: number; color?: string }>) => {
    const sorted = [...rows].sort((a, b) => b.cents - a.cents);
    const head = sorted.slice(0, 3);
    const rest = sorted.slice(3);
    const restCents = rest.reduce((s, r) => s + r.cents, 0);
    const out: Segment[] = head.map((r): Segment => ({ ...r, key: r.label, color: r.color ?? '#706D96' }));
    if (restCents > 0) out.push({ key: '__other', label: '其他', cents: restCents, count: rest.length, color: '#706D96' });
    return out.map((r): Segment => ({ ...r, color: r.color ?? '#706D96' }));
  };

  if (dim.value === 'category') {
    const rows = props.byCategory.map((c) => ({
      label: c.name, cents: c.cents, count: c.count,
      color: `var(--chart-${c.colorIndex})`,
    }));
    return top(rows);
  }
  if (dim.value === 'payment') {
    const rows = props.byPayment.map((p) => ({
      label: p.name, cents: p.cents, count: p.count,
      color: BANDS.payment[p.kind] ?? BANDS.payment.other,
    }));
    return top(rows);
  }
  if (dim.value === 'owner') {
    const rows = props.byOwner.map((o) => ({
      label: o.name, cents: o.cents, count: o.count,
      color: BANDS.owner[String(o.ownerIndex)] ?? '#706D96',
    }));
    return top(rows);
  }
  // rhythm：按 slot 排（越近越深），不截断
  return [...props.byRhythm]
    .sort((a, b) => a.slot - b.slot)
    .map((r) => ({
      key: r.label, label: r.label, cents: r.cents, count: r.count,
      color: BANDS.rhythm[String(r.slot)] ?? '#706D96',
    }));
});

const total = computed(() => props.totalCents || segments.value.reduce((s, x) => s + x.cents, 0));
const pct = (cents: number) => (total.value > 0 ? Math.round((cents / total.value) * 100) : 0);
</script>

<template>
  <section class="rounded-2xl bg-surface-container p-5 shadow-[var(--el-1)]" aria-label="本月构成">
    <div class="mb-4 flex items-center justify-between gap-3">
      <h3 class="text-base font-medium text-on-surface">本月构成</h3>
      <div class="pill-tabs" role="tablist" aria-label="构成维度">
        <button
          v-for="d in DIMS"
          :key="d.value"
          type="button"
          role="tab"
          :aria-selected="dim === d.value"
          class="pill-tab"
          @click="dim = d.value"
        >
          {{ d.label }}
        </button>
      </div>
    </div>

    <!-- 堆叠条：段与明细同色，切换维度整排换 -->
    <div class="mb-3 flex h-2.5 gap-0.5 overflow-hidden rounded-full">
      <span
        v-for="s in segments"
        :key="s.key"
        :style="{ background: s.color, width: `${(s.cents / total) * 100}%` }"
        class="h-full first:rounded-l-full last:rounded-r-full"
      />
    </div>

    <div class="space-y-1.5">
      <div
        v-for="s in segments"
        :key="s.key"
        class="flex items-center justify-between text-[13px]"
      >
        <span class="flex items-center gap-2 text-on-surface">
          <span class="h-2 w-2 rounded-sm" :style="{ background: s.color }" />
          {{ s.label }}
        </span>
        <span class="tabular-nums text-on-surface-variant">
          {{ pct(s.cents) }}% · <span class="text-on-surface">¥{{ fmt(s.cents) }}</span>
        </span>
      </div>
    </div>
  </section>
</template>
