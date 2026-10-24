# 覆盖核验：`hw-ui-spec.md` vs `web-ui-inventory.md`

> 核验对象
> - 事实源：`docs/design/audit/web-ui-inventory.md`（1172 行，A/B/C/D/E 五节）
> - 被核验：`docs/design/hw-ui-spec.md`（196 行，§0–§7）
> - 只比对，未修改任何文件。
>
> **"覆盖"判定标准（本次核验唯一口径）**：规范里给出了**具体数值或可照做的结构描述**，实现者按规范就能 1:1 做出来。
> - 只写"照 Web / 照审计 / 见 B 节"→ **不算覆盖**。
> - 有描述但**数值取自被覆盖的旧值**→ 记为 **未覆盖（值错）**，同时进 §三。
> - 审计里明确标注"桌面专用 / 死代码 / 已裁决后置"的条目 → 记 **n/a**，不计入分母。

---

## 一、覆盖率

### 1.1 汇总

| 审计节 | 条目数 | 适用 | 规范已覆盖 | 覆盖率（覆盖/适用） | 未覆盖编号 |
|---|---|---|---|---|---|
| A 令牌（A.1–A.6） | 60 | 60 | 25 | **41.7%** | 见 1.2 |
| B 组件（B.0–B.31，32 小节） | 32 | 28 | 8 | **28.6%** | 见 1.3 |
| C 屏（C.1–C.8，7 屏 + 1 动作层） | 8 | 7 | 1 | **14.3%** | 见 1.4 |
| D 移动差异（D1–D32） | 32 | 31 | 15 | **48.4%** | 见 1.5 |
| E 未定项（E1–E21） | 21 | 21 | 3 | **14.3%** | 见 1.6 |
| **合计** | **153** | **147** | **52** | **35.4%** | — |

结论先行：**规范只覆盖了约三分之一的审计事实**，且已覆盖部分里还有 31 处取值与审计相反（见 §三）。多个"像不像 Web"的关键面（颜色令牌、背景装饰、卡片圆角、分类图标、分类/支付选择器、记账键盘、设置分类管理、报表构成卡子结构）**完全没有可执行数值**。

### 1.2 A 节未覆盖清单（35 / 60）

| 编号 | 条目 | 状态 |
|---|---|---|
| A.1 `--r-sm` | 审计 `9px`，规范 §1.4 写 `10` | 值错 |
| A.1 `--font-scale` | 审计标为 E1 未定；规范未声明"不实现" | 缺（次要） |
| A.2 `surface-3` | `#F1F5F9`/`#16162a`，规范 `#EFEDFF`/`#242438` | 值错 |
| A.2 `ink` | cyber `#e0e0e0`，规范 `#d7ffe9` | 值错 |
| A.2 `ink-2` | `#64748B`/`#8f93ad`，规范 `#475569`/`#8fd9b8` | 值错 |
| A.2 `ink-3` | cyber `#6b7280`，规范 `#4e8f78` | 值错 |
| A.2 `danger` | `#EF4444`，规范 `#F43F5E` | 值错 |
| A.2 `accent-ink` | cyber `#04220f`，规范 `#04170d` | 值错（次要） |
| A.2 `cyan` `pink` `amber` `mint` `sky` `on-color` | 全部缺失（且都在用：pink=还款柱/横幅渐变、amber=chip is-on、mint/sky=orb 底色、on-color=彩底文字） | 缺 |
| A.2 `nav-bg` `scrim` `glow` | 全部缺失（nav-bg=顶栏底、scrim=抽屉/选择器遮罩） | 缺 |
| A.2 `chart-1..8` | 规范只写"按色号索引"，**8 个十六进制值一个没给** | 缺 |
| A.3 字体回退链/文件 | 只给族名，未给 audit A.3 的实际生效链与 5 个字体文件、Orbitron 700/800 两档字重 | 部分 |
| A.4 `--shadow-card-pop` | `8px 8px 0 #1E293B` 未给 | 缺 |
| A.4 `--shadow-btn-hover` / `-active` | `5px 5px 0` / `1px 1px 0` 未给 | 缺 |
| A.4 硬编码阴影组 | `.mobile-hero 4px 4px 0`、`.report-banner 5px 5px 0`、`.toast 4px 4px 0 rgba(0,0,0,.18)`、`.picker-cell/.pay-item 2px`、`.theme-card 3px`、`.heat-cell.is-now 2px`、`modal/sheet/picker` cyber 光晕 —— 全缺 | 缺 |
| A.4 `.orb` 阴影 | `2px 2px 0 var(--line-2)` 未给 | 缺 |
| A.5 卡片切角 | cyber `.card/.modal/.sheet` 为 **14px**，规范写 7px 且声明"按钮/卡片"共用 | 值错 |
| A.5 `.orb` 6px / `.logo-ph` 8px / `.tp-cyber` 8px 切角 | 全缺 | 缺 |
| A.5 `.ic` 描边 | `2.4` → cyber `1.6` 未提 | 缺 |
| A.6 `.app::before` | candy 点阵（24px 网格 / rgba(139,92,246,.13) / mask 70% 10%）与 cyber 电路网格（52px / 4 层 / mask）全缺 | 缺 |
| A.6 `.app::after` | cyber 扫描线（z-index 999、4px 周期）全缺 | 缺 |
| A.6 `.deco-a~d` | 4 个几何贴纸（260 圆 / 150 异形 / 60 三角 / 120×14 胶囊，含 top/right/bottom/left/rotate/opacity）全缺 | 缺 |
| A.6 `data-decor` 关闭开关 | 未提 | 缺（次要） |

### 1.3 B 节未覆盖清单（20 / 28 适用小节）

| 小节 | 组件 | 状态 | 主要缺口 |
|---|---|---|---|
| B.0 | 全局元素基线 | ✗ | `::placeholder` ink-3、`:focus-visible 2px accent`、`.ic stroke-width 2.4/1.6` |
| B.1 | `.shell` 栅格 | ✓ | — |
| B.2 | 侧栏/品牌/导航 | ✓（次要缺口） | `backdrop-filter:blur(10px)`、`z-index:60`、`overflow-x:auto` |
| B.3 | `.topbar` | ✓（次要缺口） | `background:var(--nav-bg)` + `blur(14px)` |
| B.4 | `.content` | ✓ | — |
| B.5 | `.btn` | ✗ | `--pink`、`--icon`(38×38)、`[disabled]`、hover/active 位移与阴影 |
| B.6 | `.icon-btn` | ✓（次要） | `color:ink-2`、hover |
| B.7 | `.card` | ✗ | 移动端 `radius:16`、`padding:14` 写成"部分卡 14" |
| B.8 | `.card-h/-t/-cap` | ✓（次要） | `card-h--tight 6`、cyber 变体 |
| B.9 | `.orb` | ✗ | 34≠36、`border:2 line-2`、`2px 2px 0`、cyber 全套 |
| B.10 | `.seg` | ✗ | `padding:3`≠4、`.seg-btn 6 13 / 12/700`、cyber `gap:0`+分隔线 |
| B.11 | `.chip` | ✗ | `5 10`≠`5 11`、`.chip-dot 7×7`、`.chips gap:7` |
| B.12 | `.field/.input` | ✗ | `.field-l`、`.search-wrap` |
| B.13 | `.switch` | ✓（次要） | knob 16×16/translateX 18、cyber |
| B.14 | `.stat` + 工具类 | ✗ | 21/700≠20/800、`stat-l 10.5` 非 mono、`.mono/.num/.pos/.neg/.muted/.tiny/.hint` |
| B.15 | `.tag` | ✗ | 10/600≠9.5/700、`border:1 line`、`bg:surface-2` |
| B.16 | `.tbl` | n/a 桌面专用 | — |
| B.17 | `.row` | n/a 桌面 | — |
| B.18 | scrim/sheet/modal | ✗ | scrim 色+blur2、head/title/body/foot 全尺寸、`max-height:calc(93dvh-124px)`、safe-area、modal 移动宽高、动画 |
| B.19 | `.toast` | ✗ | `bottom:18`、`border:2 line-2`、`4px 4px 0` 阴影、`10 16`≠`10 18`、toastIn |
| B.20 | `.empty` | ✓ | — |
| B.21 | `.bar` | ✗ | `height:9 / radius:999 / border:1 line / fill accent` 整条缺 |
| B.22 | `.donut` | ✗ | `stroke-width:16`≠12、`r=size/2-12`、段间 2.5、`rotate(-90)`、中心 9.5/21 |
| B.23 | 布局工具类 | ✗ | `.g2/.g3/.g4 → 1 列`、`.stack gap:16 不随断点`、`.split/.toolbar .stack--sm` |
| B.24 | `.pull-hint/.pull-bar` | ✗ | `.pull-bar` 视觉（实时高度/accent/11/700/transition） |
| B.25 | `PCatIcon .cat-ic` | ✗ | 30×30 / radius 9 / color-mix 12%+45% / 7 处调用尺寸 —— 整条缺 |
| B.26 | `PPayIcon` | ✗ | 尺寸链 14/15/16/18 |
| B.27 | `CompositionCard` | n/a 流水桌面专用（`stack-bar`/legend 见 B.31） | — |
| B.28 | `ReminderRow` | n/a 死代码 | — |
| B.29 | `BrandMark` | ✗ | 登录 56 / 关于 68、图源按主题 `/mark-light.svg`｜`/logo.svg` |
| B.30 | ColorPicker/IconPicker/PayIconPicker | ✗ | 三个子组件全部规格（cp-cell 26×26 r8、ip-scroll 240、ip-grid 38、pip min 84） |
| B.31 | base.css 补丁 | ✗ | `.plan-ticks i{height:4;radius:2}` 数值、`.more-menu` 结构与尺寸、路由过渡 200ms+6px/120ms |

### 1.4 C 节未覆盖清单（6 / 7 适用屏）

| 屏 | 状态 | 主要缺口 |
|---|---|---|
| C.1 外壳 | ✓（2 处次要：z-index 栈、路由过渡） | — |
| C.2 流水 | ✗ | `mobile-hero` 容器外观（padding 14 / 2px line-2 / r20 / 4px 硬阴影 / gap 12 / cyber 变体）、`.m-list gap:8`、`.date-cap padding:12 4 6`、`.mh-facts padding:9 0`、`lt-adv` 内 `.seg{flex:1 1 100%}`+`.seg-btn{flex:1 1 0}`、`.period-label{min-width:76;14/700}`、`.m-row`/hero 的 cyber 变体、明细卡 `card-h` 文案；且"全部档 2 列"错 |
| C.3 概况 | ✗ | `.og-heat .heat-grid` 移动 = **4 列**（规范只说"12 格"）、`.heat-cell{padding:7 3 6;radius:7}` + `.heat-dot h4`、`.kv{padding:8 0;12px}`、`.og-card-foot` |
| C.4 报表 | ✗ | seg 档位少"全部"；`.report-head{padding:14}`、`.rf-num 26`、`.rf-i 10.5`、`report-facts gap:10`；构成卡 chips 横滑 / `compose-list` 四列 / `dim-bar 62-1fr-76`+`db-track h10` / `week-bars 7 列 h112`；**`report-banner` 整块缺**；涨跌榜与还款节奏结构与审计相反（见 §三） |
| C.5 年度报告 | n/a 已裁决后置（§0 C17） | 但 §4.3 仍引用"年度报告"入口，未说明横幅是否实现 |
| C.6 设置 | ✗ | `.stab` 移动值（7 10 / 11.5 / gap 4 / 横滑）；分类管理移动形态（1 列 + rail 横排 wrap）与 `cat-rail-btn/cat-kid` 数值；主题卡三档列数 + `.theme-prev h56`；`.danger-zone`、`.about-card`、快照/数据总览/检查更新卡；**账单导入抽屉 `import-row/import-list` 全缺**；5 个表单抽屉字段清单缺 |
| C.7 登录 | ✗ | `max-width:420` 卡、`login-card` 结构、brand 56、`login-form gap:12`、主按钮 100% 宽、**disabled 判定（用户名非空 && 口令≥8 && !busy）**、`处理中…`、`login-foot`、`login-server` 面板 |
| C.8 记账抽屉 | ✗ | 分类选择器 `.picker`（min(660,100vw-20) / 86dvh / 94px rail / 2 列格 / cell 9px r10）、支付选择器 `.pay-item`、`.amt-display`(10 12 + 2px dashed)/`.a-cur 20`、`.preview-box`、`.month-spent`、`.quick-cats/.quick-cat`、退款/分期 set-row（select 84）、`.pay-key/paycol` 尺寸、矮屏三档条件与数值；且金额 38px、键盘 62/46/18px 均取错（见 §三） |

### 1.5 D 节未覆盖清单（16 / 31 适用）

- **完全覆盖（15）**：D1 D2 D4 D5 D6 D7 D8 D9 D11 D12 D13 D14 D19 D21 D24
- **部分覆盖（6）**：D3（缺 blur/z/overflow）、D10（缺 radius 16）、D15（缺 seg 拉满整行）、D16（缺 chips 横滑与图例四列）、D17（缺 26px/14px padding）、D22（键盘几何值为旧值，矮屏档无值）
- **未覆盖（10）**：**D20**（抽屉内距 head 12 14 / title 15 / body 12 + max-height）、**D23**（pay-key clamp 尺寸）、**D25**（modal `100vw-20`/92dvh、foot 换行、picker 94/2 列）、**D26**（toast bottom 18 / width max-content）、**D27**（stab gap 4 / 7 10 / 11.5 / 横滑）、**D28**（cat-admin 1 列 + rail 横排）、**D29**（栅格坍缩总表：theme-cards 3/2/1、heat-grid 4/6、mover 1、plan-grid 1、cal-year-grid 3、picker 94/2）、**D30**（触摸反馈 active 缩放）、**D31**（sidebar 横滑 + 滚动条隐藏）、**D32**（≤720/≤620 遮蔽 preview-box/quick-cats/month-spent）
- **n/a（1）**：D18（年度报告后置）

### 1.6 E 节未覆盖清单（18 / 21）

- **已裁决覆盖（3）**：E2（品牌图标 = 46，§3 已定）、E3（环图 = 176，§2 已定）、E17（density 用 18/12，§1.1 已定）
- **部分（1）**：E6（build-stamp 只写"含 离线模式/待同步 N"，未给拼接格式与 `{BUILD_STAMP}` 位置）
- **未处理（17）**：E1 E4 E5 E7 E8 E9 E10 E11 E12 E13 E14 E15 E16 E18 E19 E20 E21
- **其中必须先裁决的 4 条**：**E4**（color-mix 结果色，ArkUI 无此函数）、**E5**（93dvh / `calc(93dvh-124px)` / clamp(...dvh) / safe-area → vp 的映射）、**E18**（登录页移动态）、**E9**（长文本折行/省略规则）

---

## 二、缺漏项（必须补的）

> 只列影响"像不像 Web"的缺漏；纯装饰/观感强度类标次要。

| 审计位置（小节/选择器/行号） | 事实 | 规范缺什么 | 严重度 |
|---|---|---|---|
| A.2（theme.css:32–145 全表） | 实际使用但规范未定义：`--pink #F472B6/#ff00ff`（`.repay-col i`、`.report-banner` 渐变末端）、`--amber #FBBF24/#ffb020`（`.chip.is-on` 底、`.mh-plan-ic`）、`--on-color #1E293B/#05050c`（彩底文字）、`--mint #34D399`、`--sky #38BDF8`（orb 底色）、`--cyan #22D3EE` | §1.2 无这 6 个令牌 | 阻断 |
| A.2 `--nav-bg` / `--scrim` | 顶栏底 `rgba(255,253,245,.9)`/`rgba(8,8,14,.92)`；遮罩 `rgba(30,41,59,.35)`/`rgba(2,2,8,.78)` | 无（顶栏与所有抽屉遮罩都取不到色） | 阻断 |
| A.2 `--chart-1..8` | 8 组十六进制（candy `#8B5CF6 #F472B6 #FBBF24 #34D399 #38BDF8 #A78BFA #FB7185 #22D3EE`；cyber 8 值） | §1.2 只写"按色号索引" | 阻断 |
| A.6 `.app::before`/`::after`/`.deco-a~d`（theme.css 装饰层；views/app.css 无覆盖） | candy 点阵 24px + mask；cyber 电路网格 52px 四层 + 全屏扫描线（z 999）；candy 四个几何贴纸（260 圆 / 150 异形圆角 / 60px 三角 / 120×14 胶囊，含坐标、旋转、opacity） | §1/§3 完全未提"背景装饰层" | 阻断 |
| A.5 `.app[data-theme="cyber"] .card/.modal/.sheet`（theme.css:148-152） | `clip-path` **14px** 切角 | §1.4 只给 7px 并写明"按钮/卡片"共用 → cyber 卡片会切错 | 阻断 |
| A.5 `.app[data-theme="cyber"] .orb` / `.logo-ph` / `.tp-cyber` | orb 6px、logo 8px、主题缩略 8px 切角 | 无 | 阻断（cyber 主题可见） |
| B.7（app.css:759-760；D10） | 移动 `.card{padding:14; border-radius:16; box-shadow:3px 3px 0 #E9EEF6}`；cyber `radius:0; shadow:none`；`.card--pop` 的 8px 阴影被压掉 | §2 写 `padding:18（移动端部分卡 14）`：既未给移动端 **radius 16**，也未说明"全部卡都是 14" | 阻断 |
| B.25 `PCatIcon .cat-ic`（views.css 各处 + PCatIcon.vue） | `30×30; radius:9; border:1 transparent`；内联 `color:var(--chart-N)` + `background:color-mix(c 12%)` + `borderColor:color-mix(c 45%)`；调用尺寸：移动行卡 34 / 表格 30 / 选择器 20 / 设置 rail 18 / kid 26 / 支出格 28 / 快捷 16 | §2 无此组件；分类图标是流水行卡、分类管理、选择器的主识别物 | 阻断 |
| C.8 分类选择器 `.picker/.picker-body/.picker-grid/.picker-cell`（views.css:549-597、781-782、910） | 宽 `min(660px,100vw-20)`、`max-height:86dvh`、body `94px + 1fr`（min-height 300）、grid **2 列** padding 12 gap 7、cell `padding:9; border:2; radius:10; 11.5/600`、is-on `2px 2px 0 line-2` | §4.6 只提"三行字段"，选择器结构与数值 0 | 阻断 |
| C.8 支付选择器 `.pay-list/.pay-item`（views.css:600-612） | `width:min(440px,100vw-20)`、`pay-item padding:10 12; border:2; radius:rMd`、is-on `2px 2px 0` | 同上，0 | 阻断 |
| C.2 `.mobile-hero`（views.css:1012-1029） | `padding:14; border:2 solid line-2; radius:20; shadow:4px 4px 0 line-2; gap:12`；cyber `border-width:1; radius:0; border-color:rgba(0,255,136,.45); 渐变 180deg 62%; glow 0 0 30px -16px` | §4.1 只给 hero **内部**元素，容器外观与 cyber 变体全缺 → 移动端最显眼的卡做不出来 | 阻断 |
| C.6 `.cat-admin` / `.cat-rail` / `.cat-rail-btn` / `.cat-kid`（views.css:908-909、500-529、769） | 移动 `cat-admin → 1 列`；`cat-rail{flex-direction:row !important; flex-wrap:wrap; gap:4}`；`cat-rail-btn{padding:7 9; radius:9; border:2; 12/600; width:auto; nowrap}`；`cat-kid{padding:8 10; border:1; radius:10}` | §4.4 写"分类管理**左导轨** + 右侧子类列表"（桌面形态），且无任何数值 → 与移动端实际相反 | 阻断 |
| C.8 `.keypad` / `.keys` / `.key` / `.pay-key`（views.css:655-697、899-903 + ExpenseSheet:683-732） | 键盘 `grid-template-columns:54px minmax(0,1fr)`；`key min-height:clamp(38px,6.1dvh,54px); font-size:clamp(15px,4.3vw,19px); radius:clamp(8px,2.4vw,12px)`；`pay-key min-height:clamp(34px,5.4dvh,48px); font-size:clamp(7.5px,2.1vw,9px)` | §4.6 写左列 62、键 `min-h 46 / 18px / radius 11`（均是被 scoped 覆盖的旧值），pay-key 尺寸 0 | 阻断 |
| C.4 报表构成卡子结构（views.css:1119-1157 + ReportView:377-411） | `compose-list` 行 grid `9px minmax(0,1fr) 64px 32px` + 虚线分隔；`dim-bar` grid `62px 1fr 76px`、`db-track h10 r99`；`week-bars` 7 列 `h112`、柱 `radius 6 6 2 2`；图例 `i 9×9 r3` | §4.3 只有"4 段维度切换 + 176 环图 + 图例列"三个词 | 阻断 |
| C.4 涨跌榜 / 还款节奏结构（views.css:307-325、780；C.4 DOM） | 涨跌行 = `.mover` **flex 行**（cat-ic 30 + 文本 + 右金额/环比），**无 192px 名称列、无中间占比条**；还款节奏 = `.repay-steps` 6 根**竖柱**（i 宽 100%、pink、`radius 5 5 0 0`、容器 h96） | §4.3 写"名称列固定宽 192、中间占比条"与"还款节奏卡（中间占比条）"→ 两处结构被换成审计里没有的形态 | 阻断 |
| C.4 构成卡 chips（views.css:1127-1138） | `.card-cap{display:none}`；`.chips{width:100%; margin-left:0!important; flex-wrap:nowrap; overflow-x:auto}`；`.chip{flex:0 0 auto}` —— 移动端四维切换是**全宽横滑药丸条** | §4.3 未描述，默认会做成换行胶囊组 | 重要 |
| A.4 `--shadow-btn-hover/-active`、`--shadow-card-pop` | `5px 5px 0 #1E293B` / `1px 1px 0 #1E293B` / `8px 8px 0 #1E293B` | §1.4 只给各自基态 | 重要 |
| A.4 其他硬编码阴影 | `.toast 4px 4px 0 rgba(0,0,0,.18)`、`.report-banner 5px 5px 0`、`.picker-cell/.pay-item 2px`、`.theme-card 3px`、`.heat-cell.is-now 2px`、`.orb 2px`、`.modal 0 30px 70px -30px`、sheet/picker cyber 光晕 | 全缺 | 重要 |
| B.0（theme.css:12–29） | `.ic{stroke-width:2.4}`（cyber 1.6）；`::placeholder{color:ink-3}`；`:focus-visible{outline:2px solid accent; offset:2px}` | §2 无全局基线条目 → 图标线宽、占位符色、聚焦环三处会走系统默认 | 重要 |
| B.5 `.btn--pink` / `.btn--icon` / `[disabled]` / hover·active（app.css 按钮块） | pink 变体色值；icon 变体 `width:38; padding:0`；disabled `opacity:.45; transform:none!important`；hover `translate(-2,-2)+5px`；active `translate(2,2)+1px` | §2 Btn 只给 primary/ghost/sm/danger + cyber | 重要 |
| B.10 `.seg-btn`（app.css 分段控件） | `padding:6 13; border:2 transparent; 12/700`；cyber `gap:0` + `border-right:1px line` + `is-on inset 辉光` | §2 Seg 只有外框（且 padding 写 3） | 重要 |
| B.11 `.chip` / `.chips`（app.css） | `padding:5 11`；`.chip-dot{7×7}`；`.chips{display:flex; flex-wrap:wrap; gap:7}` | §2 无 chip-dot、无容器间距、padding 差 1px | 重要 |
| B.12 `.field-l` / `.search-wrap` | `field-l` mono 9.5 / ls .14em / uppercase / ink-3；`search-wrap{flex:1 1 180px; min-width:140px}` + 图标 `left:11; top:50%` | 无 | 重要 |
| B.14 `.stat` + 工具类 | `stat-v 21px/700`、`stat-l 10.5px ink-3 ls .04em`（非 mono）、`stat-sub 10 mono`；`.mono/.num/.pos/.neg/.muted/.tiny/.hint` | §2 取值 20/800 与 mono 9（错），工具类全缺（`.pos/.neg/.tiny/.hint` 在多个屏复用） | 重要 |
| B.15 `.tag` | `padding:2 8; border:1 solid line; bg:surface-2; 10/600; mono; ink-2`；tone：dash/accent/warn/danger | §2 写 9.5/700，缺 border/bg/色 | 重要 |
| B.18 `.scrim` / `.sheet-*` / `.modal-*`（app.css:762-775 + views.css:904-934） | scrim `bg:scrim + blur(2px) + fadeIn .18s`；sheet `border-top:2 line-2`、head `12 14`、title 15、body `12 + gap10 + max-height:calc(93dvh-124px)`、foot `padding-bottom:calc(12px+safe-area)`；modal `calc(100vw-20) / max-h 92dvh`、foot `wrap` + `btn flex:1 1 auto` | §2 Sheet 只有 93dvh/radius22/drag-bar；modal 移动尺寸、scrim、内距、safe-area 全缺 | 重要 |
| B.19 `.toast` | `bottom:18; width:max-content; border:2 line-2; padding:10 16; 12/600; shadow 4px 4px 0 rgba(0,0,0,.18)`；`toastIn` 14px 上移 | §2 只有底色/圆角/`10 18` | 重要 |
| B.21 `.bar` | `height:9; radius:999; border:1 line; bg:surface-3`；fill `accent` + `transition:width .5s`；调用处内联 `height:5; margin-top:2` | §2 无 Bar 条目（只有年档一句"5px 进度条"） | 重要 |
| B.22 `.donut` / PDonut.vue | `stroke-width:16`；`r=size/2-12`；段间空隙 2.5；`rotate(-90 cx cy)`；中心 `9.5 mono / 21 display 800`；默认 176 | §2 写"环宽 12"（12 实为半径内缩量）→ 环会变细；几何公式全缺 | 重要 |
| B.23 布局工具类 | `.g2/.g3/.g4 → minmax(0,1fr)`（≤860）；`.stack{gap:16}` **不随断点**；`.stack--sm 10`；`.split/.toolbar gap:10` | §4 只给 content gap 12；**卡片之间仍是 16** 没有落笔，实现会统一用 12 | 重要 |
| B.24 `.pull-bar` | `height:{pull}px` 实时、`accent`、11/700、`transition:height .15s`、文案「下拉记一笔 / 松开记一笔」 | §5 只要求"文案逐字照 Web"，视觉 0 | 重要 |
| B.26 `PPayIcon` 调用尺寸 | 表格 14 / 行卡 14 / 支出抽屉 18、15、16 | 无 | 重要 |
| B.29 `BrandMark` | 登录 56、关于 68；图源 candy `/mark-light.svg`、cyber `/logo.svg`；`radius:12` | §3 只覆盖侧栏 46 | 重要 |
| B.30 ColorPicker / IconPicker / PayIconPicker | `cp-cell 26×26 r8 border2`、`cp-auto 4 10 r999`；`ip-scroll max-h 240`、`ip-grid minmax(38px,1fr) gap6`、`ip-cell` 选中 2px 光圈；`pay-icon-picker minmax(84px,1fr)`、`pip-cell 7 8` | 三个子组件 0 描述（分类/支付方式表单的核心控件） | 重要 |
| B.31 `.plan-ticks` / `.more-menu` / 路由过渡 | `i{height:4; radius:2}`、is-done `accent`；`summary{padding:3 8; r-sm; 11 mono}`、`pop{min-width:120; padding:4}` + 按钮 `6 8 / 11.5`；`page-enter 200ms + translateY(6)` / `leave 120ms` | §4.4 只写"12 段刻度"；more-menu 只有一处"更多菜单里忽略本期"；过渡未提 | 重要 |
| C.2 `.m-list` / `.date-cap` / `.mh-facts` / `.lt-adv .seg` / `.period-label` | `m-list{gap:8}`；`date-cap{padding:12 4 6}`；`mh-facts{padding:9 0}`；`lt-adv .seg{flex:1 1 100%}`、`.seg-btn{flex:1 1 0}`；`period-label{min-width:76; 14/700}` | §4.1 缺这些间距与"展开后分段拉满整行" | 重要 |
| C.2 全部档（views.css:777 `cal-year-grid` = 3 列） | 全部档复用 `.cal-year-grid`，移动 **3 列** | §4.1 写"2 列一年一格" | 重要 |
| C.3 热力卡（views.css:994-995、130-149） | `.og-heat .heat-grid{repeat(4,minmax(0,1fr))}`；`.heat-cell{padding:7 3 6; border:1; radius:7; gap:3}`；`.heat-dot{w100% h4 r999}`；`.heat-m mono 9`/`.heat-v mono 10 700` | §4.2 只写"12 格 heat-grid" → 列数不明（会做成 6 列或 3 列） | 重要 |
| C.3 累计卡（`.kv`） | `padding:8 0; border-bottom:1px dashed; 12px`；`b{mono 600}` | §4.2 只写"5 行 kv" | 重要 |
| C.4 报表页头（views.css:879-883、820-824） | `.report-head{padding:14}`；`.rf-num 26px`（覆盖 30）；`.rf-i 10.5`；`.report-facts{gap:10 !important}`；`.rf-items{padding-bottom:0}`；`.rf-main` 标 `期间支出` | §4.3 只写"三事实" | 重要 |
| C.4 `.report-banner`（views.css:338-355） | 全宽渐变卡：`linear-gradient(100deg, accent, #A78BFA 65%, pink)`、`padding:16 18`、`border:2 line-2`、`radius:rCard`、`shadow:5px 5px 0`、`rb-t 16/800`、`rb-s 11 opacity .9`、ChevronRight 18 | §4.3 未提该卡（报表页底部最显眼的入口） | 重要 |
| C.6 `.settings-tabs` / `.stab`（views.css:461-475、875-877、932、935） | 移动 `gap:4; overflow-x:auto; scrollbar-width:none`；`stab{padding:7 10; font-size:11.5; border-bottom:3 transparent; flex:0 0 auto}` | §4.4 用桌面值 `padding:9 14 / 12.5`，缺横滑与 gap 4 | 重要 |
| C.6 数据区（views.css:734-763、814-815） | `.theme-cards--3` 3 列（≤720 变 1 列）；`.theme-card{padding:10; border:2; radius:rMd; is-on 3px3px0}`；`.theme-prev{height:56; radius:8}` + `tp-candy/tp-cyber/tp-system`；`.danger-zone{border:2 dashed danger; radius:rMd; padding:14}`；`.about-card{padding:26 18}`、`about-name 22/800`；快照/数据总览/检查更新卡结构 | §4.4 一句"数据区主题三卡/导出/导入/备份/快照/关于/危险区" | 重要 |
| C.8 账单导入抽屉（BillImportModal:258-267、C.8 DOM） | 移动 `.import-row{grid-template-columns:18px minmax(0,1fr) auto; row-gap:4}`；`.import-list{max-height:46vh}`；行内有 cat/pay 两个 select + 金额 + tag | 规范 0 描述 | 重要 |
| C.6 五个 PSheet 表单抽屉 | 分类表单 / 支付方式表单 / 合并 / 计划表单 / 成员表单（sheet-head 标题 + 若干 field + foot 保存·取消） | §4.4 未提，字段清单无 | 重要 |
| C.7 登录页（LoginView.vue:193-244 + C.7） | `login-page{center; padding:24 16}`；`login-shell max-width:420`；brand 56；`login-form{gap:12}`；主按钮 `width:100%; justify-content:center`；`canSubmit = 用户非空 && 口令≥8 && !busy`；busy「处理中…」；`login-foot`（去登录/初始化、服务器设置）；`login-server` 面板 | §4.5 只有 3 句，无尺寸/结构/禁用规则 | 重要 |
| C.8 抽屉内部件（views.css:615-635、699-710；ExpenseSheet:742-786） | `.amt-display{padding:10 12; border-bottom:2 dashed line}`；`.a-cur 20px`；`.preview-box{9 11; rSm; mono 10.5}`；`.month-spent`；`.quick-cats{gap:6; radius:rSm; 半透明 surface-3}`；`.quick-cat{5 10; r999; is-on 2px 光圈}`；退款/分期 `set-row{padding:6 0}` + `select{width:84}` | §4.6 只列了内容顺序名，全部数值缺 | 重要 |
| D22 / D32 矮屏三档 | ≤720：键 36/15px、隐藏 `.preview-box`；≤620：键 32/14px、隐藏 `.quick-cats` 与 `.month-spent`；极矮：`a-val 26px` | §4.6 "矮屏三档回退（≤720/≤620）" 无触发条件、无各级数值、无遮蔽项 | 重要 |
| D29 栅格坍缩总表 | `theme-cards 2 列 / theme-cards--3 1 列(≤720)`、`og-heat .heat-grid 4 列`、`mover-grid 1 列`、`plan-grid 1 列`、`cal-year-grid 3 列`、`picker-body 94px / picker-grid 2 列` | 规范无汇总表，各屏也未逐一落 | 重要 |
| E4（全站 `color-mix`） | `.cat-ic` 底 12%/边 45%；`.quick-cat.is-on` 光圈 20%；`.heat-dot` 18–100% 动态；`.plan-ticks.is-done` 60%；`.rw-behind` 14% | ArkUI 无 `color-mix()`，规范未给等价算法（如"与 surface 按比例混色"的公式或预计算表） | 重要 |
| E5（app.css:768、views.css:920、ExpenseSheet:688-702） | `93dvh`、`calc(93dvh - 124px)`、`clamp(...dvh)`、`env(safe-area-inset-bottom)` | §6 只说"px→vp 原样照抄"，未给 dvh/vw/safe-area 的 vp 映射（124px 常数是否保留也未定） | 重要 |
| E18（LoginView 无 @media） | 登录页移动态（键盘弹起可视区、是否抽屉化）Web 未定义 | 规范未裁决，§4.5 也未给移动态 | 重要 |
| A.1 `--font-scale`（theme.css:144） | 全仓无引用，审计列 E1 未定 | 规范未写"不实现" → 实现者会去找这个令牌 | 次要 |
| B.2 `.sidebar` 移动（app.css:723-734） | `backdrop-filter:blur(10px); z-index:60; overflow-x:auto; overflow-y:hidden`；`.brand{padding:0 4}` | §3 只给 padding/border | 次要 |
| B.3 `.topbar`（app.css:170-180） | `background:var(--nav-bg)` + `backdrop-filter:blur(14px)` | 未提背景与模糊 | 次要 |
| B.9 `.orb` cyber + tone 用法表 | cyber `radius:1; border:1 currentColor; 透明底; 6px 切角; glow`；tone 组合（amber/mint/sky/accent + ink） | §2 只写"amber/mint/sky 等" | 次要 |
| B.13 `.switch::after` | knob `16×16`、`translateX(18px)`、`cubic-bezier(.34,1.56,.64,1)` | §2 只给盒子尺寸 | 次要 |
| B.6 `.icon-btn` | `color:ink-2`；hover `color:ink + border line-2` | 只给盒子 | 次要 |
| B.8 `.card-h--tight` / cyber 标题 | `margin-bottom:6`；cyber `card-t` uppercase/12.5/ls .1em、`card-cap` 变体 | 未提 | 次要 |
| §2 Sheet "drag-bar" | 审计 PSheet DOM 只有 `sheet-head`（标题 + ✕），**没有拖拽把手** | 规范自创了 drag-bar 元素（§4.6、§7 判据 5 都依赖它） | 次要（但与审计不符，见 §三） |
| E6 `build-stamp` 文本 | `SuenMoney · 单账本家庭记账 · {BUILD_STAMP}[ · 离线模式][ · 待同步 N]` | §3/§5 只写"含 离线模式 / 待同步 N"，未给拼接格式与位置 | 次要 |
| E7（SettingsView:47、821、880） | 设置页 `<POrb>` 未 import，实际渲染为空 | 规范按"有 orb"画设置卡头 | 次要 |
| E8 | 全站 `:hover` 无 `@media(hover)` 守卫 | 规范未说鸿蒙侧 hover/pressed 如何映射 | 次要 |
| E9 | 除 `nowrap+ellipsis` 外无 `overflow-wrap/word-break` | 规范未给长文本（分类名、计划名、设备名）折行/省略规则 | 次要 |
| E11 / E12 / E13 / E14 / E15 / E16 / E19 / E20 / E21 | sticky 重叠、more-menu 溢出、chips 横滑可发现性、picker-rail 长文案、icon-btn 密集换行、theme-cards 列数感受、扫描线强度、切换动画性能、tabular-nums 字形 | 均未涉及（多为观感/边界，可由实现自行收敛） | 次要 |
| D30 触摸反馈 | `.m-row:active{scale(.995)}`、`.mh-btn:active{scale(.98)}`、`.key:active{scale(.96)}`、`.btn:active{translate(2,2)}` | §5 无按下态要求 | 次要 |
| D31 `.sidebar` 横滑 | `overflow-x:auto; overflow-y:hidden`、`.nav::-webkit-scrollbar{display:none}` | 未提（鸿蒙侧品牌条不横滑可接受） | 次要 |

**小计**：阻断 **14** 行（按"同一次修复可一并解决"归并后 = §五 的 **12 项**）、重要 **37** 行、次要 **14** 行。

---

## 三、规范里写了但与审计不符的（错误）

| 规范位置 | 规范写的 | 审计事实 | 应改为 |
|---|---|---|---|
| §1.2 `surface-3` | candy `#EFEDFF` / cyber `#242438` | A.2：`#F1F5F9` / `#16162a` | candy `#F1F5F9`、cyber `#16162a` |
| §1.2 `ink` | cyber `#d7ffe9` | A.2：cyber `#e0e0e0` | cyber `#e0e0e0` |
| §1.2 `ink-2` | `#475569` / `#8fd9b8` | A.2：`#64748B` / `#8f93ad` | candy `#64748B`、cyber `#8f93ad` |
| §1.2 `ink-3` | cyber `#4e8f78` | A.2：cyber `#6b7280` | cyber `#6b7280` |
| §1.2 `danger` | candy `#F43F5E` | A.2：candy `#EF4444` | candy `#EF4444` |
| §1.2 `accent-ink` | cyber `#04170d` | A.2：`accent-ink` cyber = `#04220f`；`#04170d` 是 B.5 `.btn--primary`/`.toast` 的**局部**字色 | 令牌用 `#04220f`，按钮局部另列 `#04170d` |
| §1.4 `--r-sm` | `10` | A.1：`9px` | `9` |
| §1.4 切角 | `polygon(...7px...)`（"按钮/卡片"共用） | A.5：`.card/.modal/.sheet` = **14px**；`.btn` = 7px；`.orb` = 6px；`.logo-ph`/`.tp-cyber` = 8px | 卡片 14 / 按钮 7 / orb 6 / logo 8 四档分列 |
| §2 Card | `padding:18（移动端部分卡 14）· radius:rCard` | B.7（app.css:759）：移动端**所有** `.card` 都是 `padding:14; radius:16` | 移动端：`padding 14 / radius 16`（无例外）；桌面保留 18/20 |
| §2 Seg | 外框 `padding:3` | B.10：`padding:4` | `padding:4`，并补 `.seg-btn{padding:6 13; 12/700}` |
| §2 Chip | `padding:5 10` | B.11：`padding:5 11` | `padding:5 11` |
| §2 Tag | `9.5/700` | B.15：`10/600`，且 `border:1 solid line; bg:surface-2; color:ink-2` | `10/600` + 补齐 border/bg/色 |
| §2 Stat | `stat-v display 20/800`；`stat-l mono 9/ink-3` | B.14：`stat-v 21px/700`（display, ls -.02em, tabular）；`stat-l 10.5px ink-3 ls .04em`（非 mono；mono+uppercase 只在 cyber） | `21/700`；`stat-l 10.5` body 字体，ink-3 |
| §2 Orb | `36×36; radius:50%` | B.9：`34×34; border:2 solid line-2; shadow:2px 2px 0 line-2; radius:50%` | `34×34` + 2px 描边 + 2px 硬阴影 |
| §2 Donut | 环宽 `12` | B.22：`stroke-width:16`；12 是 `r = size/2 - 12` 的内缩量 | `stroke-width:16`，`r = size/2 - 12` |
| §2 Toast | `padding:10 18` | B.19：`padding:10 16`；且 `border:2 solid line-2`、`shadow 4px 4px 0 rgba(0,0,0,.18)` | `padding:10 16` + border + shadow |
| §2 Sheet / §4.6 / §7 判据5 | "`drag-bar`"（贴底抽屉顶部拖拽条） | B.18 PSheet DOM：`sheet-head`（标题 + 右侧 action + ✕），**无拖拽把手** | 删除 drag-bar，改为 `sheet-head{padding:12 14}` + title 15px |
| §4.1 全部档 | "2 列一年一格" | views.css:777：`.cal-year-grid{grid-template-columns:repeat(3,minmax(0,1fr)); gap:10}`，全部档复用同一类（D29 亦记 3 列） | 3 列 gap 10 |
| §4.2 热力卡 | "12 格 heat-grid"（未给列数） | views.css:994：移动 `.og-heat .heat-grid{repeat(4,minmax(0,1fr))}` | 4 列（12 格 → 3 行） |
| §4.3 报表页头 seg | "分段 月/年" | C.4 DOM：`PSeg 本月/本年/全部` 三档 | 本月 / 本年 / 全部（三档） |
| §4.3 涨跌榜 | "每行：名称列固定宽 192、中间占比条、右侧金额与涨跌" | C.4/views.css:307-319：`.mover` 是 flex 行 = `cat-ic 30 + (mover-t + mover-s) + row-end`，**无 192 名称列、无占比条**；`mover-grid` 移动 1 列 gap 10 | 照审计：图标 + 两行文本 + 右金额/环比；如确需排名条，须由 decisions 明确标注为"Web 之外的补充" |
| §4.3 还款节奏 | "还款节奏卡（信用卡，**中间占比条**）" | C.4/views.css:321-325：`.repay-steps` = 6 根竖柱（`i` 宽 100%、pink、`radius 5 5 0 0`、容器 h96、`.mono 8.5px` 金额 + `M月`） | 6 根竖向柱状图，高度按还款额 |
| §4.4 `stab` | `padding:9 14; 12.5/700` | C.6/views.css:932、877：移动 `padding:7 10; font-size:11.5` | `padding:7 10 / 11.5`（9 14 / 12.5 是桌面值） |
| §4.4 分类管理 | "分类管理**左导轨** + 右侧子类列表" | C.6/views.css:908-909：移动 `cat-admin` 变 **1 列**，`cat-rail` 变 `flex-direction:row; flex-wrap:wrap`（一级分类成顶部横向胶囊排） | 上：一级分类横排 wrap；下：二级列表 |
| §4.6 金额显示 | "`.amt-display` **38px**" | C.8：`.a-val` 生效值是 scoped `clamp(30px,7vw,44px)`（360vp 宽 ≈ 30px）；views 的 34px 已被覆盖；E 节记矮屏 26px | 改为 `clamp(30,7vw,44)`，按 vp 宽度取值（360 → 30） |
| §4.6 键盘列宽 | "左侧支付列（宽 **62**，tall 键 row-span）" | C.8/views.css:899：移动 `grid-template-columns:54px minmax(0,1fr)`（62 是桌面值） | 54px |
| §4.6 数字键 | "键 `min-height:46; radius:11; 18px/700`" | C.8/ExpenseSheet:687-691：`clamp(38,6.1dvh,54)` / `radius:clamp(8,2.4vw,12)` / `clamp(15,4.3vw,19)`（46/16 为被覆盖值） | 三组 clamp 原式 |
| §7 判据 5 | "键盘区左列宽 ≈ **62vp**" | 同上（54vp） | 54vp |
| §0 C08 依据列 | 引"web 审计 **B.27** `.todo-mark{width:4px;border-radius:2px}`" | B.27 是 CompositionCard；`.todo-mark` 实际在 views.css:756-768 一带（C.2 待办行） | 依据改为 views.css:756-768 / C.2 |
| §2 表头 | "全部数值见 `web-ui-inventory.md` B 节对应小节"（表格内多处用此豁免，如 Btn 状态、Chip 圆点、Bar） | 审计里这些数值存在，但规范正文没抄 → 实现者"照 B 节"无从查起（且 B 节有 6 处与规范冲突，见上） | 把用到的数值直接落到规范表格，删除豁免语 |

---

## 四、规范里不可执行的要求

> 规范说了"要有什么"，但没给数值/结构，实现者无法照做（不是缺漏，是条款本身空洞）。

1. **§2 Card**：`padding:18（移动端部分卡 14）` —— "部分"是哪一部分？审计里移动端是**全部** 14。且移动端 `radius 16` 根本没出现。
2. **§2 表头 + 多行**：`全部数值见 web-ui-inventory.md B 节对应小节` —— 这句等于把 20 个组件的参数转包给另一份文档，且审计本身明确写了"两处冲突谁生效"，直接照抄会抄到被覆盖值（§三已实证 12 处）。
3. **§2 Sheet**：`drag-bar` 无名、无尺寸、无颜色，且审计 DOM 里不存在该元素。
4. **§4.2 概况**：`12 格 heat-grid` —— 列数未定（审计 = 4 列），格内 `heat-m/heat-v/heat-dot` 三层无尺寸。
5. **§4.3 报表**：`构成卡（4 段维度切换 + 176px 环图 + 图例列）` —— 四维切换的容器形态（横滑药丸 vs 换行）、图例四列宽度（9/1fr/64/32）、周柱（7 列 × h112）、条形维度（62/1fr/76 + 10px 轨道）全部没有；`涨跌榜` 与 `还款节奏` 的结构描述与审计相反且无尺寸。
6. **§4.4 设置**：`四区内容照 web 审计 C.6` —— C.6 是 400+ 行的 DOM 树，规范未抽出任何一条尺寸；`计划 set-row + 12 段刻度` 的刻度尺寸（`i{h4;r2}`）也未给。
7. **§4.5 登录**：`表单字段走 .field/.input` —— 无卡片宽度（420）、无间距（gap 12）、无按钮宽度（100%）、无 **disabled 判定条件**、无 busy 文案、无"服务器设置"面板结构。
8. **§4.6 记账抽屉**：`矮屏三档回退（≤720/≤620）` —— 三档的**触发条件**（是 vp 宽还是 vp 高？审计是 `@media` 视口宽/高混合）与**每档数值**（36/15、32/14、26）均未给；`顶部 drag bar` 无规格。
9. **§1.2**：`chart-1..8（分类色，按色号索引）` —— 无色值表，无法实现。
10. **§5 下拉**：`位移/阈值/文案（下拉记一笔 → 松开记一笔）逐字照 Web` —— 前半句给了数（§3 有 84/0.62/54），但 `.pull-bar` 的视觉（实时高度、accent、11/700）仍空。
11. **§0 C17**：`年度报告后置` —— 但 §4.3 报表页仍要放"年度报告已生成"横幅与页头"年度报告"按钮，是否渲染、点击去哪，未写。
12. **§7 判据 2**：`dump 的 bounds 高度 ≈ 字号的 1.05 倍` —— 1.05 是 `line-height:1.05` 的近似，但 ArkUI `Text` 高度包含行高策略（`TextHeightAdaptivePolicy`/`heightAdaptivePolicy`），无允许误差区间（±vp）→ 判据不可机械执行。
13. **§3 build-stamp**：`底部居中 tiny（含 离线模式 / 待同步 N）` —— 未给拼接格式、来源、是否可点击，与审计 `SuenMoney · 单账本家庭记账 · {BUILD_STAMP}[ · 离线模式][ · 待同步 N]` 不对应。
14. **§6.1 单位**：`CSS px → vp 原样照抄` —— 对 px 成立，但审计里大量 `dvh/vw/%/env()`（93dvh、`calc(93dvh-124px)`、`clamp(...,6.1dvh,...)`、`env(safe-area-inset-bottom)`）无映射规则，属未定义的"照抄"。

---

## 五、结论

**FAIL** —— 覆盖率 35.4%（52/147 适用条目），且已覆盖部分有 **31 处取值与审计相反**（其中 12 处会直接做出错的视觉）。

必须先补的 **12 项阻断**（§二 表中 14 行阻断归并为 12 个待办；不补则不可能 1:1 重建）：

1. **A.2 颜色令牌补全并改值**：补 `pink / amber / mint / sky / cyan / on-color / nav-bg / scrim / chart-1..8` 的实际色值；改 `surface-3 / ink / ink-2 / ink-3 / danger`（5 处值错）。
2. **A.6 背景装饰层**：`.app::before`（candy 点阵 24px＋mask / cyber 电路网格 52px 四层）、`.app::after`（cyber 扫描线 4px 周期）、`.deco-a~d` 四个几何贴纸的尺寸/坐标/旋转/透明度。
3. **A.5 cyber 切角四档**：卡片 14px（现写 7px 错）、按钮 7px、orb 6px、logo/主题缩略 8px；补 `.ic` 描边 2.4→1.6。
4. **B.7 卡片移动端形态**：`padding:14 + radius:16 + shadow 3px 3px 0 #E9EEF6`（全部卡，含 `--pop`）；cyber `radius:0 + 无阴影`。
5. **B.25 `PCatIcon` 全规格**：30×30 / radius 9 / border 1 / 底色 `color-mix(c 12%)` / 边 `color-mix(c 45%)` / 调用尺寸链 34·30·28·26·20·18·16。
6. **C.8 分类选择器 `.picker`**：min(660,100vw-20) / 86dvh / 94px rail / 2 列格 padding 12 gap 7 / cell padding 9 radius 10 / is-on 2px 硬阴影。
7. **C.8 支付选择器 `.pay-item`**：min(440,100vw-20) / padding 10 12 / border 2 / radius rMd / is-on 2px 硬阴影。
8. **C.2 `.mobile-hero` 容器**：padding 14 / border 2 line-2 / radius 20 / shadow 4px 4px 0 line-2 / gap 12 / cyber 渐变·1px·r0·glow。
9. **C.6 设置分类管理移动形态**：1 列 + `cat-rail` 横排 wrap gap 4 + `cat-rail-btn 7 9/r9/2px/12-600` + `cat-kid 8 10/r10`（并把"左导轨"改写）。
10. **C.8 键盘几何改为生效值**：左列 54、键 `clamp(38,6.1dvh,54)` / `clamp(15,4.3vw,19)` / `radius clamp(8,2.4vw,12)`、pay-key `clamp(34,5.4dvh,48)` / `clamp(7.5,2.1vw,9)`、`keys gap 5`、`paycol gap 6`。
11. **C.4 报表构成卡子结构**：chips 全宽横滑（`width:100%; nowrap; overflow-x`）+ `card-cap` 隐藏；`compose-list` 四列 9/1fr/64/32 虚线分隔；`dim-bar` 62/1fr/76 + 轨道 h10；`week-bars` 7 列 h112；图例 `i 9×9 r3`。
12. **C.4 报表结构与审计对齐**：seg 改**本月/本年/全部**三档；涨跌榜改 flex 行（删 192 名称列与占比条，或明确标注为 Web 之外的补充）；还款节奏改 6 根竖柱。

另有 **37 行重要**（见 §二，含颜色/阴影族、`.report-banner`、`E4 color-mix` 换算、`E5 dvh·safe-area` 映射、账单导入抽屉、五个表单抽屉、登录页禁用规则、矮屏三档数值等）与 **14 行次要**。

**放行条件**：补完上述 12 项阻断 + 至少 §二 中标注"重要"的 C.2/C.3/C.4/C.6/C.7 屏级条目后复审；本文件可直接作为补齐清单逐行勾销。
