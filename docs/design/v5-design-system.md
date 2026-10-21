# SuenMoney v5 设计系统（定稿 · 2026-10-21）

> **参考实现**：`docs/design/v5-design-preview.html`（用户已确认 —— 前端按它改造）。
> **令牌真相源**：`docs/design/tokens.json`（v5.0.0）→ `npm run tokens` 生成 CSS/Swift/ArkTS。
> **LOGO 母版**：`docs/design/brand/mark-dark.svg` / `mark-light.svg` → `npm run icons`。
> **状态**：设计语言全部接完（令牌/LOGO/字体/全局层/组件类/页面元素）。

---

## 两套主题 = 两种设计语言

不写 `data-theme` = **深色 Cyberpunk**；`data-theme="light"` = **浅色 Playful Geometric**。
不是同一配色的明度变体 —— 颜色、字体、圆角、阴影、动效曲线**全不同**。

### 浅色 · Playful Geometric

```
底 #FFFDF5 纸白   卡 #FFFFFF   正文 #1E293B   次文 #64748B
糖果四色：紫 #8B5CF6（主）· 粉 #F472B6 · 黄 #FBBF24 · 绿 #34D399
字体：标题 Outfit 800 / 正文 Plus Jakarta Sans / 中文 MiSans
形状：卡片 16px 圆角 + **2px 深色粗边框**；按钮胶囊 999px
阴影：硬阴影 4px 4px 0px #1E293B（hover 6px / active 2px，**带位移**）
卡片 hover：rotate(-1deg) scale(1.02) 贴纸摇摆
图标：2.5 chunky + round caps，装在彩色圆里（圆带 3px 硬阴影）
动效：cubic-bezier(0.34,1.56,0.64,1) 弹性回弹
装饰：点阵/confetti/squiggle/Marquee（预览页有）
```

### 深色 · Cyberpunk

```
底 #050509 void 黑   卡 #1E1D2E   屏/高层 #2A2A44   正文 #e0e0e0   次文 #8b8ba7
霓虹三色：绿 #00ff88（主）· 青 #00d4ff · 品红 #ff00ff；点缀黄 #FBBF24
字体：标题 Orbitron 800 全大写宽字距 / 正文 JetBrains Mono / 中文 MiSans
形状：**圆角归零 + clip-path 切角**（chamfer / chamfer-sm）；1px 描边
阴影：霓虹辉光 0 0 5px + 0 0 20px（叠加），无位移
卡片 hover：border-color 变霓虹 + 辉光 + translateY(-1px)
图标：1.5 细线 + drop-shadow 辉光，装在切角方框里
纹理：全页扫描线（repeating-linear-gradient 2px/4px）+ 50px 电路网格
动效：cubic-bezier(0.4,0,0.2,1) 机械；h1 cyber-glitch 动画
金额：霓虹粉 #FF6BB5 + 16px 辉光（**发光的数字**）
```

## 组件类（base.css @layer components）

| 类 | 深色 | 浅色 |
|---|---|---|
| `.btn-v4` | 切角 + 霓虹描边，hover 填充辉光 | 胶囊 + 硬阴影位移（4→6→2） |
| `.panel-v4` | 切角 + 1px 边 + 辉光 | 16px 圆角 + 2px 深边 + 硬阴影 |
| `.input-v4` | 切角 + focus 霓虹辉光 | 8px 圆角 + focus 4px 硬阴影染色 |
| `.row-v5` | 切角行 + hover 辉光右移 | 5px 硬阴影 + hover 位移换粉影 |
| `.ic-v5` | 切角方框 + 1.5 图标 + 辉光 | 彩色圆 + 3px 硬阴影 + 2.5 图标 |
| `.pill-tabs` | 等宽大写 + 切角 + 选中辉光 | 胶囊 + 选中硬阴影位移 |
| `.terminal-head` | 交通灯三点卡头 | 不显示 |
| `.amount-hero` / `.amount-v3 .int` | 霓虹粉发光 | 深 slate |

## LOGO（mark-dark / mark-light）

一台计算器，键位亮出 S：

```
机身 48,48 928×928 r220 · 屏幕 212,104 600×184 r48
键盘 4×5 起(212,324) 格 135×106 r34 间距 18；亮键 11（上横3/左竖1/中横3/右竖1/下横3右移）
屏幕：LED 点阵「88.88」（5×7 字模、亮点 16×16、点距 3、总宽 408、屏内居中余 88）
```

深色明度五档（不再糊）：底 `#050509`(5) → 机身 `#1E1D2E`(30) → 屏 `#2A2A44`(44) → 暗键 `#16162A`(23) → 键描边 `#3A3A5C`(60)，加霓虹绿机身描边 + 青色屏描边；20 键全部描边（亮键=自身亮版，暗键=灰紫）。
浅色：纸白底 + 白机身深描边 + 硬阴影 + 深屏黄描边 + LED 糖果四色。

## 前端接入清单（2026-10-21 完成）

| 项 | 落点 |
|---|---|
| 令牌 | `tokens.json` v5.0.0 → `gen-tokens.mjs` → `tokens.generated.css`（`npm run tokens:check` 在 check 第一道） |
| LOGO | `mark-dark.svg` / `mark-light.svg` → `gen-brand.mjs` 34 项 → `web/public/logo.svg`（深）/ `mark-light.svg`（浅）；`BrandMark.vue` 按主题切换 |
| 字体 | main.ts 引入 Outfit / Orbitron / Plus Jakarta Sans / JetBrains Mono；`--font-head` 按主题 |
| 全局层 | base.css：标题字体/卡片语言/图标描边/扫描线/glitch 动画 |
| 组件类 | btn-v4 / panel-v4 / input-v4 / row-v5 / ic-v5 / row-v5-td / pill-tabs / terminal-head |
| 页面 | 流水顶卡 + 概况 Hero（terminal-head + 发光大金额）；分段控件；数字键盘；登录页输入框与按钮；流水行徽位 ic-v5 |

## 已知未做（下一轮）

- 构成卡（CompositionCard）套 row-v5/贴纸语言；计划卡 ★ 徽章 + scale(1.06)
- 装饰元素（点阵/confetti/squiggle/Marquee）只在预览页，未进应用
- 浅色主题的图标容器彩色圆按分类色轮转（当前统一 primary）
- 报表页环图配色与账本色 16 槽的对齐
