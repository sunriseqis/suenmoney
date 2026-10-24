# 2026-10-25 hw 五屏对齐 Web 移动端现状 + 图标改内置 Symbol

## 一、总裁决：真值换了（覆盖 2026-10-24 的「docs 为真值」）

用户裁决（2026-10-25）：**Web 移动端现状优先级高于 docs**。

- `docs/design/hw-ui-spec.md` §0（「docs 为需求真值」）与 §0.1 的 D1–D24 偏差表**整体过时**，
  仅作历史参考（该文件顶部已加效力变更横幅）。
- 与 Web 现状**不冲突**的 docs 裁决（R/D/W 编号，如 R126 跨月撤销警告、R51/R52/R53 流水行口径）
  仍然有效，不可擅改。
- 推导出的验收方式：逐屏对照 Web 移动端 CSS 原文复刻，锚点是
  `web/src/styles/proto/views.css` / `app.css` / `base.css` / `theme.css` 的行号
  （本轮用过的锚：settings-tabs:461、stab:462、set-row:477、cat-admin:500、cat-rail-btn:502、
  cat-kid:520、todo-mark:437、theme-card:734、chip:382、btn:215、icon-btn:272、sheet:566、
  empty:645、field-l:404、input:411）。
- **Web 的 quirk 也照抄**（例：openCatCreate 新增类别时 formParent 落到第一个一级分类 id——
  Web 就是这么写的；doneTodos 顺序 = skipped 在前 + confirmed 在后）。

## 二、设置屏结构裁决（hw 专属，Web 没有对应物）

| 项 | 裁决 |
|---|---|
| 分区 | 三区：账目 / 计划与还款 / 设备（web 的「数据 + 家庭」合并为「设备」） |
| 设备区内容 | 仅 主题 / 修改密码 / 检查更新 三卡 |
| 文件流 | 导出/导入/备份/快照/WebDAV/账单导入整卡不渲染 |
| 不做 | 成员、登录设备、会话列表、危险区、关于卡 |
| 退出登录 | **不做**——web SettingsView 与 App.vue 本来就没有 logout |
| 检查更新 | `Api.health()` 显示「服务端 v{version} · 连接正常」 |
| 修改密码 | `POST /api/auth/me/password`（新增 `Api.changePassword` + `ChangePasswordBody/Request`） |
| 危险动作 | 收进「更多」菜单（bindMenu 适配 more-menu 视觉）；R126 跨月撤销警告保留，状态驱动弹层（不用 AlertDialog） |

## 三、图标层落地（交接单执行 + 方案升级）

执行了 `docs/reports/hw/图标改内置symbol-交接单.md`，第五节 brands 方案**升级**：

| 层 | 旧（已删） | 新 |
|---|---|---|
| 分类图标 | `IconPaths.ets`（86 条 Lucide path）+ `IconView.ets`（Shape/Path 手绘，真机发糊） | `CatIconView`：内置 Symbol 渲染；`CAT_ICON_OPTIONS` 24 条「lucide 键 → sys.symbol」映射（存 web ICON_REGISTRY 键保持互通，hw 近似渲染）+ 兜底 |
| 支付品牌（支付宝/微信/云闪付/京东/抖音） | 1024 坐标系填充 path 手绘 | **随包 SVG 媒体** `resources/base/media/pay_*.svg` + `Image` 原生解码 + `fillColor` 运行时染品牌色——交接单方案 A 的 path 手绘也放弃了，SVG 媒体任意尺寸都清晰 |
| 支付非品牌（银行卡/信用卡/现金/银行转账/其它钱包） | Lucide 描边 | 内置 Symbol：`bank_card` / `creditcard` / `coins` / `building` / `wallet` |
| 组件 | `IconView({path, filled, iconSize})` | `CatIconView({catName, iconSize, color})`、`PayIconView({payName, payIcon, iconSize, colorOverride})`；`PayOption` 已导出（设置屏图标选择网格要用） |

- `resolvePayVisual()` 判定顺序（显式 icon > 名字反推 > 兜底银行卡）与品牌色表**未动**。
- `CATEGORY_COLORS` 16 色槽与 `categoryColorOf()` **未动**。

## 四、五屏重写概览（代码即真相，此处只记口径）

| 屏 | 要点 |
|---|---|
| LedgerScreen | 对齐 web 移动端流水页（R51 无组头 / R52 行内日期 / R53 字段序 / R54 无还款药丸 / R55 合计只在筛选时） |
| DashboardScreen | hero 同口径修复；`SummaryReport` 补 `perExpenseAverageCents` / `categories` / `members` 可选字段供概况页用 |
| ReportScreen | 三档（本月/本年/汇总）+ headCard/composeCard（chips + DonutChart 136 + 虚线图例 + dim-bars + 节奏 7 柱）/movers/repay/annualBanner；`deltaArrow()` 等取值器 |
| AnnualScreen（新） | yearBar / overview / months 12 柱 / peak+largest（g2 双列）/ topCat；`@StorageLink('annualYear')` |
| DonutChart | PDonut 几何 1:1；**prop 名 `ringSize`**（`size` 与组件属性方法冲突） |
| MainPage | annual 路由接入：`backTarget()`（annual→report 其余→ledger）、PAGE_META「年度报告」 |
| SettingsScreen | 三区 + 单 `bindSheet` 按 `sheetKind` 切 cat/pay/merge/plan 四表单 + toast 叠加层 + bindMenu more-menu + R126 状态驱动弹层；`openCatCreate` 复刻 web quirk |

## 五、编译坑清单（本轮实战，全部 BUILD SUCCESSFUL 验证）

| 坑 | 症状/修法 |
|---|---|
| `VerticalAlign.Stretch` | 不存在；用 `VerticalAlign.Top` |
| CustomComponent 成员叫 `size` | 与继承的 `size()` 属性方法冲突 → 改名 `ringSize` |
| `Flex` 没有 `.alignItems()` 链式 | 只能构造器传 `alignItems: ItemAlign.Center`（**ItemAlign**，不是 VerticalAlign） |
| `shadow(undefined)` | 编译不过（联合类型里没有 undefined）→ 传 `{ radius: 0, offsetX: 0, offsetY: 0, color: Color.Transparent } as ShadowOptions` |
| `Scroll` 没有 `.align()` | 直接删 |
| `fontFamily(... : undefined)` | 同 shadow 问题 → 恒传值：`this.isCyber() ? fontMonoOf() : fontBodyOf(false)` |
| builder 内 possibly-null 链 | `this.railRoot().name` 编译报 null 访问 → 拆取值器 `railRootName()` |
| 对象字面量无类型 | `arkts-no-untyped-obj-literals`（Api.ets:488 实锤）→ 命名 interface + 类型化变量 |
| `LengthMetrics` | Flex `space` 要用；需 `import { LengthMetrics } from '@kit.ArkUI'` |
| `'100%%'` | width 字符串手滑双百分号，静默失效——grep 一遍 |

## 六、sys.symbol 名字权威校验法（省一轮构建）

**注册表**：`C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\ets\build-tools\ets-loader\sysResource.js`
的 `symbol` 段（约 3372 行起，**4045 个名字**，格式 `name: id`）。

- 别查错文件：`hms\ets\sysResource.js` 只有 string/media 段，**没有** symbol 段；
  `toolchains\id_defined.json` 里是 `ohos_*` 开的另一套。
- `$r('sys.symbol.xxx')` 名字必须字面量，坏名字**编译期**才报错——写码前先查注册表。
- 本轮实例：`tag`、`pencil` **不存在** → 换 `label`、`square_and_pencil`；
  `trash`、`checkmark` 存在；`CAT_ICON_OPTIONS` 24 个与 `PAY_OPTIONS` 5 个 symbol 全部核验通过。
- PowerShell 查法：读入后按 `^\s*([a-z0-9_]+):\s*(\d+),?\s*$` 逐行解析到 symbol 段结束。

## 七、状态与遗留

- `devecocli build` **BUILD SUCCESSFUL**；已部署 Mate 90 Pro 模拟器（`127.0.0.1:5555`）并启动成功。
- 服务端 `192.168.89.10:5310` 连通正常（`{"ok":true,"service":"suenmoney","version":"1.1.6"}`）。
- **设备走查未做**：重装应用清掉了本机 token，测试账号口令从未入库（也不应入库），
  本轮用户选择跳过登录验证。
- 遗留（下轮，有凭据后）：
  1. 登录 → 设置屏三区走查（分类/支付 CRUD、计划期次确认/忽略/恢复/撤销、主题切换、改密码、检查更新）；
  2. 截图 + `recognize_ui_components` 复核全部重写屏（流水/概况/报表/年度/设置 × candy/cyber）；
  3. 重验 `docs/reports/hw/2026-10-24-设备走查记录.md` 受影响条目（该文件已加增补说明）。
- 环境备忘（Windows 主机）：构建前先
  `$env:Path = "C:\Program Files\Huawei\DevEco Studio\tools\node;$env:Path"; devecocli build`（workdir `hw-native`）；
  `devecocli devices` 不存在，是 `devecocli device list`。
