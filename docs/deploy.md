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

镜像地址 `ghcr.io/sunriseqis/suenmoney`，**仅 `linux/amd64`**。
> ARM 主机（Apple Silicon、arm64 NAS）跑不了这个镜像，请改用飞牛套件 / 源码部署。
可用 tag：

| tag | 说明 |
|---|---|
| `latest` | 最新发布版，`docker-compose.yml` 默认引用它 |
| `X.Y.Z` | 与发行版本一一对应，**回滚时钉这个** |
| `X.Y` | 跟随小版本 |
| `sha-xxxxxxx` | 精确到某次提交 |

固定版本部署把 compose 里的 `image:` 改成 `ghcr.io/sunriseqis/suenmoney:2.1.1` 即可 ——
用 `latest` 时 `docker compose pull` 会静默升级到新版本，排障时很难意识到「代码变了」。

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

## 三·补、本机直接部署（不用 Docker）

合并之后服务端已经**自带静态托管**，所以「跑起来」这件事不再依赖任何容器工具 ——
一个 Node 进程 + 一个前端产物目录就是全部。想要开机自启、崩溃重启，用 systemd 托管即可。

```bash
# 1. 准备产物（前端只构建一次，改了前端要重新跑）
npm ci --prefix server && npm ci --prefix web
npm --prefix web run build          # → web/dist

# 2. 数据放仓库外，仓库保持干净（等价于容器里的 /app/data）
sudo install -d -m 755 /var/lib/suenmoney /var/lib/suenmoney/backups

# 3. 装 systemd 单元（仓库里带模板：scripts/suenmoney.service）
sudo cp scripts/suenmoney.service /etc/systemd/system/suenmoney.service
sudoedit /etc/systemd/system/suenmoney.service   # 改三处：WorkingDirectory / SUENMONEY_WEB_ROOT / ExecStart 的 node 绝对路径
sudo systemctl daemon-reload
sudo systemctl enable --now suenmoney

# 4. 看状态与日志
systemctl status suenmoney
journalctl -u suenmoney -f
```

访问 `http://<宿主机IP>:5310`。

**三个容易踩的点**

| 坑 | 说明 |
|---|---|
| `ExecStart` 里必须写 node 的**绝对路径** | systemd 不读你的 shell PATH；nvm / asdf / volta 装的 node 在 `which node` 能看到、在单元里看不到（报 `status=203/EXEC`）。用 `which node` 的输出替换 |
| 数据目录必须在仓库外 | 用 `/var/lib/suenmoney`。放仓库里的话 `git clean` 或某次误操作就可能连账本一起删 |
| 前面套反代才开 `TRUST_PROXY` | 反代场景改成 `true`；直连保持 `false`，否则 XFF 可伪造、限流被绕过 |

**验证它真的在跑**（这几条也是 CI 之外的最后一关）：

```bash
curl -s http://127.0.0.1:5310/api/health        # {"ok":true,...,"version":"..."}
curl -sI http://127.0.0.1:5310/ | head -3       # 200 text/html + cache-control: no-cache
curl -s  http://127.0.0.1:5310/api/nope         # {"error":"接口不存在"}（JSON，不是 HTML）
systemctl stop suenmoney && ls -l /var/lib/suenmoney/   # -wal 应被归并为 0 字节（优雅停机生效）
```

> 这条路与 Docker 部署**完全等价**（同一份代码、同一套环境变量），
> 也是飞牛 fnOS 套件（`docs/plan/2026-10-21-飞牛fnOS应用套件工程方案.md`）的运行形态 ——
> 套件只是把 Node 运行时和数据目录换成了包内的 `bin/node` 与 `TRIM_PKGVAR`。

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
| `SUENMONEY_CORS_ORIGINS` | 空（**仅同源/无 Origin 放行**） | 跨源白名单，逗号分隔；`*` 表示放开所有来源。空值**不是**"允许全部"，而是"仅同源"。浏览器同源部署用不到，主要给旧 WebView 壳 |
| `SUENMONEY_VERSION` | 从 `VERSION` 文件读取 | `/api/health` 里上报的版本号（原生端探活、套件升级自检用） |
| `TZ` | `Asia/Shanghai`（镜像内置） | 影响备份调度时刻与日志时间戳；业务日期不受影响（客户端传入 `YYYY-MM-DD`） |

> **不存在 `SUENMONEY_ADMIN_*` 这类环境变量**（旧版本文档写过，但代码里从未实现）。

### 更新与运维变量（可选）

| 环境变量 | 默认值 | 作用说明 |
|---|---|---|
| `SUENMONEY_UPDATE_SOURCE` | `github` | 更新通道：`github` / `off`。**设 `off` 关闭自动更新检查** |
| `SUENMONEY_UPDATE_GITHUB_REPO` | `sunriseqis/suenapp` | 更新检查的目标仓库 |
| `SUENMONEY_UPDATE_GITHUB_TOKEN` | 空 | 私有仓库更新检查需要 token |
| `SUENMONEY_UPDATE_SECRET` | 空 | 更新包下载令牌的 HMAC 密钥。**多副本部署必须设置且保持一致**，否则令牌验证失败 |
| `SUENMONEY_LOG_LEVEL` | `info` | 日志级别：`debug` / `info` / `warn` / `error` |
| `SUENMONEY_DEPLOY_ENV` | 空 | 部署形态标识（fnOS / Docker / 本地），影响更新提示文案 |
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

## 六、备份与容灾恢复

> ⚠ **`VACUUM INTO` 物理快照功能已在代码中移除**（2026-10-31 裁决）。
> 本节描述的是**当前真实可用**的三种备份方式，不是历史版本的文档。

### 1. WebDAV 远程加密备份（推荐）

服务端每日自动把整库加密（AES-256-GCM）后推送到你的 WebDAV 存储（坚果云/Nextcloud/NAS）。

- **配置**：Web 后台「设置 → 数据 → WebDAV」填地址/账号/密码，**必须设置备份口令**（≥6 位）
- **产物**：`suenmoney-backup-YYYY-MM-DD.mn`（口令加密的 JSON）
- **保留**：远端只保留最近 3 份（轮转自动清理）
- **恢复**：用备份口令解密 `.mn` 后，「设置 → 数据」上传 JSON 数据包恢复

### 2. 手动导出 JSON 数据包

「设置 → 数据」→「导出数据库备份」→ 得到 `suenmoney-backup-*.json`。

- **格式**：明文可读 JSON，版本兼容，支持幂等补缺合并
- **恢复**：「设置 → 数据」→「恢复备份」上传该 JSON（覆盖式：文件里有的以文件为准，本地多的不删）
- **自动存档**：恢复前服务端自动存一份当前全量快照到 `data/backups/pre-restore/*.json`，恢复错了能找回

### 3. 对账 CSV（流水导入/导出）

「设置 → 数据」→「导出流水（CSV）」→ 用 Excel/Numbers 对账。
**导出与备份是两个功能，不要拿按月导出当备份用**（导出包可能只含某年/某月，用它恢复会静默丢掉其他期间）。

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

## 八、飞牛私有云（fnOS）套件

不想用 Docker 的 NAS 用户，可以直接在飞牛应用中心装 `.fpk` 套件：**包里自带 Node 运行时**，
宿主机不需要装 Node、不需要包管理器、不跑容器。运行形态与「方式三：本机直接部署」同构。

### 1. 构建

```bash
npm run fn:build          # → output/suenmoney-v<version>.fpk（+ .sha256）
```

七步流水线：版本注入 → 图标（矢量母版出 64/256）→ 自带 Node 运行时（**sha256 校验**）→
组装 payload（前端产物 + 服务端源码 + `npm ci --omit=dev`）→ 权限归一 + **零软链校验** →
取 fnpack → 出包。

三条门禁都是有事故对应的，不要绕：

| 门禁 | 不做的后果 |
|---|---|
| 包内**零软链** | `node_modules/.bin` 的相对软链被打包器改写成自引用死链，飞牛赋权阶段 `stat` 失败，安装恒定报「设置目录权限失败」 |
| 包内**无 devDeps** | 体积失控、不可复现（出包前会硬检查 `typescript` / `@types` / `vite`） |
| 权限 **755/644** | 构建机 umask 077 会让包里出现 700，装到 NAS 上读不到 |

### 2. 安装与目录

应用中心上传 `output/suenmoney-v*.fpk` → 桌面出现 SuenMoney → 点开就是 `http://<NAS IP>:5310`。
**只有一个端口 5310**（页面 + `/api` 同源同端口，同 Docker 形态）。

| 变量 | 落点 | 内容 |
|---|---|---|
| `TRIM_APPDEST` | `/var/apps/suenmoney/target` | `bin/node`、`server/`、`web/dist/` —— **升级时整体替换，禁止往里放业务数据** |
| `TRIM_PKGVAR` | `…/@appdata/suenmoney` | `data/suenmoney.sqlite`、`info.log`、`app.pid`、`stop.flag` |
| `TRIM_PKGETC` | `…/@appconf/suenmoney` | `.env`（配置）、`env.example`（模板） |
| `TRIM_DATA_SHARE_PATHS` | `…/suenmoney/backup` | `SUENMONEY_BACKUP_DIR`：物理快照（`VACUUM INTO`）落这里，文件管理器里可见 |

### 3. 生命周期

| 动作 | 行为 |
|---|---|
| 启动 | 守护进程 + 服务进程；服务异常退出 5 秒后自动重启 |
| 应用中心「停止」 | 调 `cmd/main stop`：先立 `stop.flag` → `TERM` → 15 秒后 `KILL` → **校验端口释放**；端口没释放就保留 flag 防止被守护拉起 |
| 升级 | `upgrade_init` 先停并等端口释放 → 装新包 → `upgrade_callback` 起服务并探 `/api/health`，把返回体（含 `version`）写进 `info.log` |
| 卸载 | **只停进程，不删数据**。重装/升级可续用；要清空请自己删目录 |

> **「应用中心显示运行中」不算活着**：`checkport` 只探 `127.0.0.1`，进程崩了只要端口有人占就还是绿的。
> 判断是否真的在跑，看 `main status` 的退出码（`0` 运行 / `3` 未运行），或直接 `curl http://127.0.0.1:5310/api/health`。

### 4. 命令行运维（有一个必须踩的坑）

在包里跑 CLI 时，**必须显式指定数据库路径，并优先用包内 node**：

```bash
cd /var/apps/suenmoney/target
sudo -u suenmoney   SUENMONEY_DB_PATH=/var/apps/suenmoney/var/data/suenmoney.sqlite \
  ./bin/node scripts/node-run.mjs src/cli/user-add.ts --username admin --name 管理员 --admin
```

不写 `SUENMONEY_DB_PATH` 的后果：默认是相对路径 `./data/…`，库会建在 `target/` 里 ——
**下次升级整体替换 `target/`，账本就没了**。这是这类套件最典型的数据丢失路径。

### 5. 配置与日志

```bash
# 配置：写到 etc/.env，改完重启生效（bash 无法热重载 node）
sudoedit /var/apps/suenmoney/etc/.env      # 例如 SUENMONEY_BACKUP_KEEP=30
/var/apps/suenmoney/target/cmd/main restart

# 日志（>8MB 自动轮转成 info.log.1）
tail -f /var/apps/suenmoney/var/info.log
```

首次启动会在 `etc/` 写一份 `env.example` 模板，**不会自动生成 `.env`** ——
避免「改了模板以为生效」。

---

## 九、常见问题

| 现象 | 原因与处理 |
|---|---|
| 打开 5310 是登录页，但接口全 404 且返回 HTML | 前端产物没打进镜像 / `SUENMONEY_WEB_ROOT` 指错。`docker compose logs` 启动第二行会打印实际生效的目录（`静态资源：...` 或 `未启用（纯 API 模式）`） |
| 日志显示「静态资源：未启用」 | 镜像里 `web/dist` 缺失（自建镜像时把 `.dockerignore` 里的 `web/dist` 规则改坏了，或构建阶段失败）。纯 API 模式下 `/` 一律 404 |
| 手机上连不上，宿主机本机却正常 | 检查是否把 `SUENMONEY_HOST` 改成了 `127.0.0.1`；容器内必须是 `0.0.0.0` |
| 登录频繁被限流、所有人都一起被限 | 前面有反代但 `SUENMONEY_TRUST_PROXY` 还是 `false`（所有人同 IP）；或反过来没有反代却开成了 `true`（IP 可伪造）。按第五节对齐 |
| 导入大文件报 413 | 服务端请求体上限是 **512KB**（`server/src/http/server.ts` 的 `bodyLimit`）。确实需要更大就改这个常量后重建镜像，不要在反代上放宽 —— 反代放宽不改服务端行为 |
| 页面改了但用户还是旧版 | `index.html` 是 `no-cache`、`/assets/*` 是 `immutable` + 内容哈希，正常情况刷新即更新；如果换了产物却没换文件名，说明构建没跑 |
| `docker compose pull` 报 `unauthorized` | GHCR 的包可见性独立于仓库，`sunriseqis/suenmoney` 若不是 Public 就拉不到。用 `curl -s "https://ghcr.io/token?scope=repository:sunriseqis/suenmoney:pull&service=ghcr.io"` 自测（200 公开 / 403 私有），或去 Packages → 该包 → Package settings 改可见性 |
| `docker compose pull` 报 `manifest unknown` | 该 tag 还没构建过。可用 tag 见第二节；镜像由 `build-image` 流水线在推 `suenmoney-v*` tag 时产出（见 docs/ci.md） |
| **登录/记账报 500，但页面能打开** | **容器以 uid 1000(`node`) 运行，数据目录不可写**。若用 bind mount（`volumes: - ./data:/app/data`），宿主机目录属主是 root 时 `node` 进程只读 → 建库/写 WAL 失败 → 登录等写操作 500，但读正常。修：`chown -R 1000:1000 <宿主目录>` 或改用命名卷 `suenmoney-data`。`docker compose logs` 看有无 `EACCES`/`unable to open database` |
| 备份恢复后账号/密码变了 | 恢复是**整库覆盖**（含账号与口令哈希），备份里有的以备份为准。若备份不含某些账号，恢复接口会在 `needsPassword` 里点名，需管理员设初始密码（见第一节「备份与恢复」） |
| `docker compose down -v` 后数据没了 | `-v` 会**删除数据卷**（含账本）。日常升级只用 `docker compose down` + `pull` + `up -d`，不要加 `-v` |
