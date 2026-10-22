import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath, URL } from 'node:url';

import vue from '@vitejs/plugin-vue';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';

/**
 * 反代目标与端口允许用环境变量覆盖。
 * 默认值与本地开发一致，日常 `npm run dev` 无需配置。
 */
const apiTarget = process.env['SUENMONEY_API'] ?? 'http://127.0.0.1:3310';
const devPort = Number(process.env['SUENMONEY_WEB_PORT'] ?? 5410);

/**
 * 构建标记（版本 · 短 sha · 构建时间）。
 * 换肤/重构期间反复出现「你看到的和我改的不是同一版」，标记渲染在界面角落，
 * 一眼可辨：浏览器缓存、原生壳内置旧 dist、忘记重启服务，全都暴露。
 */
function buildStamp(): string {
  let sha = 'nogit';
  try {
    sha = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {
    /* 非 git 环境忽略 */
  }
  let ver = '0.0.0';
  try {
    ver = readFileSync(fileURLToPath(new URL('../VERSION', import.meta.url)), 'utf8').trim();
  } catch {
    /* 无 VERSION 文件则留默认 */
  }
  const at = new Date().toISOString().slice(5, 16).replace('T', ' ');
  return `v${ver} · ${sha} · ${at}`;
}

export default defineConfig({
  define: {
    __BUILD_STAMP__: JSON.stringify(buildStamp()),
  },

  plugins: [vue(), tailwindcss()],

  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },

  server: {
    host: '0.0.0.0',
    port: devPort,
    proxy: {
      '/api': { target: apiTarget, changeOrigin: true },
    },
  },

  /** 预览构建产物（重构期间给用户看壳与页面，不占用线上 5310） */
  preview: {
    host: '0.0.0.0',
    port: devPort,
    proxy: {
      '/api': { target: apiTarget, changeOrigin: true },
    },
  },

  build: {
    outDir: 'dist',
    sourcemap: false,
    target: 'es2022',
  },
});
