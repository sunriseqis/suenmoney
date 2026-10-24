# 令牌对照表（生成物，勿手改）

> 来源：`web/styles/proto/theme.css` · 生成器：`scripts/gen-hw-token-table.mjs`
> 令牌数 **51**（:root 2 · candy 48 · cyber 49）

| # | CSS 变量 | candy | cyber |
|---|---|---|---|
| 1 | `--density-pad` | `18px` | `18px` |
| 2 | `--density-row` | `12px` | `12px` |
| 3 | `--bg` | `#FFFDF5` | `#0a0a0f` |
| 4 | `--bg-2` | `#FFF8E7` | `#0d0d16` |
| 5 | `--bg-3` | `#F6F3FF` | `#10101c` |
| 6 | `--surface` | `#FFFFFF` | `#12121a` |
| 7 | `--surface-2` | `#F8F7FF` | `#1c1c2e` |
| 8 | `--surface-3` | `#F1F5F9` | `#16162a` |
| 9 | `--line` | `#E2E8F0` | `#2a2a3a` |
| 10 | `--line-2` | `#1E293B` | `#2a2a3a` |
| 11 | `--line-3` | `#CBD5E1` | `#3b3b52` |
| 12 | `--ink` | `#1E293B` | `#e0e0e0` |
| 13 | `--ink-2` | `#64748B` | `#8f93ad` |
| 14 | `--ink-3` | `#94A3B8` | `#6b7280` |
| 15 | `--accent` | `#8B5CF6` | `#00ff88` |
| 16 | `--accent-ink` | `#FFFFFF` | `#04220f` |
| 17 | `--cyan` | `#22D3EE` | `#00d4ff` |
| 18 | `--pink` | `#F472B6` | `#ff00ff` |
| 19 | `--amber` | `#FBBF24` | `#ffb020` |
| 20 | `--mint` | `#34D399` | `#00ff88` |
| 21 | `--sky` | `#38BDF8` | `#00d4ff` |
| 22 | `--danger` | `#EF4444` | `#ff3366` |
| 23 | `--warn` | `#F59E0B` | `#ffb020` |
| 24 | `--ok` | `#10B981` | `#00ff88` |
| 25 | `--on-color` | `#1E293B` | `#05050c` |
| 26 | `--r-card` | `20px` | `2px` |
| 27 | `--r-md` | `14px` | `2px` |
| 28 | `--r-sm` | `9px` | `2px` |
| 29 | `--r-pill` | `999px` | `2px` |
| 30 | `--border-w` | `2px` | `1px` |
| 31 | `--font-display` | `'Outfit', 'Noto Sans SC', system-ui, sans-serif` | `'Orbitron', 'Share Tech Mono', 'Noto Sans SC', monospace` |
| 32 | `--font-body` | `'Plus Jakarta Sans', 'Noto Sans SC', system-ui, sans-serif` | `'JetBrains Mono', 'Noto Sans SC', ui-monospace, monospace` |
| 33 | `--font-mono` | `'Plus Jakarta Sans', ui-monospace, monospace` | `'Share Tech Mono', 'JetBrains Mono', ui-monospace, monospace` |
| 34 | `--shadow-card` | `6px 6px 0 #E9EEF6` | `0 0 0 rgba(0, 0, 0, 0)` |
| 35 | `--shadow-card-pop` | `8px 8px 0 #1E293B` | `0 0 0 rgba(0, 0, 0, 0)` |
| 36 | `--shadow-btn` | `3px 3px 0 #1E293B` | `none` |
| 37 | `--shadow-btn-hover` | `5px 5px 0 #1E293B` | `0 0 12px rgba(0, 255, 136, 0.45)` |
| 38 | `--shadow-btn-active` | `1px 1px 0 #1E293B` | `none` |
| 39 | `--shadow-soft` | `0 10px 24px -18px rgba(30, 41, 59, 0.6)` | `0 0 20px -10px rgba(0, 212, 255, 0.5)` |
| 40 | `--nav-bg` | `rgba(255, 253, 245, 0.9)` | `rgba(8, 8, 14, 0.92)` |
| 41 | `--scrim` | `rgba(30, 41, 59, 0.35)` | `rgba(2, 2, 8, 0.78)` |
| 42 | `--glow` | `none` | `0 0 10px rgba(0, 255, 136, 0.55)` |
| 43 | `--chart-1` | `#8B5CF6` | `#00ff88` |
| 44 | `--chart-2` | `#F472B6` | `#ff00ff` |
| 45 | `--chart-3` | `#FBBF24` | `#00d4ff` |
| 46 | `--chart-4` | `#34D399` | `#ffb020` |
| 47 | `--chart-5` | `#38BDF8` | `#8b5cff` |
| 48 | `--chart-6` | `#A78BFA` | `#00a3ff` |
| 49 | `--chart-7` | `#FB7185` | `#ff3366` |
| 50 | `--chart-8` | `#22D3EE` | `#7dffd0` |
| 51 | `--font-scale` | `—` | `1` |

## 分类色的两种用法
- `--chart-1..8` 是**色板**；分类只存**色号**（1–16），显示时取 `chart[(n-1) % 8]`。
- 图标底色是 `color-mix(色 12%, transparent)`、描边 `color-mix(色 45%, transparent)`；
  ArkUI 没有 `color-mix()`，实现用 `common/ui/UiStyle.ets` 的 `mixHex(hex, bg, ratio)` 运行时算。
