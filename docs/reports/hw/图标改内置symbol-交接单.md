# 图标改用鸿蒙内置 Symbol —— 交接单（给 DevEco Code）

> ✅ **已执行（2026-10-25，commit 4850406）**：`IconPaths.ets` / `IconView.ets` 已删除，
> 分类图标改为 `CatIconView`（内置 Symbol），支付品牌改为随包 `pay_*.svg` + `Image` 染色，
> 非品牌支付图标走内置 Symbol。本文件保留作为历史记录，**不再作为待办**。
> 后续相关裁决见 `docs/memory/2026-10-26-记账页交互与多服务器模型.md`。

> **状态（2026-10-25）：已落地，方案在第五节基础上升级。**
> 品牌图形不再用 Path 手绘（方案 A 也放弃了），改为**随包 SVG 媒体**
> （`resources/base/media/pay_*.svg`）+ `Image` 原生解码 + `fillColor` 染品牌色；
> 非品牌 5 种用内置 Symbol。分类图标走 `CatIconView` + `CAT_ICON_OPTIONS`。
> `IconPaths.ets` / `IconView.ets` 已删。经过与编译坑见
> `docs/memory/2026-10-25-五屏对齐web移动端与内置Symbol.md`。

> 目标：把现在基于 Lucide SVG 路径手绘的图标，全部换成**鸿蒙系统内置 Symbol**（`sys.symbol.*` + `SymbolGlyph`）。
> 不做名字映射表：**每个分类直接指定一个内置符号**，改完删掉 Lucide 那套。

---

## 一、为什么要换

现在这套是「把 Lucide 的 SVG `d` 字符串塞进 ArkUI `Path` 组件手绘」。几何是对的（和 Web 同源），
但在真机上视觉崩坏：描边过粗/串色/发糊。原因是在 24 单位空间里画 2 单位描边，
再靠 `scale` 放到 20vp，缩放后描边和抗锯齿都不可控。

**换内置 Symbol 的好处**：系统自带矢量字体渲染，任何字号都清晰、自带字重和多色渲染策略、跟随主题。

---

## 二、改动范围（4 个文件 + 3 个调用点）

### 要删

| 文件 | 说明 |
|---|---|
| `entry/src/main/ets/common/ui/IconPaths.ets` | 120 行，86 个 Lucide path + 6 个支付品牌 path —— **整个删掉** |
| `entry/src/main/ets/common/ui/IconView.ets` | 52 行，`Path`/`Shape` 渲染器 —— **整个删掉** |
| `CategoryIcon.ets` 里的 `ICON_GLYPH`、`categoryGlyph()`、`categoryIconPath()`、`resolveIconKey()` | 换成返回内置符号的实现（见下） |
| `PaymentIcon.ets` 里的 `PAY_BRAND_PATHS` 依赖与 `visualOf()` 的 path 部分 | 见第五节（支付品牌是特殊情况） |

### 要改的 3 个调用点

| 位置 | 现在 | 改成 |
|---|---|---|
| `components/ledger/LedgerScreen.ets:1178-1191` 流水行分类徽位 | `Stack(){ IconView({ path: categoryIconPath(...), iconSize: 20, color }) }` 包在 44×44 的徽位里 | `SymbolGlyph($r('sys.symbol.xxx')).fontSize(20).fontColor([分类色])` |
| `components/settings/SettingsScreen.ets:588-596` 计划卡身份图标 | `IconView({ path: categoryIconPath(...), iconSize: 11, color: ink2 })`，外层 18×18 | 同上，`fontSize(11)` |
| `components/settings/SettingsScreen.ets:493-501` 支付方式列表头像 | `IconView({ ..., filled: brand })`，外层 28×28 | 见第五节 |
| `components/expense/ExpenseEditor.ets:534-548` 记账抽屉支付快捷胶囊 | `IconView({ ..., iconSize: 13, filled })` | 见第五节 |

删完后应无 `IconView` / `IconPaths` 引用（`grep -rn "IconView\|IconPaths" entry/src/main/ets` 结果为空）。

---

## 三、分类 → 内置符号：请直接挑符号（不用建映射表）

上面这套 `NAME_TO_ICON`（26 条）是**现在**的映射，**不要照搬**。请按下面 26 个分类，
**各自直接指定一个 `sys.symbol.*`**（你比我清楚系统里有哪些符号；挑不到好的就退到相近的通用符号，
比如 `doc_text` / `square_grid_2x2`）。

| 分类名 | 语义 |
|---|---|
| 餐饮 / 外卖 / 下馆子 | 吃饭、外卖、餐厅 |
| 买菜 | 超市购物车 / 生鲜 |
| 交通 | 公共交通 |
| 打车 | 出租车/网约车 |
| 加油 | 油枪/加油站 |
| 购物 | 购物袋/买买买 |
| 衣物 | 衣服 |
| 数码 | 手机/电脑类 |
| 居住 / 房租 | 房子 |
| 水电 | 电/水电费 |
| 医疗 | 医院/心跳 |
| 药品 | 药丸 |
| 娱乐 / 游戏 | 游戏手柄 |
| 电影 | 电影/胶片 |
| 健身 | 哑铃 |
| 学习 | 打开的书 |
| 教育 | 学士帽 |
| 人情 | 礼物/红包 |
| 宠物 | 爪印 |
| 通讯 | 电话 |
| 工资 | 钞票/钱包 |
| 还款 | 信用卡 |

额外要知道的两点：
1. **分类可能是用户在数据库里自建的**，名字不在上表里。所以实现必须有一个兜底符号（比如 `doc_text` 或 `square_grid_2x2`），不能出现"空徽位"。
2. 分类颜色还是走现有的 `categoryColorOf(name, explicit)`（16 色槽，已和 Web 对齐）——**只换图形，不动颜色逻辑**。

---

## 四、`SymbolGlyph` 用法要点（我踩过的坑）

```ts
// fontColor 收的是「数组」，不是单个颜色 —— 这是最容易写错的
SymbolGlyph($r('sys.symbol.xxx'))
  .fontSize(20)          // 数字单位是 fp
  .fontColor([color])    // ← 必须是数组
```

- 多色图标可用 `.renderingStrategy(SymbolRenderingStrategy.MULTIPLE)`；单色渲染用 `SINGLE`。
- `$r('sys.symbol.xxx')` 的**名字必须是字符串字面量**，不能拼接变量（`$r('sys.symbol.' + n)` 编译不过）。
  所以「名字 → 符号」的选择最终要落成 `if/else` 或 `Record<string, Resource>`（值里写死字面量）。
- SymbolGlyph 不支持子组件，也不支持文本通用属性。
- 大小用 `fontSize` 控制，**不要再套 `scale`**。

---

## 五、支付图标是特殊情况（重要）

支付方式有 10 种，其中 **6 种是品牌图形**：支付宝 / 微信支付 / 云闪付银联 / 京东支付 / 抖音支付 / 银行卡。
**系统内置符号里没有品牌 logo**，所以这 6 个只能二选一：

- **方案 A（推荐）**：品牌图形保留现在的填充路径（`PAY_BRAND_PATHS`），
  其余 4 种（信用卡 / 现金 / 银行转账 / 其它钱包）改用内置符号。
  这样只留 `PaymentIcon.ets` 里 6 条品牌路径，删掉 Lucide 那 86 条。
- **方案 B**：全部退化成通用内置符号（钱包、钞票、银行卡、楼宇），不再区分品牌。
  视觉上会丢掉品牌辨识度，但代码最干净。

品牌色表保持不变（支付宝 `#1677FF`、微信 `#07C160`、云闪付 `#D83B01`、京东 `#E1251B`、
抖音 `#111827`、银行卡 `#4F46E5`、信用卡 `#F59E0B`、现金 `#10B981`、银行 `#2563EB`、其它钱包 `#6B7280`）。
判定顺序也保持不变（显式 icon 优先 → 按名字关键字反推 → 兜底银行卡），这段逻辑在
`PaymentIcon.ets` 的 `resolvePayVisual()` 里，**不要重写**，只把返回的 `path/filled` 换掉。

---

## 六、验收标准

1. `devecocli check arkts` 无错；`hvigorw assembleHap` BUILD SUCCESSFUL。
2. 装机后流水页每一行左侧徽位里都有图标，**描边清晰不发糊**，颜色 = 该分类的分类色。
3. 徽位里图标视觉尺寸 ≈ **20vp**（徽位 44vp）。设置页计划卡图标 ≈ 11vp。
4. 自建分类（名字不在上表）**不出现空徽位**。
5. `grep -rn "IconView\|IconPaths" entry/src/main/ets` 结果为空（除支付品牌路径按方案 A 保留的情况）。
6. 截图自查：把流水页首屏截下来，逐个看图标是不是"能认出是什么东西"。

---

## 七、直接可用的提示词

> 项目在 `C:\work\suenmoney\hw-native`（HarmonyOS NEXT，ArkTS/ArkUI，API 26）。
>
> 任务：把图标渲染从"手绘 Lucide SVG 路径"改成"鸿蒙系统内置 Symbol"。
>
> 现状：
> - `entry/src/main/ets/common/ui/IconPaths.ets` 存了 86 个 Lucide 的 path 字符串；
> - `entry/src/main/ets/common/ui/IconView.ets` 用 `Shape`+`Path` 手绘，真机上描边发糊、视觉崩坏；
> - 调用点有 4 处：`LedgerScreen.ets` 流水行徽位、`SettingsScreen.ets` 计划卡图标与支付方式头像、`ExpenseEditor.ets` 支付快捷胶囊。
>
> 请这样改：
> 1. 删掉 `IconPaths.ets` 和 `IconView.ets`。
> 2. `CategoryIcon.ets` 里把 `categoryIconPath()/categoryGlyph()/resolveIconKey()/ICON_GLYPH` 全部替换成
>    「按分类名直接返回一个 `sys.symbol.*` 资源」的实现，用 `SymbolGlyph($r('sys.symbol.xxx')).fontSize(20).fontColor([color])` 渲染。
>    `categoryColorOf()` / `CATEGORY_COLORS` 这套 16 色槽**保留不动**。
> 3. 分类到符号请你自己挑合适的内置符号（不要照抄原来那套 Lucide 名字），覆盖这些分类名：
>    餐饮、外卖、下馆子、买菜、交通、打车、加油、购物、衣物、数码、居住、房租、水电、医疗、药品、
>    娱乐、游戏、电影、健身、学习、教育、人情、宠物、通讯、工资、还款；**另有兜底符号处理用户自建分类**。
> 4. 支付方式：6 种品牌（支付宝/微信/云闪付/京东/抖音/银行卡）系统里没有对应符号，
>    保留它们现有的填充路径；其余 4 种（信用卡/现金/银行转账/其它钱包）改用内置符号。
>    品牌色表和 `resolvePayVisual()` 的判定顺序不要动。
> 5. 注意：`SymbolGlyph.fontColor()` 收的是**数组**；`$r('sys.symbol.xxx')` 的名字必须是字面量，不能拼接变量。
>
> 验收：`devecocli check arkts` 无错、BUILD SUCCESSFUL、装机后流水页每行徽位都有清晰图标且颜色是分类色、
> 徽位内图标约 20vp、自建分类不出现空徽位。
