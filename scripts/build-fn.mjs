#!/usr/bin/env node
/**
 * 飞牛 fnOS 套件打包流水线 —— `npm run fn:build`
 *
 * 产物：`output/suenmoney-v<version>.fpk` + 同名 `.sha256`
 *
 * 七步，每步失败即中止：
 *   1. 版本注入（VERSION → fn/manifest）
 *   2. 图标（母版矢量 → 64/256，全交给 scripts/gen-brand.mjs）
 *   3. 自带 Node 运行时（sha256 校验）
 *   4. 组装 payload：web/dist + server 源码 + 生产依赖（**不带 devDeps**）
 *   5. 权限归一 + **零软链硬校验**
 *   6. 取 fnpack
 *   7. 出包 + 写 sha256
 *
 * 三个门禁对应三次真事故，别拆：
 *   · 包内不许有软链 —— node_modules/.bin 里的相对软链被打包器改写成自引用死链，
 *     飞牛赋权阶段 stat 失败，安装恒定报「设置目录权限失败」。
 *   · 包里不许有 typescript/@types —— 体积失控且不可复现。
 *   · 权限必须是 755/644 —— 构建机 umask 077 会让包内出现 700，装到 NAS 上读不到。
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  cpSync, createWriteStream, existsSync, mkdirSync, readdirSync, readFileSync,
  renameSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

process.umask(0o022);

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FN = join(ROOT, 'fn');
const APP = join(FN, 'app');
const CACHE = join(homedir(), '.cache/suenmoney-fn');
const OUT = join(ROOT, 'output');

const NODE_VERSION = 'v24.18.1';
const NODE_MIRROR = `https://registry.npmmirror.com/-/binary/node/${NODE_VERSION}`;
const FNPACK_URL = 'https://static2.fnnas.com/fnpack/fnpack-1.2.1-linux-amd64';

const argv = new Set(process.argv.slice(2));
const SKIP_WEB = argv.has('--skip-web');
const SKIP_FNPACK = argv.has('--skip-fnpack'); // 只验证 payload 组装，不出包
const SKIP_ICONS = argv.has('--skip-icons');

const step = (n, msg) => console.log(`\n[${n}/7] ${msg}`);
const ok = (msg) => console.log(`      ✓ ${msg}`);
const die = (msg) => {
  console.error(`      ✗ ${msg}`);
  process.exit(1);
};

// ── 1. 版本 ────────────────────────────────────────────────────────────────
function normalizeVersion() {
  const raw = readFileSync(join(ROOT, 'VERSION'), 'utf8').trim();
  const parts = raw.split('.');
  while (parts.length < 3) parts.push('0');
  const semver = parts.slice(0, 3).join('.');
  if (!/^\d+\.\d+\.\d+$/.test(semver)) die(`VERSION 文件不是合法版本号：${raw}`);
  return semver;
}

function injectVersion(semver) {
  const file = join(FN, 'manifest');
  const src = readFileSync(file, 'utf8');
  const out = src.replace(/^version\s*=.*$/m, `version               = ${semver}`);
  if (out === src && !src.includes(`= ${semver}`)) die('manifest 里没找到 version 行');
  writeFileSync(file, out);
  ok(`fn/manifest → version = ${semver}`);
}

// ── 2. 图标 ────────────────────────────────────────────────────────────────
function buildIcons() {
  if (SKIP_ICONS) return ok('跳过（--skip-icons）');
  execFileSync(process.execPath, [join(ROOT, 'scripts/gen-brand.mjs')], { cwd: ROOT, stdio: 'pipe' });
  for (const f of ['ICON.PNG', 'ICON_256.PNG', 'app/ui/images/icon_64.png', 'app/ui/images/icon_256.png']) {
    if (!existsSync(join(FN, f))) die(`图标没生成：fn/${f}`);
  }
  ok('图标 64/256 已从矢量母版生成');
}

// ── 3. Node 运行时 ─────────────────────────────────────────────────────────
async function download(url, dest) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
  mkdirSync(dirname(dest), { recursive: true });
  const buf = Buffer.from(await res.arrayBuffer());
  writeFileSync(dest, buf);
  return buf;
}

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');

async function ensureNodeRuntime() {
  const binDir = join(APP, 'bin');
  const target = join(binDir, 'node');
  const cachedTarball = join(CACHE, `node-${NODE_VERSION}-linux-x64.tar.xz`);

  // 已经装好且版本对得上就复用（构建幂等）
  if (existsSync(target)) {
    const v = execFileSync(target, ['-v'], { encoding: 'utf8' }).trim();
    if (v === NODE_VERSION) return ok(`复用已有运行时 ${v}`);
    rmSync(target, { force: true });
  }

  let tarball;
  if (existsSync(cachedTarball)) {
    tarball = readFileSync(cachedTarball);
    ok(`复用缓存 ${cachedTarball}`);
  } else {
    tarball = await download(`${NODE_MIRROR}/node-${NODE_VERSION}-linux-x64.tar.xz`, cachedTarball);
    ok(`已下载 node-${NODE_VERSION}-linux-x64.tar.xz（${(tarball.length / 1048576).toFixed(1)}MB）`);
  }

  // 校验和：参考实现那边裸 curl 没有任何校验，这里补上（拿不到官方 SHASUMS 就只记录）
  try {
    const sums = (await download(`${NODE_MIRROR}/SHASUMS256.txt`, join(CACHE, 'SHASUMS256.txt'))).toString();
    const line = sums.split('\n').find((l) => l.includes(`node-${NODE_VERSION}-linux-x64.tar.xz`));
    if (line) {
      const want = line.trim().split(/\s+/)[0];
      const got = sha256(tarball);
      if (want !== got) die(`Node 运行时校验失败\n        期望 ${want}\n        实际 ${got}`);
      ok(`sha256 校验通过 ${got.slice(0, 16)}…`);
    }
  } catch (e) {
    ok(`跳过 sha256 校验（${e.message}）`);
  }

  // 解包只取 bin/node：不带 lib/，包体积小一半
  const extractDir = join(CACHE, `node-${NODE_VERSION}-linux-x64`);
  if (!existsSync(join(extractDir, 'bin/node'))) {
    rmSync(extractDir, { recursive: true, force: true });
    execFileSync('tar', ['-xJf', cachedTarball, '-C', CACHE, `node-${NODE_VERSION}-linux-x64/bin/node`]);
  }
  mkdirSync(binDir, { recursive: true });
  cpSync(join(extractDir, 'bin/node'), target);
  execFileSync('chmod', ['755', target]);
  const v = execFileSync(target, ['-v'], { encoding: 'utf8' }).trim();
  if (v !== NODE_VERSION) die(`自带运行时版本不对：${v} ≠ ${NODE_VERSION}`);
  ok(`fn/app/bin/node ${v}`);
}

// ── 4. payload ─────────────────────────────────────────────────────────────
function isStale(distDir, inputs) {
  if (!existsSync(join(distDir, 'index.html'))) return true;
  const distMtime = statSync(join(distDir, 'index.html')).mtimeMs;
  for (const input of inputs) {
    if (!existsSync(input)) continue;
    const walk = (p) => {
      const st = statSync(p);
      if (st.isDirectory()) return readdirSync(p).some((f) => walk(join(p, f)));
      return st.mtimeMs > distMtime;
    };
    if (walk(input)) return true;
  }
  return false;
}

function buildWeb() {
  const web = join(ROOT, 'web');
  const inputs = ['src', 'public', 'index.html', 'vite.config.ts', 'package.json', 'package-lock.json']
    .map((f) => join(web, f));
  if (SKIP_WEB) return ok('跳过（--skip-web），直接用现有 web/dist');
  if (!isStale(join(web, 'dist'), inputs)) return ok('web/dist 是最新的，跳过重建');
  console.log('      · 前端产物陈旧或缺失，执行 npm run build …');
  execFileSync('npm', ['run', 'build'], { cwd: web, stdio: 'inherit' });
  ok('web/dist 已重建');
}

function preparePayload() {
  const serverSrc = join(ROOT, 'server');
  const destServer = join(APP, 'server');

  // web
  rmSync(join(APP, 'web'), { recursive: true, force: true });
  mkdirSync(join(APP, 'web'), { recursive: true });
  cpSync(join(ROOT, 'web/dist'), join(APP, 'web/dist'), { recursive: true });
  ok('web/dist → fn/app/web/dist');

  // server：TS 源码原样拷（套件用类型剥离直跑，不需要 tsc）
  rmSync(destServer, { recursive: true, force: true });
  mkdirSync(destServer, { recursive: true });
  for (const item of ['src', 'scripts', 'package.json', 'package-lock.json']) {
    cpSync(join(serverSrc, item), join(destServer, item), { recursive: true });
  }
  // 版本文件：服务端 cwd 是 app/server，读 ../VERSION（/api/health 上报用）
  cpSync(join(ROOT, 'VERSION'), join(APP, 'VERSION'));
  ok('server/{src,scripts,package*.json} + VERSION → fn/app/server');

  // 生产依赖：一律重装，不拷宿主的 node_modules（否则 devDeps 混入、不可复现）
  console.log('      · npm ci --omit=dev …');
  execFileSync('npm', ['ci', '--omit=dev', '--no-audit', '--no-fund'], {
    cwd: destServer,
    stdio: 'inherit',
  });

  // 门禁：node_modules 里不许有 devDeps 痕迹
  const nm = join(destServer, 'node_modules');
  const forbidden = ['typescript', '@types', 'vitest', 'vite'];
  for (const bad of forbidden) {
    if (existsSync(join(nm, bad))) die(`包里混进了 devDependency：node_modules/${bad}`);
  }
  ok('依赖树干净（无 typescript / @types / vite）');

  // 门禁：node_modules/.bin 里的相对软链会被打包器改写成自引用死链
  rmSync(join(nm, '.bin'), { recursive: true, force: true });
  ok('已移除 node_modules/.bin（软链源头）');
}

// ── 5. 权限 + 软链 ─────────────────────────────────────────────────────────
function listSymlinks(dir) {
  const out = [];
  const walk = (p) => {
    for (const entry of readdirSync(p, { withFileTypes: true })) {
      const full = join(p, entry.name);
      if (entry.isSymbolicLink()) { out.push(full); continue; }
      if (entry.isDirectory()) walk(full);
    }
  };
  walk(dir);
  return out;
}

function normalizePerms() {
  const dirs = [];
  const files = [];
  const walk = (p) => {
    for (const entry of readdirSync(p, { withFileTypes: true })) {
      const full = join(p, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) { dirs.push(full); walk(full); } else { files.push(full); }
    }
  };
  walk(FN);
  execFileSync('chmod', ['-R', 'u+rwX,go+rX,go-w', FN]);
  for (const f of readdirSync(join(FN, 'cmd'))) execFileSync('chmod', ['755', join(FN, 'cmd', f)]);
  execFileSync('chmod', ['755', join(APP, 'bin/node')]);
  ok(`权限归一：${dirs.length} 个目录 755 / ${files.length} 个文件 644（cmd/* 与 bin/node 755）`);
}

function assertNoSymlinks() {
  const links = listSymlinks(FN);
  if (links.length > 0) {
    die(`包内有 ${links.length} 个软链，飞牛赋权会 stat 失败（「设置目录权限失败」）：\n        ` +
        links.slice(0, 5).map((l) => l.replace(ROOT + '/', '')).join('\n        '));
  }
  ok('零软链');
}

// ── 6. fnpack ──────────────────────────────────────────────────────────────
async function ensureFnpack() {
  try {
    const p = execFileSync('sh', ['-c', 'command -v fnpack'], { encoding: 'utf8' }).trim();
    if (p) return ok(`使用系统 fnpack：${p}`);
  } catch { /* 继续找 */ }

  const local = join(ROOT, 'node_modules/.bin/fnpack');
  if (existsSync(local)) return ok(`使用仓库内 fnpack：${local}`);

  const dest = join(ROOT, 'node_modules/.bin/fnpack');
  const buf = await download(FNPACK_URL, dest);
  execFileSync('chmod', ['755', dest]);
  ok(`已下载 fnpack（${(buf.length / 1048576).toFixed(1)}MB，sha256 ${sha256(buf).slice(0, 16)}…）`);
  return ok(`→ node_modules/.bin/fnpack`);
}

// ── 7. 出包 ────────────────────────────────────────────────────────────────
function assemble(semver) {
  rmSync(join(FN, 'app.tgz'), { force: true });
  for (const f of readdirSync(FN)) {
    if (f.endsWith('.fpk')) rmSync(join(FN, f), { force: true });
  }
  const fnpack = (() => {
    try { return execFileSync('sh', ['-c', 'command -v fnpack'], { encoding: 'utf8' }).trim(); }
    catch { return join(ROOT, 'node_modules/.bin/fnpack'); }
  })();
  execFileSync(fnpack, ['build', '-d', '.'], { cwd: FN, stdio: 'inherit' });

  const built = readdirSync(FN).find((f) => f.endsWith('.fpk'));
  if (!built) die('fnpack 没有产出 .fpk（看上面的输出）');

  mkdirSync(OUT, { recursive: true });
  const finalName = `suenmoney-v${semver}.fpk`;
  const finalPath = join(OUT, finalName);
  renameSync(join(FN, built), finalPath);
  const buf = readFileSync(finalPath);
  const hash = sha256(buf);
  writeFileSync(`${finalPath}.sha256`, `${hash}  ${finalName}\n`);
  ok(`${finalName}  ${(buf.length / 1048576).toFixed(2)}MB`);
  ok(`sha256 ${hash}`);
}

// ── run ────────────────────────────────────────────────────────────────────
(async () => {
  console.log('SuenMoney · 飞牛 fnOS 套件打包');
  if (!existsSync(FN)) die('fn/ 不存在');

  step(1, '版本注入');
  const semver = normalizeVersion();
  ok(`VERSION → ${semver}`);
  injectVersion(semver);

  step(2, '图标（矢量母版 → 64/256）');
  buildIcons();

  step(3, '自带 Node 运行时');
  await ensureNodeRuntime();

  step(4, '组装 payload');
  buildWeb();
  preparePayload();

  step(5, '权限归一 + 零软链校验');
  normalizePerms();
  assertNoSymlinks();

  step(6, 'fnpack 工具链');
  if (SKIP_FNPACK) {
    ok('跳过（--skip-fnpck）：payload 已就绪，可用 tar 手工校验结构');
    console.log('\n完成（未出包）。下一步去掉 --skip-fnpack 即可出 .fpk。');
    return;
  }
  await ensureFnpack();

  step(7, '出包');
  assemble(semver);

  console.log(`\n✅ 产物：output/suenmoney-v${semver}.fpk（+ .sha256）`);
})().catch((e) => {
  console.error('\n打包失败：', e.message);
  process.exit(1);
});
