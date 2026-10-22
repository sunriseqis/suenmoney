/**
 * 给登录会话起一个人类可读的设备名。
 *
 * 用途是设置页里的「当前登录的设备」——出现可疑会话时你能一眼看出
 * 是不是自己的设备，从而决定要不要踢掉它。用完整的 userAgent 字符串
 * 也能达到目的，但没人愿意读那一长串。
 */
export function deviceLabel(): string {
  const ua = navigator.userAgent;

  const platform = /iPhone|iPad|iPod/.test(ua)
    ? 'iPhone'
    : /Android/.test(ua)
      ? 'Android'
      : /Macintosh|Mac OS X/.test(ua)
        ? 'macOS'
        : /Windows/.test(ua)
          ? 'Windows'
          : /Linux/.test(ua)
            ? 'Linux'
            : '未知系统';

  // 顺序有讲究：Edge 与 Chrome 的 UA 里都含 "Chrome"，
  // 先判 Edge，否则永远会把它认成 Chrome
  const browser = /Edg\//.test(ua)
    ? 'Edge'
    : /OPR\//.test(ua)
      ? 'Opera'
      : /Chrome\//.test(ua)
        ? 'Chrome'
        : /Safari\//.test(ua)
          ? 'Safari'
          : /Firefox\//.test(ua)
            ? 'Firefox'
            : '浏览器';

  return `${browser} / ${platform}`;
}
