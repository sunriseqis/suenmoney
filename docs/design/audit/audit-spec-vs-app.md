# 鸿蒙端实现审计：`hw-ui-spec.md` × `hw-native/entry/src/main/ets`

- **审计对象（唯一实现依据）**：`docs/design/hw-ui-spec.md`（472 行，v1）
- **被审代码**：`hw-native/entry/src/main/ets/`（28 个 .ets，7869 行）
- **审计方式**：把规范逐条抽成可机械核对的要求 → `grep -n` / 逐行读码定位 → 找不到或不符即记缺陷
- **审计性质**：**只读审计，未修改任何源码或文档以外的文件**（本文件为唯一产出）
- **代码基线**：审计时工作区当前状态（未做 git diff 过滤）

> 严重度口径：
> - **阻断** = 命中 §7 判据不通过 / §7.1 禁止项 / 直接把功能做错（数据或动作语义错）
> - **重要** = 规范明文要求，缺功能或结构错，但不构成"放行即事故"
> - **次要** = 数值/文案/细节口径偏差、死代码、可访问性/适配缺项

---

## 一、缺陷清单

| 编号 | 规范位置 | 代码位置（文件:行） | 缺什么 / 错什么（含 grep 依据） | 严重度 |
|---|---|---|---|---|
| **A01** | §4.3 L245、L258–260（R76）；§7 判据 23（L446） | `components/report/ReportScreen.ets:186-188`（`if (this.tier === 2) { this.summaryNote() }`）、`:448-451`（`summaryNote()` 只有一句 `Text('汇总档：跨年合计与年度对比')`） | **汇总档 5 个块一个都没有**：规范要求 汇总档 = 分类构成 / 支付排名 / 记录人排名 / 期内节奏（按年）/ 洞察（2 条）。代码在 `tier===2` 时只渲染一行说明文字，连洞察都消失。`grep -n "summaryNote" ReportScreen.ets` → 仅 186、448 两处，无任何块进入汇总分支。 | 阻断 |
| **A02** | §4.3 L247（R79）、L245/L258（R76 三档均含"按记录人"） | `components/report/ReportScreen.ets:283-300`（`rankCard()` 只画"按支付方式"） | **"按记录人"排名块全端不存在**：`grep -rn "记录人" components/report/` → **0 命中**（"记录人"在全端只出现在 `LedgerScreen.ets:141` 注释与 `:747` 的筛选维度）。判据要求排名行中间有占比条，记录人维度连行都没有。 | 阻断 |
| **A03** | §4.3 L245（月 8 / 年 7）、L250–251（R82/R83） | `components/report/ReportScreen.ets:189-196`（年档分支只有 `composeCard/rankCard/rhythmCard/insightCard` 4 块）、`:338-344`（`else { Text('按月') }`） | 年档块数 **4 < 规范 7**：缺 记录人排名、对照四格（年档版本：去年 / 近 3 年均值 / 最高月 / 单笔最高）、涨跌榜；且"期内节奏"年档只输出文字 `按月`，**没有任何图表**（R82 要求年档按月）。`grep -n "近 3 年均值\|最高月" ReportScreen.ets` → 0。 | 阻断 |
| **A04** | §4.3 L253（R84：月档 = 本月已刷 + **下月要还** 两段）；§7 判据 22（L445） | `components/report/ReportScreen.ets:379-380` | 两段用了**同一个函数同一个值**：`repayFact('本月已刷', creditCents())` 与 `repayFact('下月要还', creditCents())`，`creditCents()`（:396-404）只累加本期 `paymentMethods` 中 `type==='credit'` 的金额。下月应还（下期账单）完全没有来源，界面显示两遍相同数字。 | 阻断 |
| **A05** | §4.3 L251（R83 月档四格：上月 / **去年同月** / 近 12 月均值 / 单笔最高） | `components/report/ReportScreen.ets:152` | "去年同月"写死 `formatYuan(0)`，永远是 ¥0.00。不是"没做"而是**做了个假数**。 | 重要 |
| **A06** | §4.1 L220-223（R30/R31：四档明度 `accent .42/.24/.12/.05`、0 值只描边、选中 `2vp` accent 描边 + 8% 底）；§7 判据 18（L441） | `components/ledger/LedgerScreen.ets:940-975`（`monthGridView` → GridItem 固定 `.backgroundColor(this.tok().surface)` + `.border({width:1,color:line})`）、`:995-1030`（`yearGridView` 同写法） | 日历格 **一个视觉状态都没有**：全部格子同一底色，没有四档明度、没有 `0 值只描边`（0 元月与满额月长得一样）、没有选中态描边/底色。`grep -n "opacity\|accent" LedgerScreen.ets` 在 940-1030 区间 0 命中。 | 阻断 |
| **A07** | §4.1 L224-225（R58 两段式下钻：一次点击只切下方卡、不换页、不产生返回栈；再点或点「进入 … →」才下钻）；§7 判据 19（L442） | `components/ledger/LedgerScreen.ets:962-970`（年格 `onClick` 直接 `this.anchorMonth = point.month; this.tier = 0; this.loadMonth(true)`） | **没有两段式**：点格立刻 `tier=0` 把整屏从"12 格"换成"明细列表"（等于换页），既无"下方卡切期间"，也无「进入 … →」按钮。`grep -n "进入 " LedgerScreen.ets` → 0。 | 阻断 |
| **A08** | §4.1 L200（R23/D13：**只有逾期时**整张顶卡吸顶；非逾期随内容滚走）；§7 判据 11（L434） | `components/ledger/LedgerScreen.ets:1080-1105`（`build()` 里 `this.topCard()` 与 `this.controlRow()` 都在滚动 `List`（:825 `monthListView` 内的 `List`）**之外**） | 顶卡是**永久固定**的：它不在任何 Scroll/List 内，所以"随内容滚走"永远不发生 → 非逾期时也等于吸顶，与"只有逾期才吸顶"直接矛盾。全文件无 `sticky`/`position`/`nestedScroll` 相关写法（`grep -n "sticky\|nestedScroll\|position(" LedgerScreen.ets` → 0）。 | 阻断 |
| **A09** | §0.1 L38（D8/R15：三入口**随内容滚走**、不吸顶） | 同上 `components/ledger/LedgerScreen.ets:1081-1085` | 控制行（含三入口）与顶卡同处 List 之外 → 三入口与期间选择器**恒定吸顶**，与 D8"随内容滚走"相反。 | 重要 |
| **A10** | §4.1 L196-197（顶卡必备"环比胶囊"：`padding:3 8; border:1.5 currentColor; radius:pill; mono 10.5/700`，底色 accent 12%，涨跌**只用文字与符号**表达，不靠染色）；§5.1 L368 | `components/ledger/LedgerScreen.ets:387-391`；`components/dashboard/DashboardScreen.ets:220-221` | 环比做成**裸文本**：无 padding/无 1.5vp 边框/无 pill 圆角/无 accent 12% 底，且**用 `danger`/`ok` 染色表达涨跌**（`fontColor(deltaRatio>0 ? danger : ok)`），并且**缺 `+`/`−` 符号**（`toFixed(1)%` 直接拼）。违反"胶囊结构保留、只作废染色"的裁决（§0.2.1 L70）与"语义不只靠颜色"。 | 重要 |
| **A11** | §5.3 L397-401（F36：自动入账期次**不得出现「忽略」**）；§4.7 L314（R118 状态词必须可见）；§7 判据 25（L448） | `components/ledger/LedgerScreen.ets:476-486`（`bindMenu([{ value: '忽略本期', action: actTodo(t, true) }])` 无条件挂）；`components/settings/SettingsScreen.ets:608-616`（同一写法） | 两处待办菜单**对 `willAutoPost` 期次也给出「忽略本期」**→ `skipTodo` 会把自动入账偷偷关掉（规范点名的高风险项）。`grep -rn "忽略本期"` → 仅这 2 处，且都无 `willAutoPost` 条件包裹（对比同行 :470/:595 的按钮文案是有条件的）。 | 阻断 |
| **A12** | §4.7.2 L333-338（R65：左滑=确认/入账、右滑=忽略、阈值 **72px** 且越阈换词；动作后 **8 秒内可撤销**）；§4.7 L318-319（R125–R127 撤销入口只在期次列表） | `components/ledger/LedgerScreen.ets:1127-1140`（全文件唯一手势是抽屉的下拉 `PanGesture({ direction: PanDirection.Down, distance: 40 })`）；`components/settings/SettingsScreen.ets` 无手势 | **提醒手势与撤销闭环整体缺失**：`grep -rn "撤销\|PanGesture\|swipeAction" components/` → 只有 `LedgerScreen.ets:1129` 的抽屉下拉手势，没有左滑/右滑、没有 72px 阈值、没有"松开确认/松开忽略"换词、没有 8 秒撤销、没有"已处理"列表。 | 重要 |
| **A13** | §4.4 L272-273（R89：分类每行只给**笔数**，一级 = 其下所有二级累计）、L278（R87：分类行右侧给「停用」）；§7 判据 24/36（L447/L459） | `components/settings/SettingsScreen.ets:369`（一级行 `Text(String(root.children.length))`）、`:375-410`（二级行才有 `${kid.expenseCount} 笔`，一级无笔数）、`:486-500`（`railChildren()`） | 一级分类行显示的是**子类个数**，不是"累计笔数"——正是 R89 点名禁止的"一级 0 笔但其实下面有 7 笔"口径；而且**「停用」只在编辑弹层里**（`:980`），分类行右侧什么都没有（`grep -n "停用" SettingsScreen.ets` → 只 402/462 的"已停用"文字与 980 的按钮）。 | 阻断 |
| **A14** | §4.4 L278（FI#77：二级分类可**折叠/展开**）；§7 判据 36（L459） | `components/settings/SettingsScreen.ets:375-410` | 二级永远展开（左 110 宽一级列 + 右二级列表常驻），**没有折叠/展开控件**；`grep -n "折叠\|collapse\|expand" SettingsScreen.ets` → 0。 | 重要 |
| **A15** | §4.4 L277（FI#78/#79：支付方式行给 **本月 N 笔** + **「合并」入口**，合并前二次确认并提示历史记录归属）；§7 判据 36（L459） | `components/settings/SettingsScreen.ets:432-476`（支付行只有 name + 账期）、`:1060-1084`（合并只在"编辑支付方式"弹层内） | 支付行**没有「本月 N 笔」**（`grep -n "本月" SettingsScreen.ets` → 0 命中），**没有行内「合并」入口**；合并仅在编辑弹层，且 `deactivatePayment()` 前无二次确认弹窗（对比分类删除 `ExpenseEditor` 用了 `AlertDialog`，这里没有）。 | 重要 |
| **A16** | §0.1 L49（D19/R134：分类图标存 **kebab-case 名字**，解析优先级 显式 icon > 按名反查 > 通用图标） | `components/settings/SettingsScreen.ets:938-948`（`TextInput({ placeholder: '图标（单个字符）' })`，注释："先用 1 个字符代替"）；`components/ledger/LedgerScreen.ets:855-866`（行卡徽位渲染 `this.categoryNameOf(row).substring(0,1)`） | 图标体系**完全没按 D19 实现**：录入是"单个字符"，展示是"分类名首字"，没有 kebab-case 名、没有图标解析、没有通用兜底。`grep -rn "kebab\|iconOf\|resolveIcon" common/` → 0。 | 重要 |
| **A17** | §2 L163（行卡图标徽位 **44px**、12%/45% 混色、**图标本体 20px**、图标列定宽 R137/R138）；§4.4 L279 | `components/ledger/LedgerScreen.ets:855-866`（44×44 有，但里面是 `fontSize(16)` 的字）；`components/settings/SettingsScreen.ets:388-395`（分类行只有 8×8 色点，无徽位） | 徽位尺寸对了一半：容器 44 ✓、混色 12%/45% ✓，但**图标本体 16px（规范 20）且不是图标**；设置页分类行**根本没有 44px 徽位**（只有色点），图标列不定宽。 | 重要 |
| **A18** | §4.2 L240（R72 网格顺序：hero → **本月要还** → **进度对比** → 热力 → 累计）、L239（R73 进度对比卡：已过 N 天 + 日均 + 进度条 对近 3 个月日均）、L233（R128） | `components/dashboard/DashboardScreen.ets:435-447`（build 里只有 `hero → heat → cumulative`） | 概况网格**缺两块**：「本月要还」信息层卡（当前只是 hero 三指标之一）与「进度对比卡」；`grep -n "进度\|近 3 个月\|已过" DashboardScreen.ets` → 0。R72 规定的顺序也无法满足。 | 重要 |
| **A19** | §4.2 L241（R74/R75：提醒展开区每条必须有一行动作；动作后就地消失 + 顶卡计数 −1 + 归零变单列）、L312（R116 信息层在概况网格） | `components/dashboard/DashboardScreen.ets:106-131`（`loadTodos()`）、`:133-147`（`actTodo()`） | 待办**取回来了但从不渲染**：`grep -n "this.todos" DashboardScreen.ets` → 只有 `:129` 赋值，`build()`（:426-455）无任何引用；`actTodo` 同样零调用。等于"信息层提醒"整块不存在（且是死代码）。 | 重要 |
| **A20** | §4.2 L236-237（R70：热力 最近 12 个月、**单色四档明度** `accent .42/.24/.12/.05`、阈值同 §4.1、**格内放金额**、无记录显示 `—`、窄屏 6×2）；§7 判据 34（L457） | `components/dashboard/DashboardScreen.ets:320-350`（格内只有 `point.month.substring(5,7)` 月份数字）、`:501-508`（`heatOpacity()` 连续线性 `0.08 + r*0.82`） | 热力条 4 项不符：①**格内无金额**；②无记录月不显示 `—`（不渲染任何文字）；③**连续 opacity 而非四档明度**（R30 明确"不得引入第二种色相/四档"）；④0 值仍填色（`max<=0` 返回 0.08，永远有底色），违反"0 值只描边"。列数 6 ✓（唯一达标项）。 | 阻断 |
| **A21** | §0.1 L48（D18/R132：卡 **24** / 抽屉 24 / 输入 14 / 胶囊 999）；§4.4 L280 | `common/theme/AppTheme.ets:91`（`rCard: 20`）；实际使用点：`DashboardScreen.ets:250/358/401`、`SettingsScreen.ets:478/628/793`（`.borderRadius(radiusOf(..., this.tok().rCard))`） | 卡片圆角照 `rCard` 走 = **20vp，不是规范 24**。对比：`LedgerScreen.ets:514`（顶卡）、`ReportScreen.ets:289` 等都显式写 24 —— 同一端两套圆角，说明 `rCard` 这条通道整体偏离令牌。`grep -rn "this.tok().rCard"` → 6 处全部 20。 | 重要 |
| **A22** | §1.1 L92（cyber 切角四档 14/7/6/8）、§2 L144/L146/L164（cyber → radius 0 + 切角）、§6 L408（"不得用圆角近似"） | `common/ui/UiStyle.ets:120-128`（`CUT_CARD/CUT_BTN/CUT_ORB/CUT_LOGO` 与 `cutPathCommands()` 只有定义）；`grep -rn "cutPathCommands\|CUT_" --include=*.ets .` → **只有 UiStyle 自身 4+1 行，零调用** | cyber 主题下**切角完全没实现**：卡片/按钮/Orb 只是 `radiusOf()` 返回 0 的直角，`clipShape(Path)` 从未使用。§6.4 明文"不得用圆角近似"。 | 重要 |
| **A23** | §2 L155（Toast：底部居中、ink 底、2px line-2 边、4px 硬阴影、pill、10 16、12px）；§3 L176（`[Toast]` 在壳层） | 全仓 `grep -rn "showToast\|promptAction" --include=*.ets .` → **0 命中**；`pages/MainPage.ets:9` 注释还写着"→ Toast / 记账抽屉"，但 build（:124-152）没有 Toast | **Toast 组件不存在**：所有"保存成功/已入队/同步结果"只能靠内联 `Text` 或 `AlertDialog`，没有规范要求的 Toast 形态。 | 重要 |
| **A24** | §5 L355 与 §5.2 L395（R144：离线文案「**已存本机、联网自动同步**」，位置**并入流水页计划提醒卡区域**，只由待同步条目驱动）；§3 L175（build-stamp 含 离线/待同步 N）；§7 判据 28（L451） | `components/ledger/LedgerScreen.ets:1089-1092`（`Text('离线：显示本地缓存')`）；`pages/MainPage.ets:114-121`（stamp 只有 `SuenMoney · 单账本家庭记账`） | 三处都不对：①**文案错**（规范字面是"已存本机、联网自动同步"）；②**位置错**（当前挂在列表上方，不在计划提醒卡区域）；③**驱动条件错**（受 `this.offline` 网络状态驱动，不是"待同步条目"驱动）；④**"待同步 N"在壳层完全缺失**（stamp 里没有）。`grep -rn "已存本机"` → 0 命中。 | 阻断 |
| **A25** | §5 L357（死信/同步失败必须可见）、§5.2 L393（R145） | `components/settings/SettingsScreen.ets:92-93`（`@State pendingCount` / `deadLetters`）、`:105-113`（`refreshQueue()`） | 死信**取到了但从不显示**：`grep -n "this.deadLetters\|this.pendingCount" SettingsScreen.ets` → 只有 107/108/110/111 的赋值与清零，`build()` 与任何 `@Builder` 都无引用 → "死信必须可见"落空，失败条目静默躺在库里。 | 重要 |
| **A26** | §5 L359（R39 全局 `tabular-nums`）、§5.1.1 L379（金额/百分比/日期统一 `fontMonoOf()`）；§7 判据 29（L452） | `components/ledger/LedgerScreen.ets:899-903`（行金额 `Text(formatYuan(row.amountCents)).fontSize(13)` —— 无 `fontFamily`）；`DashboardScreen.ets:229-231`（metric 三指标值）、`ReportScreen.ets:389-395`（`repayFact` 数值）同缺 | 金额/百分比大量**未走等宽族**：`grep -c "fontFamily(fontMonoOf())" LedgerScreen.ets` = 少量，而行内金额、hero 三事实值、对照四格值等均裸写字号。数字列宽不一致，判据 29 不通过。 | 阻断 |
| **A27** | §2 L142-164（Card/Btn/IconBtn/Input/Seg/Chip/Tag/Stat/Switch/Orb 全部给出必须值）、§6 L403（实现纪律）、§7.1（禁止自造） | 无 `components/ui/` 目录：`components/BrandMark.ets` 之外没有共用原子组件；按钮散落各处且数值自定，如 `SettingsScreen.ets:345`（`Button('新增') .height(26)` 无边框无 pill）、`LedgerScreen.ets:735`（`height(36)`）、`ExpenseEditor.ets:730`（`height(42)`） | **§2 的原子组件层没有落地**：Btn 规范要求 `min-height:38 / padding:8 16 / border:2 line-2 / radius:pill / bg:surface / 12.5-700 / 3px 硬阴影 / cyber 变体`，代码里没有任何一个按钮同时满足（`grep -rn "minHeight\|constraintSize" --include=*.ets .` → **0 命中**，`grep -rn "padding({ left: 16, right: 16" --include=*.ets .` → **0 命中**，即 min-height:38 与 padding:8 16 两条根本没出现过）。Input 的 `min-height:40`、Seg 的胶囊外框 `padding:3 + border:2 outline-strong`、Switch 的 `42×24 + border:2 outline-strong` 同样缺失。 | 重要 |
| **A28** | §5.1 L372（R35：焦点态 2px `#5DB8FF` + 2px offset，作为常量 `FOCUS_RING` 写在 UiStyle） | `common/ui/UiStyle.ets`（全文 140 行） | `grep -rn "FOCUS_RING\|#5DB8FF" --include=*.ets .` → **0 命中**。焦点常量与焦点态视觉均未实现。 | 次要 |
| **A29** | §2 L154（Sheet：贴底全宽、`height:93dvh`、顶部 radius **24**、drag-bar、让开安全区） | `components/ledger/LedgerScreen.ets:1120-1125`（`height: SheetSize.LARGE, dragBar: true, showClose: true, backgroundColor`） | 用 `SheetSize.LARGE`（默认比例，不是 93dvh），**没有设置顶部 24vp 圆角/背景圆角**，也没有 `px2vp(避让区 bottom)` 的安全区让位（`grep -n "safeArea\|avoidArea\|px2vp" LedgerScreen.ets` → 0）。`showClose: true` 还额外引入了规范未列的关闭键（与"×收在标题行"的关闭语义重复）。 | 次要 |
| **A30** | §4.6 L292（R103：常用分类为**胶囊 + 底槽**） | `components/expense/ExpenseEditor.ets:490-712`（build 中字段 → 备注 → 账期 → 退款 → 键盘，无常用分类区） | **常用分类快捷条不存在**：`grep -n "常用" ExpenseEditor.ets` → 0 命中（只有文件头注释第 6 行自称有"常用分类快捷条"）。 | 重要 |
| **A31** | §4.6 L303（R113：退款仅非分期可用；分期仅信用卡且非退款） | `components/expense/ExpenseEditor.ets:592-606`（退款 Toggle 无任何 enabled 条件）、全文件无分期入口 | **分期功能整体缺失**：`grep -n "分期\|splitInstallment" components/` → 0（`splitInstallment` 只在 `common/contract/Contract.ets:63` 定义、`VectorRunner` 里测试，UI 零调用）；退款开关对信用卡/分期不设条件，R113 的两个互斥关系无从体现。 | 重要 |
| **A32** | §4.6 L295（R101 键序 `7 8 9 ⌫ / 4 5 6 C / 1 2 3 完成 / 0 00 . （空）`） | `components/expense/ExpenseEditor.ets:466-468`（`Button(key === 'B' ? '←' : (key === 'C' ? '清空' : key))`）、`:774`（`KEYPAD_KEYS`） | 键位顺序与 5 列结构 ✓，但**符号被改写**：⌫ → `←`、C → `清空`。规范把键面文案写成硬性形态（判据 16 也按"5 列键盘"dump 核对文案）。 | 次要 |
| **A33** | §5.1.1 L384（R46：容器宽 ≤460vp 时**先让账期**，支付方式与「日」保留，日期列永不折行） | `components/ledger/LedgerScreen.ets:918-927`（`subline()` 无条件拼账期段） | **窄屏让位未实现**：全仓无宽度断点/面积回调（`grep -rn "onAreaChange\|460\|Breakpoints" --include=*.ets .` → 0），账期段在 390vp 下仍全量渲染，只能靠 `maxLines(1)` 省略，违反"先让账期"的让位顺序。 | 次要 |
| **A34** | §4.1 L211-214（R62/R63/F33：筛选默认折叠；有生效条件时带**状态圆点 + 数量**；维度 = 分类/支付/记录人 + **排序** + **金额区间**） | `components/ledger/LedgerScreen.ets:730-762`（"按日期/按金额"两个按钮**常驻**在折叠面板之外）、`:697-720`（筛选按钮只改底色 `activeFilterCount()>0 ? accent : surface2`，无圆点无数字）、`:763-800`（`filterGroup` 只有分类/支付/记录人） | 三处不符：①**排序未收进折叠面板**（与"筛选默认折叠"冲突）；②筛选按钮**无状态圆点 + 数量**（`grep -n "activeFilterCount" LedgerScreen.ets` → 只用于换底色，未渲染数字）；③**金额区间维度缺失**（`grep -n "金额区间\|minCents\|maxCents" LedgerScreen.ets` → 0）。 | 重要 |
| **A35** | §1.3 L120（`fontMonoOf()` 恒返回 JetBrains Mono）、§5.1.1 L381（R41：四套 ttf 走 rawfile 本地注册） | `pages/LoginPage.ets:21`（`import { ensureFonts }` **引入但从未调用**）、`common/theme/Fonts.ets:35-38`（`familySrc: 'rawfile/fonts/...'` 字符串写法）、`common/theme/FontRegistry.ets:1-8`（注释明确写"字符串写法注册不生效"） | 首启**登录页没有任何自定义字体**：`grep -rn "ensureFonts("` → 只有 `MainPage.ets:40` 一处调用；`LoginPage` 走 `displayFont()/bodyFont()`（`Fonts.ets:46-53` 返回 'Outfit'/'Plus Jakarta Sans'），而这两个族名只有 `FontRegistry`（用 `$rawfile`）能注册成功 → 登录页整体回落系统字体。同时两套注册表并存（`Fonts` 字符串写法 vs `FontRegistry` 资源写法）本身是冲突实现。 | 重要 |
| **A36** | §4.5 L285（R98：**仅三个输入槽 + 连通指示 + 三个按钮**，技术细节文字全删）、§4.7.1 L328（M5 服务端地址编辑为**弹层**） | `pages/LoginPage.ets:158-215`（`List` 地址列表 + 每行"删除" + "新增地址"输入 + "添加" + "测试" + `probeText` 多行文本） | 服务器地址区**形态不符**：动态列表 + 增删而非"三个固定输入槽"；无 per-slot 连通指示（只有一段 `probeText` 拼接文本）；按钮数量 3 个（删除/添加/测试）但语义完全不是规范那三个；**技术细节文字未删**（placeholder 直接给 `http://192.168.1.10:5310`）；且**没有 M5 弹层**（`grep -rn "bindSheet\|CustomDialog" pages/LoginPage.ets` → 0）。 | 重要 |
| **A37** | §4.5 L286（键盘弹起时表单整体上移，见安全区 §3） | `pages/LoginPage.ets:222-227`（根 `Column().width('100%').height('100%')`，无 `Scroll`） | 登录页根容器定高且**不可滚动**：键盘弹起时下半部分（地址列表/测试按钮）无法触达。`grep -n "Scroll" LoginPage.ets` → 0。 | 次要 |
| **A38** | §4.6 L305（R115：首次进流水页提示一次「下拉可记账」，**之后永不再现**） | `components/ledger/LedgerScreen.ets:82`（`@State pullHintShown`）、`:117-127`（`maybeShowPullHint` 只判内存标志） | 提示**每次重建都重现**：标志是组件内 `@State`，`MainPage.ets:134-143` 用 `if/else` 分支渲染，去概况/报表再回流水会重建 `LedgerScreen` → `pullHintShown` 归 false。未落 Preferences（对比 `ThemeManager`/`LastPick` 都有持久化）。 | 次要 |
| **A39** | §0.1 L46（D16/R130：三档 + **未显式选择时实时跟随系统**） | `common/theme/ThemeManager.ets:41`（`getSync(KEY_MODE, 'dark')`）、`:44`（catch 里同样 `'dark'`） | 首次启动默认档是 **dark**，不是"跟随系统"。`system` 档的监听（:57-66）实现正确，但"未选择"的初值选错 → 浅色系统用户首启被强制成深色。 | 次要 |
| **A40** | §4.4 L268（外观 = 主题三档 + 品牌徽章与版本）、L269（家庭 = 成员 / 登录设备 / 我的账号）、§4.7.1 L329（FI#90 检查更新：放设置「外观」底部与版本号同处，"不得当作没有"） | `components/settings/SettingsScreen.ets:667-717`（外观区含主题 + 徽章 + 版本 + **退出登录**）、`:740-799`（家庭区只有成员） | ①**「检查更新」入口缺失**（连占位都没留，`grep -n "检查更新\|update" SettingsScreen.ets` → 0）；②外观区多了「退出登录」（规范限定外观只放主题与品牌信息）；③家庭区**缺「登录设备」与「我的账号」**（`grep -n "登录设备\|我的账号" SettingsScreen.ets` → 0）。 | 次要 |
| **A41** | §4.4 L264（`settings-tabs` + `stab`，移动端**横滑**） | `components/settings/SettingsScreen.ets:806-818`（`Row` 内 4 个 `sectionButton`） | tab 条是**固定四等分 Row**，不能横滑；4 个 tab 文案较长（"计划与还款"）时压缩换行风险，与"横滑"形态不符（`session` 内无横向 `Scroll`/`List`）。 | 次要 |
| **A42** | §4.1 L218（R60：年档 = 12 个月格，**窄屏退化成 3×4**） | `components/ledger/LedgerScreen.ets:974`（`columnsTemplate('repeat(3, 1fr)')` 硬编码） | 年档**永远 3 列 4 行**，宽屏（≥460vp）也不放宽 → "12 个月格 / 窄屏退化"的档位差异没有实现，只有窄态一种排法。 | 次要 |
| **A43** | §1.2.1 L96-107（`outline-strong` 只给**可交互控件边界**；`outline/line` 才做分隔线）、§2 L144（Card `border:2 solid line`） | `components/settings/SettingsScreen.ets:478/628/793`（卡片 `.border({width: borderW, color: outlineStrongOf(...)})`）、`DashboardScreen.ets:241` 用 `line`（正确） | 设置页三张卡把**可交互边界色 `outline-strong`（candy #1E293B / cyber #6f6f92）当成卡片描边**，与同端 `DashboardScreen` 的卡片（用 `line`）不一致；语义也错位（卡片不是控件）。 | 次要 |
| **A44** | §0.1 L31（D1 无组头、无日小计）、L44（D14/F09 移动概况不放构成堆叠条）、L45（D15/R99 不挂数据区） | `components/ledger/LedgerScreen.ets:52-56`（`LedgerDayGroup`）、`:314-330`（`grouped()` 带日小计，全文件无调用）、文件头注释第 4 行"按消费日分组 + 日小计"；`DashboardScreen.ets:283-320`（`composition()` 堆叠条 + 图例，build 无调用）；`SettingsScreen.ets:2`（注释"四区 —— 账目 / 计划 / 数据 / 家庭"）、`:665`（注释"── 数据 ──"） | 违反 D1/D14/D15 的**代码与注释仍在**：三处死代码/错误注释会让后续维护者按错口径复活（`grep -n "grouped()" LedgerScreen.ets` → 仅定义处，无调用；`grep -n "composition(" DashboardScreen.ets` → 仅定义处）。渲染层未被污染，故列为次要。 | 次要 |
| **A45** | §5 L361（R133：尊重"减少动态效果"）、§0.1 L48（动效统一 `cubic-bezier(.2,0,0,1)` + 200/350/400ms） | 全仓 `grep -rn "animateTo\|curve\|Curve\.\|reduceMotion\|animation(" --include=*.ets .` → **0 命中** | 既没有规范要求的动效曲线/时长，也没有"减少动态效果"的读取与降级；抽屉/展开/高亮全部瞬时切换（无过渡）。规范给了明确数值却零实现。 | 次要 |

**合计 45 条** = 阻断 **12**（A01/A02/A03/A04/A06/A07/A08/A11/A13/A20/A24/A26）+ 重要 **20**（A05/A09/A10/A12/A14/A15/A16/A17/A18/A19/A21/A22/A23/A25/A27/A30/A31/A34/A35/A36）+ 次要 **13**（A28/A29/A32/A33/A37/A38/A39/A40/A41/A42/A43/A44/A45）。

---

## 二、已正确实现的要求（用于确认审计覆盖）

以下均以代码行为证据，**不是"看起来像"**，逐条给命中位置：

| 要求 | 依据 | 代码位置 |
|---|---|---|
| 无底栏、无 4-Tab、顶部无标题/记一笔/主题按钮 | §0.1 L52（D22）、§3 L179、判据 1 | `pages/MainPage.ets:124-152`（只有品牌条 + 内容区 + stamp；`grep -rn "Tabs\|BottomNavigation" pages/` → 0） |
| 二级页关闭为 `×` 收在标题行行尾、19px、`--fg-muted`、不单独占行 | L180（R17/R18）、判据 4 | `pages/MainPage.ets:80-110`（`Row{ Text(title).fontSize(19).ink3; Blank(); Text('×').fontSize(19).ink3 }`） |
| 三入口只在流水页、与期间同一行、靠右、不定宽、无选中态 | L191-192（R13/R14）、判据 2/3 | `LedgerScreen.ets:586-609`（`Blank()` 后三个裸 `Text`，各按内容宽度，无背景/选中态）；概况/报表/设置三屏 `grep "概况\|报表\|设置"` 无入口 → 0 命中 |
| 月档列表**无组头**、行内日期只写「日」、含账期段、无"还款日"药丸 | L203-207（R51-R53）、判据 5/6/7 | `LedgerScreen.ets:829-846`（直接 `ForEach(this.sortedRows())`，无分组标题）；`:909-922`（`subline()` 输出 `支付方式 · 28日 · 9月12日刷 · 28日还 · 16天`）；行内无 `还款` 胶囊（`grep -n "还'" 行卡区` → 0） |
| 合计只在有筛选时显示 `筛选结果 N 笔 · 合计 ¥X` | L208（R55）、判据 8 | `LedgerScreen.ets:822-828`（`if (this.activeFilterCount() > 0)` 才渲染） |
| 顶卡两态（无待办时本月支出占满整行） | L198（R20/R21）、判据 9 | `LedgerScreen.ets:400-419`（右半格 `if (this.heroTodos.length > 0)`，否则左列 `layoutWeight(1)` 独占） |
| 提醒默认收起、点击向下展开（把列表顶下去）、不记忆 | L199（R22）、判据 10 | `LedgerScreen.ets:83`（`todoOpen=false`）、`:404-410`（点击切换）、`:443`（`if (todoOpen)` 内联展开，非浮层，无持久化） |
| 分页：游标 + 每段 100 笔 + 触底「加载更多」/ 无更多「查看上月」 | L209（R56/R57）、判据 12 | `LedgerScreen.ets:52`（`PAGE_SIZE = 100`）、`:836-856`（`hasMore ? '加载更多' : '查看上月'`） |
| 三档三形态（列表 / 12 格 / 年格） | 判据 32 | `LedgerScreen.ets:1102-1110`（`tier===0 ? monthListView : tier===1 ? monthGridView : yearGridView`） |
| 窄屏年档 3×4 | L218（R60）、判据 20 | `LedgerScreen.ets:974`（`repeat(3, 1fr)` + 12 个月数据） |
| 日历无图例、无"越深＝花得越多"说明行 | L226（R61）、判据 33 | `grep -n "图例\|越深" LedgerScreen.ets` → 0 |
| 概况是二级页、视图内不出现分类名、无构成堆叠条、hero 底部无提醒条 | L230-233（R03/R07/R67/D14/F09）、判据 13 | `DashboardScreen.ets:435-447`（build 只 hero/heat/cumulative）；hero 内只有金额/环比/三指标（:196-233） |
| 概况三档换档同时换三子指标 | L231（R66/R68） | `DashboardScreen.ets:74-99`（`loadTier()` 按档重算 total/perDay/creditDue） |
| 累计条：通栏一行、不含金额、四项 | L238（R71） | `DashboardScreen.ets:369-402` + `:410-420`（`已记 N 天 · M 笔 · 平均 A 笔/天 · 首笔 …`） |
| 报表无页首大数字、无「共 N 笔」 | L257（R86）、判据 21 | `ReportScreen.ets:218-240`（headCard 只有档位 chip + 期间） |
| 环图中心显示"分类数"不显示合计 | L246（R78）、判据 14 | `ReportScreen.ets:272`（`centerLabel: \`${this.categories().length} 类\``） |
| 环图 stroke-width 16（不是 12）、段间留空隙 | §2 L157 | `DonutChart.ets:41-43`（`lineWidth = 16`、`gap = 0.025`）、`:47`（半径内缩 `lineWidth/2` 才是 12） |
| 排名行中间有占比条 | L247（R79） | `ReportScreen.ets:288-300`（`Stack`：`surface3` 轨道 + 百分比宽度填充） |
| 块纵向堆叠、块内允许两栏 | L248（R80） | `ReportScreen.ets:394-404`（对照四格 `repeat(2, 1fr)`） |
| 还款节奏/涨跌榜在年档与汇总档隐藏 | L253/L260、判据 22 | `ReportScreen.ets:193-196`（`if (this.tier === 0) { compare/repay/movers }`） |
| 涨跌榜涨红跌绿 + 带 `+`/`−` | L252（R37） | `ReportScreen.ets:437-442` + `deltaText()`（`:444-447`） |
| 洞察纯规则引擎、无外部服务 | L255-256（R85） | `ReportScreen.ets:96-135`（`insights()` 纯本地拼句，无网络调用） |
| 设置四 tab：账目 / 计划与还款 / 外观 / 家庭 | L265-269（§4.4） | `SettingsScreen.ets:806-818` |
| 设置**不挂数据区**（导入/导出/备份/快照/危险区） | L270（D15/R99）、判据 15/27 | `grep -rn "导出\|导入\|备份\|快照\|危险" components/settings/` → 0 命中 |
| 主题三档（深/浅/跟随系统）+ 全局生效（`@StorageLink` 广播） | L268（R129/R130）、判据 17 | `ThemeManager.ets:80-88`（`setMode` → `broadcast()`）；`ThemeManager.ets:57-66`（`mediaquery` 跟随系统）；各屏 `@StorageLink(THEME_STORAGE_KEY)` |
| 分类编辑：改名/换图标/换色收进一个面板，不做行内编辑；二级不给颜色选择器 + 提示语；只允许同深度… | L274-275（R90/R91） | `SettingsScreen.ets:920-990`（`categoryForm()`：名称/图标/颜色；`if (this.formParent === '')` 才给颜色，否则 `Text('颜色跟所属一级分类走')`） |
| 支付方式**不给图标选择器** | L276（D20/R135） | `SettingsScreen.ets:994-1092`（`paymentForm()` 只有 名称/类型/账单日/还款日/合并/停用，无图标控件） |
| 抽屉：5 列键盘（左支付列物理分割线 + 右 4 列）、禁横向滚动、跨月明说、本月已支出不 await | L290-297（R100/R101/R106/R107/R108）、判据 16 | `ExpenseEditor.ets:428-500`（`Column.width(62)` + `Divider().vertical(true)` + 4 列 `Grid`）、`:575-584`（`本月已支出` + `—` 占位）、`:543-552`（`这笔会记在` + 月份）；抽屉内无 `Scroll` 横向（`grep -n "Scroll()" ExpenseEditor.ets` → 0） |
| 「完成」占右侧两行 | L295（R101） | `ExpenseEditor.ets:478-482`（`rowStart(3)/rowEnd(4)/columnStart(4)/columnEnd(4)`） |
| 账期预览走后端 `preview`，前端不重算 | L299（R109） | `ExpenseEditor.ets:163-174`（`Api.previewExpense(spendDate, paymentId)`） |
| 记住上次分类/支付 + 沿用前校验 | L300（R110） | `ExpenseEditor.ets:112-140`（`LastPick.read()` + `isEnabled` 校验） |
| 备注输入折叠数字键盘 + 上方辅助保存条 | L301（R111） | `ExpenseEditor.ets:695-720`（`if (this.noteFocus)` 分支） |
| 保存键禁用态（金额 0 或未选分类） | L308（FI#12–#14）、判据 26 | `ExpenseEditor.ets:239-241`（`canSave()`）、`:728-733`（`.enabled(!saving && canSave())`） |
| 编辑态软删 + 二次确认 | L307（FI#12–#14）、判据 26 | `ExpenseEditor.ets:360-392`（`AlertDialog.show` + `Api.deleteExpense`） |
| 保存后滚到列表顶并高亮 1.5s | L304（R114） | `LedgerScreen.ets:1044-1053`（`scrollEdge(Edge.Top)` + `setTimeout(1500)` 清 `highlightId`） |
| 计划卡 12 段进度刻度 + 旁边给精确数字（不许只靠刻度） | §2 L162（R36/R122）、L316（R121-124） | `SettingsScreen.ets:538-553`（文案 `N/M 期` + `Row{12 段}.height(4)`）、`:1336-1350`（`planTicks()` 压缩到 12 段） |
| 计划卡危险动作收进「更多」 | L317（R124） | `SettingsScreen.ets:524-540`（`bindMenu`：终止计划 / 删除计划） |
| 离线可读（A 档：本地库现算） | §5.2 L392（R141/142） | `LedgerScreen.ets:139-172`（`offline` 分支 → `ExpenseDao.byMonth/monthTotal` + `applyLocalFilters`） |
| 离线可写（B 档：Outbox + 5/10/30s 退避 + 300ms 防抖） | L393（R143/R144） | `Outbox.ets:28`（`[5000,10000,30000]`）、`SyncEngine.ets:21`（`DEBOUNCE_MS = 300`）、`ExpenseEditor.ets:317-333`（`enqueueOffline`） |
| 断网静默不弹错 | L356（R143）、判据 28 前半 | `LedgerScreen.ets:161-170`（`err.kind === 'network'` 只置 `offline`，不进 `errorText`） |
| 金额整数分、展示才除 100、退款为负不加色 | §6 L412（R146）、判据 38 | `Contract.ets:44-62`（`parseYuanToCents` 整数运算）、`ExpenseEditor.ets:284/296`（`isRefund ? -cents : cents`）、行金额 `fontColor(ink)` 无染色 |
| 字体族统一走 `fontDisplayOf/fontBodyOf/fontMonoOf`，不裸写族名 | §6 L409 | `UiStyle.ets:84-100`（三个函数；`fontMonoOf()` 恒 'JetBrains Mono' 符合 §1.3）+ 各屏 import 使用（`grep -rn "fontMonoOf\|fontDisplayOf" components/` 多处命中） |
| 移动端卡片阴影是 `3px 3px 0 #E9EEF6` 而非桌面 6px | §1.1 L93 | `UiStyle.ets:70-78`（`cardShadow(tokens, isCyber, mobile = true)`） |
| 可交互控件边界用 `outline-strong`（≥3:1） | §1.2.1 L107 | `UiStyle.ets:138-140`（candy `#1E293B` / cyber `#6f6f92`）+ `ExpenseEditor.ets:528`、`LoginPage.ets:126`、`SettingsScreen.ets` 多处 |
| 分类色存色号、按 `categoryId` 哈希兜底 | §1.1 L90 | `Palette.ets:14-34`（`slotOf`）、`:50-56`（`hashIndex`） |
| 分类图标底色 12% / 描边 45% | §1.1 L91 | `UiStyle.ets:104-118`（`mixHex`）+ `LedgerScreen.ets:864-865` |
| 无预览页装饰层（点阵/电路/扫描线） | §1.4 L122-126（R38/F12） | `grep -rn "canvas\|dot\|扫描线\|deco" components/ pages/` → 0 |
| 禁止 Emoji / 说明式文字泛滥 / 底部 Tab / 悬浮球 | §6 L413、§7.1 | `grep -Pn "[\x{1F300}-\x{1FAFF}]" components/ pages/` → 0；无 FAB（`grep -rn "FloatingButton\|fab"` → 0）；无 Tabs 底栏 |

---

## 三、结论

### 3.1 判据通过率（§7 的 38 条）

| 结论 | 条目 |
|---|---|
| **通过（25 条）** | 1、2、3、4、5、6、7、8、9、10、12、13、14、15、16、17、20、21、26、27、31、32、33、35、38 |
| **不通过（12 条）** | **11**（顶卡常驻固定，非逾期也吸顶→A08）、**18**（日历四档明度/0值/选中态全缺→A06）、**19**（无两段式下钻→A07）、**22**（"下月要还"=本月已刷→A04）、**23**（汇总档无洞察且无块→A01）、**24**（一级显示子类个数非累计笔数→A13）、**25**（自动入账仍出现「忽略」→A11）、**28**（离线文案/位置/待同步全错→A24）、**29**（金额未走等宽族→A26）、**34**（热力无金额/无 `—`/连续透明度→A20）、**36**（分类行无停用、二级不能折叠、支付行无合并与本月笔数→A13/A14/A15）、**37**（客户端无 `hold_auto_post` 期级判据，schema 也无该列→A11/§5.3 一族） |
| **未验证（1 条）** | 30（"卡底空白 ≤40vp"需真机 dump/量图，静态读码不可判定，本次不给结论） |

**判据一致度 = 25 / 37（可判定条目）= 67.6%**（若把 N/A 计入分母 38 条则为 65.8%）。

### 3.2 缺陷与总体一致度

- **缺陷总数 45 条**：**阻断 12** / 重要 20 / 次要 13。
- 三个屏是"重灾区"，按缺陷密度：**报表页**（A01/A02/A03/A04/A05，8 个块只实现 4 个，汇总档几乎空白）、**流水页**（A06/A07/A08/A09/A10/A24/A34）、**设置页**（A13/A14/A15/A40/A41）。
- 抽屉（`ExpenseEditor`）结构最完整：5 列键盘/跨月提示/编辑态/离线入队都在，缺的是 常用分类胶囊、分期、组件级数值（Sheet 93dvh/24 圆角、Toast、FOCUS_RING）。
- **加权一致度（按"可机械核对的要求条数"估算）**：
  - 结构与存在性（屏/层/弹层/禁止项/导航/禁用控件）：**≈ 88%**
  - 结构 + 数值 + 状态（§2 组件表 + §4.x 明细数值）：**≈ 61%**
  - 判据口径（§7 38 条）：**67.6%**
  - **综合估计：约 65%（±5）**。差距集中在三类：①判据 18/19/34/36/37 这类"多状态/多档位"要求只做了默认态；②§2 原子组件层未抽象（数值各屏自定，导致数值一致度低但结构看起来对）；③A23/A38 这类全局设施（Toast、主题默认档、提示只一次）缺失。

**阻断缺陷 12 条，不满足放行条件**：即使把 19 条重要缺陷全部接受，判据 11/18/19/22/23/24/25/28/29/34/36/37 不通过本身即违反 §7 的"一条不过就不放行"。
