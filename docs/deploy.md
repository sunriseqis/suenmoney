# SuenMoney 部署与运维指南

SuenMoney 是专为家庭设计的精益记账系统。本文档介绍如何使用 Docker Compose 进行自托管生产部署、数据持久化配置与物理快照灾备。

---

## 一、架构设计

```
[ 用户终端浏览器 / 移动端 WebView ]
                │
                ▼ (HTTP 端口 5310 或 80)
┌───────────────────────────────────────────────┐
│                 Nginx (Web)                   │
│  - 托管 Vue 3 SPA 静态资源与字体 (Gzip 强缓存)    │
│  - 反向代理 /api/ 到后端服务                     │
└───────────────────────┬───────────────────────┘
                        │ (Docker 内部网络: 3310)
                        ▼
┌───────────────────────────────────────────────┐
│             Fastify (Server)                  │
│  - Node 22 原生 TypeScript 剥离执行            │
│  - node:sqlite 原生单文件数据库连接             │
│  - 每日 SQLite VACUUM INTO 物理快照调度器      │
└───────────────────────┬───────────────────────┘
                        │
                        ▼ (持久化卷 suenmoney-data)
┌───────────────────────────────────────────────┐
│              宿主机持久化卷                      │
│  /app/server/data/                            │
│  ├── suenmoney.sqlite         (主数据库文件)    │
│  ├── suenmoney.sqlite-wal     (WAL 事务日志)   │
│  └── backups/snapshots/       (每日物理快照库)  │
└───────────────────────────────────────────────┘
```

---

## 二、快速开始（Docker Compose 一键部署）

### 1. 前置条件
- 已安装 **Docker** (≥ 24.0) 及 **Docker Compose** (≥ v2.20)。

### 2. 获取代码与配置文件
```bash
git clone https://github.com/your-username/suenmoney.git
cd suenmoney
```

### 3. 配置管理员（可选）
在启动前，可编辑 `docker-compose.yml` 中的环境变量，设置开机自动创建的管理员账户：

```yaml
    environment:
      - SUENMONEY_PORT=3310
      - SUENMONEY_ADMIN_USER=admin
      - SUENMONEY_ADMIN_PASSWORD=your_secure_password
      - SUENMONEY_ADMIN_NAME=家庭管理员
```
*(注：如果数据库中已存在任何用户，该环境变量会被自动忽略，保证数据安全。)*

### 4. 启动服务
```bash
# 启动并在后台运行容器组
docker compose up -d --build
```

### 5. 访问与初始化
服务默认监听在宿主机的 `http://localhost:5310`。
- 若已在 `docker-compose.yml` 中配置了初始管理员，直接登录即可开始记账；
- 若未配置，可在容器内手动添加管理员：
```bash
docker compose exec server npm run user:add -- --username admin --name 管理员 --password 你的安全口令 --admin
```
*(若不指定 `--password`，命令会自动随机生成一个高强度口令并打印)*

---

## 三、环境变量速查

| 环境变量 | 默认值 | 作用说明 |
|---|---|---|
| `SUENMONEY_PORT` | `5310` (Web) / `3310` (Server) | Web 映射端口与服务端监听端口 |
| `SUENMONEY_HOST` | `0.0.0.0` | 服务端监听地址 |
| `SUENMONEY_DB_PATH` | `/app/server/data/suenmoney.sqlite` | SQLite 单文件数据库完整路径 |
| `SUENMONEY_BACKUP_DIR` | `/app/server/data/backups` | 物理快照与恢复前归档存储目录 |
| `SUENMONEY_BACKUP_KEEP` | `14` | 物理快照最大保留份数（自动淘汰最旧快照） |
| `SUENMONEY_SESSION_DAYS` | `180` | 登录会话有效期（天） |
| `SUENMONEY_ALLOW_REGISTRATION` | `false` | 是否开放公网公开注册（默认关闭，仅管理员可创建） |
| `SUENMONEY_ADMIN_USER` | 空 | 初始管理员登录名（仅库为空时生效） |
| `SUENMONEY_ADMIN_PASSWORD` | 空 | 初始管理员口令（仅库为空时生效） |
| `SUENMONEY_ADMIN_NAME` | 空 | 初始管理员显示名称 |

---

## 四、双层备份与容灾恢复机制

SuenMoney 采用区分用户与运维的双层备份策略：

### 1. 运维侧物理快照（SQLite `VACUUM INTO`）
- **机制**：由服务端内置定时器每日自动执行 SQLite 原生 `VACUUM INTO` 命令。该命令将当前库文件完整复制并归并 WAL，生成一份物理级一致性副本。
- **存储**：保存在数据卷的 `backups/snapshots/suenmoney-snapshot-YYYYMMDD-HHmmss.sqlite`。
- **保留策略**：系统自动维持最近 `SUENMONEY_BACKUP_KEEP`（默认 14 份）快照，超额自动回收旧文件。
- **下载管理**：管理员登录 Web 端后，进入「设置 → 数据」，可直接查看快照历史列表、文件大小，并提供「一键下载」与「手动创建实时快照」按钮。

### 2. 物理快照灾备还原（冷恢复）
若遇到数据库意外损坏或误操作，可从快照快速恢复：
```bash
# 1. 停止运行中的容器
docker compose stop server

# 2. 找到需要恢复的快照文件并覆盖主库
# (可通过 docker volume inspect suenmoney-data 查看实际挂载路径)
docker run --rm -v suenmoney-data:/data alpine sh -c "
  cp /data/backups/snapshots/suenmoney-snapshot-20260929-120000.sqlite /data/suenmoney.sqlite &&
  rm -f /data/suenmoney.sqlite-wal /data/suenmoney.sqlite-shm
"

# 3. 重新启动服务
docker compose start server
```

### 3. 用户侧跨版本逻辑备份（JSON 数据包）
- **机制**：在 Web 界面「设置 → 数据」中，管理员可随时导出/导入标准全量 JSON 数据包。
- **特性**：明文可读、版本兼容、支持幂等补缺合并与全量覆盖恢复。

---

## 五、日常维护常用命令

```bash
# 查看服务端实时日志
docker compose logs -f server

# 查看前端反代实时日志
docker compose logs -f web

# 备份整个 Docker Volume 到当前目录压缩包
docker run --rm -v suenmoney-data:/data -v $(pwd):/backup alpine tar czvf /backup/suenmoney-data-backup-$(date +%Y%m%d).tar.gz /data

# 从压缩包恢复 Docker Volume
docker run --rm -v suenmoney-data:/data -v $(pwd):/backup alpine sh -c "cd / && tar xzvf /backup/suenmoney-data-backup-20260929.tar.gz"

# 升级镜像并重启
git pull
docker compose up -d --build
```
