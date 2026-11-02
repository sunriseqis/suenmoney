import { existsSync } from 'node:fs';

export type DeployMode = 'fnos' | 'docker';

/**
 * 判定服务端当前的部署方式：
 * - `fnos`   —— 飞牛私有云原生套件（`.fpk` 装的）
 * - `docker` —— 容器化部署（默认）
 *
 * 用途：**更新语义不同**。
 *   · fnOS 套件：服务端把新 `.fpk` 拉到本地缓存，界面提示用户下载后手动覆盖安装；
 *   · Docker：只比对版本，提示「去拉新镜像」—— 不下载 `.fpk`（容器里没有覆盖安装这回事）。
 *
 * 判定依据：fnOS 的 `cmd/main` 会导出 `TRIM_APPDEST` / `TRIM_PKGVAR`；
 * 容器里则有 `/.dockerenv`。都不匹配时按 docker 处理（更保守：不做本地下载）。
 */
export function getDeployMode(): DeployMode {
  const env = (process.env['SUENMONEY_DEPLOY_ENV'] ?? '').trim().toLowerCase();
  if (env === 'fnos' || process.env['TRIM_APPDEST'] || process.env['TRIM_PKGVAR']) {
    return 'fnos';
  }
  if (env === 'docker' || existsSync('/.dockerenv') || existsSync('/run/.containerenv')) {
    return 'docker';
  }
  return 'docker';
}
