# Web 移动端（≤860px）界面 · 可视化事实清单

> 用途：供另一人据此在 HarmonyOS ArkUI 中 1:1 重建 **Web 移动端（≤860px）** 界面。
> 本文只做**事实摘录**（数值、类名、选择器、层级），不评价、不建议、不写业务逻辑。
> 所有数值均来自实际读到的文件，行号写在括号里；无法从代码确定的一律进 `E` 节。

## 0. 读取范围与样式级联顺序（事实基础）

样式入口 `web/styles/index.css`（4 行）按此顺序 @import，**后导入者覆盖先导入者**（同特异性时）：

```
@import './proto/theme.css';   /* 250 行 */
@import './proto/app.css';     /* 782 行 */
@import './proto/views.css';   /* 1163 行 */
@import './base.css';          /* 222 行 */
```

关键含义（下文所有"最终值"判定都按此规则）：
- `base.css` 最后加载，其中移动端规则带 `!important`（`.topbar-txt` / `.topbar-actions` / `.topbar--bare` / `.pull-hint` 在 ≤860px 全部 `display:none !important`）。
- `views.css` 内有 **6 个独立的 `@media (max-width:860px)` 块**（第 772–789、859–916、919–937、990–1006、1113–1123、1126–1163 行）与 1 个 `@media (min-width:861px)` 块（1007–1009），彼此按出现顺序层叠；同一属性取**最后一次**声明。
- Vue 组件的 `<style scoped>` 会加 `[data-v-*]` 属性选择器，特异性高于同形类选择器；因此**组件 scoped 样式会压过 views.css 里的移动端覆盖**（例：`.keys .key` 的 `min-height` 由 ExpenseSheet.vue 的 `clamp()` 胜出，而非 views.css 的 `46px`）。凡遇此类冲突，本文两处声明都写出并注明谁生效。
- 组件内联 `style=""` 优先级最高（例：`PDonut` 的内联 `width/height`）。

主题与断点载体（事实）：
- 根节点 `.app` 携带三个 data 属性：`:data-theme="theme.proto.value"`（取值 `candy` | `cyber`）、`data-decor="on"`（固定值，无切换入口）、`data-density="cozy"`（固定值；CSS 只有 `compact` 分支，故 `cozy` 落到 `:root` 的默认密度）。
- 登录页根节点是 `<div class="app login-page" :data-theme=... data-decor="on">`（无 `data-density`）。
- 移动端判定：`window.matchMedia('(max-width: 860px)')`（App.vue:135）、路由 `MOBILE_MAX = 860; window.innerWidth <= 860`（router/index.ts:15-17）。
- 移动端落地页 = **流水**（router `/` → mobile `{name:'ledger'}`，桌面 `{name:'dashboard'}`）。

---

## A. 令牌表

`theme.css` 中 `:root` 只有 2 个令牌；两套主题变量分别定义在 `.app[data-theme="candy"]`（第 32–86 行）与 `.app[data-theme="cyber"]`（第 89–145 行）。

### A.1 结构 / 密度令牌

| CSS 变量 | candy | cyber | 用途 |
|---|---|---|---|
| `--density-pad` | `18px`（`:root`，第 8 行） | 同（cyber 块未重定义） | `.card` 内边距（`.card{padding:var(--density-pad)}` app.css:294）。`.app[data-density="compact"]` 时 14px（theme.css:242），本工程不用 |
| `--density-row` | `12px`（`:root`，第 9 行） | 同 | 表格行内边距（`.tbl td{padding:var(--density-row) 10px}` app.css:521） |
| `--border-w` | `2px` | `1px` | 所有描边宽度母值（`.card` `.btn` `.input` `.seg` `.icon-btn` `.switch`…） |
| `--r-card` | `20px` | `2px` | `.card` / `.modal` / `.picker` / `.annual-hero` / `.report-banner` 圆角 |
| `--r-md` | `14px` | `2px` | `.nav-item` `.input` `.m-row` `.sheet-cell` `.pay-item` `.year-cell` `.todo-row` `.alert-strip` `.danger-zone` 等 |
| `--r-sm` | `9px` | `2px` | `.more-menu > summary` `.preview-box` `.quick-cats` `.hero-todo` `.todo-swipe-bg` `.insight`（右侧圆角）等 |
| `--r-pill` | `999px` | `2px` | `.btn` `.icon-btn` `.seg` `.chip` `.tag`(硬写 999) `.toast` `.mh-btn` `.quick-cat` |
| `--font-scale` | **未定义**（candy 块内无该变量） | `1` | 全仓无任何规则引用（见 E 节） |

> 移动端 `.card` 的圆角与阴影被**硬编码覆盖**为 `16px` / `3px 3px 0 #E9EEF6`（app.css:759，非变量），cyber 下再改回 `border-radius:0; box-shadow:none`（app.css:760）。

### A.2 颜色令牌

| CSS 变量 | candy | cyber | 用途 |
|---|---|---|---|
| `--bg` | `#FFFDF5` | `#0a0a0f` | 页面底色 `.app` / `.sheet` / `.modal` / `.picker` |
| `--bg-2` | `#FFF8E7` | `#0d0d16` | 侧边栏底色（candy） |
| `--bg-3` | `#F6F3FF` | `#10101c` | 代码内未见引用 |
| `--surface` | `#FFFFFF` | `#12121a` | 卡片/按钮/输入框底 |
| `--surface-2` | `#F8F7FF` | `#1c1c2e` | 次级底：`.seg` 槽、`.tag` 底、`.heat-cell` 底、`.mover` 底、`.set-ic` 底、`.members` 底 |
| `--surface-3` | `#F1F5F9` | `#16162a` | 轨道底：`.switch` 关、`.bar` 轨、`.stack-bar` 轨、`.plan-ticks i`、`.donut` 底环 |
| `--line` | `#E2E8F0` | `#2a2a3a` | 1px 分隔线 / 细描边 |
| `--line-2` | `#1E293B` | `#2a2a3a`（与 `--line` 同值） | 强描边（`.btn` 边框、`.card--pop`、`.sheet` border-left、`.switch` 边框、`.m-row` 无）、硬阴影色 |
| `--line-3` | `#CBD5E1` | `#3b3b52` | `.sheet-cell:hover` 边框（`var(--line-3, var(--ink-3))`） |
| `--ink` | `#1E293B` | `#e0e0e0` | 主文字；`.toast` 反色底 |
| `--ink-2` | `#64748B` | `#8f93ad` | 次文字 / 未选中按钮字色 |
| `--ink-3` | `#94A3B8` | `#6b7280` | 三级文字 / 标签小字 / placeholder / 边框 hover |
| `--accent` | `#8B5CF6` | `#00ff88` | 主色：主按钮底、选中态、`--bar-fill`、`.key--ok`、`.link-btn` |
| `--accent-ink` | `#FFFFFF` | `#04220f` | 主色上的字色 |
| `--cyan` | `#22D3EE` | `#00d4ff` | `.key--fn`（cyber）；candy 无引用 |
| `--pink` | `#F472B6` | `#ff00ff` | `.btn--pink`、`.nav-dot` 底、`.repay-col i` 底、`.report-banner` 渐变末端 |
| `--amber` | `#FBBF24` | `#ffb020` | `.chip.is-on` 底、`.alert-strip` 底、`.mh-plan-ic` 底、`heat-cell` 图标 orb tone |
| `--mint` | `#34D399` | `#00ff88` | 装饰三角 `.deco-c`、`累计与跨度` orb tone |
| `--sky` | `#38BDF8` | `#00d4ff` | `支付方式` 卡 orb tone |
| `--danger` | `#EF4444` | `#ff3366` | 逾期/删除/退款/`.btn--danger`/`.todo-mark.is-late` |
| `--warn` | `#F59E0B` | `#ffb020` | `.urgency--soon`、`.tag--warn`、`.todo-mark.is-soon`、`.dup-flag` |
| `--ok` | `#10B981` | `#00ff88` | `.pos`、`.sync-dot i`、`.todo-mark.is-done` |
| `--on-color` | `#1E293B` | `#05050c` | 彩底上的字色（`.chip.is-on`、`.alert-strip`、`.mh-plan-ic`） |
| `--chart-1`…`--chart-8` | `#8B5CF6` `#F472B6` `#FBBF24` `#34D399` `#38BDF8` `#A78BFA` `#FB7185` `#22D3EE` | `#00ff88` `#ff00ff` `#00d4ff` `#ffb020` `#8b5cff` `#00a3ff` `#ff3366` `#7dffd0` | 图表/分类色 8 槽（`var(--chart-N)`，N 由业务按索引取） |
| `--nav-bg` | `rgba(255, 253, 245, 0.9)` | `rgba(8, 8, 14, 0.92)` | `.topbar` 背景（配合 `backdrop-filter: blur(14px)`） |
| `--scrim` | `rgba(30, 41, 59, 0.35)` | `rgba(2, 2, 8, 0.78)` | `.scrim` / `.picker-mask` 遮罩 |
| `--glow` | `none` | `0 0 10px rgba(0, 255, 136, 0.55)` | 代码内未见引用 |

### A.3 字体令牌

| CSS 变量 | candy（theme.css 原值） | cyber（theme.css 原值） | 实际生效值（base.css 第 66–78 行覆写） |
|---|---|---|---|
| `--font-display` | `'Outfit', 'Noto Sans SC', system-ui, sans-serif` | `'Orbitron', 'Share Tech Mono', 'Noto Sans SC', monospace` | candy：`'Outfit Variable','Outfit','MiSans VF','Noto Sans SC',system-ui,sans-serif`；cyber：`'Orbitron','JetBrains Mono Variable','MiSans VF','Noto Sans SC',monospace` |
| `--font-body` | `'Plus Jakarta Sans', 'Noto Sans SC', system-ui, sans-serif` | `'JetBrains Mono', 'Noto Sans SC', ui-monospace, monospace` | candy：`'Plus Jakarta Sans Variable','Plus Jakarta Sans','MiSans VF','Noto Sans SC',system-ui,sans-serif`；cyber：`'JetBrains Mono Variable','MiSans VF','Noto Sans SC',ui-monospace,monospace` |
| `--font-mono` | `'Plus Jakarta Sans', ui-monospace, monospace`（**不是等宽字体**，与 Jakarta 同族） | `'Share Tech Mono', 'JetBrains Mono', ui-monospace, monospace` | candy：`'JetBrains Mono Variable','Plus Jakarta Sans Variable','MiSans VF',ui-monospace,monospace`；cyber：`'JetBrains Mono Variable','Share Tech Mono','MiSans VF',ui-monospace,monospace` |

字体文件由 `main.ts` 从 npm 本地引入：`@fontsource-variable/jetbrains-mono`、`@fontsource-variable/outfit`、`@fontsource-variable/plus-jakarta-sans`、`@fontsource/orbitron/700.css`、`@fontsource/orbitron/800.css`、`misans/lib/Normal/MiSansVF.min.css`。

### A.4 阴影 / 发光 / 遮罩

| CSS 变量 | candy | cyber | 用途 |
|---|---|---|---|
| `--shadow-card` | `6px 6px 0 #E9EEF6` | `0 0 0 rgba(0, 0, 0, 0)` | `.card` 默认硬阴影；`.more-menu-pop` 也用它 |
| `--shadow-card-pop` | `8px 8px 0 #1E293B` | `0 0 0 rgba(0, 0, 0, 0)` | `.card--pop`（概况主卡、年度全貌卡） |
| `--shadow-btn` | `3px 3px 0 #1E293B` | `none` | `.btn` 常态 |
| `--shadow-btn-hover` | `5px 5px 0 #1E293B` | `0 0 12px rgba(0, 255, 136, 0.45)` | `.btn:hover`（cyber 因 `transform:none` 只见辉光） |
| `--shadow-btn-active` | `1px 1px 0 #1E293B` | `none` | `.btn:active` |
| `--shadow-soft` | `0 10px 24px -18px rgba(30, 41, 59, 0.6)` | `0 0 20px -10px rgba(0, 212, 255, 0.5)` | 代码内未见引用 |

其它硬编码阴影（不在变量里，重建时必须逐条照抄）：
- `.orb`（candy）`box-shadow: 2px 2px 0 var(--line-2)`；cyber `0 0 10px -2px currentColor`。
- `.chip.is-on` `box-shadow: 2px 2px 0 var(--line-2)`；`.nav-item.is-on` `3px 3px 0 var(--line-2)`；`.heat-cell.is-now` / `.cal-day.is-today` `2px 2px 0 var(--line-2)`；`.picker-cell.is-on` / `.pay-item.is-on` `2px 2px 0 var(--line-2)`；`.theme-card.is-on` `3px 3px 0 var(--line-2)`；`.alert-strip` `3px 3px 0 var(--line-2)`；`.report-banner` `5px 5px 0 var(--line-2)`；`.annual-hero` `8px 8px 0 var(--line-2)`（移动端 5px）。
- `.mobile-hero` `4px 4px 0 var(--line-2)`（cyber：`0 0 30px -16px rgba(0,255,136,.6)`）。
- `.m-row` / `.sheet-cell` / `.pay-item` / `.year-cell` / `.todo-row` **无阴影**。
- `.toast` `4px 4px 0 rgba(0,0,0,.18)`；cyber `0 0 22px rgba(0,255,136,.55)`。
- `.sheet`（cyber）`-20px 0 60px -30px rgba(0,255,136,.5)`；`.modal` `0 30px 70px -30px rgba(10,10,20,.6)`；`.modal`（cyber）`0 0 60px -20px rgba(0,255,136,.45)`；`.picker`（cyber）`0 0 50px -20px rgba(0,255,136,.5)`。

### A.5 cyber 专属切角（clip-path）与描边减薄

| 选择器 | 值 |
|---|---|
| `.app[data-theme="cyber"] .card, .modal, .sheet`（theme.css:148-152） | `clip-path: polygon(0 14px, 14px 0, 100% 0, 100% calc(100% - 14px), calc(100% - 14px) 100%, 0 100%)` |
| `.app[data-theme="cyber"] .btn` | `clip-path: polygon(0 7px, 7px 0, 100% 0, 100% calc(100% - 7px), calc(100% - 7px) 100%, 0 100%)` |
| `.app[data-theme="cyber"] .orb` | `clip-path: polygon(0 6px, 6px 0, 100% 0, 100% calc(100% - 6px), calc(100% - 6px) 100%, 0 100%)` |
| `.app[data-theme="cyber"] .logo-ph` | `clip-path: polygon(0 8px, 8px 0, 100% 0, 100% calc(100% - 8px), calc(100% - 8px) 100%, 0 100%)` |
| `.tp-cyber::before`（主题预览缩略图） | `clip-path: polygon(0 8px, 8px 0, 100% 0, 100% calc(100% - 8px), calc(100% - 8px) 100%, 0 100%)` |
| 全局描边减薄 | `.ic { stroke-width: 2.4 }` → cyber `.ic { stroke-width: 1.6 }`（theme.css:29、147） |

### A.6 背景装饰层（两套主题几何不同）

| 层 | candy | cyber |
|---|---|---|
| `.app::before` | `position:fixed; inset:0; z-index:0; pointer-events:none`；点阵 `radial-gradient(rgba(139,92,246,.13) 1.4px, transparent 1.5px)`，`background-size:24px 24px`，`opacity:.75`，`mask-image: radial-gradient(circle at 70% 10%, #000 10%, transparent 80%)` | 电路网格：两条 `linear-gradient(rgba(0,255,136,.05) 1px, transparent 1px)`（0°/90°）+ 两个 `radial-gradient`（78% 4% 青 / 8% 82% 品红）；`background-size:52px 52px, 52px 52px, 100% 100%, 100% 100%`；`mask-image: linear-gradient(#000 40%, rgba(0,0,0,.45))` |
| `.app::after` | 无 | 扫描线：`position:fixed; inset:0; z-index:999; pointer-events:none`，`repeating-linear-gradient(180deg, rgba(255,255,255,.028) 0 1px, transparent 1px 4px)` |
| 几何贴纸 `.deco-a`~`.deco-d` | 有：`a` 260×260 圆（`--amber`，opacity .28，top -90px right 8%）；`b` 150×150 异形圆角 `42% 58% 52% 48% / 55% 44% 56% 45%`（`--pink`，.22，top 32% right -60px）；`c` 三角 `border-left/right 60px transparent; border-bottom 100px var(--mint)`（.2，bottom 6% left -20px，`rotate(18deg)`）；`d` 120×14 胶囊（`--accent`，.18，`rotate(-24deg)`，bottom 16% right 12%）；全部 `position:fixed; z-index:0; pointer-events:none` | `.deco { display:none }` |
| 关闭开关 | `.app[data-decor="off"] .deco, ::before { display:none }`（本工程固定 `data-decor="on"`） | 同 |

---

## B. 基础组件规格

每个组件给出：DOM 结构 → 尺寸 → 颜色 → 阴影/切角 → 状态 → candy/cyber 差异。
「Vue 组件」列标明模板类名，组件内部**不判断主题**（`ui/index.ts` 注释：外观全部由 `.app[data-theme=...]` 接管）。

### B.0 全局元素级基线（theme.css:12–29，重建时必须存在，否则组件观感全变）

- `* { box-sizing: border-box }`
- `html, body { margin:0; padding:0; min-height:100% }`；`body { background:#FFFDF5; -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility }`
- `button { font:inherit; color:inherit; border:0; background:none; cursor:pointer; padding:0; -webkit-tap-highlight-color:transparent }`
- `input, textarea, select { font:inherit; color:inherit }`；`input::placeholder, textarea::placeholder { color:var(--ink-3) }`
- `a { color:inherit }`；`.app a { text-decoration:none }`（base.css:88，含 `:hover`）
- `:focus-visible { outline:2px solid var(--accent); outline-offset:2px }`
- `.ic { stroke-width:2.4; flex:0 0 auto }`；cyber `.ic { stroke-width:1.6 }`
- `.app { min-height:100vh; min-height:100dvh; background-color:var(--bg); color:var(--ink); font-family:var(--font-body); position:relative; isolation:isolate; transition: background-color .35s ease, color .35s ease }`

### B.1 `.shell` 外壳栅格

- DOM（App.vue:169-207）：`div.shell > aside.sidebar + div.main`
- 桌面：`display:grid; grid-template-columns:244px minmax(0,1fr); min-height:100vh; min-height:100dvh; position:relative; z-index:1`
- 移动（app.css:722）：`grid-template-columns: minmax(0,1fr)`（侧边栏与主区上下堆叠）

### B.2 侧边栏 `.sidebar` / 品牌 `.brand` / 导航 `.nav-item`

**DOM**
```
aside.sidebar
├─ a.brand (RouterLink → /ledger)
│  ├─ BrandMark(size=46 → 移动端由 CSS 缩到 32)
│  └─ div.brand-txt
│     ├─ div.brand-name  "SuenMoney"
│     └─ div.brand-sub   "FAMILY LEDGER · 单账本"
├─ nav.nav
│  ├─ div.nav-cap "账目"
│  └─ a.nav-item ×4  [svg 16px + span 文案]   (is-on 当前项)
└─ div.side-foot
   ├─ button.members
   │  ├─ span.members-txt > b + 文本 "只记支出 · 整数分"
   │  └─ span.sync-dot > i + "SYNC"
   └─ div.build-stamp
```

**尺寸/颜色（桌面基线）**
- `.sidebar`：`position:sticky; top:0; height:100vh/100dvh; display:flex; flex-direction:column; gap:26px; padding:22px 16px 18px; border-right:1px solid var(--line); background:var(--bg-2)`。cyber：`background:linear-gradient(180deg,#0b0b14,#08080f)`
- `.brand`：`display:flex; align-items:center; gap:12px; padding:0 4px`
- `.logo-ph`（原型占位块，实际品牌位是 `<img class="brand-mark">`）：`46×46; border:2px dashed var(--ink-3); border-radius:14px; background:var(--surface-2); color:var(--ink-3); font-family:var(--font-mono); font-size:9px; letter-spacing:.1em; line-height:1.25; display:grid; place-items:center`
- `.brand-name`：`font-family:var(--font-display); font-weight:700; font-size:20px; letter-spacing:-.01em; line-height:1.1`（App.vue scoped 重复声明同值）
- `.brand-sub`：`margin-top:3px; font-family:var(--font-mono); font-size:9px; letter-spacing:.2em; text-transform:uppercase; color:var(--ink-3); white-space:nowrap`
- `.nav`：`display:flex; flex-direction:column; gap:5px`
- `.nav-cap`：`font-family:var(--font-mono); font-size:9.5px; letter-spacing:.2em; text-transform:uppercase; color:var(--ink-3); padding:0 12px; margin-bottom:5px`
- `.nav-item`：`display:flex; align-items:center; gap:10px; width:100%; padding:10px 12px; border:var(--border-w) solid transparent; border-radius:var(--r-md); font-size:13.5px; font-weight:600; color:var(--ink-2); text-align:left; transition: transform .18s cubic-bezier(.34,1.56,.64,1), background .16s, color .16s, border-color .16s`
  - `:hover { background:var(--surface); color:var(--ink); border-color:var(--line); transform:translateX(2px) }`
  - `.is-on { background:var(--surface); border-color:var(--line-2); color:var(--ink); box-shadow:3px 3px 0 var(--line-2) }`
- `.nav-dot`：`margin-left:auto; min-width:18px; height:18px; padding:0 5px; border-radius:999px; background:var(--pink); color:#fff; font-size:10px; font-weight:700; display:grid; place-items:center; font-family:var(--font-mono)`（本工程 `NAV` 数组无 badge，故不渲染）
- `.side-foot`：`margin-top:auto; display:flex; flex-direction:column; gap:10px`
- `.members`：`display:flex; align-items:center; gap:8px; padding:10px; border-radius:var(--r-md); border:1px solid var(--line); background:var(--surface)`
- `.members-txt`：`font-size:10.5px; line-height:1.5; color:var(--ink-2); font-family:var(--font-mono)`；`b { display:block; color:var(--ink); font-size:11.5px; font-weight:700 }`
- `.sync-dot`：`margin-left:auto; display:flex; align-items:center; gap:5px; font-family:var(--font-mono); font-size:9px; color:var(--ink-3); letter-spacing:.06em`；`i { width:6px; height:6px; border-radius:50%; background:var(--ok); box-shadow:0 0 0 3px rgba(52,211,153,.18) }`
- `.avatar`：27×27 圆，`font-size:11px; font-weight:700; color:#fff`（本工程侧栏未使用）
- `build-stamp`：`font-family:var(--font-mono); font-size:10px; letter-spacing:.06em; opacity:.55; text-align:center; padding-top:18px`（base.css:46-54）

**cyber 差异（逐条）**
1. `.sidebar` 背景改为渐变（见上），`border-right-color:var(--line)`。
2. `.logo-ph`：`border:1px dashed rgba(0,255,136,.5); border-radius:0; clip-path`（8px 切角）；`color:var(--accent); background:rgba(0,255,136,.06); text-shadow:0 0 8px rgba(0,255,136,.5)`。
3. `.brand-name`：`letter-spacing:.16em; text-transform:uppercase; color:var(--accent); text-shadow:0 0 14px rgba(0,255,136,.45); font-size:17px`。
4. `.nav-item`：`border-radius:0; font-family:var(--font-mono); font-size:12px; letter-spacing:.08em; text-transform:uppercase`。
5. `.nav-item.is-on`：`border-color:rgba(0,255,136,.65); background:rgba(0,255,136,.07); color:var(--accent); box-shadow:inset 0 0 18px rgba(0,255,136,.12); text-shadow:0 0 10px rgba(0,255,136,.5)`。
6. `.nav-dot`：`border-radius:0; background:var(--pink); color:#0a0a0f; box-shadow:0 0 10px rgba(255,0,255,.7)`。
7. `.members`：`border-radius:0; background:rgba(0,255,136,.03)`。
8. `.avatar`：`border-radius:2px`。
9. `.sync-dot i`：`background:var(--accent); box-shadow:0 0 8px var(--accent)`。

**移动端（≤860px）最终值**
- `.sidebar`（app.css:723-734 → views.css:860-869 → views.css:1114，后者覆盖 padding）：
  `position:sticky; top:0; z-index:60; height:auto; flex-direction:row; align-items:center; flex-wrap:wrap; gap:8px 10px; padding:8px 14px 6px; border-right:0; border-bottom:1px solid var(--line); overflow-x:auto; overflow-y:hidden; background:var(--bg); backdrop-filter:blur(10px)`
- `.sidebar .brand { flex:0 0 auto; padding-bottom:0 }`；`.sidebar .brand-sub { display:none }`
- `.logo-ph` 移动端 `width:32px; height:32px; font-size:6.8px; border-radius:10px`（views.css:1116 覆盖 app.css 的 36/36/7.5/10）
- `.brand-name` 移动端 `font-size:15px`（views.css:1117 覆盖 app.css 的 16px）
- `.nav`：`flex:1 0 100%; order:3; overflow-x:auto`（views.css:870）**但紧接着 views.css:1115 `.sidebar .nav { display:none }` → 移动端导航条整条不渲染**。
- `.nav-cap`、`.side-foot`：`display:none`（app.css:741）。
- `.nav-item` 移动形态（若被渲染时的声明）：`width:auto; padding:7px 11px; font-size:12px; border-radius:999px; border-color:transparent; white-space:nowrap; gap:6px`；`:hover{transform:none}`；`.is-on{box-shadow:none; border-color:var(--line-2); background:var(--surface)}`；`.nav-dot{margin-left:2px}`；移动端 views.css:936 追加 `.nav-dot{transform:scale(.9)}`。

### B.3 顶栏 `.topbar`

**DOM**（App.vue:210-230）
```
header.topbar (ledger 页加 .topbar--bare)
├─ PIconBtn.mobile-only (icon=ChevronLeft, label="返回流水"/"返回报表")   ← 仅 route ≠ ledger 且 ≤860 渲染
├─ div.topbar-txt
│  ├─ div.topbar-title   (PAGE_META.title)
│  └─ div.topbar-sub     (PAGE_META.sub)
└─ div.topbar-actions
   ├─ PIconBtn (Moon/Sun 切主题)
   └─ PBtn primary + Plus "记一笔"
```
**尺寸**：`position:sticky; top:0; z-index:30; display:flex; align-items:center; gap:14px; padding:13px 28px; border-bottom:1px solid var(--line); background:var(--nav-bg); backdrop-filter:blur(14px)`
- `.topbar-title`：`var(--font-display); 700; 19px; letter-spacing:-.01em; line-height:1.15; white-space:nowrap`
- `.topbar-sub`：`margin-top:2px; var(--font-mono); 9.5px; letter-spacing:.16em; uppercase; color:var(--ink-3); white-space:nowrap`
- `.topbar-actions`：`margin-left:auto; display:flex; align-items:center; gap:9px`
**cyber**：`.topbar-title { text-transform:uppercase; letter-spacing:.12em; font-size:15px; text-shadow:0 0 14px rgba(0,255,136,.35) }`
**移动端最终值**：`padding:8px 12px; gap:8px; align-items:center`（views.css:1118；覆盖 app.css 的 `10px 14px`、views.css:872 的 `10px 14px 6px`）；`.topbar-title{font-size:15px}`（views.css:1120，但标题实际被隐藏，见下）；`.topbar-sub{display:none}`。
**移动端隐藏（base.css:105-118，全部 `!important`）**：`.topbar-txt`、`.topbar-actions`、`.topbar--bare`（流水页整条顶栏不占位）、`.pull-hint`。
→ **移动端顶栏 = 除流水页外，仅一个返回箭头按钮（38×38）**；流水页无顶栏。

### B.4 内容区 `.content`

`width:100%; max-width:1280px; margin:0 auto; padding:22px 28px 72px; display:flex; flex-direction:column; gap:16px; position:relative`
移动端最终值：`padding:6px 12px 64px`（views.css:1121，最后声明），`gap:12px`（app.css:757）。

### B.5 按钮 `.btn`（Vue：`PBtn`）

**DOM**（PBtn.vue）：`button.btn[.btn--{variant}][.btn--{size}] > (svg 14px | 12px if sm) + slot`
**尺寸**：`display:inline-flex; align-items:center; justify-content:center; gap:7px; min-height:38px; padding:8px 16px; border:var(--border-w) solid var(--line-2); border-radius:var(--r-pill); font-size:12.5px; font-weight:700; white-space:nowrap; transition: transform .18s cubic-bezier(.34,1.56,.64,1), box-shadow .18s, background .16s, color .16s`
**颜色**：`background:var(--surface); color:var(--ink); box-shadow:var(--shadow-btn)`
**状态**
- `:hover { transform:translate(-2px,-2px); box-shadow:var(--shadow-btn-hover) }`
- `:active { transform:translate(2px,2px); box-shadow:var(--shadow-btn-active) }`
- `[disabled] { opacity:.45; cursor:not-allowed; transform:none !important; box-shadow:var(--shadow-btn) !important }`
**变体**
| 类 | candy | cyber |
|---|---|---|
| `.btn--primary` | `background:var(--accent); color:var(--accent-ink)` | `background:var(--accent); color:#04170d; box-shadow:0 0 16px rgba(0,255,136,.35)`；`:hover` `#7dffc0` + `0 0 24px rgba(0,255,136,.75)` |
| `.btn--pink` | `background:var(--pink); color:#fff` | `border-color:var(--pink); color:var(--pink)`；`:hover` `background:var(--pink); color:#150015; box-shadow:0 0 18px rgba(255,0,255,.6)` |
| `.btn--ghost` | `border-color:transparent; box-shadow:none; background:transparent; color:var(--ink-2)`；`:hover { background:var(--surface-2); color:var(--ink); transform:none; box-shadow:none }` | `border-color:var(--line); color:var(--ink-2)`；`:hover { background:rgba(0,255,136,.08); color:var(--accent); border-color:var(--accent) }` |
| `.btn--danger` | `color:var(--danger)`；`:hover { background:var(--danger); color:#fff }` | `border-color:var(--danger); color:var(--danger)`；`:hover { background:var(--danger); color:#fff; box-shadow:0 0 18px rgba(255,51,102,.55) }` |
| `.btn--sm` | `min-height:30px; padding:4px 11px; font-size:11.5px` | 同（继承 cyber 边框/字体） |
| `.btn--icon` | `padding:0; width:38px; min-height:38px` | 同 |
**cyber 基础差异（逐条）**：`border-radius:0`；`border-width:1px`；`border-color:rgba(0,255,136,.55)`；`background:transparent`；`color:var(--accent)`；`font-family:var(--font-mono)`；`font-size:11px`；`letter-spacing:.14em`；`text-transform:uppercase`；`box-shadow:none`；`clip-path` 7px 切角；`:hover { background:var(--accent); color:#04170d; box-shadow:0 0 16px rgba(0,255,136,.55); transform:none }`。

### B.6 圆图标按钮 `.icon-btn`（Vue：`PIconBtn`）

**DOM**：`button.icon-btn[aria-label][title] > svg(17px, stroke 2.2)`
**尺寸**：`width:38px; height:38px; display:grid; place-items:center; border:var(--border-w) solid var(--line); border-radius:var(--r-pill)`
**颜色**：`background:var(--surface); color:var(--ink-2)`
**状态**：`transition:all .16s`；`:hover { color:var(--ink); border-color:var(--line-2) }`
**cyber**：`border-radius:0; border-width:1px; background:transparent`；`:hover { color:var(--accent); border-color:var(--accent); box-shadow:0 0 12px rgba(0,255,136,.4) }`
**移动端**：无独立覆盖（保持 38×38）。

### B.7 卡片 `.card`（Vue：`PCard`）

**DOM**：`div.card[.card--pop][.card--flat][.card--tint] > slot`
**尺寸**：`position:relative; border:var(--border-w) solid var(--line); border-radius:var(--r-card); padding:var(--density-pad)`（=18px）
**颜色**：`background:var(--surface)`；`box-shadow:var(--shadow-card)`
**变体**：`.card--pop { border-color:var(--line-2); box-shadow:var(--shadow-card-pop) }`；`.card--flat { box-shadow:none }`；`.card--tint { background:var(--surface-2) }`
**cyber**：`border-color:var(--line); box-shadow:0 0 0 1px rgba(0,212,255,.04); transition:border-color .2s, box-shadow .2s`；`:hover { border-color:rgba(0,255,136,.45); box-shadow:0 0 18px -6px rgba(0,255,136,.35) }`；外加 theme.css 的 14px 切角。
**移动端（app.css:759-760，无后续覆盖）**：`.card { padding:14px; border-radius:16px; box-shadow:3px 3px 0 #E9EEF6 }`（candy 硬编码）；`.app[data-theme="cyber"] .card { border-radius:0; box-shadow:none }`。

### B.8 卡头 `.card-h` / `.card-t` / `.card-cap`

`.card-h { display:flex; align-items:center; gap:10px; margin-bottom:13px }`；`.card-h--tight { margin-bottom:6px }`
`.card-t { font-family:var(--font-display); font-weight:700; font-size:15px; letter-spacing:-.01em }`；cyber：`text-transform:uppercase; letter-spacing:.1em; font-size:12.5px`
`.card-cap { font-family:var(--font-mono); font-size:9.5px; letter-spacing:.16em; text-transform:uppercase; color:var(--ink-3) }`
`.card-h .spacer / .card-h .card-cap { margin-left:auto }`

### B.9 圆形图标 `.orb`（Vue：`POrb`）

**DOM**：`span.orb[style="background:{tone};color:{ink}"] > svg(16px, stroke 2.2)`（内联 style 覆盖 CSS 底色）
**尺寸/形状**：`width:34px; height:34px; flex:0 0 auto; border-radius:50%; display:grid; place-items:center; border:2px solid var(--line-2); box-shadow:2px 2px 0 var(--line-2)`；默认 `background:var(--accent); color:#fff`
**cyber**：`border-radius:1px; border:1px solid currentColor; background:transparent; box-shadow:0 0 10px -2px currentColor; color:var(--accent); clip-path` 6px 切角
**实际用法中的 tone/ink**：`CalendarDays` tone `var(--amber)` ink `#1E293B`；`Layers` tone `var(--mint)` ink `#1E293B`；`Tag` tone `var(--accent)` ink `var(--accent-ink)`；`CreditCard` tone `var(--sky)` ink `#1E293B`；`CalendarDays`(年度) tone `var(--accent)` ink `var(--accent-ink)`。

### B.10 分段控件 `.seg`（Vue：`PSeg`）

**DOM**：`div.seg[role=tablist] > button.seg-btn[role=tab][aria-selected][.is-on] × N`
**尺寸**：`display:inline-flex; align-items:center; gap:4px; padding:4px; border:var(--border-w) solid var(--line); border-radius:var(--r-pill)`
**颜色**：`background:var(--surface-2)`
`.seg-btn`：`padding:6px 13px; border-radius:var(--r-pill); border:2px solid transparent; font-size:12px; font-weight:700; color:var(--ink-2); white-space:nowrap; transition:all .16s`；`:hover { color:var(--ink) }`；`.is-on { background:var(--accent); color:var(--accent-ink); border-color:var(--line-2) }`
**cyber**：`.seg { border-radius:0; border-width:1px; background:transparent; gap:0 }`；`.seg-btn { border-radius:0; border:0; border-right:1px solid var(--line); font-family:var(--font-mono); font-size:10.5px; letter-spacing:.1em; text-transform:uppercase }`；`.seg-btn:last-child { border-right:0 }`；`.seg-btn.is-on { background:rgba(0,255,136,.1); color:var(--accent); border-color:transparent; box-shadow:inset 0 0 14px rgba(0,255,136,.2) }`

### B.11 筛选药丸 `.chip`（Vue：`PChip`）

**DOM**：`button.chip[aria-pressed][.is-on] > (i.chip-dot[style=background])? + slot`
**尺寸**：`display:inline-flex; align-items:center; gap:6px; padding:5px 11px; border:2px solid var(--line); border-radius:var(--r-pill); font-size:11.5px; font-weight:600`
**颜色**：`background:var(--surface); color:var(--ink-2)`
**状态**：`:hover { border-color:var(--ink-3); color:var(--ink) }`；`.is-on { background:var(--amber); border-color:var(--line-2); color:var(--on-color); box-shadow:2px 2px 0 var(--line-2) }`；`transition:all .16s`
`.chip-dot { width:7px; height:7px; border-radius:50%; background:currentColor; opacity:.8 }`；容器 `.chips { display:flex; flex-wrap:wrap; gap:7px }`
**cyber**：`border-radius:0; border-width:1px; font-family:var(--font-mono); font-size:10px; letter-spacing:.06em; text-transform:uppercase; background:transparent`；`.is-on { background:rgba(0,255,136,.1); border-color:var(--accent); color:var(--accent); box-shadow:0 0 12px rgba(0,255,136,.3) }`

### B.12 表单 `.field` / `.input`（Vue：`PField` / `PInput`）

**DOM**：`label.field > (span.field-l)? + (input.input)`；PField 渲染 `label.field[for]`
`.field { display:flex; flex-direction:column; gap:6px }`
`.field-l { font-family:var(--font-mono); font-size:9.5px; letter-spacing:.14em; text-transform:uppercase; color:var(--ink-3) }`
`.input { width:100%; min-height:40px; padding:9px 12px; border:var(--border-w) solid var(--line); border-radius:var(--r-md); background:var(--surface); color:var(--ink); font-size:13px; transition:border-color .18s, box-shadow .18s }`
`:focus { outline:none; border-color:var(--accent); box-shadow:3px 3px 0 var(--accent) }`
`.input--search { padding-left:34px }`；`.search-wrap { position:relative; flex:1 1 180px; min-width:140px }`；`.search-wrap .ic { position:absolute; left:11px; top:50%; transform:translateY(-50%); color:var(--ink-3) }`
**cyber**：`.input { border-width:1px; background:#12121a; font-family:var(--font-mono); font-size:12px }`；`:focus { box-shadow:0 0 14px rgba(0,255,136,.4); border-color:var(--accent) }`
**移动端**：`.search-wrap` 在 `.lt-search` 内被改 `flex:1 1 auto; min-width:0`（views.css:941、998），`.lt-search` 移动端 `flex:1 1 100%`（views.css:997）。

### B.13 开关 `.switch`（Vue：`PSwitch`）

**DOM**：`button.switch[role=switch][aria-checked][.is-on]`（无子节点，圆点靠 `::after`）
**尺寸**：`position:relative; width:42px; height:24px; border-radius:999px; border:2px solid var(--line-2); flex:0 0 auto`
**颜色**：`background:var(--surface-3)`；`transition:background .2s`
`::after { position:absolute; top:2px; left:2px; width:16px; height:16px; border-radius:50%; background:var(--line-2); transition:transform .2s cubic-bezier(.34,1.56,.64,1) }`
`.is-on { background:var(--accent) }`；`.is-on::after { transform:translateX(18px); background:#fff }`
**cyber**：`.switch { border-radius:0; border-width:1px; background:#0a0a0f }`；`::after { border-radius:0; background:var(--ink-2) }`；`.is-on { background:rgba(0,255,136,.15); border-color:var(--accent); box-shadow:0 0 10px rgba(0,255,136,.4) }`；`.is-on::after { background:var(--accent); box-shadow:0 0 8px var(--accent) }`

### B.14 指标 `.stat`（Vue：`PStat`）

**DOM**：`div.stat > span.stat-v + span.stat-l + (span.stat-sub?)`
`.stat { display:flex; flex-direction:column; gap:3px; min-width:0 }`
`.stat-v { font-family:var(--font-display); font-weight:700; font-size:21px; line-height:1.1; letter-spacing:-.02em; font-variant-numeric:tabular-nums; white-space:nowrap }`
`.stat-l { font-size:10.5px; color:var(--ink-3); letter-spacing:.04em }`
`.stat-sub { font-size:10px; color:var(--ink-3); font-family:var(--font-mono) }`
**cyber**：`.stat-v { letter-spacing:.02em; font-size:18px; text-shadow:0 0 10px rgba(0,212,255,.32) }`；`.stat-l { font-family:var(--font-mono); text-transform:uppercase; font-size:9.5px; letter-spacing:.12em }`
工具类：`.mono { font-family:var(--font-mono); font-variant-numeric:tabular-nums }`；`.num { …; text-align:right; white-space:nowrap }`；`.pos { color:var(--ok) }`；`.neg { color:var(--danger) }`；`.muted { color:var(--ink-2) }`；`.tiny { font-size:10.5px }`；`.hint { font-size:11px; color:var(--ink-3); line-height:1.65 }`

### B.15 药丸标签 `.tag`（Vue：`PTag`）

**DOM**：`span.tag[.tag--dash|accent|warn|danger] > slot`
`display:inline-flex; align-items:center; gap:4px; padding:2px 8px; border-radius:999px; border:1px solid var(--line); background:var(--surface-2); font-size:10px; font-weight:600; color:var(--ink-2); font-family:var(--font-mono); white-space:nowrap`
`.tag--dash { border-style:dashed }`；`.tag--accent { border-color:var(--accent); color:var(--accent); background:transparent }`；`.tag--warn`/`.tag--danger` 同理。
**cyber**：`border-radius:0; text-transform:uppercase; letter-spacing:.06em`

### B.16 表格 `.tbl`（仅桌面渲染，但样式需记录）

`width:100%; border-collapse:separate; border-spacing:0; font-size:12.5px`
`th { text-align:left; var(--font-mono); font-size:9.5px; font-weight:500; letter-spacing:.12em; uppercase; color:var(--ink-3); padding:6px 10px 9px; border-bottom:1px solid var(--line); white-space:nowrap }`
`td { padding:var(--density-row) 10px; border-bottom:1px solid var(--line); vertical-align:middle }`
`tbody tr { cursor:pointer; transition:background .14s }`；`tbody tr:hover { background:var(--surface-2) }`；`tr:last-child td { border-bottom:0 }`；`.th-r/.td-r { text-align:right }`
`.cat-cell { display:flex; align-items:center; gap:9px; min-width:0 }`；`.cat-txt { min-width:0 }`；`.cat-name { font-weight:600; font-size:12.5px; nowrap; ellipsis }`；`.cat-sub { font-size:10px; color:var(--ink-3) }`

### B.17 列表行 `.row`

`.row { display:flex; align-items:center; gap:12px; padding:11px 2px; border-bottom:1px solid var(--line) }`；`:last-child { border-bottom:0 }`
`.row-main { min-width:0; flex:1 1 auto }`；`.row-t { font-size:13px; font-weight:600 }`；`.row-s { font-size:10.5px; color:var(--ink-3); margin-top:2px }`；`.row-end { margin-left:auto; text-align:right; flex:0 0 auto }`；`.row-amt { font-family:var(--font-mono); font-weight:600; font-size:13px; font-variant-numeric:tabular-nums }`

### B.18 遮罩 / 抽屉 / 弹窗 `.scrim` `.sheet` `PSheet` / `.modal`

**DOM（PSheet）**
```
div.scrim (@click=close)
└─ div.sheet[role=dialog][aria-modal][aria-label]
   ├─ div.sheet-head
   │  ├─ span.sheet-title
   │  ├─ span[style="margin-left:auto"]
   │  ├─ slot name=head-actions
   │  └─ button.icon-btn "✕" (@click=close)
   ├─ div.sheet-body  > slot
   └─ div.sheet-foot (仅当有 foot slot) > slot name=foot
```
（ExpenseSheet 不用 PSheet，自写 `div.scrim` 与 `div.sheet` 为**兄弟节点**，见 C.7。）

**尺寸**
- `.scrim { position:fixed; inset:0; z-index:80; background:var(--scrim); backdrop-filter:blur(2px); animation:fadeIn .18s ease }`
- `.sheet { position:fixed; top:0; right:0; bottom:0; z-index:81; width:min(500px,100vw); display:flex; flex-direction:column; background:var(--bg); border-left:2px solid var(--line-2); animation:slideIn .26s cubic-bezier(.22,1,.36,1) }`
- `.sheet-head { display:flex; align-items:center; gap:10px; padding:14px 16px; border-bottom:1px solid var(--line) }`
- `.sheet-title { font-family:var(--font-display); font-weight:700; font-size:16px }`
- `.sheet-body { flex:1 1 auto; overflow-y:auto; padding:14px 16px 18px; display:flex; flex-direction:column; gap:12px }`
- `.sheet-foot { padding:12px 16px; border-top:1px solid var(--line); display:flex; gap:8px }`
- `.modal { position:fixed; left:50%; top:50%; transform:translate(-50%,-50%); z-index:91; width:min(600px, calc(100vw - 28px)); max-height:88dvh; flex column; background:var(--bg); border:2px solid var(--line-2); border-radius:var(--r-card); box-shadow:0 30px 70px -30px rgba(10,10,20,.6); overflow:hidden; animation:popIn .22s cubic-bezier(.34,1.56,.64,1) }`；`.modal--wide { width:min(880px, calc(100vw - 28px)) }`
- `.modal-head { display:flex; align-items:center; gap:10px; padding:14px 18px; border-bottom:1px solid var(--line) }`；`.modal-title { var(--font-display); 700; 16px }`；`.modal-body { padding:16px 18px; overflow-y:auto; flex column; gap:14px }`；`.modal-foot { padding:12px 18px; border-top:1px solid var(--line); display:flex; gap:8px; justify-content:flex-end }`
- 动画：`fadeIn { from{opacity:0} to{opacity:1} }`；`slideIn { from{transform:translateX(28px); opacity:.4} to{translateX(0);opacity:1} }`；`popIn { from{transform:translate(-50%,-46%) scale(.97);opacity:0} to{translate(-50%,-50%) scale(1);opacity:1} }`

**cyber**：`.sheet { border-left-color:rgba(0,255,136,.5); box-shadow:-20px 0 60px -30px rgba(0,255,136,.5) }`；`.sheet-title { uppercase; letter-spacing:.14em; font-size:13px; color:var(--accent); text-shadow:0 0 12px rgba(0,255,136,.5) }`；`.modal { border-color:rgba(0,255,136,.5); box-shadow:0 0 60px -20px rgba(0,255,136,.45) }`；`.modal-title { uppercase; letter-spacing:.12em; 13px; color:var(--accent) }`；两者都有 14px 切角。

**移动端（app.css:762-775）**
```
.sheet { top:auto; left:0; right:0; bottom:0; width:100%; height:93dvh;
         border-left:0; border-top:2px solid var(--line-2); border-radius:22px 22px 0 0 }
.app[data-theme="cyber"] .sheet { border-radius:0; border-top:1px solid var(--accent) }
.modal { width:calc(100vw - 20px); max-height:92dvh }
.modal--wide { width:calc(100vw - 20px) }
```
views.css 追加：`.sheet-head { padding:12px 14px }`（921）；`.sheet-title { font-size:15px }`（922）；`.sheet-body { padding:12px; gap:10px }`（904）；`.sheet-body { max-height:calc(93dvh - 124px); -webkit-overflow-scrolling:touch }`（920）；`.sheet-foot { padding-bottom:calc(12px + env(safe-area-inset-bottom)) }`（906）；`.modal-foot { flex-wrap:wrap }`（933）；`.modal-foot .btn { flex:1 1 auto; justify-content:center }`（934）。

### B.19 轻提示 `.toast`（Vue：`PToast`）

**DOM**：`div.toast[role=status] > svg(14px) + 文案`
`position:fixed; left:50%; bottom:26px; transform:translateX(-50%); z-index:120; display:flex; align-items:center; gap:8px; padding:10px 16px; border-radius:var(--r-pill); border:2px solid var(--line-2); background:var(--ink); color:var(--bg); font-size:12px; font-weight:600; box-shadow:4px 4px 0 rgba(0,0,0,.18); max-width:calc(100vw - 32px); animation:toastIn .24s cubic-bezier(.34,1.56,.64,1)`
`toastIn { from{transform:translate(-50%,14px);opacity:0} to{translate(-50%,0);opacity:1} }`
**cyber**：`border-radius:0; background:#04170d; color:var(--accent); border-color:var(--accent); box-shadow:0 0 22px rgba(0,255,136,.55); font-family:var(--font-mono)`
**移动端**：`bottom:18px; width:max-content`（app.css:776）

### B.20 空态 `.empty`（Vue：`PEmpty`）

**DOM**：`div.empty > (svg 18px)? + slot`
`padding:34px 10px; text-align:center; color:var(--ink-3); font-size:12px; display:flex; flex-direction:column; align-items:center; gap:8px`
无 cyber 变体（只换色变量）。

### B.21 进度条 `.bar`（Vue：`PBar`）

**DOM**：`div.bar > span.bar-fill[style="width:{pct}%; background:{tone}"]`
`.bar { position:relative; height:9px; border-radius:999px; background:var(--surface-3); overflow:hidden; border:1px solid var(--line) }`
`.bar-fill { position:absolute; inset:0 auto 0 0; border-radius:inherit; background:var(--accent); transition:width .5s cubic-bezier(.22,1,.36,1) }`
**cyber**：`.bar { border-radius:0; background:#0a0a0f }`；`.bar-fill { border-radius:0; box-shadow:0 0 12px rgba(0,255,136,.6) }`
调用处内联覆写：年格/全部格内 `<div class="bar" style="height:5px; margin-top:2px">`（LedgerView:650、677）。

### B.22 环形图 `.donut`（Vue：`PDonut`）

**DOM**
```
div.donut[style="width:{size}px;height:{size}px"]
├─ svg[width=100% height=100% viewBox="0 0 {size} {size}"]
│  ├─ circle 底环 stroke=var(--surface-3) stroke-width=16
│  └─ circle × N  stroke={color} stroke-width=16 stroke-dasharray=… stroke-dashoffset=… transform="rotate(-90 {size/2} {size/2})"
└─ div.donut-center > span.donut-c-l + span.donut-c-v
```
几何（PDonut.vue:原句）：`r = size/2 - 12`；`circumference = 2πr`；每段 `dash = "{max(0,len-2.5)} {circumference - max(0,len-2.5)}"`，`offset = -累计`（段间固定 2.5 空隙）。默认 `size=176`。
`.donut { position:relative; width:176px; height:176px; flex:0 0 auto }`；`.donut-center { position:absolute; inset:0; flex column; center; gap:2px; text-align:center; pointer-events:none }`；`.donut-c-l { font-size:9.5px; letter-spacing:.14em; color:var(--ink-3); font-family:var(--font-mono); text-transform:uppercase }`；`.donut-c-v { font-family:var(--font-display); font-weight:800; font-size:21px; letter-spacing:-.02em }`
移动端 CSS 声明：`.donut { width:150px; height:150px }`（views.css:783）、`.compose-visual .donut { 148px }`（886）、`.compose-visual .donut { 136px }`（1146）。**但组件内联 `style` 的 `176px` 优先级更高 → 这些覆盖实际不生效**（见 E.4）。

### B.23 布局工具类

`.g2 { grid-template-columns:repeat(2,minmax(0,1fr)); gap:16px }`；`.g3`（3 列）、`.g4`（4 列）同 gap 16
`.g-side { grid-template-columns:minmax(0,1.55fr) minmax(0,1fr); gap:16px; align-items:start }`
`.stack { display:flex; flex-direction:column; gap:16px }`；`.stack--sm { gap:10px }`
`.split { display:flex; align-items:center; gap:10px; flex-wrap:wrap }`
`.toolbar { display:flex; align-items:center; gap:10px; flex-wrap:wrap }`；`.toolbar .spacer { margin-left:auto }`
响应式：≤1080 `.g4→2 列`、`.g-side→1 列`；≤860 `.g2,.g3,.g4 → minmax(0,1fr)`（**移动端 g2 内的两列会变成上下堆叠**）。

注意：**`.stack`（页面根容器，流水/报表/年度/设置都用它）没有移动端覆盖 → 卡片间距在移动端仍是 16px**；`.stack--sm` 恒 10px。整页卡片之间的视觉关系不随断点变化。

### B.24 下拉记一笔 `.pull-hint` / `.pull-bar`

```
div.pull-hint            (≤860 display:flex，但被 base.css !important 隐藏)
└─ span > svg(ArrowDown 11px) + 文本 "下拉记一笔"
div.pull-bar[v-if="pull>0"][style="height:{pull}px"][aria-hidden]  → 文案 "下拉记一笔" / "松开记一笔"
```
`.pull-hint { display:none; align-items:center; justify-content:center; gap:6px; font-family:var(--font-mono); font-size:9.5px; letter-spacing:.16em; text-transform:uppercase; color:var(--ink-3); padding:4px 0 0 }`；`span { display:grid; place-items:center; width:30px; height:14px; border:1px solid var(--line); border-radius:999px }`
`.pull-bar { height:0; overflow:hidden; display:flex; align-items:center; justify-content:center; color:var(--accent); font-size:11px; font-weight:700; transition:height .15s ease }`
**移动隐藏**：`.app .pull-hint { display:none !important }`（base.css:115-117）。
运行时数值（App.vue:71-73、94、99）：`PULL_THRESHOLD = 54`（px，松手判定）、`PULL_DAMPING = 0.62`、`PULL_MAX = 84`；位移 `pull = min(84, dy*0.62)`，且仅当 `window.scrollY <= 2` 且 `dy > 8` 时累计。

### B.25 业务组件 `PCatIcon`（`.cat-ic`）

**DOM**：`span.cat-ic[style="width;height;color;background;borderColor"] > svg(size*0.56, stroke 2.2)`
`.cat-ic { width:30px; height:30px; flex:0 0 auto; border-radius:9px; display:grid; place-items:center; border:1px solid transparent }`（`PCatIcon` 用内联 style 覆盖尺寸与三色）
内联着色规则（PCatIcon.vue）：`color: var(--chart-N|色值)`；`background: color-mix(in srgb, {c} 12%, transparent)`；`borderColor: color-mix(in srgb, {c} 45%, transparent)`
**cyber**：`.cat-ic { border-radius:1px }`
调用点尺寸：桌面表格 30、移动行卡 34、收款/涨跌榜 30、分类抽屉 rail 20 / grid 20、设置 rail 18 / kid 26、计划行 26、快捷分类 16、支出抽屉分类格 28。

### B.26 业务组件 `PPayIcon`

**DOM**：`svg[width={size} height={size} viewBox="0 0 1024 1024" fill=currentColor][style="color:{brandColor};flex:0 0 auto"] > path × n`，或退回 `Lucide 组件(size, stroke 2.2, style=color)`。
无自有 CSS 类；尺寸由调用方传：桌面表格 14、移动行卡 14、支出抽屉 18/15/16。

### B.27 业务组件 `CompositionCard`（`.composition`）

**DOM**
```
div.composition
├─ div.card-h > span.card-t "构成" + span.card-cap {总金额}
├─ div.seg (PSeg：分类/支付/记录人/节奏)
├─ div.empty (PEmpty，无数据时)
└─ div.stack-bar[style=margin-top:12px] > span × N [style="flex:{cents};background:{color}"]
   div.compose-legend[style=margin-top:10px] > span.cl-item × (前3) + (其他项)
```
`.composition { display:flex; flex-direction:column; gap:8px }`
`.stack-bar { display:flex; height:9px; border-radius:999px; overflow:hidden; background:var(--surface-3); border:1px solid var(--line); margin-top:8px }`；`.stack-seg { height:100%; transition:width .4s ease }`；cyber `.stack-bar { border-radius:0 }`
`.compose-legend { display:flex; flex-wrap:wrap; gap:6px 14px; margin-top:9px }`；`.cl-item { display:inline-flex; align-items:center; gap:5px; font-size:11px; color:var(--ink-2) }`；`.cl-dot { width:8px; height:8px; border-radius:2px; flex:0 0 auto }`；cyber `.cl-dot { border-radius:0; box-shadow:0 0 6px currentColor }`
本组件仅在 **流水页桌面版**使用（`PCard.desktop-only`），移动端不渲染。

### B.28 业务组件 `ReminderRow`（`.reminder` / `.rw-*`）—— 定义存在但页面未引用

**DOM**：`div.reminder[data-armed] > (div.rw-behind > span) + div.rw-track[style=transform] > span.rw-main(span.rw-t + span.rw-s) + span.rw-amt + slot`
`.reminder { position:relative; overflow:hidden; border-radius:var(--r-sm) }`
`.rw-behind { position:absolute; inset:0; display:flex; align-items:center; justify-content:flex-end; padding-right:14px; background:color-mix(in srgb, var(--danger) 14%, var(--surface)); color:var(--danger); font-family:var(--font-mono); font-size:10.5px; letter-spacing:.08em; text-transform:uppercase }`；`[data-armed='true'] .rw-behind { background:var(--danger); color:#fff }`
`.rw-track { position:relative; display:flex; align-items:center; gap:10px; padding:8px 2px; background:var(--surface); touch-action:pan-y; cursor:grab }`
`.rw-main { min-width:0; flex:1 1 auto; flex column; gap:2px }`；`.rw-t { font-size:12.5px; font-weight:600; ellipsis; nowrap }`；`.rw-s { font-size:10.5px; color:var(--ink-3) }`；`.rw-amt { font-size:12.5px; font-weight:600; flex:0 0 auto }`
手势常量：阈值 `0.6 × 容器实测宽度`，最大位移 `-width*0.92`，右向阻尼 `min(24, delta*0.3)`，回弹 `transform .24s cubic-bezier(.22,1,.36,1)`。文案：`armed ? '松开忽略' : '左滑忽略'`。
（`.reminder-row` 在 views.css:447 另有一份 div 版样式：`padding:9px 12px; border:1px solid var(--line); border-radius:var(--r-md); background:var(--surface-2); overflow:hidden`，同样未被页面引用。）

### B.29 业务组件 `BrandMark`

**DOM**：`img.brand-mark[src][width={size}][height={size}][alt="SuenMoney"]`
`.brand-mark { display:block; flex:0 0 auto; border-radius:12px }`
图源按主题切换：cyber → `/logo.svg`；candy → `/mark-light.svg`。调用尺寸：侧栏 46（移动端 CSS 不能改 img 的 width 属性，实际仍 46 —— 见 E.7）、登录 56、关于 68。

### B.30 `ColorPicker` / `IconPicker` / `PayIconPicker`（表单子组件）

**ColorPicker**：`div.color-picker > button.cp-auto[.is-on] "自动" + button.cp-cell × 16[.is-on][style=background:var(...)]`
`.color-picker { display:flex; flex-wrap:wrap; gap:6px; align-items:center }`；`.cp-cell { width:26px; height:26px; border-radius:8px; border:2px solid transparent; transition:transform .16s }`；`:hover { transform:scale(1.12) }`；`.cp-cell.is-on { border-color:var(--ink) }`；`.cp-auto { padding:4px 10px; border:1px solid var(--line); border-radius:999px; font-size:11px; color:var(--ink-2); font-family:var(--font-mono) }`；`.cp-auto.is-on { border-color:var(--accent); color:var(--accent) }`
**IconPicker**：`div.icon-picker > input.input + div.ip-scroll > div.ip-group(span.field-l + div.ip-grid > button.ip-cell ×)` 
`.icon-picker { flex column; gap:8px }`；`.ip-scroll { max-height:240px; overflow-y:auto; flex column; gap:10px }`；`.ip-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(38px,1fr)); gap:6px; margin-top:6px }`；`.ip-cell { aspect-ratio:1; display:grid; place-items:center; border:1px solid var(--line); border-radius:var(--r-sm); background:var(--surface); color:var(--ink-2); transition:all .16s }`；`:hover { color:var(--ink); border-color:var(--ink-3) }`；`.is-on { border-color:var(--accent); color:var(--accent); box-shadow:0 0 0 2px color-mix(in srgb, var(--accent) 25%, transparent) }`
**PayIconPicker**：`div.pay-icon-picker > button.pip-auto + button.pip-cell × N(PPayIcon 18 + span.pip-l)`
`.pay-icon-picker { display:grid; grid-template-columns:repeat(auto-fill,minmax(84px,1fr)); gap:6px }`；`.pip-cell { display:flex; align-items:center; gap:6px; padding:7px 8px; border:1px solid var(--line); border-radius:var(--r-sm); background:var(--surface); color:var(--ink-2); transition:all .16s; min-width:0 }`；`:hover { border-color:var(--ink-3); color:var(--ink) }`；`.is-on { border-color:var(--accent); color:var(--ink); box-shadow:0 0 0 2px color-mix(in srgb, var(--accent) 22%, transparent) }`；`.pip-l { font-size:10.5px; ellipsis; nowrap }`；`.pip-auto { padding:7px 12px; border:1px solid var(--line); border-radius:999px; font-size:11px; font-family:var(--font-mono); color:var(--ink-2) }`；`.is-on { border-color:var(--accent); color:var(--accent) }`

### B.31 `base.css` 应用级补丁（会被移动端看到的）

1. 路由过渡：`.page-enter-active { transition: opacity 200ms ease, transform 200ms cubic-bezier(.22,1,.36,1) }`；`.page-leave-active { transition: opacity 120ms ease-out }`；`.page-enter-from { opacity:0; transform:translateY(6px) }`；`.page-leave-to { opacity:0 }`
2. `.no-scrollbar { scrollbar-width:none; -ms-overflow-style:none }` + `::-webkit-scrollbar{display:none}`
3. `.build-stamp`（见 B.2）
4. `.app .set-t, .app .set-s, .app .set-body > span { display:block }`；`.app .set-s { margin-top:2px }`；`.app .set-body { display:flex; flex-direction:column; gap:0; min-width:0; flex:1 1 auto }`
5. `.plan-ticks { display:flex; gap:2px; margin-top:6px }`；`.plan-ticks i { flex:1 1 0; height:4px; border-radius:2px; background:var(--surface-3) }`；`.plan-ticks i.is-done { background:var(--accent) }`；cyber：`i{border-radius:0}`、`i.is-done{box-shadow:0 0 6px color-mix(in srgb, var(--accent) 60%, transparent)}`
6. `.more-menu { position:relative; flex:0 0 auto }`；`> summary { list-style:none; cursor:pointer; padding:3px 8px; border-radius:var(--r-sm); border:1px solid var(--line); color:var(--ink-3); font-size:11px; font-family:var(--font-mono); line-height:1.4 }`；`:hover { color:var(--ink); border-color:var(--ink-3) }`；`.more-menu-pop { position:absolute; right:0; top:calc(100% + 4px); z-index:5; min-width:120px; flex column; padding:4px; background:var(--surface); border:1px solid var(--line); border-radius:var(--r-sm); box-shadow:var(--shadow-card) }`；`.more-menu-pop button { text-align:left; padding:6px 8px; border-radius:6px; font-size:11.5px; color:var(--ink-2) }`；`:hover { background:var(--surface-2); color:var(--ink) }`；`.is-danger { color:var(--danger) }`

---

## C. 各屏（移动端 ≤860px）

屏清单（7 屏）：外壳 App · 流水 · 概况 · 报表 · 年度报告 · 设置 · 登录/初始化；另加"记账抽屉"（含两个选择器与账单导入抽屉）。
每屏给出：移动端 DOM 树（缩进=嵌套，带类名）→ mobile-only / desktop-only → 关键尺寸（注明来源选择器）→ 交互状态。

### C.1 外壳（App.vue，所有非公开页共用）

**移动端 DOM 树**
```
div.app[data-theme=candy|cyber][data-decor=on][data-density=cozy]
├─ span.deco.deco-a / .deco-b / .deco-c / .deco-d      ← cyber 下 display:none
├─ div.shell
│  ├─ aside.sidebar                                    ← 移动：sticky 顶条，只含品牌行
│  │  ├─ a.brand
│  │  │  ├─ img.brand-mark (46×46，border-radius 12px)
│  │  │  └─ div.brand-txt
│  │  │     ├─ div.brand-name  "SuenMoney"             ← 移动 15px
│  │  │     └─ div.brand-sub   "FAMILY LEDGER · 单账本"  ← 移动 display:none
│  │  ├─ nav.nav  (nav-cap + 4×a.nav-item)              ← 移动 display:none（整条）
│  │  └─ div.side-foot (button.members + div.build-stamp) ← 移动 display:none
│  └─ div.main
│     ├─ header.topbar[.topbar--bare]                   ← 流水页整条 display:none
│     │  ├─ button.icon-btn.mobile-only  (返回 ChevronLeft)  ← 仅非流水页存在
│     │  ├─ div.topbar-txt (title+sub)                  ← 移动 display:none !important
│     │  └─ div.topbar-actions (icon-btn 主题 + btn 记一笔) ← 移动 display:none !important
│     └─ main.content
│        ├─ div.pull-hint (span>svg + "下拉记一笔")       ← 移动 display:none !important
│        ├─ div.pull-bar[v-if=pull>0][style=height:{pull}px]  ← 仅下拉过程中出现
│        ├─ <RouterView>  ← Transition.page (out-in)
│        └─ div.build-stamp  "SuenMoney · 单账本家庭记账 · {BUILD_STAMP}[ · 离线模式| · 待同步 N]"
├─ div.toast[v-if=message][role=status]                 ← 全局轻提示
└─ ExpenseSheet (:open=ui.sheetOpen)                    ← 见 C.8
```

**mobile-only / desktop-only**
| 元素 | 类/条件 | ≤860 行为 |
|---|---|---|
| 返回按钮 | `PIconBtn.mobile-only` + `v-if="route.name !== 'ledger'"` | 显示；`@media(min-width:861px){.mobile-only{display:none!important}}` |
| 顶栏文本 | `.topbar-txt` | `display:none !important`（base.css:106-109） |
| 顶栏动作（主题+记一笔） | `.topbar-actions` | `display:none !important` |
| 流水页顶栏 | `.topbar--bare` | `display:none !important`（不占位） |
| 下拉提示 | `.pull-hint` | `display:none !important` |
| 导航条 | `.sidebar .nav` | `display:none`（views.css:1115，无 `!important`） |
| 导航标题/侧栏页脚 | `.nav-cap` `.side-foot` | `display:none`（app.css:741） |
| 品牌副标题 | `.sidebar .brand-sub` | `display:none`（app.css:736） |
| 侧栏 `.desktop-only` | `app.css:777 .desktop-only{display:none!important}` | 隐藏 |

**关键尺寸（来源选择器）**
- 侧栏条：`.sidebar`（移动最终）：`position:sticky; top:0; z-index:60; padding:8px 14px 6px; flex-direction:row; flex-wrap:wrap; align-items:center; gap:8px 10px; background:var(--bg); backdrop-filter:blur(10px); border-bottom:1px solid var(--line); overflow-x:auto; overflow-y:hidden`
- 品牌图标：`img.brand-mark[width=46][height=46]` + `.brand-mark{display:block;flex:0 0 auto;border-radius:12px}` → **img 的 width/height 是 HTML 属性，`32px` 的 CSS 规则作用于 `.logo-ph`（未渲染的原型占位块），所以移动端品牌图标实际仍是 46×46**（见 E.7）
- 品牌名：`.brand-name{font-size:15px}`（views.css:1117）
- 顶栏：`.topbar{padding:8px 12px; gap:8px; align-items:center; border-bottom:1px solid var(--line); background:var(--nav-bg); backdrop-filter:blur(14px); position:sticky; z-index:30}`
- 内容区：`.content{padding:6px 12px 64px; gap:12px; max-width:1280px; margin:0 auto}`
- z-index 栈（自上而下）：cyber 扫描线 `::after` 999 → `.toast` 120 → `.picker` 96 → `.picker-mask` 95 → `.modal` 91 → `.sheet` 81 → `.scrim` 80 → `.sidebar` 60 → `.topbar` 30 → `.more-menu-pop` 5 → `.deco/::before` 0。
- 过渡：路由 `opacity 200ms + translateY(6px)` 进、`opacity 120ms` 出。

**交互状态**
- 下拉记一笔（唯一记账入口，移动端无兜底按钮）：手指在 `scrollY<=2` 时下拉 `dy>8` 起算，位移 `min(84, dy*0.62)`，`≥54px` 松手 → 打开记账抽屉；未达标回 0。`pull-bar` 高度实时等于 `pull`，文案在 `<54` 时"下拉记一笔"、`≥54` 时"松开记一笔"。
- 主题切换按钮在移动端被隐藏 → 移动端切主题只能进 **设置 → 数据 → 主题**。
- 安卓返回键：抽屉开启时先关抽屉（`ui.sheetOpen` → `ui.closeSheet()`），否则交路由。

### C.2 流水 `LedgerView.vue`（移动端落地页）

**移动端 DOM 树**
```
div.stack
├─ div.mobile-hero.mobile-only                     ← ★移动端独有顶部卡
│  ├─ div.mh-head
│  │  ├─ span.mh-eyebrow     "{YYYY年M月} · 本月支出"
│  │  ├─ div.mh-amt          > span.cur "¥" + 金额文本
│  │  └─ div.mh-delta        > span.delta-pill[.pos|.neg] "{x.x}%"   (v-if deltaRatio≠null)
│  ├─ div.mh-facts           > div.mh-fact ×3 (span 标签 + b 数值)：日均 / 笔数 / 本月要还
│  ├─ div.mh-nav.mh-nav--sm  > button.mh-btn ×3 "概况" "报表" "设置"
│  ├─ button.hero-todo[v-if="dueTodos.length>0"][aria-expanded]
│  │  ├─ span.todo-dot[.is-late|.is-soon|.is-calm]
│  │  ├─ span.hero-todo-t  "{n} 笔待办"
│  │  ├─ span.mono.tiny    合计金额
│  │  ├─ span.urgency.urgency--late "(n) 笔逾期"   (v-if overdue>0)
│  │  ├─ span[style=margin-left:auto]
│  │  └─ svg ChevronUp/ChevronDown (13)
│  └─ div.mh-todos[v-if="todoOpen && dueTodos.length>0"]
│     └─ div.todo-line × N
│        ├─ i.todo-mark.is-soon|.is-late [style=height:20px]
│        ├─ span.todo-line-t "{seq}期 · {计划名}"
│        ├─ span.urgency.urgency--soon|--late "自动" | "需手动"
│        └─ b.mono.tiny 金额
├─ div.card (PCard)                                 ← 工具栏
│  └─ div.ledger-toolbar[.is-open]
│     ├─ div.lt-search (@click=openAdvOnNarrow)
│     │  ├─ div.search-wrap > svg.ic(Search 15) + input.input.input--search  "搜索备注或分类"
│     │  └─ button.btn.btn--ghost.btn--sm.lt-collapse "收起"  (v-if advOpen)
│     └─ div.lt-adv   ← 移动端默认 display:none；.is-open 时 display:flex
│        ├─ div.seg (PSeg: 按月/按年/全部)
│        ├─ div.period-nav > icon-btn(‹) + span.period-label + icon-btn(›)
│        ├─ button.btn.btn--sm(.btn--primary when 有筛选) "筛选[ · n]"
│        └─ div.seg[style=margin-left:auto] > button.seg-btn ×2 "按日期" "按金额"
├─ div.filter-row.filter-row--roomy (v-if showFilters)
│  ├─ div.filter-group > span.filter-l "分类" + chip ×N
│  ├─ div.filter-group > span.filter-l "支付" + chip ×N
│  └─ div.filter-group > span.filter-l "记录人" + chip ×N (+ ghost btn 清除)
├─ div.card.desktop-only   ← ★移动端隐藏（四维构成卡 CompositionCard）
├─ div.card (v-if tier==='month')                   ← 明细
│  ├─ div.card-h > span.card-t "流水明细" + span.card-cap "{n} 笔 · 合计 ¥x"
│  ├─ div.empty (PEmpty "加载中…" / "没有符合条件的流水")
│  ├─ table.tbl.desktop-only                        ← ★移动端隐藏
│  ├─ div.m-list.mobile-only                        ← ★移动端独有行卡
│  │  └─ div × 分组
│  │     ├─ div.date-cap "{日期文案}" + span.sum.mono "{当日小计}"
│  │     └─ button.m-row × N
│  │        ├─ span.cat-ic (PCatIcon size=34)
│  │        ├─ span.m-row-main
│  │        │  ├─ span.m-row-t  > span 分类名 + span.tag.tag--danger "退款"(v-if 负数)
│  │        │  └─ span.m-row-s  > 备注 · 支付方式 · 记录人（3 段用 "·" 分隔）
│  │        └─ span.row-end
│  │           ├─ span.row-amt[.pos] 金额
│  │           └─ span.tiny.muted.mono[style=display:block]  "{MM-DD} 还" | "即时"
│  └─ div[style=margin-top:14px;text-align:center]
│     └─ button.btn "加载更多"(disabled 时 "加载中…") | button.btn.btn--ghost "查看上月"
├─ div.card (v-else-if tier==='year')               ← 年档 12 月格
│  ├─ div.card-h > span.card-t "{YYYY} 年" + span.card-cap "合计 ¥x"
│  └─ div.cal-year-grid > button.year-cell ×12
│     ├─ div.split > span.y-m "M月" + span.tag.tag--accent "本月"(当月) + span.tiny.muted.mono "{n} 笔"
│     ├─ div.y-v 金额
│     └─ div.bar[style=height:5px;margin-top:2px] > span.bar-fill[style=width:x%]
└─ div.card (v-else)                                 ← 全部档 一年一格
   ├─ div.card-h > span.card-t "全部记录" + span.card-cap "{n} 年 · 合计 ¥x"
   └─ div.empty | div.cal-year-grid > button.year-cell ×N (span.y-m 年份 …)
```

**mobile-only / desktop-only**
- mobile-only：`div.mobile-hero.mobile-only`（整张顶部卡 + 其中 mh-nav 三入口 + 待办展开）、`div.m-list.mobile-only`。
- desktop-only：`PCard.desktop-only`（CompositionCard 四维构成）、`table.tbl.desktop-only`（明细表）。
- 仅移动出现：`.lt-collapse`"收起"（`@media(min-width:861px){.lt-collapse{display:none!important}}`，views.css:1007-1009）；`.lt-adv` 仅在 `.ledger-toolbar.is-open` 时可见。

**关键尺寸（来源选择器）**
| 区域 | 值 | 来源 |
|---|---|---|
| 顶部卡 | `padding:14px; border:2px solid var(--line-2); border-radius:20px; background:var(--surface); box-shadow:4px 4px 0 var(--line-2); display:flex; flex-direction:column; gap:12px` | `.mobile-hero` views.css:1012-1022 |
| 顶部卡 cyber | `border-width:1px; border-radius:0; border-color:rgba(0,255,136,.45); background:linear-gradient(180deg, rgba(0,255,136,.06), transparent 62%); box-shadow:0 0 30px -16px rgba(0,255,136,.6)` | views.css:1023-1029 |
| eyebrow | `font-family:var(--font-mono); font-size:9.5px; letter-spacing:.14em; uppercase; color:var(--ink-3)` | `.mh-eyebrow` :1031 |
| 大金额 | `display; 800; font-size:38px; line-height:1.05; letter-spacing:-.035em; tabular-nums; gap:2px; align-items:baseline`；`.cur{font-size:.48em;700;color:var(--ink-2)}` | `.mh-amt` :1032-1043 |
| cyber 大金额 | `color:var(--accent); letter-spacing:.01em; text-shadow:0 0 20px rgba(0,255,136,.4)` | :1044 |
| 环比行 | `font-size:10.5px; color:var(--ink-3); gap:8px; flex-wrap:wrap` | `.mh-delta` :1045 |
| 环比胶囊 | `padding:3px 8px; border-radius:999px; border:1.5px solid currentColor; mono; 10.5px; 700`；cyber `radius 0; border-width 1px` | `.delta-pill` views.css:43-54 |
| 三事实条 | `display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:8px; padding:9px 0; border-top/bottom:1px dashed var(--line)` | `.mh-facts` :1046-1053 |
| 事实单元 | 标签 `mono 9px var(--ink-3)`；值 `11px/700; nowrap; ellipsis; tabular-nums` | `.mh-fact span/b` :1054-1056 |
| 三入口 | `display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:6px` | `.mh-nav`+`.mh-nav--sm` :1085 / LedgerView:703-705 |
| 入口按钮 | `min-height:30px; padding:0 4px; font-size:11.5px; border:1px solid var(--line); border-radius:999px; background:var(--surface-2); color:var(--ink-2); gap:0`；`:active{transform:scale(.98)}`；cyber `border-color:rgba(0,255,136,.32); color:var(--accent); font-size:10px` | `.mh-nav--sm .mh-btn` LedgerView:706-723（**覆盖原型 `.mh-btn` 的 `min-height:44px; border:2px; background:var(--surface); color:var(--ink); font-size:11.5px`**） |
| 待办提醒条 | `display:flex; gap:8px; margin-top:10px; padding:7px 10px; width:100%; text-align:left; border:1px solid var(--line); border-radius:var(--r-sm); background:var(--surface-2); color:var(--ink-2); font-size:11.5px`；`:hover{border-color:var(--ink-3);color:var(--ink)}` | `.hero-todo` LedgerView:728-746（与 Dashboard 同值） |
| 待办点 | `6×6; radius 50%; background:var(--ink-3)`；`.is-late{background:var(--danger)}`；`.is-soon{background:var(--warn)}` | `.todo-dot` LedgerView:756-768 |
| 待办行 | `display:flex; gap:8px; padding:5px 0; border-bottom:1px solid var(--line)`；`.todo-line-t{flex:1 1 auto; 11.5px; ellipsis; nowrap}` | LedgerView:769-818 |
| 工具栏 | `.ledger-toolbar{display:flex; align-items:center; gap:8px; flex-wrap:wrap}` | `views.css:925`（移动 gap 8） |
| 搜索区 | `.lt-search{flex:1 1 100%; gap:8px}`；`.search-wrap{flex:1 1 auto; min-width:0}` | views.css:997-998 |
| 高级区展开 | `.ledger-toolbar .lt-adv{display:none; width:100%; margin-left:0}`；`.ledger-toolbar.is-open .lt-adv{display:flex; gap:8px; flex-wrap:wrap}`；`.lt-adv .seg{flex:1 1 100%}`；`.lt-adv .seg .seg-btn{flex:1 1 0}` | views.css:999-1005 |
| 期间标签 | `.period-label{min-width:76px; text-align:center; display; 700; 14px; padding:0 4px}`（移动缩窄） | views.css:176-183 + LedgerView:696-698 |
| 筛选区 | `.filter-row--roomy{flex-direction:column; gap:12px; margin-top:14px; padding-top:14px; border-top:1px dashed var(--line)}`；`.filter-group{gap:6px 8px; flex-wrap:wrap}`；`.filter-l{width:100%; margin-bottom:2px; mono 9.5px; ls .12em}` | LedgerView:781-809 |
| 移动行卡 | `.m-row{padding:10px; gap:8px; border:2px solid var(--line); border-radius:var(--r-md); background:var(--surface); width:100%; text-align:left}`；cyber `border-width:1px; border-radius:0`；`:active{transform:scale(.995)}` | `.m-row` views.css:204-216 + 930 |
| 行卡标题 | `.m-row-t{display:flex; align-items:center; gap:6px; font-size:12.5px; font-weight:600}` | views.css:931 |
| 行卡副行 | `.m-row-s{display:flex; gap:6px; font-size:10px; color:var(--ink-3); margin-top:3px; flex-wrap:wrap}` | views.css:219 |
| 行卡列表 | `.m-list{display:flex; flex-direction:column; gap:8px}` | views.css:203 |
| 日期分组头 | `.date-cap{display:flex; gap:8px; padding:12px 4px 6px; mono 10.5px; ls .08em; color:var(--ink-2); uppercase}`；`.sum{margin-left:auto; color:var(--ink-3)}` | views.css:189-200 |
| 年格网格 | `.cal-year-grid{grid-template-columns:repeat(3,minmax(0,1fr)); gap:10px}`（移动） | views.css:777 |
| 年格 | `.year-cell{border:2px solid var(--line); border-radius:var(--r-md); background:var(--surface); padding:12px 10px; flex column; gap:4px; text-align:left}`；`:hover{translateY(-2px)}` | views.css:224-239 |

**交互状态**
- 三档切换（`.seg` 按月/按年/全部）：切换后重拉明细与报表；`tier==='all'` 时期间前后按钮 `disabled`（`.btn[disabled]` 只影响 btn；`icon-btn` 靠 `:disabled` 原生）。
- 高级筛选：移动端默认收起；点搜索区任意位置（`openAdvOnNarrow`，`matchMedia('(max-width:860px)')` 命中时）展开；点"收起"（`.lt-collapse`）折叠。
- 待办展开：`todoOpen` 切换 `mh-todos`；`aria-expanded` 同步。无待办时整条 + 展开区都不渲染。
- 空态：`PEmpty` 两处文案"加载中…"（loading）/"没有符合条件的流水"（无数据）；全部档"还没有任何记录"。
- 分页：`hasMore` 时显示"加载更多"（`loadingMore` 时按钮 disabled 且文案"加载中…"）；否则显示"查看上月"。
- 点击行卡 → `ui.openEdit(row)` 打开记账抽屉（编辑态）。

### C.3 概况 `DashboardView.vue`

> 移动端不是落地页（`/` 在 ≤860 跳到流水），进入路径=流水顶部卡三入口的"概况"。

**移动端 DOM 树**
```
div.overview-grid[style=grid; 移动 1 列; gap 12px]
├─ div.card.og-hero.card--pop[style:grid-column 1/-1]
│  ├─ div.hero-eyebrow
│  │  ├─ div.seg (PSeg 本月/本年/全部)
│  │  ├─ span[style=margin-left:auto]
│  │  ├─ div.period-nav > icon-btn(‹) + span.mono.tiny[style=min-width:92px] 期间文案 + icon-btn(›)
│  │  └─ span.tag.tag--dash "全部记录"  (tier==='all')
│  ├─ button.hero-todo[v-if=待办>0]  (todo-dot + 文案 + 金额 + 逾期数 + 箭头)
│  ├─ div.hero-amt > span.cur "¥" + 金额
│  ├─ div.hero-delta > span.delta-pill[.pos|.neg] + span "较上月/去年/上一段 ¥x"
│  ├─ div.hero-metrics > div.stat ×3 (span.stat-v + span.stat-l)
│  ├─ div.stack-bar[style=margin-top:14px] > span × N [style="flex:{cents};background:{color}"]
│  ├─ div.compose-legend[style=margin-top:8px] > span.cl-item × N (i.cl-dot + 名 + b.mono "%")
│  └─ div.hero-todos[v-if="alertOpen && 待办>0"]
│     └─ div.todo-line × N
│        ├─ i.todo-mark.is-{late|soon|calm}[style=height:22px]
│        ├─ span.todo-line-t "{seq}期 · {计划名}"
│        ├─ span.urgency.urgency--{...} "自动"|"需手动"
│        ├─ b.mono.tiny 金额
│        ├─ button.btn.btn--sm.btn--ghost "确认"|"入账"
│        └─ details.more-menu > summary "更多" + div.more-menu-pop > button.is-danger "忽略本期"
├─ div.card.og-heat.og-card
│  ├─ div.card-h > span.orb(amber) + span.card-t "月度支出热力" + span.card-cap "近 12 个月 · 点击下钻"
│  ├─ div.og-card-body > div.heat-grid > button.heat-cell ×12
│  │  ├─ span.heat-m "M月" / span.heat-v 金额|— / span.heat-dot[style=background]
│  └─ div.og-card-foot > span.tiny.muted + button.btn.btn--sm.btn--ghost "打开报表"
├─ div.card.og-cum.og-card
│  ├─ div.card-h > span.orb(mint) + span.card-t "累计与跨度" + span.card-cap "全部历史口径"
│  └─ div.og-card-body > div[style=flex column gap 10px] > div.kv ×5 (span.tiny.muted + b)
└─ p.tiny.muted[style=text-align:center] "加载中…" (v-if loading)
```

**mobile-only / desktop-only**：**无任何 `mobile-only`/`desktop-only` 类**。移动差异全部是 CSS 栅格/字号覆盖。

**关键尺寸（来源选择器）**
| 区域 | 值 | 来源 |
|---|---|---|
| 网格 | `.overview-grid{display:grid; grid-template-columns:repeat(12,minmax(0,1fr)); gap:16px; align-items:stretch}` → 移动 `{grid-template-columns:minmax(0,1fr); gap:12px}`，`.og-hero/.og-todo/.og-heat/.og-cum/.og-progress{grid-column:span 1}` | views.css:945-955、991-992 |
| 主卡占满 | `.og-hero{grid-column:1 / -1}`（组件 scoped，所有宽度生效） | DashboardView:418 |
| 主卡内距 | `.card` 移动 `padding:14px; border-radius:16px; box-shadow:3px 3px 0 #E9EEF6`（app.css:759，同为单类选择器且位置更靠后 → **同样压掉 `.card--pop` 的 `--shadow-card-pop`**，故移动端 candy 的 pop 卡阴影也是 `3px 3px 0 #E9EEF6`；cyber 下 `.app[data-theme="cyber"] .card` 覆盖为 `box-shadow:none`）；`.card--pop` 仅剩 `border-color:var(--line-2)` 生效 | app.css:288-304、759-760 |
| 期间标签行 | `.hero-eyebrow{display:flex; align-items:center; gap:8px; mono 10px; ls .16em; uppercase; color:var(--ink-3)}` | views.css:14-23 |
| 大金额 | `.hero-amt{margin:8px 0 4px; display; 800; font-size:34px（移动覆盖 clamp(36px,5vw,52px)）; line-height:1; ls -.035em; tabular-nums; baseline; gap:4px}`；`.cur{font-size:.5em;700;color:var(--ink-2)}` | views.css:24-36、775 |
| 环比 | `.hero-delta{font-size:11.5px; color:var(--ink-2); gap:8px; wrap}` | views.css:42 |
| 三指标 | `.hero-metrics{grid 3 列; gap:8px（移动覆盖 10px）; margin-top:16px; padding-top:14px; border-top:1px dashed var(--line)}`；cyber `border-top-style:solid` | views.css:55-63、774 |
| 堆叠条 | `.stack-bar{height:9px; radius 999; bg var(--surface-3); border:1px solid var(--line); overflow:hidden; margin-top:8px}`（此屏内联 `margin-top:14px`） | views.css:167 |
| 图例 | `.compose-legend{gap:6px 14px; margin-top:9px}`；`.cl-item{11px; color:var(--ink-2); gap:5px}`；`.cl-dot{8×8; radius 2}` | views.css:792-795 |
| 热力网格 | `.og-heat .heat-grid{grid-template-columns:repeat(4,minmax(0,1fr))}`（移动）；`.og-heat .heat-cell{padding:7px 3px}` | views.css:994-995 |
| 热力格 | `.heat-cell{border:1px solid var(--line); border-radius:7px; padding:7px 3px 6px; background:var(--surface-2); flex column; gap:3px; align-items:center; text-align:center}`；`.heat-m{mono 9px}`；`.heat-v{mono 10px 700}`；`.heat-dot{width:100%; height:4px; radius 999}` | views.css:130-149 |
| 卡脚 | `.og-card-foot{margin-top:12px; padding-top:10px; border-top:1px dashed var(--line); display:flex; align-items:center; gap:10px; flex-wrap:wrap}`；`.og-card-foot .btn{margin-left:auto}` | views.css:959-968 |
| 累计行 | `.kv{display:flex; justify-content:space-between; gap:10px; padding:8px 0; border-bottom:1px dashed var(--line); font-size:12px}`；`.kv b{mono 600}` | views.css:544-546 |
| 待办展开行 | `.todo-line{gap:8px; padding:5px 0; border-bottom:1px solid var(--line)}`；`.hero-todos{margin-top:4px; padding:2px 10px 4px}` | DashboardView:461-466、600-618 |

**交互状态**
- 三档 seg 切换：`switchTier` 重设 anchor 并重载；`tier==='all'` 时隐藏期间前后按钮、显示 `tag--dash "全部记录"`。
- 待办提醒：`alertOpen` 控制展开；无待办整条不渲染。展开行内"确认/入账"按 `willAutoPost` 分支，"忽略本期"收在 `details.more-menu`。
- 热力格：可点，跳报表并带 `?month=YYYY-MM`；`is-now` 为当前月（`border:var(--line-2); box-shadow:2px 2px 0 var(--line-2)`；cyber `0 0 12px rgba(0,255,136,.35) + border accent`）。
- 加载态：整页仅底部一行 `p.tiny.muted "加载中…"`（无骨架屏）。

### C.4 报表 `ReportView.vue`

**移动端 DOM 树**
```
div.stack
├─ div.card.report-head
│  ├─ div.toolbar
│  │  ├─ div.seg (PSeg 本月/本年/全部)
│  │  ├─ div.period-nav > icon-btn(‹) + span.period-label + icon-btn(›)
│  │  ├─ span[style=margin-left:auto]
│  │  └─ button.btn.btn--sm.btn--ghost "{YYYY} 年度报告" (+Sparkles 14)
│  └─ div.report-facts
│     ├─ div.rf-main > span.tiny.muted.mono "期间支出" + b.rf-num 金额
│     └─ div.rf-items
│        ├─ span.delta-pill[.pos|.neg]
│        ├─ span.rf-i "对比 <b>¥x</b>"
│        ├─ span.rf-i "日均 <b>¥x</b>"
│        └─ span.rf-i "笔数 <b>n</b>"
├─ div.card.report-compose
│  ├─ div.card-h (移动 flex-wrap:wrap; row-gap 8)
│  │  ├─ span.card-t "支出构成"
│  │  ├─ span.card-cap "分类 / 支付 / 记录人 / 节奏"   ← ★移动端 display:none
│  │  └─ span.chips[style=margin-left:auto]          ← ★移动端 width:100%、nowrap 横滑
│  │     └─ button.chip ×4 (分类/支付/记录人/节奏)
│  ├─ div.empty (PEmpty "这个期间还没有构成数据")
│  └─ div.compose-view[data-dim]
│     ├─ div.compose-visual
│     │  ├─ div.donut (PDonut，dim=cat)
│     │  ├─ div.week-bars > div.week-bar ×7 (em.mono + i[style=height] + span)   (dim=week)
│     │  └─ div.dim-bars > div.dim-bar ×N (span.db-l + span.db-track>i + span.db-v.mono) (dim=pay/owner)
│     └─ div.compose-list
│        └─ div.legend-row ×N (i[style=background] + span.l-n + span.l-v + span.l-p)
├─ div.report-pair   ← 移动 1 列（≤1080 已单列）
│  ├─ div.card  涨跌榜
│  │  ├─ div.card-h > span.card-t + span.card-cap
│  │  ├─ div.mover-grid > div.mover ×N (span.cat-ic 30 + div(mover-t + mover-s) + div.row-end.mono.tiny)
│  │  ├─ div.empty (PEmpty "该期间没有可对比的分类"/"切到「月」档看涨跌")
│  │  └─ div.report-note 一句话结论
│  └─ div.card  还款节奏
│     ├─ div.card-h > span.card-t + span.card-cap
│     └─ div.repay-steps > div.repay-col ×6 (span.mono 8.5px 金额 + i[style=height] + span "M月")
├─ button.report-banner[style=width:100%;text-align:left]
│  ├─ div > div.rb-t "{YYYY} 年度报告已生成" + div.rb-s "年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势"
│  ├─ span.spacer[style=margin-left:auto]
│  └─ svg ChevronRight (18)
└─ p.tiny.muted[style=text-align:center] "加载中…" (v-if loading)
```

**mobile-only / desktop-only**：无 `mobile-only`/`desktop-only` 类。移动隐藏项 = `.report-compose .card-h .card-cap`（`display:none`，views.css:1128）。

**关键尺寸（来源选择器）**
| 区域 | 值 | 来源 |
|---|---|---|
| 页头卡 | `.report-head{padding:14px}`（移动） | views.css:879 |
| 事实行 | `.report-facts{gap:10px !important; margin-top:14px; align-items:flex-end; flex-wrap:wrap}` | views.css:818、880 |
| 主数字 | `.rf-num{font-family:var(--font-display); font-size:26px（移动，覆盖 30px）; ls -.02em; line-height:1.1}`；cyber `text-shadow:0 0 18px rgba(0,255,136,.35)` | views.css:820、881、824 |
| 事实小项 | `.rf-items{gap:8px 10px; padding-bottom:0; flex-wrap:wrap; align-items:center}`；`.rf-i{font-size:10.5px（移动）; color:var(--ink-2)}`；`.rf-i b{color:var(--ink); mono 600}` | views.css:821-823、882-883 |
| 构成卡 卡头 | `.report-compose .card-h{flex-wrap:wrap; row-gap:8px}`；`.chips{width:100%; margin-left:0 !important; flex-wrap:nowrap; overflow-x:auto; padding-bottom:2px}`；`.chips .chip{flex:0 0 auto}` | views.css:1127-1138 |
| 构成主体 | `.compose-view{display:flex; flex-direction:column; align-items:stretch; gap:12px; margin-top:8px}`（移动） | views.css:1139-1144 |
| 环图 | CSS 声明 `.compose-visual .donut{width:136px;height:136px}`、`.compose-visual{justify-content:center}`——**但 PDonut 内联 176px 覆盖**（E.4） | views.css:1145-1146 |
| 图例列表 | `.compose-list{width:100%; gap:0}`；`.compose-list .legend-row{display:grid; grid-template-columns:9px minmax(0,1fr) 64px 32px; gap:8px; padding:6px 0; border-bottom:1px dashed var(--line)}`；`:last-child{border-bottom:0}`；`.l-n{max-width:none}`；`.l-p{width:auto}` | views.css:1147-1157 |
| 图例基线 | `.legend-row{gap:8px; font-size:11.5px; align-items:center}`；`i{9×9; radius 3; flex:0 0 auto}`；`.l-v{mono; tabular-nums}`；`.l-p{mono 10px; color:var(--ink-3); width:38px; text-align:right}` | views.css:285-289、889-890 |
| 条形维度 | `.dim-bars{flex column; gap:8px}`；`.dim-bar{grid 62px 1fr 76px; gap:10px; align-items:center}`；`.db-track{height:10px; radius 99px; background:var(--surface-3); overflow:hidden}`；`.db-v{text-align:right; 11px; color:var(--ink-2)}` | ReportView:377-411 |
| 周柱 | `.week-bars{grid 7 列; gap:6px（移动：112px 高 / gap 6，见 views.css:785+915）; height:112px; padding-top:8px; align-items:end}`；`.week-bar{flex column; align-items:center; gap:6px; height:100%; justify-content:flex-end}`；`i{width:100%; max-width:30px; radius 6px 6px 2px 2px; background:var(--accent); border:1px solid var(--line-2); min-height:3px}`；`span{mono 9px}`；`em{mono 8.5px; font-style:normal}` | views.css:291-305 |
| 两栏 | `.report-pair{grid-template-columns:minmax(0,1fr); gap:16px}`（≤1080）；`> .card{height:100%}` | ReportView:362-375 |
| 涨跌项 | `.mover{display:flex; gap:9px; padding:9px 10px; border:1px solid var(--line); border-radius:var(--r-md); background:var(--surface-2)}`；`.mover-grid{1 列（移动）; gap:10px}` | views.css:307-319、780 |
| 结论 | `.report-note{margin-top:12px; padding-top:10px; border-top:1px dashed var(--line); font-size:11px（移动）; line-height:1.7; color:var(--ink-2)}` | views.css:836、1162 |
| 还款柱 | `.repay-steps{display:flex; align-items:flex-end; gap:8px; height:96px}`；`.repay-col{flex:1 1 0; flex column; center; gap:5px; height:100%; justify-content:flex-end}`；`i{width:100%; radius 5px 5px 0 0; background:var(--pink); border:1px solid var(--line-2); min-height:4px}` | views.css:321-325 |
| 年度横幅 | `.report-banner{padding:16px 18px; border:2px solid var(--line-2); border-radius:var(--r-card); background:linear-gradient(100deg, var(--accent), #A78BFA 65%, var(--pink)); color:#fff; box-shadow:5px 5px 0 var(--line-2); display:flex; gap:14px; align-items:center}`；`.rb-t{display 800 16px}`；`.rb-s{11px; opacity:.9; margin-top:2px}`；`:hover{translate(-2px,-2px)}` | views.css:338-355 |

**交互状态**
- 四维切换（卡片头 chips）→ `dim` 变化，视觉区在 环图 / 周柱 / 条形 三形态间切换；图例行同步。
- 涨跌榜只在 `tier==='month'` 且有上期数据时非空；否则 `PEmpty`。
- 年度横幅点击跳 `annual-summary?year=YYYY`；页头"年度报告"按钮同目标。
- 加载态：底部一行 `p.tiny.muted "加载中…"`。

### C.5 年度报告 `AnnualSummaryView.vue`

**移动端 DOM 树**
```
div.stack
├─ div.card
│  └─ div.split > icon-btn(‹) + span.mono[style=font-size:15px;font-weight:700] 年份 + icon-btn(›) + button.btn.btn--ghost.btn--sm[style=margin-left:auto] "返回报表"
├─ div.card.card--pop
│  ├─ div.card-h > span.orb(accent) + span.card-t "{YYYY} 年度全貌" + span.card-cap "{n} 个月 · m 笔"
│  ├─ div.hero-amt (span.cur ¥ + 金额)
│  ├─ div.hero-delta (span.delta-pill + span "去年 ¥x")
│  └─ div.hero-metrics[style=margin-top:14px] > div.stat ×3 (月均 / 单笔均值 / 空月)
├─ div.card
│  ├─ div.card-h > span.card-t "12 个月走势" + span.card-cap "按还款日归属"
│  ├─ div.empty | div[style="display:flex;gap:4px;align-items:flex-end;height:140px"]
│  │  └─ button ×12 (span[style=height:x%;background;border-radius:3px 3px 0 0] + span.tiny.muted[style=font-size:9.5px])
├─ div.g2   ← ★移动端变 1 列
│  ├─ div.card 最高支出月 (span.card-t + 大号月份 + span.tiny.muted 金额)
│  └─ div.card 单笔最贵   (span.card-t + 大号金额 + span.tiny.muted "{分类} · {日期}")
├─ div.card (v-if topCategory)
│  ├─ div.card-h > span.card-t "支出最多的分类" + span.card-cap "全年"
│  └─ div.split[style=align-items:baseline] > span(15px/700 分类名) + span.mono[style=margin-left:auto] 金额 + span.mono.tiny.muted "%"
└─ p.tiny.muted "加载中…" (v-if loading)
```
**mobile-only / desktop-only**：无。移动差异仅 `.g2 → 1 列`（app.css:758）。12 月柱高 `140px` 为内联固定值（不随断点变化）。"最高支出月 / 单笔最贵" 两块内联 `font-size:26px; font-weight:800; font-family:var(--font-display)`。

### C.6 设置 `SettingsView.vue`

**移动端 DOM 树（四个 tab 共用外层）**
```
div.stack
├─ div.settings-tabs[role=tablist]        ← 移动横滑、无滚动条、gap 4
│  └─ button.stab ×4 (账目 / 计划与还款 / 数据 / 家庭) [.is-on]
│
├─ 《tab=ledger 账目》
│  ├─ div.card
│  │  ├─ div.card-h > span.orb + span.card-t "分类管理" + button.btn.btn--sm "新增类别"[margin-left:auto]
│  │  └─ div.cat-admin              ← 移动 1 列
│  │     ├─ div.cat-rail            ← 移动 flex-direction:row !important; flex-wrap:wrap
│  │     │  └─ button.cat-rail-btn ×N [.is-on]  (span.cat-ic 18 + span 名称 + span.tiny.muted.mono 子类数)
│  │     └─ div
│  │        ├─ div.split[style=margin-bottom:8px] > span.tiny.muted.mono "{一级} · 分类" + spacer + btn--sm(新增分类/编辑类别/删除)
│  │        ├─ div.cat-kid-list
│  │        │  └─ div.cat-kid ×N (span.cat-ic 26 + span(名称 + tag--warn 已停用 / tiny.muted 引用数) + icon-btn 编辑 + icon-btn 删除)
│  │        └─ div.hint[style=margin-top:10px] "分类与支付方式均为软删除…"
│  └─ div.card
│     ├─ div.card-h > span.orb(sky) + span.card-t "支付方式" + btn--sm "新增"
│     └─ div.set-row ×N (span.set-ic > PPayIcon 18 + span.set-body(set-t 名称 + set-s 账单/还款) + btn--sm.ghost "合并" + icon-btn 编辑 + icon-btn 删除)
│
├─ 《tab=plans 计划与还款》
│  ├─ div.card 还款计划：card-h(card-t + card-cap + btn "新建计划") + div.set-row.plan-row ×N
│  │     └─ set-row: span.cat-ic 26 + span.set-body
│  │        ├─ span.set-t 计划名 + tag(--dash 已结束 | --accent 自动)
│  │        ├─ span.set-s "{已还}/{总} 期 · 每期 ¥x · 下次 M-D"
│  │        ├─ span.plan-ticks > i ×12 [.is-done]
│  │        └─ details.more-menu (终止计划 / 删除计划.is-danger)
│  ├─ div.card 已处理 / 已忽略：set-row ×N (set-t + tag + set-s + btn--sm.ghost 恢复|撤销)
│  └─ div.card 待处理期次：set-row ×N (i.todo-mark + set-body + btn--sm.btn--primary 确认|入账 + more-menu 忽略本期)
│
├─ 《tab=data 数据》
│  ├─ div.card 主题 > div.theme-cards.theme-cards--3 > button.theme-card ×3
│  │     └─ span.theme-prev > i.tp-candy|.tp-cyber|.tp-system ; span(12px/700 名称) ; span.tiny.muted 描述
│  ├─ div.card 导出 > div.split > btn(Database 图标)"导出账本（JSON）" + btn "导出流水（CSV）"
│  ├─ div.card 导入 > div.split > label.btn.btn--ghost "选择 JSON 文件" + btn.btn--primary "账单导入（微信 / 支付宝）"
│  ├─ div.card 备份 > div.split(下载备份文件 / 立即上传到 WebDAV) + div.stack--sm[style=margin-top:12px]
│  │     ├─ label.field(span.field-l "WebDAV 地址" + input.input)
│  │     ├─ div.g2[style=gap:8px]  ← ★移动端变 1 列
│  │     │  ├─ field 用户名 + field 口令（password）
│  │     ├─ field 远端目录
│  │     ├─ div.set-row[style=padding:4px 0] (set-body: set-t 启用 WebDAV 备份 + set-s 说明；switch)
│  │     └─ div.split > btn 测试连接 + btn primary 保存配置 + tag--dash 提示
│  ├─ div.card 数据库快照 > card-h(card-t + card-cap "{n} 个" + btn 创建快照) + set-row ×N (set-t 文件名 + set-s "{时间} · {KB} KB" + btn--sm.ghost 下载 + icon-btn 删除)
│  ├─ div.card 检查更新 (v-if canCheckUpdate) > btn + span.tiny.muted
│  ├─ div.card 数据总览 (v-if overview) > set-row ×N (set-body.set-t + b.mono) + p.hint
│  ├─ div.card 关于 > card-h(card-t + card-cap build) + div.about-card (BrandMark 68 + about-name + about-slogan + about-meta + tiny.muted)
│  └─ div.card 危险操作 > card-h + div.danger-zone > div.split ×2 (文案 + btn--sm.btn--danger 清空 / btn--sm.ghost 重置)
│
├─ 《tab=household 家庭》
│  ├─ div.card 成员 > card-h + set-row ×N (set-body: set-t 显示名 + set-s "@用户名" + tag--accent 管理员)
│  ├─ div.card 登录设备 > card-h + set-row ×N (set-t 设备 + tag--accent 当前 + set-s 最近活跃)
│  └─ div.card 我的账号 (v-if me) > card-h + div.split[style=align-items:flex-end] (field 显示名 flex 1 1 200px + btn 保存)
│        + div.g2[style=gap:8px;margin-top:12px] 当前口令/新口令 + p.hint + btn.btn--primary 修改口令
│
├─ BillImportModal（账单导入抽屉，见 C.8）
└─ 5 个 PSheet 表单抽屉：分类表单 / 支付方式表单 / 支付方式合并 / 计划表单 / 成员表单
   （结构同 B.18：sheet-head 标题 + sheet-body 若干 field + sheet-foot 保存/取消）
```
**mobile-only / desktop-only**：无该类；隐藏项仅 PSheet 未打开时不渲染（`v-if="open"`）。
**关键尺寸（来源选择器）**
| 区域 | 值 | 来源 |
|---|---|---|
| 页签条 | `.settings-tabs{display:flex; gap:4px（移动）; border-bottom:1px solid var(--line); overflow-x:auto; scrollbar-width:none}` | views.css:461、935、875-876 |
| 页签 | `.stab{padding:7px 10px（移动）; font-size:11.5px（移动）; border:0; border-bottom:3px solid transparent; font-weight:700; color:var(--ink-3); white-space:nowrap; flex:0 0 auto}`；`.is-on{color:var(--ink); border-bottom-color:var(--accent)}`；cyber `{mono 11px; uppercase; ls .1em}` + `is-on{color:var(--accent); text-shadow}` | views.css:462-475、932、877 |
| 分类管理 | `.cat-admin{grid-template-columns:minmax(0,1fr)}`（移动）；`.cat-rail{flex-direction:row !important; flex-wrap:wrap; gap:4px}` | views.css:908-909、500-501 |
| 一级按钮 | `.cat-rail-btn{display:flex; gap:8px; padding:7px 9px; border-radius:9px; border:2px solid transparent; font-size:12px; font-weight:600; color:var(--ink-2); width:auto（移动）; white-space:nowrap}`；`.is-on{background:var(--surface-2); border-color:var(--line-2); color:var(--ink)}` | views.css:502-518、769 |
| 二级卡 | `.cat-kid{display:flex; gap:8px; padding:8px 10px; border:1px solid var(--line); border-radius:10px; background:var(--surface)}`；`cyber{radius 0; bg transparent}` | views.css:520-529 |
| 设置行 | `.set-row{display:flex; align-items:center; gap:12px; padding:11px 0; border-bottom:1px solid var(--line)}`；`:last-child{0}` | views.css:477-484 |
| 行图标 | `.set-ic{32×32; radius 9; background:var(--surface-2); border:1px solid var(--line); color:var(--ink-2); grid; place-items:center}`；cyber `radius 1px` | views.css:485-494 |
| 行文本 | `.set-t{font-size:12.5px; font-weight:600}`；`.set-s{font-size:10.5px; color:var(--ink-3); margin-top:2px; line-height:1.5}`；base.css 追加 `.set-body{flex column; gap:0; min-width:0; flex:1 1 auto}` | views.css:496-497 + base.css:127-141 |
| 主题卡 | `.theme-cards--3{grid-template-columns:repeat(3,minmax(0,1fr))}`，`@media(max-width:720px){…--3{grid-template-columns:minmax(0,1fr)}}` → **≤720 单列、721–860 三列** | views.css:814-815 |
| 主题卡本体 | `.theme-card{border:2px solid var(--line); border-radius:var(--r-md); padding:10px; background:var(--surface); flex column; gap:8px; text-align:left}`；`.is-on{border-color:var(--line-2); box-shadow:3px 3px 0 var(--line-2)}`；`:hover{translateY(-2px)}` | views.css:734-748 |
| 主题缩略 | `.theme-prev{height:56px; border-radius:8px; border:1px solid rgba(0,0,0,.12); overflow:hidden; display:flex}` | views.css:749 |
| 危险区 | `.danger-zone{border:2px dashed var(--danger); border-radius:var(--r-md); padding:14px; flex column; gap:10px}` | views.css:541 |
| 关于卡 | `.about-card{flex column; center; gap:10px; text-align:center; padding:26px 18px}`；`.about-name{display 800 22px}`；`.about-slogan{11.5px; color:var(--ink-2)}`；`.about-meta{mono 10px; color:var(--ink-3); gap:14px; wrap; center}` | views.css:759-763 |
| 计划进度刻度 | `.plan-ticks{gap:2px; margin-top:6px}`；`i{flex:1 1 0; height:4px; radius 2; background:var(--surface-3)}`；`.is-done{background:var(--accent)}` | base.css:152-171 |

**交互状态**
- 页签切换用 `v-if/v-else-if/v-else` 整块替换（无过渡动画）。
- `details.more-menu` 为原生 `<details>`，点外部不自动收起。
- 所有表单走 `PSheet`（移动=底部抽屉 93dvh），底部按钮：保存（primary）+ 取消（ghost）。
- 空态：分类列表 "这个一级分类下还没有二级分类"、支付方式 "还没有支付方式"、计划 "还没有计划"、待办 "没有待处理的期次"、快照 "还没有快照"、成员 "还没有成员"、会话 "没有会话记录"。

### C.7 登录 / 初始化 `LoginView.vue`（`meta.public`，不套外壳）

**DOM 树**（该页 `<style scoped>` 内**没有任何 `@media`**，因此移动端与桌面同结构、同尺寸）
```
div.app.login-page[data-theme][data-decor=on]        ← 注意：无 data-density
├─ span.deco.deco-a / b / c / d
└─ div.login-shell
   ├─ div.card.card--pop.login-card
   │  ├─ div.login-brand > img.brand-mark(56) + div(div.brand-name + div.brand-sub)
   │  ├─ div.card-h > span.card-t "初始化账本"|"登录" + span.card-cap "第一次使用"|"家庭共用"
   │  ├─ p.hint 说明文案
   │  ├─ form.login-form
   │  │  ├─ label.field > span.field-l "登录名" + input.input (placeholder "小写字母")
   │  │  ├─ [setup] label.field > span.field-l "显示名" + input.input
   │  │  ├─ label.field > span.field-l "口令（至少 8 位）" + input.input[type=password]
   │  │  ├─ p.login-error (v-if errorMessage)
   │  │  └─ button.btn.btn--primary[style=width:100%;justify-content:center] > svg ShieldCheck(14) + 文案
   │  ├─ div.login-foot
   │  │  ├─ button.btn.btn--ghost.btn--sm "已有账号，去登录" | "首次部署？初始化账本"
   │  │  └─ button.btn.btn--ghost.btn--sm "服务器设置" (v-if isNative)
   │  ├─ div.login-server (v-if isNative && showServerConfig)
   │  │  ├─ label.field 服务器地址 + input.input
   │  │  └─ div.split > btn--sm "测试" + btn--sm.btn--primary "保存" + span.tag.tag--dash 提示
   └─ p.build-stamp "{PLAYFUL|CYBERPUNK} · SuenMoney"
```
**尺寸（scoped，无断点）**：`.login-page{display:flex; align-items:center; justify-content:center; min-height:100vh/100dvh; padding:24px 16px}`；`.login-shell{width:100%; max-width:420px; position:relative; z-index:1}`；`.login-card{flex column; gap:12px}`；`.login-brand{flex; align-items:center; gap:12px; margin-bottom:4px}`；`.login-form{flex column; gap:12px; margin-top:4px}`；`.login-error{font-size:12px; color:var(--danger); margin:0}`；`.login-foot{flex; gap:8px; flex-wrap:wrap}`；`.login-server{flex column; gap:10px; border-top:1px dashed var(--line); padding-top:12px}`
**交互状态**：`canSubmit = 用户名非空 && 密码 ≥8 位 && 非 busy` → 否则主按钮 `disabled`（`opacity:.45`）；`busy` 时文案"处理中…"；初始化被 403 拒绝自动切回登录模式；`needsSetup===true` 时隐藏"去登录/初始化"切换按钮；`isNative`（非 web 平台）才显示"服务器设置"。

### C.8 记账抽屉 `ExpenseSheet.vue`（含分类选择器 / 支付方式选择器）+ 账单导入抽屉

**移动端 DOM 树**
```
template[v-if=open]
├─ div.scrim (@click=close)
├─ div.sheet[role=dialog][aria-modal][aria-label="记一笔"|"编辑支出"]
│  ├─ div.sheet-head
│  │  ├─ span.sheet-title "记一笔"|"编辑支出"
│  │  ├─ span.tag.tag--danger "退款冲销" (v-if isRefund)
│  │  ├─ span.tag.tag--accent "{n} 期免息" (v-if periods)
│  │  ├─ span[style=margin-left:auto]
│  │  ├─ button.icon-btn 删除 (v-if 编辑态)
│  │  └─ button.icon-btn ✕ 关闭
│  ├─ div.sheet-body
│  │  ├─ div.amt-display
│  │  │  ├─ span.a-cur "-¥" | "¥"
│  │  │  ├─ span.a-val 金额 | "0.00"
│  │  │  └─ span.a-tail 支付方式名
│  │  ├─ div.g2[style=gap:8px]                    ← ★移动端 1 列（上下堆叠）
│  │  │  ├─ button.sheet-cell (PCatIcon 28 + span(span.lbl "分类" + span.val 分类名) + ChevronRight 14)
│  │  │  └─ label.sheet-cell (input[type=date][max=today])
│  │  ├─ button.sheet-cell (PPayIcon 18 + span(span.lbl "支付方式" + span.val 名 (+ span.tiny.muted "· 信用卡")) + ChevronRight 14)
│  │  ├─ input.input  placeholder "备注（选填）"
│  │  ├─ div.set-row[style=padding:6px 0]  退款：span.set-ic > svg + span.set-body(set-t + set-s) + switch
│  │  ├─ div.set-row[style=padding:6px 0]  分期：span.set-ic + span.set-body + div.split(select.input[width:84px] + switch)
│  │  ├─ div.preview-box "金额预览（不落库先算）：…"（跨月时 span.preview-cross 高亮）
│  │  ├─ p.tiny[style=color:var(--danger)] 错误文案
│  │  ├─ div.month-spent (span.mono.tiny.muted "本月已支出" + b.mono 金额)
│  │  ├─ div.quick-cats > button.quick-cat ×6 [.is-on] (PCatIcon 16 + span 名称)
│  │  ├─ input.input.desktop-only.amt-input       ← ★移动端隐藏
│  │  └─ div.keypad.mobile-only                   ← ★移动端独有
│  │     ├─ div.paycol
│  │     │  ├─ button.pay-key ×5 [.is-on] (PPayIcon 15 + span 前 4 字)
│  │     │  └─ button.pay-key (span "⋯" + span "更多")
│  │     └─ div.keys
│  │        └─ button.key ×15 + button.key.key--ok "完成"
│  │           (顺序: 7 8 9 ← / 4 5 6 清空 / 1 2 3 [完成跨 3-4 行] / 0 00 .)
│  └─ div.sheet-foot
│     ├─ button.btn.btn--primary[style=flex:1 1 auto] "{记下这笔|保存修改|保存中…}" (+Check 14)
│     └─ button.btn.btn--ghost "取消"
├─ template[v-if=catOpen]  分类选择器
│  ├─ div.picker-mask (@click=catOpen=false)
│  └─ div.picker[role=dialog][aria-label="选择分类"]
│     ├─ div.picker-head > span.modal-title "选择分类" + span.tiny.muted.mono "一级 n / 二级 m" + icon-btn ✕
│     └─ div.picker-body
│        ├─ div.picker-rail > button.picker-rail-btn ×N [.is-on] (PCatIcon 20 + 名称)
│        └─ div.picker-grid > button.picker-cell ×N [.is-on] (PCatIcon 20 + span 名称)
└─ template[v-if=payOpen]  支付方式选择器
   ├─ div.picker-mask
   └─ div.picker[style="width:min(440px,calc(100vw - 20px))"]
      ├─ div.picker-head > span.modal-title "支付方式" + span.tiny.muted.mono "账期随卡" + icon-btn ✕
      └─ div[style=padding:12px;overflow-y:auto] > div.pay-list > button.pay-item ×N [.is-on]
         (span.set-ic > PPayIcon 16 + span(名称 + 说明) + svg Check 16 当前项)
```

**mobile-only / desktop-only**
| 元素 | 判定 | 说明 |
|---|---|---|
| `input.input.desktop-only.amt-input` | `desktop-only` | ≥861 才渲染；`text-align:right; display 22px; 700; ls -.01em` |
| `div.keypad.mobile-only` | `mobile-only` | ≤860 渲染，5 列键盘 + 左支付列 |
| `.sheet` 形态 | CSS | ≤860 变底部抽屉（93dvh，顶部圆角 22px），桌面为右侧 500px 抽屉 |
| `.g2` 内两格 | CSS | ≤860 由两列变一列（分类格与日期格上下排） |

**关键尺寸（来源选择器）**
| 区域 | 值 | 来源 |
|---|---|---|
| 抽屉 | 移动 `{height:93dvh; width:100%; bottom:0; border-top:2px solid var(--line-2); border-radius:22px 22px 0 0}`；cyber `{border-radius:0; border-top:1px solid var(--accent)}` | app.css:762-773 |
| 抽屉头 | `{padding:12px 14px}`；标题 `15px` | views.css:921-922 |
| 抽屉体 | `{padding:12px; gap:10px; max-height:calc(93dvh - 124px); overflow-y:auto; -webkit-overflow-scrolling:touch}` | views.css:904、920 |
| 抽屉脚 | `{padding:12px 16px; padding-bottom:calc(12px + env(safe-area-inset-bottom)); border-top:1px solid var(--line); display:flex; gap:8px}` | app.css:590 + views.css:906 + ExpenseSheet:700-702 |
| 金额条 | 基线 `.amt-display{padding:6px 2px 10px; display:flex; align-items:baseline; gap:3px; border-bottom:2px dashed var(--line)}` → 移动 `{padding:10px 12px}` | views.css:615-621、905 |
| 货币符 | `.a-cur{font-family:var(--font-display); font-size:22px; 700; color:var(--ink-3)}` → scoped `{font-size:20px; align-self:flex-start; margin-top:6px}` | views.css:622 + ExpenseSheet:789-793 |
| 金额数字 | `.a-val{display; 800; font-size:clamp(34px,8vw,44px); ls -.03em; line-height:1; tabular-nums; ellipsis; nowrap}`；scoped `{font-size:clamp(30px,7vw,44px)}`（**生效**）；views.css 移动 34px 被 scoped 覆盖；矮屏 `26px` | views.css:623-633、923 + ExpenseSheet:794-796、714-716 |
| 尾部 | `.a-tail{margin-left:auto; display:flex; gap:6px; font-size:11px; color:var(--ink-3); mono}` | views.css:635 |
| 分类/日期/支付格 | `.sheet-cell{display:flex; align-items:center; gap:10px; width:100%; padding:10px 12px; border:2px solid var(--line); border-radius:var(--r-md); background:var(--surface); text-align:left; font-size:12.5px}`；`:hover{border-color:var(--line-3,var(--ink-3))}`；`.lbl{mono 9.5px; ls .12em; uppercase; color:var(--ink-3)}`；`.val{600}`；cyber `{border-width:1px; border-radius:0; background:transparent}` | views.css:637-653 |
| 预览框 | `.preview-box{padding:9px 11px; border:1px dashed var(--line); border-radius:var(--r-sm); background:var(--surface-2); mono 10.5px; color:var(--ink-2); line-height:1.65（移动）/1.7}`；矮屏 `display:none` | views.css:699-710、924 + ExpenseSheet:717-719 |
| 本月已支出 | `.month-spent{display:flex; align-items:baseline; gap:8px; padding:2px 4px}`；`b{12px; color:var(--ink)}`；极矮屏隐藏 | ExpenseSheet:742-751、723-727 |
| 快捷分类条 | `.quick-cats{display:flex; gap:6px; overflow-x:auto; padding:6px 2px; border-radius:var(--r-sm); background:color-mix(in srgb, var(--surface-3) 60%, transparent)}` | ExpenseSheet:753-764 |
| 快捷分类胶囊 | `.quick-cat{inline-flex; gap:5px; flex:0 0 auto; padding:5px 10px; border:1px solid var(--line); border-radius:999px; background:var(--surface); color:var(--ink-2); 11.5px; 600; nowrap}`；`.is-on{border-color:var(--accent); color:var(--ink); box-shadow:0 0 0 2px color-mix(in srgb, var(--accent) 20%, transparent)}`；cyber `radius 0` | ExpenseSheet:765-786 |
| 键盘外包 | `.keypad{display:grid; grid-template-columns:54px minmax(0,1fr)（移动，覆盖 62px）; gap:clamp(4px,1.1vw,7px)（scoped 覆盖 7px）}` | views.css:655、899 + ExpenseSheet:684-686 |
| 支付列 | `.paycol{display:grid; grid-template-columns:1fr; gap:6px}`（scoped，覆盖 views 的 `flex column; gap:4px`） | ExpenseSheet:797-801、views.css:900 |
| 支付键 | `.pay-key{flex:1 1 0; border:2px solid var(--line); border-radius:10px; background:var(--surface); flex column; center; gap:2px; padding:2px; font-size:8.5px; color:var(--ink-2); line-height:1.1}`；`.is-on{border-color:var(--line-2); background:var(--accent); color:var(--accent-ink)}`；cyber `{border-width:1px; border-radius:0; background:transparent; mono}` + `is-on{border-color:var(--accent); background:rgba(0,255,136,.12); color:var(--accent); box-shadow:0 0 12px -3px rgba(0,255,136,.7)}` | views.css:657-675 |
| 支付键（生效尺寸） | scoped：`min-height:clamp(34px,5.4dvh,48px); font-size:clamp(7.5px,2.1vw,9px)`（覆盖 views.css 的 `min-height:40px; font-size:8px`）；矮屏 `min-height:32px` | ExpenseSheet:692-695、711-713 |
| 数字键区 | `.keys{display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); grid-template-rows:repeat(4,minmax(0,1fr)); gap:5px}` | views.css:676 |
| 数字键 | `.key{min-height:44px; border:2px solid var(--line); border-radius:11px; background:var(--surface); font-family:var(--font-display); font-size:18px; 700; color:var(--ink); display:grid; place-items:center; transition:transform .1s, background .12s}`；`:hover{background:var(--surface-2)}`；`:active{transform:scale(.96)}` | views.css:677-691 |
| 数字键（生效尺寸） | scoped：`min-height:clamp(38px,6.1dvh,54px); font-size:clamp(15px,4.3vw,19px); border-radius:clamp(8px,2.4vw,12px)`（覆盖 views 的 46px/16px）；矮屏 `min-height:36px; font-size:15px`；极矮屏 `32px/14px` | ExpenseSheet:687-691、707-710、728-731 |
| 功能键 | `.key--fn{font-family:var(--font-body); font-size:11px; 700; color:var(--ink-2)}`；cyber `{color:var(--cyan)}` | views.css:692、696 |
| 完成键 | `.key--ok{grid-column:4; grid-row:3 / 5; background:var(--accent); color:var(--accent-ink); border-color:var(--line-2); font-size:13px; font-family:var(--font-body)}`，移动 `12px`；cyber `{background:var(--accent); color:#04170d; box-shadow:0 0 18px rgba(0,255,136,.5)}` | views.css:693-697、903 |
| 分类选择器 | `.picker{width:min(660px,calc(100vw - 20px)); max-height:86dvh; border:2px solid var(--line-2); border-radius:var(--r-card)}`；`.picker-body{grid-template-columns:94px minmax(0,1fr)（移动，覆盖 132px）; min-height:300px}`；`.picker-grid{grid-template-columns:repeat(2,minmax(0,1fr))（移动，覆盖 3 列）; padding:12px; gap:7px}` | views.css:549-597、781-782、910 |
| 选择器单元 | `.picker-cell{padding:9px; border:2px solid var(--line); border-radius:10px; background:var(--surface); font-size:11.5px; 600}`；`.is-on{border-color:var(--line-2); background:var(--surface-2); box-shadow:2px 2px 0 var(--line-2)}` | views.css:584-597 |
| 支付列表 | `.pay-item{padding:10px 12px; border:2px solid var(--line); border-radius:var(--r-md); background:var(--surface)}`；`.is-on{border-color:var(--line-2); box-shadow:2px 2px 0 var(--line-2)}`；`~cyber` 同前 | views.css:600-612 |

**交互状态**
- 键盘输入规则：`C` 清空、`B` 退格、`.` 只允许一个小数点且小数最多 2 位、整数最多 9 位、前导 `0` 被替换。
- 金额 0 → 保存报错"请输入金额"；分类/支付未选 → "请选择分类与支付方式"；分期离线 → "分期需要联网创建"。
- 退款开关：开启后 `a-cur` 变 `-¥`，金额取负；开启退款会清空分期期数。分期开关：非信用卡时 toast "切到信用卡后才能分期"。
- 快捷分类只在有分类时渲染；`is-on` 跟随 `categoryId`。
- 切支付方式/日期会请求 `previewDates`（信用卡账期），跨月时 `preview-cross` 用 accent + 700 提示"这笔会记在 X 月"。
- 底部主按钮 `saving` 时 disabled 且文案"保存中…"。

**账单导入抽屉（BillImportModal，从设置→数据→导入打开）**
```
div.sheet (PSheet title="账单导入")
├─ sheet-head （标题 + ✕）
├─ sheet-body
│  ├─ div.card 选择账单文件：card-h + div.split > label.btn.btn--primary "选择 CSV 文件"(+FileUp 14, 内含隐藏 input[file]) + select.input[style=max-width:180px]
│  │   + p.hint 操作路径说明 + p.tiny.muted "已读取：… · 识别为 …"
│  ├─ div.card (v-if items.length) 确认要导入的支出
│  │   ├─ card-h + div.split(全选支出 / 全不选)
│  │   └─ div.import-list > div.import-row ×N
│  │      (input[checkbox] + span.ir-main(ir-t + ir-s) + select.input.ir-cat + select.input.ir-pay + span.ir-amt.mono + tag--dash)
│  └─ div.empty "还没有选择文件"
└─ sheet-foot > btn primary "导入 {n} 笔" + btn ghost 取消
```
移动端行布局（BillImportModal:258-267）：`.import-row{grid-template-columns:18px minmax(0,1fr) auto; row-gap:4px}`（桌面 `18px minmax(0,1fr) 110px 110px 88px auto`）。`.import-list{max-height:46vh; overflow-y:auto; gap:6px}`。

---

## D. 移动端专属形态清单（逐条对照桌面端）

| # | 维度 | 桌面（≥861px） | 移动（≤860px） | 依据 |
|---|---|---|---|---|
| D1 | 主导航 | 左侧 244px 竖排：`nav-cap "账目"` + 4 个 `.nav-item`（图标+文字，纵排 gap 5） | **整条不渲染** | `.sidebar .nav{display:none}` views.css:1115；桌面 `.shell{grid-template-columns:244px minmax(0,1fr)}` app.css:9 |
| D2 | 移动端导航替代 | — | 流水页 `mobile-hero` 内 `.mh-nav.mh-nav--sm` 三按钮（概况/报表/设置）+ 顶栏返回箭头 | LedgerView:390-394；App.vue:211-217 |
| D3 | 侧边栏定位与朝向 | `position:sticky; top:0; height:100dvh; flex-direction:column; gap:26px; padding:22px 16px 18px; border-right:1px solid var(--line); background:var(--bg-2)` | `position:sticky; top:0; z-index:60; height:auto; flex-direction:row; flex-wrap:wrap; gap:8px 10px; padding:8px 14px 6px; border-right:0; border-bottom:1px solid var(--line); background:var(--bg); backdrop-filter:blur(10px); overflow-x:auto` | `.sidebar` app.css:15-26 / 723-734 / views.css:860-869、1114 |
| D4 | 品牌块 | 46px 标 + 20px 字标 + 9px/0.2em 副标（"FAMILY LEDGER · 单账本"） | 副标 `display:none`；字标 15px；logo 的 CSS 尺寸规则指向未渲染的 `.logo-ph` | `.sidebar .brand-sub{display:none}` app.css:736；`.brand-name{font-size:15px}` views.css:1117 |
| D5 | 侧栏页脚（同步状态 + build stamp） | `.side-foot`（`button.members` + `.sync-dot` + `.build-stamp`） | `display:none`；改由 `.content` 末尾的 `.build-stamp` 承担 | `.nav-cap, .side-foot{display:none}` app.css:741；App.vue:247-251 |
| D6 | 顶栏内容 | 标题 + 副标 + 主题切换 icon-btn + 主按钮「记一笔」 | 仅剩返回箭头（非流水页）；流水页整条顶栏不渲染 | `base.css:105-118`（`.topbar-txt`/`.topbar-actions`/`.topbar--bare` 全 `!important` 隐藏） |
| D7 | 顶栏间距 | `padding:13px 28px; gap:14px` | `padding:8px 12px; gap:8px` | app.css:177 vs views.css:1118 |
| D8 | 记账入口 | 顶栏「记一笔」按钮（`PBtn variant=primary`） | **无按钮**；下拉手势（阈值 54px、阻尼 0.62、上限 84px）+ 期间内出现的 `.pull-bar`；提示条 `.pull-hint` 被 `!important` 隐藏 | App.vue:70-103、233-239；base.css:114-117 |
| D9 | 内容区 | `padding:22px 28px 72px; gap:16px` | `padding:6px 12px 64px; gap:12px` | app.css:207 vs views.css:1121 |
| D10 | 卡片 | `padding:18px; border-radius:20px(2px cyber); box-shadow:6px 6px 0 #E9EEF6` | `padding:14px; border-radius:16px; box-shadow:3px 3px 0 #E9EEF6`（cyber：`radius 0; shadow none`） | `.card` app.css:288-295 / 759-760 |
| D11 | 概况 hero 卡 | `.og-hero` 内 `.hero-amt` `clamp(36px,5vw,52px)`，三指标 `.hero-metrics` gap 10 | 同一张卡：`.hero-amt{font-size:34px}`、`.hero-metrics{gap:8px}`；栅格从 12 列变 1 列 gap 12 | views.css:28、775、56、774、991 |
| D12 | 流水独有顶部卡 | **不存在**（桌面直接是工具栏卡） | `.mobile-hero.mobile-only`：38px 金额 + 三事实条 + 三入口 + 待办提醒 | LedgerView:374；`.mobile-hero` views.css:1012-1022 |
| D13 | 流水明细形态 | `table.tbl.desktop-only`：7 列（日期/分类/备注/账期/记录人/支付方式/金额），按消费日插入小计行 | `div.m-list.mobile-only`：`button.m-row` 行卡（34px 分类图标 + 标题行 + 备注·支付·记录人副行 + 右对齐金额与"还款日 还/即时"） | LedgerView:512-618；`.m-row` views.css:204-216 |
| D14 | 四维构成卡 | 流水页 `PCard.desktop-only` 内 `CompositionCard`（PSeg 四维 + 堆叠条 + 图例） | **隐藏**（改动到报表页四维卡） | LedgerView:496；`app.css:777` |
| D15 | 流水工具栏 | 搜索 + seg + 期间 + 筛选 + 排序按钮全部平铺 | `lt-adv` 默认 `display:none`，点搜索区展开；展开时出现「收起」（`lt-collapse`，桌面 `display:none`）；`.seg` 与 `.seg-btn` 拉满整行 | views.css:999-1009 |
| D16 | 报表构成卡 | 两栏 `.compose-view{1.1fr 1fr; gap:22px}`，卡头带 `.card-cap` | `flex column; gap:12px`；`.card-cap` 隐藏；`.chips` 全宽横滑；图例行改 `grid-template-columns:9px minmax(0,1fr) 64px 32px` + 虚线分隔；`.l-n` 取消 128px 上限 | views.css:827 / 1126-1158 |
| D17 | 报表页头 | `.rf-num{30px}`，`.rf-i{11px}`，`.report-facts{gap:20px}` | `.report-head{padding:14px}`、`.rf-num{26px}`、`.rf-i{10.5px}`、`gap:10px !important`、`.rf-items{padding-bottom:0}` | views.css:818-824 / 879-883 |
| D18 | 年度报告月份柱 | `height:140px`（内联，不随断点）；`.annual-months` 定义 `140px` | 内联同样是 140px；`.annual-months` 移动声明 `104px`（**该选择器未被使用**）；`.g2` → 1 列 | AnnualSummaryView:110；views.css:394、784 |
| D19 | 抽屉方向与尺寸 | 右侧固定：`top/right/bottom:0; width:min(500px,100vw); border-left:2px solid var(--line-2); animation:slideIn` | 底部上滑：`top:auto; left/right/bottom:0; width:100%; height:93dvh; border-left:0; border-top:2px solid var(--line-2); border-radius:22px 22px 0 0`（cyber：`radius 0; border-top:1px solid var(--accent)`） | app.css:566-578 / 762-773 |
| D20 | 抽屉内距 | head `14px 16px`、body `14px 16px 18px` gap 12、title 16px | head `12px 14px`、body `12px` gap 10 且 `max-height:calc(93dvh - 124px)`、title 15px、foot 加 `env(safe-area-inset-bottom)` | views.css:904-906、920-922 |
| D21 | 记账金额输入 | `input.input.desktop-only.amt-input`（右对齐 display 22px/700） | **隐藏**；改用 `.keypad.mobile-only` 自绘键盘 | ExpenseSheet:524-533 |
| D22 | 键盘布局 | 无 | `grid-template-columns:54px minmax(0,1fr)`：左 `.paycol`（5 个 `.pay-key` + "更多"），右 `.keys` 4×4（`7 8 9 ←` / `4 5 6 清空` / `1 2 3 [完成跨 3–4 行]` / `0 00 .`）；键高 `clamp(38px,6.1dvh,54px)`、字号 `clamp(15px,4.3vw,19px)`；≤720 高 36/15px；≤620 高 32/14px 并隐藏 `.quick-cats`/`.month-spent` | views.css:655-697 / 899-903 + ExpenseSheet:683-732 |
| D23 | 支付键列 | `min-height:40px; font-size:8px` | `min-height:clamp(34px,5.4dvh,48px); font-size:clamp(7.5px,2.1vw,9px)`（scoped 生效）；矮屏 32px | ExpenseSheet:692-695、711-713 |
| D24 | 抽屉内 `g2`（分类格 + 日期格） | 两列并排 | 一列上下堆叠 | `.g2` app.css:758 |
| D25 | 弹窗（modal / picker） | `width:min(600px, 100vw-28px); max-height:88dvh`（`--wide` 880px）；`.picker-body` 132px rail + 3 列格 | `width:calc(100vw - 20px); max-height:92dvh`；`.modal-foot` 换行且按钮 `flex:1 1 auto`；`.picker-body` 94px rail + 2 列格 | app.css:592-610 / 774-775；views.css:781-782、910、933-934 |
| D26 | 轻提示 | `bottom:26px`，宽度受 `max-width:calc(100vw - 32px)` | `bottom:18px; width:max-content` | app.css:622-641 / 776 |
| D27 | 设置页签 | `.settings-tabs{gap:6px}` 不横滑；`.stab{padding:9px 14px; font-size:12.5px}` | `gap:4px; overflow-x:auto; scrollbar-width:none`；`.stab{padding:7px 10px; font-size:11.5px; flex:0 0 auto}` | views.css:461-473 / 875-877、932、935 |
| D28 | 设置分类管理 | `.cat-admin{220px + 1fr}`，`.cat-rail` 纵向列表 | 1 列；`.cat-rail{flex-direction:row !important; flex-wrap:wrap}`，`.cat-rail-btn{width:auto; white-space:nowrap}` | views.css:500、767-769、908-909 |
| D29 | 多列栅格坍缩总表 | — | `.g2/.g3/.g4 → minmax(0,1fr)`（app.css:758）；`.g4 → 2 列` 且 `.g-side → 1 列`（≤1080，app.css:717-718）；`.plan-grid → 1 列`、`.mover-grid → 1 列`、`.cal-year-grid → 3 列`、`.heat-grid → 6 列`、`.og-heat .heat-grid → 4 列`、`.picker-body → 94px`、`.picker-grid → 2 列`、`.theme-cards → 2 列`、`.theme-cards--3 → 1 列(≤720)` | 见各节 |
| D30 | 触感反馈 | `.key:active{scale(.96)}`、`.btn:active{translate(2px,2px)}`、`tr:hover` 背景、`.card`(cyber)`:hover` 发光 | 新增 `.m-row:active{transform:scale(.995)}`、`.mh-btn:active{scale(.98)}`；桌面专属 hover 位移在触摸设备无对应物 | views.css:216、1100；app.css:232-233、301 |
| D31 | 侧栏滚动 | 纵向不做横滑 | `overflow-x:auto; overflow-y:hidden`；`.nav::-webkit-scrollbar{display:none}` | app.css:732-734、739-740 |
| D32 | 记账抽屉次级信息 | 无（`month-spent`、`quick-cats` 恒在 DOM） | 移动端高度自适应：≤720 隐藏 `.preview-box`，≤620 隐藏 `.quick-cats` 与 `.month-spent` | ExpenseSheet:706-732 |

**仅在桌面出现的 CSS 定义（移动端不可见，但重建时若保留桌面需一并实现）**：`.tbl`、`.cat-cell`、`.row`、`.g-side`、`.hero`/`.hero-main`/`.hero-side`、`.alert-strip`/`.alert-pop`/`.due-row`、`.mini-metrics`、`.plan-grid`/`.plan-card`/`.plan-line`、`.todo-swipe`、`.ledger-sum`、`.insight`、`.dropzone`、`.swatches`/`.swatch`、`.compose-stack`/`.compose-stack-row`、`.cal-grid`/`.cal-day`、`.mh-plan`、`.og-progress`/`.og-todo`、`.report-banner`(两端都用)、`.annual-hero`。
其中 **全仓模板从未引用**（死代码，重建可忽略但不要误以为存在）：`.dropzone`、`.swatches`、`.swatch`、`.alert-strip`、`.alert-pop`、`.due-row`、`.hero-main`、`.hero-side`、`.mini-metrics`、`.plan-grid`、`.plan-card`、`.plan-line`、`.todo-swipe`、`.ledger-sum`、`.insight`、`.compose-stack`、`.compose-stack-row`、`.cal-day`、`.mh-plan`、`.og-progress`、`.og-todo`、`.annual-months`、`.superlative`、`.reminder-row`、`.swatches`、`.hero`(裸类)。

---

## E. 我（审计员）无法确定的地方

以下项要么 Web 端根本没有定义，要么依赖运行时/浏览器/设备计算，**不做推测**。重建时若需要确定值，须由产品/设计另行裁决。

| # | 项 | 为什么无法确定 | 涉及位置 |
|---|---|---|---|
| E1 | `--font-scale` 的用途 | 只在 `.app[data-theme="cyber"]` 里赋 `1`，candy 无该变量，全仓无任何规则 `calc(... * var(--font-scale))` | theme.css:144 |
| E2 | 移动端品牌图标实际尺寸 | 移动规则 `.logo-ph{width:32px;height:32px}` 作用于未渲染的原型占位块；实际渲染的是 `img.brand-mark[width=46][height=46]`，CSS 只有 `display:block;flex:0 0 auto;border-radius:12px`，无尺寸覆盖 → 46 还是被其他约束缩放无法从源码断言 | app.css:737、views.css:1116、BrandMark.vue、App.vue:172 |
| E3 | 报表/构成环图移动端直径 | CSS 写 150 / 148 / 136px，但 `PDonut` 用内联 `style="width:{size}px;height:{size}px"`（默认 176）压制样式表 → 实际 176px；三条 CSS 声明永不生效。"设计意图到底是 136 还是 176" 无法从代码判断 | views.css:783、886、1146；PDonut.vue:46-47 |
| E4 | `color-mix()` 的具体色值 | `.cat-ic` 底/边（12%/45%）、`.heat-dot`（18–100% 动态）、`.quick-cat.is-on` 光圈 20%、`.plan-ticks.is-done` 辉光 60%、`.todo-swipe-bg`（12%/45%）、`.rw-behind`（14%）、`.chip`/`.card` 系列 rgba 混合结果 → 依赖浏览器 color-mix 与底色，无法给出固定 RGB | 各组件 |
| E5 | `dvh` / `vw` / `env(safe-area-inset-bottom)` 的实际像素 | `.sheet{height:93dvh}`、`.sheet-body{max-height:calc(93dvh - 124px)}`、键盘 `clamp(...dvh)`、`env(safe-area-inset-bottom)` 都随设备视口与安全区变化；**`124px` 这个常数没有任何推导注释**，与 `.sheet-head`（12+12+内容）和 `.sheet-foot`（12+12+safe-area）实测高度不一定相等 | app.css:768、views.css:920、ExpenseSheet:688-702 |
| E6 | `.build-stamp` 文本 | 内容来自构建期注入的 `__BUILD_STAMP__`（vite define），运行前不可知 | App.vue:32、SettingsView:57、index.html |
| E7 | 设置页 `<POrb>` 是否渲染 | 模板使用 `<POrb>`，但 `SettingsView.vue:47` 的 import 列表没有 `POrb` → Vue 会告警 "Failed to resolve component" 并渲染为空；是否被其他全局注册兜住无法从源码确认 | SettingsView.vue:47、821、880 |
| E8 | 触摸设备上 `:hover` 是否触发 | 全站大量 `:hover`（`.btn` 位移、cyber `.card` 发光、`.chip:hover`、`.m-row` 无 hover）未见 `@media (hover: hover)` 守卫；移动 WebView 的 sticky-hover 行为由浏览器决定 | app.css / views.css 各处 |
| E9 | 超长文本折行 | 除已声明的 `white-space:nowrap + text-overflow:ellipsis` 之外，全站没有 `overflow-wrap` / `word-break` 规则；中文长串在窄屏的断行位置不可静态推断（如 `.mh-plan-txt b`、`.cat-name`、`.picker-rail-btn`、`.set-t`） | theme.css 无全局规则 |
| E10 | 半像素/缩放下的断点归属 | 断点成对写在 `max-width:860px` 与 `min-width:861px`，`860 < w < 861`（缩放或小数 dpr）时落到哪一侧取决于浏览器取整 | app.css:721、780；views.css:1007 |
| E11 | `.sidebar`（移动 sticky, z-index 60）与 `.topbar`（sticky, z-index 30）滚动时的重叠关系 | 两者分属 `.shell` 子元素与 `.main` 子元素，层级由各自 z-index 决定但滚动容器是文档本身；不同浏览器下 sticky 边界表现不同，代码里没有注释或约束 | app.css:723、170 |
| E12 | `.more-menu-pop` 在窄屏是否溢出 | `position:absolute; right:0; top:calc(100% + 4px); min-width:120px`，无 `max-width`/`max-height`，靠右但父级可能贴近屏幕左缘（如待办行）→ 是否会超出视口无约束 | base.css:195-208 |
| E13 | 报表构成卡 chips 横滑的可发现性 | `.chips{overflow-x:auto; scrollbar-width:none}` 隐藏滚动条，是否另有渐隐遮罩/指示箭头：代码中无 | views.css:1129-1138 |
| E14 | `.picker-rail-btn` 长文案 | 无 `overflow:hidden`/`ellipsis`，94px 宽 rail 内长分类名的表现未定义 | views.css:569-578、910 |
| E15 | 移动端 icon-btn 尺寸 | 移动端无覆盖（保持 38×38）；views.css 的 `34×34` 只作用于未使用的 `.plan-line-acts .icon-btn`。设置/待办行里密集排列的 3–4 个 38px 图标按钮在 360px 宽的换行策略未定义 | app.css:272-282；views.css:896 |
| E16 | 主题卡在 721–860px 的列数感受 | `.theme-cards--3` 只在 `≤720px` 变单列，`721–860px` 仍是 3 列（每列约 100–170px），是否可读未定义 | views.css:814-815 |
| E17 | 桌面遗留的 `--density` 分支 | `.app` 固定 `data-density="cozy"`，CSS 只有 `compact` 分支（14/8），`cozy` 无规则 → 实际用 `:root` 的 18/12；"cozy 是否本应有别的值" 未知 | theme.css:8-9、242；App.vue:162 |
| E18 | 登录页移动端形态 | `LoginView.vue` 的 `<style scoped>` 里**没有任何 `@media`**，全页只有 `max-width:420px` + `padding:24px 16px`；移动端键盘弹起时的可视区适配、是否需要抽屉化都未定义 | LoginView.vue:193-244 |
| E19 | cyber 扫描线（`::after`，z-index 999）的可感知强度 | 覆盖在所有层之上（含 toast 120、picker 96），`pointer-events:none`；`rgba(255,255,255,.028)` 在 4px 周期内的摩尔纹在不同 DPR/亮度屏上的观感无法静态确定 | theme.css:225-238 |
| E20 | 页面切换动画在移动端的性能表现 | `.page-enter-active{opacity 200ms + transform 200ms}`，`.page-leave-active{120ms}`；`prefers-reduced-motion` 有全局降级（0.001ms），但默认移动端是否会掉帧不可静态判定 | base.css:22-34；theme.css:244-250 |
| E21 | 主数字/金额的 `font-variant-numeric` 实际字形 | 声明 `tabular-nums`，实际等宽数字来自所选字体（Outfit / Orbitron / JetBrains）；字形宽度由字体文件决定 | app.css:470、555；views.css:164、629 |

---

## 附：本清单的统计口径

- **屏（7）**：C.1 外壳 · C.2 流水 · C.3 概况 · C.4 报表 · C.5 年度报告 · C.6 设置 · C.7 登录/初始化；另含 **1 个动作层**：C.8 记账抽屉（内嵌 分类选择器 / 支付方式选择器 / 账单导入抽屉）。
- **组件（B 节 32 小节）**：B.0 基线 1 · B.1–B.4 外壳 4（shell/sidebar/topbar/content） · B.5–B.24 原子组件 20（btn、icon-btn、card、card-h、orb、seg、chip、field+input、switch、stat、tag、tbl、row、scrim+sheet+modal、toast、empty、bar、donut、布局工具类、pull-hint/pull-bar） · B.25–B.30 业务组件 6（PCatIcon、PPayIcon、CompositionCard、ReminderRow、BrandMark、ColorPicker+IconPicker+PayIconPicker） · B.31 base.css 补丁 1。其中模板实际渲染的 Vue 组件 23 个：PBar、PBtn、PCard、PChip、PDonut、PEmpty、PField、PIconBtn、PInput、POrb、PSeg、PStat、PSheet、PSwitch、PToast、PTag、PCatIcon、PPayIcon、CompositionCard、BrandMark、ColorPicker、IconPicker、PayIconPicker（ReminderRow 有定义但未被任何页面引用）。
- **E 节条目：21 条。**
