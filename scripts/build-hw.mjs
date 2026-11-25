#!/usr/bin/env node
/**
 * 鸿蒙 NEXT HAP 构建脚本：Web 编译 → 同步至 rawfile → hvigorw 构建未签名 HAP。
 *
 * 用法：
 *   node scripts/build-hw.mjs --sync-only      # 仅执行 web build 并同步到 hw rawfile
 *   node scripts/build-hw.mjs                  # 编译未签名 HAP，产出 app/suenmoney-<版本>.hap
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync } from 'node:fs';
import { copyFile, mkdir, readFile, writeFile, stat } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
/**
 * ⚠ 构建的是 **hw-native/**（2.0 的 ArkTS 原生端，38 个 .ets）。
 *
 * `hw/` 是 Capacitor 时代的 WKWebView 壳（只有 2 个 .ets + 一堆 web 资源），
 * 与 `android/` 一样属于冻结资产。曾经这里写成 `hw`，导致 CI 产出的 HAP
 * 一直是 WebView 壳 —— 和 iOS 那边同一次事故、同一个原因。
 */
const HW_DIR = join(ROOT, 'hw-native');
const OUTPUT_DIR = join(ROOT, 'app');
const SYNC_ONLY = process.argv.includes('--sync-only');

function log(msg) {
  console.log(`[build-hw] ${msg}`);
}

function fail(message) {
  console.error(`\n✖ [build-hw] ${message}`);
  process.exit(1);
}

function run(command, args, options = {}) {
  console.log(`\n$ ${command} ${args.join(' ')}`);
  execFileSync(command, args, { stdio: 'inherit', ...options });
}

async function readVersionName() {
  const raw = (await readFile(join(ROOT, 'VERSION'), 'utf8')).trim();
  if (!/^\d+(?:\.\d+)*$/.test(raw)) {
    fail(`VERSION 文件内容不是合法版本号：${JSON.stringify(raw)}`);
  }
  return raw;
}

function readVersionCode(versionName) {
  // versionCode 单一公式：major*1000000 + minor*10000 + patch*100（2.1.2 → 2010200）。
  // 与 .github/workflows/build-hw.yml / build-ios.yml 及 app.json5/pbxproj 提交值一致，
  // 不要再改回 10000+git 提交数（提交数与商店版本号量级不同，会导致拒绝升级）。
  const [major = 0, minor = 0, patch = 0] = versionName.split('.').map(Number);
  const code = major * 1000000 + minor * 10000 + patch * 100;
  return { code, source: `${versionName} → ${code}` };
}

async function syncWeb() {
  // 原生工程自己就是 UI，不消费 web/dist（`hw/` 旧壳才需要）
  log('1/3 原生工程无需同步 Web 资源（ArkTS 自带页面）');
}

async function injectVersion(versionName, versionCode) {
  log(`2/3 注入版本号至鸿蒙工程: ${versionName} (${versionCode})...`);
  const appJsonPath = join(HW_DIR, 'AppScope/app.json5');
  if (existsSync(appJsonPath)) {
    let content = await readFile(appJsonPath, 'utf8');
    content = content.replace(/"versionName":\s*"[^"]*"/, `"versionName": "${versionName}"`);
    content = content.replace(/"versionCode":\s*\d+/, `"versionCode": ${versionCode}`);
    await writeFile(appJsonPath, content, 'utf8');
  }
}

async function assembleHap(versionName, versionCode) {
  log('3/3 执行 Hvigor 编译未签名 HAP...');
  const hvigorw = join(HW_DIR, 'hvigorw');

  const args = [
    'assembleHap',
    '--mode', 'module',
    '-p', 'module=entry@default',
    '-p', 'product=default',
    '-p', `versionName=${versionName}`,
    '-p', `versionCode=${versionCode}`,
    '--no-daemon',
    '--accept-license',
  ];

  run(hvigorw, args, { cwd: HW_DIR });

  // 检索产物目录
  const candidateDirs = [
    join(HW_DIR, 'entry/build/default/outputs/default'),
    join(HW_DIR, 'build/outputs/default'),
  ];

  let foundHap = null;
  for (const dir of candidateDirs) {
    if (existsSync(dir)) {
      const files = readdirSync(dir).filter((f) => f.endsWith('.hap'));
      if (files.length > 0) {
        foundHap = join(dir, files[0]);
        break;
      }
    }
  }

  if (!foundHap) {
    fail('Hvigor 编译完成，但未在 outputs 目录找到 .hap 产物！');
  }

  await mkdir(OUTPUT_DIR, { recursive: true });
  const targetHap = join(OUTPUT_DIR, `suenmoney-${versionName}.hap`);

  await copyFile(foundHap, targetHap);

  const { size } = await stat(targetHap);
  log(`✔ HAP 打包成功！产物：${targetHap}`);
  log(`  大小 ${(size / 1024 / 1024).toFixed(2)} MB（未签名，供测试与自签使用）`);
}

const versionName = process.env.CUSTOM_VERSION || (await readVersionName());
const { code: versionCode, source } = readVersionCode(versionName);
log(`当前目标版本: v${versionName} / versionCode: ${versionCode} (${source})`);

await syncWeb();

if (SYNC_ONLY) {
  log('✔ 已完成静态资源同步（--sync-only）。');
} else {
  await injectVersion(versionName, versionCode);
  await assembleHap(versionName, versionCode);
}
