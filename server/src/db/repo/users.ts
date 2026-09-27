import type { DatabaseSync } from 'node:sqlite';

import { badRequest, conflict, notFound } from '../../lib/http-error.ts';
import { hashPassword } from '../../lib/password.ts';
import { ulid } from '../../lib/ulid.ts';
import { inTransaction, recordChange } from '../sync.ts';

export type UserRole = 'admin' | 'member';

export interface UserRow {
  id: string;
  username: string;
  display_name: string;
  password_hash: string;
  role: UserRole;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
  rev: number;
  device_id: string | null;
}

/** 可以安全下发给客户端的用户字段 —— **password_hash 永不出现**。 */
export interface PublicUser {
  id: string;
  username: string;
  displayName: string;
  role: UserRole;
}

const COLUMNS = `id, username, display_name, password_hash, role, created_at, updated_at, deleted_at, rev, device_id`;

const nowIso = (): string => new Date().toISOString();

export function toPublicUser(row: UserRow): PublicUser {
  return { id: row.id, username: row.username, displayName: row.display_name, role: row.role };
}

/** 同步给客户端的用户信息：只有显示名，用于渲染「记录人」。 */
export function toSyncUser(row: UserRow): Record<string, unknown> {
  return {
    id: row.id,
    username: row.username,
    displayName: row.display_name,
    role: row.role,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
    rev: row.rev,
  };
}

export function findUserByUsername(db: DatabaseSync, username: string): UserRow | null {
  const row = db
    .prepare(`SELECT ${COLUMNS} FROM users WHERE username = ? AND deleted_at IS NULL`)
    .get(username.toLowerCase());
  return (row as unknown as UserRow | undefined) ?? null;
}

export function findUserById(db: DatabaseSync, id: string): UserRow | null {
  const row = db
    .prepare(`SELECT ${COLUMNS} FROM users WHERE id = ? AND deleted_at IS NULL`)
    .get(id);
  return (row as unknown as UserRow | undefined) ?? null;
}

export function listUsers(db: DatabaseSync): PublicUser[] {
  const rows = db
    .prepare(`SELECT ${COLUMNS} FROM users WHERE deleted_at IS NULL ORDER BY created_at`)
    .all();
  return (rows as unknown as UserRow[]).map(toPublicUser);
}

export function countUsers(db: DatabaseSync): number {
  const row = db.prepare('SELECT COUNT(*) AS n FROM users WHERE deleted_at IS NULL').get();
  return row === undefined ? 0 : Number(row['n']);
}

export interface UpdateUserInput {
  displayName?: string | undefined;
  role?: UserRole | undefined;
  /** 传了才改口令；改完调用方应吊销该用户的其他会话 */
  password?: string | undefined;
  actorId: string;
}

export function updateUser(db: DatabaseSync, id: string, input: UpdateUserInput): PublicUser {
  const existing = findUserById(db, id);
  if (existing === null) throw notFound(`用户不存在：${id}`);

  /**
   * 不允许把最后一个管理员降级。
   *
   * 否则会出现「系统里还有账号，但没有任何人能进后台管理」的死局，
   * 只能去命令行改数据库才能恢复。
   */
  if (input.role === 'member' && existing.role === 'admin' && countAdmins(db) <= 1) {
    throw conflict('这是唯一的admin账号，不能降级为普通成员');
  }

  const displayName = (input.displayName ?? existing.display_name).trim();
  if (displayName === '') throw badRequest('显示名不能为空');

  const next: UserRow = {
    ...existing,
    display_name: displayName,
    role: input.role ?? existing.role,
    password_hash:
      input.password === undefined ? existing.password_hash : hashPassword(input.password),
    updated_at: nowIso(),
    rev: existing.rev + 1,
  };

  inTransaction(db, () => {
    db.prepare(
      `UPDATE users SET display_name = ?, role = ?, password_hash = ?,
                        updated_at = ?, rev = ?
        WHERE id = ?`,
    ).run(next.display_name, next.role, next.password_hash, next.updated_at, next.rev, next.id);

    recordChange(db, {
      entityType: 'user',
      entityId: next.id,
      op: 'upsert',
      actorId: input.actorId,
      payload: toSyncUser(next),
      deviceId: next.device_id,
    });
  });

  return toPublicUser(next);
}

export function countAdmins(db: DatabaseSync): number {
  const row = db
    .prepare("SELECT COUNT(*) AS n FROM users WHERE role = 'admin' AND deleted_at IS NULL")
    .get();
  return row === undefined ? 0 : Number(row['n']);
}

export interface CreateUserInput {
  username: string;
  displayName: string;
  password: string;
  role?: UserRole;
  deviceId?: string | null;
}

/**
 * 创建用户。
 *
 * 用户名统一转小写存储 —— 否则「Suen」和「suen」会被当成两个账号，
 * 而登录时大小写不一致又会让人以为密码错了。
 */
export function createUser(db: DatabaseSync, input: CreateUserInput): PublicUser {
  const username = input.username.trim().toLowerCase();

  if (username === '') {
    throw conflict('用户名不能为空');
  }
  if (findUserByUsername(db, username) !== null) {
    throw conflict(`用户名已被占用：${username}`);
  }

  const id = ulid();
  const timestamp = nowIso();
  const row: UserRow = {
    id,
    username,
    display_name: input.displayName.trim() || username,
    password_hash: hashPassword(input.password),
    role: input.role ?? 'member',
    created_at: timestamp,
    updated_at: timestamp,
    deleted_at: null,
    rev: 1,
    device_id: input.deviceId ?? null,
  };

  inTransaction(db, () => {
    db.prepare(
      `INSERT INTO users (id, username, display_name, password_hash, role,
                          created_at, updated_at, deleted_at, rev, device_id)
       VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 1, ?)`,
    ).run(
      row.id,
      row.username,
      row.display_name,
      row.password_hash,
      row.role,
      row.created_at,
      row.updated_at,
      row.device_id,
    );

    recordChange(db, {
      entityType: 'user',
      entityId: row.id,
      op: 'upsert',
      actorId: row.id,
      payload: toSyncUser(row),
      deviceId: row.device_id,
    });
  });

  return toPublicUser(row);
}
