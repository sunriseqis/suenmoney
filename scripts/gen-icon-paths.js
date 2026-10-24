// Lucide SVG → ArkUI Path commands 生成器
// 把每个 SVG 里的图形元素统一转成一条 path d 字符串（ArkUI Path 只吃 d）
const fs = require('fs');
const path = require('path');

const SRC = '/home/suenmoney/docs/design/icons/lucide';
const OUT = '/home/suenmoney/hw-native/entry/src/main/ets/common/ui/IconPaths.ets';

const num = (v) => {
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : 0;
};
const f = (n) => (Math.round(n * 100) / 100).toString();

function circleToPath(cx, cy, rx, ry) {
  // 两段弧闭合成椭圆
  return `M${f(cx - rx)} ${f(cy)}a${f(rx)} ${f(ry)} 0 1 0 ${f(rx * 2)} 0a${f(rx)} ${f(ry)} 0 1 0 ${f(-rx * 2)} 0`;
}

function rectToPath(x, y, w, h, rx) {
  if (!rx) {
    return `M${f(x)} ${f(y)}h${f(w)}v${f(h)}h${f(-w)}Z`;
  }
  const r = Math.min(rx, w / 2, h / 2);
  return (
    `M${f(x + r)} ${f(y)}` +
    `h${f(w - 2 * r)}a${f(r)} ${f(r)} 0 0 1 ${f(r)} ${f(r)}` +
    `v${f(h - 2 * r)}a${f(r)} ${f(r)} 0 0 1 ${f(-r)} ${f(r)}` +
    `h${f(-(w - 2 * r))}a${f(r)} ${f(r)} 0 0 1 ${f(-r)} ${f(-r)}` +
    `v${f(-(h - 2 * r))}a${f(r)} ${f(r)} 0 0 1 ${f(r)} ${f(-r)}Z`
  );
}

function pointsToPath(pts, close) {
  const arr = pts.trim().split(/[\s,]+/).map(num);
  if (arr.length < 4) return '';
  let d = `M${f(arr[0])} ${f(arr[1])}`;
  for (let i = 2; i + 1 < arr.length; i += 2) d += `L${f(arr[i])} ${f(arr[i + 1])}`;
  if (close) d += 'Z';
  return d;
}

function attrs(tag) {
  const o = {};
  const re = /([a-zA-Z-]+)\s*=\s*"([^"]*)"/g;
  let m;
  while ((m = re.exec(tag))) o[m[1]] = m[2];
  return o;
}

function svgToPath(svg) {
  const parts = [];
  const re = /<(path|circle|ellipse|rect|line|polyline|polygon)\b([^>]*?)\/?>/g;
  let m;
  while ((m = re.exec(svg))) {
    const kind = m[1];
    const a = attrs(m[2]);
    if (kind === 'path') {
      if (a.d) parts.push(a.d.trim());
    } else if (kind === 'circle') {
      parts.push(circleToPath(num(a.cx), num(a.cy), num(a.r), num(a.r)));
    } else if (kind === 'ellipse') {
      parts.push(circleToPath(num(a.cx), num(a.cy), num(a.rx), num(a.ry)));
    } else if (kind === 'rect') {
      parts.push(rectToPath(num(a.x), num(a.y), num(a.width), num(a.height), num(a.rx || a.ry)));
    } else if (kind === 'line') {
      parts.push(`M${f(num(a.x1))} ${f(num(a.y1))}L${f(num(a.x2))} ${f(num(a.y2))}`);
    } else if (kind === 'polyline') {
      parts.push(pointsToPath(a.points || '', false));
    } else if (kind === 'polygon') {
      parts.push(pointsToPath(a.points || '', true));
    }
  }
  // 合并成一串：多个子路径用空格分隔（ArkUI Path 支持多子路径）
  return parts.filter((s) => s && s.length).join(' ');
}

const files = fs.readdirSync(SRC).filter((n) => n.endsWith('.svg')).sort();
const entries = [];
for (const file of files) {
  const name = file.replace(/\.svg$/, '');
  const svg = fs.readFileSync(path.join(SRC, file), 'utf8');
  const d = svgToPath(svg);
  if (!d) {
    console.error('EMPTY:', name);
    continue;
  }
  entries.push([name, d]);
}

const lines = [];
lines.push('/**');
lines.push(' * Lucide 图标路径表（24×24 viewPort，描边 2，圆头圆角）。');
lines.push(' *');
lines.push(' * 由 `docs/design/icons/lucide/*.svg` 机械转换而来（circle/rect/line/polyline/polygon 都并进 path d），');
lines.push(' * 与 Web 端 `<component :is="Lucide">` 用的是同一份几何，保证两端图标形状一致。');
lines.push(' *');
lines.push(' * 渲染方式见 `IconView`：ArkUI 的 `Path` 组件直接吃 SVG 的 d，配合 `Shape.viewPort` 缩放，');
lines.push(' * 描边色运行时可染 —— 所以不需要把图标转成字体。');
lines.push(' */');
lines.push('');
lines.push('export const ICON_PATHS: Record<string, string> = {');
for (const [name, d] of entries) {
  lines.push(`  '${name}': '${d.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}',`);
}
lines.push('};');
lines.push('');
lines.push('/** 图标名 → path；找不到返回空串（调用方再兜底） */');
lines.push('export function iconPathOf(name: string): string {');
lines.push('  const hit = ICON_PATHS[name];');
lines.push('  return hit === undefined ? \'\' : hit;');
lines.push('}');
lines.push('');

fs.writeFileSync(OUT, lines.join('\n'), 'utf8');
console.log('生成', entries.length, '个图标 →', OUT);
console.log('文件大小', fs.statSync(OUT).size, 'bytes');
