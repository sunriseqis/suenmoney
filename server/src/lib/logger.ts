/**
 * 服务层日志（非 HTTP 路径用）。
 *
 * HTTP 请求内的日志走 Fastify 的 `request.log`；但 `services/` 里的后台任务
 * （更新产物刷新、WebDAV 备份调度等）没有 request 上下文，需要一个自己的出口。
 *
 * 这里刻意做得很薄：**只加模块前缀**，输出交给 stdout/stderr，
 * 由 systemd / 容器日志收集接管（与 Fastify 的 pino 输出并列，不抢它的格式）。
 */

type Level = 'debug' | 'info' | 'warn' | 'error';

const ORDER: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };

function threshold(): number {
  const raw = (process.env['SUENMONEY_LOG_LEVEL'] ?? 'info').trim().toLowerCase();
  return ORDER[(raw as Level)] ?? ORDER.info;
}

function emit(level: Level, scope: string, message: string): void {
  if (ORDER[level] < threshold()) return;
  const line = `[${new Date().toISOString()}] ${level.toUpperCase()} [${scope}] ${message}`;
  if (level === 'error' || level === 'warn') {
    console.error(line);
  } else {
    console.log(line);
  }
}

export interface Logger {
  debug(message: string): void;
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

export function createLogger(scope: string): Logger {
  return {
    debug: (m: string) => emit('debug', scope, m),
    info: (m: string) => emit('info', scope, m),
    warn: (m: string) => emit('warn', scope, m),
    error: (m: string) => emit('error', scope, m),
  };
}
