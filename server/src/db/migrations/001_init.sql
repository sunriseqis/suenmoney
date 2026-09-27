-- ============================================================================
--  001_init.sql —— SuenMoney 初始 schema
-- ============================================================================
--  设计约定（改动前务必先读这里，每一条都对应一个踩过的坑）
--
--  1) 主键：所有实体表主键为 TEXT，存 ULID，**由客户端生成**，服务端绝不自增分配。
--     原因：离线创建记录时，客户端必须立刻知道自己和关联对象的 ID，
--     否则「记录 → 分类」「记录 → 计划」这些引用关系根本无从建立。
--
--  2) 金额：一律 INTEGER，单位「分」。绝不使用 REAL / DECIMAL 存金额 ——
--     浮点求和会出现「总账差一分钱」这类查不出原因的 bug。
--
--  3) 业务日期：TEXT，格式 'YYYY-MM-DD'（本地日期，不含时区）。
--     「今天」由客户端按本地时区判定后传入，服务端不自行推算业务日期。
--     月/年报表 = 字符串前缀匹配（LIKE '2026-01%'），零时区换算、零边界歧义。
--     审计时间戳另存 UTC ISO8601（created_at / updated_at），两者职责分离。
--
--  4) 报表月份归属：以 expenses.repayment_date（还款日）所在月份为准。
--     这是「钱什么时候出去」的现金流出视角，不是「什么时候消费的」。
--
--  5) 删除：一律软删除（deleted_at 非空 + 一条 op='delete' 的墓碑变更），
--     永不物理删除，否则已被删除的记录会被其他设备的旧数据「复活」。
--
--  6) 同步：所有实体表共有同步字段
--       created_at / updated_at : UTC ISO8601，仅审计与排序，**不做同步游标**
--       deleted_at              : 非空即已删除（墓碑）
--       rev                     : Lamport 计数，每次写入 +1；冲突时 rev 大者胜
--       device_id               : 最后写入的设备；rev 相同时按字典序打破平局
--     游标用 changes.version（单调递增），客户端持 last_pulled_version 增量拉取。
--
--  7) 分类 / 支付方式只能停用（is_enabled = 0），不能硬删 —— 硬删会让历史记录
--     的分类变成空值，报表里冒出一块「未分类」黑洞，并随同步扩散到所有设备。
--
--  8) 唯一约束一律写成「部分索引 + WHERE deleted_at IS NULL」，
--     否则软删除掉的用户名/分类名会永久占用命名空间，无法重建同名的。
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 同步计数器（单行）
-- ---------------------------------------------------------------------------
-- 用 UPDATE ... RETURNING 发号，不用自增表 —— 自增表会随写入次数无限堆积行。

CREATE TABLE sync_sequence (
  id    INTEGER PRIMARY KEY CHECK (id = 1),
  value INTEGER NOT NULL
);

INSERT INTO sync_sequence (id, value) VALUES (1, 0);


-- ---------------------------------------------------------------------------
-- 用户
-- ---------------------------------------------------------------------------
-- 家庭共用一套账：分类、支付方式是**共享字典**（所以不带 owner），
-- 而每条支出记录带 owner_id 作为权限键 —— 「只能改自己创建的记录」。

CREATE TABLE users (
  id            TEXT PRIMARY KEY,           -- ULID
  username      TEXT NOT NULL,              -- 登录名，小写
  display_name  TEXT NOT NULL,              -- 界面显示名，也用于「记录人」
  password_hash TEXT NOT NULL,              -- scrypt，格式 scrypt$N$r$p$salt$hash
  role          TEXT NOT NULL DEFAULT 'member'
                CHECK (role IN ('admin', 'member')),

  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  rev           INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT
);

CREATE UNIQUE INDEX ux_users_username
  ON users (username)
  WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 会话（不透明令牌，不用 JWT）
-- ---------------------------------------------------------------------------
-- 为什么不用 JWT：JWT 无状态，容器重启后若签名密钥变了就会「全员掉线」；
-- 且 JWT 无法单独吊销。这里改为随机 32 字节令牌，库里只存 SHA-256 哈希，
-- 可以按设备列出、单独踢下线，且不依赖任何服务端密钥。

CREATE TABLE sessions (
  id           TEXT PRIMARY KEY,            -- ULID
  user_id      TEXT NOT NULL REFERENCES users(id),
  token_hash   TEXT NOT NULL,               -- SHA-256(令牌明文)，明文永不落库
  device_label TEXT NOT NULL DEFAULT '',    -- 如「Chrome / macOS」「Pixel 8」
  created_at   TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  expires_at   TEXT NOT NULL,
  revoked_at   TEXT
);

CREATE UNIQUE INDEX ux_sessions_token_hash ON sessions (token_hash);
CREATE INDEX ix_sessions_user ON sessions (user_id, expires_at);


-- ---------------------------------------------------------------------------
-- 分类（最多两级：一级必填，二级可选）
-- ---------------------------------------------------------------------------
-- depth 冗余存储是刻意的：让它能参与索引与查询，避免每次递归推导。

CREATE TABLE categories (
  id         TEXT PRIMARY KEY,              -- ULID
  parent_id  TEXT REFERENCES categories(id),-- NULL = 一级分类
  name       TEXT NOT NULL,
  depth      INTEGER NOT NULL DEFAULT 1 CHECK (depth IN (1, 2)),
  icon       TEXT NOT NULL DEFAULT '',      -- 图标名（前端图标库的标识）
  color      TEXT NOT NULL DEFAULT '',      -- 分类色，仅用于图标与图表，不用于正文
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_enabled INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),

  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  rev        INTEGER NOT NULL DEFAULT 1,
  device_id  TEXT,

  -- 二级分类必须有一级父级；一级分类必须没有父级
  CHECK ((depth = 1 AND parent_id IS NULL) OR (depth = 2 AND parent_id IS NOT NULL))
);

-- 同层重名。parent_id 为 NULL 时唯一索引会把两行当成不同值，
-- 所以用 COALESCE 归一化，否则「餐饮」可以被创建无数遍。
CREATE UNIQUE INDEX ux_categories_sibling_name
  ON categories (COALESCE(parent_id, ''), name)
  WHERE deleted_at IS NULL;

CREATE INDEX ix_categories_parent ON categories (parent_id, sort_order);


-- ---------------------------------------------------------------------------
-- 支付方式
-- ---------------------------------------------------------------------------
-- type = 'cash'   ：现金 / 储蓄卡。**没有账单周期**，入账日 = 还款日 = 消费日，
--                   运行时推导，不落库（所以下面两个日期字段为 NULL）。
-- type = 'credit' ：信用卡 / 花呗 / 白条等月付。必须有账单日与还款日。
--
--   账单周期规则（消费日 d，账单日 B，还款日 R）：
--     d <= B  →  入账日 = 本期 B，还款日 = 本期 R
--     d >  B  →  入账日 = 次期 B，还款日 = 次期 R

CREATE TABLE payment_methods (
  id            TEXT PRIMARY KEY,           -- ULID
  name          TEXT NOT NULL,
  type          TEXT NOT NULL CHECK (type IN ('cash', 'credit')),
  billing_day   INTEGER CHECK (billing_day IS NULL OR billing_day BETWEEN 1 AND 31),
  repayment_day INTEGER CHECK (repayment_day IS NULL OR repayment_day BETWEEN 1 AND 31),
  is_enabled    INTEGER NOT NULL DEFAULT 1 CHECK (is_enabled IN (0, 1)),
  sort_order    INTEGER NOT NULL DEFAULT 0,

  created_at    TEXT NOT NULL,
  updated_at    TEXT NOT NULL,
  deleted_at    TEXT,
  rev           INTEGER NOT NULL DEFAULT 1,
  device_id     TEXT,

  -- 信用类必须两个日期都齐；现金类必须都为 NULL
  CHECK (
    (type = 'cash'   AND billing_day IS NULL     AND repayment_day IS NULL) OR
    (type = 'credit' AND billing_day IS NOT NULL AND repayment_day IS NOT NULL)
  )
);

CREATE UNIQUE INDEX ux_payment_methods_name
  ON payment_methods (name)
  WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 计划（房贷 / 免息分期）
-- ---------------------------------------------------------------------------
-- 两者是同一个模型：期数有限 = 分期，可续 = 房贷。
--
-- 改计划（LPR 调整 / 提前还款）的语义：
--   改参数 → 作废所有**未执行**的待办（status='cancelled'，保留可追溯）
--          → 按新参数从「最后一期已确认期的下一个月」重新生成待办
--   期序 period_seq **续接**，不重排 —— 否则「第 3 期」的含义会随时间变化。
--   已确认的历史期待办与支出记录**原地不动**。
--
-- first_due_date 之后每期 = 同一天顺延 N 个月（遇该月无此日则取月末，
-- 不跨月顺延，否则「2 月的房贷」会落到 3 月，报表月份归属直接错乱）。

CREATE TABLE plans (
  id                 TEXT PRIMARY KEY,      -- ULID
  owner_id           TEXT NOT NULL REFERENCES users(id),
  name               TEXT NOT NULL,         -- 如「房贷」「京东分期-iPhone」
  category_id        TEXT NOT NULL REFERENCES categories(id),
  payment_method_id  TEXT NOT NULL REFERENCES payment_methods(id),

  amount_cents       INTEGER NOT NULL CHECK (amount_cents > 0),  -- 当前每期金额
  total_amount_cents INTEGER CHECK (total_amount_cents IS NULL OR total_amount_cents > 0),
                                            -- 仅分期：消费原价总额（历史快照，
                                            -- 改金额时不动，供进度条显示「原价」）
  purchase_date      TEXT,                  -- 仅分期：消费日 'YYYY-MM-DD'
  first_due_date     TEXT NOT NULL,         -- 首期还款日 'YYYY-MM-DD'

  remind_days_before INTEGER NOT NULL DEFAULT 3 CHECK (remind_days_before >= 0),
  auto_post          INTEGER NOT NULL DEFAULT 0 CHECK (auto_post IN (0, 1)),
                                            -- 0 = 需手动确认；1 = 到期自动入账
  source             TEXT NOT NULL DEFAULT 'manual'
                     CHECK (source IN ('manual', 'installment')),
  state              TEXT NOT NULL DEFAULT 'active'
                     CHECK (state IN ('active', 'ended')),
  note               TEXT NOT NULL DEFAULT '',

  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  deleted_at         TEXT,
  rev                INTEGER NOT NULL DEFAULT 1,
  device_id          TEXT,

  -- 分期必须记录消费日与原价总额；手动创建的计划两者都可为空
  CHECK (source = 'manual' OR (purchase_date IS NOT NULL AND total_amount_cents IS NOT NULL))
);

CREATE INDEX ix_plans_owner ON plans (owner_id, state) WHERE deleted_at IS NULL;
CREATE INDEX ix_plans_active ON plans (state) WHERE deleted_at IS NULL;


-- ---------------------------------------------------------------------------
-- 支出记录
-- ---------------------------------------------------------------------------
-- 只记支出，所以没有正负号语义：负数仅用于表示退款 / 冲销（CHECK 允许 amount_cents <> 0）。
--
-- 为什么 posting_date / repayment_date 要**冗余落库**（而不是每次 JOIN
-- payment_methods 现算）：
--   报表的核心查询是「按 repayment_date 的月份聚合」，它必须能走索引。
--   现算意味着全表扫描 + 每行一次账单周期推算，且无法建索引。
--   这是「为查询而反范式的计算值」，与「把 入账日=还款日=消费日 这种常量
--   塞进 payment_methods」是两回事 —— 后者才是没有意义的冗余。
--   写入时由领域层统一计算，只有一处逻辑。

CREATE TABLE expenses (
  id                TEXT PRIMARY KEY,       -- ULID
  owner_id          TEXT NOT NULL REFERENCES users(id),      -- 记录人 = 权限键
  amount_cents      INTEGER NOT NULL CHECK (amount_cents <> 0),
  category_id       TEXT NOT NULL REFERENCES categories(id),
  payment_method_id TEXT NOT NULL REFERENCES payment_methods(id),

  spend_date        TEXT NOT NULL,          -- 消费日 'YYYY-MM-DD'
  posting_date      TEXT NOT NULL,          -- 入账日（账单日）
  repayment_date    TEXT NOT NULL,          -- 还款日 ← 报表月份归属以此为准

  note              TEXT NOT NULL DEFAULT '',
  source            TEXT NOT NULL DEFAULT 'manual'
                    CHECK (source IN ('manual', 'plan')),
  plan_id           TEXT REFERENCES plans(id),
  plan_period_seq   INTEGER,                -- 由计划生成时，记录是第几期

  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT,
  rev               INTEGER NOT NULL DEFAULT 1,
  device_id         TEXT,

  -- 双向约束：手动记录绝不能挂计划，计划生成的记录必须挂计划。
  -- 写成单向的 `A OR B` 会留下缺口（手动记录带上真实 plan_id 依然放行）。
  CHECK (
    (source = 'manual' AND plan_id IS NULL     AND plan_period_seq IS NULL) OR
    (source = 'plan'   AND plan_id IS NOT NULL AND plan_period_seq IS NOT NULL)
  )
);

CREATE INDEX ix_expenses_repayment_date
  ON expenses (repayment_date) WHERE deleted_at IS NULL;      -- 报表主查询路径
CREATE INDEX ix_expenses_owner
  ON expenses (owner_id, repayment_date) WHERE deleted_at IS NULL;
CREATE INDEX ix_expenses_category
  ON expenses (category_id, repayment_date) WHERE deleted_at IS NULL;
CREATE INDEX ix_expenses_payment_method
  ON expenses (payment_method_id, repayment_date) WHERE deleted_at IS NULL;
CREATE INDEX ix_expenses_plan
  ON expenses (plan_id, plan_period_seq);


-- ---------------------------------------------------------------------------
-- 计划待办（每一期一行）
-- ---------------------------------------------------------------------------
-- 创建计划时**一次性生成全部期待办**，不按需动态推算。
-- 房贷 30 年也才 360 行，数据量完全无感，换来的是每一期都能有独立状态
-- （已确认 / 已跳过 / 逾期未确认 / 已作废）。动态推算省不下存储，
-- 却会让「跳过本期」「逾期确认」「改计划重算」都变得别扭。
--
-- 唯一约束 (plan_id, period_seq) 是离线并发确认的**幂等键**：
-- 两人各自离线点了同一笔房贷的确认，谁先同步到服务端谁写入成功，
-- 后到的因为在同一事务里撞唯一约束而失败，返回「已被家人确认」。

CREATE TABLE plan_todos (
  id             TEXT PRIMARY KEY,          -- ULID
  plan_id        TEXT NOT NULL REFERENCES plans(id),
  period_seq     INTEGER NOT NULL CHECK (period_seq >= 1),

  amount_cents   INTEGER NOT NULL CHECK (amount_cents > 0),
  posting_date   TEXT NOT NULL,
  repayment_date TEXT NOT NULL,
  remind_date    TEXT NOT NULL,             -- repayment_date 减 remind_days_before

  status         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'confirmed', 'skipped', 'cancelled')),

  posted_date    TEXT,                      -- 确认时用户选定的入账日期
                                            -- （逾期确认时默认填还款日，但可改）
  confirmed_by   TEXT REFERENCES users(id),
  confirmed_at   TEXT,
  expense_id     TEXT REFERENCES expenses(id),

  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  deleted_at     TEXT,
  rev            INTEGER NOT NULL DEFAULT 1,
  device_id      TEXT,

  -- 已确认的待办必须有对应的支出记录与确认人，否则就是脏数据
  CHECK (status <> 'confirmed' OR (expense_id IS NOT NULL AND confirmed_by IS NOT NULL))
);

CREATE UNIQUE INDEX ux_plan_todos_period ON plan_todos (plan_id, period_seq);

-- 仪表盘待办：待确认 + 提醒日已到
CREATE INDEX ix_plan_todos_dashboard
  ON plan_todos (status, remind_date) WHERE deleted_at IS NULL;
-- 计划详情：未执行的期待办（改计划时要批量作废这一批）
CREATE INDEX ix_plan_todos_pending
  ON plan_todos (plan_id, status, period_seq);


-- ---------------------------------------------------------------------------
-- 计划变更记录（追溯用，不做回滚功能）
-- ---------------------------------------------------------------------------
-- 你哪天发现房贷月供对不上，能查出「什么时候从 1 万改成 2000 的」。

CREATE TABLE plan_revisions (
  id                      TEXT PRIMARY KEY, -- ULID
  plan_id                 TEXT NOT NULL REFERENCES plans(id),
  changed_by              TEXT NOT NULL REFERENCES users(id),

  prev_amount_cents       INTEGER,
  prev_first_due_date     TEXT,
  prev_remind_days_before INTEGER,
  prev_auto_post          INTEGER,
  prev_state              TEXT,

  cancelled_todo_count    INTEGER NOT NULL DEFAULT 0,  -- 本次作废了这么多期
  regenerated_todo_count  INTEGER NOT NULL DEFAULT 0,  -- 重新生成了这么多期
  note                    TEXT NOT NULL DEFAULT '',

  created_at              TEXT NOT NULL
);

CREATE INDEX ix_plan_revisions_plan ON plan_revisions (plan_id, created_at);


-- ---------------------------------------------------------------------------
-- 同步变更日志（增量拉取的唯一游标来源）
-- ---------------------------------------------------------------------------
-- payload 存该次变更后的实体 JSON 快照。之所以不存「实体引用 + 让客户端回来读」：
-- 同一实体在两次拉取之间可能又变了几次，客户端按引用回读会拿到未来的版本，
-- 中间态被静默跳过。数据量在家庭账本级别，快照冗余的存储成本可以忽略。

CREATE TABLE changes (
  version     INTEGER PRIMARY KEY AUTOINCREMENT,  -- 全局单调递增，即同步游标
  entity_type TEXT NOT NULL,                      -- 'expense' | 'category' | ...
  entity_id   TEXT NOT NULL,
  op          TEXT NOT NULL CHECK (op IN ('upsert', 'delete')),
  actor_id    TEXT,                               -- 谁触发的这次变更
  payload     TEXT NOT NULL,                      -- 变更后的实体 JSON 快照
  device_id   TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX ix_changes_entity ON changes (entity_type, entity_id);


-- ---------------------------------------------------------------------------
-- 服务器设置（键值对）
-- ---------------------------------------------------------------------------
-- 存可在 Web 后台动态调整、且不需要重启的值（例如默认提醒天数）。

CREATE TABLE settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
