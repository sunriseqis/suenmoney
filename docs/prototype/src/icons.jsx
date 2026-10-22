/* 同账 · 线性图标集（手写 SVG，随主题切换笔画粗细） */

const ICON_PATHS = {
  grid: <><rect x="3.5" y="3.5" width="7" height="7" rx="1.6" /><rect x="13.5" y="3.5" width="7" height="7" rx="1.6" /><rect x="3.5" y="13.5" width="7" height="7" rx="1.6" /><rect x="13.5" y="13.5" width="7" height="7" rx="1.6" /></>,
  list: <><path d="M4 6.5h16M4 12h16M4 17.5h10" /></>,
  chart: <><path d="M4 20V9M10 20V4M16 20v-7M22 20H2" /></>,
  calendar: <><rect x="3.5" y="5" width="17" height="16" rx="2.5" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
  settings: <><circle cx="12" cy="12" r="3.2" /><path d="M12 3v2.2M12 18.8V21M4.2 7.5l1.9 1.1M17.9 15.4l1.9 1.1M4.2 16.5l1.9-1.1M17.9 8.6l1.9-1.1" /></>,
  plus: <><path d="M12 5v14M5 12h14" /></>,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="M16 16l4.5 4.5" /></>,
  close: <><path d="M6 6l12 12M18 6L6 18" /></>,
  left: <><path d="M15 5l-7 7 7 7" /></>,
  right: <><path d="M9 5l7 7-7 7" /></>,
  down: <><path d="M5 9l7 7 7-7" /></>,
  up: <><path d="M5 15l7-7 7 7" /></>,
  trash: <><path d="M4 7h16M9 7V4.5h6V7M6.5 7l1 13h9l1-13M10 11v6M14 11v6" /></>,
  edit: <><path d="M4 20h4l10-10-4-4L4 16v4zM14.5 5.5l4 4" /></>,
  check: <><path d="M4.5 12.5l5 5 10-11" /></>,
  undo: <><path d="M4 10h9a5.5 5.5 0 010 11H8M4 10l4-4M4 10l4 4" /></>,
  alert: <><path d="M12 3.5L21.5 20H2.5L12 3.5zM12 9v5M12 17h.01" /></>,
  clock: <><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></>,
  users: <><circle cx="9" cy="8" r="3.4" /><path d="M2.8 20c0-3.4 2.8-5.6 6.2-5.6s6.2 2.2 6.2 5.6" /><path d="M16 5.2a3.4 3.4 0 010 6.4M17.5 14.8c2.2.5 3.7 2.2 3.7 4.6" /></>,
  download: <><path d="M12 3v12M7.5 10.5L12 15l4.5-4.5M4 20h16" /></>,
  upload: <><path d="M12 16V4M7.5 8.5L12 4l4.5 4.5M4 20h16" /></>,
  shield: <><path d="M12 3l7.5 3v6c0 4.4-3 7.7-7.5 9-4.5-1.3-7.5-4.6-7.5-9V6L12 3z" /><path d="M8.8 12l2.2 2.2 4.2-4.4" /></>,
  database: <><ellipse cx="12" cy="6" rx="7.5" ry="3" /><path d="M4.5 6v6c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3V6M4.5 12v6c0 1.7 3.4 3 7.5 3s7.5-1.3 7.5-3v-6" /></>,
  sun: <><circle cx="12" cy="12" r="4.2" /><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M18.7 5.3l-1.6 1.6M6.9 17.1l-1.6 1.6" /></>,
  moon: <><path d="M20 14.5A8.5 8.5 0 019.5 4 8.5 8.5 0 1020 14.5z" /></>,
  menu: <><path d="M4 7h16M4 12h16M4 17h16" /></>,
  refresh: <><path d="M20 11a8 8 0 10-2.6 6M20 4.5V11h-6.2" /></>,
  trendUp: <><path d="M4 17l6-6 4 4 6-7M15 8h5v5" /></>,
  trendDown: <><path d="M4 7l6 6 4-4 6 7M15 16h5v-5" /></>,
  tag: <><path d="M11 3.5H20V12l-8.6 8.6a1.6 1.6 0 01-2.3 0L3.8 15a1.6 1.6 0 010-2.3L11 3.5z" /><circle cx="16" cy="8" r="1.4" /></>,
  filter: <><path d="M3.5 5.5h17l-6.5 7.6V20l-4-2.4v-4.5L3.5 5.5z" /></>,
  card: <><rect x="2.5" y="5" width="19" height="14" rx="2.6" /><path d="M2.5 9.5h19M6 15h3.5" /></>,
  wallet: <><path d="M3.5 8.5A2.5 2.5 0 016 6h12.5A2 2 0 0120.5 8v10a2 2 0 01-2 2H6a2.5 2.5 0 01-2.5-2.5v-9z" /><path d="M16 12.5h4.5v4H16a2 2 0 010-4z" /></>,
  coins: <><ellipse cx="9" cy="7" rx="5.5" ry="2.6" /><path d="M3.5 7v4c0 1.4 2.5 2.6 5.5 2.6s5.5-1.2 5.5-2.6V7" /><path d="M14 11.6c2.6.3 4.5 1.3 4.5 2.5v3.3c0 1.4-2.5 2.6-5.5 2.6-2.2 0-4.1-.7-5-1.7" /></>,
  bank: <><path d="M3 9.5L12 4l9 5.5M5 9.5V19M9.5 9.5V19M14.5 9.5V19M19 9.5V19M3 21h18" /></>,
  fork: <><path d="M7 3v7a2.5 2.5 0 005 0V3M9.5 12.5V21M16.5 3c1.6 1 2.3 2.7 2.3 5s-.8 3.6-2.3 4.3V21" /></>,
  car: <><path d="M4 16.5v2a1.5 1.5 0 003 0v-2M17 16.5v2a1.5 1.5 0 003 0v-2" /><path d="M3 16.5v-4l2-5.5A2 2 0 016.9 5.5h10.2a2 2 0 011.9 1.5l2 5.5v4zM3 12.5h18M7 14.5h1.5M15.5 14.5H17" /></>,
  home: <><path d="M4 10.5L12 4l8 6.5V20H4v-9.5z" /><path d="M9.5 20v-5.5h5V20" /></>,
  bag: <><path d="M5 8h14l-1.2 12H6.2L5 8z" /><path d="M9 8V6a3 3 0 016 0v2" /></>,
  basket: <><path d="M3.5 9h17l-1.8 10H5.3L3.5 9zM8 9l2.5-5M16 9l-2.5-5" /><path d="M9.5 13v3M14.5 13v3" /></>,
  heart: <><path d="M12 20s-7.5-4.3-7.5-9.4A4.1 4.1 0 0112 8a4.1 4.1 0 017.5 2.6c0 5.1-7.5 9.4-7.5 9.4z" /></>,
  book: <><path d="M4 5.5A1.5 1.5 0 015.5 4H19v16H5.5A1.5 1.5 0 014 18.5v-13zM19 16H5.5A1.5 1.5 0 004 17.5" /></>,
  game: <><rect x="2.5" y="7" width="19" height="10.5" rx="4" /><path d="M7 10v4M5 12h4M16 11h.01M18.5 13.5h.01" /></>,
  phone: <><rect x="7" y="2.5" width="10" height="19" rx="2.4" /><path d="M11 18.5h2" /></>,
  gift: <><path d="M3.5 9h17v11h-17zM3.5 9l0-3h17v3M12 6v14" /><path d="M12 6S11 2.5 8.5 3.5 9 6 12 6zM12 6s1-3.5 3.5-2.5S15 6 12 6z" /></>,
  baby: <><circle cx="12" cy="9" r="4.5" /><path d="M6 21c0-3.3 2.7-5.6 6-5.6s6 2.3 6 5.6M9.5 8.5h.01M14.5 8.5h.01M10.5 11h3" /></>,
  dots: <><circle cx="6" cy="12" r="1.4" /><circle cx="12" cy="12" r="1.4" /><circle cx="18" cy="12" r="1.4" /></>,
  link: <><path d="M10 13.5a4 4 0 005.6 0l3-3a4 4 0 00-5.6-5.6l-1.5 1.5M14 10.5a4 4 0 00-5.6 0l-3 3A4 4 0 0011 19.1l1.5-1.5" /></>,
  server: <><rect x="3" y="4" width="18" height="6" rx="1.6" /><rect x="3" y="14" width="18" height="6" rx="1.6" /><path d="M7 7h.01M7 17h.01" /></>,
  lock: <><rect x="4.5" y="10" width="15" height="10.5" rx="2.2" /><path d="M8 10V7.5a4 4 0 018 0V10" /></>,
  info: <><circle cx="12" cy="12" r="8.5" /><path d="M12 11v5.5M12 7.8h.01" /></>,
  briefcase: <><rect x="3" y="7.5" width="18" height="12.5" rx="2" /><path d="M9 7.5V5.5h6v2M3 12.5h18" /></>,
  filterOff: <><path d="M4 4l16 16M3.5 5.5h17l-5.4 6.3M13 12.5V20l-4-2.4v-4.6" /></>,
  spark: <><path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3z" /></>,
  layers: <><path d="M12 3l9 5-9 5-9-5 9-5zM3 12l9 5 9-5M3 16.5l9 5 9-5" /></>
};

function Icon({ name, size = 18, className = '', style }) {
  const body = ICON_PATHS[name] || ICON_PATHS.dots;
  return (
    <svg
      className={'ic ' + className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      style={style}
    >
      {body}
    </svg>
  );
}

Object.assign(window, { Icon, ICON_PATHS });
