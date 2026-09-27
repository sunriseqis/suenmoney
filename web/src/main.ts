import { createApp } from 'vue';
import { createPinia } from 'pinia';

/**
 * 字体必须在**这里**真正引入。
 *
 * 踩过的坑：`styles/tokens.css` 的 `--font-sans` 里早就写着
 * `'Outfit', 'MiSans', …`，但那只是「期望的回落顺序」——**没有 @font-face
 * 就等于没装**。结果是数字走 Outfit、中文静默掉到系统苹方，两套字形气质打架，
 * 而整个 Flat Design 的分层高度依赖排版（它零阴影、零边框、零渐变），
 * 字体没到位时界面看起来就像「没写完的后台」。
 *
 *   Outfit Variable —— 数字与拉丁字母，可变字重 100–900
 *   MiSans VF       —— 中文，可变字重 150–700
 *
 * 两者都从 npm 包**本地**引入，不走 CDN：移动端是 Capacitor 打包，
 * 必须离线可用，外链字体在断网时会直接退化成系统字体。
 *
 * MiSans 被切成了 56 个 unicode-range 分片，浏览器只会下载当前页面实际用到的
 * 那几片（通常 1–3 片），所以别被 dist 里的总体积吓到。
 */
import '@fontsource-variable/outfit';
import 'misans/lib/Normal/MiSansVF.min.css';

import './styles/app.css';
import App from './App.vue';
import { router } from './router';

const app = createApp(App);

/**
 * 顺序不能反：pinia 必须先于 router 安装。
 * 路由守卫里会 `useAuthStore()`，而 Pinia 只有在被 `app.use()` 之后才会
 * 设置「当前活跃实例」——反过来的话守卫会在第一次导航时抛出
 * 「getActivePinia was called with no active Pinia」。
 */
app.use(createPinia());
app.use(router);

app.mount('#app');
