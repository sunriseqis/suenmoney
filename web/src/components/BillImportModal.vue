<script setup lang="ts">
/**
 * 微信 / 支付宝账单 CSV 解析与导入弹窗。
 *
 * 流程：
 * 1. 上传微信或支付宝导出的 CSV 账单文件；
 * 2. 自动探测编码（GBK / UTF-8）与来源（微信支付 / 支付宝）；
 * 3. 智能解析交易明细，利用关键词规则预先推荐二级分类与支付渠道；
 * 4. 用户可在界面批量调整默认分类与支付方式，勾选需入账的明细；
 * 5. 校验无误后一键批量提交入库（走单次数据库事务，高速原子生效）。
 */
import { computed, ref, watch } from 'vue';
import { Check, Upload, X } from '@lucide/vue';

import { ApiError, expenses as expensesApi, type Category } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useUiStore } from '@/stores/ui';
import {
  decodeCsvBuffer,
  detectAndParseBill,
  detectBillSource,
  type ParsedBillItem,
  type ParseBillResult,
} from '@/utils/bill-parser';
import { formatYuan } from '@/utils/money';

import ChipButton from './ChipButton.vue';

const props = defineProps<{
  open: boolean;
}>();

const emit = defineEmits<{
  close: [];
  imported: [count: number];
}>();

const dict = useDictionariesStore();
const ui = useUiStore();

const fileInput = ref<HTMLInputElement | null>(null);
const file = ref<File | null>(null);
const rawCsvText = ref<string | null>(null);
const selectedSource = ref<'wechat' | 'alipay' | 'suenmoney'>('wechat');
const parsing = ref(false);
const importing = ref(false);
const errorMessage = ref<string | null>(null);

const parseResult = ref<ParseBillResult | null>(null);
const filterDirection = ref<'all' | 'expense' | 'income'>('expense');

// 批量兜底与配置
const defaultCategoryId = ref<string | null>(null);
const defaultPaymentMethodId = ref<string | null>(null);

// 可编辑的明细行封装
interface EditableBillRow {
  rawIndex: number;
  spendDate: string;
  direction: 'expense' | 'income' | 'other';
  amountCents: number;
  amountYuan: string;
  counterparty: string;
  description: string;
  paymentMethodRaw: string;
  note: string;
  categoryId: string | null;
  paymentMethodId: string | null;
  selected: boolean;
}

const rows = ref<EditableBillRow[]>([]);

const allSelectableCategories = computed(() => {
  const list: Array<{ id: string; name: string }> = [];
  for (const root of dict.rootCategories) {
    const children = dict.selectableChildren(root);
    for (const child of children) {
      list.push({
        id: child.id,
        name: child.parentId ? `${root.name} · ${child.name}` : child.name,
      });
    }
  }
  return list;
});

const allFlatCategories = computed(() => {
  const list: Category[] = [];
  for (const root of dict.categories) {
    list.push(root);
    for (const child of root.children) {
      list.push(child);
    }
  }
  return list;
});

function initDefaults(): void {
  defaultCategoryId.value = allSelectableCategories.value[0]?.id ?? null;
  defaultPaymentMethodId.value = dict.usablePaymentMethods[0]?.id ?? null;
}

watch(
  () => props.open,
  async (isOpen) => {
    if (!isOpen) {
      file.value = null;
      rawCsvText.value = null;
      parseResult.value = null;
      rows.value = [];
      errorMessage.value = null;
      selectedSource.value = 'wechat';
      return;
    }
    await dict.load();
    initDefaults();
  },
  { immediate: true },
);

function runParse(source: 'wechat' | 'alipay' | 'suenmoney'): void {
  if (!rawCsvText.value) return;
  try {
    const result = detectAndParseBill(rawCsvText.value, allFlatCategories.value, dict.usablePaymentMethods, source);
    if (result.totalParsed === 0) {
      throw new ApiError(0, '未在文件中检测到有效的交易记录，请检查格式选择是否与文件一致。');
    }
    parseResult.value = result;
    rows.value = result.items.map((item: ParsedBillItem) => {
      const categoryId = item.suggestedCategoryId ?? defaultCategoryId.value;
      const paymentMethodId = item.suggestedPaymentMethodId ?? defaultPaymentMethodId.value;

      return {
        rawIndex: item.rawIndex,
        spendDate: item.spendDate,
        direction: item.direction,
        amountCents: item.amountCents,
        amountYuan: item.amountYuan,
        counterparty: item.counterparty,
        description: item.description,
        paymentMethodRaw: item.paymentMethodRaw,
        note: item.note,
        categoryId,
        paymentMethodId,
        selected: item.direction === 'expense',
      };
    });
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '文件解析失败';
    parseResult.value = null;
    rows.value = [];
  }
}

function changeSource(s: 'wechat' | 'alipay' | 'suenmoney'): void {
  selectedSource.value = s;
  errorMessage.value = null;
  if (rawCsvText.value) {
    runParse(s);
  }
}

async function onFileSelected(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  if (!input.files || input.files.length === 0) return;
  const picked = input.files[0]!;
  input.value = '';

  file.value = picked;
  errorMessage.value = null;
  parsing.value = true;

  try {
    const buffer = await picked.arrayBuffer();
    const text = decodeCsvBuffer(buffer);
    rawCsvText.value = text;

    const detected = detectBillSource(text);
    if (detected !== 'unknown') {
      selectedSource.value = detected;
    }

    runParse(selectedSource.value);
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '文件解析失败';
    parseResult.value = null;
    rows.value = [];
  } finally {
    parsing.value = false;
  }
}

// 筛选行列表
const displayedRows = computed(() => {
  if (filterDirection.value === 'all') return rows.value;
  return rows.value.filter((r) => r.direction === filterDirection.value);
});

// 已勾选统计
const selectedRows = computed(() => rows.value.filter((r) => r.selected));
const selectedCount = computed(() => selectedRows.value.length);
const selectedTotalCents = computed(() =>
  selectedRows.value.reduce((sum, r) => sum + r.amountCents, 0),
);

// 全选 / 全不选
const allDisplayedSelected = computed(
  () =>
    displayedRows.value.length > 0 &&
    displayedRows.value.every((r) => r.selected),
);

function toggleSelectAll(): void {
  const target = !allDisplayedSelected.value;
  for (const row of displayedRows.value) {
    row.selected = target;
  }
}

// 应用默认分类到所有勾选行
function applyDefaultCategoryToSelected(): void {
  if (!defaultCategoryId.value) return;
  for (const row of selectedRows.value) {
    row.categoryId = defaultCategoryId.value;
  }
}

// 应用默认支付方式到所有勾选行
function applyDefaultPaymentMethodToSelected(): void {
  if (!defaultPaymentMethodId.value) return;
  for (const row of selectedRows.value) {
    row.paymentMethodId = defaultPaymentMethodId.value;
  }
}

async function doImport(): Promise<void> {
  if (selectedCount.value === 0 || importing.value) return;

  errorMessage.value = null;

  // 校验所有选中的行是否具备分类和支付方式
  const missingCategoryIndex = selectedRows.value.findIndex((r) => !r.categoryId);
  if (missingCategoryIndex !== -1) {
    errorMessage.value = `第 ${missingCategoryIndex + 1} 笔选中的记录未指定分类，请为其选择分类。`;
    return;
  }

  const missingMethodIndex = selectedRows.value.findIndex((r) => !r.paymentMethodId);
  if (missingMethodIndex !== -1) {
    errorMessage.value = `第 ${missingMethodIndex + 1} 笔选中的记录未指定支付方式，请为其选择支付方式。`;
    return;
  }

  importing.value = true;
  try {
    const payload = selectedRows.value.map((r) => ({
      amountCents: r.amountCents,
      categoryId: r.categoryId!,
      paymentMethodId: r.paymentMethodId!,
      spendDate: r.spendDate,
      note: r.note.slice(0, 200),
    }));

    const result = await expensesApi.batchCreate(payload);
    ui.markDataChanged();
    emit('imported', result.createdCount);
    emit('close');
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '批量导入失败，请重试';
  } finally {
    importing.value = false;
  }
}

function close(): void {
  if (importing.value) return;
  emit('close');
}
</script>

<template>
  <div v-if="open" class="fixed inset-0 z-[var(--z-sheet)] flex items-center justify-center p-3 sm:p-6">
    <!-- 遮罩 -->
    <button
      type="button"
      class="absolute inset-0 h-full w-full cursor-default bg-[var(--scrim)]"
      aria-label="关闭"
      @click="close"
    />

    <!-- 面板容器 -->
    <div
      class="relative z-10 flex h-[90vh] w-full max-w-4xl flex-col rounded-md bg-surface shadow-2xl"
      role="dialog"
      aria-modal="true"
    >
      <!-- 顶栏 -->
      <header class="flex items-center justify-between border-b border-line px-4 py-3 sm:px-6">
        <h2 class="text-base font-bold text-ink">导入流水</h2>

        <button
          type="button"
          class="rounded-sm p-1 text-ink-muted hover:bg-sunken hover:text-ink"
          @click="close"
        >
          <X class="h-5 w-5" />
        </button>
      </header>

      <!-- 主体内容 -->
      <div class="flex-1 overflow-y-auto px-4 py-4 sm:px-6">
        <!-- 来源格式切换器（微信 / 支付宝 / suenmoney） -->
        <div class="mb-4 grid grid-cols-3 gap-2 rounded-md bg-canvas p-1">
          <button
            v-for="s in ['wechat', 'alipay', 'suenmoney'] as const"
            :key="s"
            type="button"
            class="rounded-xs py-2 text-xs font-semibold transition-colors"
            :class="
              selectedSource === s
                ? 'bg-surface text-ink font-bold shadow-xs'
                : 'text-ink-muted hover:text-ink'
            "
            @click="changeSource(s)"
          >
            {{ s === 'wechat' ? '微信' : s === 'alipay' ? '支付宝' : 'suenmoney' }}
          </button>
        </div>

        <!-- 错误提示 -->
        <p v-if="errorMessage !== null" class="mb-4 rounded-sm bg-danger/10 p-3 text-xs text-danger-text">
          {{ errorMessage }}
        </p>

        <!-- 步骤 1：未选择文件或重新上传 -->
        <div
          v-if="parseResult === null"
          class="flex flex-col items-center justify-center rounded-md border-2 border-dashed border-line bg-canvas p-10 text-center transition-colors hover:border-primary/50"
        >
          <Upload class="h-10 w-10 text-ink-muted opacity-60" />
          <p class="mt-3 text-sm font-semibold text-ink">
            {{ selectedSource === 'wechat' ? '选择微信支付 CSV 账单' : selectedSource === 'alipay' ? '选择支付宝 CSV 账单' : '选择 suenmoney CSV 流水文件' }}
          </p>

          <button
            type="button"
            :disabled="parsing"
            class="mt-5 rounded-sm bg-primary-fill px-5 py-2.5 text-xs font-bold text-on-primary transition-opacity hover:opacity-90 disabled:opacity-50"
            @click="fileInput?.click()"
          >
            {{ parsing ? '正在解析账单…' : '选择 CSV 文件' }}
          </button>
          <input
            ref="fileInput"
            type="file"
            accept=".csv,text/csv"
            class="sr-only"
            @change="onFileSelected"
          />
        </div>

        <!-- 步骤 2：解析结果与配置配置预览 -->
        <div v-else class="space-y-4">
          <!-- 识别概况横幅 -->
          <div class="flex flex-wrap items-center justify-between gap-3 rounded-md bg-canvas p-3.5 text-xs">
            <div class="flex flex-wrap items-center gap-2">
              <span
                class="rounded-xs px-2 py-0.5 font-bold"
                :class="
                  selectedSource === 'wechat'
                    ? 'bg-[#07C160]/10 text-[#07C160]'
                    : selectedSource === 'alipay'
                      ? 'bg-[#1677FF]/10 text-[#1677FF]'
                      : 'bg-primary/10 text-primary'
                "
              >
                {{ selectedSource === 'wechat' ? '微信支付账单' : selectedSource === 'alipay' ? '支付宝交易记录' : 'suenmoney 流水' }}
              </span>
              <span class="text-ink">
                共识别 <strong>{{ parseResult.totalParsed }}</strong> 笔
                （支出 {{ parseResult.expenseCount }} · 收入 {{ parseResult.incomeCount }} · 其他 {{ parseResult.otherCount }}）
              </span>
            </div>

            <button
              type="button"
              class="text-xs text-primary hover:underline"
              @click="fileInput?.click()"
            >
              重新上传文件
            </button>
            <input
              ref="fileInput"
              type="file"
              accept=".csv,text/csv"
              class="sr-only"
              @change="onFileSelected"
            />
          </div>

          <!-- 批量快捷配置栏 -->
          <div class="rounded-md border border-line bg-canvas p-3.5">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <span class="text-xs font-bold text-ink">批量分配已选记录：</span>

              <div class="flex flex-wrap items-center gap-3">
                <!-- 批量设分类 -->
                <div class="flex items-center gap-1.5 text-xs">
                  <span class="text-ink-muted">默认分类：</span>
                  <select
                    v-model="defaultCategoryId"
                    class="rounded-sm bg-surface px-2 py-1 text-xs text-ink outline-none"
                    @change="applyDefaultCategoryToSelected"
                  >
                    <option v-for="cat in allSelectableCategories" :key="cat.id" :value="cat.id">
                      {{ cat.name }}
                    </option>
                  </select>
                </div>

                <!-- 批量设支付方式 -->
                <div class="flex items-center gap-1.5 text-xs">
                  <span class="text-ink-muted">默认支付方式：</span>
                  <select
                    v-model="defaultPaymentMethodId"
                    class="rounded-sm bg-surface px-2 py-1 text-xs text-ink outline-none"
                    @change="applyDefaultPaymentMethodToSelected"
                  >
                    <option v-for="m in dict.usablePaymentMethods" :key="m.id" :value="m.id">
                      {{ m.name }}
                    </option>
                  </select>
                </div>
              </div>
            </div>
          </div>

          <!-- 过滤标签与全选按钮 -->
          <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
            <div class="flex items-center gap-2">
              <ChipButton :active="filterDirection === 'expense'" @click="filterDirection = 'expense'">
                支出 ({{ parseResult.expenseCount }})
              </ChipButton>
              <ChipButton :active="filterDirection === 'all'" @click="filterDirection = 'all'">
                全部 ({{ parseResult.totalParsed }})
              </ChipButton>
              <ChipButton :active="filterDirection === 'income'" @click="filterDirection = 'income'">
                收入 ({{ parseResult.incomeCount }})
              </ChipButton>
            </div>

            <button
              type="button"
              class="text-xs font-semibold text-primary hover:underline"
              @click="toggleSelectAll"
            >
              {{ allDisplayedSelected ? '取消当前全选' : '全选当前列表' }}
            </button>
          </div>

          <!-- 明细预览列表 -->
          <div class="overflow-x-auto rounded-sm border border-line">
            <table class="w-full text-left text-xs">
              <thead class="border-b border-line bg-canvas text-ink-muted">
                <tr>
                  <th class="w-10 px-3 py-2 text-center">
                    <input
                      type="checkbox"
                      :checked="allDisplayedSelected"
                      class="rounded-xs"
                      @change="toggleSelectAll"
                    />
                  </th>
                  <th class="w-24 px-2 py-2">消费日期</th>
                  <th class="px-2 py-2">交易对方 / 备注</th>
                  <th class="w-24 px-2 py-2 text-right">金额</th>
                  <th class="w-32 px-2 py-2">分类</th>
                  <th class="w-32 px-2 py-2">支付方式</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-line/50">
                <tr
                  v-for="row in displayedRows"
                  :key="row.rawIndex"
                  class="transition-colors hover:bg-sunken/40"
                  :class="row.selected ? '' : 'opacity-40'"
                >
                  <td class="px-3 py-2.5 text-center">
                    <input
                      v-model="row.selected"
                      type="checkbox"
                      class="rounded-xs"
                    />
                  </td>
                  <td class="whitespace-nowrap px-2 py-2.5 text-ink-muted">
                    {{ row.spendDate }}
                  </td>
                  <td class="max-w-[220px] px-2 py-2.5">
                    <p class="truncate font-medium text-ink" :title="row.note">
                      {{ row.note || '—' }}
                    </p>
                    <p v-if="row.paymentMethodRaw" class="truncate text-[10px] text-ink-muted">
                      渠道：{{ row.paymentMethodRaw }}
                    </p>
                  </td>
                  <td class="whitespace-nowrap px-2 py-2.5 text-right font-bold text-ink">
                    {{ formatYuan(row.amountCents) }}
                  </td>
                  <td class="px-2 py-2.5">
                    <select
                      v-model="row.categoryId"
                      class="w-full rounded-xs bg-canvas px-1.5 py-1 text-xs text-ink outline-none"
                    >
                      <option v-for="cat in allSelectableCategories" :key="cat.id" :value="cat.id">
                        {{ cat.name }}
                      </option>
                    </select>
                  </td>
                  <td class="px-2 py-2.5">
                    <select
                      v-model="row.paymentMethodId"
                      class="w-full rounded-xs bg-canvas px-1.5 py-1 text-xs text-ink outline-none"
                    >
                      <option v-for="m in dict.usablePaymentMethods" :key="m.id" :value="m.id">
                        {{ m.name }}
                      </option>
                    </select>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- 底栏 -->
      <footer class="flex items-center justify-between border-t border-line px-4 py-3 sm:px-6">
        <div class="text-xs text-ink-muted">
          <span v-if="parseResult !== null">
            已选择 <strong class="text-ink">{{ selectedCount }}</strong> 笔 ·
            合计 <strong class="text-accent-text">{{ formatYuan(selectedTotalCents) }}</strong>
          </span>
          <span v-else>
            请先选择 CSV 账单文件
          </span>
        </div>

        <div class="flex items-center gap-2">
          <button
            type="button"
            class="rounded-sm border border-line px-3 py-1.5 text-xs font-semibold text-ink-muted hover:text-ink"
            @click="close"
          >
            取消
          </button>
          <button
            type="button"
            :disabled="selectedCount === 0 || importing"
            class="inline-flex items-center gap-1.5 rounded-sm bg-primary-fill px-4 py-1.5 text-xs font-bold text-on-primary transition-opacity hover:opacity-90 disabled:opacity-40"
            @click="doImport"
          >
            <Check v-if="!importing" class="h-3.5 w-3.5" />
            <span>{{ importing ? '正在导入中…' : `确认导入 ${selectedCount} 笔` }}</span>
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>
