# 覆盖核验（第二轮）· `hw-ui-spec.md` vs `web-ui-inventory.md`

> 对象：`docs/design/hw-ui-spec.md`（302 行，§0 已声明 **docs 为需求真值、web 仅视觉数值参考**）
> 参照：`docs/design/audit/web-ui-inventory.md`（1172 行，Web 移动端事实）
> 判据：**只判两类**——(a) docs 沉默、实现必须知道数值而规范没给；(b) 规范给的数值与审计矛盾且未在 §0.1 声明。
> **不判**：凡 §0.1 D1–D22 已声明"按 docs"的差异（无组头、三入口不定宽、二级页 `×`、卡圆角 24、无底栏、无数据区、主题三档…）**一律视为合法裁决，不计缺漏、不计错误**。
> 附带核验：§1 指认的生成物确实存在且完整（`docs/design/generated/hw-token-table.md` 51 令牌、`hw-native/.../theme/AppTheme.ets` 同源生成）——上一轮"手抄色值"问题已闭环。

---

## 一、仍需补的数值（docs 沉默处）

> 判定口径：docs（`docs-ui-rules.md`）无值 → 以审计为真值。规范若**给出了等价指针**（§2 "见审计 B 节"、§4 "细节数值查 web 审计"）可降级为第三节"需查两份文件"；规范**既无值也无可用指针**（或指针指向的是被 §0.1 否决的形态）才算本节阻断项。

| # | 审计位置 | 需要什么数值 | 规范现状 |
|---|---|---|---|
| 1 | **A.6** `.app::before` / `::after` / `.deco-a~d`（theme.css:190–238） | candy：点阵 `radial-gradient(rgba(139,92,246,.13) 1.4px, …)`、`background-size:24px 24px`、`opacity .75` + mask；cyber：电路网格两组 `52px 52px` 线 + 2 个 radial、全屏扫描线 `rgba(255,255,255,.028) 0 1px / 4px`（**z-index 999**）；candy 四枚贴纸：`260×260` 圆（amber .28）、`150×150` 异形圆角、`60px` 三角（mint .2, rotate18°）、`120×14` 胶囊（accent .18） | **全文 0 处提到"背景装饰层"**。既没给数值，也没裁决"做/不做"（docs R38 说点阵/扫描线属预览装饰、应用内未接入 → 若按 docs 应不做，但 cyber 扫描线在 Web 应用内是开着的）。这是全应用底色，做与不做视觉差一个量级 → **阻断 B1** |
| 2 | **R14 / D7 三入口**（`ui-rework-3.md` §6.6；审计 C.2 `.mh-nav--sm .mh-btn` 只是被否决形态） | 一行文字链接的：字号（审计同层级为 11.5–12.5）、字色（`--ink-2`？）、三项间距、右侧对齐基线、是否 12px 图标、触达高度（R17 对 `×` 给了 40×40，入口未给） | D7 只给"一行次要链接／不定宽／无选中态／纯文字（可带小图标）"。**无任何数值**；而审计给的那套（`min-height:30 / padding:0 4 / 11.5px / 胶囊 / bg surface-2 / 等宽 3 列 grid`）正是 D7 明令禁止的形态 → **抄审计=违规，不抄=无值** → **阻断 B2** |
| 3 | **B.7 / D10 卡片内距**（app.css:759） | 移动端 `.card{padding:14px}`（**全部卡，一等覆盖**） | §2 Card 写 `padding:18`（移动端部分卡 14）——没说"哪些卡是 14"，而事实是**全部 14**。照 §2 做，整站卡片内距全部偏大 4vp → 见第二节（矛盾）**阻断 B3** |
| 4 | **C.2 顶卡容器** `.mobile-hero`（views.css:1012–1029） | `padding:14; border:2 solid --line-2; radius:20; shadow:4px 4px 0 --line-2; gap:12`；cyber：`border:1 / radius 0 / rgba(0,255,136,.45) / 180deg 渐变 62% / glow 0 0 30px -16px` | §4.1 只写行为（两态/收起/吸顶），**无一句容器外观**；§2 只有通用 Card（`3px 3px 0 #E9EEF6`）。照着 §2 做会把落地页最显眼的卡做成"普通卡"（少 `--line-2` 描边、阴影色错、圆角差一档）→ 并入 **阻断 B3** |
| 5 | **B.21 进度条 `.bar`**（views.css:415–421） | `height:9; radius:999; bg --surface-3; border:1 solid --line; fill --accent;` 年格/全部格内联覆写 `height:5; margin-top:2` | §2 原子组件表**没有 Bar**；而 §4.1 年档/全部档、§4.2 进度对比（R73）、§4.3 占比条都要用它 → 实现者只能自创高度/圆角/轨道色 |
| 6 | **B.25 PCatIcon 调用尺寸**（views.css 各处） | 行卡 **34**、表格 30、抽屉选择器 20、设置 rail 18 / kid 26、计划行 26、抽屉分类格 28、快捷分类 16；基础 `radius:9; border:1 transparent`；cyber `radius:1` | §1.1 已解决"色"（12%/45% + chart-N）；§4.4 只给设置区的 `44px` 徽位。**流水行卡的 34px** 无出处，而 docs R138 说的是"流水/抽屉 44px 徽位" → docs 44 与审计 34 直接冲突、规范未择一 → **阻断 B6**（见第二节第 12 行） |
| 7 | **C.2 行卡** `.m-row`（views.css:204–216、930–931） | `padding:10; gap:8; border:2 solid --line; radius:14;` 标题 `12.5/600 gap 6`；副行 `10px --ink-3 gap 6 mt 3`；列表 `gap:8` | §4.1 只给字段顺序；D1/D2/D3/D4 给内容口径。行卡外观全靠"查审计"（可救，但需一并给出，否则行高与密度必然走形） |
| 8 | **紧急度竖条**（docs C08 三选未裁决；审计 `todo-mark` height 20/22、`is-late`=--danger / `is-soon`=--warn / `is-calm`=中性） | 宽（4px / 3px）、按状态的三档色、圆角（`--r-sm`?）、行内高度 20 / 22 | §0.2 只裁"左侧竖条 + 展开后不重复标记"，**没给宽度、色值映射、圆角** → 五条提醒并排时最显眼的标记无值 |
| 9 | **下拉手势**（App.vue:70–103；docs C05 60px/60vp/80vp 三值冲突） | 阈值、阻尼、上限（审计 54 / 0.62 / 84；`dy>8` 起算、`scrollY<=2` 触发）、`pull-bar` 文案切换点 | §4.6/§5/D21 只说"下拉是唯一入口 + 首次提示一次"。**阈值族一个数都没有**，且 docs 内部三值冲突未裁决 → 只能猜（不改变静态视觉，但改变唯一记账入口的手感） |
| 10 | **C.6 设置页骨架**（views.css:461–475、500–529、477–497） | `settings-tabs{ gap:4; border-bottom:1 }`、`stab{ padding:7 10; 11.5; border-bottom:3 accent }`、`cat-rail{ row + wrap; gap:4 }`、`cat-rail-btn{ padding:7 9; radius:9; border:2; 12/600 }`、`cat-kid{ padding:8 10; radius:10; border:1 }`、`set-row{ padding:11 0; gap:12 }`、`set-ic{32×32 r9}`、`set-t 12.5/600`、`set-s 10.5` | §4.4 只给类名（`settings-tabs`/`stab`）+ 44px 徽位；其余 0 值。可经"查审计"救回 → 记入第三节 |
| 11 | **C.4 报表块内部**（views.css:1126–1158、307–355） | `legend-row` 网格 `9px 1fr 64px 32px` + 虚线分隔；`dim-bar` 网格 `62px 1fr 76px`、`db-track h10 r99`；`week-bars` 7 列 `h112`、柱 `r6 6 2 2`；`repay-steps h96` / `repay-col i` 粉柱 `r5 5 0 0`；`mover{ padding:9 10; gap:9 }`；`report-banner{ padding:16 18; 100deg 渐变; shadow 5px 5px 0 }` | §4.3 只有"环图+可展开图例、中间占比条、纵向堆叠、宽度上限"等结构语；数值 0 → 第三节 |
| 12 | **C.3 概况** | `hero-amt 34px/800/-.035em`、`hero-eyebrow mono 10 ls .16`、`hero-metrics gap 8 + 顶部虚线`、`heat-cell{padding:7 3 6; r7; gap 3}`、`heat-dot h4`、`kv{padding:8 0; 12px}`、`og-card-foot` | §4.2 结构完整、数值 0 → 第三节 |
| 13 | **C.8 键盘/选择器** | `keypad` 网格 `54px + 1fr`、键序 `7 8 9 ← / 4 5 6 清空 / 1 2 3 [完成 跨3–4行] / 0 00 .`、`key clamp(38,6.1dvh,54) / clamp(15,4.3vw,19) / clamp(8,2.4vw,12)`、`pay-key clamp(34,5.4dvh,48) / clamp(7.5,2.1vw,9)`、`amt-display{padding:10 12}`、`a-val clamp(30,7vw,44)`、`sheet-cell{padding:10 12; r14}`、`preview-box{9 11; 10.5 mono}`、`month-spent`、`quick-cat{5 10; 11.5/600}`、`picker{min(660,100vw-20); 86dvh}`、`picker-body 94px + 1fr`、`picker-grid 2 列 padding12 gap7`、`picker-cell{9; 10; 11.5/600}`、`pay-item{10 12; r14}` | §1.2 只给 `clamp()`→vp 的**换算公式**（很好，但不含基准值）；§4.6 只有结构。键序（`←`/清空/完成跨行/`00`）在规范里**完全没有**，而这决定键盘能不能做对 → 第三节（键序建议直接抄进 §4.6） |
| 14 | **B.12 搜索框**（views.css:941/997–998） | `input--search{padding-left:34}` + 放大镜绝对定位 `left:11`、`search-wrap` 移动 `flex:1 1 auto; min-width:0`；`lt-search{flex:1 1 100%; gap:8}` | §4.1 只写"搜索框独占并撑满 + 筛选同行"；搜索图标位置/内距 0 值 |
| 15 | **C.7 登录**（LoginView scoped） | `login-page{padding:24 16}`、`login-shell{max-width:420}`、`login-card{gap:12}`、`login-form{gap:12}`、`login-server{border-top dashed; padding-top:12}`、`brand-mark 56` | §4.5 只给行为与 `R98` 结构；数值 0 → 第三节 |
| 16 | **B.19 Toast / B.24 pull-hint** | Toast `bottom:18`（移动）+ `border:2 --line-2` + `shadow 4px 4px 0 rgba(0,0,0,.18)`；`pull-hint` mono 9.5 ls .16 胶囊 30×14 | §2 Toast 只给"底部居中 / bg ink / radius pill / padding 10 18 / 12px"（padding 与审计 10 16 亦不符）；`pull-hint` 完全没有（Web 里被 `!important` 隐藏，鸿蒙是否要画"下拉可记账"提示面无规格，只有 R115"提示一次"的文案要求） |

---

## 二、未声明的矛盾（悄悄写错）

> 判据：规范给了值 → 与审计冲突 → §0.1 没有对应 D 编号。"是"= 合法裁决；"否"= 需修。

| # | 规范位置 | 规范值 | 审计值 | 已在 §0.1 声明 |
|---|---|---|---|---|
| 1 | §1 → `hw-token-table.md` / `AppTheme.ets`（`fontMono` candy） | `'Plus Jakarta Sans', ui-monospace, monospace`（theme.css **原值**） | **实际生效**（base.css:66–78 覆写的 A.3 表）：candy mono = `'JetBrains Mono Variable','Plus Jakarta Sans Variable','MiSans VF',ui-monospace,monospace`；display/body 亦整体不同（多了 `'Outfit Variable'` / `'MiSans VF'`） | **否** → 阻断 B4：ArkTS 侧 `fontMono` 就是非等宽族，`card-cap`/`stat-l`/金额/`tag`/`pill` 全站 mono 小字会渲染成比例字体（审计"字体实际生效值"整张表被绕过） |
| 2 | §2 Card 内距 | `padding:18`（"移动端**部分**卡 14"） | 移动端 **全部** `.card{padding:14}`（app.css:759 单类选择器，位置在 `.card` 之后） | 否 → 阻断 B3 |
| 3 | §2 Card 圆角 `radius:rCard` | **20**（`AppTheme.rCard:20`，即 `--r-card`） | 移动 **16** / 桌面 20（app.css:759） | 否（未声明）。注意 §4.4 与 D18 都写"卡 24"（docs R132）——三处三个值，**§2 的 20 落在 docs 与 web 两边都不是** → 阻断 B3 |
| 4 | §2 Sheet 圆角 | `radius 顶 22` | 22（app.css:770） | 否（半声明）：D18 已裁"抽屉 **24**"，§2 仍写 22，规范内部两值并存 |
| 5 | §2 Donut | 直径 176 ✓、**环宽 12** | 直径 176 ✓（E3 已定）、`stroke-width:16`、`r = size/2 - 12`（12 是**半径内缩**不是环宽）、段间空隙 `2.5` | 否 → 阻断 B5：环宽 16→12 会细 25%；另缺"段间 2.5 空隙"（多段时会对不上） |
| 6 | §2 Orb | `36×36; radius:50%`（无描边、无阴影） | `34×34` + `border:2 solid --line-2` + `box-shadow:2px 2px 0 --line-2`；cyber `radius:1 + 1px currentColor + glow + 6px 切角` | 否 → 卡头身份物少一圈描边和硬阴影，与卡内其它元素风格断裂 |
| 7 | §2 Stat | `stat-v 20/800`；`stat-l mono 9` | `stat-v 21/700`（cyber 18）；`stat-l 10.5px` **无衬线**（cyber 才 mono 9.5） | 否 |
| 8 | §2 Toast | `padding:10 18`；无边框、无阴影 | `padding:10 16`；`border:2 --line-2`；`shadow:4px 4px 0 rgba(0,0,0,.18)` | 否（candy 下 Toast 的"硬边框+硬阴影"是它的辨识特征） |
| 9 | §2 Chip | `padding:5 10` | `5 11` | 否（次要） |
| 10 | §2 Tag | `9.5/700 mono` | `10px/600 mono` | 否（次要） |
| 11 | §2 Seg | 外框 `padding:3` | `padding:4; gap:4` | 否（次要） |
| 12 | §4.1 流水行卡分类图标 | **未给尺寸**（§4.4 的 `44px` 徽位只写在设置区） | 行卡 `cat-ic` **34**（PCatIcon size=34）；而 docs R138「左 **44px** 圆形徽位（12% 底 + 20px 图标）」适用屏明写"流水/抽屉" | 否 → 阻断 B6：每一行都要选 34 还是 44，选哪个都与一份来源冲突 |
| 13 | §4.2 热力 | 窄屏 **6×2**（R70） | `.og-heat .heat-grid` 移动 `repeat(4,…)`（views.css:994）= 4×3 | 否（**低风险**：属 §0 通则"按 docs"，建议但仍应补一行 D 编号） |
| 14 | §4.2 累计条四项 | 四项=`已记 N 天 · M 笔 · 平均 A 笔/天 · 首笔日期`（R71） | `.kv ×5`（多一项） | 否（同上，低风险） |
| 15 | §4.3 报表页头 | 规范未写 | 审计有 `.rf-num` **26px 大数字** + 笔数；docs R86「不许有页首大数字与『共 N 笔』」 | 否 → 实现者会照审计做页首大数字，直接违反 R86。应像 D14/D15 那样显式声明"按 docs 删页首大数字" |
| 16 | §2 Sheet `drag-bar` | 规范新增元素 | 审计无（Web 是 `sheet-head` 标题 + `✕`） | 否（次要；与 §6.9"禁止自创"精神冲突，建议标注"鸿蒙手势条，非视觉必需"） |

---

## 三、可执行性检查

**实现者能否只靠规范做出正确界面？不能——但这是可接受的工作方式**（规范已多处给出指针：§2「数值见审计 B 节」、§4 抬头「细节数值查 web 审计」、§1「令牌见生成表」）。以下位置**必须同时查两份文件**，建议在规范里就地补 1 行"查 §X.Y"以免翻错小节：

1. **流水控制行**：期间 `‹ 2026-10 ›`（`icon-btn 38×38` + `period-label min-width:76 / 14px/700`）+ 搜索行（`lt-search gap 8`、`input--search padding-left 34`、图标 `left:11`）→ 审计 C.2 表。
2. **顶卡内部 8 个元素**：`mh-amt(38/800/-.035em)`、`mh-eyebrow(mono 9.5 ls .14)`、`mh-delta(10.5)`、`delta-pill(3 8 / 1.5px 边)`、`mh-facts(3 列 / 9px + 11px / 上下虚线)`、`hero-todo(7 10 / gap 8 / 11.5)`、`todo-dot 6×6`、`todo-line(padding 5 0)` → 审计 C.2 表（**注意：顶卡不是 `.card`，见 B3**）。
3. **流水行卡与三档列表**：`m-row`、`m-list gap 8`、`year-cell(padding 12 10, r14, gap 4)`、`cal-year-grid 3 列 gap 10`（docs R60 3×4 与之一致）、`bar` 5px → 审计 C.2 表 + B.21。
4. **概况整屏**：`hero-amt 34`、`hero-metrics`、`og-heat .heat-grid`（**docs 6×2 vs 审计 4 列，需按 docs 且补 D 编号**）、`heat-cell`、`kv`、`og-card-foot` → 审计 C.3 表。
5. **报表整屏**：`report-head`、`rf-num`（**按 docs R86 应删**）、`legend-row` 网格、`dim-bar` 网格、`week-bars 112`、`repay-steps 96`、`mover`、`report-banner` → 审计 C.4 表。
6. **设置整屏**：`settings-tabs/stab`、`cat-rail/cat-rail-btn/cat-kid`（**移动是横排 wrap，不是左导轨**）、`set-row/set-ic/set-t/set-s`、`theme-card/theme-prev 56`、`about-card`、`plan-ticks(4px, r2, gap2)` → 审计 C.6 表 + B.31。
7. **记账抽屉**：金额条、`sheet-cell`、`preview-box`、`month-spent`、`quick-cats/quick-cat`、**键盘 5 列 + 键序**、`picker` 两栏 94px/2 列、`pay-list` → 审计 C.8 表。规范 §1.2 给了 `clamp(…dvh)`→vp 换算，但**基准值仍要查审计**（6.1dvh/54px、4.3vw/19px、2.4vw/12px、5.4dvh/48px、2.1vw/9px）。建议把键序（`7 8 9 ← / 4 5 6 清空 / 1 2 3 [完成跨行] / 0 00 .`）直接写进 §4.6。
8. **图标尺寸调用表**：`cat-ic 34/30/28/26/20/18/16`、`PayIcon 14/18/15/16`、`orb 34`、`set-ic 32` → 审计 B.25/B.26/B.9/C.6。规范只有 44px 徽位一处。
9. **主题细节**：cyber 下逐元素差异（`.card` 发光、`.btn` 11px mono ls .14、`.chip` 10px、`.stat-v` 18px、`.nav`… 以及 `--scrim`、`--nav-bg`）→ 令牌表有颜色/圆角/阴影，**逐元素字号与字形差异只在审计**。
10. **遮罩层**：抽屉/弹窗的 `scrim{--scrim; blur 2px; fadeIn .18s}` → 令牌表有 `--scrim`，模糊与动效时长只在审计 B.18。
11. **网络/同步可见态**：`build-stamp(10px mono ls .06 opacity .55 padding-top 18)`、`sync-dot` → 审计 B.2/C.1；docs R144 只给文案与位置。
12. **空态按钮**："清除筛选"用 `--sm` 还是 ghost、放在 PEmpty 之下什么间距 → 审计 B.20/C.2 交互段（R64 只给文案与"方向不许写错"）。

---

## 四、结论

**FAIL** —— 阻断 6 项。

阻断标准：docs 沉默且规范无值、会导致做错视觉 > 0 → 命中。

| 编号 | 阻断项 | 一句话后果 | 最小修复 |
|---|---|---|---|
| **B1** | 背景装饰层（审计 A.6）全文缺失，且 docs R38 与之相左未裁决 | 全应用底色（点阵 / 电路网格 / 扫描线 / 4 枚贴纸）要么凭空消失、要么被随意发明 | §0.1 加一行 D 编号：做/不做 + 若做，四个数值组直接抄 A.6 |
| **B2** | 三入口只有形态、没有数值；审计里的值＝D7 明令禁止的形态 | 唯一被用户点名改过的控件，实现者无值可依（字号/字色/间距/触达各凭感觉） | §4.1 补：`12.5/600 --ink-2、间距 16、可带 12px 图标、触达高 ≥40`，或明确"从旧 `.mh-btn` 去胶囊化推导" |
| **B3** | 卡体系三源不一致：内距 18 / 14、圆角 20 / 16 / 24、抽屉顶 22 / 24；顶卡容器无规格 | 全站每一张卡的密度与轮廓都会做错（内距大 4vp、圆角错一档、顶卡少 `--line-2` 描边与 `4px` 阴影） | §2 改为：移动端 `padding:14`、卡 `radius:24`（docs）、抽屉 `24`；并把顶卡从"Card"里拆出来单列（14 / border2 `--line-2` / r20 / `4px 4px 0 --line-2` / gap12） |
| **B4** | 字体族取 theme.css 原值而非 base.css 生效值 | `fontMono` 变成比例字体 → `card-cap`/金额/`tag`/`stat-l` 全站 mono 小字排版与 Web 不一致 | 令牌生成器改读 base.css 覆写后的实际栈（或 §0.1 声明"mono 用 Jakarta，与 Web 生效值不同"并说明理由） |
| **B5** | Donut 环宽 12（实为 16，12 是半径内缩）+ 缺段间 2.5 空隙 | 报表主图环变细 25%，多段时接缝错位 | §2 改为 `直径 176 / stroke 16 / r = size/2-12 / 段间 2.5` |
| **B6** | 流水行卡分类图标 34（审计）vs 44（docs R138），规范未择一 | 每一行的主识别物尺寸错，且图标列宽（R137 定宽）随之错 | §4.1 明确一个值（建议按 docs 44，并把 R137 的定宽写死） |

**非阻断但需处理**：第一节其余 12 项（Bar 组件缺失、Orb 34/36、Stat 21/20、Toast 边框阴影、紧急度竖条宽度与三档色、下拉阈值族、设置/报表/概况/登录/选择器数值）——均可由"查审计对应小节"救回，但请在规范里补小节号；第二节 9–16 行为次要偏差或"按 docs 但缺 D 编号"（热力 6×2、累计四项、报表页首大数字），建议一并补 D 编号，否则实现者会照审计抄错。

**放行条件**：B1–B6 修完即 PASS；其余项建议同批补齐（工作量集中在 §2 组件表 + §4.1/§4.6 两处）。本文件可直接当作逐行勾销清单。
