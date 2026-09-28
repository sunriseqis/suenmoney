<script setup lang="ts">
/**
 * 自制数字键盘。
 *
 * 为什么不用系统键盘：
 *   1. 系统数字键盘在移动端弹出/收起会让布局整体跳动，记账时最烦的就是这个；
 *   2. 系统键盘给不了「+ 累加」—— 而一次买菜往往有好几样东西，
 *      有了累加就能「32 + 18 + 5」合成一笔记，不必先心算再记。
 *
 * 组件本身**不持有状态**：它只把按键事件抛出去，表达式由父组件维护。
 * 这样「金额怎么算」只有一处实现，编辑已有记录与新建走的是同一套逻辑。
 */
import type { KeypadKey } from './keypad';

withDefaults(
  defineProps<{
    /** 保存按钮是否可用（金额为 0 时不可用） */
    canSave?: boolean;
    saving?: boolean;
    /** 编辑模式下的文案 */
    saveLabel?: string;
  }>(),
  { canSave: true, saving: false, saveLabel: '保存' },
);

const emit = defineEmits<{
  press: [key: KeypadKey];
}>();

const DIGITS = ['7', '8', '9', '4', '5', '6', '1', '2', '3'] as const;
</script>

<template>
  <!--
    4×4 宫格。**除数字键外的每一个键都必须显式定位。**

    原先只有「保存」显式定位，注释里写着「Grid 会先安置显式定位的元素再自动排布其余的，
    所以自动排布的数字会自动避开它，不必手工指定每个键的位置」—— 前半句是对的，
    后半个推论是错的：自动排布确实会避开「保存」占的格子，但**游标只往前推进**。
    ＋ 在文档里排在数字键之后，轮到它时游标已经走到第 2 行第 1 列，于是它落在最左边，
    把 . 0 00 全挤到第 2 行；第 3、4 行只剩「保存」孤零零一格。
    表现就是「键盘布局错乱」，但每个键本身都没写错。

    正确的排布：
        7 8 9 ⌫
        4 5 6 ＋
        1 2 3 保存
        . 0 00 保存(跨两行)
  -->
  <div class="grid grid-cols-4 grid-rows-4 gap-2 p-2">
    <button
      v-for="digit in DIGITS"
      :key="digit"
      type="button"
      class="rounded-md bg-surface py-3.5 text-xl font-semibold text-ink transition-transform duration-200 active:scale-95"
      @click="emit('press', digit)"
    >
      {{ digit }}
    </button>

    <button
      type="button"
      class="col-start-4 row-start-1 rounded-md bg-surface py-3.5 text-lg font-semibold text-ink-muted transition-transform duration-200 active:scale-95"
      aria-label="退格"
      @click="emit('press', 'back')"
    >
      ⌫
    </button>

    <button
      type="button"
      class="col-start-4 row-start-2 rounded-md bg-surface py-3.5 text-lg font-semibold text-primary-text transition-transform duration-200 active:scale-95"
      aria-label="加上一笔"
      @click="emit('press', 'plus')"
    >
      ＋
    </button>

    <button
      type="button"
      class="rounded-md bg-surface py-3.5 text-xl font-semibold text-ink transition-transform duration-200 active:scale-95"
      @click="emit('press', '.')"
    >
      .
    </button>
    <button
      type="button"
      class="rounded-md bg-surface py-3.5 text-xl font-semibold text-ink transition-transform duration-200 active:scale-95"
      @click="emit('press', '0')"
    >
      0
    </button>
    <button
      type="button"
      class="rounded-md bg-surface py-3.5 text-lg font-semibold text-ink-muted transition-transform duration-200 active:scale-95"
      @click="emit('press', '00')"
    >
      00
    </button>

    <button
      type="button"
      :disabled="!canSave || saving"
      class="col-start-4 row-span-2 row-start-3 rounded-md bg-primary-fill text-base font-bold text-on-primary transition-transform duration-200 active:scale-95 disabled:opacity-40 disabled:active:scale-100"
      @click="emit('press', 'save')"
    >
      {{ saving ? '…' : saveLabel }}
    </button>
  </div>
</template>
