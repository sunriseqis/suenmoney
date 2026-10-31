# SuenMoney

家庭共用的记账系统。**只记支出**，回答两个问题：

> **这个月 / 今年花了多少？花在什么上面？**

自托管、单端口、数据完全在自己手里。2.0 起各端都是**原生实现**，不再共用一套 WebView 页面。

---

## 架构

```
                    ┌─────────────────────────────────────┐
                    │  server/  Fastify 5 + node:sqlite   │
                    │  一个进程 · 一个端口 · 同时提供      │
                    │  页面（静态托管）与 /api            │
                    └──────────────┬──────────────────────┘
                                   │ HTTP · 同源
        ┌──────────────┬───────────┴───────────┬──────────────┐
        │              │                       │              │
   web/ (Vue 3)   ios/ (SwiftUI)      hw-native/ (ArkTS)   fn/
   Web 端/后台     iOS 原生客户端        鸿蒙 NEXT 原生      飞牛 fnOS 套件
```

| 目录 | 内容 | 规模 |
|---|---|---|
| `server/` | Fastify 5 + `node:sqlite`（Node ≥ 22.9） | 42 文件 / 10.5k 行 |
| `web/` | Vue 3 + Vite，记账界面兼管理后台 | 71 文件 / 13.8k 行 |
| `ios/` | SwiftUI（iOS 26+），原生客户端 | 33 文件 / 12.1k 行 |
| `hw-native/` | ArkTS / ArkUI（HarmonyOS NEXT），原生客户端 | 37 文件 / 13.3k 行 |
| `fn/` | 飞牛 fnOS 原生套件（`.fpk`，内置 Node 运行时，免 Docker） | — |
| `hw/` · `android/` | 历史实现（Capacitor / WebView 时代），**已冻结** | 归档 |

> **只有 5310 一个端口**：页面与接口同源同端口，没有「后端地址」要配。
> 原生客户端在登录页填 `http://<主机IP>:5310` 即可。

---

## 三种部署方式

### 一、飞牛 fnOS 套件（推荐给有飞牛 NAS 的）

去 [`sunriseqis/suenapp`](https://github.com/sunriseqis/suenapp/releases) 下载 `suenmoney-v*.fpk`，
在飞牛桌面 → **应用中心** → 右上角**手动安装**。

安装向导里设：**服务端口**（默认 5310）+ **初始管理员账号**（密码 ≥ 8 位）。装完即可用。

- 纯原生进程，内置 Node 运行时，不依赖 Docker
- 数据落在飞牛独立持久化目录，升级/重装不丢账本
- 从桌面图标或 `http://<NAS地址>:<端口>` 进入

### 二、Docker Compose

```bash
docker compose pull && docker compose up -d          # 首次 / 升级
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build   # 或本地构建

# 容器内创建首个管理员（不传 --password 会随机生成并打印）
docker compose exec suenmoney node scripts/node-run.mjs src/cli/user-add.ts --username admin --name 管理员 --admin
```

镜像：`ghcr.io/sunriseqis/suenmoney`（多架构 amd64/arm64）。

### 三、本机直接跑（不用 Docker）

一个 Node 进程就是全部。systemd 托管、开机自启的做法见
[部署指南 · 本机直接部署](docs/deploy.md)。

---

## 客户端

| 平台 | 形态 | 获取方式 |
|---|---|---|
| **Web** | 浏览器直接访问 `http://<主机IP>:5310` | 无需安装，也是管理后台 |
| **iOS** | SwiftUI 原生，`.ipa` 未签名 | Release 里的 `SuenMoney-*.ipa`，用 AltStore / SideStore / 爱思助手个人签后安装 |
| **鸿蒙 NEXT** | ArkTS 原生，`.hap` 未签名 | Release 里的 `SuenMoney-*.hap`，DevEco Studio 或自签工具装入真机 |

三端共用同一个发布页：**[`sunriseqis/suenapp`](https://github.com/sunriseqis/suenapp/releases)**
（tag 为 `suenmoney-vX.Y.Z`，附件含 `.fpk` / `.hap` / `.ipa`）。

> 安卓端在 2.0 未重构，**当前没有安卓计划**；`android/` 目录保留为历史实现。

---

## 备份与恢复

Web 端「数据」页 → **下载全量备份**（`suenmoney-backup-*.json`）→ 需要时用**恢复备份**上传。

恢复是**覆盖式**的：文件里的记录以文件为准，本地多出来的记录**不会**被删。
恢复前服务端会自动存一份当前全量快照（响应里的 `snapshotPath`），恢复错了能找回。

### ⚠️ 从旧实例迁移：备份不能直接导入

备份里每条计划 / 流水 / 期次都用 **ULID 引用成员**（`owner_id` / `confirmed_by`）。
换库、重装、换 NAS 之后成员 ULID 一定会变，而导入端会逐条校验这些 id 是否存在 ——
不存在就整包拒绝（备份**不含口令哈希**，导入不能替你建账号）。

用 `scripts/convert-backup.mjs` 把旧 id 换成目标实例里真实的 id：

```bash
# 1) 先看清备份里有谁
node scripts/convert-backup.mjs --input old.json --list

# 2) 拿目标实例的成员 id
curl -s http://<地址>:<端口>/api/users -H "Authorization: Bearer <token>"

# 3) 按「旧=新」映射转换（一个成员一条 --map）
node scripts/convert-backup.mjs --input old.json --output ready.json \
  --map 01M3TWW6...=01M5E9YA2... \
  --map 01M3V08H...=01M5EV489...

# 或：所有成员合并到一个账号（单人使用）
node scripts/convert-backup.mjs --input old.json --output ready.json --collapse <目标成员id>
```

脚本会补齐 2.0 新增的 `payment_methods.icon` 列、重排字段顺序，
并在写文件前校验「转换后没有任何悬空引用」。

---

## 开发

```bash
npm run install:all     # 装 server + web 依赖
npm run dev:server      # 服务端热重载
npm run dev:web         # 前端 Vite dev server（代理到 5310）

npm run check           # 本地门禁：设计令牌校验 + 双端 typecheck + 双端测试 + web 构建
npm test                # 只跑测试
npm run typecheck       # 只跑类型检查
```

### 出包

```bash
npm run fn:build        # 飞牛 fnOS 套件 → output/suenmoney-v<ver>.fpk（+ .sha256）
npm run build:hw        # 鸿蒙 HAP（未签名）
npm run build:ios       # iOS IPA（未签名，需 macOS + Xcode）
npm run icons           # 从矢量母版重新生成品牌图标
```

### CI

**只有三条出包流水线，全部手动派发**：`build-fnos` / `build-hw` / `build-ios`。
推代码不会触发任何构建。

三端产物统一发到 **[`sunriseqis/suenapp`](https://github.com/sunriseqis/suenapp/releases)**，
共用 tag `suenmoney-vX.Y.Z`；**本仓库不发行产物**。

细节（含 tag 前缀为什么是硬性要求）见 [docs/ci.md](docs/ci.md)。

---

## 设计约定

- **只记支出**，不做收入、不做预算、不做多币种。范围小是刻意的。
- **月归属按还款日**：信用卡账单跨月时，这笔钱算在**还款月**，不是消费月。
- **软删除**：分类与支付方式被流水引用时拒绝删除，只能停用；删除失败会给可执行建议。
- **单一真相源**：服务端是唯一数据源，客户端离线队列只是暂存，冲突以服务端为准。

视觉与交互的裁决记录见 [docs/decisions.md](docs/decisions.md)。

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/api.md](docs/api.md) | HTTP 接口 |
| [docs/api-native-contract.md](docs/api-native-contract.md) | 原生客户端与服务端的契约（字段口径、错误码） |
| [docs/deploy.md](docs/deploy.md) | 部署（Docker / 本机 systemd / 飞牛套件） |
| [docs/ci.md](docs/ci.md) | CI 与发布约定 |
| [docs/conventions.md](docs/conventions.md) | 目录、产物、命名纪律 |
| [docs/decisions.md](docs/decisions.md) | 需求裁决记录（U01–U18 等） |
| [docs/feature-inventory.md](docs/feature-inventory.md) | 功能清单 |
| [docs/design/](docs/design/) | 设计系统与品牌资产 |
| [docs/plan/](docs/plan/) | 阶段性计划与收尾待办 |

---

## 许可

私有项目，未授权请勿分发。
