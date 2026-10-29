# ios/SuenMoney —— iOS 原生客户端（SwiftUI）

> 目标 **iOS 26+**。**不含 Capacitor、不含 WebView。**
> 口径：代码层面完全对齐鸿蒙端（`hw-native/`）；图标按 iOS 可用操作（SF Symbols）；
> 功能与视觉保持一致。详见 `docs/plan/2026-10-29-iOS开发目标与交付标准.md`。

## 目录

```
App/        SuenMoneyApp.swift（@main）、Info.plist
Auth/       AuthStore.swift（登录态）
Contract/   Contract.swift（金额/日期/紧急度/环图/ULID）、VectorRunner.swift（三端共用向量）
Net/        Models（服务端契约）、Api（24 条路径）、ApiClient（URLSession + 分类错误）
            ServerConfig（Keychain 令牌 + 多服务器）、ServerRouter（顺序探活）
Store/      Db（SQLite3 七张表）、ExpenseDao、DictionaryDao、LastPick
Sync/       Outbox（离线队列）、SyncEngine（推拉）、NetworkMonitor（NWPathMonitor）
Theme/      AppTheme（51 令牌 × candy/cyber）、ThemeManager（三档）、Palette（16 色槽）
UI/         RootView、LoginView、UiStyle、CategoryIcon、PaymentIcon、BrandMark
            Ledger/ Dashboard/ Report/ Expense/ Settings/
Resources/  Assets.xcassets/pay_*.imageset（5 个品牌 SVG）
```

## 在 Xcode 里建 target（5 步）

1. Xcode → File → New → Project → **iOS App**
   - Product Name：`SuenMoney`
   - Interface：**SwiftUI**；Language：**Swift**
   - Bundle ID：`com.suenmoney.app`（与服务端更新通道、Keychain 一致）
   - Deployment Target：**26.0**
2. 把本目录下 `App/ Auth/ Contract/ Net/ Store/ Sync/ Theme/ UI/ Resources/`
   **整体拖进**新工程（勾选 *Create groups* + *Copy items if needed*）；
   删掉模板自带的 `ContentView.swift` 与 `Assets.xcassets`（用本目录的）
3. Build Settings → `INFOPLIST_FILE = SuenMoney/App/Info.plist`
   （删掉 Xcode 自动生成 Info.plist 的那套 `GENERATE_INFOPLIST_FILE`）
4. 确认 `Resources/Assets.xcassets` 在 **Copy Bundle Resources** 里
5. 编译 → 装模拟器

## 三条必须知道的约束

### 1. ATS 必须放行明文 HTTP

`Info.plist` 已加 `NSAllowsArbitraryLoads` + `NSAllowsLocalNetworking`。
不开的话 URLSession 直接拒绝请求，报错信息**不会**说是 ATS 拦的。

### 2. 令牌存 Keychain，不存 UserDefaults

`Net/ServerConfig.swift` 里的 `Keychain` 枚举。`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`：
首次解锁后可读、不随备份迁移（换机时令牌本就该失效重登）。

### 3. 逻辑层已可实跑验证

```bash
# 三端共用向量（33 条，与 Web/鸿蒙同一份）
swiftc -o /tmp/vrun Contract/Contract.swift Contract/VectorRunner.swift main.swift && /tmp/vrun
# → 向量 PASS：33/33

# 本地库建表 + 按还款日归属 + 分类聚合 + Outbox 队列
swiftc -I <sqlite3 modulemap> -lsqlite3 -o /tmp/dbt Store/*.swift Sync/Outbox.swift \
  Contract/Contract.swift Net/Models.swift main.swift && /tmp/dbt
```

## 与鸿蒙端的差异（实现层面，不是功能层面）

| 关注点 | 鸿蒙 | iOS |
|---|---|---|
| 网络 | `@kit.NetworkKit` | `URLSession` async/await |
| 本地库 | `relationalStore` | **SQLite3**（系统自带） |
| 令牌 | `preferences` | **Keychain** |
| 弹层 | `bindSheet` | `.sheet` + `.presentationDetents` |
| 图标 | `sys.symbol` | **SF Symbols** |
| 切角 | `clipShape(Path)` + vp2px | `CyberCutShape`（坐标即点，无换算） |
| 网格 | `Grid`（不给高度撑满父容器） | `LazyVGrid`（无此坑） |
| 返回 | `onBackPress()` | `AppState.goBack()` + 系统边缘手势 |
| 状态 | `@State` / `AppStorage` | `@State` / `@Observable` + `@Environment` |

## 未完成 / 已知

- **未过 Xcode 编译**：Linux 上只有 `swiftc -parse`（查语法不查类型）。拿到 Mac 后需按报错逐个修。
- 分类/支付方式的**编辑弹窗**是精简版（名称 + 类型 + 删除）；图标/颜色/排序等高级项
  在鸿蒙端有更完整的表单，iOS 侧待补。
- 「新建计划」入口暂提示「请在 Web 端操作」（鸿蒙端有完整表单，iOS 侧待补）。
- 字体：`Outfit` / `Plus Jakarta Sans` / `JetBrains Mono` 未随包附带，
  会回落到系统字体（`.custom` 找不到时自动 fallback，不崩）。要完全对齐观感需补 ttf 资源。
