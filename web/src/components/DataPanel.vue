<script setup lang="ts">
/**
 * 设置 → 数据。
 *
 * ## 它按「想干什么」分块，不按接口分
 *
 * 导出 / 导入 / 备份 / 恢复 / 危险区 —— 这五件事背后是七个接口，
 * 但平铺成一排七个按钮，用户第一眼不知道先点哪个。所以：
 *
 *   · **导出 | 导入**并排：一进一出，天然成对，高度也接近；
 *   · **备份与恢复**通栏：两个动作 + 一段说明，比上面那两张高一截，
 *     硬凑成三张卡只会让某一张被撑高；
 *   · **危险区**通栏一条放最底：它天然排在所有操作**之后**，
 *     占半格反而像个附赠品（`.card-grid` 的由来看 §6.7）。
 *
 * ## 「导出」和「备份」是两件事，界面上必须看得出是两件事
 *
 * 只有一个入口的话，用户会把「按月导出」当成月度备份拿去恢复 ——
 * **静默丢掉其他月份**，而这种错误的发现时间以「年」为单位。
 * 所以这里：范围只作用于导出；备份那一栏永远全量、明说「始终全量」。
 *
 * ## 危险区的两个按钮代价不对称
 *
 * 「清空账目」用户自己能理解；「重置演示数据」会把**真实数据换成假数据**，
 * 所以它只在「库里只有演示数据」时才可点 —— 判据由服务端给
 * （`overview.resetDemoBlockers`），前端不自己判一遍。
 * 不可逆的动作一律**两步**：先出确认条，把「会删掉什么」写成具体数字。
 */
import { computed, onMounted, ref } from 'vue';

import { ApiError, data as dataApi, saveDownload } from '@/api';
import type { DataOverview, ExportScopeKind } from '@/api';
import { useUiStore } from '@/stores/ui';
import { todayLocal } from '@/utils/dates';

const ui = useUiStore();

const overview = ref<DataOverview | null>(null);
const busy = ref(false);
const errorMessage = ref<string | null>(null);
const notice = ref<string | null>(null);

function report(error: unknown, fallback: string): void {
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
  notice.value = null;
}

async function loadOverview(): Promise<void> {
  try {
    overview.value = (await dataApi.overview()).overview;
  } catch (error) {
    report(error, '数据概览加载失败');
  }
}

onMounted(loadOverview);

// ---- 范围 -----------------------------------------------------------------

const scopeKind = ref<ExportScopeKind>('all');
const today = todayLocal();
const thisYear = Number(today.slice(0, 4));
const thisMonth = Number(today.slice(5, 7));

/**
 * 年份候选：从**库里最早那笔账**到今年。
 *
 * 用账目的最早年份而不是写死一个区间：一个 2019 年就开始记的库，
 * 第一年是可导出的；而一个今年才建的库不该给出一排空选项。
 */
const years = computed<number[]>(() => {
  const first = overview.value?.firstRepaymentDate;
  const earliest = first === null || first === undefined ? thisYear : Number(first.slice(0, 4));
  const list: number[] = [];
  for (let year = thisYear; year >= Math.min(earliest, thisYear); year -= 1) list.push(year);
  return list;
});

const pickedYear = ref(thisYear);
const pickedMonth = ref(thisMonth);

const period = computed<string | undefined>(() => {
  if (scopeKind.value === 'all') return undefined;
  const year = String(pickedYear.value).padStart(4, '0');
  if (scopeKind.value === 'year') return year;
  return `${year}-${String(pickedMonth.value).padStart(2, '0')}`;
});

const SCOPE_TABS: ReadonlyArray<{ id: ExportScopeKind; label: string }> = [
  { id: 'all', label: '全部' },
  { id: 'year', label: '按年' },
  { id: 'month', label: '按月' },
];

async function download(kind: 'package' | 'csv'): Promise<void> {
  if (busy.value) return;
  errorMessage.value = null;
  notice.value = null;
  busy.value = true;
  try {
    const query = { scope: scopeKind.value, period: period.value };
    const file = kind === 'package' ? await dataApi.exportPackage(query) : await dataApi.exportCsv(query);
    saveDownload(file);
    notice.value = `已导出 ${file.filename}`;
  } catch (error) {
    report(error, '导出失败');
  } finally {
    busy.value = false;
  }
}

async function backup(): Promise<void> {
  if (busy.value) return;
  errorMessage.value = null;
  notice.value = null;
  busy.value = true;
  try {
    const file = await dataApi.backup();
    saveDownload(file);
    notice.value = `已备份 ${file.filename}`;
  } catch (error) {
    report(error, '备份失败');
  } finally {
    busy.value = false;
  }
}

// ---- 上传（导入 / 恢复共用一套读文件） ------------------------------------

const packageInput = ref<HTMLInputElement | null>(null);
const restoreInput = ref<HTMLInputElement | null>(null);

/** 读一个 `.json` 文件并解析。**解析失败要单独说**，不能报成「导入失败」。 */
async function readPackage(file: File): Promise<unknown> {
  const text = await file.text();
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new ApiError(0, `${file.name} 不是有效的 JSON 文件`);
  }
}

function summarize(report: {
  created: number;
  skipped: number;
  overwritten: number;
  snapshotPath: string | null;
}): string {
  const parts = [`新建 ${report.created}`, `跳过 ${report.skipped}`];
  if (report.overwritten > 0) parts.push(`覆盖 ${report.overwritten}`);
  return parts.join(' · ');
}

async function onImportFile(event: Event): Promise<void> {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || input.files === null || input.files.length === 0) return;
  const file = input.files[0]!;
  input.value = '';

  errorMessage.value = null;
  notice.value = null;
  busy.value = true;
  try {
    const result = await dataApi.import(await readPackage(file));
    notice.value = `导入完成 —— ${summarize(result.report)}（导入只补缺，不改已有记录）`;
    ui.markDataChanged();
    await loadOverview();
  } catch (error) {
    report(error, '导入失败');
  } finally {
    busy.value = false;
  }
}

async function onRestoreFile(event: Event): Promise<void> {
  const input = event.target;
  if (!(input instanceof HTMLInputElement) || input.files === null || input.files.length === 0) return;
  const file = input.files[0]!;
  input.value = '';

  errorMessage.value = null;
  notice.value = null;
  busy.value = true;
  try {
    const result = await dataApi.restore(await readPackage(file));
    const snapshot = result.report.snapshotPath;
    notice.value =
      `恢复完成 —— 覆盖 ${result.report.overwritten} · 新建 ${result.report.created}`
      + (snapshot === null ? '' : `。恢复前的存档在 ${snapshot}`);
    ui.markDataChanged();
    await loadOverview();
  } catch (error) {
    report(error, '恢复失败');
  } finally {
    busy.value = false;
  }
}

// ---- 危险区 ---------------------------------------------------------------

/**
 * 待确认的动作。用**行内确认条**而不是浏览器的 `confirm()`：
 * 系统弹窗里塞不下「会删掉哪些东西」，而不可逆的动作必须把这件事说清楚。
 */
const pending = ref<'wipe' | 'reset-demo' | null>(null);

const resetBlockers = computed(() => overview.value?.resetDemoBlockers ?? []);
const resetAllowed = computed(() => overview.value !== null && resetBlockers.value.length === 0);

/** 「会删掉什么」写成具体数字 —— 这是确认条存在的全部理由。 */
const ledgerSummary = computed(() => {
  const ledger = overview.value?.ledger;
  if (ledger === undefined || ledger === null) return '';
  return `${ledger.expenses} 笔支出 · ${ledger.plans} 条计划 · ${ledger.planTodos} 期待办`;
});

async function runDangerous(kind: 'wipe' | 'reset-demo'): Promise<void> {
  if (busy.value) return;
  errorMessage.value = null;
  notice.value = null;
  busy.value = true;
  try {
    if (kind === 'wipe') {
      const result = await dataApi.wipe();
      notice.value = `已清空 ${result.report.total} 条账目（分类、支付方式、账号都还在）`;
    } else {
      const result = await dataApi.resetDemo(today);
      notice.value =
        `已重置：灌入 ${result.report.seeded.expenses} 笔支出 · ${result.report.seeded.plans} 条计划`;
    }
    pending.value = null;
    ui.markDataChanged();
    await loadOverview();
  } catch (error) {
    report(error, kind === 'wipe' ? '清空失败' : '重置失败');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="space-y-8">
    <p v-if="errorMessage !== null" class="rounded-md bg-sunken px-4 py-3 text-sm text-danger-text">
      {{ errorMessage }}
    </p>
    <p
      v-if="notice !== null"
      class="rounded-md bg-sunken px-4 py-3 text-sm text-secondary-text"
    >
      {{ notice }}
    </p>

    <!-- 导出与导入：并入一张通栏卡片并平铺对齐，消除高度不均 -->
    <section aria-label="导出与导入" class="rounded-md bg-surface p-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <h2 class="label-cn">导出与导入</h2>
          <span class="text-xs text-ink-muted">数据包 JSON 互通 · 流水 CSV 对账 · 导入只补缺</span>
        </div>

        <!-- 导出范围：三档 chip + 年 / 月下拉 -->
        <div class="flex flex-wrap items-center gap-2">
          <span class="text-xs text-ink-muted">导出范围：</span>
          <button
            v-for="tab in SCOPE_TABS"
            :key="tab.id"
            type="button"
            class="rounded-sm px-2.5 py-1 text-xs font-semibold transition-colors duration-200"
            :class="scopeKind === tab.id ? 'bg-primary-fill text-on-primary' : 'bg-canvas text-ink-muted hover:text-ink'"
            :aria-pressed="scopeKind === tab.id"
            @click="scopeKind = tab.id"
          >
            {{ tab.label }}
          </button>

          <select
            v-if="scopeKind !== 'all'"
            v-model.number="pickedYear"
            class="rounded-sm bg-canvas px-2 py-1 text-xs text-ink"
            aria-label="导出年份"
          >
            <option v-for="year in years" :key="year" :value="year">{{ year }} 年</option>
          </select>

          <select
            v-if="scopeKind === 'month'"
            v-model.number="pickedMonth"
            class="rounded-sm bg-canvas px-2 py-1 text-xs text-ink"
            aria-label="导出月份"
          >
            <option v-for="month in 12" :key="month" :value="month">{{ month }} 月</option>
          </select>
        </div>
      </div>

      <!-- 平铺三栏动作区 -->
      <div class="mt-4 grid grid-cols-1 gap-3 md:grid-cols-3">
        <!-- ① JSON 数据包导出 -->
        <div class="flex flex-col justify-between rounded-sm bg-canvas p-3.5">
          <div>
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-ink">数据包 · JSON</span>
              <span class="rounded-xs bg-subtle px-1.5 py-0.5 text-[10px] font-medium text-ink-muted">导出</span>
            </div>
            <p class="mt-1 text-xs text-ink-muted leading-relaxed">
              可再导入，带有分类层级、支付方式与计划全量结构
            </p>
          </div>
          <button
            type="button"
            :disabled="busy"
            class="mt-3 w-full rounded-sm bg-primary-fill py-2 text-xs font-bold text-on-primary transition-opacity hover:opacity-90 disabled:opacity-40"
            @click="download('package')"
          >
            导出数据包
          </button>
        </div>

        <!-- ② CSV 对账表导出 -->
        <div class="flex flex-col justify-between rounded-sm bg-canvas p-3.5">
          <div>
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-ink">对账表 · CSV</span>
              <span class="rounded-xs bg-subtle px-1.5 py-0.5 text-[10px] font-medium text-ink-muted">导出</span>
            </div>
            <p class="mt-1 text-xs text-ink-muted leading-relaxed">
              流水扁平明细列，方便使用 Excel / Numbers 等查账
            </p>
          </div>
          <button
            type="button"
            :disabled="busy"
            class="mt-3 w-full rounded-sm border border-line py-2 text-xs font-semibold text-ink-muted transition-colors hover:border-ink-muted hover:text-ink disabled:opacity-40"
            @click="download('csv')"
          >
            导出对账表
          </button>
        </div>

        <!-- ③ JSON 数据包导入 -->
        <div class="flex flex-col justify-between rounded-sm bg-canvas p-3.5">
          <div>
            <div class="flex items-center justify-between">
              <span class="text-sm font-semibold text-ink">数据包导入</span>
              <span class="rounded-xs bg-subtle px-1.5 py-0.5 text-[10px] font-medium text-ink-muted">导入</span>
            </div>
            <p class="mt-1 text-xs text-ink-muted leading-relaxed">
              只补缺按主键去重，不覆盖现有记录，重复执行安全
            </p>
          </div>
          <button
            type="button"
            :disabled="busy"
            class="mt-3 w-full rounded-sm border border-dashed border-primary/50 bg-primary/5 py-2 text-xs font-semibold text-primary transition-colors hover:bg-primary/10 disabled:opacity-40"
            @click="packageInput?.click()"
          >
            选择 JSON 数据包导入
          </button>
          <input
            ref="packageInput"
            type="file"
            accept="application/json,.json"
            class="sr-only"
            @change="onImportFile"
          />
        </div>
      </div>
    </section>

    <!-- 备份与恢复：两个动作 + 一段说明，比上面两张高一截，所以通栏 -->
    <section aria-label="备份与恢复" class="rounded-md bg-surface p-4">
      <div class="flex items-baseline justify-between gap-3">
        <h2 class="label-cn">备份与恢复</h2>
        <span class="text-xs text-ink-muted">备份始终全量</span>
      </div>

      <div class="mt-3 space-y-2">
        <div class="flex items-center gap-3 rounded-sm bg-canvas px-3 py-2.5">
          <span class="min-w-0 flex-1">
            <span class="block text-sm font-semibold">下载全量备份</span>
            <span class="block text-xs text-ink-muted">只有它能被「恢复」接受</span>
          </span>
          <button
            type="button"
            :disabled="busy"
            class="shrink-0 rounded-sm px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
            @click="backup"
          >
            备份
          </button>
        </div>

        <div class="flex items-center gap-3 rounded-sm bg-canvas px-3 py-2.5">
          <span class="min-w-0 flex-1">
            <span class="block text-sm font-semibold">从备份恢复</span>
            <span class="block text-xs text-ink-muted">文件盖过本地已改过的记录，不删本地多出来的</span>
          </span>
          <button
            type="button"
            :disabled="busy"
            class="shrink-0 rounded-sm px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
            @click="restoreInput?.click()"
          >
            恢复
          </button>
        </div>
        <input
          ref="restoreInput"
          type="file"
          accept="application/json,.json"
          class="sr-only"
          @change="onRestoreFile"
        />
      </div>

      <p v-if="overview !== null" class="mt-3 text-xs text-ink-muted">
        恢复前的存档放在 {{ overview.preRestoreDir }}
      </p>
    </section>

    <!-- 危险区：通栏一条，放最底 -->
    <section
      aria-label="危险区"
      class="flex flex-wrap items-center gap-x-4 gap-y-3 rounded-md border border-line bg-surface p-4"
    >
      <div class="min-w-0 flex-1">
        <h2 class="text-sm font-bold text-danger-text">危险区</h2>
        <p class="mt-1 text-xs text-ink-muted">
          <template v-if="pending === null">
            清空只清账目，分类与账号都留着；重置演示数据会把现有账目换成一份假账单。
          </template>
          <template v-else-if="pending === 'wipe'">
            将要软删 {{ ledgerSummary }}。分类、支付方式、账号不受影响。这一步不可撤销。
          </template>
          <template v-else>
            将要清掉 {{ ledgerSummary }}，再灌入一份演示账单。现有账目不会回来。
          </template>
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <template v-if="pending === null">
          <button
            type="button"
            :disabled="busy || overview === null"
            class="rounded-sm bg-danger-fill px-3 py-2 text-xs font-bold text-on-danger disabled:opacity-40"
            @click="pending = 'wipe'"
          >
            清空账目数据
          </button>
          <button
            type="button"
            :disabled="busy || !resetAllowed"
            class="rounded-sm px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
            @click="pending = 'reset-demo'"
          >
            重置演示数据
          </button>
        </template>

        <template v-else>
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm bg-danger-fill px-3 py-2 text-xs font-bold text-on-danger disabled:opacity-40"
            @click="runDangerous(pending === 'wipe' ? 'wipe' : 'reset-demo')"
          >
            确认{{ pending === 'wipe' ? '清空' : '重置' }}
          </button>
          <button
            type="button"
            :disabled="busy"
            class="rounded-sm px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
            @click="pending = null"
          >
            取消
          </button>
        </template>
      </div>

      <!-- 「重置」为什么点不动：原因来自服务端，且直接念给用户听 -->
      <p v-if="!resetAllowed && resetBlockers.length > 0" class="w-full text-xs text-ink-muted">
        重置演示数据不可用：库里已经有不是演示数据的东西（{{ resetBlockers.join('、') }}）。
      </p>
    </section>
  </div>
</template>
