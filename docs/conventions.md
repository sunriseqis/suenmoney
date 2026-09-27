# 目录与产物约定

本文件是**硬约束**。新增文件前先对照这里；与本文件冲突的结构一律视为错误。

---

## 一、顶层分层：四个交付物必须彼此独立

```
suenmoney/
├── server/      后端服务（Fastify + node:sqlite）
├── web/         前端（Vue 3 + Vite + Tailwind v4），Web 与移动端共用同一份代码
├── android/     安卓原生产物（由 web 的 Capacitor 驱动生成，本目录只存原生工程）
├── ios/         iOS 原生产物（同上）
├── scripts/     跨项目共用的开发工具（不放业务代码）
├── docs/        文档、计划、设计素材、决策记录
└── docker-compose.yml
```

**规则**

- `server/` 与 `web/` **不得互相 import**。两者只通过 HTTP 接口耦合，接口形状由
  `web/src/api/types.ts` 与服务端 `src/http/*.ts` 两侧各自声明（类型重复是有意的：
  它让接口变更必须显式同步两边，而不是被一次自动重构悄悄改掉）。
- `android/` 与 `ios/` **不放任何手写的业务代码**。它们的内容全部由
  `web/` 的 Capacitor 生成或配置；需要改原生行为时改配置或写原生插件，
  不要在原生工程里直接改业务逻辑（下次同步会被覆盖）。
- 共享的开发工具放根 `scripts/`，不要复制到各项目里。

## 二、各项目内部结构

**server/**

```
server/
├── src/
│   ├── config.ts         运行时配置（全部来自环境变量）
│   ├── index.ts          进程入口
│   ├── cli/              命令行工具（db-init、user-add），不是测试
│   ├── db/
│   │   ├── index.ts      连接与迁移执行器
│   │   ├── sync.ts       所有写入的唯一入口（负责记录变更日志）
│   │   ├── migrations/   *.sql，文件名数字前缀即版本号
│   │   └── repo/         数据访问（按实体分文件）
│   ├── domain/           业务规则（纯函数、无 IO、必须有单元测试）
│   ├── http/             路由
│   └── lib/              通用工具（无业务语义）
└── tests/                测试，镜像 src/ 的子目录结构
```

**web/**

```
web/
├── src/
│   ├── api/          HTTP 客户端、接口封装、类型
│   ├── components/   可复用组件
│   ├── router/       路由与守卫
│   ├── stores/       Pinia
│   ├── styles/       设计令牌与全局样式
│   ├── utils/        纯函数工具
│   └── views/        页面
└── tests/            测试，镜像 src/ 的子目录结构
```

## 三、测试：一律进 `tests/`

- 测试文件**只允许**出现在 `server/tests/` 与 `web/tests/`，禁止与源码同目录。
- 命名必须是 `*.test.ts`（或 `*.test.mjs`），这样 `--test` 的默认发现规则能覆盖到。
- 跑测试用各自的 `npm test`；不要写「跑之前先手动启动服务」的测试 ——
  服务端集成测试用 Fastify 的 `app.inject()`，不需要端口。
- **临时调试脚本用完立即删除**，不要留在仓库里，也不要放 `tests/`（它不是测试）。

## 四、产物：产出物与源码物理隔离

| 层 | 产物目录 | 是否入库 | 说明 |
|---|---|---|---|
| server | 无 | — | 直接用 `node` 运行 `.ts`，**没有构建步骤**，也就没有构建产物 |
| server | `server/data/` | 否 | SQLite 库与 `backups/`。运行时数据，绝不入库 |
| web | `web/dist/` | 否 | Vite 生产构建产物。只由 Docker 构建流程消费 |
| android | `android/app/build/`、`android/build/` | 否 | Gradle 产物 |
| android | `android/**/*.apk`、`*.aab` | 否 | |
| ios | `ios/App/build/`、`ios/**/Pods/` | 否 | |
| ios | `ios/**/*.ipa`、`*.xcarchive` | 否 | |

**规则**

- 禁止把任何产物写进 `src/`。`src/` 里出现 `dist`、`build`、`*.log` 都算违规。
- 依赖目录（`node_modules/`、`Pods/`）不入库。
- 各项目的产物目录写进根 `.gitignore`，新增产物类型时同步补规则。

## 五、文档与记忆：一律进 `docs/`，禁止旁路目录

```
docs/
├── conventions.md      本文件：目录与产物约定
├── decisions.md        设计决定与理由（改设计前先读）
├── plan.md             路线图与当前进度
├── api.md              接口清单
└── design/             设计素材（设计系统原文、令牌推导、界面评审记录）
```

- 「记忆」「计划」「素材」**一律写进 `docs/`**。
- **禁止创建 `.codebuddy/`、`.workbuddy/` 或任何同类目录**用于存放记忆、
  计划、缓存、说明文件。需要长期留存的信息写进 `docs/`，需要临时存的信息
  写到系统临时目录并及时删除。
- 不进 `docs/` 的还有：代码注释（放代码旁边）、接口清单（放 `docs/api.md` 或
  README，不另开目录）。

## 六、命名

- 文件名一律 `kebab-case.ts`；Vue 组件一律 `PascalCase.vue`；视图一律 `*View.vue`。
- 数据库列名 `snake_case`，接口字段 `camelCase`（服务端 repo 层负责转换）。
- 同步给客户端的快照字段刻意保留 `snake_case`，与客户端本地表列名一致。
