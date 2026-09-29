# SuenMoney Server Dockerfile
FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV SUENMONEY_HOST=0.0.0.0
ENV SUENMONEY_PORT=3310
ENV SUENMONEY_DB_PATH=/app/server/data/suenmoney.sqlite
ENV SUENMONEY_BACKUP_DIR=/app/server/data/backups

# 复制服务端依赖声明并安装生产依赖
COPY server/package*.json ./server/
WORKDIR /app/server
RUN npm ci --omit=dev

# 复制脚本与服务端源码
WORKDIR /app
COPY scripts/ ./scripts/
COPY server/ ./server/

WORKDIR /app/server

# 数据挂载点（包含 sqlite 文件与 backups 快照目录）
VOLUME ["/app/server/data"]

EXPOSE 3310

CMD ["node", "../scripts/node-run.mjs", "src/index.ts"]
