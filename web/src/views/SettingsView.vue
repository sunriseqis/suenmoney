<script setup lang="ts">
/**
 * 设置页 —— Web 端在这里承担「管理后台」的角色。
 *
 * 分类与支付方式**只能停用不能删除**：硬删会让历史记录的分类变成空值，
 * 报表里冒出一块「未分类」黑洞，而且这个错误会随同步扩散到所有设备。
 * 界面上的「停用」按钮在服务端会做前置检查（有子分类或记录时拒绝），
 * 所以被拒绝时要把服务端的原话显示出来 —— 它说清了「为什么不能停用」。
 */
import { computed, onMounted, ref } from 'vue';
import { ChevronDown, ChevronRight } from '@lucide/vue';
import { RouterLink, useRouter } from 'vue-router';

import {
  ApiError,
  auth as authApi,
  categories as categoriesApi,
  paymentMethods as paymentMethodsApi,
  users as usersApi,
  type Category,
  type PaymentMethod,
  type PaymentMethodType,
  type User,
} from '@/api';
import PlansPanel from '@/components/PlansPanel.vue';
import CategoryIcon from '@/components/CategoryIcon.vue';
import ChipButton from '@/components/ChipButton.vue';
import ColorPicker from '@/components/ColorPicker.vue';
import DataPanel from '@/components/DataPanel.vue';
import IconPicker from '@/components/IconPicker.vue';
import PaymentIcon from '@/components/PaymentIcon.vue';
import PaymentIconPicker from '@/components/PaymentIconPicker.vue';
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

// ---- 分类 -----------------------------------------------------------------

const newCategory = ref({ name: '', parentId: '', icon: '', color: '' });
const showCategoryForm = ref(false);

/**
 * 正在展开「样式选择器」（图标 + 颜色）的分类 id（null = 没有）。
 *
 * 用「一次只开一个」而不是每个分类各持一个开关：一次开好几个的话，
 * 页面上会同时出现几块几乎一样的选择网格，很难分清正在改哪一个。
 */
const pickingIconFor = ref<string | null>(null);
/**
 * 设置的当前分区。默认「分类」与 mockup 一致。
 *
 * 「数据」**只给管理员**：导出含全家庭的数据，导入 / 清空会改全家的数据，
 * 都不是普通成员的操作。客户端隐藏按钮不算权限控制，所以服务端每一条
 * 数据类路由都挂了 `requireAdmin` —— 这里只是不把一个注定 403 的入口摆出来。
 *
 * 窄屏 5 个 tab 等分仍然放得下（15 个汉字 × 12px + 边距 ≈ 300px < 358px）；
 * 带图标放不下 —— 这正是当初去图标的原因。
 */
const SETTING_TABS = [
  { id: 'categories', label: '分类', group: '账目' },
  { id: 'payments', label: '支付方式', group: '账目' },
  { id: 'plans', label: '计划', group: '账目' },
  { id: 'data', label: '数据', group: '家庭与数据' },
  { id: 'household', label: '家庭与账号', group: '家庭与数据' },
] as const;
type TabId = (typeof SETTING_TABS)[number]['id'];

/** 管理员才看得到「数据」；分组标题跟着它出现或消失，不留一个空标题。 */
const visibleTabs = computed(() => SETTING_TABS.filter((tab) => tab.id !== 'data' || isAdmin.value));
const SETTING_GROUPS = computed(() => [...new Set(visibleTabs.value.map((tab) => tab.group))]);

const activeTab = ref<TabId>('categories');

/**
 * 二级分类默认折叠。
 * 常用操作只发生在一级（改图标颜色、停用）；二级是「偶尔要改」的，
 * 十几个二级全平铺的话，找一级分类反而要滚很久。
 */
const expandedCategories = ref<Record<string, boolean>>({});


function toggleIconPicker(id: string): void {
  pickingIconFor.value = pickingIconFor.value === id ? null : id;
}

async function addCategory(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.create({
      name: newCategory.value.name.trim(),
      parentId: newCategory.value.parentId === '' ? null : newCategory.value.parentId,
      icon: newCategory.value.icon,
      color: newCategory.value.color,
    });
    newCategory.value = { name: '', parentId: '', icon: '', color: '' };
    showCategoryForm.value = false;
    pickingIconFor.value = null;
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '新建分类失败');
  } finally {
    busy.value = false;
  }
}

async function toggleCategory(id: string, isEnabled: boolean): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.update(id, { isEnabled });
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, isEnabled ? '启用失败' : '停用失败');
  } finally {
    busy.value = false;
  }
}

async function changeCategoryIcon(id: string, icon: string): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.update(id, { icon });
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '改图标失败');
  } finally {
    busy.value = false;
  }
}

/** 改分类颜色。空字符串 = 回到「自动」（按分类名推导）。 */
async function changeCategoryColor(id: string, color: string): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.update(id, { color });
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '改颜色失败');
  } finally {
    busy.value = false;
  }
}

/**
 * 改名。
 *
 * 挂在 `@change`（失焦或回车才触发）而不是 `@input` —— 后者每敲一个字
 * 就发一次请求，一个「宠物用品」会打出 4 次 PATCH，而前 3 次写进去的都是
 * 半截名字。改名的原子性是**一次完整输入**，不是每一次按键。
 *
 * 失败时要把输入框恢复成旧名字：服务端的拒绝（同层重名 409 之类）
 * 不改数据，但用户已经在框里看到新名字了，不还原会让人以为改成功了。
 */
async function renameCategory(id: string, event: Event): Promise<void> {
  const input = event.target;
  if (!(input instanceof HTMLInputElement)) return;

  const current = dict.findCategory(id);
  const next = input.value.trim();

  if (current === null || next === '' || next === current.name) {
    input.value = current?.name ?? '';
    return;
  }

  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.update(id, { name: next });
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '改名失败');
    input.value = current.name;
  } finally {
    busy.value = false;
  }
}

/**
 * 把二级分类移到另一个一级分类下。
 *
 * 只列**启用的**一级分类：服务端会拒绝移进停用的一级（那会让这个二级
 * 整组从记账选择器里消失），与其让用户点了才被拒，不如根本不列出来。
 * 也排除它当前所在的那一个 —— 移到自己原本的组里没有任何效果。
 */
function moveTargetsFor(childId: string): Category[] {
  const child = dict.findCategory(childId);
  if (child === null) return [];
  return dict.rootCategories.filter((root) => root.id !== child.parentId);
}

async function moveCategory(id: string, parentId: string): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await categoriesApi.update(id, { parentId });
    await dict.load(true);
    ui.markDataChanged();
    notice.value = '已移动。历史记录的分类归属会跟着变 —— 报表里的分组口径也一起变。';
  } catch (error) {
    report(error, '移动失败');
  } finally {
    busy.value = false;
  }
}

// ---- 支付方式 -------------------------------------------------------------

const newMethod = ref({
  name: '',
  type: 'cash' as PaymentMethodType,
  icon: '',
  billingDay: '',
  repaymentDay: '',
});
const showMethodForm = ref(false);

const editingMethodId = ref<string | null>(null);
const editMethodForm = ref({
  name: '',
  icon: '',
  billingDay: '',
  repaymentDay: '',
});

function toggleEditMethod(method: PaymentMethod): void {
  if (editingMethodId.value === method.id) {
    editingMethodId.value = null;
  } else {
    editingMethodId.value = method.id;
    editMethodForm.value = {
      name: method.name,
      icon: method.icon || '',
      billingDay: method.billingDay ? String(method.billingDay) : '',
      repaymentDay: method.repaymentDay ? String(method.repaymentDay) : '',
    };
  }
}

async function saveEditMethod(id: string, methodType: PaymentMethodType): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    const payload: {
      name: string;
      icon?: string;
      billingDay?: number;
      repaymentDay?: number;
    } = {
      name: editMethodForm.value.name.trim(),
      icon: editMethodForm.value.icon,
    };
    if (methodType === 'credit') {
      const b = Number(editMethodForm.value.billingDay);
      const r = Number(editMethodForm.value.repaymentDay);
      if (b >= 1 && b <= 31) payload.billingDay = b;
      if (r >= 1 && r <= 31) payload.repaymentDay = r;
    }
    await paymentMethodsApi.update(id, payload);
    editingMethodId.value = null;
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '修改支付方式失败');
  } finally {
    busy.value = false;
  }
}

async function addMethod(): Promise<void> {
  clearMessages();

  const payload = {
    name: newMethod.value.name.trim(),
    type: newMethod.value.type,
    icon: newMethod.value.icon || undefined,
    ...(newMethod.value.type === 'credit'
      ? {
          billingDay: Number(newMethod.value.billingDay),
          repaymentDay: Number(newMethod.value.repaymentDay),
        }
      : {}),
  };

  busy.value = true;
  try {
    await paymentMethodsApi.create(payload);
    newMethod.value = { name: '', type: 'cash', icon: '', billingDay: '', repaymentDay: '' };
    showMethodForm.value = false;
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, '新建支付方式失败');
  } finally {
    busy.value = false;
  }
}

async function toggleMethod(id: string, isEnabled: boolean): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await paymentMethodsApi.update(id, { isEnabled });
    await dict.load(true);
    ui.markDataChanged();
  } catch (error) {
    report(error, isEnabled ? '启用失败' : '停用失败');
  } finally {
    busy.value = false;
  }
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
      <div class="mt-4 grid grid-cols-5 gap-1 rounded-md bg-sunken p-1 lg:hidden">
        <button
          v-for="t in visibleTabs"
          :key="t.id"
          type="button"
          class="rounded-sm py-2 text-xs font-semibold transition-colors duration-200"
          :class="activeTab === t.id ? 'bg-canvas text-ink' : 'text-ink-muted'"
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
          <!--
            「数据」用 v-if 而不是 v-show：其余 tab 用 v-show 是为了留住各自的
            编辑态，而这一页要的恰好相反 —— 每次进来都重新读一遍概览，
            条数才是当下的。而且用 v-show 的话它会在页面加载时就发一次请求，
            非管理员即使看不到这个 tab，也会先吃一个 403。
          -->
          <DataPanel v-if="isAdmin && activeTab === 'data'" />

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
            @click="showCategoryForm = !showCategoryForm"
          >
            {{ showCategoryForm ? '取消' : '新增' }}
          </button>
        </div>

        <ul class="mt-3 space-y-1">
          <li v-for="root in dict.categories" :key="root.id">
            <div class="flex items-center gap-2 rounded-md bg-surface py-2.5 pr-3 pl-2">
              <!-- 图标本身即入口：点它改图标，省掉一个占宽度的「改图标」按钮 -->
              <button
                type="button"
                class="grid h-9 w-9 shrink-0 place-items-center rounded-sm transition-colors duration-200 hover:bg-canvas"
                :aria-expanded="pickingIconFor === root.id"
                :aria-label="`修改「${root.name}」的图标与颜色`"
                @click="toggleIconPicker(root.id)"
              >
                <CategoryIcon :name="root.name" :icon="root.icon" :color="root.color" :size="18" />
              </button>

              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-semibold">{{ root.name }}</span>
                <span class="block text-xs text-ink-muted">{{ root.expenseCount }} 笔</span>
              </span>
              <button
                v-if="root.children.length > 0"
                type="button"
                class="grid h-8 w-8 shrink-0 place-items-center rounded-sm text-ink-muted transition-colors duration-200 hover:bg-canvas"
                :aria-expanded="!!expandedCategories[root.id]"
                :aria-label="`${expandedCategories[root.id] ? '收起' : '展开'}「${root.name}」的子分类`"
                @click="expandedCategories[root.id] = !expandedCategories[root.id]"
              >
                <ChevronRight v-if="!expandedCategories[root.id]" :size="16" aria-hidden="true" />
                <ChevronDown v-else :size="16" aria-hidden="true" />
              </button>
              <button
                type="button"
                :disabled="busy"
                class="shrink-0 rounded-sm px-3 py-2 text-xs font-semibold transition-colors duration-200 hover:bg-canvas disabled:opacity-40"
                @click="toggleCategory(root.id, !root.isEnabled)"
              >
                {{ root.isEnabled ? '停用' : '启用' }}
              </button>
            </div>

            <!--
              图标与颜色在同一个展开面板里：它们都是「这个分类长什么样」，
              分成两个入口的话用户要先想清楚自己要改的是哪一个。
              第三轮把**改名**也收进这个面板：分类树的模板必然对不上每一家
              （默认叫「外卖」，他家叫「外带」），而改名原先完全没有入口 ——
              只能停用重建，连带丢掉历史归属。
              刻意**不做行内编辑**：行内编辑会让整棵树在编辑态下抖动，
              两级树尤其明显（缩进、折叠箭头、停用按钮都会跟着挪）。
            -->
            <div v-if="pickingIconFor === root.id" class="mt-1 space-y-1">
              <label class="block rounded-md bg-sunken p-3">
                <span class="label-cn">名称</span>
                <input
                  :value="root.name"
                  type="text"
                  maxlength="20"
                  class="mt-2 w-full rounded-sm bg-canvas px-3 py-2 text-sm text-ink"
                  @change="renameCategory(root.id, $event)"
                />
              </label>

              <IconPicker
                :model-value="root.icon"
                @update:model-value="changeCategoryIcon(root.id, $event)"
              />
              <ColorPicker
                :model-value="root.color"
                @update:model-value="changeCategoryColor(root.id, $event)"
              />

              <!-- 一级分类没有「移动」这一项：分类最多两级，它无处可移 -->
              <p class="rounded-md bg-sunken px-3 py-2.5 text-xs text-ink-muted">
                一级分类不能移动
              </p>
            </div>

            <ul v-if="root.children.length > 0 && expandedCategories[root.id]" class="mt-1 ml-4 space-y-1">
              <li v-for="child in root.children" :key="child.id">
                <div class="flex items-center gap-2 rounded-md py-2 pr-3 pl-2">
                  <button
                    type="button"
                    class="grid h-8 w-8 shrink-0 place-items-center rounded-sm transition-colors duration-200 hover:bg-sunken"
                    :aria-expanded="pickingIconFor === child.id"
                    :aria-label="`修改「${child.name}」的图标与颜色`"
                    @click="toggleIconPicker(child.id)"
                  >
                    <CategoryIcon
                      :name="child.name"
                      :icon="child.icon"
                      :color="child.color"
                      :size="16"
                    />
                  </button>

                  <span class="min-w-0 flex-1">
                    <span class="block truncate text-sm">
                      {{ child.name }}
                      <span v-if="!child.isEnabled" class="ml-1 text-xs text-ink-muted">
                        （已停用）
                      </span>
                    </span>
                    <span class="block text-xs text-ink-muted">{{ child.expenseCount }} 笔</span>
                  </span>
                  <button
                    type="button"
                    :disabled="busy"
                    class="shrink-0 rounded-sm px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:bg-sunken hover:text-ink disabled:opacity-40"
                    @click="toggleCategory(child.id, !child.isEnabled)"
                  >
                    {{ child.isEnabled ? '停用' : '启用' }}
                  </button>
                </div>

                <div v-if="pickingIconFor === child.id" class="mt-1 ml-10 space-y-1">
                  <label class="block rounded-md bg-sunken p-3">
                    <span class="label-cn">名称</span>
                    <input
                      :value="child.name"
                      type="text"
                      maxlength="20"
                      class="mt-2 w-full rounded-sm bg-canvas px-3 py-2 text-sm text-ink"
                      @change="renameCategory(child.id, $event)"
                    />
                  </label>

                  <IconPicker
                    :model-value="child.icon"
                    @update:model-value="changeCategoryIcon(child.id, $event)"
                  />
                  <ColorPicker
                    :model-value="child.color"
                    @update:model-value="changeCategoryColor(child.id, $event)"
                  />

                  <!--
                    同深度移动：把二级挪到另一个一级下。
                    列的是**启用的**一级且排除它当前所在的那个 —— 服务端会拒绝
                    移进停用的一级（那会让这个二级整组从记账选择器里消失），
                    与其让人点了才被拒，不如不列出来。
                  -->
                  <div v-if="moveTargetsFor(child.id).length > 0" class="rounded-md bg-sunken p-3">
                    <span class="label-cn">移动到</span>
                    <div class="mt-2 flex flex-wrap gap-1.5">
                      <button
                        v-for="target in moveTargetsFor(child.id)"
                        :key="target.id"
                        type="button"
                        :disabled="busy"
                        class="rounded-sm bg-canvas px-3 py-2 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:text-ink disabled:opacity-40"
                        @click="moveCategory(child.id, target.id)"
                      >
                        {{ target.name }}
                      </button>
                    </div>
                    <p class="mt-2 text-xs text-ink-muted">
                      历史记录的归属会跟着变
                    </p>
                  </div>
                </div>
              </li>
            </ul>
          </li>
        </ul>

        <form v-if="showCategoryForm" class="mt-3 space-y-2" @submit.prevent="addCategory">
          <input
            v-model="newCategory.name"
            placeholder="分类名，如「话费」"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
          <select
            v-model="newCategory.parentId"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink"
          >
            <option value="">作为一级分类</option>
            <option v-for="root in dict.categories" :key="root.id" :value="root.id">
              放在「{{ root.name }}」下
            </option>
          </select>

          <div>
            <p class="label-cn mb-1.5">图标</p>
            <IconPicker v-model="newCategory.icon" />
          </div>

          <div>
            <p class="label-cn mb-1.5">颜色</p>
            <ColorPicker v-model="newCategory.color" />
          </div>

          <p class="text-xs text-ink-muted">
            分类最多两级。图标或颜色留「自动」时，会按分类名固定分配
            （如「外卖」配餐具）—— 同一个分类在任何设备上都是同一个样子。
          </p>

          <button
            type="submit"
            :disabled="busy"
            class="w-full rounded-md bg-primary-fill py-3 text-sm font-bold text-on-primary disabled:opacity-40"
          >
            新增分类
          </button>
        </form>
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
            @click="showMethodForm = !showMethodForm"
          >
            {{ showMethodForm ? '取消' : '新增' }}
          </button>
        </div>

        <ul class="mt-3 space-y-2">
          <li
            v-for="method in dict.paymentMethods"
            :key="method.id"
            class="rounded-md bg-surface px-4 py-3"
          >
            <div class="flex items-center gap-3">
              <PaymentIcon :name="method.name" :icon="method.icon" :size="22" />
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium">
                  {{ method.name }}
                  <span v-if="!method.isEnabled" class="ml-1 text-xs text-ink-muted">（已停用）</span>
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
              <button
                type="button"
                :disabled="busy"
                class="shrink-0 rounded-sm px-2.5 py-1.5 text-xs font-semibold text-primary transition-colors duration-200 hover:bg-canvas disabled:opacity-40"
                @click="toggleEditMethod(method)"
              >
                {{ editingMethodId === method.id ? '收起' : '编辑' }}
              </button>
              <button
                type="button"
                :disabled="busy"
                class="shrink-0 rounded-sm px-2.5 py-1.5 text-xs font-semibold text-ink-muted transition-colors duration-200 hover:bg-canvas hover:text-ink disabled:opacity-40"
                @click="toggleMethod(method.id, !method.isEnabled)"
              >
                {{ method.isEnabled ? '停用' : '启用' }}
              </button>
            </div>

            <!-- 编辑表单 -->
            <div
              v-if="editingMethodId === method.id"
              class="mt-3 border-t border-line/40 pt-3 space-y-2.5 animate-in fade-in"
            >
              <div>
                <label class="label-cn block mb-1">名称</label>
                <input
                  v-model="editMethodForm.name"
                  type="text"
                  placeholder="支付方式名称"
                  class="w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink placeholder:text-ink-muted"
                />
              </div>

              <div v-if="method.type === 'credit'" class="flex gap-2">
                <div class="min-w-0 flex-1">
                  <label class="label-cn block mb-1">账单日 (1–31)</label>
                  <input
                    v-model="editMethodForm.billingDay"
                    inputmode="numeric"
                    placeholder="账单日 1–31"
                    class="w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink placeholder:text-ink-muted"
                  />
                </div>
                <div class="min-w-0 flex-1">
                  <label class="label-cn block mb-1">还款日 (1–31)</label>
                  <input
                    v-model="editMethodForm.repaymentDay"
                    inputmode="numeric"
                    placeholder="还款日 1–31"
                    class="w-full rounded-sm bg-sunken px-3 py-2 text-sm text-ink placeholder:text-ink-muted"
                  />
                </div>
              </div>

              <div>
                <label class="label-cn block mb-1">图标</label>
                <PaymentIconPicker
                  v-model="editMethodForm.icon"
                  :name="editMethodForm.name"
                />
              </div>

              <div class="flex items-center justify-end gap-2 pt-1">
                <button
                  type="button"
                  class="rounded-sm bg-sunken px-3 py-1.5 text-xs font-medium text-ink-muted hover:text-ink"
                  @click="editingMethodId = null"
                >
                  取消
                </button>
                <button
                  type="button"
                  :disabled="busy || !editMethodForm.name.trim()"
                  class="rounded-sm bg-primary-fill px-4 py-1.5 text-xs font-bold text-on-primary disabled:opacity-40"
                  @click="saveEditMethod(method.id, method.type)"
                >
                  保存修改
                </button>
              </div>
            </div>
          </li>
        </ul>

        <form v-if="showMethodForm" class="mt-3 space-y-2.5" @submit.prevent="addMethod">
          <input
            v-model="newMethod.name"
            placeholder="名称，如「招行信用卡」"
            class="w-full rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
          />
          <div class="flex gap-2">
            <ChipButton :active="newMethod.type === 'cash'" @click="newMethod.type = 'cash'">
              现金 / 储蓄卡
            </ChipButton>
            <ChipButton :active="newMethod.type === 'credit'" @click="newMethod.type = 'credit'">
              信用卡
            </ChipButton>
          </div>
          <div v-if="newMethod.type === 'credit'" class="flex gap-2">
            <input
              v-model="newMethod.billingDay"
              inputmode="numeric"
              placeholder="账单日 1–31"
              class="min-w-0 flex-1 rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
            />
            <input
              v-model="newMethod.repaymentDay"
              inputmode="numeric"
              placeholder="还款日 1–31"
              class="min-w-0 flex-1 rounded-sm bg-sunken px-3 py-2.5 text-sm text-ink placeholder:text-ink-muted"
            />
          </div>
          <div>
            <p class="label-cn mb-1.5">图标</p>
            <PaymentIconPicker v-model="newMethod.icon" :name="newMethod.name" />
          </div>
          <button
            type="submit"
            :disabled="busy"
            class="w-full rounded-md bg-primary-fill py-3 text-sm font-bold text-on-primary disabled:opacity-40"
          >
            新增支付方式
          </button>
        </form>
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
  </div>
</template>
