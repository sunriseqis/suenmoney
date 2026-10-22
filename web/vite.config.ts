import { execSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import tailwindcss from '@tailwindcss/vite';

/**
 * 反代目标与端口允许用环境变量覆盖。
 *
 * 默认值就是本地开发的那一套，所以日常 `npm run dev` 无需任何配置。
 * 但覆盖能力是必要的：想在**不碰开发库**的前提下预览另一套数据
 * （演示数据、迁移前的旧库、排查线上问题时的快照），只需要
 * `SUENMONEY_API=http://127.0.0.1:3400 SUENMONEY_WEB_PORT=5410 npm run dev`，
 * 不必去改这个文件再改回来。
 */
const apiTarget = process.env['SUENMONEY_API'] ?? 'http://127.0.0.1:3310';
const devPort = Number(process.env['SUENMONEY_WEB_PORT'] ?? 5310);

/**
 * 构建标记（版本 · 短 sha · 构建时间）。
 *
 * 为什么需要：换肤期间反复出现「我这边看到的是新版，你那边是旧版」——
 * 浏览器缓存、原生壳内置的旧 dist、忘记重启服务，表现都一样。
 * 把标记渲染在界面上，一眼就能确认看的是哪一版，省掉一轮互相猜。
 */
function buildStamp(): string {
  let sha = 'nogit';
  try {
    sha = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {
    /* 非 git 环境（例如打包机）忽略 */
  }
  let ver = '0.0.0';
  try {
    ver = readFileSync(fileURLToPath(new URL('../VERSION', import.meta.url)), 'utf8').trim();
  } catch {
    /* 没有 VERSION 文件就留默认 */
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
    /**
     * 显式绑定 127.0.0.1，而不是依赖 Vite 默认的 `localhost`。
     * 在 macOS 上 `localhost` 可能只解析到 ::1，于是 `curl 127.0.0.1:5310`
     * 会连不上 —— 本地调试与自动化测试都会因此得出「服务没起来」的错误结论。
     */
    host: '127.0.0.1',
    port: devPort,
    // 开发期走后端反代而不是靠 CORS：同源请求让 cookie / 相对路径 / 生产环境
    // 行为完全一致，避免「开发能跑、部署就 404」这类只在最后才暴露的差异。
    proxy: {
      '/api': {
        target: apiTarget,
        changeOrigin: true,
      },
    },
  },

  build: {
    // 家庭自用，产物给 nginx 托管；拆 chunk 只为让「改一行代码」不必让用户重下整包
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['vue', 'vue-router', 'pinia'],
        },
      },
    },
  },
});
