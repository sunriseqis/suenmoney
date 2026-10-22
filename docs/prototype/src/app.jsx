/* 同账 · 应用外壳与状态 */

const { useState, useEffect, useMemo, useRef, useCallback } = React;

const STORAGE_KEY = 'tongzhang.v2';

function readSaved() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

const ROUTES = [
  { id: 'overview', label: '概况', icon: 'grid', sub: 'OVERVIEW' },
  { id: 'ledger', label: '流水', icon: 'list', sub: 'LEDGER' },
  { id: 'report', label: '报表', icon: 'chart', sub: 'REPORTS' },
  { id: 'settings', label: '设置', icon: 'settings', sub: 'SETTINGS' }
];

const PAGE_META = {
  overview: { title: '概况', sub: 'OVERVIEW · 本月支出与待办提醒' },
  ledger: { title: '流水', sub: 'LEDGER · 逐笔明细与检索' },
  report: { title: '报表', sub: 'REPORTS · 当月情况 / 构成 / 涨跌' },
  annual: { title: '年度报告', sub: 'ANNUAL SUMMARY' },
  settings: { title: '设置', sub: 'SETTINGS · 账目 / 计划与还款 / 数据 / 家庭' }
};

function App() {
  const saved = useMemo(readSaved, []);
  const [t, setTweak] = useTweaks(window.TWEAK_DEFAULTS);
  const [prefersDark, setPrefersDark] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
    if (!mq) return;
    setPrefersDark(mq.matches);
    const fn = (e) => setPrefersDark(e.matches);
    if (mq.addEventListener) mq.addEventListener('change', fn); else if (mq.addListener) mq.addListener(fn);
    return () => {
      if (mq.removeEventListener) mq.removeEventListener('change', fn); else if (mq.removeListener) mq.removeListener(fn);
    };
  }, []);
  const theme = t.theme === 'cyber' ? 'cyber' : t.theme === 'system' ? (prefersDark ? 'cyber' : 'candy') : 'candy';
  const density = t.density === 'compact' ? 'compact' : 'cozy';
  const decor = t.decor !== false;

  const [route, setRoute] = useState(() => (
    typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(max-width: 860px)').matches ? 'ledger' : 'overview'
  ));
  const [settingsTab, setSettingsTab] = useState('ledger');
  const [ledgerAnchor, setLedgerAnchor] = useState(null);
  const [annualYear, setAnnualYear] = useState(TODAY.getFullYear());
  const [expenses, setExpenses] = useState(() => (saved && Array.isArray(saved.expenses) ? saved.expenses : SEED_EXPENSES));
  const [plans, setPlans] = useState(() => (saved && Array.isArray(saved.plans) ? saved.plans : SEED_PLANS));
  const [todos, setTodos] = useState(() => (saved && Array.isArray(saved.todos) ? saved.todos : SEED_TODOS));
  const [users, setUsers] = useState(USERS);
  const [sheet, setSheet] = useState({ open: false, expense: null });
  const [toast, setToast] = useState(null);
  const [pull, setPull] = useState(0);
  const toastTimer = useRef(null);
  const startY = useRef(null);
  const isMobile = useMedia('(max-width: 860px)');

  const showToast = useCallback((msg) => {
    setToast(msg);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 2400);
  }, []);

  /* 首次进入恢复上次主题 */
  const restoredTheme = useRef(false);
  useEffect(() => {
    if (restoredTheme.current) return;
    restoredTheme.current = true;
    if (saved && saved.theme) setTweak('theme', saved.theme);
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ theme: t.theme, expenses, plans, todos }));
    } catch (e) { /* 忽略存储失败 */ }
  }, [t.theme, expenses, plans, todos]);

  /* 移动端下拉记账（唯一入口，无兜底按钮） */
  useEffect(() => {
    if (!isMobile) { setPull(0); return; }
    const down = (e) => {
      if (window.scrollY > 2) return;
      startY.current = e.touches ? e.touches[0].clientY : e.clientY;
    };
    const move = (e) => {
      if (startY.current == null) return;
      const y = e.touches ? e.touches[0].clientY : e.clientY;
      const dy = y - startY.current;
      if (dy > 8 && window.scrollY <= 2) setPull(Math.min(84, dy * 0.62));
    };
    const up = () => {
      if (startY.current == null) return;
      setPull((p) => {
        if (p > 54) setSheet({ open: true, expense: null });
        return 0;
      });
      startY.current = null;
    };
    window.addEventListener('touchstart', down, { passive: true });
    window.addEventListener('touchmove', move, { passive: true });
    window.addEventListener('touchend', up);
    window.addEventListener('mousedown', down);
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
    return () => {
      window.removeEventListener('touchstart', down);
      window.removeEventListener('touchmove', move);
      window.removeEventListener('touchend', up);
      window.removeEventListener('mousedown', down);
      window.removeEventListener('mousemove', move);
      window.removeEventListener('mouseup', up);
    };
  }, [isMobile]);

  const navigate = useCallback((next, opts) => {
    if (opts && opts.anchor) setLedgerAnchor(opts.anchor);
    if (next === 'annual') setAnnualYear((opts && opts.year) || annualYear);
    if (next === 'settings') setSettingsTab((opts && opts.tab) || 'ledger');
    setRoute(next);
    window.scrollTo({ top: 0, behavior: 'auto' });
  }, [annualYear]);

  const saveExpense = (payload) => {
    if (payload.id) {
      setExpenses((prev) => prev.map((x) => (x.id === payload.id ? { ...x, ...payload } : x)));
      showToast('已保存修改');
    } else {
      const id = 'e' + Date.now();
      setExpenses((prev) => [{ ...payload, id }, ...prev]);
      showToast('已记一笔 ' + signedMoney(payload.amount_cents));
    }
    setSheet({ open: false, expense: null });
  };

  const deleteExpense = (tx) => {
    setExpenses((prev) => prev.filter((x) => x.id !== tx.id));
    setSheet({ open: false, expense: null });
    showToast('已删除这笔记录');
  };

  const todoAction = (todo, action) => {
    if (action === 'ack' || action === 'confirm') {
      const plan = plans.find((p) => p.id === todo.plan_id);
      setTodos((prev) => prev.map((x) => (x.id === todo.id ? { ...x, state: 'done' } : x)));
      if (document && plan) {
        const payId = plan.pay_id;
        setExpenses((prev) => [{
          id: 'e' + Date.now(),
          amount_cents: todo.amount_cents,
          spend_date: todo.due_date,
          cat_id: plan.kind === '房贷' ? 'c0301' : plan.kind === '车贷' ? 'c0203' : 'c0304',
          note: todo.title + ' · 已入账',
          pay_id: payId,
          owner_id: plan.owner_id,
          repayment_date: repaymentOf(payId, todo.due_date),
          installment: null
        }, ...prev]);
      }
      showToast(action === 'ack' ? '已确认并自动入账' : '已手动入账');
      return;
    }
    if (action === 'skip') {
      setTodos((prev) => prev.map((x) => (x.id === todo.id ? { ...x, state: 'skipped' } : x)));
      showToast('已忽略这笔待办');
      return;
    }
    if (action === 'revert') {
      setTodos((prev) => prev.map((x) => (x.id === todo.id ? { ...x, state: 'pending' } : x)));
      setExpenses((prev) => prev.filter((x) => x.note !== todo.title + ' · 已入账'));
      showToast('已撤销，待办恢复');
      return;
    }
    if (action === 'restore') {
      setTodos((prev) => prev.map((x) => (x.id === todo.id ? { ...x, state: 'pending' } : x)));
      showToast('已恢复待办');
    }
  };

  const savePlan = (draft) => {
    if (draft.id) {
      setPlans((prev) => prev.map((p) => (p.id === draft.id ? { ...p, ...draft } : p)));
      showToast('计划已更新');
    } else {
      const id = 'pl' + Date.now();
      setPlans((prev) => [...prev, { ...draft, id, paid: 0, active: true }]);
      setTodos((prev) => [...prev, {
        id: 't' + Date.now(),
        plan_id: id,
        title: draft.name + ' · 1/' + draft.total + ' 期',
        amount_cents: draft.amount_cents,
        due_date: ymd(new Date(TODAY.getFullYear(), TODAY.getMonth(), draft.dueDay)),
        state: 'pending',
        kind: draft.auto ? 'auto' : 'manual'
      }]);
      showToast('计划已创建，待办已生成');
    }
  };

  const endPlan = (plan) => {
    setPlans((prev) => prev.map((p) => (p.id === plan.id ? { ...p, active: false } : p)));
    setTodos((prev) => prev.filter((t) => t.plan_id !== plan.id || t.state !== 'pending'));
    showToast('计划已终止');
  };

  const prepayPlan = (plan) => {
    const cat = plan.kind === '房贷' ? 'c0301' : plan.kind === '车贷' ? 'c0203' : 'c0304';
    setExpenses((prev) => [{
      id: 'e' + Date.now(),
      amount_cents: plan.amount_cents,
      spend_date: TODAY_KEY,
      cat_id: cat,
      note: plan.name + ' · 提前还款',
      pay_id: plan.pay_id,
      owner_id: plan.owner_id,
      repayment_date: repaymentOf(plan.pay_id, TODAY_KEY),
      installment: null
    }, ...prev]);
    setPlans((prev) => prev.map((p) => (p.id === plan.id ? { ...p, paid: Math.min(p.total, p.paid + 1) } : p)));
    showToast('提前还款已入账');
  };

  const saveCat = (draft) => {
    if (!draft.name || !draft.name.trim()) { showToast('请填写分类名称'); return; }
    if (draft.id) {
      setCatOverrides((prev) => ({ ...prev, [draft.id]: { ...prev[draft.id], ...draft, name: draft.name.trim(), parent: draft.parent || null } }));
      showToast('分类已更新');
    } else {
      const id = 'cx' + Date.now();
      const parent = CAT_BY_ID[draft.parent] || ROOT_CATS[0];
      setCatOverrides((prev) => ({
        ...prev,
        [id]: { id, name: draft.name.trim(), icon: parent.icon, color: parent.color, parent: draft.parent, active: draft.active !== false }
      }));
      showToast('分类已新增');
    }
  };

  const [catOverrides, setCatOverrides] = useState({});
  const [payOverrides, setPayOverrides] = useState({});

  const deleteCat = (cat) => {
    const used = expenses.some((x) => x.cat_id === cat.id);
    if (used) { showToast('该分类已有流水引用，请改为停用'); return; }
    setCatOverrides((prev) => ({ ...prev, [cat.id]: { ...cat, active: false } }));
    showToast('分类已停用（软删除）');
  };

  const savePay = (draft) => {
    setPayOverrides((prev) => ({ ...prev, [draft.id]: draft }));
    showToast('支付方式已更新');
  };

  const mergePay = (from, to) => {
    const target = to || PAYS.find((p) => p.id !== from.id);
    setExpenses((prev) => prev.map((x) => (x.pay_id === from.id ? { ...x, pay_id: target.id } : x)));
    setPayOverrides((prev) => ({ ...prev, [from.id]: { ...from, active: false } }));
    showToast('已合并到「' + target.name + '」');
  };

  const importRows = (rows) => {
    setExpenses((prev) => [...rows.map((r, i) => ({ ...r, id: 'imp' + Date.now() + i })), ...prev]);
    showToast('已导入 ' + rows.length + ' 笔流水');
    setRoute('ledger');
  };

  /* 分类 / 支付方式：叠加本地修改 */
  const cats = useMemo(() => applyCatOverrides(catOverrides).slice(), [catOverrides]);
  const pays = useMemo(() => PAYS.map((p) => (payOverrides[p.id] ? { ...p, ...payOverrides[p.id] } : p)), [payOverrides]);

  const pendingCount = todos.filter((t) => t.state === 'pending').length;

  return (
    <div className="app" data-theme={theme} data-decor={decor ? 'on' : 'off'} data-density={density}>
      <span className="deco deco-a"></span>
      <span className="deco deco-b"></span>
      <span className="deco deco-c"></span>
      <span className="deco deco-d"></span>

      <div className="shell">
        <aside className="sidebar">
          <div className="brand">
            <div className="logo-ph" aria-label="LOGO 占位">LOGO<br />占位</div>
            <div className="brand-txt">
              <div className="brand-name">同账</div>
              <div className="brand-sub">FAMILY LEDGER · 单账本</div>
            </div>
          </div>

          <nav className="nav" aria-label="主导航">
            <div className="nav-cap">账目</div>
            {ROUTES.map((r) => (
              <button
                type="button"
                key={r.id}
                className={'nav-item' + (route === r.id || (route === 'annual' && r.id === 'report') ? ' is-on' : '')}
                onClick={() => navigate(r.id)}
                aria-current={route === r.id ? 'page' : undefined}
              >
                <Icon name={r.icon} size={16} />
                <span>{r.label}</span>
                {r.id === 'overview' && pendingCount ? <span className="nav-dot">{pendingCount}</span> : null}
              </button>
            ))}
          </nav>

          <div className="side-foot">
            <div className="members">
              <div className="split" style={{ gap: 4 }}>
                {users.map((u) => (
                  <span key={u.id} className="avatar" style={{ background: u.color, marginLeft: -6, border: '2px solid var(--surface)' }} title={u.name}>{u.initial}</span>
                ))}
              </div>
              <div className="members-txt"><b>阿禾 & 小满</b>两人家庭</div>
              <div className="sync-dot"><i></i>SYNC</div>
            </div>
            <div className="tiny muted" style={{ lineHeight: 1.6, paddingLeft: 4 }}>
              只记支出 · 整数分<br />退款以负数冲销
            </div>
          </div>
        </aside>

        <div className="main">
          <header className="topbar">
            {route !== 'ledger' ? (
              <button
                type="button"
                className="icon-btn topbar-back mobile-only"
                onClick={() => navigate(route === 'annual' ? 'report' : 'ledger')}
                aria-label={route === 'annual' ? '返回报表' : '返回流水'}
              >
                <Icon name="left" size={16} />
              </button>
            ) : null}
            <div className="topbar-txt">
              <div className="topbar-title">{PAGE_META[route].title}</div>
              <div className="topbar-sub">{PAGE_META[route].sub}</div>
            </div>
            <div className="topbar-actions">
              <IconBtn
                icon={theme === 'cyber' ? 'sun' : 'moon'}
                label={theme === 'cyber' ? '切换到水果硬糖' : '切换到赛博朋克'}
                onClick={() => setTweak('theme', theme === 'cyber' ? 'candy' : 'cyber')}
              />
              <div className="desktop-only">
                <Btn variant="primary" icon="plus" onClick={() => setSheet({ open: true, expense: null })}>记一笔</Btn>
              </div>
            </div>
          </header>

          <main className="content">
            <div className="pull-hint mobile-only"><span><Icon name="down" size={11} /></span>下拉记一笔</div>
            <div className="pull-bar" style={{ height: pull }} aria-hidden="true">
              {pull > 54 ? '松开记一笔' : '下拉记一笔'}
            </div>

            {route === 'overview' ? (
              <Dashboard
                expenses={expenses}
                plans={plans}
                todos={todos}
                onNav={navigate}
                onTodoAction={todoAction}
                onOpenSheet={() => setSheet({ open: true, expense: null })}
              />
            ) : null}
            {route === 'ledger' ? (
              <Ledger
                expenses={expenses}
                plans={plans}
                todos={todos}
                onNav={navigate}
                initialAnchor={ledgerAnchor}
                onOpenExpense={(x) => setSheet({ open: true, expense: x })}
              />
            ) : null}
            {route === 'report' ? (
              <Report expenses={expenses} onOpenAnnual={(y) => { setAnnualYear(y); setRoute('annual'); }} />
            ) : null}
            {route === 'annual' ? (
              <AnnualReport expenses={expenses} year={annualYear} onBack={() => setRoute('report')} />
            ) : null}
            {route === 'settings' ? (
              <Settings
                tab={settingsTab}
                onTab={setSettingsTab}
                cats={cats}
                pays={pays}
                plans={plans}
                todos={todos}
                expenses={expenses}
                theme={t.theme}
                onTheme={(v) => setTweak('theme', v)}
                onCatSave={saveCat}
                onCatDelete={deleteCat}
                onPaySave={savePay}
                onPayMerge={mergePay}
                onImport={importRows}
                onWipe={() => { setExpenses([]); setTodos([]); showToast('数据已清空'); }}
                onReset={() => { setExpenses(SEED_EXPENSES); setPlans(SEED_PLANS); setTodos(SEED_TODOS); setCatOverrides({}); setPayOverrides({}); showToast('已重置为演示数据'); }}
                onMemberToggle={(u) => { setUsers((prev) => prev.map((x) => (x.id === u.id ? { ...x, active: false } : x))); showToast(u.name + ' 已停用'); }}
                onSavePlan={savePlan}
                onEndPlan={endPlan}
                onPrepay={prepayPlan}
                onTodoAction={todoAction}
                showToast={showToast}
              />
            ) : null}

            <div className="tiny muted mono" style={{ textAlign: 'center', padding: '18px 0 0', opacity: 0.75 }}>
              同账 · 单账本家庭记账原型 · LOGO 位置预留
            </div>
          </main>
        </div>
      </div>

      <ExpenseSheet
        open={sheet.open}
        expense={sheet.expense}
        expenses={expenses}
        onClose={() => setSheet({ open: false, expense: null })}
        onSave={saveExpense}
        onDelete={deleteExpense}
        showToast={showToast}
      />

      {toast ? <div className="toast" role="status"><Icon name="check" size={14} />{toast}</div> : null}

      <TweaksPanel title="风格">
        <TweakSection label="主题" />
        <TweakRadio
          label="配色方向"
          value={t.theme}
          options={[{ value: 'candy', label: '水果硬糖' }, { value: 'cyber', label: '赛博朋克' }]}
          onChange={(v) => setTweak('theme', v)}
        />
        <TweakSection label="布局" />
        <TweakRadio
          label="密度"
          value={density}
          options={[{ value: 'cozy', label: '舒适' }, { value: 'compact', label: '紧凑' }]}
          onChange={(v) => setTweak('density', v)}
        />
        <TweakToggle label="背景装饰图形" value={decor} onChange={(v) => setTweak('decor', v)} />
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
