# CI 与发布构建

**当前策略：默认手动派发；唯一的例外是镜像流水线由 tag 触发。**

推送 `main` **不会**启动任何工作流；只有推 `suenmoney-v*` tag 会触发镜像构建。

**2026-10-31 范围收缩**（用户裁决）：

- **安卓不再有计划** —— 2.0 未重构，后续按情况再说。
- ~~**镜像 CI 暂时不做**~~ → **2026-11-20 恢复上线**（见下节「镜像流水线」）。
- **不做 CI 门禁** —— 本地推远端前都跑过 `npm run check`，CI 上再跑一遍没有信息增量。

所以 CI 现在是四条**出包**流水线：`build-fnos` / `build-hw` / `build-ios` / `build-image`。

---

## 镜像流水线（2026-11-20 上线）

**为什么现在要做**：`docker-compose.yml` 与 `docs/deploy.md` 从 2.0 起就引用
`ghcr.io/sunriseqis/suenmoney:latest`，但**这个镜像从来没被发布过**
（2026-11-20 核查：匿名拉取返回 403；旧的 `suenmoney-server` / `suenmoney-web`
存在且停在 1.1.6）。也就是说照文档部署会直接 `manifest unknown` ——
这条流水线首先是把断掉的部署路径接回来。

**触发**：只认 tag，且 tag 必须打在**本仓库**。

```bash
# 发版后把同名 tag 也推到 suenmoney 仓库（三端出包流水线建的 tag 在 suenapp，不通用）
git tag suenmoney-v2.1.1 && git push origin suenmoney-v2.1.1
```

> ⚠ 这是**最容易忘的一步**：`build-fnos` / `build-hw` / `build-ios` 的
> `softprops/action-gh-release` 是在**发行仓库 suenapp** 上建 tag，
> 本仓库的 tag 列表里没有它们。本仓库不打 tag = 镜像永远不构建，而且不报错
> （只是「什么都没发生」）。
>
> 失败重跑用 GitHub 页面上的 **Re-run jobs**，不需要 `workflow_dispatch`。

**产物**：`ghcr.io/sunriseqis/suenmoney`，多架构 `linux/amd64` + `linux/arm64`，四个 tag：

| tag | 用途 |
|---|---|
| `latest` | `docker-compose.yml` 引用它，**必须无条件推**（tag 事件下 `is_default_branch` 为 false，旧工作流那套写法会让 latest 永远不更新） |
| `X.Y.Z` | 与发行版本一一对应，回滚用 |
| `X.Y` | 跟随小版本 |
| `sha-xxxxxxx` | 精确到提交 |

推完流水线会 `docker buildx imagetools inspect` 回读 manifest，**断言 amd64 与 arm64
都在**才判成功 —— 多架构「推成功」只代表 blob 上去了，少一个架构要等用户
`docker pull` 才炸。

> ⚠ **首次推送后确认包可见性**。GHCR 的包可见性**独立于仓库**：由 `GITHUB_TOKEN`
> 首次创建时会继承仓库可见性（公开仓库 → 公开包），但若同名包曾以私有方式建过，
> 会一直保持私有 —— 表现是流水线全绿、而部署机 `docker compose pull` 报
> `unauthorized`。核对办法：不登录直接
> `curl -s "https://ghcr.io/token?scope=repository:sunriseqis/suenmoney:pull&service=ghcr.io"`
> 返回 200 即公开（403 为私有或不存在）。需要改就去
> `Packages → suenmoney → Package settings → Change visibility`。

**与 suenapp 的关系**：镜像本体在 GHCR，发行页只写一节 `<!-- SECTION:DOCKER -->`
（地址、拉取命令、compose 用法）。**不**把镜像导出成 tar.gz 附到 Release ——
几百 MB 的附件换不来什么，`docker pull` 本来就能离线缓存。

---

## 为什么默认仍然手动

- 镜像、macOS runner、鸿蒙构建容器都是自己掏的额度。日常提交（尤其文档、设计资产、
  Web 改动）自动触发全链路构建，收益接近零、成本是实打实的。
- 之前为了绕开它，还得在 head commit 里塞 `[skip ci]` —— 那是**症状治理**：
  提交信息被迫承载构建策略，谁忘了写就烧一次。
- 需要产物时（发版、验镜像、出 APK/IPA/HAP）再手动跑，**时间点是可控的**。
- 镜像那条之所以按 tag 触发：tag 本身就是「这是一个版本」的信号，
  和「日常提交」天然可区分，不需要额外判断。

## 现在怎么构建

| 工作流 | 产出 | 触发 |
|---|---|---|
| `build-fnos.yml` | 飞牛 fnOS 套件 `.fpk` | 手动派发 |
| `build-hw.yml` | 未签名 HAP | 手动派发 |
| `build-ios.yml` | 未签名 IPA（macOS runner 按 10 倍计费） | 手动派发 |
| `build-image.yml` | 多架构容器镜像（GHCR） | **推 `suenmoney-v*` tag** |

## 发行仓库约定（2026-10-31 起）

**本仓库不再发行任何产物** —— 四端（fnos / hw / ios / docker）的交付统一发到
**`sunriseqis/suenapp`**，与 suenmusic、suenweb 并列。

**产物命名统一为 `suenmoney-<版本>.<ext>`**（用户裁决）：全小写、版本号不带 `v`、
不带 `-unsigned` / `-release` 后缀；三端扩展名分别是 `.fpk` / `.hap` / `.ipa`。

四端共用**同一个 Release**：

```
tag       = suenmoney-vX.Y.Z          ← 硬性要求，必须带 suenmoney- 前缀
附件       = suenmoney-X.Y.Z.fpk        （fnOS）
            suenmoney-X.Y.Z.hap        （鸿蒙，未签名）
            suenmoney-X.Y.Z.ipa        （iOS，未签名）
            —— 镜像**没有附件**，本体在 ghcr.io/sunriseqis/suenmoney
body      = 四节 SECTION（FNOS / HARMONY / IOS / DOCKER），由
            scripts/prepare-release-notes.mjs 各自替换自己那节
```

四个 workflow 是**独立运行**的，先后发布靠 `<!-- SECTION:X -->` 标记合并：
每次只替换/追加自己那节，不会覆盖别人。同一端重跑也只是替换，不会重复堆叠。
顺序无关 —— 镜像先跑（发行页只有 DOCKER 一节）也成立，后面三端各自追加。

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
| `docs/archive/ci/build-images.yml` | **已被 `.github/workflows/build-image.yml` 取代**（2026-11-20 镜像流水线上线）。旧文件的 `type=semver` 对 `suenmoney-vX.Y.Z` 解析不出、`latest` 在 tag 事件下不更新、且没有发布到 suenapp 的步骤 —— 不要原样搬回来 |
| `docs/archive/ci/ci-test.yml` | **不做 CI 门禁** —— 本地推远端前都跑过 `npm run check`，CI 上再跑没有信息增量 |

恢复方式：移回 `.github/workflows/` 即可（`on:` 段都是 `workflow_dispatch`）。
每个归档文件头部都写明了作废原因与归档时间。

三条手动流水线的触发方式，任选：

```bash
# 1) 网页：Actions → 选工作流 → Run workflow（可填 inputs）

# 2) 命令行（需要 gh CLI 且已登录）
gh workflow run build-fnos.yml --ref main

# 3) 带参数
gh workflow run build-fnos.yml --ref main -f custom_version=2.0.0 -f publish_release=true
```

镜像那条不在这里 —— 它只认 tag：

```bash
# 发版后补打本仓库 tag，才会触发镜像构建（详见上文「镜像流水线」）
git tag suenmoney-v2.1.1 && git push origin suenmoney-v2.1.1

# 或事后补一个旧版本的镜像
git tag suenmoney-v2.1.0 <那个版本的 commit> && git push origin suenmoney-v2.1.0
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
