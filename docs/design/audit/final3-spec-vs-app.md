# 终审复核（第 3 次）：`hw-ui-spec.md` §7 × 鸿蒙端实现 —— B01–B06 修复核实

- **对象**：`docs/design/hw-ui-spec.md`（§7 共 40 行判据）vs `hw-native/entry/src/main/ets/`（33 个 `.ets`，9283 行）
- **性质**：只读审计，仅新增本文件。未编译、未真机 dump；结论全部基于 `grep` + 逐行读码
- **基线**：`docs/design/audit/final-spec-vs-app.md`（上一轮阻断 6 条 B01–B06）
- **本轮口径**：每个"已修"声明都**逐条 grep 调用点 + 找 UI 渲染**，防"写了没接"；同时全仓扫描新死代码与新引入 bug

---

## 一、B01–B06 修复核实

> 结论四档：**已修好** / **部分修好** / **没修好** / **无法静态判定**

| 编号 | 声明 | 结论 | 证据 `file:line` |
|---|---|---|---|
| **B01** | 年档洞察 3 条（最大一笔/最高月/最低月）；年档切入清 `this.report` | **已修好** | `components/report/ReportScreen.ets:54-72`（`reload()` 只按 `tier` 填对应字段，不再交叉污染）；`:141-167` 年档分支独立取 `this.year`，`:149` 最大一笔、`:152` 最高月、`:154-163` 最低月（遍历 `y.months` 取 `totalCents>0` 的最小月）、`:165` 兜底；`:168` `slice(0,3)` 恒 3 条。汇总档 `:132-139` 恒 2 条。**同一档位内容不再随访问路径变** |
| **B02** | tabular-nums：`formatYuan` 文本加 `fontFeature` | **部分修好** | 全仓 `fontFeature('"tnum" on')` 已从 2 处增至 **23 处**（含 `LedgerScreen.ets:468/517/555-560/1065/1176/1248/1263/1318/1333`、`DashboardScreen.ets:186/289/404`、`ReportScreen.ets:464/642`、`SettingsScreen.ets:629/664/704`、`ExpenseEditor.ets:672/704/814/823`、`MainPage.ets:148`）。**但仍有一批金额/数字裸写无 `fontFamily`/`fontFeature`**：`ReportScreen.ets:502`（对照四格值 `Text(f.value)`）、`:565`（年度对照四格值）、`:596`（`repayFact` 的 `Text($$.value)`）、`:664`（洞察行）；`LedgerScreen.ets:505`（`${heroTodos.length} 笔待办`）、`:564`/`:573`（期次/状态词）、`:1261`/`:1270`（年档月格月份/笔数）、`:1331`/`:1339`（全部档年份/笔数）；`SettingsScreen.ets:380`（一级分类笔数 `String(root.expenseCount ?? 0)`）、`:429` 之外的笔数均无；`DashboardScreen.ets:263`（`metric` 的 `Text($$.value)` 无 `fontFamily`）、`:375`（累计条文案）。**判据 29「同一数字在等宽列中宽度一致」在对照四格/累计条/分类笔数列仍不成立** |
| **B03②** | 一级分类行「停用」 | **已修好** | `components/settings/SettingsScreen.ets:421-433`（一级行右侧 `if (!kid.isEnabled)` → `已停用`，else → 行内「停用」按钮）→ `:451`/`:461` `deactivateCategoryById(kid.id)`；实现 `:1499-1517`（`patchCategory` `isEnabled:false`）。二级行 `:440-448` 同款另有「停用」+ 长按 `:457-461`。**表单内「停用分类」按钮** `:1212` → `deactivateCategory()` `:1519-1538`（有 `:1212` 调用点，非死代码） |
| **B03③** | 支付合并二次确认 + 「历史记录归属到目标」提示 | **已修好（但弹窗不渲染，见下）** | 行内「合并」入口 `SettingsScreen.ets:522-531` → `:529 this.confirmMerge(p)` → `:181-188` `confirmMerge()` → `:190-198` `askMerge()` 置 `mergeConfirmText = '合并「X」到另一个支付方式后，它的历史记录会全部归属到目标项。'` 并 `mergeConfirmOpen=true`，`await` Promise。**文案与二次确认逻辑都在**。⚠ 但 `mergeConfirmOpen`/`mergeConfirmResolve` 全仓**无任何渲染点**（`grep mergeConfirmOpen` 仅 `:73`/`:192`，`grep mergeConfirmResolve` 仅 `:75`/`:194`），`askMerge()` 返回的 Promise **永不 resolve** → 点「合并」后 `confirmMerge()` 永久 `await` 挂起，表单根本打不开（详见 §三 阻断 B-NEW1） |
| **B04** | `sheetContent` 补 `member` 分支（`memberForm` 不再死方法） | **已修好** | `SettingsScreen.ets:1056-1074` `sheetContent()` 已有 `if (sheetMode==='category') categoryForm / else if payment / else if member → memberForm / else planForm`；保存键 `:1082-1093` 同款四分支 → `:1089 saveMember()`。`memberForm()` 定义 `:1330-1385`，字段齐全：显示名 `formName` `:1332-1339`、登录名 `formUsername` `:1341-1348`、口令 `formPassword` `:1350-1358`、角色按钮 member/admin `:1360-1379`；`saveMember()` `:234-250` 读 `formUsername/formPassword/formName/formRole` 全部有输入源，`UserCreateRequest` 四字段齐。`sheetTitle()` `:1119-1131` `member` 分支返回 `添加成员`。**调用点** `:1069`（sheetContent 内）确认已接 |
| **B05** | 服务端 `payment-methods` 加 `monthExpenseCount`；设置页用它 | **部分修好** | 服务端 ✓ `server/src/db/repo/payment-methods.ts:41-43`（接口字段）、`:62`（`toApi` 映射）、`:118`（子查询 `substr(e.repayment_date,1,7)=substr(date('now','localtime'),1,7)` 真按本月过滤）。客户端 Api ✓ `common/net/Api.ets:53-54`（`monthExpenseCount?: number`）。**设置页现金/储蓄卡行** ✓ `SettingsScreen.ets:510`（`本月 ${p.monthExpenseCount !== undefined ? p.monthExpenseCount : 0} 笔`）。**✗ 但信用卡行仍用旧字段** `:505`（`${p.billingDay} 日账单 · ${p.repaymentDay} 日还款 · 本月 ${p.expenseCount} 笔`）→ 信用卡行「本月 N 笔」仍是**全部历史笔数**，口径错没修全（详见 §三 阻断 B-NEW2） |
| **B06** | 「未上传 N 条」→「有未上传记录/已全部同步」 | **没修好（禁止项 F19 仍命中）** | `SettingsScreen.ets:855-856` 仍渲染 `Text('待发送 ${this.pendingCount} 条')` + `:857-864` `Button('立即同步')` —— 与上轮 `final-spec-vs-app.md:69` 描述的 `:832-845` 内容**完全一致，仅行号漂移**。仓库全文（含 `.git/COMMIT_EDITMSG`）**搜不到「有未上传记录/已全部同步」**；`grep 未上传` 仅命中 `.git/COMMIT_EDITMSG:4` 的提交说明，代码里根本没这段文案。声明的文案替换**没有落到代码里**。另 `:869` `发送失败 N 条` 死信区按上轮备注可保留，但 `待发送 N 条` 数值命中 F19 明列的"待发送队列"禁止项（详见 §三 阻断 B06 未修） |
| **M05**（本轮顺带核实） | build-stamp 含待同步/离线（AppStorage 共享） | **已修好** | `pages/MainPage.ets:128-139` `stampText()`：`pendingSync>0 → ' · 待同步 N'`，`else if offline → ' · 离线'`；渲染 `:146-152` `Text(this.stampText())`。`LedgerScreen.ets:95` `@StorageLink('pendingSync') sharedPending`，`:136-147` `refreshPending()` 同步写 `this.pendingSync` + `this.sharedPending`，`:144-148` `aboutToAppear` 也写。⚠ 残留：`LedgerScreen.ets:136` `refreshPending()` 全仓 **0 调用点**（`aboutToAppear` 里是内联重复代码，不是调 `refreshPending()`）→ 抽屉保存后 `pendingSync` 不刷新，m31 仍在（见 §二） |

**小结**：B01 已修；B03② 已修；B04 已修；B05 **半修**（信用卡行漏改）；B02 **半修**（tnum 覆盖大增但对照四格/累计条等裸写仍在）；B03③ **逻辑在但弹窗不渲染、Promise 挂起**；B06 **完全没修**（声明的文案替换未落到代码）。

---

## 二、新死代码（方法/状态 + 调用点数）

> 全仓扫描 `@State`/`private`/`static`/`export function` 定义 vs `this.X`/`X(` 调用，逐一 grep 核对。

| 符号 | 位置 | 调用点数 | 说明 |
|---|---|---|---|
| `confirmMerge` | `SettingsScreen.ets:181` | **1**（`:529`） | ✅ 已接（但下游 `askMerge` 挂起，见 B-NEW1） |
| `askMerge` | `SettingsScreen.ets:190` | **1**（`:182`） | ✅ 已接 |
| `mergeConfirmOpen` | `SettingsScreen.ets:73` | **0** 渲染点（仅 `:192` 置位） | ⚠ **死状态**：`grep mergeConfirmOpen` → `:73`/`:192`，无任何 `if (mergeConfirmOpen)` 弹窗渲染 |
| `mergeConfirmResolve` | `SettingsScreen.ets:75` | **0** resolve 点（仅 `:194` 赋值） | ⚠ **死状态**：`grep mergeConfirmResolve` → `:75`/`:194`，无人调用 → `askMerge()` Promise 永不返回 |
| `deactivateCategory` | `SettingsScreen.ets:1519` | **1**（`:1212` 表单「停用分类」按钮） | ✅ 已接 |
| `deactivateCategoryById` | `SettingsScreen.ets:1499` | **2**（`:451`/`:461` 行内） | ✅ 已接 |
| `patchCategory` | `common/net/Api.ets:606` | **3**（`SettingsScreen.ets:280`/`:1512`/`:1532`） | ✅ 已接 |
| `stampText` | `pages/MainPage.ets:132` | **1**（`:146`） | ✅ 已接 |
| `sharedPending` | `LedgerScreen.ets:95` | 3（`:139`/`:146` 写；`:95` 声明） | ✅ 已接（AppStorage 共享给 `MainPage`） |
| `refreshPending` | `LedgerScreen.ets:136` | **0** | ⚠ **死方法**：`aboutToAppear` `:144-148` 内联重复了同样代码而非调 `refreshPending()`；抽屉保存回调 `:1382-1392` 也没调 → m31（`pendingSync` 不即时刷新）**仍在** |
| `memberForm` | `SettingsScreen.ets:1330` | **1**（`:1069`） | ✅ 已接（B04 修复确认） |
| `heatOpacity` | `DashboardScreen.ets:567` | **0** | ⚠ **死方法**：`grep heatOpacity` → 仅定义行 `:567`（`DashboardScreen` 用的是 `heat4()`，`LedgerScreen` 用 `heatOpacity4()`，两个不同函数） |
| `monthByCategory` | `common/store/ExpenseDao.ets:90` | **0**（`grep ExpenseDao.` 仅 `:234/235/257`） | ⚠ **死方法**（离线分类汇总，未接） |
| `schemaReport` | `common/store/Db.ets:155` | **0** | ⚠ **死方法**（`SettingsScreen` 曾有的 `vectorReport/schemaReport` 状态已删，但 `Db.schemaReport` 本体还在） |
| `splitInstallment` | `common/contract/Contract.ets:63` | **0**（除 `VectorRunner` 测试外） | 次要：仅测试向量用 |
| `urgencyLabel` | `common/contract/Contract.ets:131` | **0** UI 调用（`DashboardScreen.ets:18`/`SettingsScreen.ets:21` import 未用；`LedgerScreen.ets:570` 用的是自己的 `urgencyOf` `:659`） | ⚠ **死导入 + 死方法**（仅 `VectorRunner` 测试用） |
| `btnShadow` | `common/ui/UiStyle.ets:64` | **0** | ⚠ **死方法** |
| `cutPathCommands` | `common/ui/UiStyle.ets:126` | **0** | ⚠ **死方法**（与 `cyberClipCommands` `:161` 函数体重复） |
| `deleteCategory` / `patchUser` / `syncStatus` | `common/net/Api.ets:612`/`:666`/`:702` | **各 0** | ⚠ 三个 **死 API 封装**（无 UI 调用） |
| `syncMessage` | `SettingsScreen.ets:106` | **0** 渲染（仅 `:127`/`:129`/`:131` 赋值） | ⚠ **死状态**：`grep syncMessage` → `:106`/`:127`/`:129`，无渲染 → 同步结果用户看不到（延续上轮 m02） |
| `revertDialogOpen` / `pendingResolve` / `revertWarn` / `revertPendingId` | `SettingsScreen.ets:77-80` | **各 0** 渲染/resolve | ⚠ **死状态**：`confirmRevert()` `:769-776` `await` 永不 resolve 的 Promise，无弹窗渲染 → R126 跨月撤销警告**仍不生效**（上轮 M04 未修，且 `confirmRevert` 会永久挂起） |
| `DashboardScreen.todos` / `TodoView` | `DashboardScreen.ets:50`/`:20` | **0** 渲染（`:50` 声明、`:20` interface，无 `this.todos` 引用） | ⚠ **死状态 + 死类型**：概况待办取回但不渲染（上轮 m02 未修；本轮删了 `actTodo`/`todoOpen`，但 `todos`/`TodoView` 留着） |
| `grouped` / `LedgerScreen.tierButton` / `yearBar` / `DashboardScreen.actTodo` / `maxHeat` / `vectorReport` | — | **0** | ✅ **已确认删除**（`grep` 全 0 命中；`DashboardScreen.tierButton` `:235` 是另一个活着的 builder，`:148-150` 三处调用） |

**小结**：本轮**新增死代码 2 个**（`mergeConfirmOpen`/`mergeConfirmResolve` 无渲染 → B-NEW1；`refreshPending` 0 调用），**未清理旧死代码 10+ 个**（`heatOpacity`/`monthByCategory`/`schemaReport`/`btnShadow`/`cutPathCommands`/`deleteCategory`/`patchUser`/`syncStatus`/`urgencyLabel`/`syncMessage`/`revertDialogOpen` 一族/`Dashboard.todos`）。声明的"死代码清理"只做了一部分（`grouped`/`tierButton`/`yearBar`/`actTodo`/`maxHeat`/`vectorReport` 确已删）。

---

## 三、仍存阻断

| 编号 | 位置 | 缺什么 / 错什么 | 严重度 |
|---|---|---|---|
| **B06（未修）** | `components/settings/SettingsScreen.ets:855-856` | **禁止项 F19 仍命中**：仍渲染 `待发送 ${pendingCount} 条` + `立即同步`，即 F19 明列的"待发送队列"数值。声明的「有未上传记录/已全部同步」**代码里搜不到**（全仓 `grep 未上传` 仅 `.git/COMMIT_EDITMSG`）。按上轮备注，`:869` 死信区可保留，但队列数值必须去掉数字或移到流水页计划卡 | **阻断** |
| **B-NEW1** | `components/settings/SettingsScreen.ets:181-198`、`:73`/`:75`/`:192`/`:194` | **支付方式合并流程不可达**：`askMerge()` 置 `mergeConfirmOpen=true` 但全仓**无任何渲染 `mergeConfirmOpen` 的弹窗**（`grep` 仅 `:73`/`:192`），`mergeConfirmResolve` 无人调用 → `askMerge()` 返回的 Promise **永不 resolve** → `confirmMerge()` 永久 `await` 挂起 → **点「合并」按钮无反应，`openPaymentSheet()` 永远到不了**。二次确认文案虽然写了（`mergeConfirmText` `:191`），但用户根本看不到（`mergeConfirmText` 也无渲染点，`grep` 仅 `:74`/`:191`）。**合并功能实为"点了没反应"** | **阻断** |
| **B-NEW2** | `components/settings/SettingsScreen.ets:505` | **信用卡行「本月 N 笔」口径仍错**：`:505` 仍用 `p.expenseCount`（全部历史笔数）而非 `p.monthExpenseCount`；只有现金/储蓄卡行 `:510` 改对了。**数据口径错半边**，与 §4.4 L279「本月笔数」不符（上轮 B05 只修了非信用行） | **阻断** |
| **B-NEW3** | `components/ledger/LedgerScreen.ets:136-147`、`:1382-1392` | **`pendingSync` 不即时刷新**（m31 升级）：`refreshPending()` 定义在 `:136` 但**0 调用点**；`aboutToAppear` `:144-148` 是内联重复代码，抽屉保存回调 `:1382-1392`（`onSaved`）只调 `this.reload()` 不调 `refreshPending()` → 离线记一笔后 `MainPage` stamp 的「待同步 N」与流水顶卡的「已存本机」提示**不会即时更新**，需重进流水页才刷新 | **重要**（数据可信度，非"点了没反应"，故列重要不列阻断） |
| **B02 残留** | `ReportScreen.ets:502`/`:565`/`:596`/`:664`；`LedgerScreen.ets:505`/`:564`/`:573`/`:1261`/`:1270`/`:1331`/`:1339`；`SettingsScreen.ets:380`；`DashboardScreen.ets:263`/`:375` | **tabular-nums 未覆盖到对照四格/累计条/分类笔数列**：这些数字文本无 `fontFamily`/`fontFeature`，判据 29「等宽列中宽度一致」在这些列不成立 | **重要**（判据 29 仍不完全通过，但非阻断级——主流金额已覆盖） |

**其他延续问题**（非本轮新增，未在本轮修复范围）：R126 跨月撤销警告（M04）仍双断链（服务端 `expenseMonth` 已补，但 `confirmRevert()` 无弹窗渲染 → 永久挂起）；§2 原子组件层整层未落地（M01）；汇总档仍 4 块（M02）；年档对照四格口径仍错（M03）；登录页 `ensureFonts` 在 `MainPage.ets:44` 已调（上轮 M12 部分修复，`LoginPage.ets:21` 仍有未用 import）。

---

## 四、结论

- **判据通过率**：**33 / 40 = 82.5%**（40 行口径）
  - **通过 33**：#1–#22、#24、#25、#26、#27、#28、#31、#32、#33、#34、#35、#37、#39、#40
  - **不通过 5**：**#23**（B01 已修，但归入 #23 的判据本身仍需真机三档 dump 确认——静态看已达标，保守计"通过"）实际不通过为 **#29**（B02 残留）、**#36**（B05 半修 + B-NEW1 合并不可达 + B03③ 弹窗缺失）
  - **无法静态判定 2**：#30（卡底空白 ≤40vp，需截图量测）、#38（金额/日期/月份归属需双端对账）
  - 修正计数：**通过 35**（#23 已达标）/ **不通过 3**（#29、#36，及 #23 若保守算则 3 条）/ **无法静态判定 2** → **35/40 = 87.5%**（与上轮持平，因 B06 未修、B02 半修抵消了 B01/B03②/B04 的进步）
- **阻断数 = 3**（较上轮 6 条，B01/B03②/B04 已解，B05/B06 未解，新增 B-NEW1/B-NEW2）：
  1. **B06 未修** 禁止项 F19：`待发送 N 条` 队列数值仍在（声明的文案替换未落码）
  2. **B-NEW1** 支付方式「合并」二次确认弹窗不渲染 → Promise 永久挂起 → 合并功能"点了没反应"
  3. **B-NEW2** 信用卡行「本月 N 笔」仍用 `expenseCount`（全历史），口径错半边
- **重要**：B02 残留（对照四格等数字未走等宽/tnum）、B-NEW3（`pendingSync` 不即时刷新）、M04（R126 仍挂起）、M01/M02/M03 等 14 项延续
- **新死代码清单**（调用点数）：`mergeConfirmOpen` 0 渲染、`mergeConfirmResolve` 0 resolve、`refreshPending` 0 调用、`heatOpacity` 0、`monthByCategory` 0、`schemaReport` 0、`btnShadow` 0、`cutPathCommands` 0、`deleteCategory` 0、`patchUser` 0、`syncStatus` 0、`urgencyLabel` 0 UI、`syncMessage` 0 渲染、`revertDialogOpen`/`pendingResolve`/`revertWarn`/`revertPendingId` 各 0 渲染、`Dashboard.todos`/`TodoView` 0 渲染。已确认删除的：`grouped`/`LedgerScreen.tierButton`/`yearBar`/`DashboardScreen.actTodo`/`maxHeat`/`vectorReport`
- **交付判断**：**不可放行**。B06 禁止项仍命中（一条禁止项即不放行）+ B-NEW1 合并功能不可用 + B-NEW2 数据口径错半边。建议优先级：①B06 文案/位置改对（或移到流水页计划卡）；②B-NEW1 补一个渲染 `mergeConfirmOpen` 的 `AlertDialog` 并在回调里 `mergeConfirmResolve(true/false)`；③B-NEW2 把 `:505` 的 `p.expenseCount` 改成 `p.monthExpenseCount`。这三条修完后，B02 残留与 B-NEW3 可作下一轮收口项。
