#!/usr/bin/env node
/**
 * 品牌资产生成 —— 一个矢量母版，出全端图标。
 *
 * 母版在 `docs/design/brand/`（手写矢量，零位图嵌入）：
 *   mark.svg         1024 方形，11 亮格 + 9 空格（≥32px 用）
 *   mark-small.svg   <32px：只留 11 个笔画（空格在 16px 等于不存在）
 *   mark-mono.svg    单色剪影（monochrome / 分层前景）
 *
 * 注意：**没有「header 变体」**。那条横条是计算器的显示屏 —— 它是标记的语义主体，
 * 不是「大尺寸才配的装饰」。曾把它当成可选项删掉，Logo 立刻只剩一片点阵。
 *
 * 尺寸阈值写在 `docs/design/brand/README.md` 与 `tokens.json` 的 brand 段里 ——
 * 「16px 用哪个母版」这种事不许各处各判一次。
 *
 * 用法：
 *   node scripts/gen-brand.mjs            # 生成全部产物
 *   node scripts/gen-brand.mjs --check    # 只列会写哪些文件，不落盘
 *
 * 为什么用 sharp 而不是 Python + Pillow：参考实现那边就是因为本机没有 PIL，
 * 打包流水线的图标步骤直接把构建打挂了。sharp 是纯 npm 依赖，`npm ci` 就有。
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import sharp from 'sharp';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const BRAND = join(ROOT, 'docs/design/brand');
const DIST = join(BRAND, 'dist');
const CHECK = process.argv.includes('--check');

/** 尺寸 → 用哪个母版。阈值来自 README，不许在这里再发明一套。 */
const SMALL_MAX = 31; // <32px 用简化版（键位改圆点）

const svg = (name) => readFileSync(join(BRAND, name), 'utf8');

/** 母版缓存：同一份 SVG 反复用，不要每次都读盘 */
const SRC = {
  master: svg('mark.svg'),
  small: svg('mark-small.svg'),
  mono: svg('mark-mono.svg'),
};

function pick(size) {
  return size <= SMALL_MAX ? SRC.small : SRC.master;
}

/**
 * 渲染一张 PNG。
 * `density` 交给 sharp 的 SVG 渲染器决定内部分辨率 —— 直接把 1024 母版缩到 16px
 * 会丢笔画，所以按目标尺寸放大密度再缩，等于超采样。
 */
async function png(source, size, out) {
  const targets = [];
  if (CHECK) {
    targets.push({ out, size });
    return targets;
  }
  mkdirSync(dirname(out), { recursive: true });
  await sharp(Buffer.from(source), { density: Math.max(72, Math.ceil((size / 1024) * 72 * 8)) })
    .resize(size, size, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png({ compressionLevel: 9 })
    .toFile(out);
  return targets;
}

const written = [];
async function emit(source, size, relPath) {
  const out = join(ROOT, relPath);
  await png(source, size, out);
  written.push(`${relPath}  ${size}×${size}`);
}

async function main() {
  // ── 1) 母版渲染全集（文档、外部使用、其它端取用） ──
  for (const size of [16, 24, 32, 48, 64, 96, 128, 180, 192, 256, 512, 1024]) {
    await emit(pick(size), size, `docs/design/brand/dist/mark-${size}.png`);
  }
  for (const size of [64, 256, 512, 1024]) {
    await emit(SRC.mono, size, `docs/design/brand/dist/mark-mono-${size}.png`);
  }

  // ── 2) Web / PWA ──
  await emit(pick(32), 32, 'web/public/favicon.png');        // index.html 只引这一个
  await emit(SRC.master, 180, 'web/public/icon.png');        // apple-touch-icon
  await emit(SRC.master, 512, 'web/public/icon-512.png');
  await emit(SRC.master, 512, 'web/public/logo.png');
  await emit(SRC.master, 512, 'web/public/apple-touch-icon.png');

  // 真矢量 logo：替掉过去那个「里面是一张 base64 PNG」的 280KB 假 SVG
  if (!CHECK) writeFileSync(join(ROOT, 'web/public/logo.svg'), SRC.master);
  written.push('web/public/logo.svg  (真矢量，' + (SRC.master.length / 1024).toFixed(1) + 'KB)');

  // ── 3) 飞牛 fnOS 套件（计划二直接消费） ──
  if (existsSync(join(ROOT, 'fn/manifest'))) {
    await emit(SRC.master, 64, 'fn/ICON.PNG');
    await emit(SRC.master, 256, 'fn/ICON_256.PNG');
    await emit(SRC.master, 64, 'fn/app/ui/images/icon_64.png');
    await emit(SRC.master, 256, 'fn/app/ui/images/icon_256.png');
  } else {
    written.push('（跳过 fn/ —— 工程还没建）');
  }

  // ── 4) iOS / 鸿蒙：计划三会重写工程，这里只出「可用的源图」，不动工程 ──
  await emit(SRC.master, 1024, 'docs/design/brand/dist/appicon-ios-1024.png');
  await emit(SRC.mono, 1024, 'docs/design/brand/dist/appicon-layered-foreground-1024.png');

  console.log(CHECK ? '将写入以下文件：' : '已生成：');
  for (const w of written) console.log('  ' + w);
  console.log(`\n共 ${written.length} 项。尺寸阈值：<${SMALL_MAX + 1}px 用简化版（键位改圆点）。`);
}

main().catch((e) => {
  console.error('生成失败：', e.message);
  process.exit(1);
});
