# Web 移动端视觉事实 × 鸿蒙实现 · 差异审计

> **审计对象**：`docs/design/audit/web-ui-inventory.md`（1172 行，Web ≤860px 可视事实）
> vs `hw-native/entry/src/main/ets/`（32 个 .ets，逐文件通读）
> **裁决前提**：`docs/design/hw-ui-spec.md` §0 —— docs 优先，Web 只在 docs 沉默处生效；
> §0.1 的 D1–D22 已声明的 22 条差异按 docs 实现是**正确的**，**不计缺陷**（见本文 §二）。
> **本文只报「docs 沉默处」Web 有而代码没有、或数值对不上的项。**
> 审计员只读不改；本文件是新增产物，未触碰任何源码。

**引用格式**：Web 侧给「审计小节 + 选择器（审计文件里标注的行号）」；代码侧给 `文件:行`。

---

## 一、视觉偏差清单

严重度口径：**阻断** = 组件/弹层不可见或 docs 明写「必须/必备」的视觉物整类缺失，验收必不过；
**高** = 数值/形态明显不同，肉眼一眼看出走形；**中** = 单点数值或单组件形态不符；**低** = 1–2vp 级或文案级。

| 编号 | 项 | Web 位置（选择器/行号，来自审计） | 代码位置 | 期望值（Web/规范） | 实际值 | 严重度 |
|---|---|---|---|---|---|---|
| W01 | 卡片内距 | B.7 `.card` 移动覆盖 `app.css:759`；规范 §2 Card | `common/theme/AppTheme.ets:66`；`dashboard/DashboardScreen.ets:238`；`settings/SettingsScreen.ets:475,625,712,790` | `padding:14` | `densityPad = 18` | 高 |
| W02 | 卡片圆角 | B.7 `app.css:759`（Web 16）+ 规范 §0.1 D18 / §2 = **24** | `AppTheme.ets:91`（`rCard:20`）；`DashboardScreen.ets:240,358,401`；`SettingsScreen.ets:477,627,792` | `radius:24` | `20`（`heat/cumulative` 甚至未走 `radiusOf`，cyber 下仍 20 圆角） | 高 |
| W03 | 卡片描边色 | B.7 `.card{border:2 solid var(--line)}` `app.css:288-295` | `SettingsScreen.ets:478,628,793` | `--line` = candy `#E2E8F0` | `outlineStrongOf()` = `#1E293B`（描边比 Web 深两档，卡片像被"框住"） | 高 |
| W04 | 卡片描边宽 / 硬阴影一致性 | B.7 `.card{box-shadow:3px 3px 0 #E9EEF6}` 移动覆盖；A.4 | `DashboardScreen.ets:359,402`（border 1）；`ReportScreen.ets:309,346,368,383,423,442`（无 `.shadow`） | 全部卡 `border:2` + `3px 3px 0` | heat/累计卡 `border:1`；报表 6 张卡只有 `composeCard`(289) 有阴影 | 中 |
| W05 | 顶卡硬阴影 | C.2 `.mobile-hero{box-shadow:4px 4px 0 var(--line-2)}` `views.css:1012-1022`；规范 §2 顶卡 | `LedgerScreen.ets:496-501` | `4px 4px 0 --line-2`（cyber 为辉光） | 只有 `padding/radius/border`，**无 `.shadow()`** | 高 |
| W06 | 环比胶囊 | C.2 `.delta-pill{padding:3 8;radius:999;border:1.5 currentColor;mono 10.5 700}` `views.css:43-54`；规范 §4.1「顶卡**必须有**环比胶囊」 | `LedgerScreen.ets:386-392`；`DashboardScreen.ets:219-223` | 带 1.5vp 描边 + 胶囊 + accent 12% 底 + 显式 `+` 号 | 裸 `Text`：无描边/无圆角/无底色、`toFixed(1)+'%'`（正数没有 `+`）、且用 danger/ok 染色 | 阻断 |
| W07 | 概况环比行 | C.3 `.hero-delta` = `delta-pill` + `span "较上月 ¥x"` `views.css:42` | `DashboardScreen.ets:219-223` | 胶囊 + 「较上月/去年/上一段 ¥x」 | 只有百分比 | 中 |
| W08 | 概况三项指标 | B.14 `.stat-v 21/700 display`、`.stat-l 10.5 ink-3`；C.3 `.hero-metrics{margin-top:16;padding-top:14;border-top:1px dashed}` gap 8 | `DashboardScreen.ets:268-281`（值 12/500、标签 9、无 display 族）；`228-233`（无虚线分隔、Row 无 gap） | 21 / 10.5 / display 族 / 虚线上分隔 | 12 / 9 / 默认族 / 无分隔线 | 高 |
| W09 | 顶卡三事实条间距 | C.2 `.mh-facts{gap:8}` `views.css:1046-1053` | `LedgerScreen.ets:439` | 列间 gap 8 | `Row()` 无 `space`，三格紧贴（只靠 `layoutWeight` 撑开） | 低 |
| W10 | 卡头体系 | B.8 `.card-t 15/700 var(--font-display)` + `.card-cap mono 9.5 ls.16em uppercase ink-3`；C.3/C.4 每张卡都有 `.card-h` | `ReportScreen.ets:266,296,327,355,377,410,437`；`DashboardScreen.ets:327,388`；`SettingsScreen.ets:336,422,496,671,745` | 15/700 + display 族；右上角 mono 大写小标 | 全部退化为 `11.5/700` 裸 `Text`，无 display 族、无 `card-cap`、无卡头间距 13 | 高 |
| W11 | Orb 圆形图标 | B.9 `.orb{34×34;radius:50%;border:2 line-2;shadow:2px 2px 0 line-2}`；C.3 三张卡 / C.4 / C.6 卡头均挂 orb | 全仓 **0 处**（`UiStyle.ets` 只有 `CUT_ORB` 常量） | 34×34 圆形描边徽标，tone 分 amber/mint/sky/accent | 无此组件 | 中 |
| W12 | 图标体系 | B.0 `.ic{stroke-width:2.4}`/cyber 1.6；B.25 `PCatIcon`；B.26 `PPayIcon`；C.2 搜索/Search 15、Chevron 13/14/18；C.8 退格与 ChevronRight | 全仓 `grep SymbolGlyph|Image(` 仅 2 处品牌图（`BrandMark.ets:10`、`SettingsScreen.ets:688`）；其余全部用文字字符：`LedgerScreen.ets:412,567,579`（`⌃ ⌄ ‹ ›`）、`ExpenseEditor.ets:468,410`（`←`、`›`） | Lucide 图标（描边 2.4/1.6） | 文本字符，无描边、字号与光学尺寸不受控 | 阻断 |
| W13 | 行卡分类徽位 | B.25 移动行卡 `PCatIcon size=34`（图标 `size*0.56`=19）；规范 §2「徽位 44、图标本体 20」 | `LedgerScreen.ets:870-879` | 44 徽位 + 分类图标 20 | `Text(分类名首字)`、`fontSize 16`、`radius 12`——**用的是假名首字不是图标** | 高 |
| W14 | 行卡排版细值 | C.2 `.m-row{gap:8}`、`.m-row-t 12.5/600`、`.row-amt mono 13/600` | `LedgerScreen.ets:869`（space 10）、`884`（Medium 500）、`899-902`（无 mono） | gap 8 / 600 / mono | gap 10 / 500 / 默认族（金额列宽会随字形跳动，违反 R39） | 中 |
| W15 | 搜索框 | B.12 `.input{min-h 40;padding 9 12;border 2 line;radius 14;bg surface;13px}` + `.search-wrap .ic{left:11}`；规范 §2 Input（描边改 outline-strong） | `LedgerScreen.ets:699-702` | 40 高、实描边、14 圆角、surface 底、13px、左内嵌搜索图标 | 36 高、**无描边**、**无圆角**、`surface2` 底、无图标 | 高 |
| W16 | 期间导航 | B.6 `.icon-btn{38×38;border:2 line;radius:pill;bg surface}`；C.2 `.period-label{min-width:76;14/700 display}` | `LedgerScreen.ets:567-578`；`ReportScreen.ets:220-230`；`DashboardScreen.ets:182-202` | 38×38 描边圆钮 + 定宽 76 的 14/700 标签 | 16px 文本 `‹›`（ledger/report）、30×26 `surface2` 无描边钮（dashboard）、标签 13 | 中 |
| W17 | 档位 seg | B.10 `.seg{padding:4;border:2 line;radius:pill;bg surface-2}` + `.seg-btn{padding:6 13;12/700;is-on accent+accentInk+border line-2}` | `LedgerScreen.ets:618-634`；`DashboardScreen.ets:246-259`；`ReportScreen.ets:247-259` | 外框胶囊 + 内部分段按钮，选中 accent 实色 | 无外框无槽，三个独立小胶囊（ledger/report 用 `surface2` 淡底、dashboard 用 accent 实色）——三屏三种形态 | 中 |
| W18 | 排序 seg 位置/形态 | C.2 `.lt-adv .seg[style=margin-left:auto]`（在展开区内）`views.css:999-1005` | `LedgerScreen.ets:721-741` | 折叠在高级区内，选中 accent | 常驻一行，选中用 `surface3`（非 accent）、11px、高 28 | 中 |
| W19 | 筛选按钮 | C.2 `button.btn.btn--sm` `min-h 30/padding 4 11/11.5 700`，有筛选时 `.btn--primary` 且文案带「· n」（R62） | `LedgerScreen.ets:710-714` | 30 高 / 11.5 / 2vp 描边 / 带数量 | 36 高 / 12 / 无描边 / 无数量 | 中 |
| W20 | 年格 / 全部档网格 | C.2 `.cal-year-grid{gap:10}`（3 列）、`.year-cell{border:2;padding:12 10;radius rMd;gap:4}` `views.css:224-239,777` | `LedgerScreen.ets:974-976`（gap 8）、`959-962`（padding 8 / border 1）、`1029`（全部档 2 列） | gap 10 / 2 描边 / 12-10 内距 / 3 列 | gap 8 / 1 描边 / 8 内距 / 全部档 2 列 | 中 |
| W21 | 概况热力卡 | C.3 `.og-heat .heat-grid` 4 列、`.heat-cell{border1;radius7;padding 7 3 6;bg surface-2}`、内含 `.heat-m/.heat-v/.heat-dot`、卡头 orb+card-t+card-cap、`.og-card-foot` 按钮、格可点下钻 | `DashboardScreen.ets:324-360` | 每格：月份 + **金额** + 4vp 色条；有卡头/卡脚；可点击下钻 | 只有一个 26 高的色块 + 8px 月数字；**无金额**（R70）、无描边无底、无卡头卡脚、**无 `onClick`** | 高 |
| W22 | 页面内距重复 | C.1 `.content{padding:6px 12px 64px; gap:12}` `views.css:1121` | `MainPage.ets:148`（12）+ `LedgerScreen.ets:1118`（12）/`DashboardScreen.ets:453`（12）/`SettingsScreen.ets:847`（12）；`ReportScreen.ets:204`（只 bottom） | 左右 12 一处 | 流水/概况/设置实际左右 **24**，报表 12——三屏不一致 | 中 |
| W23 | 底部 build-stamp | B.2/base.css `.build-stamp{mono 10;opacity:.55;padding-top:18;居中}`；C.1 内容 `{BUILD_STAMP}[ · 离线模式\| · 待同步 N]` | `MainPage.ets:113-122` | mono 10 / opacity .55 / 含版本戳与离线·待同步 | `fontBody`（非 mono）、9px、无版本戳、无离线/待同步（规范 §3 要求含） | 中 |
| W24 | 全局 Toast | B.19 `.toast{…bg ink;border 2 line-2;radius pill;shadow 4px 4px 0}`；C.1 `div.toast` | 全仓无（`MainPage.ets:8` 只在注释里提到） | 底部居中反色胶囊 | 不存在（规范 §3 外壳把它列为必备层） | 中 |
| W25 | 设置页表单弹层 | C.6「5 个 PSheet 表单抽屉：分类/支付/支付合并/计划/成员」 | `SettingsScreen.ets:851-910`（`sheetContent()` **从未被 `bindSheet` 引用**，全仓仅 `LedgerScreen.ets:1120` 有 bindSheet） | 点行 → 底部 sheet 表单 | 点「新增/编辑」只改 `sheetMode` 状态，**没有任何浮层出现**（M1/M2/M3 与成员表单全不可用） | 阻断 |
| W26 | 设置页签 | C.6 `.settings-tabs{gap:4;border-bottom:1px line;overflow-x:auto}` + `.stab{padding:7 10;11.5/700;border-bottom:3 accent;color ink3}` `views.css:461-475,875-877,932,935` | `SettingsScreen.ets:807-815`、`1322-1333` | 下划线式页签、gap 4、11.5px、可横滑 | 4 个实色胶囊按钮（选中 accent 填充）、gap 6、11px、`layoutWeight` 等分不横滑 | 中 |
| W27 | 主题三档形态 | C.6 `.theme-card{border2;radius rMd;padding 10}` + `.theme-prev{height:56}` 缩略图 + `is-on{shadow 3px 3px 0}` `views.css:734-763` | `SettingsScreen.ets:720-738` | 三张带主题缩略图的卡片（≤720 单列 / 721–860 三列） | 三行单选：16×16 色点 + 文案 + 「已选」 | 中 |
| W28 | 一级分类导航 | C.6 移动 `.cat-rail{flex-direction:row !important;flex-wrap:wrap;gap:4}` + `.cat-rail-btn{padding 7 9;radius 9;border 2 transparent;12/600;width:auto}` `views.css:500-518,767-769,908-909` | `SettingsScreen.ets:360-385` | 横排换行按钮组 | 纵向列表，**固定 `width(110)/height(200)`**（桌面形态）、padding 8、radius 6、无描边 | 中 |
| W29 | 设置行与行图标 | C.6 `.set-row{padding:11 0;border-bottom:1px line}`、`.set-ic{32×32;radius 9;border 1 line;bg surface-2}` `views.css:477-494` | `SettingsScreen.ets:438-468`（行 padding 6）、`440-447`（28×28、radius 8、无描边）；`764-786` 同 | 行 padding 11 / 分隔线 / 32 图标 | 行 padding 6 / 无分隔线 / 28 图标 / 用名称首字代替支付图标 | 中 |
| W30 | 二级分类行 | C.6 `.cat-kid{padding 8 10;border 1 line;radius 10;bg surface}` + `cat-ic 26` + `tag--warn 已停用` `views.css:520-529` | `SettingsScreen.ets:386-412` | 卡片式行 + 26 图标 + 药丸标签 | 裸 Row（padding 4）、8×8 色点、无描边无底、「已停用」纯文本 | 中 |
| W31 | 次要按钮规格 | B.5 `.btn{min-h 38;padding 8 16;border 2 line-2;radius pill;12.5/700;shadow 3px 3px 0}`；`.btn--sm{min-h 30;padding 4 11;11.5}` | `SettingsScreen.ets:342-353,428-431,502-505,752-754`（26 高、10–11px、无描边无阴影）；`LedgerScreen.ets:710,722,731`；`ExpenseEditor.ets:706,711` | 2vp 描边 + 硬阴影 + 11.5/700 | 无描边、无阴影、10–11px、高度 26–36 混用 | 中 |
| W32 | 报表页头卡 | C.4 `div.card.report-head{padding:14}` + 内部 toolbar `views.css:879` | `ReportScreen.ets:213-235` | 一张 `padding:14` 的卡承载档位 + 期间 | 裸 `Row`（`padding top/bottom 4`），无卡、无描边、无底 | 低 |
| W33 | 报表图例 | C.4 移动 `.legend-row{grid 9px\|1fr\|64px\|32px;padding 6 0;border-bottom 1px dashed}` `views.css:1147-1157` | `ReportScreen.ets:275-281` | 四列（点/名/**金额**/占比）+ 虚线分隔 | 三列（点/名/占比），无金额列、无虚线分隔 | 中 |
| W34 | 涨跌榜行 | C.4 `.mover{padding 9 10;border 1 line;radius rMd;bg surface-2}` + `cat-ic 30` `views.css:307-319` | `ReportScreen.ets:414-421` | 带底带描边的行卡 + 30 分类图标 | 裸 Row（名 11 / 金额 / 差额），无底无描边无图标 | 中 |
| W35 | 环图几何与中心字 | B.22 `.donut{176×176}`、`stroke-width 16`、`r = size/2 - 12`、段间 **2.5**（弧长）空隙、`.donut-c-v display 800 21` + `.donut-c-l mono 9.5 uppercase`；规范 §2 Donut | `DonutChart.ets:93-94`（160×160）、`41`（`min/2-10` 再减 `lineWidth/2`）、`44`（`gap=0.025` rad）、`75-81`（`14vp sans-serif` 无小标） | 176 / 16 / r=76 / 2.5 弧长 / 21 display + 9.5 mono 两行 | 160 / 16 / 有效半径 62 / ≈1.55（r=62 时）/ 单行 14px | 高 |
| W36 | 抽屉字段格 | C.8 `.sheet-cell{padding 10 12;border 2 line;radius rMd;bg surface}`、`.lbl{mono 9.5;ls .12em;uppercase;ink-3}`、`.val{600}`、尾部 `ChevronRight 14` `views.css:637-653` | `ExpenseEditor.ets:394-421` | surface 底 + 2vp 描边 + mono 9.5 标签 + 600 值 + 14 图标 | `surface2` 底、**无描边**、标签 9 非 mono、值 13/500、尾部 `'›'` 16px 文本 | 高 |
| W37 | 抽屉金额条 | C.8 `.amt-display{padding 10 12;baseline;border-bottom 2px dashed line}`、`.a-cur 20px`；`.a-tail` 右挂 | `ExpenseEditor.ets:527-537` | 左对齐 baseline、`¥` 20、下缘 2vp 虚线 | 右对齐（`justifyContent End`）、`¥` 18、无虚线、无尾部支付方式名 | 中 |
| W38 | 账期预览框 | C.8 `.preview-box{padding 9 11;border 1px dashed line;radius r-sm;bg surface-2;mono 10.5;ink-2}` `views.css:699-710` | `ExpenseEditor.ets:572-591` | 虚线框 + mono 10.5 的整句预览 | 裸 `Row`，10px 文本，无框/虚线/底/mono | 中 |
| W39 | 快捷分类胶囊条 | C.8 `.quick-cats{gap:6;overflow-x:auto;padding 6 2;bg surface-3 60%}` + `.quick-cat{padding 5 10;radius 999;11.5/600;is-on accent 圈}`；规范 §4.6 R101/R103「常用分类为胶囊 + 底槽」 | 全仓无（`ExpenseEditor.ets:6` 注释还写着「常用分类快捷条」，实现里没有） | 底部槽内横滑胶囊，含 `cat-ic 16` | 不存在 | 中 |
| W40 | 分期开关 | C.8 `.set-row 分期：set-ic + set-body(set-t/set-s) + select.input[width 84] + switch`；规范 §4.6 R113 | `ExpenseEditor.ets` 无「分期」（`grep 分期` 无命中，仅 `VectorRunner` 有算法） | 分期行 + 期数选择 + 开关 | 不存在（分期能力在 UI 上完全不可达） | 中 |
| W41 | 键盘数值 | C.8 `.keypad{grid-template-columns:54px …}`、`.key{border 2 line;radius 11;无阴影}`、`.key--fn{font-body 11/700;ink-2}`、`.key--ok{font 12 body}` `views.css:655-697,899-903` | `ExpenseEditor.ets:458`（62 宽）、`477`（border 1）、`478`（额外 `2px 2px 0` 硬阴影）、`471`（功能键 13/19）、`474`（OK display 族） | 54 列宽 / 2 描边 / 无阴影 / 功能键 11 body / OK 12 body | 62 / 1 / 有硬阴影（自创） / 13、19 / 13 display | 中 |
| W42 | 分类/支付选择器 | C.8 `.picker{min(660,100vw-20);max-h 86dvh;border 2 line-2;radius r-card}`、`.picker-body{grid 94px 1fr}`、移动 `.picker-grid` **2 列**、`.picker-cell{padding 9;border 2;radius 10;11.5/600}`、`.pay-item{padding 10 12;border 2;radius r-md;is-on shadow 2px 2px 0}` `views.css:549-612,781-782,910` | `ExpenseEditor.ets:613-659`（内联 Row：rail 88、**3 列**、cell 无描边 radius 6）、`662-691`（内联 List：padding 8、无描边、radius 6） | 独立弹层面板（94px 一级轨 + 2 列网格 + 描边单元） | 抽屉内联展开、3 列、无描边、无弹层层级 | 高 |
| W43 | 登录 / 初始化页 | C.7 `.login-page{padding 24 16;居中}`、`.login-card` = `card--pop`（`border 2 line-2;radius r-card;shadow 8px 8px 0`）、`.login-brand`（brand-mark 56 + name 20 + sub mono 9）、`.field-l{mono 9.5;uppercase}`、`.login-form{gap 12}` | `LoginPage.ets:87-99`（标题 26 + 12 副标，无品牌图标）、`100-119`（只有 placeholder，无 `field-l`）、`224-226`（`padding 20`、`justifyContent Start`、无卡容器） | 居中的 pop 卡片 + 品牌块 + 字段小标 | 无卡片、无品牌图标、无字段标签、左上对齐、`padding 20` | 高 |
| W44 | cyber 切角四档 | A.5 `theme.css:148-152` 卡 14 / 按钮 7 / orb 6 / logo 8 的 `clip-path`；规范 §6.4「cyber 用 `clipShape(Path)` 复刻 polygon」 | `UiStyle.ets:120-128` 有 `CUT_CARD/CUT_BTN/CUT_ORB/CUT_LOGO` 与 `cutPathCommands()`，但 **全仓 0 引用** | cyber 下 4 档切角 | 全部直角（`radiusOf` 归 0 就是"方角"，不是切角）——cyber 缺最关键的一眼识别特征 | 阻断 |
| W45 | 顶卡 / 控制行吸顶行为 | C.2 顶卡与工具栏都在 `div.stack` 内**随页面滚走**；规范 §0.1 D8「三入口随内容滚走、不吸顶」、D13「**只有逾期时**顶卡吸顶」 | `LedgerScreen.ets:1073-1114`（`topCard()`/`controlRow()` 在 `List` 之外，`monthListView` 才 `layoutWeight(1)` 滚动） | 常态随滚；逾期才吸顶 | 顶卡 + 控制行 **恒吸顶**（列表单独滚），与 Web 相反，也与 D8/D13 相反 | 中 |
| W46 | 数字等宽覆盖 | B.14 `.mono/.stat-v tabular-nums`；规范 §5.1 R39 | `LedgerScreen.ets:899-902`（行金额）、`DashboardScreen.ets:274-277`（指标值）、`ReportScreen.ets:361,392`（对照值）、`SettingsScreen.ets:450` | 所有金额/百分比/日期走 mono | 多处未加 `fontMonoOf()`（列宽随字形跳动，判据 29 只能过一半） | 低 |

> 非纯视觉但同源（docs 明写、Web 有，代码没有，供后续排期）：
> 支付方式行的**「合并」入口**（C.6 / R135 / FI#78–79，`SettingsScreen.ets:438-472` 无）；
> 分类行**停用/删除**约束（R87–R89，`SettingsScreen.ets:386-412` 只有点击编辑）；
> 报表明细的**「加载更多」之外的空态与「清除筛选」按钮**（R64，`LedgerScreen.ets:820-861` 无空态分支，只有列表 + 一个底部按钮）。

---

## 二、按 §0.1 声明属"按 docs 实现"的项（确认不误判）

下表是逐条比对 D1–D22 与代码的结论。**"≠ Web"不报缺陷**；只有"连 docs 也没做到"才转入 §一。

| # | 主题 | 代码实现位置 | 判定 |
|---|---|---|---|
| D1 | 月档无组头 | `LedgerScreen.ets:831-836` 直接 `ForEach(sortedRows())`；`grouped()`(314-326) 已死代码，未渲染 | ✅ 按 docs（但文件头注释 6 行仍写"按消费日分组 + 日小计"，与 D1 矛盾，建议改注释） |
| D2 | 只写「日」 | `LedgerScreen.ets:919-921` `${day}日` | ✅ 按 docs |
| D3 | 行内字段顺序 | `LedgerScreen.ets:918-926`：支付方式 · 日 · `M月D日刷 · M月D日还 · N天` | ✅ 按 docs（顺序、文案格式都对） |
| D4 | 无"还款日"药丸 | `LedgerScreen.ets:899-902` 右端只有金额 | ✅ 按 docs |
| D5 | 合计仅在有筛选时 | `LedgerScreen.ets:823-829`（`activeFilterCount()>0` 才渲染） | ✅ 按 docs |
| D6 | 三入口与控制行同行靠右 | `LedgerScreen.ets:591-610`（`Blank()` 后三个 `Text`） | ✅ 按 docs |
| D7 | 三入口不定宽/无选中态/纯文字 | `LedgerScreen.ets:593-610` 12px `ink3` 无背景无边框 | ✅ 按 docs；⚠️ 同文件 `659-672` 的 `navBtn()` 仍是"等宽胶囊"（死代码、未调用），**建议删除以免将来误用**（F32） |
| D8 | 三入口只在流水页、随内容滚走 | 只在流水页 ✅；"随内容滚走" ❌ | ⚠️ 一半（见 W45） |
| D9 | 搜索独占一行并撑满 | `LedgerScreen.ets:697-719`（第一行 `TextInput layoutWeight(1)` + 筛选） | ✅ 按 docs（形态细节另计 W15/W19） |
| D10 | 二级页 `×` 在标题行行尾 | `MainPage.ets:79-100`（19px、`ink3`、不单占行、不吸顶、触达 40×40） | ✅ 按 docs |
| D11 | 顶卡两态 | `LedgerScreen.ets:365-434`（无待办时左列 `layoutWeight(1)` 独占，右格不渲染） | ✅ 按 docs |
| D12 | 提醒默认收起、向下展开、不记忆 | `LedgerScreen.ets:81`（`todoOpen=false`）、`448-495`（在流内展开）、状态不持久化 | ✅ 按 docs |
| D13 | 只有逾期时吸顶 | 无吸顶判据，恒吸顶 | ❌ 见 W45 |
| D14 | 移动概况不放构成堆叠条 | `DashboardScreen.ets:284-321` `composition()` 已存在但**未被 build 调用**（`426-457` 无引用） | ✅ 按 docs（建议删死代码） |
| D15 | 设置不挂数据区 | `SettingsScreen.ets:807-815` 四 tab = 账目/计划与还款/外观/家庭；无导入导出/快照/危险区 | ✅ 按 docs |
| D16 | 主题三档并跟随系统 | `SettingsScreen.ets:677-681` + `ThemeManager.setMode('dark'|'light'|'system')` | ✅ 按 docs（形态细节 W27） |
| D17 | 主题入口只在设置 | 外壳无主题按钮（`MainPage.ets:124-153`） | ✅ 按 docs |
| D18 | 圆角令牌（卡 24/输入 14/胶囊 999） | 输入 14 ✅、胶囊 999 ✅；**卡 = 20** | ❌ 卡不成立 → W02 |
| D19 | 分类图标存 kebab-case 名字 | 无图标解析链；设置里"图标"是**单个字符**输入（`SettingsScreen.ets:938-939` 注释"先用 1 个字符代替"），行内也渲染首字 | ❌ 见 W12/W13 |
| D20 | 支付方式不给图标选择器 | 确实没有图标选择器 ✅；但"按类型推断图标"（cash→banknote / credit→credit-card）也没做（`SettingsScreen.ets:440` 用名称首字） | ⚠️ 一半（并入 W12/W29） |
| D21 | 记一笔唯一入口 = 下拉 | 无 FAB、无底部"＋记一笔"、无空态按钮；`LedgerScreen.ets:1127-1139` 下拉手势 | ✅ 按 docs（阈值 80 vs Web 54，属细节，见下） |
| D22 | 无底栏无顶栏 | `MainPage.ets:124-153` 只有品牌条 + 内容 + 戳 | ✅ 按 docs |

> 另外确认**不算缺陷**的 §0/§1 声明项：装饰层不实现（A.6 → 全仓无 deco，✅ 按 R38/F12）；
> fontMono 恒 JetBrains Mono（`UiStyle.ets:85-87`，✅ 按 §1.3）；环图 stroke 16（`DonutChart.ets:43`，✅ 按 §2）；
> 徽位 44（`LedgerScreen.ets:871-872`，✅ 按 R138）；紧急度竖条 4×2 / 高 20（`LedgerScreen.ets:453-457`，✅ 按 views.css:437-441）；
> 卡阴影移动端 `3px 3px 0 #E9EEF6`（`UiStyle.ets:51-56` `mobile=true` 分支，✅ 按 §1.1-4）。
>
> 顺带（不在 §0.1，但同样按 docs 属正确）：概况/报表**没有**页首大数字与「共 N 笔」（R86）、报表**没有**四维 chips（R77 用环图+排名）、
> 年档格内**没有**柱状条（R59）、日历**没有**图例（R61）——这几处在 Web 里都有，代码按 docs 删掉是对的。

---

## 三、结论

### 3.1 一致度

以 B 节 32 个小节 + C 节 7 屏为骨架，抽取 **118 条**可静态核对的视觉事实（颜色/间距/字号/圆角/描边/阴影/组件形态/交互阈值）：

| 维度 | 条数 |
|---|---|
| 一致（含按 docs 覆盖 Web 的 22 条） | 72 |
| 偏差合计 | 46 |
| ├ 阻断 | **4** |
| ├ 高 | 13 |
| ├ 中 | 26 |
| └ 低 | 3 |

**原始一致度 ≈ 61%（72/118）**。按严重度加权（阻断×5 / 高×3 / 中×1.5 / 低×0.5 扣分）后的**有效还原度 ≈ 27%**
——原因是偏差高度集中在"卡片/按钮/图标的原子层"，即**一个 token 错会被 7 张卡放大**。

### 3.2 阻断数：**4**

| 阻断 | 内容 | 为什么阻断 |
|---|---|---|
| B1 = W25 | 设置页 4 类表单弹层（分类/支付/计划/成员）**根本没有挂载**（`sheetContent()` 无 `bindSheet`） | M1–M3 弹层不可达 → 判据 36 与 FI#77/#78 无法验收，且点击"无反应" |
| B2 = W12 | 图标体系整类缺失（Lucide `.ic` / PCatIcon / PPayIcon / chevron / 搜索 / 退格） | docs D19/D20/R137/R138 明写图标；现为文字字符 → 行卡、设置、键盘、选择器全部"看起来不像 Web" |
| B3 = W44 | cyber 切角四档未实现（`CUT_*` + `cutPathCommands` 全仓 0 引用） | 规范 §6.4「必须 `clipShape`」；cyber 主题的识别特征整类缺失（判据 17 的"随主题变"只剩圆角/阴影） |
| B4 = W06 | 顶卡环比胶囊缺失（且正数无 `+` 号、用红绿染色） | 规范 §4.1 明写「顶卡内**必须有**环比胶囊」；同时撞 R25/R27（涨跌不许靠染色） |

### 3.3 修复优先级建议（按"每单位工作量消除的偏差数"排序）

1. **令牌层 3 处**（`densityPad→14`、`rCard→24`、卡片描边改回 `line`）：一次改动消除 W01/W02/W03/W04 影响面 → 7 张卡。
2. **抽 3 个原子组件**：`Card`（含 `card-h/card-t/card-cap`）、`Btn`（含 `--sm`/描边/硬阴影）、`Icon`（若近期接不上图标库，至少先把"首字徽位"换成占位图形并补齐 chevron 的 14px 尺寸）→ 消除 W10/W13/W12/W31 的主干。
3. **补 2 个缺失物**：`Toast`（W24）与 `cutPathCommands` 接线（W44），都是"写了没用"的状态，接上即得分。
4. **设置页 `bindSheet`**（W25）——单点、影响"能不能用"，建议最先做。
5. **环图几何对齐**（W35：176 / r-12 / 2.5 弧长 / 中心两行字）与**顶卡阴影 + 环比胶囊**（W05/W06）。

### 3.4 备注

- 本轮只审"docs 沉默处"的视觉事实；§一 中凡带「规范 §x」依据的条目，说明该项 docs 也已规定，属**双重不达标**。
- 数值口径：CSS px 与 ArkUI vp 按规范 §6.1 视为 1:1，故所有"vp vs px"比较均直接对比，不做密度折算。
- Web 审计 E 节的 21 条"无法确定项"（如 E2 品牌图标实尺寸、E4 `color-mix` 具体色值、E5 dvh/安全区）**未列入偏差**；代码在这些点上的取舍（`mixHex`、`SheetSize.LARGE`）视为可接受近似。
