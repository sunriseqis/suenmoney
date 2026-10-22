import { createPinia } from 'pinia';
import { createApp } from 'vue';

/**
 * 字体从 npm 包**本地**引入，不走 CDN —— 移动端是 Capacitor 打包，必须离线可用。
 * 中文用 MiSans（56 个 unicode-range 分片，浏览器只下当前页用到的几片）。
 * 拉丁与数字按原型两套语言各配一套：candy 用 Outfit/Jakarta，cyber 用 Orbitron/JetBrains。
 */
import '@fontsource-variable/jetbrains-mono';
import '@fontsource-variable/outfit';
import '@fontsource-variable/plus-jakarta-sans';
import '@fontsource/orbitron/700.css';
import '@fontsource/orbitron/800.css';
import 'misans/lib/Normal/MiSansVF.min.css';

import './../styles/index.css';
import App from './App.vue';
import { router } from './router';

const app = createApp(App);

/** 顺序不能反：pinia 必须先于 router —— 路由守卫里会 useAuthStore() */
app.use(createPinia());
app.use(router);
app.mount('#app');
