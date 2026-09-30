#!/usr/bin/env node
/**
 * iOS 构建脚本：Web 编译 → cap sync ios → xcodebuild → 导出未签名 IPA。
 *
 * 用法：
 *   node scripts/build-ios.mjs --sync-only      # 仅执行 web build + cap sync ios
 *   node scripts/build-ios.mjs --unsigned       # 构建未签名 IPA，产出 app/SuenMoney-v<版本>-release.ipa
 *   node scripts/build-ios.mjs                  # 开发签名构建（需要 Xcode 配置 Team）
 */

import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, readFile, rm, stat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const WEB_DIR = join(ROOT, 'web');
const IOS_PROJECT = join(ROOT, 'ios/App/App.xcodeproj');
const PBXPROJ = join(IOS_PROJECT, 'project.pbxproj');
const OUTPUT_DIR = join(ROOT, 'app');

const TARGET = process.env.IOS_APP_TARGET || 'App';
const ALLOW_PROVISIONING_UPDATES = process.env.IOS_ALLOW_PROVISIONING_UPDATES !== '0';
const SYNC_ONLY = process.argv.includes('--sync-only');
const UNSIGNED = process.argv.includes('--unsigned');

const SYMROOT = join(OUTPUT_DIR, UNSIGNED ? 'build-unsigned' : 'build');
const IPA_DIR = UNSIGNED ? join(OUTPUT_DIR, 'unsigned') : OUTPUT_DIR;

function fail(message) {
  console.error(`\n✖ ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  console.log(`\n$ ${command} ${args.join(' ')}`);
  execFileSync(command, args, { stdio: 'inherit', ...options });
}

function output(command, args, options = {}) {
  return execFileSync(command, args, { encoding: 'utf8', ...options }).trim();
}

if (process.platform !== 'darwin' && !SYNC_ONLY) {
  fail(`iOS IPA 构建只能在 macOS 上跑（当前操作系统为 ${process.platform}）。`);
}

async function readVersionName() {
  const raw = (await readFile(join(ROOT, 'VERSION'), 'utf8')).trim();
  if (!/^\d+(?:\.\d+)*$/.test(raw)) {
    fail(`VERSION 文件内容不是合法版本号：${JSON.stringify(raw)}`);
  }
  return raw;
}

function readVersionCode(versionName) {
  try {
    const count = Number(output('git', ['rev-list', '--count', 'HEAD'], { cwd: ROOT }));
    if (Number.isInteger(count) && count > 0) {
      return { code: 10000 + count, source: `10000 + git 提交数 ${count}` };
    }
  } catch {
    /* 无法执行 git 时回退到版本号推导 */
  }
  const [major = 0, minor = 0, patch = 0] = versionName.split('.').map(Number);
  return {
    code: 10000 + major * 100 + minor * 10 + patch,
    source: `按版本号推导`,
  };
}

async function readTeamId() {
  if (!existsSync(PBXPROJ)) return null;
  const pbx = await readFile(PBXPROJ, 'utf8');
  return /DEVELOPMENT_TEAM = ([A-Za-z0-9]+);/.exec(pbx)?.[1] ?? null;
}

async function syncWeb() {
  console.log('\n── 1/2 编译 Web 静态资源 ──');
  run('npm', ['run', 'build'], { cwd: WEB_DIR });

  console.log('\n── 2/2 同步至 iOS 原生工程 (cap sync ios) ──');
  run('npx', ['cap', 'sync', 'ios'], { cwd: WEB_DIR });
}

async function buildIpa(versionName, versionCode) {
  await mkdir(IPA_DIR, { recursive: true });

  const args = [
    '-project', IOS_PROJECT,
    '-target', TARGET,
    '-configuration', 'Release',
    '-sdk', 'iphoneos',
    `SYMROOT=${SYMROOT}`,
    `MARKETING_VERSION=${versionName}`,
    `CURRENT_PROJECT_VERSION=${versionCode}`,
  ];

  if (UNSIGNED) {
    args.push('CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=""');
  } else if (ALLOW_PROVISIONING_UPDATES) {
    args.push('-allowProvisioningUpdates');
  }
  args.push('build');

  console.log(
    `\n── 编译 Release（版本 ${versionName} / code ${versionCode}，${UNSIGNED ? '未签名' : '开发签名'}）──`
  );
  run('xcodebuild', args, { cwd: join(ROOT, 'ios/App') });

  const appPath = join(SYMROOT, 'Release-iphoneos', `${TARGET}.app`);
  if (!existsSync(appPath)) fail(`找不到编译产物：${appPath}`);

  console.log('\n── 打包 IPA ──');
  const payloadDir = join(IPA_DIR, 'Payload');
  await rm(payloadDir, { recursive: true, force: true });
  await mkdir(payloadDir, { recursive: true });
  run('cp', ['-R', appPath, payloadDir]);

  const ipaName = `SuenMoney-v${versionName}-release.ipa`;
  const ipaPath = join(IPA_DIR, ipaName);
  await rm(ipaPath, { force: true });
  run('zip', ['-qry', ipaName, 'Payload'], { cwd: IPA_DIR });
  await rm(payloadDir, { recursive: true, force: true });

  const { size } = await stat(ipaPath);
  console.log(`\n✔ 已生成 IPA：${ipaPath}`);
  console.log(`  大小 ${(size / 1024 / 1024).toFixed(1)} MB${UNSIGNED ? '（未签名，供 AltStore / SideStore / TrollStore 自签使用）' : ''}`);
}

const versionName = await readVersionName();
const teamId = await readTeamId();
if (!UNSIGNED && !teamId && !SYNC_ONLY) {
  console.warn('提示：未配置 DEVELOPMENT_TEAM，将默认进行未签名构建。');
}

await syncWeb();

if (SYNC_ONLY) {
  console.log('\n✔ Web 静态资源已同步至 iOS 工程。');
} else {
  const { code: versionCode, source } = readVersionCode(versionName);
  console.log(`versionCode: ${versionCode} (${source})`);
  await buildIpa(versionName, versionCode);
}
