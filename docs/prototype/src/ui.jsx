/* 同账 · 通用组件 */

const { useState, useEffect, useRef, useCallback, useMemo } = React;

function useMedia(query) {
  const [match, setMatch] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const mq = window.matchMedia(query);
    const on = () => setMatch(mq.matches);
    on();
    if (mq.addEventListener) mq.addEventListener('change', on);
    else mq.addListener(on);
    return () => {
      if (mq.removeEventListener) mq.removeEventListener('change', on);
      else mq.removeListener(on);
    };
  }, [query]);
  return match;
}

function Card({ children, className = '', as: Tag = 'div', ...rest }) {
  return <Tag className={'card ' + className} {...rest}>{children}</Tag>;
}

function Btn({ variant = '', size = '', className = '', icon, children, ...rest }) {
  const cls = ['btn', variant ? 'btn--' + variant : '', size ? 'btn--' + size : '', className].join(' ');
  return (
    <button type="button" className={cls} {...rest}>
      {icon ? <Icon name={icon} size={14} /> : null}
      {children}
    </button>
  );
}

function IconBtn({ icon, label, className = '', ...rest }) {
  return (
    <button type="button" className={'icon-btn ' + className} aria-label={label} title={label} {...rest}>
      <Icon name={icon} size={17} />
    </button>
  );
}

function Seg({ options, value, onChange, label }) {
  return (
    <div className="seg" role={label ? 'tablist' : 'group'} aria-label={label}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role={label ? 'tab' : undefined}
          aria-selected={label ? value === o.value : undefined}
          className={'seg-btn' + (value === o.value ? ' is-on' : '')}
          onClick={() => onChange(o.value)}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

function Chip({ active, dot, children, ...rest }) {
  return (
    <button type="button" className={'chip' + (active ? ' is-on' : '')} aria-pressed={!!active} {...rest}>
      {dot ? <i className="chip-dot" style={{ background: dot }}></i> : null}
      {children}
    </button>
  );
}

function Tag({ tone = '', children, className = '' }) {
  return <span className={['tag', tone ? 'tag--' + tone : '', className].join(' ')}>{children}</span>;
}

function Switch({ checked, onChange, label }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      className={'switch' + (checked ? ' is-on' : '')}
      onClick={() => onChange(!checked)}
    ></button>
  );
}

function CatIcon({ catId, size = 30, icon }) {
  const color = catColor(catId);
  const cat = CAT_BY_ID[catId];
  return (
    <span
      className="cat-ic"
      style={{
        width: size,
        height: size,
        background: color + '1F',
        borderColor: color + '55',
        color: color
      }}
    >
      <Icon name={icon || (cat ? cat.icon : 'dots')} size={Math.round(size * 0.55)} />
    </span>
  );
}

function Stat({ label, value, sub, className = '' }) {
  return (
    <div className={'stat ' + className}>
      <span className="stat-v">{value}</span>
      <span className="stat-l">{label}</span>
      {sub ? <span className="stat-sub">{sub}</span> : null}
    </div>
  );
}

function Bar({ pct, tone }) {
  return (
    <div className="bar">
      <div className="bar-fill" style={{ width: Math.min(100, Math.max(2, pct)) + '%', background: tone }}></div>
    </div>
  );
}

function Empty({ icon = 'info', children }) {
  return (
    <div className="empty">
      <Icon name={icon} size={22} />
      <span>{children}</span>
    </div>
  );
}

/* 环形图（纯 SVG，颜色随主题 token） */
function Donut({ data, total, centerLabel, centerValue, hole = 0.66 }) {
  const size = 176;
  const r = size / 2 - 12;
  const c = 2 * Math.PI * r;
  const sum = data.reduce((a, d) => a + d.value, 0) || 1;
  let acc = 0;
  return (
    <div className="donut">
      <svg width="100%" height="100%" viewBox={'0 0 ' + size + ' ' + size} aria-hidden="true">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--surface-3)" strokeWidth="16" />
        {data.map((d, i) => {
          const len = (d.value / sum) * c;
          const el = (
            <circle
              key={i}
              cx={size / 2}
              cy={size / 2}
              r={r}
              fill="none"
              stroke={d.color}
              strokeWidth="16"
              strokeDasharray={Math.max(0, len - 2.5) + ' ' + (c - Math.max(0, len - 2.5))}
              strokeDashoffset={-acc}
              transform={'rotate(-90 ' + size / 2 + ' ' + size / 2 + ')'}
              strokeLinecap="butt"
            />
          );
          acc += len;
          return el;
        })}
      </svg>
      <div className="donut-center">
        <span className="donut-c-l">{centerLabel}</span>
        <span className="donut-c-v">{centerValue}</span>
      </div>
    </div>
  );
}

function Modal({ open, onClose, title, children, footer, wide, className = '' }) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <React.Fragment>
      <div className="scrim" onClick={onClose}></div>
      <div className={'modal ' + (wide ? 'modal--wide ' : '') + className} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <span className="modal-title">{title}</span>
          <span className="spacer" style={{ marginLeft: 'auto' }}></span>
          <IconBtn icon="close" label="关闭" onClick={onClose} />
        </div>
        <div className="modal-body">{children}</div>
        {footer ? <div className="modal-foot">{footer}</div> : null}
      </div>
    </React.Fragment>
  );
}

/* 紧急度：容器不染色，单色标记 + 文字 */
function daysTo(dateStr) {
  return Math.round((parseYmd(dateStr) - parseYmd(TODAY_KEY)) / 86400000);
}

function urgencyOf(dateStr) {
  const n = daysTo(dateStr);
  if (n < 0) return { text: '逾期 ' + -n + ' 天', cls: 'late', level: 'late' };
  if (n === 0) return { text: '今日到期', cls: 'late', level: 'late' };
  if (n <= 3) return { text: n + ' 天后', cls: 'soon', level: 'soon' };
  return { text: n + ' 天后', cls: 'calm', level: 'calm' };
}

Object.assign(window, {
  useMedia, Card, Btn, IconBtn, Seg, Chip, Tag, Switch, CatIcon, Stat, Bar, Empty, Donut, Modal,
  daysTo, urgencyOf
});
