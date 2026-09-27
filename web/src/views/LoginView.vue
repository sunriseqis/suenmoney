<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { ApiError } from '@/api';
import { useAuthStore } from '@/stores/auth';

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();

/**
 * 登录 / 首次初始化。
 *
 * 「初始化管理员」不做成独立页面而是同一个表单的另一种模式：两者字段几乎
 * 相同，而且新用户第一次打开时看到的是「登录」会很困惑 —— 他还没有账号。
 * 默认仍是登录，页脚给一条切换链接。
 */
const mode = ref<'login' | 'setup'>('login');

const username = ref('');
const displayName = ref('');
const password = ref('');
const busy = ref(false);
const errorMessage = ref<string | null>(null);

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

      <p class="mt-6 text-center text-xs text-ink-muted">
        <template v-if="mode === 'login'">
          首次部署？
          <button
            type="button"
            class="font-semibold text-primary-text underline"
            @click="switchMode"
          >
            初始化管理员账号
          </button>
        </template>
        <template v-else>
          系统已有账号？
          <button
            type="button"
            class="font-semibold text-primary-text underline"
            @click="switchMode"
          >
            返回登录
          </button>
        </template>
      </p>

      <p v-if="mode === 'setup'" class="mt-4 text-center text-xs leading-relaxed text-ink-muted">
        该入口只在系统里一个账号都没有时可用，建好第一个账号后会自动关闭。
      </p>
    </div>
  </div>
</template>
