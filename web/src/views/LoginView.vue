<script setup lang="ts">
/**
 * 登录 / 首次初始化（原型语言重写）。
 *
 * 「初始化管理员」与「登录」是同一个表单的两种模式 —— 全新部署第一次打开时
 * 如果只给登录表单，用户会困惑（他还没有账号）。页面加载时问一次服务端
 * 初始化状态：需要初始化就直接进 setup 模式，并隐藏手动切换入口。
 *
 * 服务器地址配置只对**原生壳**出现：浏览器里前端就是服务端托管的那份，
 * 永远同源，让用户填后端地址只会把自己锁在外面。
 */
import { ShieldCheck } from '@lucide/vue';
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { ApiError, auth as authApi, probeServerUrl, readServerUrl, writeServerUrl } from '@/api';
import BrandMark from '@/components/BrandMark.vue';
import { useTheme } from '@/composables/useTheme';
import { getPlatform } from '@/platform';
import { useAuthStore } from '@/stores/auth';
import { PBtn, PField, PInput, PTag } from '@/ui';

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const theme = useTheme();

const mode = ref<'login' | 'setup'>('login');
const needsSetup = ref<boolean | null>(null);

const username = ref('');
const displayName = ref('');
const password = ref('');
const busy = ref(false);
const errorMessage = ref<string | null>(null);

const showServerConfig = ref(false);
const customServerUrl = ref(readServerUrl());
const testing = ref(false);
const serverNotice = ref<string | null>(null);
const isNative = computed(() => getPlatform() !== 'web');

const isSetup = computed(() => mode.value === 'setup');
const themeLabel = computed(() => (theme.proto.value === 'cyber' ? 'CYBERPUNK' : 'PLAYFUL'));
const canSubmit = computed(() => username.value.trim() !== '' && password.value.length >= 8 && !busy.value);

async function submit(): Promise<void> {
  if (!canSubmit.value) return;
  errorMessage.value = null;
  busy.value = true;
  try {
    if (isSetup.value) {
      await auth.setup(username.value.trim(), displayName.value.trim(), password.value);
    } else {
      await auth.login(username.value.trim(), password.value);
    }
    const next = typeof route.query['next'] === 'string' ? route.query['next'] : '/';
    await router.replace(next);
  } catch (error) {
    errorMessage.value = error instanceof ApiError ? error.message : '操作失败，请重试';
    // 初始化被拒通常意味着已有账号，自动切回登录省一次点击
    if (isSetup.value && error instanceof ApiError && error.status === 403) {
      mode.value = 'login';
    }
  } finally {
    busy.value = false;
  }
}

function switchMode(): void {
  mode.value = isSetup.value ? 'login' : 'setup';
  errorMessage.value = null;
}

async function testServer(): Promise<void> {
  const raw = customServerUrl.value.trim();
  if (!raw) {
    serverNotice.value = '请填写服务器地址';
    return;
  }
  testing.value = true;
  serverNotice.value = null;
  const probe = await probeServerUrl(raw, 3000);
  serverNotice.value = probe.ok ? `连接正常（${probe.latencyMs}ms）` : `连接失败（${probe.error ?? '无法访问'}）`;
  testing.value = false;
}

function saveServer(): void {
  writeServerUrl(customServerUrl.value.trim());
  serverNotice.value = '服务器地址已保存';
}

onMounted(async () => {
  try {
    const status = await authApi.status();
    needsSetup.value = status.needsSetup;
    if (status.needsSetup) mode.value = 'setup';
  } catch {
    // 离线或服务未起：保持登录模式，提交时由服务端兜底
  }
});
</script>

<template>
  <div class="app login-page" :data-theme="theme.proto.value" data-decor="on">
    <span class="deco deco-a" />
    <span class="deco deco-b" />
    <span class="deco deco-c" />
    <span class="deco deco-d" />

    <div class="login-shell">
      <div class="card card--pop login-card">
        <div class="login-brand">
          <BrandMark :size="56" />
          <div>
            <div class="brand-name">SuenMoney</div>
            <div class="brand-sub">FAMILY LEDGER · 单账本</div>
          </div>
        </div>

        <div class="card-h">
          <span class="card-t">{{ isSetup ? '初始化账本' : '登录' }}</span>
          <span class="card-cap">{{ isSetup ? '第一次使用' : '家庭共用' }}</span>
        </div>

        <p class="hint">
          {{ isSetup ? '创建第一个账号（管理员），之后可添加家庭成员。' : '用你的账号进入账本。' }}
        </p>

        <form class="login-form" @submit.prevent="submit">
          <PField label="登录名" id="login-username">
            <PInput id="login-username" v-model="username" placeholder="小写字母" autocomplete="username" />
          </PField>

          <PField v-if="isSetup" label="显示名" id="login-display">
            <PInput id="login-display" v-model="displayName" placeholder="界面上显示的名字，如「我」" />
          </PField>

          <PField label="口令（至少 8 位）" id="login-password">
            <PInput
              id="login-password"
              v-model="password"
              type="password"
              placeholder="至少 8 位"
              :autocomplete="isSetup ? 'new-password' : 'current-password'"
            />
          </PField>

          <p v-if="errorMessage" class="login-error">{{ errorMessage }}</p>

          <PBtn variant="primary" type="submit" :disabled="!canSubmit" style="width: 100%; justify-content: center">
            <ShieldCheck :size="14" />
            {{ busy ? '处理中…' : isSetup ? '创建并进入' : '登录' }}
          </PBtn>
        </form>

        <div class="login-foot">
          <button
            v-if="needsSetup !== true"
            type="button"
            class="btn btn--ghost btn--sm"
            @click="switchMode"
          >
            {{ isSetup ? '已有账号，去登录' : '首次部署？初始化账本' }}
          </button>
          <button
            v-if="isNative"
            type="button"
            class="btn btn--ghost btn--sm"
            @click="showServerConfig = !showServerConfig"
          >
            服务器设置
          </button>
        </div>

        <div v-if="isNative && showServerConfig" class="login-server">
          <PField label="服务器地址" id="server-url">
            <PInput id="server-url" v-model="customServerUrl" placeholder="http://192.168.1.10:5310" />
          </PField>
          <div class="split">
            <PBtn size="sm" :disabled="testing" @click="testServer">{{ testing ? '测试中…' : '测试' }}</PBtn>
            <PBtn size="sm" variant="primary" @click="saveServer">保存</PBtn>
            <PTag v-if="serverNotice" tone="dash">{{ serverNotice }}</PTag>
          </div>
        </div>
      </div>

      <p class="build-stamp">{{ themeLabel }} · SuenMoney</p>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  min-height: 100dvh;
  padding: 24px 16px;
  position: relative;
  isolation: isolate;
}
.login-shell {
  position: relative;
  z-index: 1;
  width: 100%;
  max-width: 420px;
}
.login-card {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.login-brand {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 4px;
}
.login-form {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 4px;
}
.login-error {
  font-size: 12px;
  color: var(--danger);
  margin: 0;
}
.login-foot {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.login-server {
  display: flex;
  flex-direction: column;
  gap: 10px;
  border-top: 1px dashed var(--line);
  padding-top: 12px;
}
</style>
