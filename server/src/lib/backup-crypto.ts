/**
 * `.mn` —— 口令加密的数据库备份包。
 *
 * 为什么需要它
 * ------------
 * JSON 备份 = **整个数据库，含账号与 `password_hash`**。这个文件一旦落到
 * 第三方存储（WebDAV / 网盘 / NAS 共享），等同于把「整库 + 登录凭据」交出去。
 * 所以推到远端之前必须加密，且加密必须绑口令 —— 拿不到口令就解不开。
 *
 * 文件格式
 * --------
 * ```
 * offset  size  内容
 * 0       14    magic  "SUENMONEY-MN1\0"
 * 14      16    salt   （scrypt 用，每次随机）
 * 30      12    iv     （AES-GCM 用，每次随机）
 * 42      16    tag    （GCM 认证标签）
 * 58      -     ciphertext
 * ```
 *
 * 处理顺序：**先 gzip 压缩，再加密**。
 * 反过来（先加密再压缩）压缩的是一坨高熵数据，几乎压不掉一个字节 ——
 * 顺序反了只会让包更大，没有任何好处。
 *
 * 口令派生：`scrypt(passphrase, salt, 32)`，默认参数（N=16384, r=8, p=1）；
 * 这个组合在普通 NAS 上约 50–100ms，对「手动触发的一次备份」完全可接受，
 * 而对离线爆破足够贵。
 *
 * 认证：AES-256-GCM 自带 tag 校验 —— **口令错、或文件被篡改，都会在解密阶段
 * 直接抛错**，不会「解出一半垃圾数据再写库」。
 */

import { createCipheriv, createDecipheriv, randomBytes, scryptSync } from 'node:crypto';
import { gunzipSync, gzipSync } from 'node:zlib';

const MAGIC = Buffer.from('SUENMONEY-MN1\u0000', 'binary'); // 14 字节
const SALT_LEN = 16;
const IV_LEN = 12;
const TAG_LEN = 16;
const KEY_LEN = 32;

export class MnFormatError extends Error {}

function deriveKey(passphrase: string, salt: Buffer): Buffer {
  if (passphrase.trim() === '') {
    throw new MnFormatError('备份口令不能为空');
  }
  return scryptSync(passphrase, salt, KEY_LEN);
}

/** 把 JSON 文本打包成 `.mn` 二进制。 */
export function packMn(json: string, passphrase: string): Buffer {
  const salt = randomBytes(SALT_LEN);
  const iv = randomBytes(IV_LEN);
  const key = deriveKey(passphrase, salt);

  const compressed = gzipSync(Buffer.from(json, 'utf8'), { level: 9 });

  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(compressed), cipher.final()]);
  const tag = cipher.getAuthTag();

  return Buffer.concat([MAGIC, salt, iv, tag, ciphertext]);
}

/**
 * 解开 `.mn`，返回原始 JSON 文本。
 *
 * 口令错 / 文件损坏 / 不是 `.mn` —— 都会抛 `MnFormatError`，
 * 由调用方翻译成人话（别说「authentication failed」，用户听不懂）。
 */
export function unpackMn(buf: Buffer, passphrase: string): string {
  if (buf.length < MAGIC.length + SALT_LEN + IV_LEN + TAG_LEN) {
    throw new MnFormatError('文件太小，不是有效的备份包');
  }
  if (!buf.subarray(0, MAGIC.length).equals(MAGIC)) {
    throw new MnFormatError('不是 SuenMoney 的加密备份包（文件头不匹配）');
  }

  let offset = MAGIC.length;
  const salt = buf.subarray(offset, offset + SALT_LEN); offset += SALT_LEN;
  const iv = buf.subarray(offset, offset + IV_LEN); offset += IV_LEN;
  const tag = buf.subarray(offset, offset + TAG_LEN); offset += TAG_LEN;
  const ciphertext = buf.subarray(offset);

  const key = deriveKey(passphrase, salt);

  let compressed: Buffer;
  try {
    const decipher = createDecipheriv('aes-256-gcm', key, iv);
    decipher.setAuthTag(tag);
    compressed = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  } catch {
    throw new MnFormatError('口令不对，或文件已损坏');
  }

  try {
    return gunzipSync(compressed).toString('utf8');
  } catch {
    throw new MnFormatError('备份包内容损坏（解压失败）');
  }
}

/** WebDAV 上的文件名：`suenmoney-backup-2026-11-01.mn` */
export function mnFileName(date: Date = new Date()): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `suenmoney-backup-${y}-${m}-${d}.mn`;
}
