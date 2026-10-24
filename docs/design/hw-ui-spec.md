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

## §0 效力条款与冲突裁决（**用户 2026-10-24 裁决：docs 为需求真值**）

> **效力顺序（必须遵守）**
> 1. **`docs/design/audit/docs-ui-rules.md` 的 146 条规则 + 36 条禁止项 = 需求真值**。
> 2. `docs/design/audit/web-ui-inventory.md` = **视觉数值参考**，仅在 docs 未规定时采用
>    （颜色、间距、字号、阴影、字体等细节）。
> 3. 两者冲突 → **按 docs**。docs 与 docs 冲突 → 见下方裁决表（已按用户指示处理）。
>
> **背景**：Web 端实现曾经**漏做了 docs 里的需求**（用户原话："docs 是对的，
> 这是之前 web 构建你忽略掉的需求"）。所以"照抄 Web"只在 docs 沉默处成立。

### 0.1 关键差异清单（docs 覆盖 Web；实现必须按"按 docs"一列）

| # | 主题 | docs 要求（真值） | Web 现状（不可照抄） | 依据 |
|---|---|---|---|---|
| D1 | 月档流水**无组头** | 列表直接就是明细，无"按天"分组标题、无日小计 | 有 `.date-cap` 组头 + 当日小计 | R51 |
| D2 | 行内日期**只写「日」** | `28日`（月份由期间/组头给） | `2026-10-20` 整串 | R52 |
| D3 | 行内字段顺序 | 分类图标 · 分类名/备注 · 支付方式 · **日** · **账期** · 金额；账期形如 `9月12日刷 · 28日还 · 16天` | 只有备注+支付方式+右侧小字 | R53 |
| D4 | **删掉行内"还款日"药丸** | 紧急度属于概况「本月要还」，不属于流水行 | 行卡右侧挂 `MM-DD 还` | R54 |
| D5 | 合计**只在有筛选时**给金额 | 无筛选时不显示"合计 ¥X" | 始终显示"N 笔 · 合计 ¥X" | R55 |
| D6 | 三入口位置 | 与控制行的**期间选择器同一行、靠右** | 单独一行（`mh-nav`） | R13 |
| D7 | 三入口样式 | **一行次要链接**：右对齐、**不定宽**、**无选中态**、纯文字（可带小图标） | 等宽 3 列胶囊按钮（等于把底栏搬到顶上） | R14 + F32 |
| D8 | 三入口只在流水页顶部、**随内容滚走**、二级页不重复 | 不吸顶 | — | R15 |
| D9 | 搜索框**独占一行并撑满**，筛选按钮同行 | — | 与期间/入口挤在一行 | R16 |
| D10 | 二级页关闭 | `×` 收在**标题行行尾**（`设置 ×`），19px、`--fg-muted`、不单独占一行、不吸顶 | 我实现的独立返回条 `‹` | R17/R18 |
| D11 | 顶卡两态 | 有未处理 → 两列；**无 → 本月支出独占整列**（不留半格、不放"没有待处理"） | — | R20/R21 |
| D12 | 顶卡提醒 | **默认收起**、点击**向下展开**（把列表顶下去，不是浮层）、展开态**不记忆** | — | R22 |
| D13 | 顶卡吸顶 | **只有逾期时整张顶卡吸顶**；吸顶是位置、颜色标记是"要不要动手"，两者都由"有无逾期"推出但互不解释 | — | R23 |
| D14 | 移动端概况**不放构成堆叠条** | 构成是报表页的活 | 有 `stack-bar` + 图例 | F09 |
| D15 | 移动端设置**不挂数据区** | 导入/导出/备份/快照/关于不进移动端 | 有"数据"tab | F18/R99 |
| D16 | 主题**三档**并跟随系统 | 深色 / 浅色 / **跟随系统**；未显式选择时实时跟随系统 | 只有 candy/cyber 两档 | R130 |
| D17 | 主题入口只在设置里 | 顶栏永不放主题按钮 | — | R131 |
| D18 | 圆角令牌 | 卡 **24** / 抽屉 **24** / 输入 **14** / 胶囊 **999**；动效统一 `cubic-bezier(.2,0,0,1)`，200/350/400ms | 卡 20 / 卡（移动）16 | R132 |
| D19 | 分类图标 | 存 **kebab-case 名字**；解析优先级 显式 icon > 按名反查 > 通用图标 | — | R134 |
| D20 | 支付方式**不给图标选择器** | 图标按类型推断（cash→banknote / credit→credit-card） | 我做了 PayIconPicker | R135 |
| D21 | 记一笔唯一入口 | 下拉手势；**不许**列表底部"＋ 记一笔"、空态按钮、FAB | — | R24/F01 |
| D22 | 移动端**无底栏无顶栏** | 顶栏不含标题/记一笔/主题；导航只有三入口 + 二级页 `×` | 我曾自造 4-Tab 底栏（已删） | R02 |

### 0.2 冲突的处理结果（用户已裁决）

| 原冲突 | 结果 |
|---|---|
| C04 月档分组 | **按 docs：无组头**（D1） |
| C06 移动端数据区 | **按 docs：不挂数据区**（D15）；主题切换仍然只能在设置里（R131），因此设置保留「账目/计划与还款/家庭」三区 + 一个不含导入导出的「外观」入口 |
| C07/C09 移动端概况 | **按 docs：不放构成条**（D14）；提醒 0 条时整格消失（R20） |
| C02/C05 底部入口 | **按 docs：无底栏**（D22）；入口是三入口链接（D6/D7） |
| C01 金额染色 | **不加语义色**（R26 类）；cyber 下 hero 大金额用 `--accent` 属主题色 |
| C08 紧急度标记 | 左侧竖条；**展开后不再重复标记**（R28） |
| C03 设置分组 | 按 docs 的 tab 分组（见 §4.4），不再自定义 4 区 |

### 0.3 裁决纪律

- 本表任何一行**不得**在实现阶段"因为 Web 更好看"而改动。要改先改这张表并说明理由。
- 实现完成后，验收按 §7 + docs 的 146 条逐条打勾；两者的判据冲突时 **docs 优先**。

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

## §3 外壳（移动端，按 docs R02/R15/R17/R19）

```
[内容区]（无底栏、无吸顶标题条）
  └ 当前屏
      ├ 流水页：控制行（期间靠左 + 三入口靠右，同一行，随内容滚走）
      └ 二级页（概况/报表/设置）：标题行 `标题            ×`（19px、--fg-muted、不吸顶）
[build-stamp] 底部 tiny（含 离线 / 待同步 N）
[Toast] / [记账抽屉]
```

- **无底栏、无吸顶顶栏**；标题只出现一次（R19），内容里不得重复。
- 二级页关闭用 **`×` 收在标题行行尾**（R17/R18），不是单独一行的 `‹`。
- 三入口**只在流水页**，二级页一个字都不重复（R15）。
- 安全区：抽屉与底栏必须让开手势条（`px2vp(避让区 bottom)`）。
- 返回键：抽屉开着先关抽屉。

---

## §4 各屏（结构与功能按 docs；细节数值查 web 审计）

### 4.1 流水（落地页）

**控制行（R13/R14/R16）**：两行。
1. `期间 ‹ 2026-10 ›`（靠左） + `概况 报表 设置`（**靠右、不定宽、纯文字次要链接、无选中态**）
2. 搜索框（**独占并撑满**） + `筛选` 按钮

**顶卡（R20–R23）**
- 两态：有未处理待办 → 两列（本月支出 + 处理提醒）；**无 → 本月支出独占整列**（同一个组件带布尔，不写两个分支）
- 提醒**默认收起**；点一下**向下展开**明细（把列表顶下去，不是浮层）；展开态**不记忆**
- **只有逾期时整张顶卡吸顶**；颜色标记与吸顶互相独立
- 三档（月/年/全部）属于期间选择器，不占额外行

**月档列表（R51–R56）**
- **无组头**：列表直接就是明细
- 行内顺序：`分类图标 · 分类名/备注 · 支付方式 · 日 · 账期 · 金额`
  - 日期只写 `28日`；账期形如 `9月12日刷 · 28日还 · 16天`
  - **不得**出现"还款日"灰药丸
- 合计：**只有加了筛选**才显示 `筛选结果 N 笔 · 合计 ¥X`；无筛选时指路到本月总额
- 分页：游标 + 每段 100 笔 + 触底「加载更多」

**年档 / 全部档**：年档 12 个月格、全部档一格一年；日历**不新增页面/路由**。

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
