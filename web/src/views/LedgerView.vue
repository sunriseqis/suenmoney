<script setup lang="ts">
/**
 * 流水页。
 *
 * 分页用服务端的**键集游标**而不是页码：并发写入时页码分页会让第二页
 * 重复或漏掉记录（前一行被删掉，后面所有行往前挪一位）。
 * 这里只负责把 `nextCursor` 原样回传。
 */
import { computed, onMounted, ref, watch } from 'vue';

import { ApiError, expenses as expensesApi, type Expense } from '@/api';
import CategoryIcon from '@/components/CategoryIcon.vue';
import ChipButton from '@/components/ChipButton.vue';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useUiStore } from '@/stores/ui';
import {
  currentMonth,
  formatDayLabel,
  formatMonthDay,
  formatMonthLabel,
  shiftMonth,
  todayLocal,
  weekdayOf,
} from '@/utils/dates';
import { formatYuan } from '@/utils/money';

const ui = useUiStore();
const dict = useDictionariesStore();

const month = ref(currentMonth());
const categoryId = ref<string | null>(null);
const paymentMethodId = ref<string | null>(null);
const keyword = ref('');

const items = ref<Expense[]>([]);
const nextCursor = ref<string | null>(null);
const hasMore = ref(false);
const loading = ref(false);
const loadingMore = ref(false);
const errorMessage = ref<string | null>(null);

/** 列表内合计。不是报表的权威数字（那由服务端算），只是「当前这一屏加起来多少」 */
const loadedTotal = computed(() =>
  items.value.reduce((sum, item) => sum + item.amountCents, 0),
);

async function fetchPage(cursor: string | null): Promise<void> {
  const page = await expensesApi.list({
    month: month.value,
    categoryId: categoryId.value ?? undefined,
    paymentMethodId: paymentMethodId.value ?? undefined,
    q: keyword.value.trim() === '' ? undefined : keyword.value.trim(),
    limit: 50,
    cursor: cursor ?? undefined,
  });

  items.value = cursor === null ? page.items : [...items.value, ...page.items];
  nextCursor.value = page.nextCursor;
  hasMore.value = page.hasMore;
}

async function reload(): Promise<void> {
  loading.value = true;
  errorMessage.value = null;
  try {
    await fetchPage(null);
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '加载失败';
  } finally {
    loading.value = false;
  }
}

async function loadMore(): Promise<void> {
  if (!hasMore.value || loadingMore.value || nextCursor.value === null) return;

  loadingMore.value = true;
  try {
    await fetchPage(nextCursor.value);
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '加载更多失败';
  } finally {
    loadingMore.value = false;
  }
}

onMounted(async () => {
  await dict.load();
  await reload();
});

watch([month, categoryId, paymentMethodId], reload);
watch(() => ui.dataVersion, reload);

/**
 * 关键词搜索做 300ms 防抖。
 * 不防抖的话每敲一个字就发一次请求，而账本里几百条记录的模糊匹配
 * 会让服务端和界面都在做无意义的功。
 */
let searchTimer: ReturnType<typeof setTimeout> | undefined;
watch(keyword, () => {
  if (searchTimer !== undefined) clearTimeout(searchTimer);
  searchTimer = setTimeout(() => void reload(), 300);
});

const today = todayLocal();
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+24px)]">
    <!--
      桌面：内容收成阅读栏（lg:max-w-3xl = 768px），不跟着外壳铺到 1120px。

      一开始我按「全宽对账单」做，结果分类名和金额之间空了约 600px ——
      因为这一行只有「日期 / 图标 / 文字 / 金额」四段，文字段是弹性的，
      多出来的宽度全变成空档，眼睛要从左边一路扫到最右才能对上金额。

      表格要宽，得靠**增加列**去填（备注一列、支付方式一列、还款日一列），
      而不是把四段摊开。那是一次独立的改造：行结构要从两行文本变成真正的
      单行多列，且手机端要保持现在的两行式。在那之前，收窄是更诚实的选择 ——
      对账单不需要 1120px。
    -->
    <header
      class="sticky top-0 z-[var(--z-sticky)] bg-canvas px-4 pt-[calc(var(--safe-top)+16px)] pb-3 lg:px-6"
    >
      <div class="mx-auto w-full max-w-[var(--content-max)]">
        <div class="flex items-center gap-2">
          <button
            type="button"
            class="rounded-sm px-2 py-1 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink"
            aria-label="上一个月"
            @click="month = shiftMonth(month, -1)"
          >
            ←
          </button>
          <h1 class="flex-1 text-center text-sm font-semibold text-ink-muted">
            {{ formatMonthLabel(month) }}
          </h1>
          <button
            type="button"
            class="rounded-sm px-2 py-1 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink"
            aria-label="下一个月"
            @click="month = shiftMonth(month, 1)"
          >
            →
          </button>
        </div>

        <input
          v-model="keyword"
          type="search"
          placeholder="搜索备注"
          class="mt-3 w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
        />

        <!--
          筛选。
          手机上横向滚动（一屏放不下），桌面上改成自动换行 ——
          宽屏还用横向滚动的话，用户会以为「就这几个分类」，实际后面还有一堆。
        -->
        <div
          class="mt-3 flex gap-2 overflow-x-auto pb-1 lg:flex-wrap lg:overflow-visible lg:pb-0"
        >
          <ChipButton :active="categoryId === null" @click="categoryId = null">全部分类</ChipButton>
          <ChipButton
            v-for="root in dict.rootCategories"
            :key="root.id"
            :active="categoryId === root.id"
            @click="categoryId = categoryId === root.id ? null : root.id"
          >
            {{ root.name }}
          </ChipButton>
        </div>

        <div
          class="mt-2 flex gap-2 overflow-x-auto pb-1 lg:flex-wrap lg:overflow-visible lg:pb-0"
        >
          <ChipButton :active="paymentMethodId === null" @click="paymentMethodId = null">
            全部方式
          </ChipButton>
          <ChipButton
            v-for="method in dict.paymentMethods"
            :key="method.id"
            :active="paymentMethodId === method.id"
            @click="paymentMethodId = paymentMethodId === method.id ? null : method.id"
          >
            {{ method.name }}
          </ChipButton>
        </div>

        <p v-if="items.length > 0" class="mt-3 text-xs text-ink-muted">
          已加载 {{ items.length }} 笔 · 合计 {{ formatYuan(loadedTotal) }}
        </p>
      </div>
    </header>

    <main class="mx-auto w-full max-w-[var(--content-max)] px-4 lg:px-6">
      <p v-if="errorMessage !== null" class="py-4 text-sm text-danger-text">{{ errorMessage }}</p>

      <p v-else-if="loading" class="py-8 text-center text-sm text-ink-muted">加载中…</p>

      <p v-else-if="items.length === 0" class="py-12 text-center text-sm text-ink-muted">
        这个月没有符合条件的记录
      </p>

      <template v-else>
        <!--
          桌面：真正的表格，**靠加列把宽度用掉**。
          之前只有「日期 / 图标 / 文字 / 金额」四段，文字段是弹性的，
          1120px 宽度下分类名和金额之间空出约 600px，眼睛要横跨整行才能对上。
          空出来的宽度要用**新列**去填（备注 / 支付方式 / 还款日 / 记录人），
          而不是把四段摊开。

          注意 `lg:table` 而不是 `lg:block`：<table> 设成 block 后浏览器会在内部
          生成一个 shrink-to-fit 的匿名表格，表格只延伸到各列固定宽度之和就停了，
          右侧留一大块白 —— 外层元素量起来仍是 100%，极难发现。
        -->
        <table class="hidden w-full lg:table" aria-label="流水明细">
          <thead>
            <tr
              class="border-b border-line text-left text-[11px] tracking-widest text-ink-muted"
            >
              <th class="py-2 pr-3 font-bold">日期</th>
              <th class="py-2 pr-3 font-bold">分类</th>
              <th class="py-2 pr-3 font-bold">备注</th>
              <th class="py-2 pr-3 font-bold">支付方式</th>
              <th class="py-2 pr-3 font-bold">还款日</th>
              <th class="py-2 pr-3 font-bold">记录人</th>
              <th class="py-2 text-right font-bold">金额</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in items"
              :key="row.id"
              class="cursor-pointer border-b border-line/60 transition-colors duration-200 hover:bg-sunken"
              @click="ui.openEdit(row)"
            >
              <td class="whitespace-nowrap py-2.5 pr-3 align-middle">
                <span class="block text-sm">{{ formatDayLabel(row.spendDate) }}</span>
                <span class="block text-[10px] text-ink-muted">
                  {{ row.spendDate === today ? '今天' : weekdayOf(row.spendDate) }}
                </span>
              </td>
              <td class="py-2.5 pr-3 align-middle">
                <span class="flex items-center gap-2">
                  <CategoryIcon
                    :name="row.categoryName"
                    :icon="row.categoryIcon"
                    :color="row.parentCategoryColor ?? row.categoryColor"
                    :color-name="row.parentCategoryName ?? row.categoryName"
                    :size="18"
                  />
                  <span class="truncate">
                    {{
                      row.parentCategoryName === null
                        ? row.categoryName
                        : `${row.parentCategoryName} · ${row.categoryName}`
                    }}
                  </span>
                </span>
              </td>
              <td class="max-w-[240px] truncate py-2.5 pr-3 text-sm text-ink-muted">
                {{ row.note === '' ? '—' : row.note }}
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-sm text-ink-muted">
                {{ row.paymentMethodName }}
              </td>
              <!-- 还款日单独成列：它原来是挂在每行下面的灰药丸，几乎行行都有，是纯噪音 -->
              <td class="whitespace-nowrap py-2.5 pr-3 text-sm text-ink-muted">
                <template v-if="row.repaymentDate.slice(0, 7) !== row.spendDate.slice(0, 7)">
                  {{ formatMonthDay(row.repaymentDate) }}
                </template>
                <template v-else>—</template>
              </td>
              <td class="whitespace-nowrap py-2.5 pr-3 text-sm text-ink-muted">
                {{ row.ownerName }}
              </td>
              <td
                class="whitespace-nowrap py-2.5 text-right text-sm font-semibold"
                :class="row.amountCents < 0 ? 'text-danger-text' : ''"
              >
                {{ formatYuan(row.amountCents) }}
              </td>
            </tr>
          </tbody>
        </table>

        <!-- 手机：两行式 -->
        <ul class="space-y-0.5 lg:hidden">
        <li v-for="row in items" :key="row.id">
          <button
            type="button"
            class="flex w-full items-center gap-3 rounded-md px-2 py-2.5 text-left transition-colors duration-200 hover:bg-sunken"
            @click="ui.openEdit(row)"
          >
            <span class="w-16 shrink-0">
              <span class="block text-xs text-ink-muted">{{ formatDayLabel(row.spendDate) }}</span>
              <span class="block text-[10px] text-ink-muted">
                {{ row.spendDate === today ? '今天' : weekdayOf(row.spendDate) }}
              </span>
            </span>

            <!--
              图标列必须**定宽**：不同图标的实际宽度不一样，不定宽的话
              分类名会左右错位，列表就扫不动了 —— 而"扫"正是这个列表唯一的用法。
            -->
            <span class="w-5 shrink-0 text-ink-muted">
              <!--
                颜色只归**一级分类**，二级永远跟它的一级走。
                不这么做的后果：用户给「餐饮」选了紫，流水里的
                「餐饮 · 外卖」「餐饮 · 买菜」却各自按名字推导出别的颜色，
                一屏之内同一个一级分类下冒出四五种颜色 —— 颜色一多就不再是身份标识，
                而是噪音（这正是这次返工要解决的原问题）。
              -->
              <CategoryIcon
                :name="row.categoryName"
                :icon="row.categoryIcon"
                :color="row.parentCategoryColor ?? row.categoryColor"
                :color-name="row.parentCategoryName ?? row.categoryName"
                :size="18"
              />
            </span>

            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm">
                {{ row.parentCategoryName === null ? row.categoryName : `${row.parentCategoryName} · ${row.categoryName}` }}
              </span>
              <span class="block truncate text-xs text-ink-muted">
                {{ row.note === '' ? row.paymentMethodName : `${row.note} · ${row.paymentMethodName}` }}
              </span>
              <!--
                消费日与还款日不在同一个月时，明确标出来。
                否则用户会疑惑「我 1 月 11 日买的东西为什么出现在 2 月的账里」。
              -->
              <span
                v-if="row.repaymentDate.slice(0, 7) !== row.spendDate.slice(0, 7)"
                class="mt-0.5 inline-block rounded-sm bg-surface px-1.5 py-0.5 text-[10px] text-ink-muted"
              >
                {{ formatMonthDay(row.repaymentDate) }} 还款
              </span>
            </span>

            <span
              class="shrink-0 text-sm font-semibold"
              :class="row.amountCents < 0 ? 'text-danger-text' : ''"
            >
              {{ formatYuan(row.amountCents) }}
            </span>
          </button>
        </li>
      </ul>
      </template>

      <button
        v-if="hasMore"
        type="button"
        :disabled="loadingMore"
        class="mt-4 w-full rounded-md bg-surface py-3 text-sm font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-50"
        @click="loadMore"
      >
        {{ loadingMore ? '加载中…' : '加载更多' }}
      </button>
    </main>
  </div>
</template>
