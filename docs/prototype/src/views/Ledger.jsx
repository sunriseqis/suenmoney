/* 流水 LedgerView · 三档：按月 / 按年 / 全部 */

const { useState, useEffect, useMemo, useCallback } = React;

function Ledger({ expenses, plans, todos, onOpenExpense, onNav, initialAnchor }) {
  const [tier, setTier] = useState('month');
  const [anchor, setAnchor] = useState(initialAnchor || TODAY);
  const [query, setQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [catF, setCatF] = useState('');
  const [payF, setPayF] = useState('');
  const [ownerF, setOwnerF] = useState('');
  const [sortBy, setSortBy] = useState('date');
  const [visible, setVisible] = useState(100);
  const [advOpen, setAdvOpen] = useState(false);

  useEffect(() => { if (initialAnchor) { setAnchor(initialAnchor); setTier('month'); } }, [initialAnchor]);

  const monthRange = periodOf('month', anchor);
  const monthList = inRange(expenses, monthRange.start, monthRange.end);
  const monthTotal = sumCents(monthList);
  const prevMonthTotal = sumCents(prevPeriodExpenses(expenses, 'month', anchor));
  const monthDelta = prevMonthTotal ? (monthTotal - prevMonthTotal) / prevMonthTotal : 0;
  const pendingTodos = todos.filter((t) => t.state === 'pending');
  const nextTodo = pendingTodos.slice().sort((a, b) => (a.due_date < b.due_date ? -1 : 1))[0];
  const dueTotal = dueRows(expenses, TODAY).reduce((a, x) => a + x.amount_cents, 0);
  const perDay = Math.round(monthTotal / Math.max(1, TODAY.getDate()));
  const isNarrow = () => typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(max-width: 860px)').matches;

  const match = useCallback((x) => {
    if (query) {
      const q = query.trim();
      const hit = catPath(x.cat_id).includes(q) || (x.note || '').includes(q);
      if (!hit) return false;
    }
    if (catF) {
      const c = CAT_BY_ID[x.cat_id];
      if (!c) return false;
      if ((c.parent || c.id) !== catF) return false;
    }
    if (payF && x.pay_id !== payF) return false;
    if (ownerF && x.owner_id !== ownerF) return false;
    return true;
  }, [query, catF, payF, ownerF]);

  const range = tier === 'month' ? monthRange : periodOf(tier, anchor);
  const scoped = inRange(expenses, range.start, range.end).filter(match);
  const sorted = useMemo(() => {
    const arr = scoped.slice();
    if (sortBy === 'amount') arr.sort((a, b) => b.amount_cents - a.amount_cents);
    else arr.sort((a, b) => (a.spend_date === b.spend_date ? (a.id < b.id ? 1 : -1) : a.spend_date < b.spend_date ? 1 : -1));
    return arr;
  }, [scoped, sortBy]);

  const grouped = useMemo(() => {
    const map = {};
    sorted.slice(0, visible).forEach((x) => {
      map[x.spend_date] = map[x.spend_date] || [];
      map[x.spend_date].push(x);
    });
    return Object.keys(map).map((d) => ({ date: d, rows: map[d], cents: sumCents(map[d]) }));
  }, [sorted, visible]);

  const filterCount = (catF ? 1 : 0) + (payF ? 1 : 0) + (ownerF ? 1 : 0);

  const monthGrid = useMemo(() => {
    return Array.from({ length: 12 }).map((_, i) => {
      const d = new Date(anchor.getFullYear(), i, 1);
      const rows = inRange(scoped, d, endOfMonth(d));
      return { date: d, cents: sumCents(rows), count: rows.length };
    });
  }, [scoped, anchor]);
  const gridMax = Math.max.apply(null, monthGrid.map((m) => m.cents).concat([1]));

  const yearGrid = useMemo(() => {
    const map = {};
    scoped.forEach((x) => {
      const y = x.spend_date.slice(0, 4);
      map[y] = map[y] || { cents: 0, count: 0 };
      map[y].cents += x.amount_cents;
      map[y].count += 1;
    });
    return Object.keys(map).sort().reverse().map((y) => ({ year: y, cents: map[y].cents, count: map[y].count }));
  }, [scoped]);

  const clearFilters = () => { setCatF(''); setPayF(''); setOwnerF(''); setQuery(''); };
  const jumpMonth = (dir) => setAnchor(shiftPeriod('month', anchor, dir));

  return (
    <div className="stack" style={{ gap: 16 }}>
      <div className="mobile-hero mobile-only">
        <div className="mh-head">
          <span className="mh-eyebrow">{monthLabel(anchor)} · 本月支出</span>
          <div className="mh-amt"><span className="cur">¥</span>{moneyPlain(monthTotal)}</div>
          <div className="mh-delta">
            <span className={'delta-pill ' + (monthDelta > 0 ? 'neg' : 'pos')}>
              <Icon name={monthDelta > 0 ? 'trendUp' : 'trendDown'} size={11} />{Math.abs(monthDelta * 100).toFixed(1)}%
            </span>
            <span>较上月 {money(prevMonthTotal)}</span>
          </div>
        </div>

        <div className="mh-facts">
          <div className="mh-fact"><span>日均</span><b>{money(perDay)}</b></div>
          <div className="mh-fact"><span>笔数</span><b>{monthList.length} 笔</b></div>
          <div className="mh-fact"><span>本月要还</span><b>{money(dueTotal)}</b></div>
        </div>

        {nextTodo ? (
          <button type="button" className="mh-plan" onClick={() => onNav('settings', { tab: 'plans' })}>
            <span className="mh-plan-ic"><Icon name="calendar" size={14} /></span>
            <span className="mh-plan-txt">
              <b>{nextTodo.title}</b>
              <span>{pendingTodos.length} 笔待处理 · {urgencyOf(nextTodo.due_date).text}</span>
            </span>
            <span className="mh-plan-amt">{money(nextTodo.amount_cents)}</span>
            <Icon name="right" size={13} />
          </button>
        ) : (
          <div className="mh-plan is-clear">
            <span className="mh-plan-ic"><Icon name="check" size={14} /></span>
            <span className="mh-plan-txt"><b>计划待办已清空</b><span>本月没有待处理的还款</span></span>
          </div>
        )}

        <div className="mh-nav">
          <button type="button" className="mh-btn" onClick={() => onNav('overview')}><Icon name="home" size={13} />概况</button>
          <button type="button" className="mh-btn" onClick={() => onNav('report')}><Icon name="chart" size={13} />报表</button>
          <button type="button" className="mh-btn" onClick={() => onNav('settings')}><Icon name="settings" size={13} />设置</button>
        </div>
      </div>

      <Card>
        <div className={'ledger-toolbar' + (advOpen ? ' is-open' : '')}>
          <div className="lt-search" onClick={() => { if (isNarrow()) setAdvOpen(true); }}>
            <div className="search-wrap">
              <Icon name="search" size={15} />
              <input
                className="input input--search"
                placeholder="搜索备注或分类"
                value={query}
                onChange={(e) => { setQuery(e.target.value); setVisible(100); }}
                onFocus={() => { if (isNarrow()) setAdvOpen(true); }}
                aria-label="搜索流水"
              />
            </div>
            {advOpen ? (
              <button
                type="button"
                className="btn btn--ghost btn--sm lt-collapse"
                onClick={(e) => { e.stopPropagation(); setAdvOpen(false); }}
              >
                收起
              </button>
            ) : null}
          </div>

          <div className="lt-adv">
            <Seg
              label="流水档位"
              value={tier}
              onChange={(v) => { setTier(v); setVisible(100); }}
              options={[{ value: 'month', label: '按月' }, { value: 'year', label: '按年' }, { value: 'all', label: '全部' }]}
            />
            <div className="period-nav">
              <IconBtn icon="left" label="上一期间" onClick={() => setAnchor(shiftPeriod(tier === 'all' ? 'year' : tier, anchor, -1))} disabled={tier === 'all'} />
              <span className="period-label">{periodLabel(tier, anchor)}</span>
              <IconBtn icon="right" label="下一期间" onClick={() => setAnchor(shiftPeriod(tier === 'all' ? 'year' : tier, anchor, 1))} disabled={tier === 'all'} />
            </div>
            <button type="button" className={'btn btn--sm' + (filterCount ? ' btn--primary' : '')} onClick={() => setShowFilters((v) => !v)}>
              <Icon name="filter" size={13} /> 筛选{filterCount ? ' · ' + filterCount : ''}
            </button>
            <div className="seg" style={{ marginLeft: 'auto' }}>
              <button type="button" className={'seg-btn' + (sortBy === 'date' ? ' is-on' : '')} onClick={() => setSortBy('date')}>按日期</button>
              <button type="button" className={'seg-btn' + (sortBy === 'amount' ? ' is-on' : '')} onClick={() => setSortBy('amount')}>按金额</button>
            </div>
          </div>
        </div>

        <div className="ledger-sum">
          <span className="mono">{periodLabel(tier, anchor)}</span>
          <span className="ls-sep">·</span>
          <span>{sorted.length} 笔</span>
          <span className="ls-sep">·</span>
          <span>合计 <b>{money(sumCents(sorted))}</b></span>
          {filterCount || query ? <span className="tiny muted" style={{ marginLeft: 'auto' }}>已筛选</span> : null}
        </div>

        {showFilters ? (
          <div className="filter-row" style={{ marginTop: 12, paddingTop: 12, borderTop: '1px dashed var(--line)' }}>
            <div className="filter-group">
              <span className="filter-l">分类</span>
              <Chip active={!catF} onClick={() => setCatF('')}>全部</Chip>
              {ROOT_CATS.map((c) => (
                <Chip key={c.id} active={catF === c.id} dot={CAT_COLORS[c.color]} onClick={() => setCatF(catF === c.id ? '' : c.id)}>{c.name}</Chip>
              ))}
            </div>
            <div className="filter-group">
              <span className="filter-l">支付</span>
              {PAYS.map((p) => (
                <Chip key={p.id} active={payF === p.id} onClick={() => setPayF(payF === p.id ? '' : p.id)}>{p.name}</Chip>
              ))}
            </div>
            <div className="filter-group">
              <span className="filter-l">记录人</span>
              {USERS.map((u) => (
                <Chip key={u.id} active={ownerF === u.id} dot={u.color} onClick={() => setOwnerF(ownerF === u.id ? '' : u.id)}>{u.name}</Chip>
              ))}
              {filterCount || query ? <Btn size="sm" variant="ghost" icon="close" onClick={clearFilters}>清除</Btn> : null}
            </div>
          </div>
        ) : null}
      </Card>

      {tier === 'month' ? (
        <Card>
          <div className="card-h">
            <span className="card-t">流水明细</span>
            <span className="card-cap">{sorted.length} 笔 · 合计 {money(sumCents(sorted))}</span>
          </div>
          <div className="desktop-only">
            {grouped.length === 0 ? <Empty icon="search">没有符合条件的流水</Empty> : (
              <table className="tbl">
                <thead>
                  <tr>
                    <th style={{ width: 104 }}>消费日期</th>
                    <th style={{ width: 150 }}>分类</th>
                    <th>备注</th>
                    <th style={{ width: 112 }}>账期</th>
                    <th style={{ width: 82 }}>记录人</th>
                    <th style={{ width: 100 }}>支付方式</th>
                    <th style={{ width: 104 }} className="th-r">金额</th>
                  </tr>
                </thead>
                <tbody>
                  {grouped.map((g) => (
                    <React.Fragment key={g.date}>
                      <tr style={{ cursor: 'default' }} aria-hidden="true">
                        <td colSpan="7" style={{ padding: '12px 10px 6px', borderBottom: 0 }}>
                          <div className="date-cap" style={{ padding: 0 }}>
                            <Icon name="calendar" size={12} />{ledgerDate(g.date)}
                            <span className="sum mono">{money(g.cents)}</span>
                          </div>
                        </td>
                      </tr>
                      {g.rows.map((x) => {
                        const pay = PAY_BY_ID[x.pay_id];
                        return (
                          <tr key={x.id} onClick={() => onOpenExpense(x)}>
                            <td className="mono tiny muted">{x.spend_date.slice(5)}</td>
                            <td>
                              <div className="cat-cell">
                                <CatIcon catId={x.cat_id} size={30} />
                                <div className="cat-txt">
                                  <div className="cat-name">{catName(x.cat_id)}</div>
                                  <div className="cat-sub">{catPath(x.cat_id).split(' / ')[0]}</div>
                                </div>
                              </div>
                            </td>
                            <td>
                              <div className="split" style={{ gap: 6 }}>
                                <span>{x.note || '—'}</span>
                                {x.amount_cents < 0 ? <Tag tone="danger">退款</Tag> : null}
                                {x.installment ? <Tag tone="accent">{x.installment.periods} 期</Tag> : null}
                              </div>
                            </td>
                            <td className="mono tiny">
                              {pay && pay.billing ? (
                                <span>{x.repayment_date.slice(5)} <span className="muted">还</span></span>
                              ) : <span className="muted">即时</span>}
                            </td>
                            <td className="tiny">{USERS.find((u) => u.id === x.owner_id).name}</td>
                            <td className="tiny muted">{pay ? pay.name : '—'}</td>
                            <td className={'num ' + (x.amount_cents < 0 ? 'pos' : '')}>{signedMoney(x.amount_cents)}</td>
                          </tr>
                        );
                      })}
                    </React.Fragment>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          <div className="m-list mobile-only">
            {grouped.length === 0 ? <Empty icon="search">没有符合条件的流水</Empty> : grouped.map((g) => (
              <React.Fragment key={g.date}>
                <div className="date-cap">{ledgerDate(g.date)}<span className="sum mono">{money(g.cents)}</span></div>
                {g.rows.map((x) => (
                  <button type="button" className="m-row" key={x.id} onClick={() => onOpenExpense(x)}>
                    <CatIcon catId={x.cat_id} size={34} />
                    <div className="m-row-main">
                      <div className="m-row-t">
                        <span>{catName(x.cat_id)}</span>
                        {x.amount_cents < 0 ? <Tag tone="danger">退款</Tag> : null}
                        {x.installment ? <Tag tone="accent">{x.installment.periods} 期</Tag> : null}
                      </div>
                      <div className="m-row-s">
                        <span>{x.note || '—'}</span>
                        <span>·</span>
                        <span>{PAY_BY_ID[x.pay_id].name}</span>
                        <span>·</span>
                        <span>{USERS.find((u) => u.id === x.owner_id).name}</span>
                      </div>
                    </div>
                    <div className="row-end">
                      <div className={'row-amt ' + (x.amount_cents < 0 ? 'pos' : '')}>{signedMoney(x.amount_cents)}</div>
                      <div className="tiny muted mono">{PAY_BY_ID[x.pay_id].billing ? x.repayment_date.slice(5) + ' 还' : '即时'}</div>
                    </div>
                  </button>
                ))}
              </React.Fragment>
            ))}
          </div>

          <div className="split" style={{ marginTop: 14 }}>
            {sorted.length > visible ? (
              <Btn variant="ghost" icon="down" onClick={() => setVisible((v) => v + 100)}>加载更多（{sorted.length - visible}）</Btn>
            ) : <span className="tiny muted mono">已到底 · 每段 100 笔</span>}
            <Btn size="sm" variant="ghost" icon="left" style={{ marginLeft: 'auto' }} onClick={() => jumpMonth(-1)}>查看上月</Btn>
            <Btn size="sm" variant="ghost" icon="right" onClick={() => jumpMonth(1)}>查看下月</Btn>
          </div>
        </Card>
      ) : null}

      {tier === 'year' ? (
        <Card>
          <div className="cal-head">
            <span className="card-t">{anchor.getFullYear()} 年 · 12 个月</span>
            <span className="card-cap">点击月份下钻</span>
            <span style={{ marginLeft: 'auto' }} className="mono tiny muted">合计 {money(monthGrid.reduce((a, m) => a + m.cents, 0))}</span>
          </div>
          <div className="cal-year-grid">
            {monthGrid.map((m) => (
              <button
                type="button"
                className="year-cell"
                key={m.date.getTime()}
                onClick={() => { setAnchor(m.date); setTier('month'); }}
                style={{ borderColor: sameMonth(m.date, TODAY) ? 'var(--line-2)' : '' }}
              >
                <div className="split" style={{ gap: 5 }}>
                  <span className="y-m">{m.date.getMonth() + 1} 月</span>
                  {sameMonth(m.date, TODAY) ? <Tag tone="accent">本月</Tag> : null}
                  <span style={{ marginLeft: 'auto' }} className="tiny muted mono">{m.count} 笔</span>
                </div>
                <div className="y-v">{money(m.cents)}</div>
                <div className="bar" style={{ height: 5, marginTop: 2 }}>
                  <div className="bar-fill" style={{ width: Math.round((m.cents / gridMax) * 100) + '%' }}></div>
                </div>
              </button>
            ))}
          </div>
        </Card>
      ) : null}

      {tier === 'all' ? (
        <Card>
          <div className="cal-head">
            <span className="card-t">全部记录</span>
            <span className="card-cap">一格一年 · 点击年份下钻</span>
            <span style={{ marginLeft: 'auto' }} className="mono tiny muted">{expenses.length} 笔 / {money(sumCents(expenses))}</span>
          </div>
          <div className="cal-year-grid">
            {yearGrid.map((y) => (
              <button type="button" className="year-cell" key={y.year} onClick={() => { setAnchor(new Date(Number(y.year), 0, 1)); setTier('year'); }}>
                <div className="split"><span className="y-m">{y.year}</span><span style={{ marginLeft: 'auto' }} className="tiny muted mono">{y.count} 笔</span></div>
                <div className="y-v">{money(y.cents)}</div>
                <div className="bar" style={{ height: 5, marginTop: 2 }}>
                  <div className="bar-fill" style={{ width: Math.round((y.cents / Math.max.apply(null, yearGrid.map((g) => g.cents).concat([1]))) * 100) + '%' }}></div>
                </div>
              </button>
            ))}
          </div>
          <div className="hint" style={{ marginTop: 12 }}>「全部」档不设期间切换，统计口径为历史全量；切换到「按年」可看单一年份的 12 月格。</div>
        </Card>
      ) : null}
    </div>
  );
}

Object.assign(window, { Ledger });
