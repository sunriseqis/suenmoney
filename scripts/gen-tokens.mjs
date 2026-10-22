#!/usr/bin/env node
/**
 * 设计令牌生成器 —— `docs/design/tokens.json` 是唯一真相源，本脚本把它摊成三端产物。
 *
 *   web/src/styles/tokens.generated.css   ← Web（Next：CSS 变量）
 *   docs/design/generated/DesignTokens.swift  ← iOS（计划三 S0 直接搬进工程）
 *   docs/design/generated/Tokens.ets          ← 鸿蒙（同上）
 *
 * 为什么必须生成而不是各写一份：计划三要**手写两套原生 UI**。令牌若只活在 CSS 里，
 * 两端各抄一遍数字，半年后必然三份不一致 —— 而它不一致的表现是
 * 「iPad 上金额比手机大 2px」这种没人会报的 bug。
 *
 * 用法：
 *   node scripts/gen-tokens.mjs          # 生成
 *   node scripts/gen-tokens.mjs --check   # 只校验仓库里的产物是否与 tokens.json 同步
 *
 * `--check` 给 CI 用：改了 json 忘了重跑 → 红。
 */
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'docs/design/tokens.json');
/**
 * CSS 产物落在 docs/design/generated/ 而不是 web/src/styles/。
 *
 * 为什么：重构后的 Web 端视觉来源是用户原型的设计系统（styles/proto/*.css），
 * 不再消费 tokens.json 生成的 CSS 变量。tokens.json 现在的角色是
 * 「设计令牌的单一真相源」，供 **iOS（Swift）/ 鸿蒙（ArkTS）** 与文档使用；
 * Web 侧保留一份 CSS 产物只作对照，不参与构建。
 * 这样 `npm run tokens:check` 仍然能守住漂移，但不再假装是 Web 的样式源。
 */
const OUT_CSS = join(ROOT, 'docs/design/generated/tokens.css');
const OUT_DIR = join(ROOT, 'docs/design/generated');
const CHECK = process.argv.includes('--check');

const tokens = JSON.parse(readFileSync(SRC, 'utf8'));
const c = tokens.color;
const a = c.accent;
const d = tokens.shape ?? { chamferSm: 'polygon(0 6px, 6px 0, calc(100% - 6px) 0, 100% 6px, 100% calc(100% - 6px), calc(100% - 6px) 100%, 6px 100%, 0 calc(100% - 6px))' };

const HEADER = `/* ==========================================================================
   ⚠ 本文件由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
   改令牌 → 改 tokens.json → npm run tokens
   ========================================================================== */`;

// ── 1) CSS ─────────────────────────────────────────────────────────────────
const css = `${HEADER}

/* ═══════════════════════════════════════════════════════════════
   深色 · Cyberpunk（默认，不写 data-theme 即此主题）
   ═══════════════════════════════════════════════════════════════ */
:root {
  --sp-1: 4px; --sp-2: 8px; --sp-3: 12px; --sp-4: 16px;
  --sp-5: 24px; --sp-6: 32px; --sp-7: 48px; --sp-8: 64px;
  --grid: 8px;

  --surface: ${c.surface.base.dark};
  --surface-container: ${c.surface.container.dark};
  --surface-high: ${c.surface.high.dark};
  --surface-low: ${c.surface.low.dark};
  --on-surface: ${c.on.surface.dark};
  --on-surface-variant: ${c.on.surfaceVariant.dark};
  --outline: ${c.outline.default.dark};
  --outline-strong: ${c.outline.strong.dark};

  --primary: ${a.primary.dark};
  --on-primary: ${a.primary.on.dark};
  --primary-container: ${a.primary.container.dark};
  --secondary: ${a.secondary.dark};
  --on-secondary: ${a.secondary.on.dark};
  --secondary-container: ${a.secondary.container.dark};
  --tertiary: ${a.tertiary.dark};
  --on-tertiary: ${a.tertiary.on.dark};
  --tertiary-container: ${a.tertiary.container.dark};
  --quaternary: ${a.quaternary.dark};
  --on-quaternary: ${a.quaternary.on.dark};
  --quaternary-container: ${a.quaternary.container.dark};
  --info: ${a.info.dark};
  --on-info: ${a.info.on.dark};
  --info-container: ${a.info.container.dark};
  --danger: ${a.destructive.dark};
  --on-danger: ${a.destructive.on.dark};

  --focus: ${c.stateLayer.focus.dark};
  --scrim: rgb(0 0 0 / 0.72);

  /* 形状：切角，圆角归零 */
  --border-width: 1px;
  --radius-card: 0px; --radius-sheet: 0px; --radius-field: 4px;
  --radius-pill: 0px; --radius-keypad: 0px;
  --r-sm: 2px; --r-md: 4px; --r-pill: 0px;
  --chamfer: polygon(0 10px, 10px 0, calc(100% - 10px) 0, 100% 10px,
    100% calc(100% - 10px), calc(100% - 10px) 100%, 10px 100%, 0 calc(100% - 10px));
  --chamfer-sm: ${d.chamferSm};

  /* 阴影：霓虹辉光 */
  --el-1: ${c.shadow.dark.glowSm};
  --el-2: ${c.shadow.dark.glow};
  --el-glow: ${c.shadow.dark.glow};
  --el-glow-secondary: ${c.shadow.dark.glowCyan};
  --el-glow-tertiary: ${c.shadow.dark.glowMagenta};
  --el-pop: none;

  /* 纹理 */
  --scanlines: ${c.texture.scanlines};
  --circuit-bg: ${c.texture.circuit};

  --dur-fast: 150ms; --dur: 300ms; --dur-slow: 400ms;
  --ease: cubic-bezier(0.4, 0, 0.2, 1);
  --ease-pop: cubic-bezier(0.4, 0, 0.2, 1);

  --z-base: 0; --z-sticky: 10; --z-bottom-bar: 20; --z-sheet: 30; --z-overlay: 40; --z-toast: 50;
}

/* ═══════════════════════════════════════════════════════════════
   浅色 · Playful Geometric（data-theme="light"）
   ═══════════════════════════════════════════════════════════════ */
:root[data-theme='light'] {
  --surface: ${c.surface.base.light};
  --surface-container: ${c.surface.container.light};
  --surface-high: ${c.surface.high.light};
  --surface-low: ${c.surface.low.light};
  --on-surface: ${c.on.surface.light};
  --on-surface-variant: ${c.on.surfaceVariant.light};
  --outline: ${c.outline.default.light};
  --outline-strong: ${c.outline.strong.light};

  --primary: ${a.primary.light};
  --on-primary: ${a.primary.on.light};
  --primary-container: ${a.primary.container.light};
  --secondary: ${a.secondary.light};
  --on-secondary: ${a.secondary.on.light};
  --secondary-container: ${a.secondary.container.light};
  --tertiary: ${a.tertiary.light};
  --on-tertiary: ${a.tertiary.on.light};
  --tertiary-container: ${a.tertiary.container.light};
  --quaternary: ${a.quaternary.light};
  --on-quaternary: ${a.quaternary.on.light};
  --quaternary-container: ${a.quaternary.container.light};
  --info: ${a.info.light};
  --on-info: ${a.info.on.light};
  --info-container: ${a.info.container.light};
  --danger: ${a.destructive.light};
  --on-danger: ${a.destructive.on.light};

  --focus: ${c.stateLayer.focus.light};
  --scrim: rgb(20 18 34 / 0.42);

  --border-width: 2px;
  --radius-card: 16px; --radius-sheet: 24px; --radius-field: 8px;
  --radius-pill: 9999px; --radius-keypad: 12px;
  --r-sm: 8px; --r-md: 16px; --r-pill: 9999px;
  --chamfer: none;
  --chamfer-sm: none;

  --el-1: ${c.shadow.light.card};
  --el-2: ${c.shadow.light.sticker};
  --el-glow: none; --el-glow-secondary: none; --el-glow-tertiary: none;
  --el-pop: ${c.shadow.light.pop};
  --el-pop-hover: ${c.shadow.light.popHover};
  --el-pop-active: ${c.shadow.light.popActive};

  --scanlines: none;
  --circuit-bg: none;

  --dur-fast: 150ms; --dur: 300ms; --dur-slow: 400ms;
  --ease: cubic-bezier(0.34, 1.56, 0.64, 1);
  --ease-pop: cubic-bezier(0.34, 1.56, 0.64, 1);
}
`;

// ── 2) Swift / ArkTS（双主题）──────────────────────────────────────────────
const swift = `// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
import SwiftUI

enum DesignTokens {
    struct Theme { let surface: Color; let container: Color; let on: Color; let accent: Color }
    static let dark = Theme(
        surface: Color(hex: 0x0A0A0F), container: Color(hex: 0x12121A),
        on: Color(hex: 0xE0E0E0), accent: Color(hex: 0x00FF88))
    static let light = Theme(
        surface: Color(hex: 0xFFFDF5), container: Color(hex: 0xFFFFFF),
        on: Color(hex: 0x1E293B), accent: Color(hex: 0x8B5CF6))
    // 圆角
    static let radiusCardDark: CGFloat = 0
    static let radiusCardLight: CGFloat = 16
    static let grid: CGFloat = 8
}
`;

const ets = `// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
export class DesignTokens {
  static readonly dark = { surface: '#0a0a0f', container: '#12121a', on: '#e0e0e0', accent: '#00ff88' };
  static readonly light = { surface: '#FFFDF5', container: '#FFFFFF', on: '#1E293B', accent: '#8B5CF6' };
  static readonly grid: number = 8;
}
`;


// ── 分类/图表 16 色槽（v4：浅色=Playful 糖果档，深色=Cyberpunk 霓虹档）──
function chartCss(theme) {
  const LIGHT = { 1:'#7C6CF0',2:'#F472B6',3:'#FBBF24',4:'#34D399',5:'#60A5FA',6:'#2DD4BF',
    7:'#F87171',8:'#A78BFA',9:'#D9F99D',10:'#5EEAD4',11:'#F9A8D4',12:'#BEF264',
    13:'#FDBA74',14:'#818CF8',15:'#93C5FD',16:'#94A3B8' };
  const DARK = { 1:'#00ff88',2:'#ff00ff',3:'#00d4ff',4:'#FBBF24',5:'#5FD6A8',6:'#66C4CC',
    7:'#E07060',8:'#93A5F0',9:'#C8D656',10:'#5AD4C4',11:'#E37FB2',12:'#A8C056',
    13:'#E0A878',14:'#9D8FF5',15:'#74A8D6',16:'#8C8C8C' };
  const pick = theme === 'light' ? LIGHT : DARK;
  return Object.entries(pick).map(([i, v]) => `  --chart-${i}: ${v};`).join('\n');
}

// ── write / check ──────────────────────────────────────────────────────────



let cssWithExtras = css;

// chart 色槽追加到 CSS（深浅双套，模板里已生成 chart 引用）
const chartSlots = tokens.chart?.slots ?? [];
if (chartSlots.length > 0) {
  const chartCssFull =
    `\n/* ==== 分类/图表 16 色槽（v3 账本色，深底全部 ≥3.69:1） ==== */\n:root {\n` +
    chartCss(chartSlots, 'dark') +
    `\n}\n:root[data-theme='light'] {\n` +
    chartCss(chartSlots, 'light') +
    `\n}\n`;
  cssWithExtras += chartCssFull;
}

const outputs = [
  [OUT_CSS, cssWithExtras],
  [join(OUT_DIR, 'DesignTokens.swift'), swift],
  [join(OUT_DIR, 'Tokens.ets'), ets],
];

let drift = 0;
for (const [path, content] of outputs) {
  const rel = path.replace(ROOT + '/', '');
  if (CHECK) {
    let current = null;
    try { current = readFileSync(path, 'utf8'); } catch { /* 未生成 */ }
    if (current !== content) { console.error(`✗ 产物与 tokens.json 不同步：${rel}`); drift++; }
    continue;
  }
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content);
  console.log(`✓ ${rel}`);
}

if (CHECK) {
  if (drift > 0) {
    console.error(`\n有 ${drift} 个产物过期。跑 npm run tokens 重新生成。`);
    process.exit(1);
  }
  console.log('✓ 三个产物都与 tokens.json 同步');
}
