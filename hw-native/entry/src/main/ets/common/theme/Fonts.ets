/**
 * 字体族名解析（H0-6）。
 *
 * 字体注册统一走 `common/theme/FontRegistry.ets` 的 `ensureFonts`（用 `$rawfile` 资源路径，
 * 字符串路径在真机上静默失败）。这里只保留「标题 / 正文」的族名映射，
 * 返回值必须与 `ensureFonts` 注册的名字一致，否则会静默回落系统字体。
 */

/** 按主题给出「标题」字体族（与 Web 的 --font-display 同义） */
export function displayFont(themeIsCandy: boolean): string {
  return themeIsCandy ? 'Outfit' : 'Orbitron';
}

/** 按主题给出「正文」字体族（与 Web 的 --font-body 同义） */
export function bodyFont(themeIsCandy: boolean): string {
  return themeIsCandy ? 'Plus Jakarta Sans' : 'JetBrains Mono';
}
