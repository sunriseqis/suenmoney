# 鸿蒙原生端 UI 规范 v1（1:1 对齐 Web 移动端）

> **这份文档是唯一实现依据。** 实现与验收都拿它逐条对照。
> 上游事实来源（只读，不改）：
> - `docs/design/audit/web-ui-inventory.md`（1172 行，Web 移动端全部可视事实）
> - `docs/design/audit/docs-ui-rules.md`（1350 行，146 条硬性规则 + 36 条禁止项 + 28 条冲突）
>
> **总原则**：
> 1. **视觉与布局以 Web 移动端为唯一真值**（用户裁决："1:1 照搬 web 移动端"）。
> 2. 文档（decisions / feature-inventory）用于**补齐 Web 未覆盖的规则**（数据口径、禁止项、功能入口）。
> 3. 两者冲突时按 §0 的裁决表执行，不再逐条讨论。
> 4. **禁止自创布局**：结构、层级、顺序、尺寸都照 Web；拿不准就查审计文件对应行。

---

## §0 冲突裁决表（28 条里影响实现的 12 条）

| 编号 | 冲突 | 裁决 | 依据 |
|---|---|---|---|
| C02/C05 | 移动端是否有底部 Tab 条 | **没有。** 移动端导航 = 流水页 hero 内三个小入口（概况/报表/设置）+ 顶栏返回按钮。禁止底部 Tab | web 审计 C.1：`views.css:1115 .sidebar .nav{display:none}`、`base.css` 隐藏顶栏文字与动作 |
| C04 | 月档是否按日分组 | **按消费日分组**，组头带当日小计 | web 审计 C.2：`.date-cap` + `.sum` 现存于模板 |
| C06 | 移动端设置是否含数据区 | **含。** 四个 tab：账目 / 计划与还款 / 数据 / 家庭 | web 审计 C.6 |
| C07/C09 | 移动端概况形态 | 与桌面临时同一套，**无 mobile-only 差异**；含待办提醒条与构成堆叠条 | web 审计 C.3：「无任何 mobile-only/desktop-only 类」 |
| C01 | 金额是否加语义色 | **不加。** 退款仅显示负号，不染色；hero 大金额 cyber 下用 `--accent`（霓虹）属主题色不属语义色 | web 审计 C.2/C.3 + decisions:387 |
| C08 | 紧急度标记 | 统一 **左侧竖条**：`.todo-mark` 4px 宽、颜色按 late/soon/calm/done/skip | web 审计 B.27 `.todo-mark{width:4px;border-radius:2px}` |
| C03 | 设置分组 | 四个 `stab`（下划线页签），**不是**胶囊按钮组 | web 审计 C.6 `.settings-tabs` / `.stab` |
| C21 | 流水行日期显示 | 分组头用 `M月D日`；行内右下角小字显示 `MM-DD 还` 或 `即时` | web 审计 C.2 `.row-end`/`date-cap` |
| C16 | 离线提示文案 | 顶栏下方细条 `离线模式`；同步队列非空时 `待同步 N`（build-stamp 区域内联） | web 审计 C.1 build-stamp 结构 |
| C17 | 年度报告 | **后置项**，本轮不实现（不阻塞验收） | docs-audit D；web 审计 C.5 单独屏 |
| C24 | 依赖 DOM/CSS 的机械判据 | 改为 ArkUI 可判据：见 §7 | 本规范新定义 |
| C26 | 服务端槽位 | 固定三槽（内网/备用/公网），动态增删后置 | web 审计 C.6 数据区 + 任务书 |

---

## §1 令牌（**以生成表为准，本规范不重复抄值**）

> **唯一真值**：`docs/design/generated/hw-token-table.md`（由 `scripts/gen-hw-token-table.mjs`
> 从 `web/styles/proto/theme.css` 机器生成，51 个令牌，含 `--chart-1..8` 全部色值）。
> ArkTS 侧同源生成物：`common/theme/AppTheme.ets`（字段名 = 变量名去 `--` 转驼峰）。
> **禁止在本规范里手抄色值** —— v1 就是因为手抄抄错了 5 组，被覆盖核验判 FAIL。

### 1.1 必须知道的 5 条派生规则

| # | 规则 | 实现 |
|---|---|---|
| 1 | 分类色存**色号**（1–16），显示取 `chart[(n-1) % 8]`；没设过色号按 `categoryId` 哈希取稳定值 | `Palette.slotOf()` / `chartColor()` |
| 2 | 分类图标底色 `color-mix(色 12%, 透明)`、描边 `color-mix(色 45%, 透明)` | ArkUI 无 `color-mix()` → `UiStyle.mixHex(色, surface, .12/.45)` |
| 3 | cyber 切角**四档**：卡片 14 / 按钮 7 / orb 6 / logo·主题缩略 8 | `UiStyle.CUT_CARD/CUT_BTN/CUT_ORB/CUT_LOGO` + `cutPathCommands()` |
| 4 | 移动端卡片阴影是 **`3px 3px 0 #E9EEF6`**（`.card--pop` 也被覆盖），不是桌面 6px | `cardShadow(tokens, isCyber, mobile=true)` |
| 5 | cyber 下 `.ic` 描边 1.6，candy 2.4 | `strokeWidthOf(isCyber)` |

### 1.2 尺寸映射（替换 v1 的「px 照抄」）

| Web | ArkUI | 说明 |
|---|---|---|
| `Npx` | `N` vp | 密度无关单位，1:1 |
| `dvh` / `vh` | `屏高 × pct / 100` vp | 通过 `display.getDefaultDisplaySync().height / densityPixels` 取屏高 vp 后换算 |
| `env(safe-area-inset-bottom)` | `px2vp(窗口避让区 bottom)` | 抽屉底部必须让开手势条（见 §3.1） |
| `clamp(a, 6.1dvh, b)` | `Math.max(a, Math.min(b, 屏高vp * 0.061))` | 键盘键高/字号/圆角全部走这个换算 |

## §2 原子组件（ArkUI 侧一一对应，禁止自行发挥）

> 全部数值见 `web-ui-inventory.md` B 节对应小节；这里给**必须实现的关键点**。
> 单位：CSS px 直接当 vp 用（同为密度无关单位，1:1 视觉）。

| 组件 | 必须满足 |
|---|---|
| **Card** | `padding:18`（移动端部分卡 14）· `border:2 solid line` · `radius:rCard` · `shadow:3px 3px 0 #E9EEF6`（candy）/ `border:1 solid line` + 无阴影（cyber） |
| **CardH** | `display:flex; gap:10; margin-bottom:13`；`card-t` 15px/700 display 字体；`card-cap` mono 9.5/ls .16em/uppercase/ink-3 |
| **Btn** | `min-height:38; padding:8 16; border:2 solid line-2; radius:pill; bg:surface; font 12.5/700; shadow:3px 3px 0 line-2`。变体 `--primary`(accent 底) `--ghost`(无边框无阴影) `--sm`(min-h 30, padding 4 11, 11.5) `--danger`(文字 danger)。cyber：`radius:0; border:1; border-color:accent 55%; bg:transparent; color:accent; mono; 11px; ls .14em; uppercase; 切角` |
| **IconBtn** | `38×38; radius:pill; border:2 line; bg:surface`；cyber 方角 1px |
| **Input** | `min-height:40; padding:9 12; border:2 line; radius:rMd; bg:surface; 13px`；focus `border:accent + shadow 3px 3px 0 accent`；cyber `border:1; bg:#12121a; mono; 12px; focus 发光` |
| **Seg** | 胶囊外框 `padding:3; border:2 line; radius:pill; bg:surface-2`；选中项 `bg:accent; color:accent-ink; radius:pill`；cyber 方角 |
| **Chip** | `padding:5 10; border:2 line; radius:pill; 11.5/600`；`is-on` → `bg:amber; border-color:line-2; shadow:2px 2px 0 line-2` |
| **Tag** | `padding:2 8; radius:pill; 9.5/700; mono`；tone: accent/danger/warn/dash |
| **Stat** | 竖排 gap 3；`stat-v` display 20/800；`stat-l` mono 9/ink-3 |
| **Switch** | `42×24; radius:pill; border:2 line-2; bg:surface-3`；开：accent |
| **Sheet** | 移动端**贴底全宽**，`height:93dvh`、`radius 顶 22`、`drag-bar`；桌面右侧 500 面板（原生不做） |
| **Toast** | 底部居中、`bg:ink; color:bg; radius:pill; padding:10 18; 12px` |
| **Empty** | `padding:34 10; 居中; ink-3`；必须能区分「加载中…」与「没有符合条件的流水」 |
| **Donut** | 移动端直径 **176px**（PDonut 内联尺寸压制 CSS）；环宽 12；颜色取 chart-N |
| **Orb** | 圆形底色块 `36×36; radius:50%`，作为卡头身份物（amber/mint/sky 等） |

---

## §3 外壳（移动端）

**没有底部导航。** 结构自上而下：

```
[sticky 品牌条]  padding:8 14 6; bg:bg; border-bottom:1 solid line
   └ 品牌图标 46×46 radius 12 + 品牌名 15px（副标题隐藏）
[顶栏 topbar]    padding:8 12; border-bottom:1 solid line; sticky; z:30
   ├ 返回按钮（仅非流水页；流水页整条顶栏不渲染）
   └ 标题/副标题、主题按钮、记一笔 → 移动端**全部隐藏**
[内容区 content] padding:6 12 64; gap:12
   └ 当前屏
[build-stamp]   底部居中 tiny（含 离线模式 / 待同步 N）
[Toast] / [记账抽屉]
```

- **记账唯一入口 = 下拉手势**（列表 `scrollY<=2` 且 `dy>8`；位移 `min(84, dy*0.62)`；≥54 松手打开；<54 回零）。
- 禁止：底部 Tab、移动端顶栏按钮、悬浮球/FAB。
- 返回键：抽屉开着先关抽屉，否则回上一屏。

---

## §4 各屏结构（照 web 审计 C 节，逐项实现）

### 4.1 流水（落地页）
`mobile-hero` → 工具条卡 → 筛选区（展开时）→ 明细卡 → 分页。

hero（**移动独有**）：
- `.mh-head`：eyebrow（mono 9.5 / ls .14em / uppercase / ink-3）→ 大金额（display 800 **38px**，`¥` 为 0.48em、ink-2）→ 环比胶囊（`padding:3 8; border:1.5 currentColor; radius:pill`）
- `.mh-facts`：三列 grid gap 8，上下 **1px 虚线** line 分隔；标签 mono 9 ink-3；值 11/700
- `.mh-nav--sm`：三列 grid gap 6，按钮 `min-height:30; padding:0 4; 11.5px; border:1 line; radius:pill; bg:surface-2`
- `hero-todo`：`padding:7 10; border:1 solid line; radius:r-sm; bg:surface-2; 11.5px`；左侧 `todo-dot` 6×6 圆点按 late/soon/calm 着色；右侧 chevron
- `mh-todos`（展开）：每行 `padding:5 0; border-bottom:1 solid line`，`todo-mark` **4px 宽**竖条 + 「N期 · 计划名」+ 自动/需手动 + 金额

工具条：搜索框（input 前置 Search 图标，`padding-left:34`）+ 「收起」按钮（仅展开时）；`.lt-adv` 展开后是 **分段 按月/按年/全部** + 期间 ‹ 2026-10 › + 「筛选 · n」+ 分段 按日期/按金额。
筛选区：三组（分类/支付/记录人），组标题 mono 9.5 独占一行，chip 换行，顶上 1px 虚线与 14px 间距。
明细：组头 `date-cap`（mono 10.5 / ls .08em / uppercase / ink-2，右侧当日小计 ink-3）；行卡 `.m-row`（`padding:10; gap:8; border:2 line; radius:rMd; bg:surface`；标题 12.5/600；副行 10/ink-3，三段用 `·` 连接；右侧金额 13/600 + 小字 `MM-DD 还`|`即时`）。
年档：3 列 ×12 格（`.year-cell` padding 12 10、2px 边、rMd），格内 `M月` + 本月标签 + 笔数 + 金额 + 5px 进度条。
全部档：2 列一年一格。
分页：`hasMore` → 「加载更多」（loading 时禁用且文案「加载中…」）；否则「查看上月」。

### 4.2 概况
单列 gap 12。主卡 `og-hero`（占满宽）：eyebrow 行（分段 本月/本年/全部 + ‹ 期间 › + `全部记录` 标签）→ 待办提醒条（同流水 hero-todo）→ 大金额（display 800 **34px**）→ 环比 → 三指标（grid 3，gap 10，上方 1px 虚线）→ 构成堆叠条（`margin-top:14`，各段 `flex:cents`）→ 图例（`cl-dot` + 名 + mono 百分比）→ 展开待办（`todo-mark` 4px 高 22，主按钮「确认/入账」+ `更多` 菜单里「忽略本期」）。
热力卡：卡头 orb + 标题 + cap；12 格 heat-grid，点格下钻报表。
累计卡：卡头 + 5 行 kv。

### 4.3 报表
`report-head` 卡（分段 月/年 + 期间 + 三事实）→ 构成卡（4 段维度切换 + **176px 环图** + 图例列）→ 涨跌榜卡（每行：名称列固定宽 192、中间占比条、右侧金额与涨跌）→ 还款节奏卡（信用卡，中间占比条）。
> 排名行**中间必须有条**（decisions）。

### 4.4 设置
`settings-tabs`：四个 `stab`，`padding:9 14; border-bottom:3 solid transparent; 12.5/700; is-on → border-color:accent + ink`；cyber `mono 11 uppercase ls .1em`。
四区内容照 web 审计 C.6（分类管理左导轨 + 右侧子类列表；支付方式 set-row；计划 set-row + 12 段刻度 + more-menu；数据区主题三卡/导出/导入/备份/快照/关于/危险区；家庭成员/设备/账号）。
`set-row`：`padding:11 0; border-bottom:1 solid line; gap:12`；`set-ic` 32×32 radius 9；`set-t` 12.5/600；`set-s` 10.5 ink-3。

### 4.5 登录
无外壳；表单字段走 `.field/.input`；错误文案按类型（401 → 口令错；网络 → 连不上）；服务器地址多槽 + 顺序探活。

### 4.6 记账抽屉
贴底、全宽、`93dvh`、顶部 drag bar。内容顺序：金额显示（`.amt-display` 38px，`¥` 小号）→ 分类/日期/支付三行字段 → 备注 → 退款开关 → 跨月提示（`这笔会记在 YYYY 年 M 月`，accent + 粗）→ 常用分类快捷条 → 键盘。
键盘：**5 列** = 左侧支付列（宽 62，tall 键 `row-span`）+ 右侧 4×4 数字键（`7 8 9 ⌫ / 4 5 6 C / 1 2 3 完成 / 0 00 .`），键 `min-height:46; radius:11; 18px/700`；矮屏三档回退（≤720/≤620）。

---

## §5 状态与交互（不许省略）

| 状态 | 要求 |
|---|---|
| 加载 | 「加载中…」出现在内容区，不用骨架屏（Web 就是文字） |
| 空态 | 文案必须指对地方：无数据「没有符合条件的流水」；全部档「还没有任何记录」 |
| 离线 | build-stamp 内联 `离线模式`；列表用本地库现算并保持可读 |
| 待同步 | build-stamp 内联 `待同步 N` |
| 错误 | 就地显示服务端 message，禁止静默吞掉 |
| 下拉 | 位移/阈值/文案（下拉记一笔 → 松开记一笔）逐字照 Web |

---

## §6 ArkUI 映射约定（实现纪律）

1. **单位**：CSS px → vp，数值原样照抄，不做"适配换算"。
2. **阴影**：`parseShadow()` 把 `"3px 3px 0 #E9EEF6"` 转 `{offsetX:3, offsetY:3, radius:0, color}`。
3. **圆角**：`radiusOf(tokens, isCyber, candyValue)`；cyber 一律 0。
4. **切角**：cyber 用 `.clipShape(new Path({commands}))` 复刻 `polygon`，不得用圆角近似。
5. **字体**：一律走 `fontDisplayOf/fontBodyOf/fontMonoOf`，禁止裸写族名。
6. **`@Builder` 参数**：动态内容**必须**单参数对象 + `$$`（多参数不刷新，已踩坑）。
7. **主题**：`@StorageLink(THEME_STORAGE_KEY)` + `tok()`，禁止 `@State tokens` 快照。
8. **金额**：整数分；显示才除 100；退款为负、不加色。
9. **禁止**：Emoji、说明式文字、整卡语义色、底部 Tab、悬浮球、系统数字键盘、桌面元素（表格/构成卡/顶栏动作）。

---

## §7 验收判据（ArkUI 可机械核对）

| # | 判据 | 检查方式 |
|---|---|---|
| 1 | 移动端无底部 Tab；导航只有 hero 三入口 + 返回 | `uitest dumpLayout` 里不得出现 4 个等宽底栏项；hero 内必须有 概况/报表/设置 |
| 2 | 流水 hero 大金额字号 38vp、display 字体 | dump 的 bounds 高度 ≈ 字号的 1.05 倍；切换主题后文本宽度变化（Outfit≠Orbitron） |
| 3 | 卡片 2px 边框 + candy 硬阴影 | 截图取色：卡片左边缘 2px 内颜色 != 页面底；阴影方向为右下 3px |
| 4 | 设置用下划线页签（不是胶囊） | dump：四个 tab 下方有 3px accent 下划线，无胶囊背景 |
| 5 | 记账抽屉贴底、5 列键盘 | dump：键盘区左列宽 ≈62vp，右侧 4 列；抽屉顶边 y ≈ 屏高 7% |
| 6 | 跨月提示 | 选次月日期后 dump 含「这笔会记在」且颜色为 accent |
| 7 | 主题全局生效 | 切主题后各屏背景取色变化（candy>#F0 / cyber<#20 灰度） |
| 8 | 禁止项 | dump 全文不得出现说明式长句、Emoji、FAB |
