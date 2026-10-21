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
const OUT_CSS = join(ROOT, 'web/src/styles/tokens.generated.css');
const OUT_DIR = join(ROOT, 'docs/design/generated');
const CHECK = process.argv.includes('--check');

const tokens = JSON.parse(readFileSync(SRC, 'utf8'));
const c = tokens.color;
const a = c.accent;

const HEADER = `/* ==========================================================================
   ⚠ 本文件由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
   改令牌 → 改 tokens.json → npm run tokens
   ========================================================================== */`;

// ── 1) CSS ─────────────────────────────────────────────────────────────────
const css = `${HEADER}

:root {
  /* ---- 间距（4px 基数，v3 用 8px 栅格） ---- */
  --sp-1: 4px;   --sp-2: 8px;   --sp-3: 12px;  --sp-4: 16px;
  --sp-5: 24px;  --sp-6: 32px;  --sp-7: 48px;  --sp-8: 64px;
  --grid: 8px;

  /* ---- 圆角（M3：卡 24 / 输入 14 / FAB 28 / 胶囊全圆） ---- */
  --radius-card: ${tokens.shape.card.value};
  --radius-sheet: ${tokens.shape.sheet.value};
  --radius-field: ${tokens.shape.field.value};
  --radius-fab: ${tokens.shape.fab.value};
  --radius-pill: ${tokens.shape.pill.value};
  --radius-keypad: ${tokens.shape.keypad.value};

  /* ---- 字号（v3 阶梯；旧名保留，值为 v3 档位） ---- */
  --fs-xs: 11px;        /* 辅助标签，全大写 + 字距 0.5px */
  --fs-sm: 12px;
  --fs-md: 15px;        /* 正文 / 流水行 */
  --fs-lg: 17px;
  --fs-xl: 22px;
  --fs-2xl: 28px;
  --fs-3xl: 32px;       /* 页面大标题 */
  --fs-card-title: 16px;
  --fs-amount: 44px;    /* 大数字（规格 40–48） */
  --fs-display: 48px;
  --fs-hero: 56px;

  --lh-tight: 1.15; --lh-normal: 1.6; --lh-relaxed: 1.7;

  --fw-regular: 400; --fw-medium: 500; --fw-semibold: 600; --fw-bold: 700; --fw-extrabold: 800;

  /* ---- 动效（M3 emphasized，全站唯一曲线） ---- */
  --dur-fast: ${tokens.motion.durationFast.value};
  --dur: ${tokens.motion.durationMid.value};
  --dur-slow: ${tokens.motion.durationSlow.value};
  --ease: ${tokens.motion.easing.value};

  /* ---- 层级 ---- */
  --z-base: 0; --z-sticky: 10; --z-bottom-bar: 20; --z-sheet: 30; --z-overlay: 40; --z-toast: 50;

  /* ======================================================================
     颜色 · v3 深色（**默认主题**，不看系统偏好）
     ====================================================================== */
  /* 表面三层 */
  --surface: ${c.surface.base.value};
  --surface-container: ${c.surface.container.value};
  --surface-high: ${c.surface.high.value};

  /* 文字 */
  --on-surface: ${c.on.surface.value};
  --on-surface-variant: ${c.on.surfaceVariant.value};

  /* 描边：default 只做分隔线，strong 给可交互控件（WCAG 1.4.11 要 ≥3:1） */
  --outline: ${c.outline.default.value};
  --outline-strong: ${c.outline.strong.value};

  /* 五色（各自带 on- 深字与 12% container） */
  --primary: ${a.primary.value};
  --on-primary: ${a.primary.on};
  --primary-container: ${a.primary.container};
  --secondary: ${a.secondary.value};
  --on-secondary: ${a.secondary.on};
  --secondary-container: ${a.secondary.container};
  --tertiary: ${a.tertiary.value};
  --on-tertiary: ${a.tertiary.on};
  --tertiary-container: ${a.tertiary.container};
  --lemon: ${a.lemon.value};
  --on-lemon: ${a.lemon.on};
  --lemon-container: ${a.lemon.container};
  --info: ${a.blue.value};
  --on-info: ${a.blue.on};
  --info-container: ${a.blue.container};

  --focus: ${c.stateLayer.focus.value};
  --scrim: rgb(0 0 0 / 0.62);

  /* 高度 */
  --el-1: ${tokens.elevation.level1.value};
  --el-2: ${tokens.elevation.level2.value};

  /* ======================================================================
     兼容别名：老组件用的还是这套名字，映射到 v3 值 ——
     这样「全站先变暗」不需要一次性改两百个类名。
     逐条对照见 docs/design/suenmoney-v3-design-system.md §七。
     ====================================================================== */
  --bg: var(--surface);
  --bg-subtle: var(--surface-container);
  --bg-sunken: var(--surface-high);
  --fg: var(--on-surface);
  --fg-muted: var(--on-surface-variant);
  --fg-faint: #8E8878;              /* 深底 4.9:1，仅用于占位与最弱说明 */
  --border: var(--outline);
  --border-strong: var(--outline-strong);

  --primary-fill: var(--primary);
  --primary-text: var(--primary);
  --secondary-fill: var(--secondary);
  --secondary-text: var(--secondary);
  --accent: var(--tertiary);        /* 旧「琥珀=待处理」并入霓虹粉 */
  --accent-fill: var(--tertiary);
  --accent-text: var(--tertiary);
  --on-accent: var(--on-tertiary);
  --danger: var(--tertiary);
  --danger-fill: var(--tertiary);
  --danger-text: var(--tertiary);
  --on-danger: var(--on-tertiary);

  /* 圆角旧名（组件大量使用） */
  --r-sm: var(--radius-field);
  --r-md: var(--radius-card);
  --r-pill: var(--radius-pill);
}
`;

// ── 2) Swift ───────────────────────────────────────────────────────────────
const hex = (v) => `Color(hex: 0x${v.replace('#', '').toUpperCase()})`;
const swift = `// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
// 计划三 S0 时搬进 ios/SuenMoney/UI/DesignTokens.swift，并补 Color(hex:) 扩展。
import SwiftUI

enum DesignTokens {
    // 表面
    static let surface = ${hex(c.surface.base.value)}
    static let surfaceContainer = ${hex(c.surface.container.value)}
    static let surfaceHigh = ${hex(c.surface.high.value)}
    // 文字
    static let onSurface = ${hex(c.on.surface.value)}
    static let onSurfaceVariant = ${hex(c.on.surfaceVariant.value)}
    // 描边
    static let outline = ${hex(c.outline.default.value)}
    static let outlineStrong = ${hex(c.outline.strong.value)}
    // 五色
    static let primary = ${hex(a.primary.value)}
    static let onPrimary = ${hex(a.primary.on)}
    static let secondary = ${hex(a.secondary.value)}
    static let onSecondary = ${hex(a.secondary.on)}
    static let tertiary = ${hex(a.tertiary.value)}
    static let onTertiary = ${hex(a.tertiary.on)}
    static let lemon = ${hex(a.lemon.value)}
    static let onLemon = ${hex(a.lemon.on)}
    static let info = ${hex(a.blue.value)}
    static let onInfo = ${hex(a.blue.on)}

    // 圆角 / 间距 / 动效
    static let radiusCard: CGFloat = 24
    static let radiusSheet: CGFloat = 24
    static let radiusField: CGFloat = 14
    static let radiusPill: CGFloat = 999
    static let grid: CGFloat = 8
    static let durationsFast: Double = 0.2
    static let durationsMid: Double = 0.35
    static let durationsSlow: Double = 0.4
}
`;

// ── 3) ArkTS ───────────────────────────────────────────────────────────────
const ets = `// ⚠ 由 scripts/gen-tokens.mjs 从 docs/design/tokens.json 生成，请勿手改。
// 计划三 S0 时搬进 hw/entry/src/main/ets/common/Tokens.ets。
export class DesignTokens {
  // 表面
  static readonly surface: string = '${c.surface.base.value}';
  static readonly surfaceContainer: string = '${c.surface.container.value}';
  static readonly surfaceHigh: string = '${c.surface.high.value}';
  // 文字
  static readonly onSurface: string = '${c.on.surface.value}';
  static readonly onSurfaceVariant: string = '${c.on.surfaceVariant.value}';
  // 描边
  static readonly outline: string = '${c.outline.default.value}';
  static readonly outlineStrong: string = '${c.outline.strong.value}';
  // 五色
  static readonly primary: string = '${a.primary.value}';
  static readonly onPrimary: string = '${a.primary.on}';
  static readonly secondary: string = '${a.secondary.value}';
  static readonly onSecondary: string = '${a.secondary.on}';
  static readonly tertiary: string = '${a.tertiary.value}';
  static readonly onTertiary: string = '${a.tertiary.on}';
  static readonly lemon: string = '${a.lemon.value}';
  static readonly onLemon: string = '${a.lemon.on}';
  static readonly info: string = '${a.blue.value}';
  static readonly onInfo: string = '${a.blue.on}';

  // 圆角 / 间距
  static readonly radiusCard: number = 24;
  static readonly radiusField: number = 14;
  static readonly radiusPill: number = 999;
  static readonly grid: number = 8;
}
`;



function lightBlock(L) {
  const rows = [
    ['--surface', L['surface']],
    ['--surface-container', L['surface-container']],
    ['--surface-high', L['surface-high']],
    ['--on-surface', L['on-surface']],
    ['--on-surface-variant', L['on-surface-variant']],
    ['--outline', L['outline']],
    ['--outline-strong', L['outline-strong']],
    ['--primary', L['primary']],
    ['--on-primary', L['on-primary']],
    ['--primary-container', L['primary-container']],
    ['--secondary', L['secondary']],
    ['--on-secondary', L['on-secondary']],
    ['--secondary-container', L['secondary-container']],
    ['--tertiary', L['tertiary']],
    ['--on-tertiary', L['on-tertiary']],
    ['--tertiary-container', L['tertiary-container']],
    ['--lemon', L['lemon']],
    ['--on-lemon', L['on-lemon']],
    ['--lemon-container', L['lemon-container']],
    ['--info', L['info']],
    ['--on-info', L['on-info']],
    ['--info-container', L['info-container']],
    ['--focus', L['focus']],
    ['--scrim', L['scrim']],
  ];
  return `
/* ==========================================================================
   浅色主题（data-theme="light"）
   --------------------------------------------------------------------------
   **同产品不同光**：结构、圆角、字号完全一致，只换色阶。
   刻意不复用旧扁平浅色 —— 那会变成「两个产品」而不是「两种光线」。
   ========================================================================== */
:root[data-theme='light'] {
` + rows.map(([k, v]) => `  ${k}: ${v};`).join('\n') + `\n}\n`;
}


// ── 分类/图表 16 色槽（tokens.json → chart.slots）──────────────────────────
function chartCss(slots, theme) {
  // 浅色主题：同色相压深（分类色在白卡上要 ≥3:1），深色主题直接用
  const DARK = { 1:'#6E9EEA',2:'#5C9E78',3:'#C0894A',4:'#9A8AC9',5:'#C4737E',6:'#5FA0A7',
    7:'#B85C50',8:'#7E8FC9',9:'#A0A050',10:'#4FA8A0',11:'#B06A9E',12:'#8A9A55',
    13:'#C98B5F',14:'#7A6FC9',15:'#5C8AB0',16:'#8C8C8C' };
  const LIGHT = { 1:'#2E5FB8',2:'#2F6D4E',3:'#8A5A20',4:'#6B5CA5',5:'#A63A55',6:'#2F6D74',
    7:'#8F3E33',8:'#4F5FA5',9:'#5C5300',10:'#1F6D66',11:'#7E3A68',12:'#556430',
    13:'#8A5A30',14:'#4F46A0',15:'#2E5A80',16:'#6B6B6B' };
  const pick = theme === 'light' ? LIGHT : DARK;
  return slots.map((s) => `  --chart-${s.index}: ${pick[s.index] ?? s.value};`).join('\n');
}

// ── write / check ──────────────────────────────────────────────────────────



let cssWithExtras = css;

// 浅色主题追加到 CSS
const light = tokens.theme?.light;
if (light) {
  cssWithExtras += lightBlock(light);
}

// chart 色槽追加到 CSS（浅色主题同生成）
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
