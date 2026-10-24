# 终审轮：`hw-ui-spec.md` × 鸿蒙端实现（修后现状）

- **对象**：`docs/design/hw-ui-spec.md`（476 行，§7 实为 **40** 行判据，文首自称 38 条）vs `hw-native/entry/src/main/ets/`（**33** 个 `.ets`，**9245** 行）
- **审计性质**：**只读**。除本文件外未改动任何源码/文档
- **基线**：`docs/design/audit/recheck2-spec-vs-app.md`（阻断 5+2）。本轮逐条核实"已修"声明；**凡声明与代码不符的照报"没修好"**
- **严重度**：
  - **阻断** = §7 判据不通过 / 违反 §7.1 禁止项 / 功能做错（数据口径错、入口指向错表单、部件不可用）
  - **重要** = 规范明文结构或功能要件缺失
  - **次要** = 数值、文案、死代码、适配/一致性偏差
- **限制**：静态读码 + `grep` 定位，未编译、未真机 dump；需截图量测的判据（30）与需双端对账的判据（38）如实标"无法静态判定"

---

## 一、上一轮阻断与"已修"声明的核实

> 结论列只有四种：**已修好** / **部分修好**（列出仍缺的那一半）/ **没修好** / **无法静态判定**。

| 编号 | 声明内容 | 结论 | 证据 `file:line` |
|---|---|---|---|
| **判据 19 / G01** | 两段式下钻：点一次只切下方卡、不换页 | **已修好**（位置有偏差，见 §二 m01） | `components/ledger/LedgerScreen.ets:1221-1244`（`selectedCellSummary()`：显示 `selectedCell` + `¥rowSum()` + 「进入 →」）、`:1197-1207`（月格首点只 `selectedCell=…` 并 `loadMonth`）、`:1270-1280`（年格同）、`:1454`（`tier===1‖2` 时渲染该卡）、`:1234`（`进入 →` → `tier=0`） |
| **判据 23 / G05** | 洞察 3 / 3 / 2 条 | **没修好** | 汇总档已**正确**返回 2 条（`ReportScreen.ets:132-139`），但**年档恒为 2 条**：`yearly` 只填 `this.year`、不清 `this.report`（`:58-64`），进年档时 `report===null` → 走 `:141-148` 分支只 push「本年合计 / 最高月」→ `:149` `slice(0,3)` 得 2 条；若先看过月档则 `report` 非空 → 返回 **3 条月档内容**。同一档位随访问路径变 |
| **判据 28 / G03** | 离线文案并入计划卡区、只由 pendingSync 驱动、stamp 带待同步 | **部分修好** | 位置 ✓ `LedgerScreen.ets:602-609`（在 `topCard()` 内部）、驱动 ✓ `:603`（`if (this.pendingSync > 0)`，`offline` 不再参与）；**stamp 仍无「离线 / 待同步 N」**：`pages/MainPage.ets:128-137` 仅 `SuenMoney · 单账本家庭记账`（`:127` 注释「含离线/待同步内联提示」与实现矛盾） |
| **判据 29 / G02** | 全局 tabular-nums / 数字统一 `fontMonoOf()` | **没修好** | 全仓 `fontFeature` 仅 **2 处**：`LedgerScreen.ets:559`、`DashboardScreen.ets:425`；其余金额/百分比裸写 `fontSize` 无 `fontFamily`（`DashboardScreen.ets:277-280` 三指标、`:298-312` 热力格、`ReportScreen.ets:490-493/519-535` 对照四格、`LedgerScreen.ets:720-735` `heroFact`、`SettingsScreen.ets:380/410` 笔数） |
| **判据 36 / G04** | 分类停用、二级折叠、支付「本月 N 笔」+ 行内「合并」+ 二次确认 | **部分修好** | ✓ 支付行有「本月 N 笔」`SettingsScreen.ets:485/490`；✓ 支付行有行内「合并」`:500-512`；✓ 二级分类行有「停用」`:421-433`。**✗ 二级不能折叠/展开**（全仓 `折叠\|collapse\|expand` 仅注释命中 3 处）；**✗ 一级分类行无「停用」**（`:371-390` 只有名称 + 笔数）；**✗ 合并无二次确认、无「历史记录归属过去」提示**（`:302` 与改名同一次保存静默串联）→ 判据 36 仍**不通过** |
| **G06** | 筛选合计按结果集 + 金额区间在线生效 | **已修好**（备注见 m22） | `LedgerScreen.ets:1048-1054`（`filteredTotal()` 遍历 `this.rows`）、`:1080`（`筛选结果 ${this.rows.length} 笔 · 合计 ${filteredTotal()}`）、`:240`（在线路径也过 `applyAmountFilter`）、`:326-361`（离线路径本地过滤含 min/max） |
| **G07** | 「添加成员」改走成员表单 | **没修好（阻断）** | `SettingsScreen.ets:1040-1046`：`sheetContent()` 仍只有 `category / payment / else→planForm()` 三支，`member` 落进 `else`；`memberForm()` 定义在 `:1305` 但**零调用**（`grep "this.memberForm"` → 0）。保存键虽加了 `member` 分支 `:1068-1069` → `saveMember()` `:214-236` 读 `formUsername`，而 `planForm()` 里没有该输入 → 必报「登录名必填，口令至少 6 位」。**添加成员仍不可用** |
| **R117 / R116** | 提醒行字段顺序 + 多急文案；紧急度排序 | **已修好** | 顺序（金额→期次·名称→多急→状态→按钮）：`LedgerScreen.ets:554-599`；多急文案 `:656-670`（`逾期 X 天 / 今天 / 还有 Y 天`）；排序 `:285-290`（`daysUntil` 升序，逾期为负自然置顶）。备注：设置「待处理」行未按此口径（m10） |
| **R126** | 跨月撤销警告 | **没修好** | ① 数据源不存在：`Api.ets:299-300` 的 `expenseMonth` 服务端**不下发**（`server/src/db/repo/plans.ts:217-241` `toTodoApi()` 无该字段，全仓 `grep expenseMonth server/src` → 0）→ `SettingsScreen.ets:765-767` 的 `crossMonth` 恒 false；② 即便有值也弹不出：`confirmRevert()` `:744-757` 只把 `revertDialogOpen=true` 并 `await` 一个永不 resolve 的 Promise，而全仓**没有任何对话框渲染 `revertDialogOpen`**（`grep revertDialogOpen` 仅 :73/:752）→ 会永久挂起 |
| **R121** | 计划卡分类图标 | **部分修好** | 解析链已接：`SettingsScreen.ets:562`（`categoryGlyph(plan.categoryIcon ?? '', plan.categoryName ?? plan.name)`）；但服务端计划列表不下发 `categoryName/categoryIcon`（`server/src/db/repo/plans.ts:278-298` `toPlanApi()` 无此二字段），而客户端**没有用 `plan.categoryId` 查本地字典兜底**（对比 `LedgerScreen.ets:408-414` 有兜底）→ 实际显示的是**计划名首字**，不是分类图标 |
| **R134** | 图标解析链（`common/ui/CategoryIcon.ets`） | **部分修好** | 链本身在 `common/ui/CategoryIcon.ets:96-119`（显式 kebab → 名称反查 → 首字兜底，禁止 Emoji ✓）；**只接了 2 处**（`LedgerScreen.ets:1161` 流水徽标、`SettingsScreen.ets:562` 计划卡），**抽屉未接**（`ExpenseEditor.ets` 无 import，分类面板只渲染名称 `:745-780`）；另有死分支 `CategoryIcon.ets:114-117`（同一 `if` 重复两遍） |
| **R103** | 常用分类胶囊条 | **已修好**（缺「底槽」，见 m15） | `ExpenseEditor.ets:473-495`（`quickBar()`，胶囊 + 选中态）、`:494-506`（`quickCats()` 按本月笔数前 6）、`:833`（`noteFocus` 为假时渲染在键盘上方） |
| **R35** | 备注焦点环 | **没修好** | `ExpenseEditor.ets:646-655` 有焦点态，但用的是 **accent 2vp 边框**，不是 R35 指定的 `2px #5DB8FF + 2px offset`；`common/ui/UiStyle.ets`（163 行）**无 `FOCUS_RING` 常量**，全仓 `grep 5DB8FF` → 0 |
| **R98** | 登录页三槽 + 连通点 + 测试/保存/同步 | **已修好** | `pages/LoginPage.ets:30-33`（三槽 + 三态）、`:196-219`（固定 3 槽行 + 连通点）、`:221-251`（测试 / 保存 / 同步）、`:192-194`（技术细节文字已删）。备注：`ensureFonts` 仍未调用（m13） |
| **R144** | 离线文案并入计划卡区、只由 pendingSync 驱动 | **已修好**（stamp 例外见判据 28） | `LedgerScreen.ets:602-609`；旧的行内挂载点已删除（全仓 `已存本机` 仅此 1 处 UI）；断网静默 ✓ `:186-197`（网络错只置 `offline`，不写 `errorText`） |
| **R76** | 年档 7 块（服务端 yearly 已返回 categories/paymentMethods/members，客户端已接） | **年档已修好 / 汇总档没修好** | 年档 7 块 ✓ `ReportScreen.ets:237-246`（构成/支付/记录人/节奏/年度对照/涨跌/洞察）；数据源 ✓ `:78-105`（`categories()/payments()/members()` 三档分派）+ `common/net/Api.ets:228-247` + 服务端 `server/src/db/repo/reports.ts:125-137`；**汇总档仍 4 块**（`:231-236`：年度对照/节奏/洞察/跨度），规范 5 块且清单是「分类构成/支付排名/记录人排名/节奏(按年)/洞察 2 条」→ 见 M02 |
| **R82** | 汇总档按年柱 | **已修好** | `ReportScreen.ets:403-418`（`this.summary.years` 逐柱 + 「共 N 年」） |
| **R83** | 去年同月真实值 | **已修好**（年档四格仍错，见 M03） | `ReportScreen.ets:196-197`（`r.yearAgo.totalCents`）+ `common/net/Api.ets:209-210` + 服务端 `server/src/db/repo/reports.ts:677`（真算 `shiftMonthString(month,-12)`） |
| **R85** | 汇总档洞察 2 条 | **已修好**（年档 3 条未成立，见判据 23） | `ReportScreen.ets:132-139`（`tier===2` 走 `summary` 独立生成） |
| **R128** | 概况「本月要还」卡 | **已修好** | `DashboardScreen.ets:411-434`（`creditCard()`）+ `:512`（月档渲染）+ `:436-448`（信用类笔数）；网格顺序 hero→本月要还→进度→热力→累计 `:511-520` |
| **R136** | 二级颜色跟一级 | **已修好** | `LedgerScreen.ets:390-406`（子分类优先取 `parent.color`，再自身，再哈希） |
| **R118** | 「自动入账」状态词 | **部分修好** | 流水顶卡展开行 ✓ `LedgerScreen.ets:570`（`自动入账 / 需手动`）；计划卡 ✓ `SettingsScreen.ets:575-578`；**设置「待处理」行无状态词**（`:669-720` 只有「确认 / 入账」按钮） |
| **R77** | 图例前 6 + 其他 | **已修好**（「可展开二级图例」未做，见 m29） | `ReportScreen.ets:100-119`（前 6 + 其余合并「其他」、`ink3` 中性色）、`:363-378`（图例渲染） |
| **F01** | 说明式文字清理 | **已修好** | 全仓 `Text` 字面量 ≥10 字者仅 4 条（`ReportScreen:616` 空态、`SettingsScreen:823` 版本、`:1155` 颜色继承约束、`MainPage:130` stamp），均为"约束/空态"允许项；无「因为…所以」「越深＝花得越多」类句子 |
| **F19** | 去「游标」 | **没修好（并命中禁止项）** | 字符串仍在 `SettingsScreen.ets:129`（`推送 N · 拉取 N · 游标 ${report.cursor}`），只是 `syncMessage` **从未被渲染**（`grep syncMessage` 仅 :103/:125/:127）→ 同步结果用户永远看不到；同时 `:832` 渲染 `待发送 ${pendingCount} 条` → 命中 F19「待发送队列」数值（详见 B06） |

**小结**：声明 26 项 → **已修好 13**（判据 19 / G06 / R117+R116 / R103 / R98 / R144 / R76 年档 / R82 / R83 / R85 / R128 / R136 / R77 / F01）、**部分修好 5**（判据 28、判据 36、R121、R134、R118）、**没修好 7**（判据 23、判据 29、G07、R126、R35、F19、R76 汇总档）。

---

## 二、仍存在缺口

### 2.0 三项"特别审查"结论

| # | 审查项 | 结论 |
|---|---|---|
| **S1** | **§2 原子组件层是否落地** | **未落地**。仓库**没有 `components/ui/`**（`ls components` → `BrandMark.ets` + 4 个屏目录 + `report/DonutChart.ets`）；`common/ui/UiStyle.ets` 只有数值/函数工具（`cardShadow / radiusOf / mixHex / outlineStrongOf / cardRadiusOf / CARD_PAD`），**没有任何 Card/Input/Seg/Switch/Orb/Stat/Toast/Bar 组件**。按钮高度实测 **24/26/28/30/32/36/38/40/42/44** 十档混用（`.height(26)`×15、`.height(32)`×12、`.height(28)`×9…），无一处满足 §2 `min-height:38 + padding:8 16 + border:2 line-2 + pill + 3px 硬阴影`；`Seg` 无「胶囊外框 padding:3 + 2vp outline-strong」；`Switch` 用系统 `Toggle`（无 `42×24 + 2vp outline-strong`）；**`Orb` 组件在全端不存在**；`Stat` 三处各写一套（`LedgerScreen:720-735` / `DashboardScreen:275-285` / `ReportScreen:521-528`）；`Toast` 见 m21；`Bar` 见 m30；`Donut` 尺寸 160≠**176**（`DonutChart.ets:90-91`，stroke 16 ✓、段间 2.5° ✓、中心分类数 ✓）；顶卡缺 §2 要求的 `shadow:4px 4px 0 line-2`（`LedgerScreen:453-645` 无 `.shadow`） |
| **S2** | **每个新增方法是否真的被 UI 调用** | **5 个新方法只写没接**：`SettingsScreen.memberForm()`（:1305，0 调用 → B04）、`ReportScreen.yearBar()`（:653，0 调用 → 死代码）、`LedgerScreen.grouped()`（:374，0 调用）、`LedgerScreen.tierButton()`（:848，0 调用）、`DashboardScreen.actTodo()`（:106，0 调用）+ `maxHeat()`（:377）/`heatOpacity()`（:588）。另有**写了状态但没渲染**：`SettingsScreen.syncMessage`/`vectorReport`/`schemaReport`/`revertDialogOpen`/`pendingResolve`、`DashboardScreen.todos`/`todoOpen`/`TodoView` |
| **S3** | **`CategoryIcon.ets` 是否在 流水徽标 / 计划卡 / 抽屉 三处都接上** | **2/3**。流水徽标 ✓ `LedgerScreen.ets:1161`；计划卡 ✓ `SettingsScreen.ets:562`（但数据源错，见 R121）；**抽屉 ✗**（`ExpenseEditor.ets` 无 import；分类面板 `:745-780`、支付面板 `:790-825` 只有名称文字，无图标���。另：设置页分类行也没有徽位（`SettingsScreen.ets:371-440`，见 M08） |

### 2.1 阻断（6）

| 编号 | 位置 | 缺什么 / 错什么 | 严重度 |
|---|---|---|---|
| **B01** | `components/report/ReportScreen.ets:129-149`、`:231-236` | **判据 23 不通过**：年档洞察清点只有 2 条（规范 3 条），且内容随"是否先看过月档"变化（`this.report` 不随档位重置）。**同一屏两种结果**，属功能做错而非单纯少一条 | **阻断** |
| **B02** | 全仓（`grep fontFeature` = 2 处） | **判据 29 不通过**：R39 的全局 tabular-nums 等价实现未做，金额/百分比/日期绝大多数裸写 `fontSize` 无 `fontFamily` → 「同一数字在等宽列中宽度一致」不成立 | **阻断** |
| **B03** | `components/settings/SettingsScreen.ets:371-440`（一级/二级分类行）、`:302`（合并） | **判据 36 不通过**：① 二级分类**不能折叠/展开**（R/FI#77 明文）；② **一级分类行没有「停用」**（只有二级有）；③ 支付方式**合并无二次确认、无「历史记录会归属过去」提示**（FI#78/#79） | **阻断** |
| **B04** | `components/settings/SettingsScreen.ets:1040-1046`、`:1305-1352` | **G07 未修**：「添加成员」仍渲染「新建计划」表单（`sheetContent()` 无 `member` 分支），`memberForm()` 死代码 → 保存必报「登录名必填」→ **成员无法新增** | **阻断** |
| **B05** | `components/settings/SettingsScreen.ets:485`、`:490`；根因 `server/src/db/repo/payment-methods.ts:105-110` | **数据口径错**：支付行写「**本月** N 笔」，但 `expenseCount` 是**全部历史**笔数（服务端子查询无月份条件）→ 与 §4.4 L279「本月笔数」口径不符，用户会看到"本月 37 笔"而本月只有 3 笔 | **阻断** |
| **B06** | `components/settings/SettingsScreen.ets:832-845` | **禁止项 F19 命中**：设置页渲染「待发送 N 条」+「立即同步」，即 F19 明列的"待发送队列"技术细节。注：§5「死信/同步失败必须可见」不在 F19 列举项内，**死信区 `:848-861` 可保留**，只需把"待发送 N 条"改成无数字的状态词（或移到流水页计划卡，与 R144 同源） | **阻断** |

### 2.2 重要（14）

| 编号 | 位置 | 缺什么 / 错什么 | 严重度 |
|---|---|---|---|
| **M01** | §2 全节；`common/ui/UiStyle.ets`（全文）；各屏内联 | **§2 原子组件层未落地**（详见 S1）：无组件目录、按钮 10 档高度、无 Seg/Switch/Orb/Stat/Toast/Bar 组件、Donut 160≠176、顶卡无 4px 硬阴影 → §2「ArkUI 侧一一对应」无法验收 | **重要** |
| **M02** | `components/report/ReportScreen.ets:231-236`、`:78-105` | 汇总档**仍 4 块**（年度对照/节奏/洞察/跨度），规范 5 块应为「分类构成/支付排名/记录人排名/期内节奏(按年)/洞察 2 条」；且 `categories()/payments()/members()` 在 `tier===2` 时返回**月报**（未看月档则为空）→ 即使补块也无数据 | **重要** |
| **M03** | `components/report/ReportScreen.ets:519-535` | 年档对照四格口径错：规范是「去年 / 近 3 年均值 / 最高月 / 单笔最高」，实现给的是「全年合计 / 月均 / 最高月 / 笔数」；服务端已下发 `yearAgo`(:751) 与 `average3YearsCents`(:134) 却未用 | **重要** |
| **M04** | `components/settings/SettingsScreen.ets:744-770`；`common/net/Api.ets:299`；`server/src/db/repo/plans.ts:217-241` | **R126 跨月撤销警告不生效**：① 服务端不下发 `expenseMonth` → 判据恒 false；② `confirmRevert()` 无任何对话框渲染 `revertDialogOpen`，一旦数据到位会**永久 await**（撤销按钮点下去无反应） | **重要** |
| **M05** | `pages/MainPage.ets:128-137` | §3 L177 要求的 build-stamp「含 离线 / 待同步 N」仍缺；`:127` 注释与实现矛盾 | **重要** |
| **M06** | `components/expense/ExpenseEditor.ets:745-825` | 抽屉未接图标解析链（S3）；分类面板二级项、支付面板项都没有图标/色点，与流水行 44 徽位视觉断层 | **重要** |
| **M07** | `components/settings/SettingsScreen.ets:371-440`、`:1129-1136` | §4.4 L281（R137/R138）：设置分类行**无 44px 徽位**、无图标、图标列不定宽；图标录入仍是 `TextInput('图标（单个字符）')`（无 kebab 名、无选择器/无预览） | **重要** |
| **M08** | `components/ledger/LedgerScreen.ets:554-599`（`grep Gesture` 仅 :1492 下拉） | §4.7/§4.7.2（R65）移动端提醒手势**整块未实现**：无左滑（确认/入账）、无右滑（忽略）、无 72px 阈值、无「松开确认/松开忽略」换词（行内等价按钮在 ✓，所以不受"可达性"追责，但手势是明文要件） | **重要** |
| **M09** | `components/settings/SettingsScreen.ets:669-724` | 设置「待处理」行未按 R117 口径：金额不在前（在第二行与日期并列）、**无「多急」**、**无「自动入账/需手动」状态词** → 与流水顶卡两套提醒行口径不一致 | **重要** |
| **M10** | `components/dashboard/DashboardScreen.ets:58-84`、`components/report/ReportScreen.ets:54-73` | §5.2 A 档「断网时列表/**概况/报表**用本地库现算」未做：两屏都不 import `ExpenseDao`，断网只显示"上次返回的数据"（内存）或空（`Dashboard:69`「离线：仅显示服务端上次返回的数据」）；只有流水页有本地现算（`LedgerScreen:193-198`） | **重要** |
| **M11** | `components/settings/SettingsScreen.ets:286-306`、`:1160-1180` | 支付方式「合并」入口点开的是**普通编辑表单**（不是独立合并流程），合并在保存时与改名/改账期**静默串联执行**，无二次确认、无历史归属提示（同 B03③，此处记为"入口语义错"） | **重要** |
| **M12** | `pages/LoginPage.ets:21`、`:39-47`、`:139-265` | R98 之外的登录页要件仍缺：`ensureFonts` **引入未调用**（首屏字体回落系统）；根 `Column` 定高**无 `Scroll`** → 键盘弹起不能整体上移（§4.5 L288）；**无 M5 服务端地址弹层**（§4.7.1，地址编辑是页内常驻） | **重要** |
| **M13** | `components/ledger/LedgerScreen.ets:1391`、`:648-654`、`:1462-1469` | §2 Toast 形态：轻提示是主 `Column` **流内一段文字**（位置随内容、挤在顶卡与档位之间），无 `4px 4px 0 rgba(0,0,0,.18)` 硬阴影、无 `2vp line-2` 边、不做底部悬浮；设置页/登录页仍无 Toast（同步/死信只有内联文字） | **重要** |
| **M14** | `components/settings/SettingsScreen.ets:735-880` | 设置「外观」区仍是"主题 + 贴图徽章 + 待发送/死信 + 退出登录"的混合体：**「检查更新」无占位**（`grep 检查更新` → 0，§4.7.1 明文"代码里必须留位"）；多出规范未列的「退出登录」；家庭区仍只有成员，**无「登录设备」「我的账号」** | **重要** |

### 2.3 次要（29）

| 编号 | 位置 | 缺什么 / 错什么 |
|---|---|---|
| **m01** | `LedgerScreen.ets:1454` | 判据 19 的"下方那张卡"渲染在**月格/年格上方**（`build()` 里排在 `monthGridView()` 之前），与 R58「下方那张卡」的字面位置不符（机制已通） |
| **m02** | 全仓 | 死代码 9 处：`grouped()`、`tierButton()`、`memberForm()`、`yearBar()`、`Dashboard.actTodo()/maxHeat()/heatOpacity()`、`Settings.vectorReport/schemaReport`、`LinearBar` 无；死状态 4 处：`syncMessage`、`revertDialogOpen/revertPendingResolve`、`Dashboard.todos/todoOpen` |
| **m03** | `SettingsScreen.ets:524`、`:723`、`:957` | 三张**卡片**描边仍用可交互边界色 `outlineStrongOf()`（语义错位，同屏其他卡用 `tok().line`） |
| **m04** | `DashboardScreen.ets:331`、`:404` | 热力卡/累计卡仍用 `tok().rCard`（20，cyber 下 2），与同屏 hero/进度卡的 `cardRadiusOf()`（24/0）不一致 |
| **m05** | `UiStyle.ets:120-128` | cyber 切角四档只有 `CUT_CARD` 被用（`LedgerScreen:1430-1432`）；`CUT_BTN/CUT_ORB/CUT_LOGO` **零调用**；`cutPathCommands()` 与 `cyberClipCommands()` 函数体完全相同且前者无人用 |
| **m06** | `components/report/DonutChart.ets:90-91` | 直径 160 ≠ 规范 176（stroke 16 / 段间 2.5 / 中心分类数 ✓） |
| **m07** | `LedgerScreen.ets:453-645` | 顶卡缺 §2 规定的 `4px 4px 0 line-2` 硬阴影；padding 14 ✓、border 2 line-2 ✓、radius 24 ✓、gap 12 ✓ |
| **m08** | `components/BrandMark.ets:25-81`；`SettingsScreen.ets:820` | LOGO 第三形态（单色）仍缺；设置页徽章仍是静态贴图 `app.media.layered_image`，未复用 `BrandMark` → 同一端两种 LOGO |
| **m09** | `SettingsScreen.ets:380` | 一级分类笔数缺单位「笔」（二级有，`:429`） |
| **m10** | `ExpenseEditor.ets:552` | 完成键键面仍是 `OK`，规范/判据要「完成」 |
| **m11** | `ExpenseEditor.ets:511-540` | 支付快捷列 `slice(0,4)`；**2 项时不放大平分**、空位不补「更多」（只有 >4 才有「更多」）；快捷键名仍是硬编码 + `substring(0,2)` |
| **m12** | `LedgerScreen.ets:81`、`:143-153` | R115「下拉可记账」提示仍是内存态、未落 Preferences（MainPage 用 if/else 换屏会重建组件 → 每次回流水页都提示） |
| **m13** | `common/theme/ThemeManager.ets:41`、`:44` | 首启默认档仍 `'dark'`（R130 要求未显式选择时**实时跟随系统**）；三档与 system 监听本身正确 |
| **m14** | 全仓 `grep animateTo\|Curve\.\|animation(` → 0 | 无动效曲线/时长（§0.1 D18 `cubic-bezier(.2,0,0,1)` + 200/350/400ms）、无「减少动态效果」降级（R133） |
| **m15** | `ExpenseEditor.ets:473-495` | 常用分类无 R103 的「**底槽**」（只有一行胶囊，无凹槽底板） |
| **m16** | `UiStyle.ets`（163 行）；全仓 | R35 焦点常量 `FOCUS_RING`（`#5DB8FF` + 2px offset）**不存在**；除备注框外全局无焦点态 |
| **m17** | `common/contract/Contract.ets:137`；`DashboardScreen.ets:18`、`SettingsScreen.ets:21` | `urgencyLabel()` 仍写「已逾期 N 天」（R49 精简口径要「逾期 N 天」），且两屏都**只 import 不调用**（死导入） |
| **m18** | `LedgerScreen.ets:1312`、`:1376` | 年档永远 3 列、全部档永远 2 列（R60 只要求窄屏 3×4，宽屏应放宽） |
| **m19** | `LedgerScreen.ets:1210-1219` | R46 窄屏让位（≤460vp 先让账期）未实现：`subline()` 无条件拼账期段，只能靠省略号截断 |
| **m20** | `DashboardScreen.ets:139-146` | R69「每月前 3 天改为 `—` **并注明数据太少**」：只做了 `—`，没有注明 |
| **m21** | `LedgerScreen.ets:884-930`、`:926-947` | R62/R63：排序（按日期/按金额）仍**常驻在折叠面板之外**；筛选按钮**无状态圆点、无数量**（`activeFilterCount()` 只用于换底色） |
| **m22** | `LedgerScreen.ets:1080`、`:1048-1054` | 「筛选结果 N 笔 · 合计」只统计**已加载页**（首屏 100 笔）；筛选命中 >100 时条数与合计偏小 |
| **m23** | `DashboardScreen.ets:200-204` | 概况 hero 大金额 cyber 下仍 `tok().ink`，未按 C01 用 `--accent`（流水顶卡已正确 `LedgerScreen:487`） |
| **m24** | `LedgerScreen.ets:755-817` | §4.7.1 **L3 期间面板**整层仍缺：无年份 chip、无 12 月格 3×4、「回本月/回今年」`grep` → 0（控制行只有 `‹ 2026-10 ›` + 三档 chip）；三档 chip 与期间/三入口塞进同一 Row，390vp 下已接近满宽 |
| **m25** | `common/net/Api.ets:486-517`；`LedgerScreen.ets:226-236` | R62「搜索支持**跨期**」未做：`Api.expenses()` 恒带 `month`，服务端 `server/src/http/expenses.ts` 的 `from/to` 未接 |
| **m26** | `docs/design/hw-ui-spec.md:419`、`:424-465` | 判据自称「38 条」但表格实为 **40 行**（编号顺序 1–29、39、40、30–38），规范自身待勘误 |
| **m27** | `common/ui/CategoryIcon.ets:114-117` | `categoryGlyph()` 同一条 `if (glyph !== undefined)` 重复两遍（死分支）；`resolveIconKey()` 兜底返回 raw icon，再由 `ICON_GLYPH` 查不到 → 链尾语义含糊 |
| **m28** | `SettingsScreen.ets:991-999` | 设置四 tab 用 `Row` 固定四等分，**不是** §4.4「移动端横滑」（`settings-tabs` 形态） |
| **m29** | `ReportScreen.ets:363-378` | R77「**可展开**二级图例」未做：图例是平铺前 6 行，无展开/收起（环图本身 ✓） |
| **m30** | `ReportScreen.ets:268-300`、`:520-535` | §2 `Bar` 规范（轨道 `height 9 + border:1 line`、半高圆角、旁边必须有数字）：多数占比条无 1vp 描边；年档对照四格无数值对比条（R36 数字 ✓ 在） |
| **m31** | `LedgerScreen.ets:150-153`、`:604` | `pendingSync` 只在 `aboutToAppear` 取一次；抽屉保存（离线入队）后不刷新 → 计划卡上的「待同步 N 条」不即时更新 |

**计数**：**阻断 6**（B01–B06）+ **重要 14**（M01–M14）+ **次要 31**（m01–m31）= **51 项**。

---

## 三、§7 判据逐条（40 行）

| # | 判据 | 结论 | 证据 / 说明 |
|---|---|---|---|
| 1 | 无底栏、无吸顶顶栏；顶部无标题/记一笔/主题 | **通过** | `pages/MainPage.ets:139-164`（品牌条 + 内容 + stamp；`grep Tabs/BottomNavigation` → 0） |
| 2 | 三入口与期间同一行、靠右、不定宽、无选中态 | **通过**（备注） | `LedgerScreen.ets:755-817`（同一 Row + `Blank()` + 三个裸 `Text`，无背景/选中态）。备注：间距 8（规范 12）、触达高非 44；三档 chip 同排致 390vp 接近满宽（m24） |
| 3 | 三入口只在流水页 | **通过** | 概况/报表/设置三屏 `grep "概况/报表/设置"` 只命中注释与文件头 |
| 4 | 二级页关闭为 `×` 收在标题行行尾 | **通过** | `MainPage.ets:94-115`（`Row{标题, Blank, ×}`，19px `ink3`，非独占行、不吸顶） |
| 5 | 月档列表无组头 | **通过** | `LedgerScreen.ets:1094-1099`（直接 `ForEach(sortedRows())`）；`grouped()` 为死代码（m02） |
| 6 | 行内日期只写「日」、含账期段 | **通过** | `LedgerScreen.ets:1210-1219` → `支付方式 · 28日 · 9月12日刷 · 28日还 · 16天` |
| 7 | 行内无「还款日」药丸 | **通过** | 行卡区 `:1158-1208` 无「还款」胶囊 |
| 8 | 合计仅在有筛选时显示 | **通过** | 条件 `:1079`；数值改用结果集 `:1048-1054`（G06 已修） |
| 9 | 顶卡两态 | **通过** | `:453-520`（右半格 `if (heroTodos.length > 0)`，否则左列 `layoutWeight(1)` 独占） |
| 10 | 提醒默认收起、向下展开、不记忆 | **通过** | `:83`（`todoOpen=false`）、`:490-497`（内联展开、无持久化） |
| 11 | 仅逾期时顶卡吸顶 | **通过** | `:1442-1445`（`hasOverdue()` 时渲染在滚动区外）+ `:1092-1096`（否则作 List 首项）+ `:1446-1450`（年/全部档不重复，G08 已修） |
| 12 | 触底「加载更多」/ 无更多「查看上月」 | **通过** | `:1124-1139`（`hasMore ? '加载更多' : '查看上月'`） |
| 13 | 概况视图内不出现分类名 | **通过** | `DashboardScreen` 全文无 `categoryName`；hero 只有金额/环比/三指标 |
| 14 | 报表环图中心为"分类数" | **通过** | `ReportScreen.ets:354`（`centerLabel: ${categories().length} 类`） |
| 15 | 设置不含数据区 | **通过** | `grep 导出\|导入\|备份\|快照\|危险区 components/` → 仅注释 |
| 16 | 抽屉：5 列键盘、横滑禁用、跨月提示、本月已支出 | **通过** | `ExpenseEditor.ets:508-587`（支付列 62 + `Divider().vertical` + 4×4 Grid）、`:695-703`（`这笔会记在`）、`:805-811`（本月已支出 + `—`）；全文件无 `Scroll` |
| 17 | 主题三档 + 全局生效 + 字体/圆角/阴影随主题变 | **通过**（备注） | `ThemeManager.ets:66-99`（三档 + 广播）、各屏 `@StorageLink(THEME_STORAGE_KEY)`；`fontDisplayOf/fontBodyOf`、`cardRadiusOf`(24/0)、`cardShadow`(3px/cyber 0) 随主题。备注：首启默认 dark 不跟随系统（m13） |
| 18 | 日历格只给量、四档明度、0 值只描边、选中描边不填充 | **通过** | `LedgerScreen.ets:1008-1023`（四档 `mixHex`）、`:1283-1290`（0 值 `Color.Transparent`）、`:1291-1294`（选中 2vp accent 描边）；格内仅文本 |
| 19 | 两段式：点一次只切下方卡、不换页 | **通过**（备注） | `:1197-1207`/`:1270-1280`（首点只选中+`loadMonth`）+ `:1221-1244`（卡随 `selectedCell` 变）+ `:1454`（渲染）。备注：卡在格**上方**（m01） |
| 20 | 窄屏年档 3×4 | **通过** | `:1312` `repeat(3, 1fr)` × 12 月格。备注：宽屏不放宽（m18） |
| 21 | 报表无页首大数字与「共 N 笔」 | **通过** | `ReportScreen.ets:275-300`（只有档位 chip + 期间） |
| 22 | 还款节奏月档两段、年/汇总隐藏 | **通过** | `ReportScreen.ets:251-254`（仅 `tier===0`）+ `:556-575`（本月已刷 / 下月要还两段独立取值） |
| 23 | 洞察 3 / 3 / 2 条 | **不通过** | 年档 = 2 条且随"是否看过月档"变内容 → **B01**（`ReportScreen.ets:129-149`） |
| 24 | 分类行只给笔数、一级累计子类 | **通过**（备注） | `SettingsScreen.ets:380`（`root.expenseCount`，服务端 `categories.ts:96-108` 已按子类累计）、`:429`（二级 `N 笔`）；无金额。备注：一级缺「笔」（m09） |
| 25 | 自动入账期次不出现「忽略」 | **通过** | `LedgerScreen.ets:580-595`、`SettingsScreen.ets:704-717`（均 `if (!willAutoPost)` 包装） |
| 26 | 编辑态软删二次确认、保存键禁用态 | **通过** | `ExpenseEditor.ets:402-432`（`AlertDialog`）、`:882`（`.enabled(!saving && canSave())`） |
| 27 | 设置含外观（主题三档）+ 品牌徽章 | **通过**（备注） | `SettingsScreen.ets:779-846`。备注：徽章为贴图、缺「检查更新」（M14/m08） |
| 28 | 离线文案在计划提醒卡区域、断网不弹错 | **通过**（备注） | `LedgerScreen.ets:602-609`（顶卡内、`pendingSync>0` 驱动）+ `:186-197`（网络错静默）。备注：build-stamp 仍缺待同步（M05） |
| 29 | tabular-nums 生效 | **不通过** | 全仓 `fontFeature` 仅 2 处（`LedgerScreen:559`、`Dashboard:425`）→ **B02** |
| 30 | 卡底空白 ≤40vp | **无法静态判定** | 需真机截图量测 |
| 31 | 提醒行只有计划名可截断 | **通过** | `LedgerScreen.ets:554-599`（计划名 `layoutWeight(1)+maxLines(1)`；金额/多急/状态/按钮不设省略、不设固定宽） |
| 32 | 三档三形态 | **通过** | `:1459-1465`（列表 / 12 月格 / 年格） |
| 33 | 日历无图例、无「越深＝花得越多」 | **通过** | `grep 图例\|越深` → 0 |
| 34 | 热力 12 个月、格内金额、无记录 `—`、窄屏 6×2 | **通过** | `DashboardScreen.ets:294-326`（`repeat(6, 1fr)`、`formatYuan`、`'—'`、`height(2*50)`）；数据源 `rolling12Months` |
| 35 | 提醒展开区每条都有动作 | **通过** | `LedgerScreen.ets:498-599`（每条：确认/入账 + 更多→忽略）。备注：手势态缺失（M08）不影响本判据 |
| 36 | 分类停用/删除约束、二级折叠、支付合并与本月笔数 | **不通过** | 二级不能折叠、一级行无停用、合并无二次确认（B03）；且「本月 N 笔」数字口径错（B05） |
| 37 | 判据落在"期"级：`willAutoPost = plan.auto_post && !hold_auto_post` | **通过** | 服务端 `server/src/db/repo/plans.ts:231`；客户端两处均用 `todo.willAutoPost`（`LedgerScreen:570`、`SettingsScreen:700`） |
| 38 | 金额整数分、日期字符串、月份按还款日归属 | **无法静态判定** | 静态部分符合：`Contract.ets` 整数分换算、日期全 `YYYY-MM-DD`、账期由 `POST /api/expenses/preview` 给（`ExpenseEditor:376-390`）；"与 web 同月逐笔一致"需双端对账 |
| 39 | 累计条通栏一行、不含金额、四项齐全 | **通过** | `DashboardScreen.ets:405-409`、`:501-510`（`已记 N 天 · M 笔 · 平均 A 笔/天 · 首笔 <date>`） |
| 40 | 键盘恰好 16 格（15 键 + 完成跨两行）、无空格子 | **通过** | `ExpenseEditor.ets:544-575`（`KEYPAD_KEYS` 15 键 + `OK` 占 `rowStart:3,rowEnd:4,column:4`） |

**小结**：**通过 35 / 不通过 3（#23、#29、#36）/ 无法静态判定 2（#30、#38）**。

### §7.1 禁止项抽查

F01 说明式文字 **0**（仅空态/约束/版本 4 条合法字面量）· F07 组头 **0**（`grouped()` 死代码）· F09 概况构成条 **0** · F18 移动数据区 **0** · **F19 待发送队列数值 命中 1**（`SettingsScreen.ets:832`「待发送 N 条」→ B06；「游标」字符串在 `:129` 但未渲染）· F32 等宽三入口 **0** · F34 自造页面 **0**（设置表单为页内态，无新页面/新弹层；M12 的 M5 缺失属"缺"不属"多"）· F35 判据下沉 **0** · F36 跳过复用 **0** · F12 装饰层 **0** · F13 结余/收入/预算卡 **0** · F21 卡底空白 **无法静态判定** · F24 日历格内塞图表 **0** · F33 收入/多账本/币种/标签/附件控件 **0** · F14 分享/海报 **0** · F15 日历第二色相 **0** · F17 数据 tab 版式 **n/a** · F27 桌面顶栏动作 **0** · Emoji **0**（Unicode 扫描 0 命中）· 系统数字键盘 **0**（自绘键盘在位）· 横向滑块 **0**。

→ **禁止项命中 1**（F19），其余 0；F21 留真机。

---

## 四、结论

- **判据通过率**：**35 / 40 = 87.5%**（40 行口径；若只算可静态判定的 38 行 → **35/38 = 92.1%**）。上一轮 31/38 = 81.6%，本轮 +4 条（#19、#28 转通过，#23/#29/#36 仍卡）。
- **阻断数 = 6**：
  1. **B01** 判据 23（年档洞察 2 条，且随访问路径变内容）
  2. **B02** 判据 29（tabular-nums 仅 2 处）
  3. **B03** 判据 36（二级不可折叠 / 一级无停用 / 合并无二次确认）
  4. **B04** 添加成员仍打开"新建计划"表单 → 成员无法新增（上轮 G07，未修）
  5. **B05** 支付方式「本月 N 笔」实为全部历史笔数（数据口径错）
  6. **B06** 禁止项 F19：设置页出现「待发送 N 条」队列数值
- **重要 14 / 次要 31**。分布最集中的两块仍是 **§2 原子组件层（整层未落地，M01）** 与 **§4.4 设置行动作/口径（B03/B05/M07/M11/M14）**；本轮新增的重量级发现是 **R126 跨月警告双断链（M04，含"若数据到位会永久挂起"）** 与 **概况/报表断网无本地现算（M10）**。
- **交付判断**：**不可放行**。三条判据不通过 + 两项"一点就错"的功能缺陷（成员新增直接失败、支付行笔数口径错）+ 一条禁止项。修完 B01–B06 后剩下的 14 项重要缺口仍足以让"§2 一一对应"与"设置页功能完整"两条验收口径无法签字，建议把 M01/M02/M03/M04/M05 一并收口后再做一次真机 dump（届时补判据 30/38 与 m01 的位置确认）。
