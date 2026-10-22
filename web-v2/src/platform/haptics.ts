/**
 * 触感震动反馈适配器。
 * 纯 Web 与移动容器通用，静默异常降级。
 */
export function triggerHaptic(durationMs = 15): void {
  if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
    try {
      navigator.vibrate(durationMs);
    } catch {
      // 某些无权限或非安全上下文静默忽略
    }
  }
}
