<script setup lang="ts">
/**
 * 期间选择器 —— 流水页、报表页、导出页共用。
 *
 * ## 为什么要有这个组件
 *
 * 这三个页面原先各自内联一份「← 上一期 / → 下一期」，只能**逐期翻**：
 * 想看半年前的账要按 6 次，而且是盲按 —— 按到第几次心里没数，只有翻到了才知道。
 * 抽成一个组件之后，三处行为不会再各自漂移（原先 LedgerView 与 ReportView
 * 就是两份独立实现，只是恰好长得一样）。
 *
 * ## 交互
 *
 * 标题本身可点 → 弹出面板：年份可前后翻 + 12 格网格（月模式是 12 个月，
 * 年模式是 12 年），底部给「回到本月 / 今年」。
 *
 * 刻意**不加**「跳一年」按钮。那只是把 6 次点击变成 2 次，用户仍要猜按几下；
 * 面板是一次点到位，顺带还能跳到任意一个月。两套并存也没意义 ——
 * 有了面板，箭头按钮就是纯冗余。
 *
 * ## 边界：往后到当期为止
 *
 * 未来没有数据，翻过去只会看到一片空，让人以为坏了。所以超过当期（或调用方
 * 给的 `maxMonth`）的格子直接**禁用**而不是隐藏 —— 隐藏会让人以为"只有这么多月份"，
 * 禁用才表达得出"这里还有，但现在没意义"。
 * 往前不设限：账本可以回溯很多年。
 */
import { ChevronDown, ChevronLeft, ChevronRight } from '@lucide/vue';
import { computed, onUnmounted, ref, watch } from 'vue';

import { currentMonth } from '@/utils/dates';

const props = withDefaults(
  defineProps<{
    /** 触发按钮上的文字 */
    label: string;
    /** 当前选中的月份 'YYYY-MM'（mode='month' 时用） */
    month?: string;
    /** 当前选中的年份 'YYYY'（mode='year' 时用） */
    year?: string;
    /** 面板展示哪种网格 */
    mode?: 'month' | 'year';
    /** 可选范围的最后一期 'YYYY-MM'，默认本月 */
    maxMonth?: string;
    /** 面板相对触发按钮的对齐方式。右对齐的场景用 'end'，否则会溢出屏幕 */
    align?: 'start' | 'center' | 'end';
    /** 只显示文字，不做成可点的（导出页选「全部」时用） */
    readonly?: boolean;
  }>(),
  { month: '', year: '', mode: 'month', maxMonth: '', align: 'start', readonly: false },
);

const emit = defineEmits<{
  'update:month': [value: string];
  'update:year': [value: string];
}>();

/** 当期。整个项目里「今天是几号」只能由客户端给，服务端常年跑 UTC。 */
const thisMonth = currentMonth();

/** 可选范围的最后一期。默认本月 —— 未来的月份没有数据 */
const upperBound = computed(() => (props.maxMonth === '' ? thisMonth : props.maxMonth));
const maxYear = computed(() => Number(upperBound.value.slice(0, 4)));

const selectedMonth = computed(() => (props.month === '' ? thisMonth : props.month));
const selectedYear = computed(() =>
  props.year === '' ? String(maxYear.value) : props.year,
);

/* ---- 面板开合 ---------------------------------------------------------- */

const open = ref(false);
const rootRef = ref<HTMLElement | null>(null);

/** 月模式下面板翻到的年份 */
const panelYear = ref(Number(selectedMonth.value.slice(0, 4)));
/** 年模式下年份窗口的**末**年（窗口 = 末年前 12 年） */
const windowEnd = ref(maxYear.value);

function toggle(): void {
  if (props.readonly) return;
  open.value = !open.value;
  if (open.value) {
    // 每次打开都回到「含当前选择」的位置，而不是上次翻到哪就停在哪 ——
    // 否则用户下次打开看到的是一片与当前数据无关的年份，还得自己找回来。
    panelYear.value = Math.min(Number(selectedMonth.value.slice(0, 4)), maxYear.value);
    windowEnd.value = maxYear.value;
  }
}

/**
 * 点面板外面就收起。
 *
 * 与「更多」菜单同一套做法：监听 document 的 pointerdown 而不是 click ——
 * click 要等手指抬起，期间面板还开着，落在别处的那一下会先被当成别的操作。
 */
function onDocumentPointerDown(event: PointerEvent): void {
  const el = rootRef.value;
  if (el !== null && event.target instanceof Node && !el.contains(event.target)) {
    open.value = false;
  }
}

function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape') open.value = false;
}

watch(open, (isOpen) => {
  if (isOpen) {
    document.addEventListener('pointerdown', onDocumentPointerDown);
    document.addEventListener('keydown', onKeydown);
  } else {
    document.removeEventListener('pointerdown', onDocumentPointerDown);
    document.removeEventListener('keydown', onKeydown);
  }
});

onUnmounted(() => {
  document.removeEventListener('pointerdown', onDocumentPointerDown);
  document.removeEventListener('keydown', onKeydown);
});

/* ---- 面板内容 ---------------------------------------------------------- */

interface Cell {
  key: string;
  label: string;
  active: boolean;
  disabled: boolean;
}

const MONTH_CELLS = ['1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'] as const;

const cells = computed<Cell[]>(() => {
  if (props.mode === 'year') {
    const start = windowEnd.value - 11;
    return Array.from({ length: 12 }, (_, index) => {
      const value = String(start + index);
      return {
        key: value,
        label: value,
        active: value === selectedYear.value,
        disabled: Number(value) > maxYear.value,
      };
    });
  }

  return MONTH_CELLS.map((label, index) => {
    const value = `${String(panelYear.value).padStart(4, '0')}-${String(index + 1).padStart(2, '0')}`;
    return {
      key: value,
      label,
      active: value === selectedMonth.value,
      // 字符串比较在这里是安全的：'YYYY-MM' 定宽零填充，字典序 = 时间序
      disabled: value > upperBound.value,
    };
  });
});

const windowLabel = computed(() =>
  props.mode === 'year'
    ? `${windowEnd.value - 11} – ${windowEnd.value}`
    : String(panelYear.value),
);

const canPrevWindow = computed(() =>
  props.mode === 'year' ? windowEnd.value - 12 >= 1 : panelYear.value > 1970,
);

const canNextWindow = computed(() =>
  props.mode === 'year' ? windowEnd.value < maxYear.value : panelYear.value < maxYear.value,
);

function prevWindow(): void {
  if (!canPrevWindow.value) return;
  if (props.mode === 'year') windowEnd.value -= 12;
  else panelYear.value -= 1;
}

function nextWindow(): void {
  if (!canNextWindow.value) return;
  if (props.mode === 'year') windowEnd.value = Math.min(maxYear.value, windowEnd.value + 12);
  else panelYear.value += 1;
}

function pick(cell: Cell): void {
  if (cell.disabled) return;

  if (props.mode === 'year') emit('update:year', cell.key);
  else emit('update:month', cell.key);

  open.value = false;
}

/** 已经就在当期时，这个按钮没有意义，置灰而不是藏起来（藏起来会让人以为不能回） */
const atNow = computed(() =>
  props.mode === 'year' ? selectedYear.value === String(maxYear.value) : selectedMonth.value === thisMonth,
);

function backToNow(): void {
  if (props.mode === 'year') emit('update:year', String(maxYear.value));
  else emit('update:month', thisMonth);
  open.value = false;
}

const alignClass = computed(() =>
  props.align === 'center' ? 'left-1/2 -translate-x-1/2' : props.align === 'end' ? 'right-0' : 'left-0',
);
</script>

<template>
  <div ref="rootRef" class="relative">
    <button
      v-if="!readonly"
      type="button"
      class="inline-flex items-center gap-1 rounded-sm px-2 py-1 text-sm font-semibold text-ink transition-colors duration-200 hover:bg-sunken"
      aria-haspopup="dialog"
      :aria-expanded="open"
      :aria-label="`选择期间，当前 ${label}`"
      @click="toggle"
    >
      {{ label }}
      <ChevronDown :size="14" class="text-ink-muted" aria-hidden="true" />
    </button>

    <span v-else class="inline-block px-2 py-1 text-sm font-semibold text-ink">{{ label }}</span>

    <div
      v-if="open"
      class="pop-in absolute top-full z-[var(--z-sticky)] mt-1 w-[236px] rounded-md border border-line bg-surface p-2"
      :class="alignClass"
      role="dialog"
      :aria-label="mode === 'year' ? '选择年份' : '选择月份'"
    >
      <div class="flex items-center justify-between">
        <button
          type="button"
          :disabled="!canPrevWindow"
          class="grid h-7 w-7 place-items-center rounded-sm text-ink-muted transition-colors duration-200 hover:bg-canvas hover:text-ink disabled:opacity-30 disabled:hover:bg-transparent"
          :aria-label="mode === 'year' ? '往前十二年' : '往前一年'"
          @click="prevWindow"
        >
          <ChevronLeft :size="16" aria-hidden="true" />
        </button>

        <span class="text-xs font-bold tracking-wide text-ink-muted">{{ windowLabel }}</span>

        <button
          type="button"
          :disabled="!canNextWindow"
          class="grid h-7 w-7 place-items-center rounded-sm text-ink-muted transition-colors duration-200 hover:bg-canvas hover:text-ink disabled:opacity-30 disabled:hover:bg-transparent"
          :aria-label="mode === 'year' ? '往后十二年' : '往后一年'"
          @click="nextWindow"
        >
          <ChevronRight :size="16" aria-hidden="true" />
        </button>
      </div>

      <div class="mt-1.5 grid grid-cols-3 gap-1">
        <button
          v-for="cell in cells"
          :key="cell.key"
          type="button"
          :disabled="cell.disabled"
          :aria-pressed="cell.active"
          class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200 disabled:opacity-30"
          :class="
            cell.active
              ? 'bg-primary-fill text-on-primary'
              : 'bg-canvas text-ink-muted hover:text-ink disabled:hover:text-ink-muted'
          "
          @click="pick(cell)"
        >
          {{ cell.label }}
        </button>
      </div>

      <button
        type="button"
        :disabled="atNow"
        class="mt-2 w-full rounded-sm bg-canvas py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40 disabled:hover:text-ink-muted"
        @click="backToNow"
      >
        {{ mode === 'year' ? '回到今年' : '回到本月' }}
      </button>
    </div>
  </div>
</template>
