<script setup lang="ts">
/**
 * 账单导入（微信 / 支付宝 / 本系统导出 CSV）。
 *
 * 解析逻辑全部复用 `utils/bill-parser`（有 16 组单测覆盖）：
 * 该模块负责编码嗅探、表头识别、金额/状态归一、分类与支付方式的**猜测**，
 * 前端这里只做「给用户确认与改的机会」，不重新实现任何解析规则。
 *
 * 为什么不默认全选：猜出来的分类一定有错。让用户扫一眼勾选，
 * 比导进去几百条错分类再一条条改要省事得多。
 */
import { FileUp, Upload } from '@lucide/vue';
import { computed, ref } from 'vue';

import { expenses as expensesApi, type Category, type PaymentMethod } from '@/api';
import { useToast } from '@/composables/useToast';
import { useDictionariesStore } from '@/stores/dictionaries';
import { PBtn, PCard, PEmpty, PSheet, PTag } from '@/ui';
import {
  decodeCsvBuffer,
  detectAndParseBill,
  type BillSource,
  type ParsedBillItem,
} from '@/utils/bill-parser';
import { formatYuan } from '@/utils/money';

defineProps<{ open: boolean }>();
const emit = defineEmits<{ close: []; imported: [] }>();

const dict = useDictionariesStore();
const toast = useToast();

const source = ref<BillSource>('unknown');
const items = ref<ParsedBillItem[]>([]);
const importing = ref(false);
const fileName = ref('');
const preferred = ref<BillSource | ''>('');

/** 所有可选分类（一级 + 二级拍平） */
const flatCategories = computed<Category[]>(() =>
  dict.categories.flatMap((root) => [root, ...root.children]).filter((c) => c.isEnabled),
);

const selectedCount = computed(() => items.value.filter((i) => i.selected).length);
const selectedCents = computed(() =>
  items.value.filter((i) => i.selected).reduce((a, i) => a + i.amountCents, 0),
);

const SOURCE_LABEL: Record<BillSource, string> = {
  wechat: '微信支付账单',
  alipay: '支付宝账单',
  suenmoney: '本系统流水导出',
  unknown: '未识别格式',
};

async function onFile(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const file = input.files?.[0];
  if (!file) return;
  fileName.value = file.name;
  try {
    // 微信/支付宝导出的是 GBK，统一走 decodeCsvBuffer 嗅探编码
    const buf = await file.arrayBuffer();
    const text = decodeCsvBuffer(buf);
    const parsed = detectAndParseBill(
      text,
      dict.categories,
      dict.paymentMethods as PaymentMethod[],
      preferred.value === '' ? undefined : (preferred.value as BillSource),
    );
    source.value = parsed.source;
    items.value = parsed.items.map((i) => ({ ...i, selected: i.direction === 'expense' && i.suggestedCategoryId !== null }));
    if (parsed.totalParsed === 0) toast.show('没解析到任何记录，确认是账单 CSV 吗？');
    else toast.show(`解析 ${parsed.totalParsed} 行，其中支出 ${parsed.expenseCount} 笔`);
  } catch {
    toast.show('文件读取失败');
  } finally {
    input.value = '';
  }
}

function toggleAll(next: boolean): void {
  items.value = items.value.map((i) => (i.direction === 'expense' ? { ...i, selected: next } : i));
}

function setCategory(index: number, id: string): void {
  items.value = items.value.map((item, i) => (i === index ? { ...item, suggestedCategoryId: id } : item));
}

function setPayment(index: number, id: string): void {
  items.value = items.value.map((item, i) => (i === index ? { ...item, suggestedPaymentMethodId: id } : item));
}

async function runImport(): Promise<void> {
  const rows = items.value.filter((i) => i.selected && i.suggestedCategoryId !== null && i.suggestedPaymentMethodId !== null);
  if (rows.length === 0) {
    toast.show('没有可导入的行（需要分类与支付方式都确认）');
    return;
  }
  importing.value = true;
  try {
    const res = await expensesApi.batchCreate(
      rows.map((r) => ({
        amountCents: r.amountCents,
        categoryId: r.suggestedCategoryId as string,
        paymentMethodId: r.suggestedPaymentMethodId as string,
        spendDate: r.spendDate,
        note: r.note,
      })),
    );
    toast.show(`已导入 ${res.createdCount} 笔${res.failed.length > 0 ? `，${res.failed.length} 笔失败` : ''}`);
    items.value = [];
    fileName.value = '';
    emit('imported');
    emit('close');
  } catch {
    toast.show('导入失败，请检查网络后重试');
  } finally {
    importing.value = false;
  }
}
</script>

<template>
  <PSheet :open="open" title="账单导入" @close="emit('close')">
    <PCard>
      <div class="card-h">
        <span class="card-t">选择账单文件</span>
        <span class="card-cap">微信 / 支付宝 / 本系统导出</span>
      </div>
      <div class="split">
        <label class="btn btn--primary" style="cursor: pointer">
          <FileUp :size="14" />
          选择 CSV 文件
          <input type="file" accept=".csv,text/csv" style="display: none" @change="onFile" />
        </label>
        <select v-model="preferred" class="input" style="max-width: 180px" aria-label="账单来源">
          <option value="">自动识别</option>
          <option value="wechat">微信支付</option>
          <option value="alipay">支付宝</option>
          <option value="suenmoney">本系统导出</option>
        </select>
      </div>
      <p class="hint" style="margin-top: 8px">
        微信：我 → 服务 → 钱包 → 账单 → 常见问题 → 下载账单；支付宝：账单 → 开具交易流水。
        文件是 GBK 编码也没关系，会按内容自动嗅探。
      </p>
      <p v-if="fileName" class="tiny muted" style="margin-top: 6px">
        已读取：{{ fileName }} · 识别为 {{ SOURCE_LABEL[source] }}
      </p>
    </PCard>

    <PCard v-if="items.length > 0">
      <div class="card-h">
        <span class="card-t">确认要导入的支出</span>
        <span class="card-cap">已选 {{ selectedCount }} 笔 · {{ formatYuan(selectedCents) }}</span>
      </div>
      <div class="split" style="margin-bottom: 8px">
        <PBtn size="sm" variant="ghost" @click="toggleAll(true)">全选支出</PBtn>
        <PBtn size="sm" variant="ghost" @click="toggleAll(false)">全不选</PBtn>
      </div>

      <div class="import-list">
        <div v-for="(row, i) in items" :key="row.rawIndex" class="import-row">
          <input
            v-model="row.selected"
            type="checkbox"
            :disabled="row.direction !== 'expense'"
            :aria-label="`选择第 ${i + 1} 行`"
          />
          <span class="ir-main">
            <span class="ir-t">{{ row.counterparty || row.description || '—' }}</span>
            <span class="ir-s">{{ row.spendDate }} · {{ row.note }}</span>
          </span>
          <select
            class="input ir-cat"
            :value="row.suggestedCategoryId ?? ''"
            aria-label="分类"
            @change="setCategory(i, ($event.target as HTMLSelectElement).value)"
          >
            <option value="">未选</option>
            <option v-for="c in flatCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
          <select
            class="input ir-pay"
            :value="row.suggestedPaymentMethodId ?? ''"
            aria-label="支付方式"
            @change="setPayment(i, ($event.target as HTMLSelectElement).value)"
          >
            <option value="">未选</option>
            <option v-for="p in dict.usablePaymentMethods" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <span class="ir-amt mono" :class="row.direction === 'income' ? 'pos' : ''">
            {{ formatYuan(row.amountCents) }}
          </span>
          <PTag v-if="row.direction !== 'expense'" tone="dash">{{ row.direction === 'income' ? '收入' : '其他' }}</PTag>
        </div>
      </div>
    </PCard>

    <PEmpty v-else-if="fileName === ''" :icon="Upload">还没有选择文件</PEmpty>

    <template #foot>
      <PBtn variant="primary" :icon="Upload" :disabled="importing || selectedCount === 0" @click="runImport">
        {{ importing ? '导入中…' : `导入 ${selectedCount} 笔` }}
      </PBtn>
      <PBtn variant="ghost" @click="emit('close')">取消</PBtn>
    </template>
  </PSheet>
</template>

<style scoped>
.import-list {
  max-height: 46vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.import-row {
  display: grid;
  grid-template-columns: 18px minmax(0, 1fr) 110px 110px 88px auto;
  gap: 8px;
  align-items: center;
  padding: 6px 2px;
  border-bottom: 1px solid var(--line);
}
.ir-main {
  min-width: 0;
}
.ir-t {
  display: block;
  font-size: 12.5px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ir-s {
  display: block;
  font-size: 10.5px;
  color: var(--ink-3);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ir-cat,
.ir-pay {
  min-height: 30px;
  padding: 3px 6px;
  font-size: 11.5px;
}
.ir-amt {
  text-align: right;
  font-size: 12.5px;
  font-weight: 600;
}
@media (max-width: 860px) {
  .import-row {
    grid-template-columns: 18px minmax(0, 1fr) auto;
    row-gap: 4px;
  }
  .ir-cat,
  .ir-pay {
    grid-column: span 1;
  }
}
</style>
