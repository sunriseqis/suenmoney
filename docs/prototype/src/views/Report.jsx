/* 报表 ReportView + 年度报告 AnnualReportView */

const { useState, useMemo } = React;

function Report({ expenses, onOpenAnnual }) {
  const [period, setPeriod] = useState('month');
  const [anchor, setAnchor] = useState(TODAY);
  const [dim, setDim] = useState('cat');

  const range = periodOf(period, anchor);
  const list = inRange(expenses, range.start, range.end);
  const total = sumCents(list);
  const prevList = prevPeriodExpenses(expenses, period, anchor);
  const prevTotal = sumCents(prevList);
  const delta = prevTotal ? (total - prevTotal) / prevTotal : 0;
  const avg = Math.round(total / Math.max(1, list.length));
  const biggest = list.reduce((a, b) => (b.amount_cents > a.amount_cents ? b : a), { amount_cents: 0 });
  const daysPassed = sameMonth(anchor, TODAY) && period === 'month' ? TODAY.getDate() : Math.max(1, Math.round((range.end - range.start) / 86400000) + 1);
  const perDay = Math.round(total / daysPassed);

  const cats = rootTotals(list);
  const prevCats = rootTotals(prevList);
  const prevMap = {};
  prevCats.forEach((c) => { prevMap[c.cat.id] = c.cents; });

  const donutData = cats.slice(0, 7).map((c) => ({ name: c.cat.name, value: c.cents, color: CAT_COLORS[c.cat.color] }));
  const rest = cats.slice(7).reduce((a, c) => a + c.cents, 0);
  if (rest > 0) donutData.push({ name: '其他', value: rest, color: '#94A3B8' });

  const weekday = weekdayDist(list);
  const wdMax = Math.max.apply(null, weekday.concat([1]));

  const payRows = payTotals(list).map((p) => ({ name: p.pay.name, cents: p.cents, color: PAY_BY_ID[p.pay.id].billing ? 'var(--pink)' : 'var(--sky)' }));
  const ownerRows = ownerTotals(list).map((o) => ({ name: o.user.name, cents: o.cents, color: o.user.color }));

  const movers = cats.map((c) => {
    const p = prevMap[c.cat.id] || 0;
    return { cat: c.cat, now: c.cents, prev: p, diff: c.cents - p, pct: p ? (c.cents - p) / p : 1 };
  }).filter((m) => m.prev > 0 || m.now > 0).sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff)).slice(0, 5);

  const repay = useMemo(() => {
    const out = [];
    for (let i = 5; i >= 0; i--) {
      const d = new Date(TODAY.getFullYear(), TODAY.getMonth() - i, 1);
      const cents = sumCents(expenses.filter((x) => x.repayment_date && sameMonth(parseYmd(x.repayment_date), d) && PAY_BY_ID[x.pay_id] && PAY_BY_ID[x.pay_id].billing));
      out.push({ date: d, cents });
    }
    return out;
  }, [expenses]);
  const repayMax = Math.max.apply(null, repay.map((r) => r.cents).concat([1]));

  const top = cats[0];
  const refunds = list.filter((x) => x.amount_cents < 0);
  const refundCents = refunds.reduce((a, x) => a + x.amount_cents, 0);
  const installments = list.filter((x) => x.installment);
  const installmentLeft = installments.reduce((a, x) => a + x.amount_cents, 0);

  const dimRows = dim === 'cat'
    ? cats.slice(0, 8).map((c) => ({ name: c.cat.name, cents: c.cents, color: CAT_COLORS[c.cat.color], count: c.count }))
    : dim === 'pay'
      ? payRows
      : dim === 'owner'
        ? ownerRows
        : weekday.map((cents, i) => ({ name: '周' + '日一二三四五六'[i], cents, color: 'var(--accent)', count: null }));
  const dimMax = Math.max.apply(null, dimRows.map((r) => r.cents).concat([1]));

  return (
    <div className="stack" style={{ gap: 16 }}>
      <Card className="report-head">
        <div className="toolbar">
          <Seg
            label="报表档位"
            value={period}
            onChange={setPeriod}
            options={[{ value: 'month', label: '月' }, { value: 'year', label: '年' }, { value: 'all', label: '全部' }]}
          />
          <div className="period-nav">
            <IconBtn icon="left" label="上一期间" onClick={() => setAnchor(shiftPeriod(period === 'all' ? 'year' : period, anchor, -1))} disabled={period === 'all'} />
            <span className="period-label">{periodLabel(period, anchor)}</span>
            <IconBtn icon="right" label="下一期间" onClick={() => setAnchor(shiftPeriod(period === 'all' ? 'year' : period, anchor, 1))} disabled={period === 'all'} />
          </div>
          <span className="spacer" style={{ marginLeft: 'auto' }}></span>
          <Btn size="sm" variant="ghost" icon="spark" onClick={() => onOpenAnnual(anchor.getFullYear())}>{anchor.getFullYear()} 年度报告</Btn>
        </div>
        <div className="report-facts">
          <div className="rf-main">
            <span className="tiny muted mono">期间支出</span>
            <b className="rf-num">{money(total)}</b>
          </div>
          <div className="rf-items">
            <span className={'delta-pill ' + (delta > 0 ? 'neg' : 'pos')}>
              <Icon name={delta > 0 ? 'trendUp' : 'trendDown'} size={11} />{(delta * 100).toFixed(1)}%
            </span>
            <span className="rf-i">对比 <b>{money(prevTotal)}</b></span>
            <span className="rf-i">日均 <b>{money(perDay)}</b></span>
          </div>
        </div>
      </Card>

      <Card className="report-compose">
        <div className="card-h">
          <span className="card-t">支出构成</span>
          <span className="card-cap">分类 / 支付 / 记录人 / 节奏</span>
          <span className="chips" style={{ marginLeft: 'auto' }}>
            {[['cat', '分类'], ['pay', '支付'], ['owner', '记录人'], ['week', '节奏']].map(([k, l]) => (
              <Chip key={k} active={dim === k} onClick={() => setDim(k)}>{l}</Chip>
            ))}
          </span>
        </div>
        <div className="compose-view" data-dim={dim}>
          <div className="compose-visual">
            {dim === 'cat' ? (
              <Donut data={donutData} centerLabel="合计" centerValue={money(total)} />
            ) : dim === 'week' ? (
              <div className="week-bars">
                {weekday.map((c, i) => (
                  <div className="week-bar" key={i}>
                    <em className="mono">{c ? wan(c) : ''}</em>
                    <i style={{ height: Math.max(3, (c / wdMax) * 100) + '%' }}></i>
                    <span>{'日一二三四五六'[i]}</span>
                  </div>
                ))}
              </div>
            ) : (
              <div className="compose-stack">
                {dimRows.map((r, i) => (
                  <div className="compose-stack-row" key={i}>
                    <span className="cs-n">{r.name}</span>
                    <i style={{ width: (r.cents / dimMax) * 100 + '%', background: r.color }}></i>
                    <b className="mono">{money(r.cents)}</b>
                  </div>
                ))}
                {!dimRows.length ? <Empty icon="chart">暂无数据</Empty> : null}
              </div>
            )}
          </div>
          <div className="compose-list">
            {dim === 'cat' ? donutData.map((d, i) => (
              <div className="legend-row" key={i}>
                <i style={{ background: d.color }}></i>
                <span className="l-n">{d.name}</span>
                <span className="l-v">{money(d.value)}</span>
                <span className="l-p">{Math.round((d.value / Math.max(1, total)) * 100)}%</span>
              </div>
            )) : dim === 'week' ? (
              <div className="insight" style={{ boxShadow: 'none', border: 0, padding: 0, background: 'transparent' }}>
                周{'日一二三四五六'[weekday.indexOf(Math.max.apply(null, weekday))]} 是这期间花得最多的一天，合计 {money(Math.max.apply(null, weekday))}；
                单笔均值 {money(avg)}，共 {list.length} 笔。
              </div>
            ) : dimRows.map((r, i) => (
              <div className="legend-row" key={i}>
                <i style={{ background: r.color }}></i>
                <span className="l-n">{r.name}</span>
                <span className="l-v">{money(r.cents)}</span>
                <span className="l-p">{Math.round((r.cents / Math.max(1, total)) * 100)}%</span>
              </div>
            ))}
            {!dimRows.length ? <Empty icon="chart">这个期间还没有构成数据</Empty> : null}
          </div>
        </div>
      </Card>

      <div className="g-side">
        <Card>
          <div className="card-h">
            <span className="card-t">涨跌榜</span>
            <span className="card-cap">分类环比 · 按差额排序</span>
          </div>
          <div className="mover-grid">
            {movers.map((m) => (
              <div className="mover" key={m.cat.id}>
                <CatIcon catId={m.cat.id} size={30} />
                <div style={{ minWidth: 0, flex: '1 1 auto' }}>
                  <div className="mover-t">{m.cat.name}</div>
                  <div className="mover-s">{money(m.now)} <span className="muted">/ 上期 {money(m.prev)}</span></div>
                </div>
                <div className={'row-end mono tiny ' + (m.diff > 0 ? 'neg' : 'pos')}>
                  {m.diff > 0 ? '+' : '-'}{money(Math.abs(m.diff))}
                  <div className="mover-s" style={{ color: 'inherit', opacity: 0.75 }}>{m.prev ? (m.pct * 100).toFixed(0) + '%' : '新增'}</div>
                </div>
              </div>
            ))}
          </div>
          {!movers.length ? <Empty icon="chart">该期间没有可对比的分类</Empty> : null}
          <div className="report-note">
            {total === 0
              ? '这个期间还没有记录，记一笔之后这里会自动生成结论。'
              : (top ? '头号开销是' + top.cat.name + '，占 ' + Math.round((top.cents / total) * 100) + '%；' : '') +
                (prevTotal ? '整体' + (delta >= 0 ? '多花 ' : '少花 ') + money(Math.abs(total - prevTotal)) + '（' + Math.abs(delta * 100).toFixed(1) + '%）。' : '这是第一段可对比的期间。')}
          </div>
        </Card>

        <div className="stack">
          <Card>
            <div className="card-h">
              <span className="card-t">还款节奏</span>
              <span className="card-cap">近 6 个月 · 按账期</span>
            </div>
            <div className="repay-steps">
              {repay.map((r) => (
                <div className="repay-col" key={r.date.getTime()}>
                  <span className="mono" style={{ fontSize: 8.5 }}>{wan(r.cents)}</span>
                  <i style={{ height: Math.max(4, (r.cents / repayMax) * 100) + '%' }}></i>
                  <span>{r.date.getMonth() + 1}月</span>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <div className="card-h">
              <span className="card-t">退款与分期</span>
              <span className="card-cap">冲销口径</span>
            </div>
            <div className="split" style={{ alignItems: 'flex-start', gap: 18, marginTop: 4 }}>
              <div className="stat">
                <span className="stat-v">{refunds.length} 笔</span>
                <span className="stat-l">退款冲销 {refundCents ? money(refundCents) : '—'}</span>
              </div>
              <div className="stat">
                <span className="stat-v">{installments.length} 笔</span>
                <span className="stat-l">分期消费 {installmentLeft ? money(installmentLeft) : '—'}</span>
              </div>
              <div className="stat">
                <span className="stat-v">{money(biggest.amount_cents || 0)}</span>
                <span className="stat-l">最大单笔{biggest.note ? ' · ' + biggest.note : ''}</span>
              </div>
            </div>
          </Card>
        </div>
      </div>

      <button type="button" className="report-banner" onClick={() => onOpenAnnual(anchor.getFullYear())}>
        <span style={{ display: 'grid', placeItems: 'center', width: 42, height: 42, borderRadius: 12, background: 'rgba(255,255,255,0.22)', border: '2px solid rgba(255,255,255,0.5)' }}>
          <Icon name="spark" size={20} />
        </span>
        <div>
          <div className="rb-t">{anchor.getFullYear()} 年度报告已生成</div>
          <div className="rb-s">年度全貌 · 年度之最 · 单笔最贵 · 最集中月份 · 12 月走势画卷</div>
        </div>
        <span className="spacer" style={{ marginLeft: 'auto' }}></span>
        <Icon name="right" size={18} />
      </button>
    </div>
  );
}

function AnnualReport({ expenses, year, onBack }) {
  const list = expenses.filter((x) => x.spend_date.slice(0, 4) === String(year));
  const total = sumCents(list);
  const months = Array.from({ length: 12 }).map((_, i) => {
    const d = new Date(year, i, 1);
    const rows = inRange(list, d, endOfMonth(d));
    return { month: i + 1, cents: sumCents(rows), count: rows.length };
  });
  const max = Math.max.apply(null, months.map((m) => m.cents).concat([1]));
  const peak = months.reduce((a, b) => (b.cents > a.cents ? b : a), months[0]);
  const biggest = list.reduce((a, b) => (b.amount_cents > a.amount_cents ? b : a), { amount_cents: 0, note: '—', spend_date: TODAY_KEY, cat_id: 'c12' });
  const cats = rootTotals(list);
  const topCat = cats[0];
  const avg = Math.round(total / Math.max(1, months.filter((m) => m.cents).length));
  const prevYearTotal = sumCents(expenses.filter((x) => x.spend_date.slice(0, 4) === String(year - 1)));
  const delta = prevYearTotal ? (total - prevYearTotal) / prevYearTotal : 0;

  return (
    <div className="stack" style={{ gap: 16 }}>
      <div className="split">
        <Btn variant="ghost" icon="left" onClick={onBack}>返回报表</Btn>
        <span className="tiny muted mono">年度报告 / ANNUAL SUMMARY</span>
      </div>

      <div className="annual-hero">
        <div className="hero-eyebrow"><Icon name="spark" size={12} />{year} 年度全貌</div>
        <div className="annual-year">{year}</div>
        <div className="annual-total">{money(total)}</div>
        <div className="hero-delta">
          <span className={'delta-pill ' + (delta > 0 ? 'neg' : 'pos')}>
            <Icon name={delta > 0 ? 'trendUp' : 'trendDown'} size={11} />{(delta * 100).toFixed(1)}%
          </span>
          <span>较 {year - 1} 年 {money(prevYearTotal)}</span>
        </div>
        <div className="hero-metrics">
          <Stat label="全年笔数" value={list.length + ' 笔'} />
          <Stat label="有记录月份均值" value={money(avg)} />
          <Stat label="最高月" value={peak.month + ' 月 · ' + wan(peak.cents)} />
        </div>
      </div>

      <div className="g-side">
        <Card>
          <div className="card-h">
            <span className="card-t">12 月走势画卷</span>
            <span className="card-cap">每月支出</span>
          </div>
          <div className="annual-months">
            {months.map((m) => (
              <div className="annual-col" key={m.month} title={money(m.cents)}>
                <span className="mono" style={{ fontSize: 8 }}>{wan(m.cents)}</span>
                <i style={{ height: Math.max(3, (m.cents / max) * 100) + '%' }}></i>
                <span>{m.month}</span>
              </div>
            ))}
          </div>
        </Card>

        <div className="stack">
          <Card>
            <div className="card-h"><span className="card-t">年度之最</span><span className="card-cap">THE EXTREMES</span></div>
            <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <div className="superlative">
                <span className="s-l">单笔最贵</span>
                <span className="s-v">{money(biggest.amount_cents)}</span>
                <span className="tiny muted">{biggest.spend_date} · {catPath(biggest.cat_id)}{biggest.note ? ' · ' + biggest.note : ''}</span>
              </div>
              <div className="superlative">
                <span className="s-l">最集中月份</span>
                <span className="s-v">{peak.month} 月 · {money(peak.cents)}</span>
                <span className="tiny muted">占全年 {Math.round((peak.cents / Math.max(1, total)) * 100)}%</span>
              </div>
              <div className="superlative">
                <span className="s-l">头号分类</span>
                <span className="s-v">{topCat ? topCat.cat.name : '—'} · {topCat ? money(topCat.cents) : '—'}</span>
                <span className="tiny muted">占全年 {topCat ? Math.round((topCat.cents / Math.max(1, total)) * 100) : 0}% · {topCat ? topCat.count : 0} 笔</span>
              </div>
            </div>
          </Card>
        </div>
      </div>

      <Card>
        <div className="card-h"><span className="card-t">年度分类构成</span><span className="card-cap">12 个一级分类</span></div>
        <div className="legend" style={{ gap: 9 }}>
          {cats.map((c) => (
            <div className="legend-row" key={c.cat.id}>
              <i style={{ background: CAT_COLORS[c.cat.color] }}></i>
              <span className="l-n">{c.cat.name}</span>
              <span className="l-v">{money(c.cents)}</span>
              <span className="l-p">{Math.round((c.cents / Math.max(1, total)) * 100)}%</span>
            </div>
          ))}
        </div>
      </Card>
    </div>
  );
}

Object.assign(window, { Report, AnnualReport });
