import { createHash, randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

/**
 * 口令哈希 —— 用 Node 内置的 scrypt，不引入任何原生依赖。
 *
 * 为什么不用 bcrypt / argon2：它们都是原生模块，需要本地编译工具链。
 * 「为了哈希一个 2 人家庭的口令而要求部署环境装 C++ 编译器」不划算。
 * scrypt 是内存硬的，抗 GPU 暴力破解，由 Node 标准库直接提供。
 *
 * 存储格式：scrypt$N$r$p$salt(base64)$hash(base64)
 * 把参数一起存进去，将来调强参数时旧口令仍然可以校验。
 */
const N = 16_384;
const R = 8;
const P = 1;
const KEY_LEN = 32;
const MAX_MEM = 64 * 1024 * 1024;

function derive(plain: string, salt: Buffer, keyLen: number, n: number, r: number, p: number): Buffer {
  return scryptSync(plain, salt, keyLen, { N: n, r, p, maxmem: MAX_MEM });
}

export function hashPassword(plain: string): string {
  const salt = randomBytes(16);
  const hash = derive(plain, salt, KEY_LEN, N, R, P);
  return `scrypt$${N}$${R}$${P}$${salt.toString('base64')}$${hash.toString('base64')}`;
}

export function verifyPassword(plain: string, stored: string): boolean {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;

  const n = Number(parts[1]);
  const r = Number(parts[2]);
  const p = Number(parts[3]);
  const saltRaw = parts[4];
  const hashRaw = parts[5];

  if (
    !Number.isInteger(n) ||
    !Number.isInteger(r) ||
    !Number.isInteger(p) ||
    saltRaw === undefined ||
    hashRaw === undefined
  ) {
    return false;
  }

  const salt = Buffer.from(saltRaw, 'base64');
  const expected = Buffer.from(hashRaw, 'base64');
  if (expected.length === 0) return false;

  const actual = derive(plain, salt, expected.length, n, r, p);
  // 长度不等时 timingSafeEqual 会抛异常，所以先比长度
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/**
 * 生成会话令牌。
 *
 * 返回「明文 + 哈希」两份：明文只在这一刻存在于内存里、发给客户端后就丢弃，
 * 数据库里**只存哈希**。这样即使库文件泄漏或被备份到别处，也无法直接冒用会话。
 */
export function createSessionToken(): { token: string; tokenHash: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, tokenHash: hashToken(token) };
}

/** 令牌哈希用 SHA-256 而非 scrypt：令牌是 256 位随机串，不需要抗暴力破解。 */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
