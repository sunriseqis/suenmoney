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

import { ApiError, categories as categoriesApi, expenses as expensesApi, paymentMethods as paymentMethodsApi, type Category } from '@/api';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useUiStore } from '@/stores/ui';
import {
  decodeCsvBuffer,
  detectAndParseBill,
  detectBillSource,
  type ParsedBillItem,
  type ParseBillResult,
} from '@/utils/bill-parser';
import { decidePlacement } from '@/utils/category-placement';
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

// 部分失败提示：服务端已改为逐条容错，成功部分照常落库、失败行被跳过。
// 只报「成功导入 N 笔」会让用户察觉不到少了几笔，也无法追溯是哪几行，故单独留一个提示块。
const importNotice = ref<{
  createdCount: number;
  failures: Array<{ label: string; reason: string }>;
} | null>(null);

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
      importNotice.value = null;
      provisionNotice.value = null;
      provisionPlan.value = null;
      provisionDismissed.value = false;
      selectedSource.value = 'wechat';
      return;
    }
    await dict.load();
    initDefaults();
  },
  { immediate: true },
);

/**
 * 「缺就建」：对账 CSV 里出现的分类与支付方式，本地没有时经用户确认后自动创建。
 *
 * 预设分类/支付方式已移除，全新部署就是空库 —— 靠这一步让导入自给自足。
 * 只对 suenmoney 对账来源生效：只有它携带真实的分类名与账户名；
 * 微信/支付宝来源的原始文本是「商家名 + 渠道串」，建出来的是垃圾。
 * 流程：解析 → 列出缺失清单并弹确认 → 创建 → 就地刷新预览（不用关窗重导）。
 * 同批同名只创建一次；二级名已存在（哪怕挂在别的一级下）直接认领，
 * 不再重复建出同名的一级/二级两份。
 */

interface ProvisionPlan {
  categories: Array<{ parent: string; child: string }>;
  methods: string[];
}

const provisionPlan = ref<ProvisionPlan | null>(null);
const provisionDismissed = ref(false);
const provisionBusy = ref(false);
const provisionNotice = ref<string | null>(null);

function computeProvisionPlan(result: ParseBillResult): void {
  if (result.source !== 'suenmoney' || provisionDismissed.value) {
    provisionPlan.value = null;
    return;
  }

  const catMap = new Map<string, { parent: string; child: string }>();
  const methodSet = new Set<string>();
  for (const item of result.items) {
    if (item.suggestedCategoryId === null) {
      const parent = (item.categoryParentName ?? '').trim();
      const child = (item.categoryChildName ?? '').trim();
      if (parent !== '' || child !== '') {
        const key = `${parent}|${child}`;
        if (!catMap.has(key)) catMap.set(key, { parent, child });
      }
    }
    if (item.suggestedPaymentMethodId === null && item.paymentMethodRaw !== '') {
      methodSet.add(item.paymentMethodRaw);
    }
  }

  const plan = { categories: [...catMap.values()], methods: [...methodSet] };
  provisionPlan.value = plan.categories.length > 0 || plan.methods.length > 0 ? plan : null;
}

async function confirmProvision(): Promise<void> {
  const plan = provisionPlan.value;
  if (plan === null || provisionBusy.value) return;

  provisionBusy.value = true;
  errorMessage.value = null;
  try {
    // 现有体系快照，创建过程就地更新 —— 同批同名只建一次
    const roots = new Map<string, string>(); // 一级名 → id
    const children = new Map<string, string>(); // 二级名 → id
    const methods = new Map<string, string>(); // 支付方式名 → id
    const rootNameById = new Map<string, string>(); // 一级 id → 名
    for (const c of dict.categories) {
      if (c.parentId === null) {
        roots.set(c.name, c.id);
        rootNameById.set(c.id, c.name);
      } else {
        children.set(c.name, c.id);
      }
    }
    for (const m of dict.paymentMethods) methods.set(m.name, m.id);

    // 证据集合：现有字典里的一级/二级名 + **本批计划里同时有 parent 与 child 的项**。
    // 后者是关键 —— 同一批数据里完整填了两列的行，能提供「叶子 → 父级」的父子关系，
    // 用来纠正那些「二级分类」为空、叶子名直接写进「分类」列的行，避免误建一堆一级分类。
    const knownRoots = new Set<string>();
    const knownChildren = new Set<string>();
    const knownChildToParent = new Map<string, string>();
    for (const c of dict.categories) {
      if (c.parentId === null) {
        knownRoots.add(c.name);
      } else {
        knownChildren.add(c.name);
        const parentName = rootNameById.get(c.parentId);
        if (parentName !== undefined) knownChildToParent.set(c.name, parentName);
      }
    }
    for (const { parent, child } of plan.categories) {
      if (parent !== '' && child !== '') {
        knownRoots.add(parent);
        knownChildren.add(child);
        knownChildToParent.set(child, parent);
      }
    }

    let createdCategories = 0;
    let createdMethods = 0;
    const resolved = new Map<string, string>(); // 'parent|child' → categoryId
    // 因「完全没有任何层级证据」而兜底建成一级的名字，收集起来在完成提示里告知用户
    const fallbackRoots = new Set<string>();

    const ensureRoot = async (name: string): Promise<string> => {
      let id = roots.get(name);
      if (id === undefined) {
        const created = await categoriesApi.create({ name });
        id = created.category.id;
        roots.set(name, id);
        createdCategories += 1;
      }
      return id;
    };

    const ensureChild = async (parentId: string, name: string): Promise<string> => {
      // 二级名已存在（哪怕挂在别的一级下）直接认领，避免同名两份
      let id = children.get(name);
      if (id === undefined) {
        const created = await categoriesApi.create({ name, parentId });
        id = created.category.id;
        children.set(name, id);
        createdCategories += 1;
      }
      return id;
    };

    for (const { parent, child } of plan.categories) {
      const key = `${parent}|${child}`;
      if (resolved.has(key)) continue;

      // 按证据推断落位：能认领就认领、能证明是二级就挂到父下、否则才兜底建一级
      const placement = decidePlacement({
        parent,
        child,
        knownChildToParent,
        knownRoots,
        knownChildren,
      });

      if (placement.kind === 'existing') {
        const id = children.get(placement.categoryName) ?? roots.get(placement.categoryName);
        if (id !== undefined) {
          resolved.set(key, id);
          continue;
        }
        // 名字有证据但库里尚未存在（证据仅来自本批数据）：按证据落到父下，否则建根
        const evidenceParent = knownChildToParent.get(placement.categoryName);
        if (evidenceParent !== undefined) {
          resolved.set(key, await ensureChild(await ensureRoot(evidenceParent), placement.categoryName));
        } else {
          resolved.set(key, await ensureRoot(placement.categoryName));
        }
        continue;
      }

      if (placement.kind === 'createChild') {
        resolved.set(key, await ensureChild(await ensureRoot(placement.parentName), placement.childName));
        continue;
      }

      // createRoot：没有任何证据，只能建一级 —— 记下来让用户知晓并去设置里手改
      fallbackRoots.add(placement.name);
      resolved.set(key, await ensureRoot(placement.name));
    }

    for (const name of plan.methods) {
      if (methods.has(name)) continue;
      // 名称含信用卡字样按信用卡建（默认 1 日出账 / 10 日还款，可在设置中调整账期）；
      // 其余一律储蓄卡 —— 与其猜一个错的账期，不如给一个能改的起点
      const isCredit = /信用卡|贷记|花呗/.test(name);
      const created = await paymentMethodsApi.create({
        name,
        type: isCredit ? 'credit' : 'cash',
        ...(isCredit ? { billingDay: 1, repaymentDay: 10 } : {}),
      });
      methods.set(name, created.paymentMethod.id);
      createdMethods += 1;
    }

    // 先强制刷新字典，再重建预览行 —— 顺序不能反：分类下拉（allSelectableCategories）
    // 是从 dict 计算出来的，字典没刷进来时新建的分类 id 不在选项里，行会显示成空白「无分类」。
    await dict.load(true);

    // 回填解析结果并重建预览行 —— 不再需要关掉窗口重导
    const result = parseResult.value;
    if (result !== null) {
      for (const item of result.items) {
        if (item.suggestedCategoryId === null) {
          const parent = (item.categoryParentName ?? '').trim();
          const child = (item.categoryChildName ?? '').trim();
          const id = resolved.get(`${parent}|${child}`);
          if (id !== undefined) item.suggestedCategoryId = id;
        }
        if (item.suggestedPaymentMethodId === null && item.paymentMethodRaw !== '') {
          const id = methods.get(item.paymentMethodRaw);
          if (id !== undefined) item.suggestedPaymentMethodId = id;
        }
      }
      buildRows(result);
    }

    let noticeText =
      `已新建分类 ${createdCategories} 个、支付方式 ${createdMethods} 个` +
      (createdMethods > 0 ? '（新建信用卡默认 1日出账/10日还款，可在设置中调整账期）' : '');
    if (fallbackRoots.size > 0) {
      noticeText +=
        `；另有 ${fallbackRoots.size} 个名字缺少层级信息，已按一级创建：` +
        `${[...fallbackRoots].join('、')}，可在设置中调整到正确的一级分类下`;
    }
    provisionNotice.value = noticeText;
    provisionPlan.value = null;
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '自动创建失败，请手动指定分类与支付方式';
  } finally {
    provisionBusy.value = false;
  }
}

function dismissProvision(): void {
  provisionDismissed.value = true;
  provisionPlan.value = null;
}

function buildRows(result: ParseBillResult): void {
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
}

function runParse(source: 'wechat' | 'alipay' | 'suenmoney'): void {
  if (!rawCsvText.value) return;
  try {
    const result = detectAndParseBill(rawCsvText.value, allFlatCategories.value, dict.usablePaymentMethods, source);
    if (result.totalParsed === 0) {
      throw new ApiError(0, '未在文件中检测到有效的交易记录，请检查格式选择是否与文件一致。');
    }
    parseResult.value = result;
    buildRows(result);
    computeProvisionPlan(result);
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : '文件解析失败';
    parseResult.value = null;
    rows.value = [];
    provisionPlan.value = null;
  }
}

function changeSource(s: 'wechat' | 'alipay' | 'suenmoney'): void {
  selectedSource.value = s;
  errorMessage.value = null;
  provisionNotice.value = null;
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
  provisionNotice.value = null;
  provisionDismissed.value = false;
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
  importNotice.value = null;

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
    // 提交顺序与 selectedRows 一一对应，服务端回来的是同一数组的下标
    const targetRows = selectedRows.value;
    const payload = targetRows.map((r) => ({
      amountCents: r.amountCents,
      categoryId: r.categoryId!,
      paymentMethodId: r.paymentMethodId!,
      spendDate: r.spendDate,
      note: r.note.slice(0, 200),
    }));

    const result = await expensesApi.batchCreate(payload);

    // 新建的分类/支付方式只在服务端，客户端字典是带缓存的（loaded 为真时 load() 直接 return）。
    // 导入成功后强制刷新一次，否则列表侧拿着旧字典渲染，新导入的流水会显示成「未分类」。
    await dict.load(true);

    // 成功的那部分必须照常生效：即便有行被跳过，也不能把整批当失败。
    // 本项目导入是幂等的（重复导入不会产生重复数据），但若整体报失败，用户会以为一笔没进
    // 而重导一遍，白白多一次操作；况且成功的笔数确已落库，父组件/列表侧必须收到通知去刷新。
    ui.markDataChanged();
    emit('imported', result.createdCount);

    if (result.failed.length === 0) {
      emit('close');
      return;
    }

    // 有失败行时不直接关窗：留在弹窗里逐条交代「哪几行没进、为什么」。
    // index 是提交数组下标，映射回选中的行给出人看得懂的口径（第 N 笔 + 日期 + 金额 + 对手方）。
    importNotice.value = {
      createdCount: result.createdCount,
      failures: result.failed.map((f) => {
        const row = targetRows[f.index];
        const label =
          row === undefined
            ? `第 ${f.index + 1} 笔`
            : `第 ${f.index + 1} 笔 · ${row.spendDate} · ${formatYuan(row.amountCents)} · ${row.note || row.counterparty || '—'}`;
        return { label, reason: f.reason };
      }),
    };
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

        <!-- 「缺就建」确认：列出将自动创建的分类与支付方式 -->
        <div v-if="provisionPlan !== null" class="mb-4 rounded-sm bg-primary/10 p-3 text-xs text-primary-text">
          <p class="font-semibold">检测到本机不存在的分类 / 支付方式：</p>
          <p class="mt-1 leading-relaxed break-all">
            <template v-if="provisionPlan.categories.length > 0">分类：{{ provisionPlan.categories.map((c) => (c.child !== '' && c.child !== c.parent) ? `${c.parent} · ${c.child}` : c.parent || c.child).join('、') }}</template>
            <template v-if="provisionPlan.categories.length > 0 && provisionPlan.methods.length > 0">；</template>
            <template v-if="provisionPlan.methods.length > 0">支付方式：{{ provisionPlan.methods.join('、') }}</template>
          </p>
          <div class="mt-2 flex items-center gap-3">
            <button
              type="button"
              :disabled="provisionBusy"
              class="rounded-sm bg-primary-fill px-3 py-1.5 font-bold text-on-primary transition-opacity hover:opacity-90 disabled:opacity-40"
              @click="confirmProvision"
            >
              {{ provisionBusy ? '创建中…' : '自动创建并填入' }}
            </button>
            <button
              type="button"
              class="font-semibold text-ink-muted hover:text-ink"
              @click="dismissProvision"
            >
              不创建，手动指定
            </button>
          </div>
        </div>

        <!-- 「缺就建」完成提示 -->
        <p v-if="provisionNotice !== null" class="mb-4 rounded-sm bg-primary/10 p-3 text-xs text-primary-text">
          {{ provisionNotice }}
        </p>

        <!-- 部分失败提示：成功部分已入账，被跳过的行逐条列出（最多 5 条） -->
        <div
          v-if="importNotice !== null"
          class="mb-4 rounded-sm bg-accent/10 p-3 text-xs text-accent-text"
        >
          <p class="font-semibold">
            已成功导入 {{ importNotice.createdCount }} 笔，另有
            {{ importNotice.failures.length }} 笔被跳过（未入账）。
          </p>
          <ul class="mt-1 space-y-0.5 leading-relaxed">
            <li v-for="(f, i) in importNotice.failures.slice(0, 5)" :key="i" class="break-all">
              {{ f.label }}：{{ f.reason }}
            </li>
          </ul>
          <p v-if="importNotice.failures.length > 5" class="mt-1">
            其余略，等 {{ importNotice.failures.length }} 笔。
          </p>
        </div>

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
