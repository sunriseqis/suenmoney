# SuenMoney

家庭共用的记账系统。**只记支出**，目标是回答两个问题：

> **这个月 / 今年花了多少？花在什么上面？**

服务端自托管（Docker Compose）。Web 端是记账界面兼管理后台；
Android / iOS 复用同一份前端代码。

---

## 快速开始

### 方式一：Docker Compose（推荐，自托管生产环境）

```bash
# 启动并在后台运行
docker compose up -d --build

# （可选）若未在环境变量预设管理员，可在容器内手动添加首个管理员：
docker compose exec server npm run user:add -- --username admin --name 管理员 --admin
```
打开 `http://127.0.0.1:5310` 即可开始使用。详细运维与备份请阅读 [部署与运维指南](docs/deploy.md)。

---

### 方式二：本地开发调试

需要 **Node ≥ 22.9**。

```bash
npm run install:all          # 安装 server 与 web 的依赖

npm --prefix server run db:init                      # 建库并写入默认分类
npm --prefix server run user:add -- --username 你的登录名 --name 显示名
                                                     # 不传 --password 会随机生成并打印

npm run dev:server           # 后端，默认 127.0.0.1:3310
npm run dev:web              # 前端，默认 127.0.0.1:5310
```

打开 `http://127.0.0.1:5310` 即可。第一个账号会自动成为管理员。

> **关于实验性旗标**：`node:sqlite` 与 TypeScript 类型剥离在不同 Node 小版本上
> 的状态不一致（22.5 起需要旗标，新版本已默认开启）。`scripts/node-run.mjs`
> **不猜版本号，直接探测能力**：不用旗标行不行，不行再试加上，两条都不通就
> 给出可操作的报错。所以 22.x / 23.x / 24.x 与 CI 上都能直接跑，
> 将来 Node 取消旗标也无需改脚本。

## 测试

```bash
npm test                          # 两侧全跑
npm --prefix server test          # 单元 + 端到端集成（服务端）
npm --prefix web test             # 纯逻辑单元测试（前端）
npm --prefix server run test:schema   # 只跑 schema 约束回归
```

服务端的集成测试用 Fastify 的 `app.inject()`，不占端口、不依赖网络、
不碰真实的 `server/data/suenmoney.sqlite`。

## 用演示数据看界面

```bash
export SUENMONEY_DB_PATH=/tmp/suenmoney-demo.sqlite
npm --prefix server run db:init
npm --prefix server run user:add -- --username demo --name 我 --password demo1234 --admin
npm --prefix server run user:add -- --username lin  --name 爱人 --password demo1234
npm --prefix server run seed:demo

# 另起一套栈，完全不碰开发库
SUENMONEY_DB_PATH=/tmp/suenmoney-demo.sqlite SUENMONEY_PORT=3400 npm --prefix server run start &
SUENMONEY_API=http://127.0.0.1:3400 SUENMONEY_WEB_PORT=5410 npm --prefix web run dev
```

为什么要它：空库或者只有一两笔数据时，流水列表、报表饼图、计划进度条全是空壳，
**判断不出排版、字号、对齐是否成立**。设计评审必须在真实数据密度下做。

种子会写入 49 笔支出（含一笔负数退款）、3 个计划（房贷 / 分期 / 已逾期）、36 期待办。

---

## 结构

```
suenmoney/
├── server/      后端：Fastify + node:sqlite + 手写 SQL（无构建步骤，直接跑 .ts）
├── web/         前端：Vue 3 + Vite + Tailwind v4 —— Web 与移动端共用
├── android/     安卓原生工程（预留，由 web 的 Capacitor 驱动）
├── ios/         iOS 原生工程（预留，同上）
├── scripts/     跨项目共用的开发工具
└── docs/        文档、计划、设计素材
```

**目录与产物是硬约束**，见 [`docs/conventions.md`](docs/conventions.md)。
摘要：测试一律进 `tests/`；产物一律不进 `src/`；文档与记忆一律进 `docs/`；
不创建任何 `.codebuddy` / `.workbuddy` 之类的旁路目录。

---

## 文档

| 文件 | 内容 |
|---|---|
| [`docs/deploy.md`](docs/deploy.md) | **部署与运维指南** —— Docker Compose 一键部署、环境变量与物理快照容灾 |
| [`docs/decisions.md`](docs/decisions.md) | **设计决定与理由** —— 改设计前先读这份 |
| [`docs/plan.md`](docs/plan.md) | 路线图、当前进度、待决事项 |
| [`docs/api.md`](docs/api.md) | 接口清单 |
| [`docs/conventions.md`](docs/conventions.md) | 目录与产物约定 |
| [`docs/design/flat-design.md`](docs/design/flat-design.md) | 设计系统、令牌推导、与原始设计系统的偏离 |
| [`docs/design/mockup.html`](docs/design/mockup.html) | **界面设计稿**（可直接在浏览器打开，5 页 + 22 条编号说明） |
| [`docs/design/ui-review.md`](docs/design/ui-review.md) | 界面评审归档（已完成，保留原始记录） |
| [`docs/design/ui-rework-2.md`](docs/design/ui-rework-2.md) | **第三轮返工方案**（9 条问题的代码核查、决策、落地顺序） |
| [`docs/design/ui-rework-3.md`](docs/design/ui-rework-3.md) | **第四轮：信息架构重设**（读 BeeCount 源码 + **实测其部署实例**后重定每页内容；**概况看「多少」、报表=统计看「结构」**；**报表按档位组织块**；**移动端只保留流水一页 + 顶卡**；**卡片不为对齐而撑高**；**提醒展开后要能动手**（确认 / 入账 / 忽略，桌面与移动端都有）；**流水三档三形态**（月＝列表 / 年＝12 个月格日历 / 全部＝一格一年日历，点一下选中、再点才进，**格子底色＝花销深浅四档**）；**没有组头**；**流水行一行一项**（窄屏**账期让位**，**唯一可截断的是计划名**）；**提醒的颜色只落在展开箭头上、不染卡片**；**全局禁用 emoji**；**移动端提醒左右滑**（左滑确认 / 入账、右滑忽略，桌面仍是按钮；动作按「这一期会不会自动入账」分流，会自动入账的只给「确认」＝记一笔 `ack_at`、不改业务状态）；**日历只有深浅、没有图例**（月均已在汇总行，同一页不重复同一个数）；**所有页面禁用「说明式文字」**；计划提醒归属、功能清单） |
| [`docs/design/ui-rework-3-preview.html`](docs/design/ui-rework-3-preview.html) | **第四轮方案预览（第十版）**（可交互原型：四页新分工 + 三档时间维度 + 热力图 + 累计条 + 报表分类下钻与**按档位换块** + **移动端单页化 / 顶卡可折叠 / 控制行 / 下拉记账** + **提醒压成一行、动作按钮在行尾** + **紧急度的颜色只落在展开箭头上** + **二级页关闭入标题行** + **流水三档三形态（月＝列表 / 年 / 全部＝日历，点一下选中、再点或按「进入」才下钻，底色＝花销深浅四档）** + **流水行一行一项**（并已修掉两个让它「多行」的结构 bug） + **无组头 / 无 emoji / 无图例** + **PC 版式体检**，桌面/手机两种宽度。<br>**这份预览的落地顺序前 3 步已全部落进代码** —— ① `.card-grid` 版式基线（卡片一律按内容高、**不为对齐而撑高**；危险区改通栏放最底）；② 设置页「数据」tab（导出数据包 / 导出对账表 / 导入 / 备份与恢复 / 危险区两个动作，**仅管理员**；导出范围三档，**一律走还款日前缀匹配、与报表同源**）；③ 计划提醒的动作层 —— 含 `003` 迁移（`ack_at`）、`ack` 端点、`ReminderRow` / `ReminderList`（一条一行 + 染色展开箭头 + 折叠 + 窄屏左右滑 + 8 秒撤销）） |
| [`docs/design/oss-patterns.md`](docs/design/oss-patterns.md) | 同类开源项目调研（Maybe / Actual / Wallos / Cashew / ExpenseOwl） |

---

## 几件最容易被误解的事

- **报表的月份归属以「还款日」为准**，不是消费日。一笔 1 月 11 日的消费，
  若信用卡账单日 10、还款日 28，就归属 **2 月**。这是现金流出视角。
- **业务日期是 `YYYY-MM-DD` 字符串，不是时间戳**，所以月/年聚合零时区换算。
  「今天」由客户端按本地时区判定后传入，服务端不推算。
- **金额是整数「分」**，浮点会带来「总账差一分钱」的 bug。
- **分类与支付方式只能停用不能删除**，否则历史报表会出现「未分类」黑洞，
  并随同步扩散到所有设备。
- **只能改自己创建的记录**。这不只是权限 —— 它同时是离线冲突的消解机制。
