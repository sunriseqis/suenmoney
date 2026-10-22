/**
 * 轻提示（原型 `.toast`）—— 模块级单例，任何组件 `useToast().show('已保存')` 即可。
 *
 * 为什么不放 store：toast 是纯展示，没有业务状态，也不需要被测试断言；
 * 一个模块级 ref 足够，还省掉 Pinia 初始化顺序的坑。
 */
import { ref } from 'vue';

const message = ref<string | null>(null);
let timer: ReturnType<typeof setTimeout> | null = null;

export function useToast() {
  function show(text: string, ms = 2400): void {
    message.value = text;
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      message.value = null;
      timer = null;
    }, ms);
  }

  function hide(): void {
    if (timer) clearTimeout(timer);
    timer = null;
    message.value = null;
  }

  return { message, show, hide };
}
