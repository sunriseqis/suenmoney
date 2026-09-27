/**
 * 计算分类调色板：8 个色相，每个色相在「浅色卡 #FFFFFF」与「深色卡 #1F2937」上
 * 都必须 ≥ 3:1（WCAG 对**有意义的图形**的要求）。
 * 直接用 Tailwind 的色阶枚举出能同时过线的最深/最浅档，避免凭感觉挑色。
 */
const LUM = (hex) => {
  const c = hex.replace('#', '');
  const [r, g, b] = [0, 2, 4].map((i) => {
    let v = parseInt(c.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const CONTRAST = (a, b) => {
  const [l1, l2] = [LUM(a), LUM(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
};

const LIGHT_CARD = '#ffffff';
const DARK_CARD = '#1f2937';

const HUES = {
  blue:    ['#1d4ed8', '#2563eb', '#3b82f6', '#60a5fa', '#93c5fd'],
  green:   ['#047857', '#059669', '#10b981', '#34d399', '#6ee7b7'],
  orange:  ['#b45309', '#d97706', '#f59e0b', '#fbbf24', '#fcd34d'],
  violet:  ['#5b21b6', '#6d28d9', '#7c3aed', '#8b5cf6', '#a78bfa'],
  pink:    ['#9d174d', '#be185d', '#db2777', '#ec4899', '#f472b6'],
  cyan:    ['#155e75', '#0e7490', '#0891b2', '#22d3ee', '#67e8f9'],
  red:     ['#991b1b', '#b91c1c', '#dc2626', '#ef4444', '#f87171'],
  indigo:  ['#3730a3', '#4338ca', '#4f46e5', '#6366f1', '#818cf8'],
};

for (const [name, shades] of Object.entries(HUES)) {
  // shades 按「深 → 浅」排列。
  //   浅色主题（白卡）：颜色越浅对比越低，取**能过线的最浅档**
  //   深色主题（深卡）：颜色越深对比越低，取**能过线的最深档**
  // 两头都取到极限，色相才不至于一边闷黑、一边刺眼。
  const light = [...shades].reverse().find((h) => CONTRAST(h, LIGHT_CARD) >= 3.3);
  const dark = shades.find((h) => CONTRAST(h, DARK_CARD) >= 3.3);
  const fmt = (h) => (h ? `${h} (${CONTRAST(h, LIGHT_CARD).toFixed(2)}/${CONTRAST(h, DARK_CARD).toFixed(2)})` : '无');
  console.log(
    name.padEnd(7),
    'light:', fmt(light).padEnd(24),
    'dark:', fmt(dark).padEnd(24),
    light && dark ? 'OK' : '*** 需要人工调 ***',
  );
}
