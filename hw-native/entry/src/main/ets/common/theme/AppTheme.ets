/**
 * 主题令牌 —— **由 scripts/gen-hw-theme.mjs 从 web/styles/proto/theme.css 生成，请勿手改**。
 *
 * 两套设计语言：candy（水果硬糖 / 浅色）与 cyber（赛博朋克 / 深色）。
 * 共 51 个令牌，与原型 CSS 变量一一对应；映射表见 docs/design/generated/hw-theme-mapping.md。
 *
 * ArkTS 约束：不用对象字面量的动态 key 访问，所以这里是「接口 + 两个常量对象」，
 * 取字段一律走 `theme.bg` 这种静态成员访问。
 */

export interface ThemeTokens {
  densityPad: number;
  densityRow: number;
  bg: string;
  bg2: string;
  bg3: string;
  surface: string;
  surface2: string;
  surface3: string;
  line: string;
  line2: string;
  line3: string;
  ink: string;
  ink2: string;
  ink3: string;
  accent: string;
  accentInk: string;
  cyan: string;
  pink: string;
  amber: string;
  mint: string;
  sky: string;
  danger: string;
  warn: string;
  ok: string;
  onColor: string;
  rCard: number;
  rMd: number;
  rSm: number;
  rPill: number;
  borderW: number;
  fontDisplay: string;
  fontBody: string;
  fontMono: string;
  shadowCard: string;
  shadowCardPop: string;
  shadowBtn: string;
  shadowBtnHover: string;
  shadowBtnActive: string;
  shadowSoft: string;
  navBg: string;
  scrim: string;
  glow: string;
  chart1: string;
  chart2: string;
  chart3: string;
  chart4: string;
  chart5: string;
  chart6: string;
  chart7: string;
  chart8: string;
  fontScale: string;
}

export const CANDY: ThemeTokens = {
  densityPad: 18,
  densityRow: 12,
  bg: "#FFFDF5",
  bg2: "#FFF8E7",
  bg3: "#F6F3FF",
  surface: "#FFFFFF",
  surface2: "#F8F7FF",
  surface3: "#F1F5F9",
  line: "#E2E8F0",
  line2: "#1E293B",
  line3: "#CBD5E1",
  ink: "#1E293B",
  ink2: "#64748B",
  ink3: "#94A3B8",
  accent: "#8B5CF6",
  accentInk: "#FFFFFF",
  cyan: "#22D3EE",
  pink: "#F472B6",
  amber: "#FBBF24",
  mint: "#34D399",
  sky: "#38BDF8",
  danger: "#EF4444",
  warn: "#F59E0B",
  ok: "#10B981",
  onColor: "#1E293B",
  rCard: 20,
  rMd: 14,
  rSm: 9,
  rPill: 999,
  borderW: 2,
  fontDisplay: "'Outfit', 'Noto Sans SC', system-ui, sans-serif",
  fontBody: "'Plus Jakarta Sans', 'Noto Sans SC', system-ui, sans-serif",
  fontMono: "'Plus Jakarta Sans', ui-monospace, monospace",
  shadowCard: "6px 6px 0 #E9EEF6",
  shadowCardPop: "8px 8px 0 #1E293B",
  shadowBtn: "3px 3px 0 #1E293B",
  shadowBtnHover: "5px 5px 0 #1E293B",
  shadowBtnActive: "1px 1px 0 #1E293B",
  shadowSoft: "0 10px 24px -18px rgba(30, 41, 59, 0.6)",
  navBg: "rgba(255, 253, 245, 0.9)",
  scrim: "rgba(30, 41, 59, 0.35)",
  glow: "none",
  chart1: "#8B5CF6",
  chart2: "#F472B6",
  chart3: "#FBBF24",
  chart4: "#34D399",
  chart5: "#38BDF8",
  chart6: "#A78BFA",
  chart7: "#FB7185",
  chart8: "#22D3EE",
  fontScale: "1",
};

export const CYBER: ThemeTokens = {
  densityPad: 18,
  densityRow: 12,
  bg: "#0a0a0f",
  bg2: "#0d0d16",
  bg3: "#10101c",
  surface: "#12121a",
  surface2: "#1c1c2e",
  surface3: "#16162a",
  line: "#2a2a3a",
  line2: "#2a2a3a",
  line3: "#3b3b52",
  ink: "#e0e0e0",
  ink2: "#8f93ad",
  ink3: "#6b7280",
  accent: "#00ff88",
  accentInk: "#04220f",
  cyan: "#00d4ff",
  pink: "#ff00ff",
  amber: "#ffb020",
  mint: "#00ff88",
  sky: "#00d4ff",
  danger: "#ff3366",
  warn: "#ffb020",
  ok: "#00ff88",
  onColor: "#05050c",
  rCard: 2,
  rMd: 2,
  rSm: 2,
  rPill: 2,
  borderW: 1,
  fontDisplay: "'Orbitron', 'Share Tech Mono', 'Noto Sans SC', monospace",
  fontBody: "'JetBrains Mono', 'Noto Sans SC', ui-monospace, monospace",
  fontMono: "'Share Tech Mono', 'JetBrains Mono', ui-monospace, monospace",
  shadowCard: "0 0 0 rgba(0, 0, 0, 0)",
  shadowCardPop: "0 0 0 rgba(0, 0, 0, 0)",
  shadowBtn: "none",
  shadowBtnHover: "0 0 12px rgba(0, 255, 136, 0.45)",
  shadowBtnActive: "none",
  shadowSoft: "0 0 20px -10px rgba(0, 212, 255, 0.5)",
  navBg: "rgba(8, 8, 14, 0.92)",
  scrim: "rgba(2, 2, 8, 0.78)",
  glow: "0 0 10px rgba(0, 255, 136, 0.55)",
  chart1: "#00ff88",
  chart2: "#ff00ff",
  chart3: "#00d4ff",
  chart4: "#ffb020",
  chart5: "#8b5cff",
  chart6: "#00a3ff",
  chart7: "#ff3366",
  chart8: "#7dffd0",
  fontScale: "1",
};
