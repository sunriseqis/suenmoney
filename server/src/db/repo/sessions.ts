import type { DatabaseSync } from 'node:sqlite';

import { createSessionToken, hashToken } from '../../lib/password.ts';
import { ulid } from '../../lib/ulid.ts';
import type { UserRow } from './users.ts';

export interface SessionRow {
  id: string;
  user_id: string;
  token_hash: string;
  device_label: string;
  created_at: string;
  last_seen_at: string;
  expires_at: string;
  revoked_at: string | null;
}

export interface SessionInfo {
  id: string;
  deviceLabel: string;
  createdAt: string;
  lastSeenAt: string;
  expiresAt: string;
}

const nowIso = (): string => new Date().toISOString();

export function toSessionInfo(row: SessionRow): SessionInfo {
  return {
    id: row.id,
    deviceLabel: row.device_label,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
    expiresAt: row.expires_at,
  };
}

/**
 * 新建会话。
 *
 * 明文令牌只在这里返回一次，之后数据库里只剩 SHA-256 哈希 —— 因此
 * 「数据库被拷走」不等于「会话被冒用」，也不需要任何服务端签名密钥
 * （这正是放弃 JWT 的主要原因之一：密钥换掉就等于把所有人踢下线）。
 */
export function createSession(
  db: DatabaseSync,
  userId: string,
  deviceLabel: string,
  sessionDays: number,
): { token: string; expiresAt: string; sessionId: string } {
  const { token, tokenHash } = createSessionToken();
  const timestamp = nowIso();
  const expires = new Date(Date.now() + sessionDays * 86_400_000).toISOString();
  const sessionId = ulid();

  db.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, device_label,
                           created_at, last_seen_at, expires_at, revoked_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, NULL)`,
  ).run(sessionId, userId, tokenHash, deviceLabel.slice(0, 120), timestamp, timestamp, expires);

  return { token, expiresAt: expires, sessionId };
}

/**
 * 用令牌明文查出有效会话及其用户。
 *
 * 三个条件缺一不可：哈希命中、未吊销、未过期。
 */
export function findSessionByToken(
  db: DatabaseSync,
  token: string,
): { session: SessionRow; user: UserRow } | null {
  const session = db
    .prepare(
      `SELECT id, user_id, token_hash, device_label, created_at, last_seen_at, expires_at, revoked_at
         FROM sessions
        WHERE token_hash = ? AND revoked_at IS NULL AND expires_at > ?`,
    )
    .get(hashToken(token), nowIso()) as unknown as SessionRow | undefined;

  if (session === undefined) return null;

  const user = db
    .prepare(
      `SELECT id, username, display_name, password_hash, role, created_at, updated_at,
              deleted_at, rev, device_id
         FROM users WHERE id = ? AND deleted_at IS NULL`,
    )
    .get(session.user_id) as unknown as UserRow | undefined;

  if (user === undefined) return null;

  return { session, user };
}

/**
 * 刷新 last_seen_at，用于「当前登录设备」列表里显示活跃时间。
 *
 * 只在距离上次记录超过 1 小时时才写库 —— 每次请求都写会把 WAL 写爆，
 * 而「最后活跃时间」精确到小时完全够用。
 */
export function touchSession(db: DatabaseSync, sessionId: string, lastSeenAt: string): void {
  const ageMs = Date.now() - new Date(lastSeenAt).getTime();
  if (ageMs < 3_600_000) return;

  db.prepare('UPDATE sessions SET last_seen_at = ? WHERE id = ?').run(nowIso(), sessionId);
}

export function revokeSession(db: DatabaseSync, sessionId: string): void {
  db.prepare('UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL').run(
    nowIso(),
    sessionId,
  );
}

export function revokeSessionByToken(db: DatabaseSync, token: string): void {
  db.prepare('UPDATE sessions SET revoked_at = ? WHERE token_hash = ? AND revoked_at IS NULL').run(
    nowIso(),
    hashToken(token),
  );
}

/** 吊销该用户的其他所有会话 —— 改密码时用。 */
export function revokeOtherSessions(db: DatabaseSync, userId: string, keepSessionId: string): number {
  const info = db
    .prepare(
      'UPDATE sessions SET revoked_at = ? WHERE user_id = ? AND id <> ? AND revoked_at IS NULL',
    )
    .run(nowIso(), userId, keepSessionId);
  return Number(info.changes);
}

export function listSessions(db: DatabaseSync, userId: string): SessionInfo[] {
  const rows = db
    .prepare(
      `SELECT id, user_id, token_hash, device_label, created_at, last_seen_at, expires_at, revoked_at
         FROM sessions
        WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ?
        ORDER BY last_seen_at DESC`,
    )
    .all(userId, nowIso());
  return (rows as unknown as SessionRow[]).map(toSessionInfo);
}

export function purgeExpiredSessions(db: DatabaseSync): number {
  const info = db
    .prepare('DELETE FROM sessions WHERE expires_at <= ? OR revoked_at IS NOT NULL')
    .run(nowIso());
  return Number(info.changes);
}
