# ios/ —— iOS 原生工程

**本目录目前是预留位置，尚无内容。**

## 这里放什么

Capacitor 生成并维护的 iOS 原生工程（Xcode 项目）。构建流程：

```
web/（Vue 源码） → vite build → web/dist/ → cap sync ios → 本目录 → Xcode → IPA
```

## 约束

- **不放任何手写的业务代码。** 界面与逻辑全部来自 `web/`，这里只有原生壳。
- 需要改原生行为时改 `web/capacitor.config.ts` 或写原生插件，
  **不要直接改被 `cap sync` 管理的文件**。
- 原生产物（`App/build/`、`Pods/`、`*.ipa`、`*.xcarchive`）已在根 `.gitignore` 中忽略。
- iOS 排在安卓之后，具体顺序与理由见 `docs/plan.md`。

## 与 `android/` 的关系

两者是同一条流水线的两个出口，共用 `web/` 的同一份源码。
两端的行为差异（安全区、状态栏、返回手势、原生能力缺失）应当收敛在
**`web/` 里的适配层**，而不是各写一套界面 —— 否则「移动端复用同一份前端」
这个前提就失效了。
