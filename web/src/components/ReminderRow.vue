<script setup lang="ts">
/**
 * 待办提醒行（带左滑手势）。
 *
 * 交互口径（原型 + 用户裁决）：**左滑超过 60% 宽度才触发「忽略」**，
 * 松手未达标弹回。为什么是 60% 而不是 30%：忽略会改变账本状态（那一期
 * 不再提醒），太容易误触；60% 需要明确的、有意图的一次滑动。
 *
 * 桌面没有滑动语义，所以同时保留右侧的普通按钮入口 —— 手势是移动端的加速器，
 * 不是唯一入口（这点与「下拉记账」不同，那条是用户明确要求不留兜底的）。
 */
import { computed, ref } from 'vue';

const props = defineProps<{
  /** 行宽参考值（px），用于算 60% 阈值；0 表示按容器实测 */
  title: string;
  sub?: string;
  amount: string;
  /** 是否允许左滑忽略（已入账的行不允许） */
  swipeable?: boolean;
}>();

const emit = defineEmits<{ skip: []; confirm: []; ack: [] }>();

const track = ref<HTMLElement | null>(null);
const dx = ref(0);
const dragging = ref(false);
let startX = 0;
let width = 0;

const THRESHOLD = 0.6;

const offset = computed(() => Math.min(0, dx.value));
const armed = computed(() => props.swipeable !== false && width > 0 && Math.abs(offset.value) >= width * THRESHOLD);
const label = computed(() => (armed.value ? '松开忽略' : '左滑忽略'));

function onDown(e: PointerEvent): void {
  if (props.swipeable === false) return;
  width = track.value?.offsetWidth ?? 0;
  startX = e.clientX;
  dragging.value = true;
  (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
}

function onMove(e: PointerEvent): void {
  if (!dragging.value) return;
  const delta = e.clientX - startX;
  // 只接受左滑；少量右滑给一点阻尼回弹，避免完全僵住
  dx.value = delta < 0 ? Math.max(-width * 0.92, delta) : Math.min(24, delta * 0.3);
}

function onUp(): void {
  if (!dragging.value) return;
  dragging.value = false;
  if (armed.value) emit('skip');
  dx.value = 0;
}
</script>

<template>
  <div ref="track" class="reminder" :data-armed="armed ? 'true' : 'false'">
    <!-- 滑出区：告诉用户这一下会发生什么 -->
    <div v-if="swipeable !== false" class="rw-behind">
      <span>{{ label }}</span>
    </div>

    <div
      class="rw-track"
      :style="{
        transform: `translateX(${offset}px)`,
        transition: dragging ? 'none' : 'transform 0.24s cubic-bezier(0.22, 1, 0.36, 1)',
      }"
      @pointerdown="onDown"
      @pointermove="onMove"
      @pointerup="onUp"
      @pointercancel="onUp"
    >
      <span class="rw-main">
        <span class="rw-t">{{ title }}</span>
        <span v-if="sub" class="rw-s">{{ sub }}</span>
      </span>
      <span class="rw-amt mono">{{ amount }}</span>
      <slot />
    </div>
  </div>
</template>

<style scoped>
.reminder {
  position: relative;
  overflow: hidden;
  border-radius: var(--r-sm);
}
.rw-behind {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  padding-right: 14px;
  background: color-mix(in srgb, var(--danger) 14%, var(--surface));
  color: var(--danger);
  font-family: var(--font-mono);
  font-size: 10.5px;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.reminder[data-armed='true'] .rw-behind {
  background: var(--danger);
  color: #fff;
}
.rw-track {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 2px;
  background: var(--surface);
  touch-action: pan-y;
  cursor: grab;
}
.rw-main {
  min-width: 0;
  flex: 1 1 auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.rw-t {
  font-size: 12.5px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.rw-s {
  font-size: 10.5px;
  color: var(--ink-3);
}
.rw-amt {
  font-size: 12.5px;
  font-weight: 600;
  flex: 0 0 auto;
}
</style>
