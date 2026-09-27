/**
 * 创建账号。
 *
 *   npm run user:add -- --username suen --name 你 --admin
 *
 * 不传 --password 时会**随机生成一个强口令并打印出来**，而不是让你
 * 留空或用一个弱口令。随机生成比「请自行设置」更安全 —— 反正马上就能
 * 在界面上改掉。
 */
import { randomBytes } from 'node:crypto';

import { migrate, openDatabase } from '../db/index.ts';
import { countUsers, createUser, type UserRole } from '../db/repo/users.ts';

function arg(name: string): string | undefined {
  const index = process.argv.indexOf(`--${name}`);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  return value === undefined || value.startsWith('--') ? undefined : value;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

const username = arg('username');
if (username === undefined || username.trim() === '') {
  console.error('用法：npm run user:add -- --username <登录名> [--name <显示名>] [--password <口令>] [--admin]');
  process.exit(1);
}

const db = openDatabase();
migrate(db);

const generated = arg('password') === undefined;
const password = arg('password') ?? randomBytes(15).toString('base64url');
const isFirstUser = countUsers(db) === 0;

// 第一个账号必须是管理员，否则会出现「有账号但没人能进后台」的死局
const role: UserRole = hasFlag('admin') || isFirstUser ? 'admin' : 'member';

const user = createUser(db, {
  username,
  displayName: arg('name') ?? username,
  password,
  role,
});

console.log(`已创建账号：${user.displayName}（${user.username}，${user.role}）`);
if (generated) {
  console.log(`\n随机口令（请立即保存并登录后修改）：\n\n    ${password}\n`);
}
if (isFirstUser) {
  console.log('这是第一个账号，已自动设为管理员，可以进入 Web 后台管理其他账号。');
}
