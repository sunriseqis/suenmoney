/**
 * 主题状态（模块级单例）—— 让 App.vue 外壳、ThemeSwitch、BrandMark 共享一份。
 *
 * 为什么不放 Pinia：主题要在 **Vue 挂载之前**就由 index.html 的内联脚本定好，
 * 挂载后只需要一个「读当前 + 改当前」的轻量桥；为它建 store 反而多一层。
 *
 * 档位仍是三档（dark / light / system），原型的两套语言从这里映射：
 *   dark   → cyber（赛博朋克）
 *   light  → candy（水果硬糖）
 *   system → 按 prefers-color-scheme 落到上面两者之一
 */
import { computed, ref } from 'vue';

import { applyTheme, effectiveTheme, readStoredTheme, type ThemeChoice } from '@/utils/theme';

const choice = ref<ThemeChoice>(readStoredTheme() ?? 'dark');

/** 系统是否偏好深色（跟随档位时用） */
const systemPrefersDark = ref(
  typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)').matches : true,
);

if (typeof matchMedia === 'function') {
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
    systemPrefersDark.value = e.matches;
  });
}

export function useTheme() {
  /** 当前**实际生效**的明暗（system 已解析） */
  const effective = computed<'dark' | 'light'>(() => effectiveTheme(choice.value));
  /** 原型语言：cyber / candy */
  const proto = computed<'cyber' | 'candy'>(() => (effective.value === 'dark' ? 'cyber' : 'candy'));

  function set(next: ThemeChoice): void {
    choice.value = next;
    applyTheme(next);
  }

  return { choice, systemPrefersDark, effective, proto, set };
}
