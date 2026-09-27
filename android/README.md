# android/ —— 安卓原生工程

**本目录目前是预留位置，尚无内容。**

## 这里放什么

Capacitor 生成并维护的安卓原生工程（Gradle 项目）。构建流程：

```
web/（Vue 源码） → vite build → web/dist/ → cap sync android → 本目录 → Gradle → APK/AAB
```

## 约束

- **不放任何手写的业务代码。** 界面与逻辑全部来自 `web/`，这里只有原生壳。
- 需要改原生行为（权限、原生插件、启动图、签名、应用名）时，改
  `web/capacitor.config.ts` 或写原生插件，**不要直接改业务相关代码** ——
  `cap sync` 会覆盖被它管理的文件。
- 原生产物（`app/build/`、`*.apk`、`*.aab`、`.gradle/`）已在根 `.gitignore` 中忽略。

## 为什么本目录在仓库顶层而不是 `web/android/`

四个交付物（server / web / android / ios）必须彼此独立、边界清晰，
这样「改了哪一层」在目录结构上一眼可见，也不会出现「前端仓库里藏着一个
完整的安卓工程」这种混淆。具体接入方式见 `docs/plan.md` 的移动端阶段说明。
