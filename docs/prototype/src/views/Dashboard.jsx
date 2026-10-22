/* 概况 DashboardView */

const { useState, useMemo } = React;

function Dashboard({ expenses, plans, todos, onNav, onTodoAction, onOpenSheet }) {
  const [period, setPeriod] = useState('month');
  const [anchor, setAnchor] = useState(TODAY);
  const [alertOpen, setAlertOpen] = useState(false);

  const range = periodOf(period, anchor);
  const list = inRange(expenses, range.start, range.end);
  const total = sumCents(list);
  const prev = prevPeriodExpenses(expenses, period, anchor);
  const prevTotal = sumCents(prev);
  const delta = prevTotal ? (total - prevTotal) / prevTotal : 0;

  const days = Math.max(1, Math.round((Math.min(range.end, TODAY) - range.start) / 86400000) + 1);
  const dayCount = period === 'month' ? days : Math.max(1, Math.round((range.end - range.start) / 86400000) + 1);
  const perDay = Math.round(total / dayCount);
  const projected = period === 'month' ? Math.round((total / days) * range.end.getDate()) : null;
  const monthsInRange = period === 'year' ? 12 : Math.max(1, Math.round((range.end - range.start) / 86400000) / 30);
  const monthAvg = Math.round(total / monthsInRange);
  const peak = byMonth(expenses, 12).reduce((a, b) => (b.cents > a.cents ? b : a), { cents: 0, date: TODAY });
  const monthCount = list.filter((x) => x.amount_cents > 0).length;

  const pending = todos.filter((t) => t.state === 'pending');
  const late = pending.filter((t) => daysTo(t.due_date) < 0);
  const soon = pending.filter((t) => daysTo(t.due_date) >= 0 && daysTo(t.due_date) <= 3);
  const pendingTotal = pending.reduce((a, t) => a + t.amount_cents, 0);

  const due = useMemo(() => {
    const map = {};
    dueRows(expenses, TODAY).forEach((x) => {
      map[x.repayment_date] = map[x.repayment_date] || { date: x.repayment_date, cents: 0, rows: [] };
      map[x.repayment_date].cents += x.amount_cents;
      map[x.repayment_date].rows.push(x);
    });
    return Object.values(map).sort((a, b) => (a.date < b.date ? -1 : 1));
  }, [expenses]);
  const dueTotal = due.reduce((a, d) => a + d.cents, 0);

  const planMonthly = plans.filter((p) => p.active).reduce((a, p) => a + p.amount_cents, 0);
  const monthTodos = todos.filter((t) => sameMonth(parseYmd(t.due_date), TODAY));
  const paidPlan = monthTodos.filter((t) => t.state === 'done').reduce((a, t) => a + t.amount_cents, 0);
  const progressPct = planMonthly ? (paidPlan / planMonthly) * 100 : 0;

  const monthly = byMonth(expenses, 12);
  const heatMax = Math.max.apply(null, monthly.map((m) => m.cents).concat([1]));
  const yearCents = sumCents(expenses.filter((x) => x.spend_date.slice(0, 4) === String(TODAY.getFullYear())));
  const lastYearCents = sumCents(expenses.filter((x) => x.spend_date.slice(0, 4) === String(TODAY.getFullYear() - 1)));
  const yearDelta = lastYearCents ? (yearCents - lastYearCents) / lastYearCents : 0;
  const firstDate = expenses.length ? expenses[expenses.length - 1].spend_date : TODAY_KEY;
  const spanDays = Math.round((TODAY - parseYmd(firstDate)) / 86400000);
  const totalAll = sumCents(expenses);

  const compose = useMemo(() => {
    const map = {};
    list.forEach((x) => {
      const c = CAT_BY_ID[x.cat_id];
      const id = c && c.parent ? c.parent : x.cat_id;
      map[id] = (map[id] || 0) + x.amount_cents;
    });
    const rows = Object.keys(map).map((id) => ({ id, cents: map[id] })).filter((r) => r.cents > 0).sort((a, b) => b.cents - a.cents);
    const top = rows.slice(0, 4);
    const rest = rows.slice(4).reduce((a, r) => a + r.cents, 0);
    if (rest > 0) top.push({ id: 'rest', cents: rest });
    return top;
  }, [list]);

  const metrics = period === 'year'
    ? [{ l: '月均支出', v: money(monthAvg) }, { l: '笔数', v: monthCount + ' 笔' }, { l: '最高月', v: (peak.date.getMonth() + 1) + ' 月' }]
    : period === 'all'
      ? [{ l: '月均支出', v: money(monthAvg) }, { l: '笔数', v: monthCount + ' 笔' }, { l: '记录跨度', v: Math.round(spanDays / 30) + ' 个月' }]
      : [{ l: '日均支出', v: money(perDay) }, { l: '笔数', v: monthCount + ' 笔' }, { l: '预计月末', v: money(projected || 0) }];

  const activePlans = plans.filter((p) => p.active);
  const doneTodos = monthTodos.filter((t) => t.state === 'done');

  return (
    <div className="overview-grid">
      <Card className="hero-main card--pop og-hero">
        <div className="hero-eyebrow">
          <Seg
            label="期间"
            value={period}
            onChange={setPeriod}
            options={[{ value: 'month', label: '本月' }, { value: 'year', label: '本年' }, { value: 'all', label: '全部' }]}
          />
          <span className="spacer" style={{ marginLeft: 'auto' }}></span>
          {period !== 'all' ? (
            <div className="period-nav">
              <IconBtn icon="left" label="上一期间" onClick={() => setAnchor(shiftPeriod(period, anchor, -1))} />
              <span className="mono tiny" style={{ minWidth: 72, textAlign: 'center' }}>{periodLabel(period, anchor)}</span>
              <IconBtn icon="right" label="下一期间" onClick={() => setAnchor(shiftPeriod(period, anchor, 1))} />
            </div>
          ) : <Tag tone="dash">全部记录</Tag>}
        </div>

        <div className="hero-amt"><span className="cur">¥</span>{moneyPlain(total)}</div>
        <div className="hero-delta">
          <span className={'delta-pill ' + (delta > 0 ? 'neg' : 'pos')}>
            <Icon name={delta > 0 ? 'trendUp' : 'trendDown'} size={11} />
            {(delta * 100).toFixed(1)}%
          </span>
          <span>较{period === 'month' ? '上月' : period === 'year' ? '去年' : '上一段'} {money(prevTotal)}</span>
          <span className="muted tiny">· 期间对比</span>
        </div>

        <div className="hero-metrics">
          {metrics.map((m) => <Stat key={m.l} label={m.l} value={m.v} />)}
        </div>

        <div className="og-hero-foot">
          <div className="stack-bar" role="img" aria-label="支出构成堆叠条">
            {compose.map((r) => (
              <span key={r.id} style={{ flex: r.cents, background: r.id === 'rest' ? 'var(--ink-3)' : CAT_COLORS[catColor(r.id)] }}></span>
            ))}
          </div>
          <div className="compose-legend">
            {compose.map((r) => (
              <span className="cl-item" key={r.id}>
                <i className="cl-dot" style={{ background: r.id === 'rest' ? 'var(--ink-3)' : CAT_COLORS[catColor(r.id)] }}></i>
                {r.id === 'rest' ? '其他' : catName(r.id)}
                <b className="mono" style={{ fontWeight: 600 }}>{total ? Math.round((r.cents / total) * 100) : 0}%</b>
              </span>
            ))}
          </div>
          <div className="toolbar" style={{ marginTop: 14 }}>
            <span className="desktop-only"><Btn variant="primary" icon="plus" onClick={() => onOpenSheet && onOpenSheet()}>记一笔</Btn></span>
            <Btn variant="ghost" icon="list" onClick={() => onNav('ledger')}>查看流水</Btn>
            <span style={{ marginLeft: 'auto' }} className="tiny muted mono">离线数据 · 联网后自动校准</span>
          </div>
        </div>
      </Card>

      <Card className="og-todo og-card">
        <button type="button" className="alert-strip" onClick={() => setAlertOpen((v) => !v)} aria-expanded={alertOpen}>
          <Icon name="alert" size={15} />
          <span>{late.length ? late.length + ' 笔已逾期' : soon.length ? soon.length + ' 笔临近还款' : '暂无待办'}{pending.length ? ' · 共 ' + pending.length + ' 笔' : ''}</span>
          <span className="spacer" style={{ marginLeft: 'auto' }}></span>
          <Icon name={alertOpen ? 'up' : 'down'} size={13} />
        </button>
        {alertOpen ? (
          <div className="alert-pop" style={{ marginTop: 8 }}>
            {pending.length === 0 ? <Empty icon="check">待办已清空</Empty> : pending.map((t) => {
              const u = urgencyOf(t.due_date);
              return (
                <div className="alert-item" key={t.id}>
                  <i className={'todo-mark is-' + u.level} style={{ height: 18, width: 3 }}></i>
                  <span style={{ minWidth: 0, flex: '1 1 auto' }}>{t.title}</span>
                  <span className={'urgency urgency--' + (u.level === 'late' ? 'late' : u.level === 'soon' ? 'soon' : 'calm')}>{u.text}</span>
                  <div className="row-end">
                    <Btn size="sm" variant="ghost" onClick={() => onTodoAction(t, t.kind === 'auto' ? 'ack' : 'confirm')}>
                      {t.kind === 'auto' ? '确认' : '入账'}
                    </Btn>
                    <Btn size="sm" variant="ghost" onClick={() => onTodoAction(t, 'skip')}>忽略</Btn>
                  </div>
                </div>
              );
            })}
            {pending.length ? (
              <div className="split" style={{ borderTop: '1px dashed var(--line)', paddingTop: 8 }}>
                <span className="tiny muted">待办合计 <b className="mono" style={{ color: 'var(--ink)' }}>{money(pendingTotal)}</b></span>
                <button type="button" className="btn btn--ghost btn--sm" style={{ marginLeft: 'auto' }} onClick={() => onNav('settings', { tab: 'plans' })}>全部待办</button>
              </div>
            ) : null}
          </div>
        ) : null}

        <div className="og-card-body">
          <div className="card-h card-h--tight">
            <span className="card-t">本月要还</span>
            <span className="card-cap">信用卡 · {due.length} 个还款日</span>
          </div>
          {due.length === 0 ? <Empty icon="card">本月没有信用卡账单</Empty> : due.map((d) => {
            const u = urgencyOf(d.date);
            return (
              <div className="due-row" key={d.date}>
                <span className="due-card-badge"><Icon name="card" size={15} /></span>
                <div style={{ minWidth: 0, flex: '1 1 auto' }}>
                  <div style={{ fontSize: 12, fontWeight: 600 }}>{(d.date.slice(5, 7))} 月 {d.date.slice(8, 10)} 日还款</div>
                  <div className="tiny muted">{d.rows.length} 笔 · {Array.from(new Set(d.rows.map((r) => PAY_BY_ID[r.pay_id].name))).join(' / ')}</div>
                </div>
                <div className="row-end">
                  <div className="row-amt">{money(d.cents)}</div>
                  <div className={'urgency urgency--' + (u.level === 'late' ? 'late' : u.level === 'soon' ? 'soon' : 'calm')}>{u.text}</div>
                </div>
              </div>
            );
          })}
        </div>
        <div className="og-sub">
          <div className="card-h card-h--tight">
            <span className="card-t">待办提醒</span>
            <span className="card-cap">{pending.length} 笔待处理</span>
          </div>
          {pending.length === 0 ? <Empty icon="check">待办已清空</Empty> : pending.slice(0, 3).map((t) => {
            const u = urgencyOf(t.due_date);
            return (
              <div className="og-todo-row" key={t.id}>
                <span className={'todo-mark is-' + u.level}></span>
                <span className="og-todo-t">{t.title}</span>
                <span className={'urgency urgency--' + (u.level === 'late' ? 'late' : u.level === 'soon' ? 'soon' : 'calm')}>{u.text}</span>
                <b className="mono tiny">{money(t.amount_cents)}</b>
              </div>
            );
          })}
        </div>
        <div className="og-card-foot">
          <span className="tiny muted">合计应还 <b className="mono" style={{ color: 'var(--ink)' }}>{money(dueTotal)}</b></span>
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => onNav('settings', { tab: 'plans' })}>全部待办</button>
        </div>
      </Card>

      <Card className="og-heat og-card">
        <div className="card-h">
          <span className="orb" style={{ background: 'var(--amber)', color: '#1E293B' }}><Icon name="calendar" size={16} /></span>
          <span className="card-t">月度支出热力</span>
          <span className="card-cap">近 12 个月 · 点击下钻</span>
        </div>
        <div className="og-card-body">
          <div className="heat-grid">
            {monthly.map((m) => {
              const pct = m.cents / heatMax;
              return (
                <button
                  type="button"
                  className={'heat-cell' + (sameMonth(m.date, TODAY) ? ' is-now' : '')}
                  key={m.date.getTime()}
                  onClick={() => onNav('ledger', { anchor: m.date })}
                  title={m.date.getFullYear() + '年' + (m.date.getMonth() + 1) + '月 ' + money(m.cents)}
                >
                  <span className="heat-m">{m.date.getMonth() + 1}月</span>
                  <span className="heat-v">{wan(m.cents)}</span>
                  <span className="heat-dot" style={{ background: 'color-mix(in srgb, var(--accent) ' + Math.round(18 + pct * 82) + '%, var(--surface-3))' }}></span>
                </button>
              );
            })}
          </div>
        </div>
        <div className="og-card-foot">
          <span className="tiny muted">近 12 个月合计 <b className="mono" style={{ color: 'var(--ink)' }}>{money(monthly.reduce((a, m) => a + m.cents, 0))}</b></span>
          <button type="button" className="btn btn--ghost btn--sm" onClick={() => onNav('report')}>打开报表</button>
        </div>
      </Card>

      <Card className="og-cum og-card">
        <div className="card-h">
          <span className="orb" style={{ background: 'var(--mint)', color: '#1E293B' }}><Icon name="layers" size={16} /></span>
          <span className="card-t">累计与跨度</span>
          <span className="card-cap">年度口径</span>
        </div>
        <div className="og-card-body">
          <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column' }}>
            <div className="kv"><span className="tiny muted">本年累计</span><b>{money(yearCents)}</b></div>
            <div className="kv"><span className="tiny muted">去年全年</span><b>{money(lastYearCents)}</b></div>
            <div className="kv"><span className="tiny muted">年度环比</span><b className={yearDelta > 0 ? 'neg' : 'pos'}>{(yearDelta * 100).toFixed(1)}%</b></div>
            <div className="kv"><span className="tiny muted">记录跨度</span><b>{Math.round(spanDays / 30)} 个月 · {expenses.length} 笔</b></div>
            <div className="kv"><span className="tiny muted">历史累计</span><b>{money(totalAll)}</b></div>
          </div>
        </div>
        <div className="og-card-foot og-cum-foot">
          <div className="progress-line"><span>本年 / 去年</span><span>{lastYearCents ? Math.round((yearCents / lastYearCents) * 100) : 0}%</span></div>
          <Bar pct={lastYearCents ? (yearCents / lastYearCents) * 100 : 0} tone="var(--mint)" />
        </div>
      </Card>

      <Card className="og-progress og-card">
        <div className="card-h">
          <span className="card-t">还款进度</span>
          <span className="card-cap">本月计划 {activePlans.length} 个 · 已入账 {doneTodos.length} 笔</span>
          <span style={{ marginLeft: 'auto' }}><Btn size="sm" variant="ghost" icon="right" onClick={() => onNav('settings', { tab: 'plans' })}>管理计划</Btn></span>
        </div>
        <div className="op-row">
          <div className="op-main">
            <div className="split" style={{ alignItems: 'baseline', gap: 8 }}>
              <span className="op-num">{money(paidPlan)}</span>
              <span className="tiny muted">/ {money(planMonthly)}</span>
              <span className={'mono tiny ' + (progressPct > 120 ? 'neg' : 'muted')} style={{ marginLeft: 'auto', color: progressPct > 100 && progressPct <= 120 ? 'var(--warn)' : '' }}>{progressPct.toFixed(0)}%</span>
            </div>
            <div style={{ marginTop: 8 }}>
              <Bar pct={progressPct} tone={progressPct > 120 ? 'var(--danger)' : progressPct > 100 ? 'var(--warn)' : 'var(--accent)'} />
            </div>
            <div className="progress-line"><span>计划固定还款</span><span>已入账 {money(paidPlan)}</span></div>
          </div>
          <div className="op-stats">
            <div className="stat"><span className="stat-v">{activePlans.length}</span><span className="stat-l">进行中计划</span></div>
            <div className="stat"><span className="stat-v">{pending.length}</span><span className="stat-l">待处理待办</span></div>
            <div className="stat"><span className="stat-v">{money(pendingTotal)}</span><span className="stat-l">待办金额</span></div>
          </div>
        </div>
      </Card>
    </div>
  );
}

Object.assign(window, { Dashboard });
