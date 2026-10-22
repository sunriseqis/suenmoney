/**
 * 客户端 ULID 生成器 —— 26 字符，10 字符时间前缀 + 16 字符随机。
 *
 * 采用 Crockford Base32 编码（排除了 I / L / O / U，避免与 1 / 0 混淆）。
 * 保证时间递增序，且在离线状态下可在本地预分配实体 ID。
 */
const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function ulid(now: number = Date.now()): string {
  let time = '';
  let rest = now;

  for (let index = 0; index < 10; index += 1) {
    time = CROCKFORD[rest % 32]! + time;
    rest = Math.floor(rest / 32);
  }

  const bytes = new Uint8Array(16);
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    crypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
  }

  let randomness = '';
  for (let index = 0; index < 16; index += 1) {
    randomness += CROCKFORD[bytes[index]! & 31];
  }

  return time + randomness;
}

/** 校验字符串是否为标准 26 位 ULID 格式 */
export function isUlid(value: string): boolean {
  return /^[0-9A-HJKMNP-TV-Z]{26}$/.test(value);
}
