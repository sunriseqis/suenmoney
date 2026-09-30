# syntax=docker/dockerfile:1
# ==============================================================================
# SuenMoney Server Dockerfile
# 基于 Node 22 轻量级 Alpine 镜像，原生运行 TypeScript
#
# 多架构构建注意：npm ci 必须在 --platform=$BUILDPLATFORM 跑，避免 QEMU 模拟 arm64 时
# 触发 Node V8 JIT 探测崩溃（SIGILL exit code 132）。
# 依赖均为纯 JS，node_modules 可以安全跨架构复用。
# ==============================================================================

# ---- 阶段 1：依赖安装（构建机原生平台） ----
FROM --platform=$BUILDPLATFORM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force

# ---- 阶段 2：生产运行镜像（目标架构） ----
FROM node:22-alpine AS runner

RUN apk add --no-cache tzdata wget ca-certificates

WORKDIR /app

ENV NODE_ENV=production \
    SUENMONEY_HOST=0.0.0.0 \
    SUENMONEY_PORT=3310 \
    SUENMONEY_DB_PATH=/app/data/suenmoney.sqlite \
    SUENMONEY_BACKUP_DIR=/app/data/backups

# 纯 JS 依赖：直接复用构建机装好的 node_modules
COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY scripts/ ./scripts/
COPY src/ ./src/

# 预先创建持久化数据目录，并将所有权赋予非 root 用户 node
RUN mkdir -p /app/data /app/data/backups && chown -R node:node /app

USER node

EXPOSE 3310

VOLUME ["/app/data"]

# 容器健康检查：定时探测 /api/health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3310/api/health || exit 1

# 启动服务
CMD ["node", "scripts/node-run.mjs", "src/index.ts"]
