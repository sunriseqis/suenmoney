/* 设置 SettingsView · 三组 tab：账目 / 数据 / 家庭 */

const { useState } = React;

const ICON_CHOICES = ['fork', 'car', 'home', 'bag', 'basket', 'heart', 'book', 'game', 'phone', 'gift', 'baby', 'dots', 'tag', 'coins', 'card', 'briefcase'];

function downloadFile(name, text, type) {
  const blob = new Blob([text], { type: type || 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1200);
}

function ImportModal({ open, onClose, expenses, onImport, showToast }) {
  const [kind, setKind] = useState('wechat');
  const [stage, setStage] = useState('pick');
  const [rows, setRows] = useState([]);

  const buildRows = (k) => {
    const rnd = [['06-02 12:30', '午餐 · 老乡鸡', 3800, 'c0102'], ['06-03 08:12', '地铁通勤', 600, 'c0201'], ['06-05 19:40', '永辉超市', 12860, 'c0501'], ['06-08 21:05', '视频会员', 2500, 'c0803'], ['06-11 10:22', '打车回家', 3420, 'c0202'], ['06-15 14:00', '奶茶两杯', 4200, 'c0105'], ['06-18 09:30', '加油', 32000, 'c0203'], ['06-20 20:15', '药店', 6780, 'c0602']];
    return rnd.map((r, i) => {
      const ymdStr = TODAY.getFullYear() + '-' + r[0].slice(0, 2).replace('-', '-') + '-' + r[0].slice(3, 5);
      const duplicate = i === 1 || i === 4;
      return {
        id: 'imp' + i,
        time: r[0],
        note: r[1],
        amount_cents: r[2],
        cat_id: r[3],
        spend_date: ymdStr,
        pay_id: k === 'wechat' ? 'p1' : 'p2',
        duplicate
      };
    });
  };

  const choose = (k) => {
    setKind(k);
    setRows(buildRows(k));
    setStage('preview');
  };

  const commit = () => {
    const fresh = rows.filter((r) => !r.duplicate);
    onImport(fresh.map((r, i) => ({
      id: 'imp' + Date.now() + i,
      amount_cents: r.amount_cents,
      spend_date: r.spend_date,
      cat_id: r.cat_id,
      note: r.note,
      pay_id: r.pay_id,
      owner_id: 'u1',
      repayment_date: repaymentOf(r.pay_id, r.spend_date),
      installment: null
    })));
    setStage('pick');
    setRows([]);
    onClose();
  };

  return (
    <Modal
      open={open}
      onClose={() => { setStage('pick'); onClose(); }}
      title="导入导出"
      wide
      footer={stage === 'preview' ? (
        <React.Fragment>
          <span className="tiny muted" style={{ marginRight: 'auto' }}>自动去重 {rows.filter((r) => r.duplicate).length} 笔</span>
          <Btn variant="ghost" onClick={() => setStage('pick')}>返回</Btn>
          <Btn variant="primary" icon="download" onClick={commit}>导入 {rows.filter((r) => !r.duplicate).length} 笔</Btn>
        </React.Fragment>
      ) : null}
    >
      {stage === 'pick' ? (
        <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div className="g2">
            <button type="button" className="pay-item" onClick={() => choose('wechat')}>
              <span className="set-ic"><Icon name="download" size={16} /></span>
              <span style={{ minWidth: 0 }}><span style={{ display: 'block', fontWeight: 600, fontSize: 12.5 }}>微信账单 CSV</span><span className="tiny muted">自动识别列 + 分类映射</span></span>
              <Icon name="right" size={14} style={{ marginLeft: 'auto' }} />
            </button>
            <button type="button" className="pay-item" onClick={() => choose('alipay')}>
              <span className="set-ic"><Icon name="download" size={16} /></span>
              <span style={{ minWidth: 0 }}><span style={{ display: 'block', fontWeight: 600, fontSize: 12.5 }}>支付宝账单 CSV</span><span className="tiny muted">自动识别列 + 分类映射</span></span>
              <Icon name="right" size={14} style={{ marginLeft: 'auto' }} />
            </button>
          </div>
          <div className="dropzone" onClick={() => showToast('原型内使用示例数据预览')}>
            <Icon name="upload" size={22} />
            <span style={{ fontSize: 12.5, fontWeight: 600 }}>拖入 CSV 账单文件</span>
            <span className="tiny muted">支持微信 / 支付宝导出的 CSV，列名自动匹配</span>
          </div>
          <div className="split" style={{ borderTop: '1px dashed var(--line)', paddingTop: 12 }}>
            <Btn icon="download" onClick={() => downloadFile('tongzhang-ledger.json', JSON.stringify({ version: 2, expenses, exported_at: new Date().toISOString() }, null, 2))}>导出账本 JSON</Btn>
            <Btn icon="upload" onClick={() => showToast('原型内已用示例账本替代文件选择')}>导入账本 JSON</Btn>
            <Btn icon="download" onClick={() => {
              const head = '日期,分类,备注,支付方式,账期,记录人,金额(元)\n';
              const body = expenses.slice(0, 50).map((x) => [x.spend_date, catPath(x.cat_id), x.note, PAY_BY_ID[x.pay_id].name, x.repayment_date, USERS.find((u) => u.id === x.owner_id).name, (x.amount_cents / 100).toFixed(2)].join(',')).join('\n');
              downloadFile('tongzhang-ledger.csv', head + body, 'text/csv');
            }}>导出流水 CSV</Btn>
          </div>
        </div>
      ) : (
        <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <div className="split">
            <Tag tone="accent">{kind === 'wechat' ? '微信账单' : '支付宝账单'}</Tag>
            <span className="tiny muted">{rows.length} 行 · 去重后 {rows.filter((r) => !r.duplicate).length} 笔</span>
          </div>
          <div className="import-preview">
            <table className="tbl">
              <thead><tr><th>日期</th><th>备注</th><th>分类映射</th><th>支付</th><th className="th-r">金额</th><th>校验</th></tr></thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} style={{ opacity: r.duplicate ? 0.5 : 1, cursor: 'default' }}>
                    <td className="mono tiny">{r.spend_date}</td>
                    <td>{r.note}</td>
                    <td className="tiny muted">{catPath(r.cat_id)}</td>
                    <td className="tiny">{PAY_BY_ID[r.pay_id].name}</td>
                    <td className="num">{money(r.amount_cents)}</td>
                    <td>{r.duplicate ? <span className="dup-flag">重复跳过</span> : <span className="tiny" style={{ color: 'var(--ok)' }}>可导入</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </Modal>
  );
}

function Settings(props) {
  const { cats, pays, plans, todos, expenses, theme, onTheme, onCatSave, onCatDelete, onPaySave, onPayMerge, onImport, onWipe, onReset, onMemberToggle, onSavePlan, onEndPlan, onPrepay, onTodoAction, showToast } = props;
  const [tabLocal, setTabLocal] = useState('ledger');
  const tab = props.tab || tabLocal;
  const setTab = (v) => { setTabLocal(v); if (props.onTab) props.onTab(v); };
  const [catRail, setCatRail] = useState(ROOT_CATS[0].id);
  const [catEdit, setCatEdit] = useState(null);
  const [payEdit, setPayEdit] = useState(null);
  const [mergeFrom, setMergeFrom] = useState(null);
  const [importOpen, setImportOpen] = useState(false);
  const [autoSwitch, setAutoSwitch] = useState(true);
  const [webdav, setWebdav] = useState({ url: 'https://dav.jianguoyun.com/dav/', user: 'suen', pass: '••••••••' });
  const [update, setUpdate] = useState({ state: 'idle', pct: 0 });
  const [slots, setSlots] = useState(STATIC_DATA.serverSlots);
  const [dragIdx, setDragIdx] = useState(null);
  const [profile, setProfile] = useState({ name: '阿禾', slogan: '一笔一笔，把家记清楚' });

  const childCount = cats.filter((c) => c.parent).length;
  const catUsage = (id) => expenses.filter((x) => x.cat_id === id || (CAT_BY_ID[x.cat_id] && CAT_BY_ID[x.cat_id].parent === id)).length;

  const runUpdate = () => {
    setUpdate({ state: 'running', pct: 8 });
    let p = 8;
    const timer = setInterval(() => {
      p += 12 + Math.random() * 16;
      if (p >= 100) {
        clearInterval(timer);
        setUpdate({ state: 'done', pct: 100 });
        showToast('已是最新版本 v2.4.0');
      } else {
        setUpdate({ state: 'running', pct: Math.round(p) });
      }
    }, 260);
  };

  return (
    <div className="stack" style={{ gap: 16 }}>
      <div className="settings-tabs" role="tablist" aria-label="设置分组">
        {[['ledger', '账目'], ['plans', '计划与还款'], ['data', '数据'], ['family', '家庭']].map(([k, l]) => (
          <button type="button" key={k} role="tab" aria-selected={tab === k} className={'stab' + (tab === k ? ' is-on' : '')} onClick={() => setTab(k)}>{l}</button>
        ))}
      </div>

      {tab === 'ledger' ? (
        <React.Fragment>
          <Card>
            <div className="card-h">
              <span className="orb"><Icon name="tag" size={16} /></span>
              <span className="card-t">分类管理</span>
              <span className="card-cap">一级 12 · 二级 {childCount}</span>
            </div>
            <div className="cat-admin">
              <div className="cat-rail">
                {ROOT_CATS.map((c) => (
                  <button type="button" key={c.id} className={'cat-rail-btn' + (catRail === c.id ? ' is-on' : '')} onClick={() => setCatRail(c.id)}>
                    <Icon name={c.icon} size={14} style={{ color: CAT_COLORS[c.color] }} />
                    <span style={{ flex: '1 1 auto' }}>{c.name}</span>
                    <span className="tiny muted mono">{kidsOf(c.id).length}</span>
                  </button>
                ))}
              </div>
              <div>
                <div className="split" style={{ marginBottom: 8 }}>
                  <span className="tiny muted mono">二级分类 · 继承父级图标与颜色</span>
                  <Btn size="sm" variant="ghost" icon="plus" style={{ marginLeft: 'auto' }} onClick={() => setCatEdit({ isNew: true, parent: catRail, name: '', icon: CAT_BY_ID[catRail].icon, color: CAT_BY_ID[catRail].color, active: true })}>新增二级</Btn>
                </div>
                <div className="cat-kid-list">
                  {kidsOf(catRail).map((k) => (
                    <div className="cat-kid" key={k.id}>
                      <CatIcon catId={k.id} size={26} />
                      <span style={{ flex: '1 1 auto', minWidth: 0 }}>
                        <span style={{ fontSize: 12, fontWeight: 600, display: 'block' }}>{k.name} {k.active === false ? <Tag tone="warn">已停用</Tag> : null}</span>
                        <span className="tiny muted" style={{ display: 'block' }}>{catUsage(k.id)} 笔引用</span>
                      </span>
                      <IconBtn icon="edit" label="编辑分类" onClick={() => setCatEdit({ ...k })} />
                      <IconBtn icon="trash" label="删除分类" onClick={() => onCatDelete(k)} />
                    </div>
                  ))}
                </div>
                <div className="hint" style={{ marginTop: 10 }}>分类与支付方式均为软删除：已有流水引用时拒绝删除，只能停用。</div>
              </div>
            </div>
          </Card>

          <Card>
            <div className="card-h">
              <span className="orb" style={{ background: 'var(--sky)', color: '#1E293B' }}><Icon name="card" size={16} /></span>
              <span className="card-t">支付方式</span>
              <span className="card-cap">类型 · 账期 · 合并</span>
            </div>
            <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              {pays.map((p) => (
                <div className="set-row" key={p.id}>
                  <span className="set-ic"><Icon name={p.icon} size={16} /></span>
                  <div className="set-body">
                    <div className="set-t">{p.name} {p.active ? null : <Tag tone="warn">已停用</Tag>}</div>
                    <div className="set-s">{p.type} · {creditPeriodLabel(p.id)}{p.billing ? ' · 免息 ' + p.grace + ' 天' : ''}</div>
                  </div>
                  <div className="set-end">
                    <Btn size="sm" variant="ghost" onClick={() => setPayEdit({ ...p })}>编辑</Btn>
                    <Btn size="sm" variant="ghost" onClick={() => setMergeFrom(p)}>合并</Btn>
                  </div>
                </div>
              ))}
            </div>
          </Card>

          <Card>
            <div className="card-h"><span className="card-t">外观与主题</span><span className="card-cap">THEME</span></div>
            <div className="theme-cards theme-cards--3">
              <button type="button" className={'theme-card' + (theme === 'candy' ? ' is-on' : '')} onClick={() => onTheme('candy')}>
                <span className="theme-prev"><i className="tp-candy"></i></span>
                <span style={{ fontSize: 12, fontWeight: 700 }}>水果硬糖</span>
                <span className="tiny muted">浅色 · 贴纸硬阴影</span>
              </button>
              <button type="button" className={'theme-card' + (theme === 'cyber' ? ' is-on' : '')} onClick={() => onTheme('cyber')}>
                <span className="theme-prev"><i className="tp-cyber"></i></span>
                <span style={{ fontSize: 12, fontWeight: 700 }}>赛博朋克</span>
                <span className="tiny muted">深色 · 切角霓虹</span>
              </button>
              <button type="button" className={'theme-card' + (theme === 'system' ? ' is-on' : '')} onClick={() => onTheme('system')}>
                <span className="theme-prev"><i className="tp-system"></i></span>
                <span style={{ fontSize: 12, fontWeight: 700 }}>跟随系统</span>
                <span className="tiny muted">浅色 / 深色自动</span>
              </button>
            </div>
            <div className="tiny muted mono" style={{ marginTop: 8 }}>主题选择写入 localStorage；深色即赛博朋克。</div>
          </Card>

          <div className="hint">
            计划与还款已收进设置：新建 / 修改 / 终止计划、提前还款与待办清单都在「计划与还款」分组；日常提醒仍以概况页为主。
            <button type="button" className="link-btn" onClick={() => setTab('plans')}>去管理</button>
          </div>
        </React.Fragment>
      ) : null}

      {tab === 'plans' ? (
        <PlansPanel
          plans={plans}
          todos={todos}
          onSavePlan={onSavePlan}
          onEndPlan={onEndPlan}
          onPrepay={onPrepay}
          onTodoAction={onTodoAction}
        />
      ) : null}

      {tab === 'data' ? (
        <React.Fragment>
          <Card>
            <div className="card-h"><span className="orb" style={{ background: 'var(--mint)', color: '#1E293B' }}><Icon name="database" size={16} /></span><span className="card-t">数据总览</span><span className="card-cap">LOCAL DB</span></div>
            <div className="g4" style={{ gap: 10 }}>
              <Stat label="支出记录" value={expenses.length + ' 笔'} />
              <Stat label="累计金额" value={money(sumCents(expenses))} />
              <Stat label="分类 / 支付" value={cats.length + ' / ' + pays.length} />
              <Stat label="计划 / 待办" value={plans.length + ' / ' + plans.length * 2} />
            </div>
          </Card>

          <Card>
            <div className="card-h"><span className="orb" style={{ background: 'var(--amber)', color: '#1E293B' }}><Icon name="download" size={16} /></span><span className="card-t">数据管理</span><span className="card-cap">IMPORT / EXPORT</span></div>
            <div className="set-row">
              <span className="set-ic"><Icon name="download" size={15} /></span>
              <div className="set-body"><div className="set-t">导出账本 JSON</div><div className="set-s">全量账本（分类 / 支付 / 流水 / 计划 / 待办）</div></div>
              <Btn size="sm" icon="download" onClick={() => downloadFile('tongzhang-ledger.json', JSON.stringify({ version: 2, expenses, exported_at: new Date().toISOString() }, null, 2))}>导出</Btn>
            </div>
            <div className="set-row">
              <span className="set-ic"><Icon name="upload" size={15} /></span>
              <div className="set-body"><div className="set-t">导入账本 JSON</div><div className="set-s">覆盖式导入，导入前自动生成快照</div></div>
              <Btn size="sm" icon="upload" onClick={() => showToast('已生成快照，原型内不覆盖数据')}>导入</Btn>
            </div>
            <div className="set-row">
              <span className="set-ic"><Icon name="list" size={15} /></span>
              <div className="set-body"><div className="set-t">导出流水 CSV</div><div className="set-s">按当前范围导出 7 列流水</div></div>
              <Btn size="sm" icon="download" onClick={() => {
                const head = '日期,分类,备注,支付方式,账期,记录人,金额(元)\n';
                const body = expenses.slice(0, 100).map((x) => [x.spend_date, catPath(x.cat_id), x.note, PAY_BY_ID[x.pay_id].name, x.repayment_date, USERS.find((u) => u.id === x.owner_id).name, (x.amount_cents / 100).toFixed(2)].join(',')).join('\n');
                downloadFile('tongzhang-ledger.csv', head + body, 'text/csv');
              }}>导出</Btn>
            </div>
            <div className="set-row">
              <span className="set-ic"><Icon name="upload" size={15} /></span>
              <div className="set-body"><div className="set-t">导入流水</div><div className="set-s">微信 / 支付宝 CSV，预览 + 去重</div></div>
              <Btn size="sm" variant="primary" icon="upload" onClick={() => setImportOpen(true)}>打开导入</Btn>
            </div>
          </Card>

          <div className="g2">
            <Card>
              <div className="card-h"><span className="card-t">安全备份</span><span className="card-cap">BACKUP</span></div>
              <div className="kv"><span className="tiny muted">备份目录</span><b className="mono">/volume1/suen/backup</b></div>
              <div className="kv"><span className="tiny muted">最近备份</span><b>今日 03:00 · 4.2 MB</b></div>
              <div className="split" style={{ marginTop: 10 }}>
                <Btn size="sm" variant="ghost" icon="refresh" onClick={() => showToast('已触发一次本地备份')}>立即备份</Btn>
                <Btn size="sm" variant="ghost" icon="download" onClick={() => showToast('备份包已开始下载')}>下载备份</Btn>
              </div>
            </Card>
            <Card>
              <div className="card-h"><span className="card-t">WebDAV 备份</span><span className="card-cap">REMOTE</span></div>
              <div className="field"><span className="field-l">服务器地址</span><input className="input" value={webdav.url} onChange={(e) => setWebdav({ ...webdav, url: e.target.value })} /></div>
              <div className="g2" style={{ gap: 8, marginTop: 8 }}>
                <div className="field"><span className="field-l">账号</span><input className="input" value={webdav.user} onChange={(e) => setWebdav({ ...webdav, user: e.target.value })} /></div>
                <div className="field"><span className="field-l">口令</span><input className="input" type="password" value={webdav.pass} onChange={(e) => setWebdav({ ...webdav, pass: e.target.value })} /></div>
              </div>
              <div className="split" style={{ marginTop: 10 }}>
                <Btn size="sm" variant="ghost" onClick={() => showToast('连接测试成功 · 42ms')}>测试连接</Btn>
                <Btn size="sm" variant="ghost" onClick={() => showToast('已上传到 WebDAV')}>立即执行</Btn>
              </div>
            </Card>
          </div>

          <Card>
            <div className="card-h"><span className="card-t">快照</span><span className="card-cap">SNAPSHOTS</span><span style={{ marginLeft: 'auto' }}><Btn size="sm" variant="ghost" icon="plus" onClick={() => showToast('已创建快照')}>创建快照</Btn></span></div>
            {STATIC_DATA.snapshots.map((s) => (
              <div className="set-row" key={s.id}>
                <span className="set-ic"><Icon name="layers" size={15} /></span>
                <div className="set-body"><div className="set-t">{s.name}</div><div className="set-s">{s.at} · {s.size}</div></div>
                <div className="set-end">
                  <Btn size="sm" variant="ghost" onClick={() => showToast('快照已开始下载')}>下载</Btn>
                  <Btn size="sm" variant="ghost" style={{ color: 'var(--danger)' }} onClick={() => showToast('快照已删除')}>删除</Btn>
                </div>
              </div>
            ))}
          </Card>

          <Card>
            <div className="card-h"><span className="card-t">服务端设置</span><span className="card-cap">3 槽 · 自动切换</span></div>
            <div className="tiny muted" style={{ marginBottom: 4 }}>按住行首手柄上下拖动排序；探活按 1 → 2 → 3 顺序降级。</div>
            {slots.map((s, i) => (
              <div
                className="set-row"
                key={s.id}
                draggable
                onDragStart={() => setDragIdx(i)}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (dragIdx != null && dragIdx !== i) {
                    setSlots((prev) => { const a = [...prev]; const [x] = a.splice(dragIdx, 1); a.splice(i, 0, x); return a; });
                    showToast('槽位顺序已调整');
                  }
                  setDragIdx(null);
                }}
                onDragEnd={() => setDragIdx(null)}
                style={{ cursor: 'grab', opacity: dragIdx === i ? 0.45 : 1 }}
              >
                <span className="set-ic"><Icon name="list" size={15} /></span>
                <div className="set-body">
                  <div className="set-t">{s.url} {i === 0 ? <Tag tone="accent">当前</Tag> : null}</div>
                  <div className="set-s">{s.state}{s.ping ? ' · ' + s.ping + 'ms' : ''} · 槽位 {i + 1}</div>
                </div>
                <Btn size="sm" variant="ghost" icon="refresh" onClick={() => showToast('探活完成：' + s.url + ' ' + (s.ping || '—') + 'ms')}>探活</Btn>
              </div>
            ))}
            <div className="set-row">
              <span className="set-ic"><Icon name="link" size={15} /></span>
              <div className="set-body"><div className="set-t">自动切换</div><div className="set-s">1 → 2 → 3 顺序探活，失败自动降级</div></div>
              <Switch checked={autoSwitch} onChange={setAutoSwitch} label="自动切换" />
            </div>
          </Card>

          <Card>
            <div className="card-h"><span className="card-t">检查更新</span><span className="card-cap">UPDATE</span></div>
            <div className="set-row">
              <span className="set-ic"><Icon name="refresh" size={15} /></span>
              <div className="set-body"><div className="set-t">当前版本 v2.4.0</div><div className="set-s">手动检查，含下载进度</div></div>
              <Btn size="sm" icon="refresh" onClick={runUpdate} disabled={update.state === 'running'}>
                {update.state === 'running' ? update.pct + '%' : update.state === 'done' ? '已最新' : '检查更新'}
              </Btn>
            </div>
            {update.state !== 'idle' ? <div style={{ marginTop: 8 }}><Bar pct={update.pct} /></div> : null}
          </Card>

          <Card>
            <div className="card-h"><span className="card-t" style={{ color: 'var(--danger)' }}>危险区</span><span className="card-cap">DANGER ZONE</span></div>
            <div className="danger-zone">
              <div className="split">
                <span style={{ flex: '1 1 auto' }}><b style={{ fontSize: 12.5 }}>清空全部数据</b><div className="tiny muted">删除所有流水、计划与待办，不可恢复</div></span>
                <Btn size="sm" variant="danger" onClick={onWipe}>清空</Btn>
              </div>
              <div className="split">
                <span style={{ flex: '1 1 auto' }}><b style={{ fontSize: 12.5 }}>重置为演示数据</b><div className="tiny muted">恢复初始演示账本</div></span>
                <Btn size="sm" variant="ghost" onClick={onReset}>重置</Btn>
              </div>
            </div>
          </Card>
        </React.Fragment>
      ) : null}

      {tab === 'family' ? (
        <React.Fragment>
          <Card>
            <div className="card-h"><span className="orb" style={{ background: 'var(--pink)', color: '#1E293B' }}><Icon name="users" size={16} /></span><span className="card-t">成员管理</span><span className="card-cap">两人家庭 · 共用单账本</span></div>
            {USERS.map((u) => (
              <div className="set-row" key={u.id}>
                <span className="avatar" style={{ background: u.color }}>{u.initial}</span>
                <div className="set-body">
                  <div className="set-t">{u.name} {u.id === 'u1' ? <Tag tone="accent">管理员</Tag> : <Tag>成员</Tag>}</div>
                  <div className="set-s">记录人字段 · {expenses.filter((x) => x.owner_id === u.id).length} 笔</div>
                </div>
                <Btn size="sm" variant="ghost" onClick={() => showToast(u.name + ' 的显示名已更新')}>改显示名</Btn>
                <Btn size="sm" variant="ghost" style={{ color: 'var(--danger)' }} disabled={u.id === 'u1'} onClick={() => onMemberToggle(u)}>停用</Btn>
              </div>
            ))}
          </Card>

          <div className="g2">
            <Card>
              <div className="card-h"><span className="card-t">我的账号</span><span className="card-cap">ACCOUNT</span></div>
              <div className="field"><span className="field-l">显示名</span><input className="input" value={profile.name} onChange={(e) => setProfile({ ...profile, name: e.target.value })} /></div>
              <div className="field" style={{ marginTop: 8 }}><span className="field-l">新口令</span><input className="input" type="password" placeholder="••••••••" /></div>
              <div className="split" style={{ marginTop: 10 }}>
                <Tag tone="accent">管理员</Tag>
                <span className="tiny muted">会话保存在 cookie 中</span>
                <Btn size="sm" variant="ghost" style={{ marginLeft: 'auto' }} onClick={() => showToast('账号资料已保存')}>保存</Btn>
              </div>
            </Card>
            <Card>
              <div className="card-h"><span className="card-t">登录设备</span><span className="card-cap">SESSIONS</span></div>
              {STATIC_DATA.sessions.map((s) => (
                <div className="set-row" key={s.id}>
                  <span className="set-ic"><Icon name="phone" size={15} /></span>
                  <div className="set-body"><div className="set-t">{s.name}</div><div className="set-s">{s.at}</div></div>
                  {s.current ? <Tag tone="accent">当前</Tag> : <Btn size="sm" variant="ghost" onClick={() => showToast('该设备已被踢出')}>踢出</Btn>}
                </div>
              ))}
              <div style={{ marginTop: 10 }}><Btn size="sm" variant="ghost" onClick={() => showToast('已踢出其他设备')}>踢出其他设备</Btn></div>
            </Card>
          </div>

          <Card>
            <div className="card-h"><span className="card-t">关于应用</span><span className="card-cap">ABOUT</span></div>
            <div className="about-card">
              <div className="logo-ph about-logo">LOGO<br />占位</div>
              <div>
                <div className="about-name">同账</div>
                <div className="about-slogan">{profile.slogan}</div>
              </div>
              <div className="about-meta">
                <span>v2.4.0</span><span>单账本</span><span>整数分</span><span>只记支出</span>
              </div>
              <div className="tiny muted">LOGO 位置已预留，接入正式品牌标识时替换此处占位即可。</div>
            </div>
          </Card>
        </React.Fragment>
      ) : null}

      <Modal
        open={!!catEdit}
        onClose={() => setCatEdit(null)}
        title={catEdit && catEdit.isNew ? '新增二级分类' : '编辑分类'}
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setCatEdit(null)}>取消</Btn><Btn variant="primary" onClick={() => { onCatSave(catEdit); setCatEdit(null); }}>保存</Btn></React.Fragment>}
      >
        {catEdit ? (
          <React.Fragment>
            <label className="field"><span className="field-l">分类名称</span>
              <input className="input" value={catEdit.name} onChange={(e) => setCatEdit({ ...catEdit, name: e.target.value })} />
            </label>
            <div className="field"><span className="field-l">图标</span>
              <div className="swatches">
                {ICON_CHOICES.map((ic) => (
                  <button type="button" key={ic} className={'icon-btn' + (catEdit.icon === ic ? '' : '')} style={{ borderColor: catEdit.icon === ic ? 'var(--accent)' : 'var(--line)', color: catEdit.icon === ic ? 'var(--accent)' : 'var(--ink-2)' }} onClick={() => setCatEdit({ ...catEdit, icon: ic })} aria-label={ic}>
                    <Icon name={ic} size={16} />
                  </button>
                ))}
              </div>
            </div>
            <div className="field"><span className="field-l">颜色（16 槽）</span>
              <div className="swatches">
                {CAT_COLORS.map((c, i) => (
                  <button type="button" key={c} className={'swatch' + (catEdit.color === i ? ' is-on' : '')} style={{ background: c }} onClick={() => setCatEdit({ ...catEdit, color: i })} aria-label={'颜色 ' + (i + 1)}></button>
                ))}
              </div>
            </div>
            <div className="set-row">
              <span className="set-ic"><Icon name="check" size={15} /></span>
              <div className="set-body"><div className="set-t">启用</div><div className="set-s">停用后不出现在记账选择器，历史流水保留</div></div>
              <Switch checked={catEdit.active !== false} onChange={(v) => setCatEdit({ ...catEdit, active: v })} label="启用分类" />
            </div>
          </React.Fragment>
        ) : null}
      </Modal>

      <Modal
        open={!!payEdit}
        onClose={() => setPayEdit(null)}
        title="编辑支付方式"
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setPayEdit(null)}>取消</Btn><Btn variant="primary" onClick={() => { onPaySave(payEdit); setPayEdit(null); }}>保存</Btn></React.Fragment>}
      >
        {payEdit ? (
          <div className="g2">
            <label className="field"><span className="field-l">名称</span><input className="input" value={payEdit.name} onChange={(e) => setPayEdit({ ...payEdit, name: e.target.value })} /></label>
            <label className="field"><span className="field-l">类型</span>
              <select className="input" value={payEdit.type} onChange={(e) => setPayEdit({ ...payEdit, type: e.target.value })}>
                <option>余额</option><option>信用卡</option><option>信用支付</option><option>借记卡</option><option>现金</option>
              </select>
            </label>
            <label className="field"><span className="field-l">账单日</span><input className="input" type="number" value={payEdit.billDay || ''} onChange={(e) => setPayEdit({ ...payEdit, billDay: Number(e.target.value) })} /></label>
            <label className="field"><span className="field-l">还款日</span><input className="input" type="number" value={payEdit.dueDay || ''} onChange={(e) => setPayEdit({ ...payEdit, dueDay: Number(e.target.value) })} /></label>
          </div>
        ) : null}
      </Modal>

      <Modal
        open={!!mergeFrom}
        onClose={() => setMergeFrom(null)}
        title="合并支付方式"
        footer={<React.Fragment><Btn variant="ghost" onClick={() => setMergeFrom(null)}>取消</Btn><Btn variant="primary" onClick={() => { onPayMerge(mergeFrom); setMergeFrom(null); }}>合并</Btn></React.Fragment>}
      >
        {mergeFrom ? (
          <div className="stack--sm" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <div className="preview-box">把「{mergeFrom.name}」的流水迁移到另一个支付方式，随后停用「{mergeFrom.name}」。</div>
            <div className="pay-list">
              {pays.filter((p) => p.id !== mergeFrom.id).map((p) => (
                <button type="button" key={p.id} className="pay-item" onClick={() => onPayMerge(mergeFrom, p)}>
                  <span className="set-ic"><Icon name={p.icon} size={15} /></span>
                  <span style={{ flex: '1 1 auto', textAlign: 'left' }}>{p.name}</span>
                  <Icon name="right" size={14} />
                </button>
              ))}
            </div>
          </div>
        ) : null}
      </Modal>

      <ImportModal open={importOpen} onClose={() => setImportOpen(false)} expenses={expenses} onImport={onImport} showToast={showToast} />
    </div>
  );
}

Object.assign(window, { Settings, ImportModal });
