#!/usr/bin/env node
/**
 * 自适应启动器 —— 让脚本在 Node 22.x / 23.x / 24.x 与 CI 上都能直接跑。
 *
 * 存在的原因：`node:sqlite` 与 TypeScript 类型剥离这两项能力在不同 Node
 * 小版本上的状态不一样 ——
 *
 *   node:sqlite            22.5 起存在但需要 --experimental-sqlite，新版本已默认开启
 *   类型剥离 .ts           22.6 起存在但需要 --experimental-strip-types，22.18+ 默认开启
 *
 * 写死旗标在旧版本上能跑、在新版本上会 `bad option` 直接崩；不写旗标则相反。
 * 所以这里**不猜版本号，直接探测能力**：先看不用旗标行不行，不行再试加上旗标，
 * 两条路都不通就给出可操作的报错。这样将来 Node 再取消旗标也无需改这里。
 *
 * 用法：
 *   node scripts/node-run.mjs src/index.ts          # 跑一个 .ts 入口
 *   node scripts/node-run.mjs --watch src/index.ts  # 带 --watch
 *   node scripts/node-run.mjs --test                # 跑测试（自动发现 *_test / *.test）
 */
import { spawn, spawnSync } from 'node:child_process';

const rawArgs = process.argv.slice(2);
const wantsWatch = rawArgs.includes('--watch');
const wantsTest = rawArgs.includes('--test');
const positionals = rawArgs.filter((arg) => !arg.startsWith('--'));

/**
 * 两种模式对位置参数的解释不同：
 *   运行模式 `node-run.mjs src/index.ts --foo bar` —— 第一个是入口，其余透传给业务
 *   测试模式 `node-run.mjs --test src/http/x.test.ts` —— 全部是测试文件/目录
 * 早期版本把「第一个位置参数」无条件当作入口，导致测试模式下的文件路径被吞掉，
 * 表现是「指定了文件却跑了全量」，白等一轮。
 */
const entry = wantsTest ? undefined : positionals[0];

if (!wantsTest && entry === undefined) {
  console.error(
    '用法：\n  node scripts/node-run.mjs [--watch] <入口文件> [业务参数...]\n  node scripts/node-run.mjs --test [测试文件或目录...]',
  );
  process.exit(1);
}

/** 该旗标在当前 Node 上是否被接受（未知旗标会让 node 以非 0 退出并报 bad option）。 */
function acceptsFlag(flag) {
  return spawnSync(process.execPath, [flag, '-e', '0'], { stdio: 'ignore' }).status === 0;
}

/** 在给定旗标下能否加载 node:sqlite。 */
function sqliteLoadable(flags) {
  return (
    spawnSync(process.execPath, [...flags, '--input-type=module', '-e', "await import('node:sqlite')"], {
      stdio: 'ignore',
    }).status === 0
  );
}

const nodeFlags = [];

// ---- TypeScript 类型剥离 ----
// 旗标仍被接受就显式加上（在默认开启的新版本上它只是空操作）；
// 将来旗标被移除时这里会自动跳过，而那时该能力必然已默认开启。
if (acceptsFlag('--experimental-strip-types')) {
  nodeFlags.push('--experimental-strip-types');
}

// ---- node:sqlite ----
if (!sqliteLoadable([])) {
  if (sqliteLoadable(['--experimental-sqlite'])) {
    nodeFlags.push('--experimental-sqlite');
  } else {
    console.error(
      [
        `当前 Node（${process.version}）无法加载 node:sqlite。`,
        '需要 Node >= 22.5。若你用的是更老的版本，请升级后重试。',
        '若你确认版本满足，请提 issue 并附上 `node -v` 与操作系统。',
      ].join('\n'),
    );
    process.exit(1);
  }
}

// ---- .env ----
// --env-file-if-exists 自 22.9 起可用；老版本上静默跳过，此时需要自己 export 环境变量。
if (acceptsFlag('--env-file-if-exists=.env')) {
  nodeFlags.push('--env-file-if-exists=.env');
}

// 实验性能力会打印警告，而我们的旗标本身已在探测中被验证过 —— 噪音没有信息量
nodeFlags.push('--disable-warning=ExperimentalWarning');

const finalArgs = [...nodeFlags];

if (wantsTest) {
  finalArgs.push('--test');
} else {
  if (wantsWatch) finalArgs.push('--watch');
  finalArgs.push(entry);
}

/**
 * 透传业务参数时**必须保持原顺序**。
 *
 * 早期版本把它拆成「先所有位置参数、再所有 --开关」两趟，结果
 * `--username suen` 变成了 `suen --username`；而 `user:add` 是按
 * `argv.indexOf('--username')` 再取下一个元素来读值的，于是读到的
 * 是下一个标志，判定为「没传」并打印用法。参数顺序本身就是信息。
 */
for (const extra of rawArgs) {
  if (extra === entry) continue;
  if (extra === '--watch' || extra === '--test') continue;
  finalArgs.push(extra);
}

const child = spawn(process.execPath, finalArgs, { stdio: 'inherit' });

child.on('exit', (code, signal) => {
  process.exit(signal !== null ? 1 : (code ?? 0));
});

/**
 * 转发信号给子进程。
 *
 * 交互式运行时 Ctrl+C 会把 SIGINT 发给整个进程组，父子都会退出，看不出问题。
 * 但 `kill <启动器的 pid>` 只发给启动器本身 —— 子进程会继续占着端口活着，
 * 于是你以为「重启了服务」，实际上新的实例因 EADDRINUSE 静默退出，
 * 请求仍然打在旧进程上（还可能是旧进程打开着的、已被删除的数据库文件）。
 * 这个坑排查起来极其费时，因为现象是「改了代码/换了库，但服务端行为不变」。
 */
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => {
    if (!child.killed) child.kill(signal);
  });
}
