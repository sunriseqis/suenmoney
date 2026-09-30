import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.suenmoney.app',
  appName: 'SuenMoney',
  webDir: 'dist',
  android: {
    path: '../android',
    allowMixedContent: true,
  },
  ios: {
    path: '../ios',
  },
  server: {
    // 页面源使用 http 模式以保证局域网/自建部署时明文 HTTP 接口 fetch 不被 WebView 拦截
    androidScheme: 'http',
  },
};

export default config;
