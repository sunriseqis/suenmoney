/* 记一笔 · ExpenseSheet（新增 / 编辑 / 删除） */

const { useState, useEffect } = React;

function CategoryPicker({ open, value, onPick, onClose }) {
  const initial = value && CAT_BY_ID[value] ? (CAT_BY_ID[value].parent || CAT_BY_ID[value].id) : ROOT_CATS[0].id;
  const [rail, setRail] = useState(initial);
  useEffect(() => { if (open) setRail(initial); }, [open, initial]);
  if (!open) return null;
  return (
    <React.Fragment>
      <div className="picker-mask" onClick={onClose}></div>
      <div className="picker" role="dialog" aria-modal="true" aria-label="选择分类">
        <div className="picker-head">
          <span className="modal-title">选择分类</span>
          <span className="tiny muted mono" style={{ marginLeft: 'auto' }}>一级 12 / 二级 46</span>
          <IconBtn icon="close" label="关闭" onClick={onClose} />
        </div>
        <div className="picker-body">
          <div className="picker-rail">
            {ROOT_CATS.map((c) => (
              <button type="button" key={c.id} className={'picker-rail-btn' + (rail === c.id ? ' is-on' : '')} onClick={() => setRail(c.id)}>
                <Icon name={c.icon} size={14} style={{ color: CAT_COLORS[c.color] }} />
                {c.name}
              </button>
            ))}
          </div>
          <div className="picker-grid">
            {kidsOf(rail).filter((k) => k.active !== false).map((k) => (
              <button
                type="button"
                key={k.id}
                className={'picker-cell' + (value === k.id ? ' is-on' : '')}
                onClick={() => { onPick(k.id); onClose(); }}
              >
                <Icon name={k.icon} size={15} style={{ color: CAT_COLORS[k.color] }} />
                <span style={{ minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{k.name}</span>
              </button>
            ))}
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

function PayPicker({ open, value, onPick, onClose }) {
  if (!open) return null;
  return (
    <React.Fragment>
      <div className="picker-mask" onClick={onClose}></div>
      <div className="picker" role="dialog" aria-modal="true" aria-label="选择支付方式" style={{ width: 'min(440px, calc(100vw - 20px))' }}>
        <div className="picker-head">
          <span className="modal-title">支付方式</span>
          <span className="tiny muted mono" style={{ marginLeft: 'auto' }}>账期随卡</span>
          <IconBtn icon="close" label="关闭" onClick={onClose} />
        </div>
        <div style={{ padding: 12, overflowY: 'auto' }}>
          <div className="pay-list">
            {PAYS.map((p) => (
              <button type="button" key={p.id} className={'pay-item' + (value === p.id ? ' is-on' : '')} onClick={() => { onPick(p.id); onClose(); }}>
                <span className="set-ic"><Icon name={p.icon} size={16} /></span>
                <span style={{ flex: '1 1 auto', minWidth: 0 }}>
                  <span style={{ display: 'block', fontSize: 12.5, fontWeight: 600 }}>{p.name}</span>
                  <span className="tiny muted" style={{ display: 'block', marginTop: 2 }}>{p.type} · {creditPeriodLabel(p.id)}</span>
                </span>
                {value === p.id ? <Icon name="check" size={16} style={{ color: 'var(--accent)' }} /> : null}
              </button>
            ))}
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

function ExpenseSheet({ open, expense, expenses, onClose, onSave, onDelete, showToast }) {
  const [amount, setAmount] = useState('');
  const [catId, setCatId] = useState('c0102');
  const [payId, setPayId] = useState('p1');
  const [date, setDate] = useState(TODAY_KEY);
  const [note, setNote] = useState('');
  const [refund, setRefund] = useState(false);
  const [installment, setInstallment] = useState(null);
  const [catOpen, setCatOpen] = useState(false);
  const [payOpen, setPayOpen] = useState(false);

  useEffect(() => {
    if (!open) return;
    if (expense) {
      setAmount((Math.abs(expense.amount_cents) / 100).toFixed(2));
      setCatId(expense.cat_id);
      setPayId(expense.pay_id);
      setDate(expense.spend_date);
      setNote(expense.note || '');
      setRefund(expense.amount_cents < 0);
      setInstallment(expense.installment ? expense.installment.periods : null);
    } else {
      setAmount('');
      setCatId('c0102');
      setPayId('p1');
      setDate(TODAY_KEY);
      setNote('');
      setRefund(false);
      setInstallment(null);
    }
  }, [open, expense]);

  const pay = PAY_BY_ID[payId];
  const isCredit = pay && pay.billing;
  const cents = Math.round((parseFloat(amount) || 0) * 100);
  const effective = refund ? -cents : cents;
  const dueDate = repaymentOf(payId, date);

  const press = (k) => {
    if (k === 'C') { setAmount(''); return; }
    if (k === 'B') { setAmount((v) => v.slice(0, -1)); return; }
    if (k === '.') {
      setAmount((v) => (v.includes('.') ? v : (v || '0') + '.'));
      return;
    }
    setAmount((v) => {
      const next = (v === '0' ? '' : v) + k;
      if (next.includes('.')) {
        const parts = next.split('.');
        if (parts[1].length > 2) return v;
      }
      if (next.length > 9) return v;
      return next;
    });
  };

  const commit = () => {
    if (!cents) { showToast('请输入金额'); return; }
    onSave({
      id: expense ? expense.id : null,
      amount_cents: effective,
      spend_date: date,
      cat_id: catId,
      note: note.trim(),
      pay_id: payId,
      owner_id: expense ? expense.owner_id : 'u1',
      repayment_date: dueDate,
      installment: installment && isCredit ? { periods: installment, paid: 0, per_cents: Math.round(cents / installment) } : null
    });
  };

  const alreadyDue = expenses
    .filter((x) => x.repayment_date === dueDate && x.pay_id === payId && (!expense || x.id !== expense.id))
    .reduce((a, x) => a + x.amount_cents, 0);

  if (!open) return null;

  return (
    <React.Fragment>
      <div className="scrim" onClick={onClose}></div>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={expense ? '编辑支出' : '记一笔'}>
        <div className="sheet-head">
          <span className="sheet-title">{expense ? '编辑支出' : '记一笔'}</span>
          {refund ? <Tag tone="danger">退款冲销</Tag> : null}
          {installment ? <Tag tone="accent">{installment} 期免息</Tag> : null}
          <span style={{ marginLeft: 'auto' }}></span>
          {expense ? <IconBtn icon="trash" label="删除" onClick={() => onDelete(expense)} /> : null}
          <IconBtn icon="close" label="关闭" onClick={onClose} />
        </div>

        <div className="sheet-body">
          <div className="amt-display">
            <span className="a-cur">{refund ? '-¥' : '¥'}</span>
            <span className="a-val">{amount || '0.00'}</span>
            <span className="a-tail">{pay ? pay.name : ''}</span>
          </div>

          <div className="g2" style={{ gap: 8 }}>
            <button type="button" className="sheet-cell" onClick={() => setCatOpen(true)}>
              <CatIcon catId={catId} size={28} />
              <span style={{ minWidth: 0 }}>
                <span className="lbl" style={{ display: 'block' }}>分类</span>
                <span className="val">{catPath(catId)}</span>
              </span>
              <Icon name="right" size={14} style={{ marginLeft: 'auto', color: 'var(--ink-3)' }} />
            </button>
            <label className="sheet-cell" style={{ cursor: 'pointer' }}>
              <Icon name="calendar" size={18} style={{ color: 'var(--ink-2)' }} />
              <span style={{ minWidth: 0, flex: '1 1 auto' }}>
                <span className="lbl" style={{ display: 'block' }}>消费日期</span>
                <input
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value || TODAY_KEY)}
                  style={{ border: 0, background: 'transparent', padding: 0, width: '100%', fontSize: 12.5, fontWeight: 600, color: 'var(--ink)' }}
                  aria-label="消费日期"
                />
              </span>
            </label>
          </div>

          <button type="button" className="sheet-cell" onClick={() => setPayOpen(true)}>
            <Icon name={pay ? pay.icon : 'wallet'} size={18} style={{ color: 'var(--ink-2)' }} />
            <span style={{ minWidth: 0 }}>
              <span className="lbl" style={{ display: 'block' }}>支付方式</span>
              <span className="val">{pay ? pay.name : '选择支付方式'} <span className="tiny muted">{pay ? '· ' + pay.type : ''}</span></span>
            </span>
            <Icon name="right" size={14} style={{ marginLeft: 'auto', color: 'var(--ink-3)' }} />
          </button>

          <input
            className="input"
            placeholder="备注（选填）"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            aria-label="备注"
          />

          <div className="set-row" style={{ padding: '6px 0' }}>
            <span className="set-ic"><Icon name="undo" size={15} /></span>
            <div className="set-body">
              <div className="set-t">退款（负数冲销）</div>
              <div className="set-s">{installment ? '分期中的消费不能标记退款' : '退款不使用「收入」，直接以负数金额冲减本期支出'}</div>
            </div>
            <Switch checked={refund} onChange={(v) => { setRefund(v); if (v) setInstallment(null); }} label="退款" />
          </div>

          <div className="set-row" style={{ padding: '6px 0' }}>
            <span className="set-ic"><Icon name="layers" size={15} /></span>
            <div className="set-body">
              <div className="set-t">分期（仅信用卡 · 非退款）</div>
              <div className="set-s">{isCredit ? '免息分期，每期金额自动四舍五入' : '当前支付方式不支持分期，请先切换到信用卡'}</div>
            </div>
            <div className="split">
              {installment ? (
                <select
                  className="input"
                  value={installment}
                  onChange={(e) => setInstallment(Number(e.target.value))}
                  style={{ width: 84, minHeight: 32, padding: '4px 8px' }}
                  aria-label="分期期数"
                >
                  {[3, 6, 12, 24].map((n) => <option key={n} value={n}>{n} 期</option>)}
                </select>
              ) : null}
              <Switch
                checked={!!installment}
                onChange={(v) => { if (v && !isCredit) { showToast('切到信用卡后才能分期'); return; } if (v && refund) setRefund(false); setInstallment(v ? 12 : null); }}
                label="分期"
              />
            </div>
          </div>

          <div className="preview-box">
            金额预览（不落库先算）：<br />
            {isCredit ? (
              <React.Fragment>
                账期归属 <b>{dueDate}</b> 还款日 · 当前该账期已有 <b>{money(alreadyDue)}</b>，新增后 <b>{money(alreadyDue + effective)}</b>
                {installment ? <span> · 每期约 <b>{money(Math.round(cents / installment))}</b>，共 {installment} 期</span> : null}
              </React.Fragment>
            ) : (
              <React.Fragment>
                即时入账，消费日期 <b>{date}</b> · 本月记录人 <b>阿禾</b>
              </React.Fragment>
            )}
          </div>

          <div className="keypad">
            <div className="paycol">
              {PAYS.slice(0, 6).map((p) => (
                <button type="button" key={p.id} className={'pay-key' + (payId === p.id ? ' is-on' : '')} onClick={() => setPayId(p.id)} title={p.name}>
                  <Icon name={p.icon} size={15} />
                  <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', width: '100%', textAlign: 'center' }}>{p.name.slice(0, 4)}</span>
                </button>
              ))}
            </div>
            <div className="keys">
              {['7', '8', '9', 'B', '4', '5', '6', 'C', '1', '2', '3', 'OK', '0', '00', '.'].map((k) => {
                if (k === 'OK') {
                  return <button type="button" className="key key--ok" key={k} onClick={commit}>完成</button>;
                }
                const fn = k === 'B' || k === 'C';
                return (
                  <button type="button" className={'key' + (fn ? ' key--fn' : '')} key={k} onClick={() => press(k)}>
                    {k === 'B' ? <Icon name="left" size={16} /> : k === 'C' ? '清空' : k}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        <div className="sheet-foot">
          <Btn variant="primary" icon="check" style={{ flex: '1 1 auto' }} onClick={commit}>{expense ? '保存修改' : '记下这笔'}</Btn>
          <Btn variant="ghost" onClick={onClose}>取消</Btn>
        </div>
      </div>

      <CategoryPicker open={catOpen} value={catId} onPick={setCatId} onClose={() => setCatOpen(false)} />
      <PayPicker open={payOpen} value={payId} onPick={setPayId} onClose={() => setPayOpen(false)} />
    </React.Fragment>
  );
}

Object.assign(window, { ExpenseSheet, CategoryPicker, PayPicker });
