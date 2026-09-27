# SuenMoney

家庭共用的记账系统。**只记支出**，目标是回答两个问题：

> **这个月 / 今年花了多少？花在什么上面？**

服务端自托管（Docker Compose）。Web 端是记账界面兼管理后台；
Android / iOS 复用同一份前端代码。

---

## 快速开始

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
| [`docs/decisions.md`](docs/decisions.md) | **设计决定与理由** —— 改设计前先读这份 |
| [`docs/plan.md`](docs/plan.md) | 路线图、当前进度、待决事项 |
| [`docs/api.md`](docs/api.md) | 接口清单 |
| [`docs/conventions.md`](docs/conventions.md) | 目录与产物约定 |
| [`docs/design/flat-design.md`](docs/design/flat-design.md) | 设计系统、令牌推导、与原始设计系统的偏离 |

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
