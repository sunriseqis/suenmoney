import { randomBytes } from 'node:crypto';

/**
 * ULID —— 26 字符，10 字符时间前缀 + 16 字符随机。
 *
 * 为什么不用自增 ID / UUID：
 *   - 自增 ID 由服务端分配，但**客户端离线时也要创建记录**，那时拿不到服务端
 *     分配的 ID，关联关系（记录 → 分类、记录 → 计划）就无从建立。
 *   - UUIDv4 没有时间前缀，插入时会让 B-Tree 索引随机分裂；ULID 的时间前缀
 *     让新记录总是追加在索引尾部。
 *
 * Crockford Base32：去掉了 I / L / O / U，避免人工核对时与 1 / 0 混淆。
 */
const CROCKFORD = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function ulid(now: number = Date.now()): string {
  let time = '';
  let rest = now;

  for (let index = 0; index < 10; index += 1) {
    time = CROCKFORD[rest % 32]! + time;
    rest = Math.floor(rest / 32);
  }

  const bytes = randomBytes(16);
  let randomness = '';
  for (let index = 0; index < 16; index += 1) {
    randomness += CROCKFORD[bytes[index]! & 31];
  }

  return time + randomness;
}

/** 校验一个字符串是否是形状合法的 ULID（用于拒绝客户端传来的垃圾 ID）。 */
export function isUlid(value: string): boolean {
  return /^[0-9A-HJKMNP-TV-Z]{26}$/.test(value);
}
