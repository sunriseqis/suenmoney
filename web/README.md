# web-v2 —— Web 端重构工程

> 方案：`docs/plan/2026-10-22-web端从零重构方案.md`
> 旧工程备份：`archive/web-2026-10-22/` + git tag `web-legacy-2026-10-22`

## 为什么另起一个目录

换肤在旧工程上补了十余轮：旧全局样式（`button:active`、`svg{stroke}`、`.card` 自定义版）
与原型设计系统互相覆盖，每修一处冒三处。所以视觉层（views/components/styles）**全部重写**，
逻辑层（api/stores/platform/utils）**原样搬**——那部分有 156 项测试兜着，重写等于重新赌一次。

## 硬规则

1. 视觉只来自 `styles/proto/*.css`（原型 1:1，**逐字未改**）+ 组件自身 `<style>`。
2. **禁止**元素级全局外观规则（`button {}` / `svg {}` / `h1 {}`）。这是旧工程打转的根因。
3. **禁止**写旧类名（`bg-canvas` / `text-ink` / `rounded-md` / `btn-v4`）与兼容层。
4. 功能守则以 `docs/feature-inventory.md` 的 138 项为准，每阶段逐条打勾。

## 开发

```bash
npm run install:web2          # 装依赖
npm run dev:web2              # 5410，/api 反代到 3310
SUENMONEY_API=http://127.0.0.1:5310 npm run preview:web2   # 预览构建产物，反代到线上数据
npm run build:web2            # 类型检查 + 构建
```

## 阶段

P0 骨架 ✅ · P1 设计系统与外壳 · P2 认证 · P3 流水 · P4 记账抽屉 ·
P5 概况 · P6 报表 · P7 设置 · P8 离线同步 · P9 切换到 `web/`
