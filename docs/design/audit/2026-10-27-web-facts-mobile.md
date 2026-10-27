# SuenMoney Web 前端 · 移动端事实清单（@media max-width:860px）

> 只陈述代码事实，每条带 `文件:行号`。路径相对 `/home/suenmoney/web/`。

## 0. 生效条件与层叠

| 事实 | 依据 |
|---|---|
| 断点 860px（媒体查询） | `app.css:721`、`views.css:772/859/919/990/1113/1126`、`base.css:105`、`ExpenseSheet.vue:683` |
| 外壳 JS 侧同断点 | `App.vue:135`（`matchMedia('(max-width: 860px)')`） |
| 根路径落地页：移动 → 流水，桌面 → 概况 | `router/index.ts:17,23` |
| 样式顺序 theme → app → views → base（base 最后且用 `!important`，覆盖前两者） | `styles/index.css:2-5`、`base.css:105-117` |
| views.css 有 6 个 860 块，后者覆盖前者同权重规则 | `views.css:772,859,919,990,1113,1126` |
| 主题令牌：浅=candy / 深=cyber（`--accent` #8B5CF6 / #00ff88；`--r-card` 20px / 2px；`--border-w` 2px / 1px） | `theme.css:30-77,80-131` |

## 1. 外壳 `src/App.vue`

**结构顺序（移动端，自上而下）**

| # | 块 | 依据 |
|---|---|---|
| 1 | `RouterView`（`login` 等 `meta.public` 路由，不套外壳） | `35,160` |
| 2 | `.app` 根（`data-theme` / `data-decor=on` / `data-density=cozy`）+ `.deco` a~d | `162-167` |
| 3 | `.sidebar` = **品牌条**（BrandMark 46px + `SuenMoney`）；`.nav` / `.nav-cap` / `.side-foot` 隐藏 | `170-206`；隐藏见 `views.css:1115`、`app.css:736,741` |
| 4 | `.topbar`：仅「返回」图标按钮（`route.name !== 'ledger'`）；流水页整条 `.topbar--bare` 不渲染 | `210-217`、`base.css:111-113` |
| 5 | `.content` 内 `.pull-hint`（模板有、移动端隐藏） | `234-236`、`base.css:114-117` |
| 6 | `.pull-bar`（`v-if="pull > 0"`，下拉过程出现） | `237-239` |
| 7 | `<RouterView>` 页面（page 过渡） | `241-245` |
| 8 | `.build-stamp`（正文流末尾，非固定） | `247-251` |
| 9 | `PToast` → `ExpenseSheet` 抽屉 | `256,258-263` |

**文案**（`App.vue` 行号）

| 文案 | 移动端可见 |
|---|---|
| `SuenMoney`(174)、`FAMILY LEDGER · 单账本`(175) | 前者是；后者否（`app.css:736`） |
| `账目`(180) / `概况`·`流水`·`报表`·`设置`(37-42,190) | 否（`views.css:1115`、`app.css:741`） |
| `离线（点击重试）`·`同步中…`·`待同步 N 笔`·`已同步`·`只记支出 · 整数分`·`SYNC`(197-203) | 否（`.side-foot`，`app.css:741`） |
| 顶栏标题 `概况`/`流水`/`报表`/`年度报告`/`设置` + 副标题 `OVERVIEW · 本月支出与待办提醒` 等(45-51,219-220) | 否（`base.css:106-110`） |
| 主题按钮 aria `切换到水果硬糖`/`切换到赛博朋克`(225)、`记一笔`(228) | 否（`base.css:107-110`） |
| `返回报表`/`返回流水`（返回按钮 aria+title，215） | 是 |
| `下拉记一笔`(235，hint) | 否（`base.css:114-117`） |
| `下拉记一笔` / `松开记一笔`（pull-bar，238，按阈值切换） | 是（手势中） |
| `SuenMoney · 单账本家庭记账 · {buildStamp}` + ` · 离线模式` / ` · 待同步 N`(248-250) | 是 |

**关键样式值（移动端生效）**

| 项 | 值 | 依据 |
|---|---|---|
| 外壳栅格 | 桌面 `244px + 1fr` → 移动单列 | `app.css:6-11` / `app.css:722` |
| `.sidebar` 品牌条 | `sticky; top:0; z-index:60;` `flex-wrap:wrap; gap:8px 10px;` `background:var(--bg);` `blur(10px);` `padding:8px 14px 6px;` 底边 1px | `views.css:860-871,1114` |
| 品牌字号 / LOGO | `.brand-name` 15px/700（桌面 20px）；LOGO 46px（`.logo-ph` 规则不适用，组件是 `<img>`） | `views.css:1117`、`App.vue:172,279-285`、`BrandMark.vue:12,20` |
| `.topbar` | `padding:8px 12px; gap:8px;` sticky、`z-index:30`、`blur(14px)` | `views.css:1118`、`app.css:182-190` |
| `.content` | `padding:6px 12px 64px; gap:12px; max-width:1280px` | `views.css:1121`、`app.css:757,238-247` |
| `.card` | `padding:14px; border-radius:16px; box-shadow:3px 3px 0 #E9EEF6`；cyber 下 `radius:0; shadow:none` | `app.css:759-760` |
| `.pull-bar` | 高=`pull`px(0–84)，`color:var(--accent)`，11px/700，`transition:height .15s` | `app.css:703-713` |
| `.pull-hint` | 9.5px mono、字距 .16em、大写、`var(--ink-3)`、药丸 30×14px | `app.css:683-702` |
| `.build-stamp` | 10px mono、字距 .06em、`opacity:.55`、居中、`padding-top:18px` | `base.css:46-54` |
| z-index 阶梯 | topbar 30 / sidebar 60 / scrim 80 / sheet 81 / modal 91 / picker-mask 95 / toast 120 | `app.css:173`、`views.css:863`、`app.css:561,571,597,627`、`views.css:549` |

**交互**

| 交互 | 条件 | 依据 |
|---|---|---|
| 下拉记一笔（**唯一新建入口**） | `scrollY ≤ 2` 按下；位移 > 8px 跟手；阻尼 0.62、上限 84px；松手 `pull ≥ 54` → `ui.openCreate()` | `71-73,85-103` |
| 返回 | 非流水页显示；`annual-summary` → 报表，其余 → 流水 | `66-68,212-217` |
| 主题切换 `toggleTheme` | cyber ⇄ light/dark（移动端按钮被隐藏） | `61-63,223-227` |
| 安卓返回键 | 抽屉开→先关抽屉并消费事件 | `121-133` |
| 切回前台 | 静默检查更新 + `sync.runSync()` | `115-118` |
| 抽屉保存回调 | `@saved` → `ui.markDataChanged()`（dataVersion+1，300ms 后调度同步） | `262`、`stores/ui.ts:45-52` |

**数据来源**：`__BUILD_STAMP__`(32)；`useSyncStore` 的 `isSyncing/isOnline/hasPending/pendingCount`(28,197-199,249-250)；`useUiStore` 的 `sheetOpen/editingExpense`(27,259-260)；`useTheme().proto`(30,162)。

## 2. 流水 `src/views/LedgerView.vue`（移动端落地页）

**结构顺序**

| # | 块 | 移动端 | 依据 |
|---|---|---|---|
| 1 | `.mobile-hero`：期间+本月支出大数 / 环比 / 三事实 / 三入口 / 待办条 | 仅移动 | `374-421` |
| 2 | 工具栏卡 `.ledger-toolbar`（搜索 + 折叠 `.lt-adv`） | 显示，`.lt-adv` 默认收起 | `424-451`、`views.css:1000-1001` |
| 3 | 筛选行（`showFilters`） | 显示 | `454-490` |
| 4 | 构成四维卡 `CompositionCard` | **隐藏**（`desktop-only`） | `496-498`、`app.css:777` |
| 5 | 月档「流水明细」卡：`.m-list` 行卡（桌面表格隐藏） | 显示 | `501-627`（`512` 表格 desktop-only，`577` 行卡 mobile-only） |
| 6 | 年档 12 月格 / 全部档一年一格 | 显示 | `630-655` / `658-685` |

**文案**

| 文案 | 依据 |
|---|---|
| `{月份} · 本月支出`；`日均`·`笔数`·`本月要还`；`概况`·`报表`·`设置` | `376,385-387,391-393` |
| `{N} 笔待办`·`{N} 笔逾期`·`自动`/`需手动`·`{periodSeq}期 · {planName}` | `405-417` |
| `搜索备注或分类`(429)、`收起`(432)、`按月`·`按年`·`全部`(35-39)、`上一期间`·`下一期间`(439,441)、`筛选`/`筛选 · N`(444)、`按日期`·`按金额`(447-448)、`分类`·`支付`·`记录人`·`全部`·`清除`(456,468,479,457,488) | 同左 |
| `流水明细`·`{N} 笔 · 合计 ¥X`(503-504)、`加载中…`·`没有符合条件的流水`(507-508)、`退款`(600)、`即时`/`{MM-DD} 还`(613)、`加载中…`·`加载更多`·`查看上月`(621,624) | 同左 |
| 年档 `{year} 年`·`合计 ¥X`·`本月`·`{n} 笔`(632-647)；全部档 `全部记录`·`{n} 年 · 合计 ¥X`·`还没有任何记录`(660-663) | 同左 |

**关键样式值（移动端生效）**

| 项 | 值 | 依据 |
|---|---|---|
| `.mobile-hero` | `padding:14px; border:2px solid var(--line-2); radius:20px; shadow:4px 4px 0; gap:12px` | `views.css:1012-1022` |
| `.mh-eyebrow` / `.mh-amt` / `.cur` | 9.5px mono 大写 `.14em`；38px/800 `.035em`；`0.48em` | `views.css:1031-1043` |
| `.mh-facts` / `.mh-fact` | 3 列、`gap:8px`、`padding:9px 0`、上下 1px 虚线；标签 9px / 值 11px/700 | `views.css:1046-1056` |
| `.mh-nav` / `.mh-btn` | 3 列 `gap:6px`；按钮 `min-height:30px`（覆盖 44px）、`padding:0 4px`、11.5px、`border:1px var(--line)`、`background:var(--surface-2)`、999px | `views.css:1085-1099`、`LedgerView.vue:703-715` |
| `.hero-todo` 待办条 | `padding:7px 10px; margin-top:10px; radius:9px; 11.5px` | `LedgerView.vue:728-750` |
| `.date-cap` / `.m-row` / `.m-row-t` | 10.5px mono `padding:12px 4px 6px`；`padding:10px; gap:8px; 2px 边框; radius:14px`；12.5px 600 | `views.css:189-201,204-219,930-931` |
| `.cal-year-grid` / `.year-cell` | 4 列 → **移动 3 列**；`padding:12px 10px`、`y-m`15px、`y-v`11px mono | `views.css:223-237` / `views.css:777` |
| `.period-label` | 14px display 700；桌面 min-width 116px → 移动 scoped 76px | `views.css:176-183`、`LedgerView.vue:692-699` |
| `.filter-l`（筛选组标签） | 移动 `width:100%` 独占一行 | `LedgerView.vue:804-809` |
| 空态 `.empty` | `padding:34px 10px`、12px、`var(--ink-3)`（无移动端变化） | `app.css:645-653` |

**交互**

| 交互 | 条件 | 依据 |
|---|---|---|
| 展开高级区（档位/期间/筛选/排序） | 移动端点 `.lt-search` → `advOpen=true`（`matchMedia 860` 判定）；`收起` 关闭 | `308-310,426-433`、`views.css:1000-1001` |
| 切档位 / 前后翻页 | `switchTier` 重拉明细+报表；`shift(±1)`，`全部` 档禁用 | `286-297,439-441` |
| 展开收起待办 | 点 `.hero-todo` 切 `todoOpen` | `397-420` |
| 点行进编辑 | `.m-row` → `ui.openEdit(row)` | `583-589` |
| 加载更多 / 查看上月 | `hasMore` 时前者，否则 `goPrevMonth()` | `620-625,140-142` |
| 年档下钻 / 筛选 chips / 搜索 | `drillMonth`；`PChip` 再点取消；`watch` 直接 `reload()` | `636-643,319-324,457-489,346-348` |

**数据来源**：`expenses.list()` `/api/expenses`（`limit=100`+cursor，`18,223-264`）；`reports.monthly/yearly/summary`（`266-284`）；`plans.dueTodos/loadDueTodos/loadPlans`（`30-31,192,300-306,357-361`）；字典 `rootCategories/usablePaymentMethods/colorOf`（`29,92,210-213`）；`users.list()`→`members`（`363`）。

## 3. 概况 `src/views/DashboardView.vue`

**结构顺序**（`.overview-grid` 12 列 → 移动 1 列，`views.css:991-992`）

| # | 块 | 依据 |
|---|---|---|
| 1 | 主卡 `.og-hero`：期间分段+翻页 / 待办条 / 大金额 / 环比 / 三指标 / 构成堆叠条+图例 / 展开的待办行（含 `确认`·`入账`·`更多`·`忽略本期`） | `288-362` |
| 2 | `.og-heat` 月度支出热力（12 格 → 移动 4 列） | `365-392`、`views.css:994-995` |
| 3 | `.og-cum` 累计与跨度 | `395-408` |
| 4 | `加载中…` | `410` |

**文案**

| 文案 | 依据 |
|---|---|
| `本月`·`本年`·`全部`(37-41)；`上一期间`·`下一期间`(293,295)；`全部记录`(297) | 同左 |
| `{N} 笔待办`·`{N} 笔逾期`·`自动`/`需手动`·`确认`/`入账`·`更多`·`忽略本期`(309-357) | 同左 |
| `较上月 ¥X`/`较去年 ¥X`/`较上一段 ¥X` + `{n}%`(319-323) | 同左 |
| 三指标：月档 `日均支出`·`笔数`·`预计月末`；年/全部档 `月均支出`·`笔数`·`最高月`|`记录跨度`(96-108) | 同左 |
| `月度支出热力`·`近 12 个月 · 点击下钻`·`{n}月`·`—`·`近 12 个月合计 ¥X`·`打开报表`(368-390) | 同左 |
| `累计与跨度`·`全部历史口径`·`历史累计`/`记录笔数`/`记录跨度`/`月均支出`/`单笔均值`(398-404,172-181)；`加载中…`(410) | 同左 |
| Toast：`已忽略这笔待办`/`已确认并自动入账`/`已手动入账`/`操作失败，请重试`(263-266) | 同左 |

**关键样式值（移动端）**

| 项 | 值 | 依据 |
|---|---|---|
| 栅格 / 热力格 | 1 列 `gap:12px`；热力 4 列、`.heat-cell{padding:7px 3px}` | `views.css:991-995,130-142` |
| `.hero-amt` | 桌面 `clamp(36px,5vw,52px)`/800 → **移动 34px**（概况主卡与年度报告都用该类） | `views.css:24-35` / `views.css:775` |
| `.delta-pill` | 10.5px mono/700、`padding:3px 8px`、1.5px currentColor 描边、999px | `views.css:43-53` |
| `.hero-metrics` / `.stat-v` / `.stat-l` | 3 列 `gap:10px` 上虚线；21px/700；10.5px `var(--ink-3)` | `views.css:55-63`、`app.css:464-474` |
| `.stack-bar` / `.compose-legend` / `.cl-item` | 高 9px 999px；`gap:6px 14px`；11px | `views.css:167,792-794` |
| `.hero-todo` | `padding:7px 10px`、`radius:9px`、11.5px | `DashboardView.vue:438-460` |

**交互**：`switchTier`(231-235)、`shift(±1)` 且 `全部` 档无翻页(225-229,292-297)、待办展开 `alertOpen`(301-314,342-361)、`todoAction(ack|confirm|skip)`→`plans.*`(257-269)、热力格 → `report?month=`(373-381)、`打开报表`(390)。

**数据来源**：`reports.monthly/yearly/summary`(237-251)；`plans.dueTodos/loadDueTodos/loadPlans`(155,272-276)；`dict.colorOf`→`--chart-1..8`(113-130)；热力色 `color-mix`(142-146)。

## 4. 报表 `src/views/ReportView.vue`

| # | 结构块 | 依据 |
|---|---|---|
| 1 | `.report-head`：档位分段+翻页+`{year} 年度报告` 按钮 + 事实条（`期间支出`/环比/`对比`/`日均`/`笔数`） | `200-234` |
| 2 | `支出构成`：卡头四维 chips + 环图或条形 + 图例列表（cap `分类 / 支付 / 记录人 / 节奏` 移动隐藏） | `237-290`、`views.css:1128` |
| 3 | `.report-pair` 两卡（≤1080 单列）：`涨跌榜`（cap `分类环比 · 按差额排序`）+ `还款节奏`（cap `近 6 个月 · 按账期`） | `294-334`、`ReportView.vue:371-375` |
| 4 | `.report-banner`：`{year} 年度报告已生成` / `年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势` | `337-349` |
| 5 | `加载中…` | `351` |

**文案**：`本月/本年/全部`(23-27)；`上一期间`/`下一期间`(204-206)；`{periodLabel}`=`全部记录`|`YYYY 年`|月标签(65-69)；`分类/支付/记录人/节奏`(105-110)；空态 `这个期间还没有构成数据`(253)；环图中心 `合计`(260)；`上期 ¥X`/`新增`(305-311)；空态 `该期间没有可对比的分类` / `切到「月」档看涨跌`(316)；结论句 `这个期间还没有记录，记一笔之后这里会自动生成结论。` / `头号开销是X，占 N%；整体多花/少花 ¥X（N%）。`(152-161)；`{n}月`(330)。

**关键样式值（移动端）**

| 项 | 值 | 依据 |
|---|---|---|
| `.report-head` / `.rf-num` / `.rf-i` | `padding:14px`；30px(`820`) → 26px(`881`)；11px(`822`) → 10.5px、`gap:8px 10px`(`880-883`) | `views.css:879-883,820-822` |
| `.report-pair` | 2 列 → ≤1080 单列、`align-items:stretch` | `ReportView.vue:362-375` |
| 构成 chips | 移动整行、不换行、横向滚动、隐藏滚动条 | `views.css:1129-1137` |
| `.compose-view` / `.donut` | 移动 `flex column` `gap:12px`；136px（同文件另有 148/150px） | `views.css:1140-1146,886,783` |
| `.legend-row`（构成列表） | 移动栅格 `9px / 1fr / 64px / 32px`、`gap:8px`、`padding:6px 0`、行间虚线 | `views.css:1148-1157` |
| `.report-note` / `.week-bars` / `.repay-steps` | 11px/1.7(`1162`)；7 列高 132px(`291`)→112px(`785`)、移动宽 100%(`1161`)；高 96px `gap:8px`(`321`) | `views.css:1162,291-304,785,321` |
| `.report-banner` | `padding:16px 18px`、2px 边框、`radius:20px`、渐变底、`shadow 5px 5px 0`、`rb-t`16px/800、`rb-s`11px | `views.css:338-354` |

**交互**：档位切换(169-173)、翻页(163-167)、四维 chips → `dim`(242-249)、进年度报告(209-216,337-342)。
**数据来源**：`reports.monthly(anchor)` + `reports.monthly(前一个月)`（涨跌榜）(175-191)、`reports.yearly`/`reports.summary`(181-183)、`paymentMethods/members/daily`(121-143)、`dict.colorOf`(80-87)。

## 5. 年度报告 `src/views/AnnualSummaryView.vue`

| # | 结构 / 文案 | 依据 |
|---|---|---|
| 1 | 年份卡：`上一年`·`下一年`（aria）+ 年份 + `返回报表` | `66-80` |
| 2 | `{year} 年度全貌`：`{n} 个月 · {n} 笔`、大金额、环比%、`去年 ¥X`、三指标 `月均`/`单笔均值`/`空月`(`{n} 个月`) | `83-101` |
| 3 | `12 个月走势`（cap `按还款日归属`），空态 `这一年还没有记录` | `104-132` |
| 4 | `.g2` 两卡（移动单列）：`最高支出月` / `单笔最贵`，空态 `没有数据` | `135-161` |
| 5 | `支出最多的分类`（cap `全年`，`v-if="topCategory"`） | `164-174` |
| 6 | `加载中…` | `176` |

**样式**：12 月柱区 `height:140px`、`gap:4px`、柱 `radius:3px 3px 0 0`、月号 9.5px mono(110,120-129)；大金额 `.hero-amt` 移动 34px(`views.css:775`)；最值数字 26px/800(142,155)；`.g2` 移动单列(`app.css:758`)。
**数据来源**：`reports.yearly(year)` → `totalCents/months/yearAgo/peakMonth/largest/categories/count`(24-57)；`route.query.year` + `router.replace`(20,43-46)。
**交互**：年份前后翻、点月柱 → `report?month=`、`返回报表`。

## 6. 设置 `src/views/SettingsView.vue`

**共 4 个 tab**（`59-64,804-813`）：`账目` / `计划与还款` / `数据` / `家庭`。移动端 tab 条：`overflow-x:auto` 无滚动条、`.stab{flex:0 0 auto; padding:7px 10px; font-size:11.5px}`、`gap:4px`、选中 `border-bottom:3px solid var(--accent)`（`views.css:875-877,932,935,461-473`）。

| tab | 卡（按渲染顺序） | 依据 |
|---|---|---|
| 账目 | ① `分类管理`（`新增类别`；左一级 rail + 右二级列表 + `编辑类别`/`删除`/`新增分类`；空态 `这个一级分类下还没有二级分类`；提示 `分类与支付方式均为软删除：已有流水引用时拒绝删除，只能停用。`）② `支付方式`（`新增`；`{n} 日账单 · {n} 日还款`、`合并`；空态 `还没有支付方式`） | `818-899` |
| 计划与还款 | ① `还款计划`（cap `进行中 N · 已结束 N`、`新建计划`、空态 `还没有计划`、`更多`/`终止计划`/`删除计划`）② `已处理 / 已忽略`（`v-if doneTodos.length>0`、`恢复`/`撤销`）③ `待处理期次`（cap `N 笔`、空态 `没有待处理的期次`、`确认`/`入账`/`忽略本期`） | `901-986` |
| 数据 | ① `主题` ② `导出`（`导出账本（JSON）`/`导出流水（CSV）`）③ `导入`（`选择 JSON 文件`/`导入中…`/`账单导入（微信 / 支付宝）`）④ `备份`（`下载备份文件`/`立即上传到 WebDAV`/`WebDAV 地址`·`用户名`·`口令（留空表示不改）`·`远端目录`·`启用 WebDAV 备份`/`测试连接`/`保存配置`）⑤ `数据库快照`（`创建快照`/`下载`/空态 `还没有快照`）⑥ `检查更新`（`v-if canCheckUpdate`，仅原生）⑦ `数据总览`（`v-if overview`）⑧ `关于`（`SuenMoney`/`一笔一笔，把家记清楚`/`单账本`·`整数分`·`只记支出`）⑨ `危险操作`（`清空全部数据`/`清空`、`重置为演示数据`/`重置`） | `988-1155` |
| 家庭 | ① `成员`（cap `N 人`、`添加成员`、空态 `还没有成员`、`管理员`）② `登录设备`（cap `N 个会话`、`其他设备退出`、空态 `没有会话记录`、`当前`）③ `我的账号`（`v-if me`：`显示名`+`保存`、`当前口令`、`新口令（≥8 位）`、`修改口令`、提示 `改口令后其他设备会被退出登录。`） | `1157-1218` |

**主题选择器（数据 tab 第 1 卡）**

| 事实 | 依据 |
|---|---|
| 3 个选项：`水果硬糖`(`浅色 · 贴纸硬阴影`)、`赛博朋克`(`深色 · 切角霓虹`)、`跟随系统`(`浅色 / 深色自动`) | `411-415,993-1009` |
| 每卡 = **大预览块** `.theme-prev`（高 56px，纯 CSS 仿界面）+ 12px/700 名称 + `tiny muted` 说明 | `1002-1006`、`views.css:749-756,810-812` |
| 栅格：基础 2 列 → `--3` 变体 3 列；≤860 的 2 列规则被更高权重的 `.theme-cards.theme-cards--3` 覆盖仍 **3 列**；**≤720 变 1 列** | `views.css:733,788,814,815` |
| 卡样式：2px 边框、`radius:14px`、`padding:10px`、选中 `shadow:3px 3px 0 var(--line-2)` | `views.css:734-748` |
| 写入：`themeChoice` → `theme.set('light'|'dark'|'system')` | `418-421` |

**其它移动端样式**：`.cat-admin` 2→1 列(`views.css:908`)、`.cat-rail` 横向换行(909)、`.plan-line` 2 列两行区+图标按钮 34px(892-897)、`.set-row` `gap:12px` `set-t`12.5px/600 `set-s`10.5px(`views.css:477-498`)。
**抽屉表单**（复用 `.sheet` 底部抽屉，`PSheet.vue:11-23`）：`编辑分类`/`新增分类`(`名称`/`图标`/`颜色`|`归属类别`，`保存`/`取消`)、`编辑支付方式`/`新增支付方式`(`名称`/`图标`/`类型`/`账单日`/`还款日`)、`合并支付方式`、`新建计划`(`名称`/`分类`/`支付方式`/`每期金额`/`期数`/`首期还款日`/`到期自动入账`，`创建`/`取消`)、`添加成员`(`登录名`/`显示名`/`初始口令（至少 8 位）`，`添加`/`取消`)、`BillImportModal`（`1223-1340,1219`）。
**数据来源**：`categories`/`paymentMethods`/`plans`/`planTodos`/`users`/`data.overview`/`snapshots`/`webdavBackup`/`auth`(20-34) + `dict.*` + `plansStore.*`。

## 7. 记账抽屉 `src/components/ExpenseSheet.vue`

**结构顺序（底部抽屉内，自上而下）**

| # | 块 | 依据 |
|---|---|---|
| 1 | `.scrim` 遮罩（点击关闭） | `377` |
| 2 | `.sheet-head`：标题 + 可选 `退款冲销`/`{n} 期免息` + 删除（编辑态）+ 关闭 | `379-386` |
| 3 | `.amt-display`（`-¥`/`¥` + 金额 + 支付方式名） | `390-394` |
| 4 | `.g2`：分类格 + 消费日期（原生 `date`）→ 支付方式格 | `396-427` |
| 5 | 备注输入 → 退款开关行 → 分期开关行（+期数 3/6/12/24） | `429-479` |
| 6 | `.preview-box` 金额预览 → 错误行 → `本月已支出` | `482-505` |
| 7 | `.quick-cats` 常用分类快捷条（最多 6 个胶囊） | `509-521` |
| 8 | 桌面金额输入框（移动隐藏）→ `.keypad`（`mobile-only`）：左支付列 5+`更多`，右 4×4 键盘含 `完成` | `524-576` |
| 9 | `.sheet-foot`：主按钮 + `取消` | `579-584` |
| 10 | 分类选择 `.picker`（rail+grid）/ 支付方式选择 `.picker`（纵向列表） | `588-663` |

**文案**

| 文案 | 依据 |
|---|---|
| `记一笔`/`编辑支出`(378,380)、`退款冲销`(381)、`{n} 期免息`(382)、`删除`/`关闭`(384-385) | 同左 |
| `分类`/`选择分类`(400,401)、`支付方式`/`选择支付方式`/`· 信用卡`(422-423)、`备注（选填）`(429) | 同左 |
| `退款（负数冲销）`+`退款不使用「收入」，直接以负数金额冲减本期支出`/`分期中的消费不能标记退款`(435-437) | 同左 |
| `分期（仅信用卡 · 非退款）`+`免息分期，每期金额自动四舍五入`/`当前支付方式不支持分期，请先切换到信用卡`(451-453)、`3 期`·`6 期`·`12 期`·`24 期`(464-467) | 同左 |
| `金额预览（不落库先算）：`、`这笔会记在 {月}（还款日 MM-DD）`、`还款日 MM-DD`、`本次计入 ¥X`、`每期约 ¥X，共 N 期`、`即时入账，消费日期 {date}`(483-495)、`本月已支出`(503) | 同左 |
| 键盘键面 `7 8 9 ← 4 5 6 清空 1 2 3 完成 0 00 .`（`B`→`←`、`C`→`清空`、`OK`→`完成`）(372,562-572)、支付列取前 4 字 + 固定 `更多`(546-557) | 同左 |
| 底部 `记下这笔`/`保存修改`/`保存中…` + `取消`(580-583) | 同左 |
| 错误 `请输入金额`·`请选择分类与支付方式`·`分期需要联网创建`·`保存失败，请重试`·`删除失败`(224,228,238,324,344) | 同左 |
| Toast `已记一笔 ¥X`·`已离线记一笔 ¥X`·`网络异常，已存入离线队列`·`已保存修改`·`已离线保存`·`已删除这笔记录`·`已创建分期计划`·`切到信用卡后才能分期`(257,272,282,292,307,316,340,473) | 同左 |
| 弹层 `选择分类`·`一级 N / 二级 N`(592-595)、`支付方式`·`账期随卡`·`信用卡 · {n} 日账单 / {n} 日还款`·`即时结算`(637-655) | 同左 |

**关键样式值（移动端生效）**

| 项 | 值 | 依据 |
|---|---|---|
| 抽屉定位 | 桌面右侧 500px → 移动**底部抽屉** `width:100%; height:93dvh; bottom:0`、`border-top:2px`、`radius:22px 22px 0 0`；cyber 下 `radius:0`、`border-top:1px var(--accent)` | `app.css:566-578,762-773` |
| `.sheet-head` / `.sheet-title` | `padding:12px 14px`（桌面 14px 16px）/ 15px（桌面 16px、cyber 13px 大写） | `views.css:921-922`、`app.css:580-588` |
| `.sheet-body` | `padding:12px; gap:10px; max-height:calc(93dvh - 124px)` | `views.css:904,920` |
| `.sheet-foot` | `padding:12px 16px` + `padding-bottom:calc(12px + env(safe-area-inset-bottom))`、顶部 1px 分隔 | `app.css:590`、`views.css:906`、`ExpenseSheet.vue:700-702` |
| `.amt-display` / 金额 | `padding:10px 12px`、底部 2px 虚线；`a-val` 34px（`views.css:923`）但组件 scoped `clamp(30px,7vw,44px)` 权重更高；`a-cur` 20px | `views.css:905,615-621,923`、`ExpenseSheet.vue:789-796` |
| `.preview-box` / `.month-spent` | 10.5px/1.65、1px 虚线框；`padding:2px 4px`、值 12px | `views.css:699-708,924`、`ExpenseSheet.vue:742-751` |
| `.quick-cats` | `flex; gap:6px; overflow-x:auto`（无滚动条）；`padding:6px 2px`；底槽 `color-mix(--surface-3 60%)`、`radius:9px` | `ExpenseSheet.vue:753-764` |
| `.quick-cat` | `flex:0 0 auto; padding:5px 10px;` 999px；11.5px/600；选中 accent 边 + 2px 外环 | `ExpenseSheet.vue:765-783` |
| `.keypad` 列宽 | 桌面 `62px + 1fr` → **移动 `54px + 1fr`**、`gap:6px`；scoped 覆盖 `gap:clamp(4px,1.1vw,7px)` | `views.css:655,899`、`ExpenseSheet.vue:684-686` |
| `.keys` | 4 列 × 4 行、`gap:5px`；`完成` 键 `grid-column:4; grid-row:3 / 5` | `views.css:676,693` |
| `.key`（数字） | views.css 移动 `min-height:46px; 16px`；scoped 覆盖 `min-height:clamp(38px,6.1dvh,54px)`、`font:clamp(15px,4.3vw,19px)`、`radius:clamp(8px,2.4vw,12px)` | `views.css:902`、`ExpenseSheet.vue:687-691` |
| `.pay-key`（支付列） | views.css 移动 `min-height:40px; 8px`；scoped 覆盖 `clamp(34px,5.4dvh,48px)`、`font:clamp(7.5px,2.1vw,9px)` | `views.css:901`、`ExpenseSheet.vue:692-695` |
| `完成` 键字号 | `clamp(11px,3vw,14px)`（views.css 12px） | `ExpenseSheet.vue:696-698`、`views.css:903` |
| 矮屏 `≤860×720` | 数字键 36px/15px、支付键 32px、金额 26px、**`.preview-box` 隐藏** | `ExpenseSheet.vue:706-720` |
| 极矮 `≤860×620` | **`.quick-cats` 与 `.month-spent` 隐藏**、数字键 32px/14px | `ExpenseSheet.vue:723-732` |
| `.picker` | `picker-body` 移动 94px + 1fr（桌面 132px）；`picker-grid` 移动 2 列（桌面 3 列） | `views.css:567,583,781-782,910` |
| `.sheet-cell` | `padding:10px 12px`、2px 边框、`radius:14px`、12.5px | `views.css:637-652` |

**交互**

| 交互 | 条件 | 依据 |
|---|---|---|
| **`完成` 键 = 保存** | `OK` 按钮 `@click="save"`，与底部主按钮同函数 | `562,580` |
| **底部独立按钮** | `.sheet-foot` 主按钮（`记下这笔`/`保存修改`）+ `取消`，**无任何移动端隐藏规则** | `579-584` |
| 保存分支 | 金额 0 / 未选分类·支付 → 报错；分期 → `plans.create`；新建 → `expenses.create`（离线落 outbox，`status 0` 也落）；编辑 → `expenses.update` | `221-328` |
| 删除 | 编辑态显示删除图标，直接 `remove()`，无二次确认 | `384,330-348` |
| 输入规则 | ≤9 位、小数 ≤2 位、`.` 唯一；`C` 清空、`B` 退格 | `202-219` |
| 退款/分期互斥 | 开退款 → `periods=null`；开分期 → 若退款则关掉；非信用卡开分期 → toast | `443,472-476` |
| 账期预览 | `watch([paymentId, spendDate])` → `expenses.preview()` | `197-199` |
| 常用分类 | 全部可选二级分类按服务端 `expenseCount` 降序取前 6（有引用的不足 3 则取前 6） | `365-370` |
| 记住上次选择 | `localStorage['suenmoney:last-pick']`，失效退回第一项 | `50-70,146-158` |
| 弹层 / 关闭 | 点格子开；遮罩/按钮/`取消` 关闭 | `397,417,588-663,377,385,583` |

**数据来源**：字典 `rootCategories/selectableChildren/usablePaymentMethods/findCategory/findPaymentMethod`(39,105,110,125-128,536,644)；`reports.monthly(currentMonth())`(165-172)；`expenses.preview/create/update/remove`(191,275,309,338)；`plans.create`(241)；`sync.addOfflineExpense/updateOfflineExpense/deleteOfflineExpense` + `sync.isOnline`(237,265,300,336)。

## 8. 登录 / 初始化 `src/views/LoginView.vue`

| # | 结构 / 文案 | 依据 |
|---|---|---|
| 1 | `.app.login-page` + 4 个 `.deco` | `105-109` |
| 2 | 品牌：`BrandMark(56)` + `SuenMoney` + `FAMILY LEDGER · 单账本` | `113-119` |
| 3 | 卡头 `初始化账本`/`登录` + cap `第一次使用`/`家庭共用`；提示 `创建第一个账号（管理员），之后可添加家庭成员。`/`用你的账号进入账本。` | `121-128` |
| 4 | 表单：`登录名`(`小写字母`)、`显示名`(仅 setup，`界面上显示的名字，如「我」`)、`口令（至少 8 位）`(`至少 8 位`) | `131-147` |
| 5 | 错误行 → 主按钮 `创建并进入`/`登录`/`处理中…` | `149-154` |
| 6 | 底部 `已有账号，去登录`/`首次部署？初始化账本`；`服务器设置` | `157-174` |
| 7 | 服务器区（**仅原生壳**）：`服务器地址`(`http://192.168.1.10:5310`) + `测试`/`测试中…` + `保存` + 结果标签 | `176-185` |
| 8 | 页脚 `{PLAYFUL 或 CYBERPUNK} · SuenMoney` | `188,44` |

| 关键事实 | 内容 | 依据 |
|---|---|---|
| 同一表单两模式 | 加载调 `auth.status()`，`needsSetup` 真 → setup 模式并隐藏手动切换 | `93-101,159` |
| **服务端地址输入口 = 1 个** | 只有 `服务器地址` 一个输入 + `测试`/`保存`；且 `v-if="isNative"`（`getPlatform() !== 'web'`） | `176-185,41,167` |
| 地址存储 | `writeServerUrl` 写入**列表**（新地址置顶去重），key `SERVER_URLS`（兼容旧 `SERVER_URL`、`ACTIVE_SERVER`） | `api/client.ts:129-160,230-242` |
| web 端 | `getActiveServerUrl()` 强制同源，历史手填地址不采信 | `api/client.ts:188-190` |
| 结果文案 | `请填写服务器地址` / `连接正常（Nms）` / `连接失败（原因）` / `服务器地址已保存` | `78,84,90` |
| 布局 / 校验 | `.login-shell` `max-width:420px`；`.login-page` 居中 `padding:24px 16px` `min-height:100dvh`；`gap:12px`；用户名非空且口令 ≥8 才可提交 | `194-226,45` |
| 无移动端覆盖 | 文件内**没有**任何 `@media`，移动端沿用同一套值（`width:100%` 自适应） | 全文 |

## 9. 争议点速查

| 问题 | 结论 | 依据 |
|---|---|---|
| 顶部品牌条 | **有**。`.sidebar` ≤860 变 sticky 品牌条（LOGO 46px + `SuenMoney` 15px + 底边线），`brand-sub`、导航项全隐藏；五个屏都显示 | `views.css:860-868,1114-1117`、`app.css:722-736`、`views.css:1115` |
| 页面标题栏 | **没有**。`.topbar-txt` 被 `!important` 隐藏；流水页整条 `.topbar--bare` 不渲染；其它页只剩「返回」图标 | `base.css:106-113`、`App.vue:210-221` |
| 主题切换 | 顶栏里**没有**（`.topbar-actions` 整块隐藏）；唯一入口 = 设置→数据→主题 | `base.css:107-110`、`App.vue:223-227`、`SettingsView.vue:993-1009` |
| 「记一笔」按钮 | **没有**。顶栏主按钮随 `.topbar-actions` 隐藏；新建唯一入口 = 下拉手势（`pull ≥ 54` → `openCreate`） | `base.css:107-110`、`App.vue:70-103` |
| 底部固定页脚 | `.side-foot`（同步状态 + 侧栏 build-stamp）**隐藏**；但正文流末尾仍有 `.build-stamp`（`SuenMoney · 单账本家庭记账 · {stamp}`）**正常显示**，随页滚动，**非 fixed** | `app.css:741`、`App.vue:247-251`、`base.css:46-54` |
| 设置 tab 数 / 卡 | 4 tab：账目(2 卡) / 计划与还款(3 卡) / 数据(9 卡) / 家庭(3 卡)，明细见第 6 节 | `SettingsView.vue:59-64,818-1218` |
| 主题选择器形态 | 3 个选项，每项含**大预览块**（56px 高 CSS 仿界面）+ 名称 + 说明；≤720px 单列，721–860 三列 | `views.css:749-756,810-815`、`SettingsView.vue:993-1009` |
| 抽屉「完成」= 保存？ | **是**，`OK` 直接 `@click="save"`，与底部主按钮同函数 | `ExpenseSheet.vue:562,580` |
| 底部独立「保存」/「取消」 | **有**：`.sheet-foot` 主按钮 + `取消`；移动端无隐藏规则 | `ExpenseSheet.vue:579-584` |
| 快捷条与键盘列宽 | 快捷条**不参与**键盘栅格：在 `.sheet-body` 内、键盘上方，宽度=抽屉内容宽（跨满 54px 支付列 + 数字区），自身横向滚动；键盘才是 `54px + 1fr` 两列 | `ExpenseSheet.vue:509-521,753-761`、`views.css:899` |
| 下拉记账的视觉指示器 | 静态 `.pull-hint`（`下拉记一笔` + 药丸箭头）被 `!important` 隐藏；只剩 `.pull-bar`：高度=下拉距离(0–84px)、居中细条、文字 `下拉记一笔`→达阈值变 `松开记一笔`、accent、11px/700 | `base.css:114-117`、`App.vue:234-239`、`app.css:703-713` |
| 登录页服务端地址输入口 | **1 个**（`服务器地址`），仅原生壳；多地址由代码内部按列表存储/自动探测，界面无多入口表单 | `LoginView.vue:166-185`、`api/client.ts:129-160,285-292,424-428,525-529` |

## 10. 移动端隐藏清单（`display:none`，≤860px）

| 隐藏元素 | 内容 | 规则 | 依据 |
|---|---|---|---|
| `.topbar-txt` | 页面标题 + 英文副标题（`PAGE_META`） | `!important` | `base.css:106-109` |
| `.topbar-actions` | 主题切换按钮 + `记一笔` 主按钮 | `!important` | `base.css:107-110` |
| `.topbar--bare`（整条顶栏） | 流水页顶栏（含返回位） | `!important` | `base.css:111-113` |
| `.pull-hint` | `下拉记一笔` 静态提示 + 箭头药丸 | `!important`（覆盖 `app.css:761` 的 `display:flex`） | `base.css:114-117` |
| `.sidebar .nav` | 4 个导航项 | `display:none` | `views.css:1115` |
| `.nav-cap` | 导航小标题 `账目` | `display:none` | `app.css:741` |
| `.side-foot` | 同步状态按钮（`已同步`/`待同步 N 笔`/`离线（点击重试）`/`SYNC`）+ 侧栏 build-stamp | `display:none` | `app.css:741` |
| `.sidebar .brand-sub` | `FAMILY LEDGER · 单账本` | `display:none` | `app.css:736` |
| `.topbar-sub` | 顶栏英文副标题（冗余于 topbar-txt） | `display:none` | `app.css:756` |
| `.desktop-only` | 通用桌面块 | `!important` | `app.css:777` |
| └ 流水页构成四维卡 `CompositionCard` | 分类/支付/记录人/节奏构成卡 | 同上 | `LedgerView.vue:496-498` |
| └ 流水页明细表 `<table class="tbl">` | 桌面表格（移动改 `.m-list`） | 同上 | `LedgerView.vue:512` |
| └ 抽屉桌面金额输入 `input.amt-input` | 桌面键入框（移动用键盘） | 同上 | `ExpenseSheet.vue:524-530` |
| `.ledger-toolbar .lt-adv` | 档位/翻页/筛选/排序（默认收起） | `none`，`.is-open` 时 `flex` | `views.css:1000-1001` |
| `.report-compose .card-h .card-cap` | 报表构成卡副标题 `分类 / 支付 / 记录人 / 节奏` | `display:none` | `views.css:1128` |
| `.lt-collapse`（反向） | 移动端显示的 `收起` 按钮在 ≥861px 隐藏 | `!important`(min-width:861) | `views.css:1007-1008` |
| `.mobile-only`（反向） | 移动专属块（返回按钮、`.mobile-hero`、`.m-list`、`.keypad`）在 ≥861px 隐藏 | `!important`(min-width:861) | `app.css:780-782` |
| `.preview-box`（高度条件） | 金额预览块，`≤860×720` 起隐藏 | `display:none` | `ExpenseSheet.vue:717-719` |
| `.quick-cats`、`.month-spent`（高度条件） | 分类快捷条、`本月已支出`，`≤860×620` 起隐藏 | `display:none` | `ExpenseSheet.vue:723-727` |
| 滚动条 | `.nav`、`.settings-tabs`、`.report-compose .chips`、`.quick-cats` 的 WebKit 滚动条 | `display:none` | `app.css:740`、`views.css:876,1137`、`ExpenseSheet.vue:762-764` |
