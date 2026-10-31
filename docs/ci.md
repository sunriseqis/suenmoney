# CI 与发布构建

**当前策略（2026-10-21 起）：自动构建全部关闭，只保留手动派发。**
推送代码（含推 `main`、推 tag）**不会**启动任何工作流。

**2026-10-31 范围收缩**（用户裁决）：

- **安卓不再有计划** —— 2.0 未重构，后续按情况再说。
- **镜像 CI 暂时不做**。
- **不做 CI 门禁** —— 本地推远端前都跑过 `npm run check`，CI 上再跑一遍没有信息增量。

所以 CI 只保留三条**出包**流水线：`build-fnos` / `build-hw` / `build-ios`。

---

## 为什么关

- 镜像、macOS runner、鸿蒙构建容器都是自己掏的额度。日常提交（尤其文档、设计资产、
  Web 改动）自动触发全链路构建，收益接近零、成本是实打实的。
- 之前为了绕开它，还得在 head commit 里塞 `[skip ci]` —— 那是**症状治理**：
  提交信息被迫承载构建策略，谁忘了写就烧一次。
- 需要产物时（发版、验镜像、出 APK/IPA/HAP）再手动跑，**时间点是可控的**。

## 现在怎么构建

| 工作流 | 产出 | 何时手动跑 |
|---|---|---|
| `build-fnos.yml` | 飞牛 fnOS 套件 `.fpk` | 出飞牛包时 |
| `build-hw.yml` | 未签名 HAP | 出鸿蒙包时 |
| `build-ios.yml` | 未签名 IPA（macOS runner 按 10 倍计费） | 出 iOS 包时 |

## 发行仓库约定（2026-10-31 起）

**本仓库不再发行任何产物** —— 三端（fnos / hw / ios）的包统一发到
**`sunriseqis/suenapp`**，与 suenmusic、suenweb 并列。

三端共用**同一个 Release**：

```
tag       = suenmoney-vX.Y.Z          ← 硬性要求，必须带 suenmoney- 前缀
附件       = suenmoney-vX.Y.Z.fpk     （fnOS）
            SuenMoney-vX.Y.Z-unsigned.hap
            SuenMoney-vX.Y.Z-release.ipa
body      = 三节 SECTION（FNOS / HARMONY / IOS），由
            scripts/prepare-release-notes.mjs 各自替换自己那节
```

三个 workflow 是**独立运行**的，先后发布靠 `<!-- SECTION:X -->` 标记合并：
每次只替换/追加自己那节，不会覆盖别人。同一端重跑也只是替换，不会重复堆叠。

### ⚠ tag 前缀是硬性要求

`softprops/action-gh-release` 遇到**已存在的 tag 会更新那个 Release**
（改 name、覆盖 body、追加附件），不是新建。

2026-10-31 出过一次事故：`build-fnos.yml` 用了裸 `v2.0.0`，直接把 suenmusic
早已发布的同名发行页改成了「SuenMoney v2.0.0」并混入 suenmoney 附件。
已手工恢复（name/body 还原、误加附件删除）。

**所以：任何一端都不许用裸 `vX.Y.Z` 作 tag。** suenweb 用 `suenweb-v2.0.0`，
suenmoney 用 `suenmoney-v2.0.0`。

### 已归档（不在 CI 里）

这三个工作流已移到 **`docs/archive/ci/`**，不再被 GitHub Actions 加载：

| 归档文件 | 作废原因 |
|---|---|
| `docs/archive/ci/build-android.yml` | 安卓端 2.0 未重构，**不再有安卓计划**，后续按情况再说 |
| `docs/archive/ci/build-images.yml` | **镜像 CI 暂时不做** |
| `docs/archive/ci/ci-test.yml` | **不做 CI 门禁** —— 本地推远端前都跑过 `npm run check`，CI 上再跑没有信息增量 |

恢复方式：移回 `.github/workflows/` 即可（`on:` 段都是 `workflow_dispatch`）。
每个归档文件头部都写明了作废原因与归档时间。

三种触发方式，任选：

```bash
# 1) 网页：Actions → 选工作流 → Run workflow（可填 inputs）

# 2) 命令行（需要 gh CLI 且已登录）
gh workflow run build-fnos.yml --ref main

# 3) 带参数
gh workflow run build-fnos.yml --ref main -f custom_version=2.0.0 -f publish_release=true
```

## 要临时恢复自动构建怎么办

每个工作流头部都留了说明，`on:` 段只剩 `workflow_dispatch`。恢复方式二选一：

1. **从 git 历史取回原触发器**：
   ```bash
   git show f37aa8c~1:.github/workflows/build-hw.yml | sed -n '/^on:/,/^permissions:/p'
   ```
   （`f37aa8c~1` = 关闭自动构建前的最后一个提交）
2. **按需手写**，注意一个坑：**任何改动 `.github/workflows/**` 的推送本身**
   也会命中 `paths:`（如果恢复了路径过滤），所以「先加触发器再推」这一下就会触发一次构建。
   介意的话，恢复的那次推送仍然可以用 `[skip ci]` 跳过。

> 建议保持手动：发布是**动作**，不是**副作用**。

## 与本项目其他约定的关系

- `npm run check`（typecheck + 两侧测试 + build）仍是**本地门禁**，CI 关掉不等于可以跳过它；
  `docs/conventions.md` 的目录与产物纪律照旧。
- 容器部署见 `docs/deploy.md`（单容器单端口）；飞牛套件见
  `docs/plan/2026-10-21-飞牛fnOS应用套件工程方案.md`。
