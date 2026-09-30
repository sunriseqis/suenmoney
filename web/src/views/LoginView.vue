<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { ApiError, auth as authApi, probeServerUrl, readServerUrl, writeServerUrl } from '@/api';
import { useAuthStore } from '@/stores/auth';

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

/**
 * 登录 / 首次初始化。
 *
 * 「初始化管理员」不做成独立页面而是同一个表单的另一种模式：两者字段几乎
 * 相同，而且新用户第一次打开时看到的是「登录」会很困惑 —— 他还没有账号。
 * 页面加载时查询服务端初始化状态：已有账号则隐藏切换入口（点了也会被 403
 * 打回，不如一开始就不给）；查询失败（如离线）保持入口可见，服务端兜底。
 */
const mode = ref<'login' | 'setup'>('login');
const needsSetup = ref<boolean | null>(null);

const username = ref('');
const displayName = ref('');
const password = ref('');
const busy = ref(false);
const errorMessage = ref<string | null>(null);

// 服务器连接配置
const showServerConfig = ref(false);
const customServerUrl = ref(readServerUrl());
const serverTesting = ref(false);
const serverUrlNotice = ref<string | null>(null);

async function testServerConnection(): Promise<void> {
  serverTesting.value = true;
  serverUrlNotice.value = null;
  const raw = customServerUrl.value.trim();
  if (!raw) {
    serverUrlNotice.value = '请填写服务器地址';
    serverTesting.value = false;
    return;
  }
  const probe = await probeServerUrl(raw, 3000);
  if (probe.ok) {
    serverUrlNotice.value = `连接正常 (${probe.latencyMs}ms)`;
  } else {
    serverUrlNotice.value = `连接失败 (${probe.error ?? '无法访问'})`;
  }
  serverTesting.value = false;
}

function saveServerConnection(): void {
  writeServerUrl(customServerUrl.value.trim());
  serverUrlNotice.value = '服务器地址已保存';
}

const canSubmit = computed(
  () => username.value.trim() !== '' && password.value.length >= 8 && !busy.value,
);

async function submit(): Promise<void> {
  if (!canSubmit.value) return;

  errorMessage.value = null;
  busy.value = true;

  try {
    if (mode.value === 'login') {
      await auth.login(username.value.trim(), password.value);
    } else {
      await auth.setup(username.value.trim(), displayName.value.trim(), password.value);
    }

    const next = typeof route.query['next'] === 'string' ? route.query['next'] : '/';
    await router.replace(next);
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '操作失败，请重试';

    // 初始化被拒绝通常意味着系统里已经有账号了，自动切回登录省用户一次点击
    if (mode.value === 'setup' && error instanceof ApiError && error.status === 403) {
      mode.value = 'login';
    }
  } finally {
    busy.value = false;
  }
}

function switchMode(): void {
  mode.value = mode.value === 'login' ? 'setup' : 'login';
  errorMessage.value = null;
}

onMounted(async () => {
  try {
    const status = await authApi.status();
    needsSetup.value = status.needsSetup;
    // 全新部署：直接进入初始化表单，省一次点击
    if (status.needsSetup) mode.value = 'setup';
  } catch {
    // 查询失败（离线/服务器未起）：保持默认登录模式与入口可见，提交时服务端兜底
  }
});
</script>

<template>
  <div
    class="flex min-h-full items-center justify-center bg-canvas px-4 py-[var(--safe-top)] text-ink"
  >
    <div class="w-full max-w-[380px]">
      <h1 class="text-3xl font-extrabold tracking-tight">SuenMoney</h1>
      <p class="mt-2 text-sm text-ink-muted">家庭共用记账 · 只记支出</p>

      <form class="mt-8 space-y-4" @submit.prevent="submit">
        <div>
          <label class="label-cn" for="login-username">登录名</label>
          <input
            id="login-username"
            v-model="username"
            type="text"
            autocomplete="username"
            autocapitalize="off"
            class="mt-2 w-full rounded-sm bg-sunken px-4 py-3 text-base text-ink placeholder:text-ink-muted"
            placeholder="小写字母"
          />
        </div>

        <div v-if="mode === 'setup'">
          <label class="label-cn" for="login-displayname">显示名</label>
          <input
            id="login-displayname"
            v-model="displayName"
            type="text"
            class="mt-2 w-full rounded-sm bg-sunken px-4 py-3 text-base text-ink placeholder:text-ink-muted"
            placeholder="界面上显示的名字，如「我」"
          />
        </div>

        <div>
          <label class="label-cn" for="login-password">口令</label>
          <input
            id="login-password"
            v-model="password"
            type="password"
            :autocomplete="mode === 'login' ? 'current-password' : 'new-password'"
            class="mt-2 w-full rounded-sm bg-sunken px-4 py-3 text-base text-ink placeholder:text-ink-muted"
            placeholder="至少 8 位"
          />
        </div>

        <p v-if="errorMessage !== null" class="text-sm text-danger-text">{{ errorMessage }}</p>

        <button
          type="submit"
          :disabled="!canSubmit"
          class="w-full rounded-md bg-primary-fill py-3.5 text-base font-bold text-on-primary transition-transform duration-200 hover:scale-[1.02] active:scale-95 disabled:opacity-40 disabled:hover:scale-100"
        >
          {{ busy ? '请稍候…' : mode === 'login' ? '登录' : '创建管理员账号' }}
        </button>
      </form>

      <p v-if="mode === 'login' && needsSetup !== false" class="mt-6 text-center text-xs text-ink-muted">
        首次部署？
        <button
          type="button"
          class="font-semibold text-primary-text underline"
          @click="switchMode"
        >
          初始化管理员账号
        </button>
      </p>

      <!-- 状态未知（查询失败）时才给返回路；确认过已有账号则本就不该进 setup 模式 -->
      <p v-if="mode === 'setup' && needsSetup === null" class="mt-6 text-center text-xs text-ink-muted">
        系统已有账号？
        <button
          type="button"
          class="font-semibold text-primary-text underline"
          @click="switchMode"
        >
          返回登录
        </button>
      </p>

      <p v-if="mode === 'setup'" class="mt-4 text-center text-xs leading-relaxed text-ink-muted">
        该入口只在系统里一个账号都没有时可用，建好第一个账号后会自动关闭。
      </p>

      <!-- 自定义服务器连接配置（移动端或局域网自建部署） -->
      <div class="mt-8 border-t border-line pt-4 text-xs">
        <button
          type="button"
          class="flex w-full items-center justify-between text-ink-muted transition-colors hover:text-ink"
          @click="showServerConfig = !showServerConfig"
        >
          <span>后端服务器设置</span>
          <span>{{ showServerConfig ? '收起' : '展开' }}</span>
        </button>

        <div v-if="showServerConfig" class="mt-3 space-y-2.5">
          <input
            v-model="customServerUrl"
            type="url"
            placeholder="http://192.168.1.100:3000"
            class="w-full rounded-sm bg-sunken px-3 py-2 text-xs text-ink outline-none placeholder:text-ink-muted focus:ring-1 focus:ring-primary"
          />
          <div class="flex items-center justify-between gap-2">
            <span v-if="serverUrlNotice" class="truncate text-[11px] text-ink-muted">
              {{ serverUrlNotice }}
            </span>
            <span v-else class="flex-1" />
            <div class="flex gap-2">
              <button
                type="button"
                :disabled="serverTesting || !customServerUrl"
                class="rounded-sm border border-line bg-canvas px-2.5 py-1 text-xs hover:bg-surface disabled:opacity-40"
                @click="testServerConnection"
              >
                {{ serverTesting ? '测试中…' : '测试连接' }}
              </button>
              <button
                type="button"
                class="rounded-sm bg-surface border border-line px-2.5 py-1 text-xs font-semibold hover:bg-canvas"
                @click="saveServerConnection"
              >
                保存
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
