# SuenMoney 部署与运维指南

SuenMoney 是专为家庭设计的精益记账系统。本文档介绍如何使用 Docker Compose 进行自托管生产部署、数据持久化配置与物理快照灾备。

---

## 一、架构设计：一个容器、一个端口

```
[ 浏览器 / iOS / 鸿蒙原生客户端 ]
                │
                ▼  http://<宿主机IP>:5310
┌───────────────────────────────────────────────┐
│          suenmoney（单容器 = 单进程）           │
│  Fastify + @fastify/static                    │
│  - GET /            → web/dist/index.html     │
│  - GET /assets/*    → 带内容哈希的静态资源      │
│  - GET /ledger 等   → SPA 回退（同一份 index）  │
│  - /api/*           → 接口（未命中回 JSON 404） │
│  - node:sqlite 单文件库 + 每日 VACUUM INTO 快照 │
└───────────────────────┬───────────────────────┘
                        │
                        ▼ (持久化卷 suenmoney-data → /app/data)
┌───────────────────────────────────────────────┐
│  suenmoney.sqlite / -wal / -shm               │
│  backups/snapshots/suenmoney-snapshot-*.sqlite│
└───────────────────────────────────────────────┘
```

**只有 5310 一个端口**，它同时是页面地址与接口地址 —— 没有第二个端口要记，
也没有 `BACKEND_URL` 之类的「后端地址」要配。浏览器里前端永远走同源相对路径。

> 历史版本是「nginx（web）+ Fastify（server）」两个容器、两个镜像。现已合并：
> 服务端自己托管 `web/dist`，nginx 那层不再需要（要上 HTTPS 见第五节，反代仍可选）。

---

## 二、快速开始（Docker Compose）

### 1. 前置条件

- 已安装 **Docker** (≥ 24.0) 及 **Docker Compose** (≥ v2.20)。

### 2. 获取配置文件

部署机**只需要 `docker-compose.yml` 一个文件**（镜像已托管在 GHCR）：

```bash
mkdir -p ~/suenmoney && cd ~/suenmoney
curl -fsSLO https://raw.githubusercontent.com/sunriseqis/suenmoney/main/docker-compose.yml
```

### 3. 启动服务

```bash
# 拉取镜像并启动
docker compose pull && docker compose up -d

# 或：从源码本地构建（需完整仓库，叠加 dev 覆写文件）
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d --build
```

### 4. 访问与初始化

打开 `http://localhost:5310`（局域网内其它设备用 `http://<宿主机IP>:5310`）。

- 库为空时，第一个通过「初始化管理员」表单创建的账号自动成为管理员；
- 也可以直接在容器里建号（口令不传则随机生成并打印）：

```bash
docker compose exec suenmoney node scripts/node-run.mjs src/cli/user-add.ts --username admin --name 管理员 --admin
```

---

## 三、从「双容器」升级到「单容器」

老部署（`suenmoney-server` + `suenmoney-web`）升级时**数据卷名不变**，因此账本不会丢：

```bash
# 1. 用新版 docker-compose.yml 覆盖旧的（service 名从两个变成一个：suenmoney）
# 2. 停掉旧栈并启动新栈
docker compose down          # 注意：不要加 -v，那会删数据卷
docker compose pull
docker compose up -d

# 3. 确认只有一个容器在跑
docker ps --filter name=suenmoney

# 4. 确认数据还在（登录后核对流水笔数与合计；升级前建议先在「设置 → 数据」导出一份对账 CSV）
```

**回滚**：GHCR 上的 `ghcr.io/sunriseqis/suenmoney-server` 与 `...-web` 历史镜像**保留不再更新**，
把 compose 换回旧版（`git checkout <升级前的 tag> -- docker-compose.yml`）即可退回双容器形态，
数据卷通用。

> 新容器与旧容器**不要同时**映射 5310 —— 会端口冲突，这本身也是一道保护。

---

## 四、环境变量速查

| 环境变量 | 默认值 | 作用说明 |
|---|---|---|
| `SUENMONEY_PORT` | `3310`（compose 里显式设 `5310`） | 服务端监听端口。**它是对外唯一端口**：页面与 `/api` 都在这里 |
| `SUENMONEY_HOST` | `0.0.0.0` | 服务端监听地址 |
| `SUENMONEY_WEB_ROOT` | `../web/dist`（镜像里 `/app/web/dist`） | 前端产物目录。目录里没有 `index.html` 时自动退化为**纯 API 模式** |
| `SUENMONEY_DB_PATH` | `./data/suenmoney.sqlite`（镜像里 `/app/data/suenmoney.sqlite`） | SQLite 单文件数据库路径 |
| `SUENMONEY_BACKUP_DIR` | `./data/backups`（镜像里 `/app/data/backups`） | 快照与恢复前归档目录 |
| `SUENMONEY_BACKUP_KEEP` | `14` | 快照最大保留份数（自动淘汰最旧） |
| `SUENMONEY_SESSION_DAYS` | `180` | 登录会话有效期（天） |
| `SUENMONEY_ALLOW_REGISTRATION` | `false` | 是否开放公开注册（默认仅管理员建号） |
| `SUENMONEY_TRUST_PROXY` | `false`（镜像是 `false`） | 是否信任 `X-Forwarded-For`。**前面没有反代时必须保持 false**：开了等于允许伪造来源 IP，登录限流（按 IP 计数）会被绕过 |
| `SUENMONEY_CORS_ORIGINS` | 空（允许全部来源） | 跨源白名单，逗号分隔；`*` 表示放开。浏览器同源部署用不到，主要给旧 WebView 壳 |
| `SUENMONEY_VERSION` | 从 `VERSION` 文件读取 | `/api/health` 里上报的版本号（原生端探活、套件升级自检用） |
| `TZ` | `Asia/Shanghai`（镜像内置） | 影响备份调度时刻与日志时间戳；业务日期不受影响（客户端传入 `YYYY-MM-DD`） |

> **不存在 `SUENMONEY_ADMIN_*` 这类环境变量**（旧版本文档写过，但代码里从未实现）。
> 首个管理员请用「初始化管理员」表单或上面的 `user-add` 命令创建。

---

## 五、可选：在前面加一层反代（TLS）

需要 HTTPS（公网访问、或想用域名）时，**反代只做 TLS 终止**，其余一仍旧贯：

```nginx
server {
    listen 443 ssl;
    server_name money.example.com;

    ssl_certificate     /etc/ssl/fullchain.pem;
    ssl_certificate_key /etc/ssl/privkey.pem;

    # 导入类接口可能提交较大 JSON；如需放宽，改服务端 bodyLimit（见「常见问题」）
    client_max_body_size 32m;

    location / {
        proxy_pass http://127.0.0.1:5310;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

此时 compose 里改成：

```yaml
    ports:
      - "127.0.0.1:5310:5310"        # 只让本机反代访问
    environment:
      - SUENMONEY_TRUST_PROXY=true   # 有反代才开，否则限流会把所有人算成同一个 IP
```

---

## 六、双层备份与容灾恢复

### 1. 运维侧物理快照（SQLite `VACUUM INTO`）

- **机制**：服务端内置定时器每日执行 SQLite 原生 `VACUUM INTO`，把当前库完整复制并归并 WAL，产出物理一致性副本。
- **存储**：`backups/snapshots/suenmoney-snapshot-YYYYMMDD-HHmmss.sqlite`。
- **保留策略**：维持最近 `SUENMONEY_BACKUP_KEEP`（默认 14 份）。
- **管理入口**：管理员登录后「设置 → 数据」可查看快照列表、大小、一键下载与手动创建。

### 2. 物理快照灾备还原（冷恢复）

```bash
# 1. 停止服务
docker compose stop

# 2. 用快照覆盖主库（卷名不变：suenmoney-data）
docker run --rm -v suenmoney-data:/data alpine sh -c "
  cp /data/backups/snapshots/suenmoney-snapshot-20260929-120000.sqlite /data/suenmoney.sqlite &&
  rm -f /data/suenmoney.sqlite-wal /data/suenmoney.sqlite-shm
"

# 3. 重新启动
docker compose start
```

### 3. 用户侧逻辑备份（JSON 数据包 + 对账 CSV）

「设置 → 数据」里管理员可导出/导入全量 JSON 数据包（明文可读、版本兼容、支持幂等补缺合并），
另有对账 CSV 与账单导入。**导出与备份是两个功能，不要拿按月导出当备份用**。

---

## 七、日常维护常用命令

```bash
# 查看实时日志
docker compose logs -f

# 整个数据卷打包备份
docker run --rm -v suenmoney-data:/data -v $(pwd):/backup alpine \
  tar czvf /backup/suenmoney-data-backup-$(date +%Y%m%d).tar.gz /data

# 从压缩包恢复数据卷
docker run --rm -v suenmoney-data:/data -v $(pwd):/backup alpine \
  sh -c "cd / && tar xzvf /backup/suenmoney-data-backup-20260929.tar.gz"

# 升级
docker compose pull && docker compose up -d
```

---

## 八、常见问题

| 现象 | 原因与处理 |
|---|---|
| 打开 5310 是登录页，但接口全 404 且返回 HTML | 前端产物没打进镜像 / `SUENMONEY_WEB_ROOT` 指错。`docker compose logs` 启动第二行会打印实际生效的目录（`静态资源：...` 或 `未启用（纯 API 模式）`） |
| 日志显示「静态资源：未启用」 | 镜像里 `web/dist` 缺失（自建镜像时把 `.dockerignore` 里的 `web/dist` 规则改坏了，或构建阶段失败）。纯 API 模式下 `/` 一律 404 |
| 手机上连不上，宿主机本机却正常 | 检查是否把 `SUENMONEY_HOST` 改成了 `127.0.0.1`；容器内必须是 `0.0.0.0` |
| 登录频繁被限流、所有人都一起被限 | 前面有反代但 `SUENMONEY_TRUST_PROXY` 还是 `false`（所有人同 IP）；或反过来没有反代却开成了 `true`（IP 可伪造）。按第五节对齐 |
| 导入大文件报 413 | 服务端请求体上限是 **512KB**（`server/src/http/server.ts` 的 `bodyLimit`）。确实需要更大就改这个常量后重建镜像，不要在反代上放宽 —— 反代放宽不改服务端行为 |
| 页面改了但用户还是旧版 | `index.html` 是 `no-cache`、`/assets/*` 是 `immutable` + 内容哈希，正常情况刷新即更新；如果换了产物却没换文件名，说明构建没跑 |
