# syntax=docker/dockerfile:1
# ==============================================================================
# SuenMoney 单镜像：一个进程同时提供前端页面与 /api 接口
#
# 三个阶段：
#   1) web-builder  构建前端产物（Vite）
#   2) deps         安装服务端生产依赖
#   3) runner       运行时：服务端 + web/dist，**单端口 5310**
#
# 多架构构建注意：npm ci 必须在 --platform=$BUILDPLATFORM 跑，避免 QEMU 模拟 arm64 时
# 触发 Node V8 JIT 探测崩溃（SIGILL exit code 132）。依赖均为纯 JS，可跨架构复用。
# ==============================================================================

# ---- 阶段 1：前端产物（构建机原生平台） ----
FROM --platform=$BUILDPLATFORM node:22-alpine AS web-builder
WORKDIR /app/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --ignore-scripts && npm cache clean --force
COPY web/ ./
RUN npm run build

# ---- 阶段 2：服务端生产依赖（构建机原生平台） ----
FROM --platform=$BUILDPLATFORM node:22-alpine AS deps
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# ---- 阶段 3：运行时（目标架构） ----
FROM node:22-alpine AS runner

RUN apk add --no-cache tzdata wget ca-certificates

WORKDIR /app/server

ENV NODE_ENV=production \
    SUENMONEY_HOST=0.0.0.0 \
    SUENMONEY_PORT=5310 \
    SUENMONEY_DB_PATH=/app/data/suenmoney.sqlite \
    SUENMONEY_BACKUP_DIR=/app/data/backups \
    SUENMONEY_WEB_ROOT=/app/web/dist \
    SUENMONEY_TRUST_PROXY=false \
    # 时区固定为东八区：快照/备份调度器的「每日」时刻、日志时间戳都依赖本地时区。
    # 业务日期不受影响（客户端传入 YYYY-MM-DD，服务端不推算），见 docs/decisions.md。
    TZ=Asia/Shanghai

COPY --from=deps /app/server/node_modules ./node_modules
COPY server/package.json server/package-lock.json ./
COPY server/scripts/ ./scripts/
COPY server/src/ ./src/
COPY --from=web-builder /app/web/dist /app/web/dist

# 版本文件供 /api/health 上报（服务端 cwd 是 /app/server，故读 ../VERSION）
COPY VERSION /app/VERSION

# 预先创建持久化数据目录，并将所有权赋予非 root 用户 node
RUN mkdir -p /app/data /app/data/backups && chown -R node:node /app

USER node

# 只有一个端口：页面（/）与接口（/api）同源同端口
EXPOSE 5310

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:5310/api/health || exit 1

CMD ["node", "scripts/node-run.mjs", "src/index.ts"]
