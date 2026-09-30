<script setup lang="ts">
/**
 * 设置页 —— Web 端在这里承担「管理后台」的角色。
 *
 * 分类与支付方式**只能停用不能删除**：硬删会让历史记录的分类变成空值，
 * 报表里冒出一块「未分类」黑洞，而且这个错误会随同步扩散到所有设备。
 * 界面上的「停用」按钮在服务端会做前置检查（有子分类或记录时拒绝），
 * 所以被拒绝时要把服务端的原话显示出来 —— 它说清了「为什么不能停用」。
 */
import { computed, onMounted, ref, watch } from 'vue';
import { ChevronDown, ChevronRight } from '@lucide/vue';
import { RouterLink, useRouter } from 'vue-router';

import {
  ApiError,
  auth as authApi,
  users as usersApi,
  type Category,
  type PaymentMethod,
  type User,
} from '@/api';
import PlansPanel from '@/components/PlansPanel.vue';
import CategoryEditModal from '@/components/CategoryEditModal.vue';
import CategoryIcon from '@/components/CategoryIcon.vue';
import DataPanel from '@/components/DataPanel.vue';
import PaymentMethodEditModal from '@/components/PaymentMethodEditModal.vue';
import PaymentIcon from '@/components/PaymentIcon.vue';
import { useAuthStore } from '@/stores/auth';
import { useDictionariesStore } from '@/stores/dictionaries';
import { useUiStore } from '@/stores/ui';

const auth = useAuthStore();
const dict = useDictionariesStore();
const ui = useUiStore();
const router = useRouter();

const busy = ref(false);
const errorMessage = ref<string | null>(null);
const notice = ref<string | null>(null);

function report(error: unknown, fallback: string): void {
  if (error instanceof ApiError && error.status === 0) {
    // 离线状态静默，不展示报错条，保障页面无扰无抖动
    return;
  }
  errorMessage.value = error instanceof ApiError ? error.message : fallback;
  notice.value = null;
}

function clearMessages(): void {
  errorMessage.value = null;
  notice.value = null;
}

// ---- 家庭成员 -------------------------------------------------------------

const members = ref<User[]>([]);
const newMember = ref({ username: '', displayName: '', password: '' });
const showMemberForm = ref(false);

const isAdmin = computed(() => auth.user?.role === 'admin');

async function loadMembers(): Promise<void> {
  try {
    members.value = (await usersApi.list()).users;
  } catch (error) {
    report(error, '成员列表加载失败');
  }
}

async function addMember(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await usersApi.create({
      username: newMember.value.username.trim(),
      displayName: newMember.value.displayName.trim() || newMember.value.username.trim(),
      password: newMember.value.password,
    });
    newMember.value = { username: '', displayName: '', password: '' };
    showMemberForm.value = false;
    notice.value = '账号已创建，把登录名与口令告诉家人即可';
    await loadMembers();
  } catch (error) {
    report(error, '创建账号失败');
  } finally {
    busy.value = false;
  }
}

// ---- 设置分区 -------------------------------------------------------------

/**
 * 设置的当前分区。
 */
const SETTING_TABS = [
  { id: 'categories', label: '分类', group: '账目' },
  { id: 'payments', label: '支付', group: '账目' },
  { id: 'plans', label: '计划', group: '账目' },
  { id: 'system', label: '系统', group: '系统' },
  { id: 'household', label: '账号', group: '系统' },
] as const;
type TabId = (typeof SETTING_TABS)[number]['id'];

const visibleTabs = computed(() => SETTING_TABS);
const SETTING_GROUPS = computed(() => [...new Set(visibleTabs.value.map((tab) => tab.group))]);

const activeTab = ref<TabId>('categories');

watch(activeTab, () => {
  clearMessages();
});

/**
 * 二级分类默认折叠。
 */
const expandedCategories = ref<Record<string, boolean>>({});

// 分类独立弹窗编辑与新增
const editingCategory = ref<Category | null>(null);
const categoryModalOpen = ref(false);

function openCategoryCreate(): void {
  editingCategory.value = null;
  categoryModalOpen.value = true;
}

function openCategoryEdit(cat: Category): void {
  editingCategory.value = cat;
  categoryModalOpen.value = true;
}

async function onCategorySaved(): Promise<void> {
  await dict.load(true);
  ui.markDataChanged();
  notice.value = '分类已保存';
}

// 支付方式独立弹窗编辑与新增
const editingMethod = ref<PaymentMethod | null>(null);
const methodModalOpen = ref(false);

function openMethodCreate(): void {
  editingMethod.value = null;
  methodModalOpen.value = true;
}

function openMethodEdit(m: PaymentMethod): void {
  editingMethod.value = m;
  methodModalOpen.value = true;
}

async function onMethodSaved(): Promise<void> {
  await dict.load(true);
  ui.markDataChanged();
  notice.value = '支付方式已保存';
}

// ---- 设备会话 -------------------------------------------------------------

const sessions = ref<Array<{ id: string; deviceLabel: string; lastSeenAt: string; current: boolean }>>(
  [],
);

async function loadSessions(): Promise<void> {
  try {
    sessions.value = (await authApi.sessions()).sessions;
  } catch (error) {
    report(error, '设备列表加载失败');
  }
}

async function revokeOthers(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    const result = await authApi.revokeOthers();
    notice.value = result.revoked === 0 ? '没有其他登录中的设备' : `已踢下线 ${result.revoked} 个设备`;
    await loadSessions();
  } catch (error) {
    report(error, '操作失败');
  } finally {
    busy.value = false;
  }
}

async function logout(): Promise<void> {
  await auth.logout();
  await router.replace({ name: 'login' });
}

onMounted(async () => {
  await dict.load();
  await Promise.all([loadMembers(), loadSessions()]);
});

function formatTimestamp(iso: string): string {
  const date = new Date(iso);
  const pad = (value: number) => String(value).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
</script>

<template>
  <div class="pb-[calc(var(--bottom-bar-h)+var(--safe-bottom)+32px)]">
    <header
      class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-[calc(var(--safe-top)+16px)] lg:px-6 lg:pt-8"
    >
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-extrabold text-ink">设置</h1>
        <!-- 窄屏标题行行尾关闭按键（A24），返回流水落地页 -->
        <RouterLink
          :to="{ name: 'ledger' }"
          class="grid h-9 w-9 place-items-center rounded-sm text-base font-bold text-ink-muted transition-colors hover:bg-sunken hover:text-ink lg:hidden"
          aria-label="关闭设置，返回流水"
        >
          ✕
        </RouterLink>
      </div>
    </header>

    <main class="mx-auto w-full max-w-[var(--content-max)] px-4 pt-6 lg:px-6 lg:pt-8">
      <p
        v-if="errorMessage !== null"
        class="rounded-md bg-surface px-4 py-3 text-sm text-danger-text lg:mb-8"
      >
        {{ errorMessage }}
      </p>
      <p
        v-if="notice !== null"
        class="rounded-md bg-surface px-4 py-3 text-sm text-secondary-text lg:mb-8"
      >
        {{ notice }}
      </p>

                  <!--
        设置 = **单区块视图**（mockup 原案）：窄屏等分 tab 条，宽屏左侧栏分组，
        一次只显示一类配置。之前所有区块堆一页，手机上要滚十几屏才到「登录设备」，
        宽屏两栏也会让人以为这些配置在视觉上有什么对应关系 —— 其实没有。

        计划在这里只做**管理**（新建/编辑/规则），hide-todos 关掉「该处理了」：
        待办是首页的事，两页重复同一份提醒只会让人怀疑数据是不是两份。
      -->
      <div class="mt-4 flex gap-1 overflow-x-auto no-scrollbar rounded-md bg-sunken p-1 lg:hidden">
        <button
          v-for="t in visibleTabs"
          :key="t.id"
          type="button"
          class="shrink-0 px-3.5 py-2 text-xs font-semibold rounded-sm transition-colors duration-200"
          :class="activeTab === t.id ? 'bg-canvas text-ink shadow-sm' : 'text-ink-muted'"
          :aria-pressed="activeTab === t.id"
          @click="activeTab = t.id"
        >
          {{ t.label }}
        </button>
      </div>

      <div class="mt-6 flex items-start gap-10">
        <aside class="hidden w-44 shrink-0 space-y-6 lg:block" aria-label="设置分组">
          <div v-for="g in SETTING_GROUPS" :key="g">
            <p class="label-cn">{{ g }}</p>
            <div class="mt-2 space-y-1">
              <button
                v-for="t in visibleTabs.filter((x) => x.group === g)"
                :key="t.id"
                type="button"
                class="block w-full rounded-sm px-3 py-2 text-left text-sm font-semibold transition-colors duration-200"
                :class="activeTab === t.id ? 'bg-surface text-ink' : 'text-ink-muted hover:text-ink'"
                :aria-pressed="activeTab === t.id"
                @click="activeTab = t.id"
              >
                {{ t.label }}
              </button>
            </div>
          </div>
        </aside>

        <div class="min-w-0 flex-1">
          <DataPanel v-if="activeTab === 'system'" />

          <div v-show="activeTab === 'plans'">
            <PlansPanel hide-todos />
          </div>

          <div v-show="activeTab === 'categories'" class="space-y-8">
            <!-- 分类 -->
          <section aria-label="分类">
            <div class="flex items-baseline justify-between">
              <h2 class="label-cn">分类</h2>
          <button
            type="button"
            class="text-xs font-semibold text-primary-text hover:underline"
            @click="openCategoryCreate"
          >
            新增
          </button>
        </div>

        <ul class="mt-3 space-y-1">
          <li v-for="root in dict.categories" :key="root.id">
            <div
              class="flex items-center gap-2 rounded-md bg-surface py-2.5 pr-3 pl-2 transition-colors hover:bg-surface/80 cursor-pointer"
              @click="openCategoryEdit(root)"
            >
              <div class="grid h-9 w-9 shrink-0 place-items-center rounded-sm">
                <CategoryIcon :category-id="root.id" :size="18" />
              </div>

              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5 truncate text-sm font-semibold text-ink">
                  {{ root.name }}
                  <span v-if="!root.isEnabled" class="rounded bg-sunken px-1.5 py-0.5 text-[10px] text-ink-muted">已停用</span>
                </span>
                <span class="block text-xs text-ink-muted">{{ root.expenseCount }} 笔</span>
              </span>

              <button
                v-if="root.children.length > 0"
                type="button"
                class="grid h-8 w-8 shrink-0 place-items-center rounded-sm text-ink-muted transition-colors duration-200 hover:bg-canvas"
                :aria-expanded="!!expandedCategories[root.id]"
                :aria-label="`${expandedCategories[root.id] ? '收起' : '展开'}「${root.name}」的子分类`"
                @click.stop="expandedCategories[root.id] = !expandedCategories[root.id]"
              >
                <ChevronRight v-if="!expandedCategories[root.id]" :size="16" aria-hidden="true" />
                <ChevronDown v-else :size="16" aria-hidden="true" />
              </button>
            </div>

            <ul v-if="root.children.length > 0 && expandedCategories[root.id]" class="mt-1 ml-4 space-y-1">
              <li v-for="child in root.children" :key="child.id">
                <div
                  class="flex items-center gap-2 rounded-md py-2 pr-3 pl-2 transition-colors hover:bg-surface/60 cursor-pointer"
                  @click="openCategoryEdit(child)"
                >
                  <div class="grid h-8 w-8 shrink-0 place-items-center rounded-sm">
                    <CategoryIcon :category-id="child.id" :size="16" />
                  </div>

                  <span class="min-w-0 flex-1">
                    <span class="flex items-center gap-1.5 truncate text-sm text-ink">
                      {{ child.name }}
                      <span v-if="!child.isEnabled" class="rounded bg-sunken px-1.5 py-0.5 text-[10px] text-ink-muted">已停用</span>
                    </span>
                    <span class="block text-xs text-ink-muted">{{ child.expenseCount }} 笔</span>
                  </span>
                </div>
              </li>
            </ul>
          </li>
        </ul>
      </section>
          </div>

          <div v-show="activeTab === 'payments'">
            <!-- 支付方式 -->
      <section aria-label="支付方式">
        <div class="flex items-baseline justify-between">
          <h2 class="label-cn">支付方式</h2>
          <button
            type="button"
            class="text-xs font-semibold text-primary-text hover:underline"
            @click="openMethodCreate"
          >
            新增
          </button>
        </div>

        <ul class="mt-3 space-y-2">
          <li
            v-for="method in dict.paymentMethods"
            :key="method.id"
            class="rounded-md bg-surface px-4 py-3 transition-colors hover:bg-surface/80 cursor-pointer"
            @click="openMethodEdit(method)"
          >
            <div class="flex items-center gap-3">
              <PaymentIcon :name="method.name" :icon="method.icon" :size="22" />
              <span class="min-w-0 flex-1">
                <span class="flex items-center gap-1.5 truncate text-sm font-medium text-ink">
                  {{ method.name }}
                  <span v-if="!method.isEnabled" class="rounded bg-sunken px-1.5 py-0.5 text-[10px] text-ink-muted">已停用</span>
                </span>
                <span class="block text-xs text-ink-muted">
                  {{
                    method.type === 'credit'
                      ? `信用卡 · 账单日 ${method.billingDay} · 还款日 ${method.repaymentDay}`
                      : '现金 / 储蓄卡'
                  }}
                  · {{ method.expenseCount }} 笔
                </span>
              </span>
            </div>
          </li>
        </ul>
      </section>
          </div>

          <div v-show="activeTab === 'household'" class="space-y-8">
            <!-- 账号 -->
          <section aria-label="账号">
        <h2 class="label-cn">我的账号</h2>
        <div class="mt-3 flex items-center gap-3 rounded-md bg-surface px-4 py-3">
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-semibold">{{ auth.user?.displayName }}</p>
            <p class="text-xs text-ink-muted">
              {{ auth.user?.username }} ·
              {{ auth.user?.role === 'admin' ? '管理员' : '成员' }}
            </p>
          </div>
          <button
            type="button"
            class="shrink-0 rounded-sm px-3 py-2 text-sm font-semibold text-danger-text transition-colors duration-200 hover:bg-canvas"
            @click="logout"
          >
            退出登录
          </button>
        </div>
      </section>
            <!-- 家庭成员 -->
      <section aria-label="家庭成员">
        <div class="flex items-baseline justify-between">
          <h2 class="label-cn">家庭成员</h2>
          <button
            v-if="isAdmin"
            type="button"
            class="text-xs font-semibold text-primary-text hover:underline"
            @click="showMemberForm = !showMemberForm"
          >
            {{ showMemberForm ? '取消' : '添加成员' }}
          </button>
        </div>

        <ul class="mt-3 space-y-2">
          <li
            v-for="member in members"
            :key="member.id"
            class="flex items-center gap-3 rounded-md bg-surface px-4 py-3"
          >
            <span class="min-w-0 flex-1 truncate text-sm">{{ member.displayName }}</span>
            <span class="shrink-0 text-xs text-ink-muted">
              {{ member.role === 'admin' ? '管理员' : '成员' }}
            </span>
          </li>
        </ul>

        <form v-if="showMemberForm" class="mt-3 space-y-2" @submit.prevent="addMember">
          <input
            v-model="newMember.username"
            placeholder="登录名（小写）"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
          <input
            v-model="newMember.displayName"
            placeholder="显示名，如「家人」"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
          <input
            v-model="newMember.password"
            type="text"
            placeholder="初始口令（至少 8 位）"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
          <button
            type="submit"
            :disabled="busy"
            class="w-full rounded-md bg-primary-fill py-3 text-sm font-bold text-on-primary disabled:opacity-40"
          >
            创建账号
          </button>
        </form>
      </section>
            <section aria-label="登录设备">
        <div class="flex items-baseline justify-between">
          <h2 class="label-cn">登录设备</h2>
          <button
            type="button"
            :disabled="busy"
            class="text-xs font-semibold text-danger-text hover:underline disabled:opacity-40"
            @click="revokeOthers"
          >
            踢掉其他设备
          </button>
        </div>

        <ul class="mt-3 space-y-2">
          <li
            v-for="item in sessions"
            :key="item.id"
            class="flex items-center gap-3 rounded-md bg-surface px-4 py-3"
          >
            <span class="min-w-0 flex-1">
              <span class="block truncate text-sm">
                {{ item.deviceLabel === '' ? '未知设备' : item.deviceLabel }}
                <span v-if="item.current" class="ml-1 text-xs text-secondary-text">当前</span>
              </span>
              <span class="block text-xs text-ink-muted">
                最近活跃 {{ formatTimestamp(item.lastSeenAt) }}
              </span>
            </span>
          </li>
        </ul>
          </section>
          </div>
        </div>
      </div>

    </main>

    <!-- 分类独立编辑弹窗 -->
    <CategoryEditModal
      :open="categoryModalOpen"
      :category="editingCategory"
      :parent-categories="dict.categories"
      @close="categoryModalOpen = false"
      @saved="onCategorySaved"
    />

    <!-- 支付方式独立编辑弹窗 -->
    <PaymentMethodEditModal
      :open="methodModalOpen"
      :method="editingMethod"
      :available-methods="dict.paymentMethods"
      @close="methodModalOpen = false"
      @saved="onMethodSaved"
    />
  </div>
</template>
