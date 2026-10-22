/* 计划与还款 · 设置内精简面板（管理计划 + 待办清单） */

const { useState, useRef } = React;

function PlansPanel({ plans, todos, onSavePlan, onEndPlan, onPrepay, onTodoAction, onNav }) {
  const [todoFilter, setTodoFilter] = useState('pending');
  const [editing, setEditing] = useState(null);
  const [prepay, setPrepay] = useState(null);
  const [ending, setEnding] = useState(null);
  const [swipe, setSwipe] = useState({ id: null, dx: 0 });
  const swipeStart = useRef(null);
  const [draft, setDraft] = useState({ name: '', kind: '房贷', amount: 0, dueDay: 5, total: 12, auto: true, pay_id: 'p6' });

  const openNew = () => {
    setDraft({ name: '', kind: '房贷', amount: 0, dueDay: 5, total: 12, auto: true, pay_id: 'p6' });
    setEditing({ isNew: true });
  };
  const openEdit = (p) => {
    setDraft({ name: p.name, kind: p.kind, amount: p.amount_cents / 100, dueDay: p.dueDay, total: p.total, auto: p.auto, pay_id: p.pay_id });
    setEditing(p);
  };
  const submit = () => {
    if (!draft.name.trim() || !draft.amount) return;
    onSavePlan({
      id: editing.isNew ? null : editing.id,
      name: draft.name.trim(),
      kind: draft.kind,
      amount_cents: Math.round(Number(draft.amount) * 100),
      dueDay: Number(draft.dueDay),
      total: Number(draft.total),
      auto: !!draft.auto,
      pay_id: draft.pay_id
    });
    setEditing(null);
  };

  const active = plans.filter((p) => p.active);
  const pending = todos.filter((t) => t.state === 'pending');
  const monthly = active.reduce((a, p) => a + p.amount_cents, 0);
  const visibleTodos = todos.filter((t) => {
    if (todoFilter === 'pending') return t.state === 'pending';
    if (todoFilter === 'done') return t.state === 'done' || t.state === 'ack';
    if (todoFilter === 'skip') return t.state === 'skipped';
    return true;
  }).sort((a, b) => (a.due_date < b.due_date ? -1 : 1));

  return (
    <div className="stack" style={{ gap: 14 }}>
      <Card>
        <div className="card-h">
          <span className="orb"><Icon name="calendar" size={16} /></span>
          <span className="card-t">计划与还款</span>
          <span className="card-cap">{active.length} 个进行中 · 每月固定 {money(monthly)}</span>
          <span style={{ marginLeft: 'auto' }}><Btn size="sm" variant="primary" icon="plus" onClick={openNew}>新建计划</Btn></span>
        </div>
        <div className="plan-list">
          {plans.map((p) => {
            const pct = Math.round((p.paid / p.total) * 100);
            return (
              <div className={'plan-line' + (p.active ? '' : ' is-off')} key={p.id}>
                <div className="plan-line-main">
                  <div className="split" style={{ gap: 6 }}>
                    <span className="plan-kind">{p.kind}</span>
                    <span className="plan-name">{p.name}</span>
                    {p.active ? (p.auto ? <Tag tone="accent">自动</Tag> : <Tag tone="dash">手动</Tag>) : <Tag tone="danger">已终止</Tag>}
                  </div>
                  <div className="plan-line-meta">
                    每月 {p.dueDay} 日 · {PAY_BY_ID[p.pay_id].name} · 第 {p.paid}/{p.total} 期 · 剩余约 {money((p.total - p.paid) * p.amount_cents)}
                  </div>
                  <div style={{ marginTop: 6 }}><Bar pct={pct} tone={pct > 90 ? 'var(--pink)' : 'var(--accent)'} /></div>
                </div>
                <div className="plan-line-amt">
                  <b>{money(p.amount_cents)}</b>
                  <span>每期</span>
                </div>
                <div className="plan-line-acts">
                  <IconBtn icon="edit" label="改计划" onClick={() => openEdit(p)} />
                  <IconBtn icon="refresh" label="提前还款" onClick={() => setPrepay(p)} disabled={!p.active} />
                  <IconBtn icon="close" label="终止计划" onClick={() => setEnding(p)} disabled={!p.active} />
                </div>
              </div>
            );
          })}
          {!plans.length ? <Empty icon="calendar">还没有计划，新建一个房贷 / 车贷 / 分期</Empty> : null}
        </div>
      </Card>

      <Card>
        <div className="card-h">
          <span className="card-t">还款待办</span>
          <span className="card-cap">按还款日生成</span>
          <span className="chips" style={{ marginLeft: 'auto' }}>
            {[['pending', '待处理'], ['done', '已入账'], ['skip', '已忽略'], ['all', '全部']].map(([k, l]) => (
              <Chip key={k} active={todoFilter === k} onClick={() => setTodoFilter(k)}>{l}</Chip>
            ))}
          </span>
        </div>
        <div className="plan-todo-list">
          {visibleTodos.map((t) => {
            const done = t.state === 'done' || t.state === 'ack';
            const u = urgencyOf(t.due_date);
            return (
              <div className={'todo-swipe' + (swipe.id === t.id && swipe.dx < 0 ? ' is-dragging' : '')} key={t.id}>
                <div className="todo-swipe-bg" aria-hidden="true"><Icon name="close" size={13} />松开忽略</div>
                <div
                  className={'todo-row' + (done ? ' is-done' : '') + (t.state === 'skipped' ? ' is-skip' : '')}
                  style={{ transform: swipe.id === t.id && swipe.dx ? 'translateX(' + swipe.dx + 'px)' : undefined }}
                  onPointerDown={(e) => {
                    if (t.state !== 'pending' || e.pointerType !== 'touch') return;
                    swipeStart.current = { id: t.id, x: e.clientX, w: e.currentTarget.getBoundingClientRect().width || 320 };
                  }}
                  onPointerMove={(e) => {
                    if (!swipeStart.current || swipeStart.current.id !== t.id) return;
                    const dx = Math.min(0, e.clientX - swipeStart.current.x);
                    setSwipe({ id: t.id, dx: Math.max(-160, dx) });
                  }}
                  onPointerUp={() => {
                    if (!swipeStart.current || swipeStart.current.id !== t.id) return;
                    if (swipe.dx <= -0.6 * swipeStart.current.w) onTodoAction(t, 'skip');
                    setSwipe({ id: null, dx: 0 });
                    swipeStart.current = null;
                  }}
                  onPointerCancel={() => { setSwipe({ id: null, dx: 0 }); swipeStart.current = null; }}
                >
                  <span className={'todo-mark is-' + (done ? 'done' : t.state === 'skipped' ? 'skip' : u.level)}></span>
                  <div className="todo-body">
                    <div className="todo-t">
                      {t.title}
                      {t.state === 'skipped' ? <Tag tone="warn">已忽略</Tag> : null}
                    </div>
                    <div className="todo-s">{t.due_date} 到期 · {done ? '已处理' : u.text}</div>
                  </div>
                  <div className="row-amt">{money(t.amount_cents)}</div>
                  <div className="todo-acts">
                    {t.state === 'pending' ? (
                      <React.Fragment>
                        <Btn size="sm" variant="primary" icon={t.kind === 'auto' ? 'check' : 'download'} onClick={() => onTodoAction(t, t.kind === 'auto' ? 'ack' : 'confirm')}>{t.kind === 'auto' ? '确认' : '入账'}</Btn>
                        <Btn size="sm" variant="ghost" icon="close" onClick={() => onTodoAction(t, 'skip')}>忽略</Btn>
                      </React.Fragment>
                    ) : null}
                    {done ? <Btn size="sm" variant="ghost" icon="undo" onClick={() => onTodoAction(t, 'revert')}>撤销</Btn> : null}
                    {t.state === 'skipped' ? <Btn size="sm" variant="ghost" icon="refresh" onClick={() => onTodoAction(t, 'restore')}>恢复</Btn> : null}
                  </div>
                </div>
              </div>
            );
          })}
          {!visibleTodos.length ? <Empty icon="check">这个筛选下没有待办</Empty> : null}
        </div>
        <div className="hint" style={{ marginTop: 10 }}>
          待办提醒仍以概况页为主；这里只做清单查看与处理，移动端可左滑忽略。
        </div>
      </Card>

      <Modal
        open={!!editing}
        onClose={() => setEditing(null)}
        title={editing && editing.isNew ? '新建计划' : '修改计划'}
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setEditing(null)}>取消</Btn><Btn variant="primary" onClick={submit}>{editing && editing.isNew ? '创建' : '保存'}</Btn></React.Fragment>}
      >
        <div className="g2">
          <label className="field"><span className="field-l">计划名称</span>
            <input className="input" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="例如：房贷" />
          </label>
          <label className="field"><span className="field-l">类型</span>
            <select className="input" value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value })}>
              <option>房贷</option><option>车贷</option><option>分期</option>
            </select>
          </label>
          <label className="field"><span className="field-l">每期金额（元）</span>
            <input className="input" type="number" value={draft.amount} onChange={(e) => setDraft({ ...draft, amount: e.target.value })} />
          </label>
          <label className="field"><span className="field-l">还款日</span>
            <input className="input" type="number" min="1" max="28" value={draft.dueDay} onChange={(e) => setDraft({ ...draft, dueDay: e.target.value })} />
          </label>
          <label className="field"><span className="field-l">总期数</span>
            <input className="input" type="number" value={draft.total} onChange={(e) => setDraft({ ...draft, total: e.target.value })} />
          </label>
          <label className="field"><span className="field-l">支付方式</span>
            <select className="input" value={draft.pay_id} onChange={(e) => setDraft({ ...draft, pay_id: e.target.value })}>
              {PAYS.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
            </select>
          </label>
        </div>
        <div className="set-row">
          <span className="set-ic"><Icon name="refresh" size={15} /></span>
          <div className="set-body"><div className="set-t">到期自动入账</div><div className="set-s">开启后到期自动结算为一笔支出，也可在清单里手动确认</div></div>
          <Switch checked={draft.auto} onChange={(v) => setDraft({ ...draft, auto: v })} label="自动入账" />
        </div>
      </Modal>

      <Modal
        open={!!prepay}
        onClose={() => setPrepay(null)}
        title="提前还款"
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setPrepay(null)}>取消</Btn><Btn variant="primary" onClick={() => { onPrepay(prepay); setPrepay(null); }}>确认还款</Btn></React.Fragment>}
      >
        {prepay ? (
          <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div className="kv"><span className="tiny muted">计划</span><b>{prepay.name}</b></div>
            <div className="kv"><span className="tiny muted">本期应还</span><b>{money(prepay.amount_cents)}</b></div>
            <div className="kv"><span className="tiny muted">当前进度</span><b>{prepay.paid} / {prepay.total} 期</b></div>
            <div className="preview-box">提前还款会立即生成一笔支出，并把计划期数 +1；剩余 {Math.max(0, prepay.total - prepay.paid - 1)} 期。</div>
          </div>
        ) : null}
      </Modal>

      <Modal
        open={!!ending}
        onClose={() => setEnding(null)}
        title="终止计划"
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setEnding(null)}>取消</Btn><Btn variant="danger" onClick={() => { onEndPlan(ending); setEnding(null); }}>终止计划</Btn></React.Fragment>}
      >
        {ending ? <div className="preview-box">终止后不再生成本期之后的待办，历史流水保留。确定终止「{ending.name}」吗？</div> : null}
      </Modal>
    </div>
  );
}

Object.assign(window, { PlansPanel });
