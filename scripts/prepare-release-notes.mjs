#!/usr/bin/env node
/**
 * 为发行仓库（sunriseqis/suenapp）合并各平台的发布说明。
 *
 * 背景：四个平台的构建是**四个独立 workflow**（build-fnos / build-hw / build-ios /
 * build-image），但对外应该表现为**同一个 Release**（tag `suenmoney-vX.Y.Z`）：
 * 附件里放 `.fpk` / `.hap` / `.ipa`，容器镜像本体在 GHCR，发行页只留一节说明。
 *
 * 难点：后跑的 workflow 不能覆盖先跑的。所以用带标记的 SECTION 分区：
 * 每次只替换/追加「自己那一节」，其余原样保留。
 *
 * 用法：
 *   node scripts/prepare-release-notes.mjs --platform <fnos|harmony|ios|docker> \
 *     --tag suenmoney-v2.0.0 --output /tmp/release_body.md [--repo sunriseqis/suenapp]
 *
 * 行为：
 *   1. 拉取该 tag 现有 Release 的 body（不存在则视为全新）
 *   2. 有 `<!-- SECTION:X -->…<!-- /SECTION:X -->` → 整块替换（并清掉重复块）
 *   3. 有历史无标记的同名段落 → 按 titleRegex 替换
 *   4. 都没有 → 追加到末尾
 *   5. 合并后把 3 个以上连续空行压成 1 个
 */

import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const PLATFORMS = {
  fnos: {
    id: 'FNOS',
    titleRegex: /###\s+SuenMoney\s+.*?飞牛私有云[\s\S]*?(?=(?:###\s+SuenMoney|<!-- SECTION:)|$)/gi,
    content: (tag) => `<!-- SECTION:FNOS -->
### SuenMoney ${tag} 飞牛私有云（fnOS）原生套件

- **格式**：\`.fpk\` 纯原生系统运行（免 Docker，零虚拟化损耗）。
- **功能**：内置安装引导向导，安装时可自定义服务端口并直接初始化第一个管理员账号，开箱即用。
- **依赖**：内置独立 Node 运行时，无需宿主机预装环境。
<!-- /SECTION:FNOS -->`
  },
  harmony: {
    id: 'HARMONY',
    titleRegex: /###\s+SuenMoney\s+.*?鸿蒙[\s\S]*?(?=(?:###\s+SuenMoney|<!-- SECTION:)|$)/gi,
    content: (tag) => `<!-- SECTION:HARMONY -->
### SuenMoney ${tag} 鸿蒙 NEXT 原生客户端

- **格式**：\`.hap\` 未签名包。
- **使用方式**：可直接推入鸿蒙 NEXT 模拟器调试，或通过移动端侧载/自签名工具签名后在真机运行。
<!-- /SECTION:HARMONY -->`
  },
  ios: {
    id: 'IOS',
    titleRegex: /###\s+SuenMoney\s+.*?iOS[\s\S]*?(?=(?:###\s+SuenMoney|<!-- SECTION:)|$)/gi,
    content: (tag) => `<!-- SECTION:IOS -->
### SuenMoney ${tag} iOS 原生客户端

- **格式**：\`.ipa\` 未签名包。
- **使用方式**：可直接使用 AltStore、SideStore、爱思助手等工具通过个人证书签名后安装到真机。
<!-- /SECTION:IOS -->`
  },
  docker: {
    id: 'DOCKER',
    /*
     * 镜像没有附件 —— 本体在 GHCR，发行页只负责告诉用户「怎么拉、拉哪个」。
     * 标题里刻意保留「Docker」字样：这一节在 suenmusic / suenweb 的发行页上不存在，
     * 用户扫一眼就要能认出这是 suenmoney 独有的交付形态。
     */
    titleRegex: /###\s+SuenMoney\s+.*?Docker[\s\S]*?(?=(?:###\s+SuenMoney|<!-- SECTION:)|$)/gi,
    content: (tag) => `<!-- SECTION:DOCKER -->
### SuenMoney ${tag} Docker 镜像

- **地址**：\`ghcr.io/sunriseqis/suenmoney\`（多架构：linux/amd64 + linux/arm64，构建机自动选对）
- **拉取**：\`docker pull ghcr.io/sunriseqis/suenmoney:${tag.replace(/^v/, '')}\`（或 \`:latest\`）
- **启动**：仓库根的 \`docker-compose.yml\` 已指向该镜像，\`docker compose up -d\` 即可；数据落在命名卷 \`suenmoney-data\`
- **端口**：只有 \`5310\` —— 页面与 \`/api\` 同源同端口，没有第二个端口要配
<!-- /SECTION:DOCKER -->`
  }
};

function parseArgs() {
  const args = process.argv.slice(2);
  let platform = '';
  let tag = '';
  let output = '';
  let repo = process.env.RELEASE_REPO || 'sunriseqis/suenapp';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--platform' && args[i + 1]) platform = args[++i];
    if (args[i] === '--tag' && args[i + 1]) tag = args[++i];
    if (args[i] === '--output' && args[i + 1]) output = args[++i];
    if (args[i] === '--repo' && args[i + 1]) repo = args[++i];
  }

  if (!platform || !tag || !output) {
    console.error('用法: node scripts/prepare-release-notes.mjs --platform <fnos|harmony|ios|docker> --tag <suenmoney-vX.Y.Z> --output <file>');
    process.exit(1);
  }

  return { platform, tag, output, repo };
}

async function fetchExistingReleaseBody(repo, tag) {
  const token = process.env.GITHUB_TOKEN || process.env.GH_RELEASE_TOKEN || process.env.SUENAPP_TOKEN || '';
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'suenmoney-ci',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/releases/tags/${tag}`, { headers });
    if (res.status === 404) return '';
    if (!res.ok) {
      console.warn(`[WARN] 获取现有 Release 失败 (HTTP ${res.status})，将作为全新 Release 处理`);
      return '';
    }
    const data = await res.json();
    return typeof data.body === 'string' ? data.body : '';
  } catch (err) {
    console.warn(`[WARN] 无法连接 GitHub API: ${err.message}，按全新 Release 处理`);
    return '';
  }
}

/**
 * 文案里展示的版本号要**去掉 `suenmoney-` 前缀**（tag 是 `suenmoney-v2.0.0`，
 * 但标题应该是 `### SuenMoney v2.0.0 …`，不能是 `### SuenMoney suenmoney-v2.0.0 …`）。
 * 查询 Release 仍用带前缀的完整 tag。
 */
function displayVersion(tag) {
  return tag.replace(/^suenmoney-/, '');
}

export function mergeBody(existing, platform, tag) {
  const conf = PLATFORMS[platform];
  if (!conf) throw new Error('Unsupported platform: ' + platform);
  const newContent = conf.content(displayVersion(tag)).trim();

  let body = (existing || '').trim();
  const markedRegex = new RegExp(`<!-- SECTION:${conf.id} -->[\\s\\S]*?<!-- /SECTION:${conf.id} -->`, 'gi');
  const titleRegex = new RegExp(conf.titleRegex.source, 'gi');

  if (markedRegex.test(body)) {
    // 替换所有已存在的带标记段落（保留第一块，清掉重复块）
    markedRegex.lastIndex = 0;
    let replacedFirst = false;
    body = body.replace(markedRegex, () => {
      if (!replacedFirst) {
        replacedFirst = true;
        return newContent;
      }
      return '';
    });
  } else if (titleRegex.test(body)) {
    // 替换历史无标记段落（同时清理多次重复文本）
    titleRegex.lastIndex = 0;
    let replacedFirst = false;
    body = body.replace(titleRegex, () => {
      if (!replacedFirst) {
        replacedFirst = true;
        return newContent;
      }
      return '';
    });
  } else {
    // 全新段落追加
    body = body ? `${body}\n\n${newContent}` : newContent;
  }

  return body.replace(/\n{3,}/g, '\n\n').trim();
}

async function main() {
  const { platform, tag, output, repo } = parseArgs();
  console.log(`[Release Notes] 合并平台 ${platform}（Tag: ${tag}, Repo: ${repo}）…`);

  const existingBody = await fetchExistingReleaseBody(repo, tag);
  const mergedBody = mergeBody(existingBody, platform, tag);

  writeFileSync(output, mergedBody + '\n', 'utf8');
  console.log(`[Release Notes] 已写入：${output}`);
}

/*
 * 只在「被当作脚本执行」时跑 main()。
 *
 * 之前这里是无条件 `main()`，于是 `import { mergeBody } from './prepare-release-notes.mjs'`
 * 会顺带触发一次 CLI 解析并因缺少 `--platform` 直接 `process.exit(1)` ——
 * 导出的 `mergeBody` 实际上没法被 import 使用（想给它写测试都做不到）。
 * 用 argv[1] 比对而不是 `import.meta.main`：后者要 Node ≥ 24.2，
 * 而这个脚本会被多条流水线在不同 Node 版本下调起。
 */
const invokedDirectly =
  process.argv[1] !== undefined && resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (invokedDirectly) {
  main().catch((err) => {
    console.error('[Release Notes] 错误:', err);
    process.exit(1);
  });
}
