# 开源项目设计调研 —— 针对 `ui-review.md` 的返工清单

调研日期 2026-09-27。目的：在动手返工前，先看清同类项目是怎么处理这批问题的。

**方法说明**：以下全部来自**读源码**（GitHub API 取目录树 + `raw.githubusercontent.com` 取文件），
不是看截图或体验 Demo。所以「他们这么做」是有据可查的；凡是「这样更好」都是我的推论，
实现时必须自己验证，不要当成结论。

| 项目 | ★ | 技术 | 为什么选它 |
|---|---|---|---|
| [Maybe Finance](https://github.com/maybe-finance/maybe) | 54.3k | Rails + Hotwire | 公认 UI 最精致的开源记账项目。**注意：已停服归档（2025-07）**，只作参考 |
| [Actual Budget](https://github.com/actualbudget/actual) | 29.2k | React + TS | 本地优先，桌面与移动**两套界面**，与我们架构最接近 |
| [Firefly III](https://github.com/firefly-iii/firefly-iii) | 24.7k | PHP + Blade | 自托管服务端型，功能最全 |
| [Wallos](https://github.com/ellite/Wallos) | 8.6k | PHP | **专做周期订阅支出**，D3 最相关 |
| [Cashew](https://github.com/jameskokoska/Cashew) | 4.7k | Flutter | 移动端首页可配置卡片 |
| [ExpenseOwl](https://github.com/Tanq16/ExpenseOwl) | 1.5k | 单页 HTML | "极简自托管记账"的对照样本 |

---

## 一、跨项目共性结论（最有价值的部分）

### 结论 1：响应式不是「撒断点类」，是「先决定这条内容在窄屏要不要存在」

- **Actual** 走了极端：`components/responsive/{index,narrow,wide}.tsx` 做**组件级整页替换**。
  `narrow.ts` 里注册了 11 个移动端专属页面实现（Budget / Accounts / Account / Rules /
  RuleEdit / Schedules / ScheduleEdit / Category / Payees / PayeeEdit / BankSync），
  并且**按变体懒加载**（`webpackChunkName: "narrow-components"`）—— 手机不会下载桌面代码。

  ```tsx
  export function NarrowAlternate({ name }: { name: ... }) {
    const { isNarrowWidth } = useResponsive();
    return <LoadComponent name={name} importer={isNarrowWidth ? loadNarrow : loadWide} />;
  }
  ```
  断点有**四档**：narrow / small / medium / wide。

- **Maybe** 没做两套组件，但有个**反复出现的固定搭配**：

  | 场景 | 桌面 | 移动 |
  |---|---|---|
  | 带头像的区块布局 | `flex-col lg:flex-row` | 竖排 |
  | 列表的附加列 | `hidden lg:flex` / `hidden lg:block` | 直接不渲染 |
  | 主要动作按钮 | `hidden lg:inline-flex`（**带文字**） | `rounded-full lg:hidden`（**纯图标圆按钮**） |
  | 设置导航 | `hidden md:block` 侧栏 | `md:hidden` 横向条目 |

**对我们意味着什么**：我用 `lg:hidden` / `lg:grid-cols-2` 是在**同一套 DOM 上挪位置**，
而两家都是先判断「这块内容在窄屏上该不该出现」。这正是"偷懒"的技术根源 ——
固定双栏不是布局决策，是**我没决定哪块内容在桌面该以什么形态存在**。

**但不要照搬 Actual 的 11 套页面**：它的数据模型比我们复杂一个量级。
我们的量级更适合 Maybe 的做法：**少数页面级双实现 + 大量「列级增删」**。

### 结论 2：页面不写死栏数，区块可增删、可配置

| 项目 | 做法 |
|---|---|
| **Maybe** 仪表盘 | **单列堆叠**（`w-full space-y-6`），区块用 `<% if Current.family.accounts.any? %>` 整体切换；**没有数据时是整页空态**，不是一个空洞 |
| **Cashew** 首页 | 12 张**用户可配置**的卡片（`editHomePage`）与 `homePage*` 系列组件：AllSpendingSummary / Budgets / CreditDebts / Heatmap / LineGraph / NetWorth / Objectives / PieChart / UpcomingTransactions / WalletList / WalletSwitcher |
| **Actual** 报表 | 报表页是**可拖拽的 `ReportCard` 卡片网格**（`NON_DRAGGABLE_AREA_CLASS_NAME` + `useContextMenu` + `useIsInViewport` 懒渲染），配 `ChooseGraph` 让用户选图表类型，`SaveReport` 存配置 |

**三家的共同点**：内容区是**可组合的块集合**，不是一格一格塞死的容器。
固定 `grid-cols-2` 从结构上就无法表达「这块可能不存在」—— 这就是 P1 的根因。

### 结论 3：列表行是网格 + 按断点「增删列」，不是把几段摊开

**Maybe** 的交易行是 CSS grid，附加信息是新列、在窄屏隐藏：

```erb
<div class="text-secondary text-xs font-normal hidden lg:block">   <!-- 账户列 -->
<div class="hidden lg:flex items-center gap-1 col-span-2">          <!-- 分类列 -->
<div class="col-span-2 ml-auto text-right">                         <!-- 金额列 -->
```

**这正是我们 D4「四段摊开、中间空 600px」的解法**：空出来的宽度要用**新列**去填，
而不是让弹性段摊平。我们缺的列是：备注 / 支付方式 / 还款日。

### 结论 4：行内操作一律收进 ⋮ 溢出菜单

| 项目 | 行内操作 |
|---|---|
| **Maybe** 分类行 | 只有「色块徽标 + 名称」和右侧一个 `⋮`（菜单里是 编辑 / 删除） |
| **Wallos** 订阅卡 | `.actions-expand` + `fa-ellipsis-v`，并额外有 `.mobile-actions` 一套（`.mobile-action-edit/delete/clone/renew`） |

**我们现状**：分类每行摆一个「停用」按钮，支付方式每行也是。
分类二级项多的时候，屏幕上就是几十个重复按钮。这不是"信息密度高"，是噪音。

### 结论 5：设置页 = 独立 layout + 导航 + 每个区域独立路由

**Maybe** 的实现（`app/views/layouts/settings.html.erb`）：

```erb
<div class="flex flex-col lg:flex-row h-full bg-surface">
  <div class="p-4 w-full md:w-96 shrink-0 md:h-full md:overflow-y-auto">   <!-- 384px 侧栏 -->
    <%= render "settings/settings_nav" %>
  </div>
  <main class="px-4 pt-2 md:py-4 md:px-10 grow flex h-full overflow-y-auto">
    <div class="relative max-w-4xl mx-auto ...">                          <!-- 内容列限宽 -->
```

导航是**数据驱动的分组列表**（`nav_sections`），三组：

- 通用：Profile / Preferences / Security / API Key / Self-hosting / **Accounts** / **Imports**
- 交易：Tags / **Categories** / Rules / Merchants
- 其他：What's New / Feedback

**关键**：`Categories` 是侧栏里的一项，指向**它自己的页面**。
桌面用侧栏 + 分组标题（`uppercase text-secondary text-xs` + 分隔线），
移动端同一份数据渲染成横向条目条（`md:hidden`）—— **就是用户说的「一级目录 tab 页」**。

**分类页本身**（`categories/index.html.erb`）的组织：

1. 顶部：标题 + 右侧 `⋮`（删除全部）+ 主按钮「新建」（`frame: :modal` 开模态）
2. **先按类型分组**：Incomes / Expenses 各一组
3. 每组一个头部：`分组名 · 数量`（小号大写次级色，inset 底色）
4. 组内：**父分类一行，其子分类紧随其后**（不是折叠，是直接列在下面），
   子分类用 `corner-down-right` 箭头**按该分类自己的颜色**着色做缩进提示
5. 间隔：**只在父分组之间**放 `shared/ruler`，不是每行都放
6. 每行右侧 `⋮`（编辑 / 删除）

对照我们的分类区：所有一级+二级一次性平铺、每行一个「停用」按钮、
无分组计数、无缩进提示 —— 就是"极其冗长"的来源。

### 结论 6：「记一笔」不进底部栏的"特殊按钮"位

| 项目 | 做法 |
|---|---|
| **Actual** | 底部导航是 **3 列 × 可展开 3 行**的抽屉（`COLUMN_COUNT = 3`，`ROW_HEIGHT = 70`，默认 1 行、可上下拖拽展开或隐藏，`useScrollListener` 滚动时收起）。第一行是 **Budget / Transaction / Accounts**，而 `Transaction` 指向 `/transactions/new` —— **「记一笔」就是第 2 个普通 tab**，与邻居同样的图标 + 文字尺寸 |
| **Maybe** | 列表页头部右侧：桌面 `hidden lg:inline-flex` 带文字的「New transaction」，移动 `rounded-full lg:hidden` **纯图标圆形按钮** |

**没有一家把它做成"挤在 tab 之间的填充胶囊"**（= 我们现在的样子）。
Actual 的做法是把"新增"当作导航的一等公民；Maybe 的做法是把它当作**页面的主操作**放在头部。

### 结论 7：周期/计划类内容需要比交易更"重"的呈现

**Wallos** 的订阅卡（`includes/list_subscriptions.php`）字段结构：

```
.subscription  →  .subscription-main
                    .logo            （服务图标）
                    .name
                    .price           .original_price   （原价对比）
                    .next            （下次付款日）
                    .cycle           （周期）
                    .payment_method
                    .subscription-progress-container  →  .subscription-progress  （进度条）
                  .actions / .actions-expand（⋮）
                  .mobile-actions（移动端单独一套操作）
```

**这正是 D3「计划与流水极度割裂」的反面样本**：它们把周期项当成一种**有身份的对象**
（图标 + 名字 + 价格 + 下次时间 + 周期 + 支付方式 + 进度），而我们的待办卡只有
「名字 + 期数 + 日期 + 金额 + 两个按钮」，没有任何身份识别物。

### 结论 8：颜色用在「身份标识」和「进度」上，不用来表示数值好坏

- **Maybe** `_group_weight.html.erb`：用 **10 个小方块**表达权重（`i < (weight/10).ceil` 点亮），
  方块颜色由调用方传入的 `color` 决定 —— 比一条纯色进度条更有刻度感，且天然支持分类配色
- **Wallos**：卡片上的 `.subscription-progress` 进度条
- 两家都**不给金额本身染色**

这与我们「支出金额不加语义色 + 颜色只表达需要行动」的方向一致，可以继续沿用。

### 结论 9：ExpenseOwl 的反面证明 —— 它根本没有桌面布局

ExpenseOwl（1.5k★，`index.html` 24KB + `style.css` 16KB + 一个 Go 后端，**全部 15 个文件**）
号称"极简但好看"。它做到的代价是：

- **样式表里没有任何宽度断点**，只有 `prefers-color-scheme`。它只有一个 `.container` 单列
- **不用 Web 字体**（`font-family: -apple-system, BlinkMacSystemFont, ...`），
  但**金额用 `font-family: monospace`** —— 和我们 `tabular-nums` 是同一个动机
- 圆角只有 3 / 4 / 8 / 9999px 四档
- **「记一笔」的表单是原地展开的**（`toggleExpenseFormBtn` → `.form-container`），
  不是抽屉、不是模态、不是独立页面
- 导航只有 header 里几个图标按钮（`view-button`），且 **`/settings` 是独立页面**，不嵌在页内
- `settings.html` **43.9KB，是这个小项目里最大的模板**（比 `index.html` 还大 83%）

**两条结论**：

1. ExpenseOwl 之所以不需要适配桌面，是因为它**不试图使用宽屏** —— 内容就是一条单列流水。
   这直接反驳了我原来的做法：我既用不满 1120px（流水收窄到 768px 才对），
   又硬要分两栏。**没有足够内容去填两栏时，正确的答案是只用一栏。**
2. 一个 15 个文件的项目，设置页占了最大的一块。**设置是所有项目的复杂度汇聚点**，
   D5 值得单独花一轮。

---

## 二、逐条对应到我们的问题

| 编号 | 问题 | 参考做法 | 落回本项目的方向（待定，不是决定） |
|---|---|---|---|
| **P1** | 双栏固定、空栏留洞 | Maybe 单列堆叠 + 页面级空态；Cashew/Actual 可配置卡片集合 | 放弃固定双栏。首页改为**单列堆叠的区块流**，或做成可配置卡片；空态做成整页状态 |
| **P2** | 抽屉通栏无适配 | Maybe 用 `frame: :drawer`；Actual 用 `NarrowAlternate` 换整页 | 桌面端抽屉改为**右侧定宽面板**（如 480–560px），移动端保持底部抽屉；即一份逻辑、两种容器 |
| **D1** | 页面构建过于简略 | Maybe 每组都有「分组名 · 数量」头部、区块有 inset 底 + 圆角卡片层次 | 引入**区块/层级词汇**：卡片容器 → 分组 → 行；不再是一片平铺 |
| **D2** | 支出构成可重新设计 | Actual `ReportCard` 可拖拽卡片网格 + `ChooseGraph`；Maybe Sankey 现金流图 | 报表改为**卡片网格**；先补齐分类配色（否则任何图表都只有一种蓝） |
| **D3** | 计划与流水割裂 | Wallos 订阅卡（图标+进度+下次日期+⋮） | 计划卡补上**身份物**（图标、进度、下次付款日），并采用与流水行同族的行结构 |
| **D4** | 流水可更好看 | Maybe 网格 + `hidden lg:block` 加列 | 桌面端**加列**（备注/支付方式/还款日），而不是收窄绕开；去掉重复的还款日药丸 |
| **D5** | 设置极冗长 | Maybe 独立 layout + 侧栏/tab + 分类独立页 + 组内父带子 + 行内 ⋮ | 设置拆路由；移动端导航变横向 tab 条；分类区加分组计数、缩进提示，动作收进 ⋮ |
| **D6** | 计划应进设置 | Maybe 把 Accounts/Imports/Categories 放在设置侧栏里 | 与用户意见一致，可做。（反向样本：Actual 把 Schedules 放在主导航 —— 因为他们的 Schedules 是预算流的一部分，我们的房贷/分期是低频账户级配置，更像 Maybe 那些设置项） |
| **M1** | 记一笔与底栏割裂 | Actual 当普通 tab；Maybe 圆形图标按钮 | 两条路，需用户选：**做成普通 tab**（Actual 式）或**移出底栏、做成页面主操作**（Maybe 式） |

---

## 三、几处「他们和我们的决定相反」，记录但不改

| 项 | 开源做法 | 我们的决定 | 说明 |
|---|---|---|---|
| 提醒送达 | **Wallos 用服务端 cron**（`endpoints/cronjobs/sendnotifications.php`、`updatenextpayment.php`），支持邮件/推送 | 只做开屏仪表盘，无推送、无定时任务 | 用户当初明确选了仪表盘。若要改，代价是加一套定时任务与推送凭据 |
| 到期自动入账 | Wallos 有服务端 `updatenextpayment` 自动推进 | 需确认或显式开自动，不做服务端定时 | 同上，用户的决定，不改 |
| 多账本 | Maybe/Firefly/Actual 都支持多账户/多预算 | 一套账 | 用户的决定，不改 |

---

## 四、我没做的（避免你以为覆盖到了）

- **没看截图**，所以本文件里没有任何"好不好看"的判断依据 —— 全是结构与信息架构
- 没调研**移动端的离线状态呈现**（Actual 是本地优先，这块很重，等移动端阶段再看）
- 没调研**表格/虚拟滚动**（我们数据量小，暂时不需要）
- **Firefly III 只看了目录规模，没深入读**。它是桌面 Web 型，对 P1/P2 的参考价值低于 Maybe，
  但它的报表模块（预算 / 分类 / 账户多维度）值得在定 D2 时单独看一轮
- **没统计视觉层面的东西**（间距节奏、圆角尺度、字重搭配）。这类结论必须看截图或跑起来，
  读源码读不出来。如果后面需要，正确做法是把几个项目本地跑起来截图对照，
  而不是继续读代码
