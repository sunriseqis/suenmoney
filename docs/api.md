# 接口一览

所有需要登录的接口用 `Authorization: Bearer <令牌>`。
令牌是不透明随机串，不是 JWT。

错误响应统一为 `{ "error": "人话描述", "details": null }`。

---

## 认证

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/auth/setup` | 首次初始化。**仅在系统无任何用户时可用**，之后永久 403 |
| POST | `/api/auth/login` | 返回 `{ token, expiresAt, user }`，带登录限流（15 分钟 10 次） |
| POST | `/api/auth/logout` | 吊销当前令牌 |
| GET | `/api/auth/me` | 当前登录者 |
| GET | `/api/auth/sessions` | 当前登录的设备列表 |
| POST | `/api/auth/sessions/revoke-others` | 踢掉其他设备 |

**防用户名枚举**：「用户不存在」与「密码错误」返回完全相同的提示，
且用户不存在时也跑一次同开销的 scrypt 以抹平时序差异。

## 账号

读对所有登录者开放（界面要显示「记录人」），写仅限管理员。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/users` | 成员列表（只有 id / username / displayName / role） |
| POST | `/api/users` | 管理员创建账号。口令至少 8 位 |
| PATCH | `/api/users/:id` | 改显示名 / 角色 / 口令。改口令会吊销该用户其他会话 |

不允许把最后一个管理员降级（会死锁在「有账号但没人能进后台」）。

## 分类

共享字典，两人都可增改。**没有 DELETE 接口** —— 只能停用。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/categories` | 返回两级树，含 `expenseCount` |
| POST | `/api/categories` | 传 `parentId` 即为二级分类，最多两级 |
| PATCH | `/api/categories/:id` | `isEnabled: false` 停用；有子分类或记录时返回 409 |

## 支付方式

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/payment-methods` | 含已停用项（历史记录还要靠它显示） |
| POST | `/api/payment-methods` | 信用类必须同时传 `billingDay` 与 `repaymentDay`（1–31） |
| PATCH | `/api/payment-methods/:id` | 停用**不受历史记录阻挡**，只有进行中的计划会拦 |

## 支出

读全开放，**写仅限创建者**。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/expenses` | 见下方查询参数；键集分页 |
| GET | `/api/expenses/:id` | |
| POST | `/api/expenses` | 客户端只传 `spendDate`，入账日与还款日由服务端按账单周期算出 |
| PATCH | `/api/expenses/:id` | 改 `spendDate` 或 `paymentMethodId` 会**重算**账单日期 |
| DELETE | `/api/expenses/:id` | 软删除（写墓碑） |
| POST | `/api/expenses/transfer` | `{ fromCategoryId, toCategoryId }` 批量转移记录 |

**GET 查询参数**

| 参数 | 说明 |
|---|---|
| `month` | `YYYY-MM`，按**还款日**所在月份过滤 |
| `from` / `to` | 还款日区间 |
| `categoryId` | 给一级分类时连带其二级分类一起算 |
| `paymentMethodId` / `ownerId` | |
| `q` | 备注模糊搜索。`%` 与 `_` 按字面量处理，不当通配符 |
| `limit` | 默认 50，上限 200 |
| `cursor` | 键集游标 `${repayment_date}\|${id}`，用上一页的 `nextCursor` |

分页用键集而非 OFFSET：OFFSET 在深翻页时要求扫描并丢弃前面所有行，
且并发写入会让第二页重复或漏掉记录。

## 报表

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/reports/monthly` | `month=YYYY-MM` **必填** |
| GET | `/api/reports/yearly` | `year=YYYY`，返回 12 个月（无数据的补 0） |

两者都支持可选的 `ownerId` 按记录人筛选。

**为什么 `month` 必填**：服务端常年跑 UTC，让它猜「现在是几月」会制造只在
跨零点复现的月份归属错位。「今天」只对客户端所在时区有意义，所以由客户端算好再传。

## 计划与待办

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/plans` | 列表，含由待办派生的进度 |
| GET | `/api/plans/:id` | 计划 + 它的全部待办 |
| POST | `/api/plans` | 创建。**一次性生成全部期待办** |
| PATCH | `/api/plans/:id` | 改计划（LPR 调整 / 提前还款） |
| POST | `/api/plans/:id/end` | 终止：未执行的待办删除，已确认的历史保留 |
| GET | `/api/plan-todos` | 待办列表。传 `today` 会**先结算到期的自动入账待办** |
| POST | `/api/plan-todos/:id/confirm` | 确认入账 → 生成支出记录。**请求体可省略** |
| POST | `/api/plan-todos/:id/skip` | 跳过某一期（不生成账目） |

**创建计划**

| 字段 | 说明 |
|---|---|
| `source` | `manual`（房贷/房租）或 `installment`（免息分期） |
| `amountCents` | `manual` 必填：每期金额 |
| `totalAmountCents` + `purchaseDate` | `installment` 必填：消费原价与消费日 |
| `periods` | 必填，1–600。全部一次生成，所以没有「无限期」 |
| `firstDueDate` | 首期还款日，之后每期按月递推 |
| `remindDaysBefore` | 默认 3，0–60 |
| `autoPost` | 默认 false。开了则到期自动入账，不产生待办 |

**改计划**

| 字段 | 说明 |
|---|---|
| `amountCents` | 新的每期金额 |
| `remainingPeriods` | 从「最后一期已确认期 + 1」起还要多少期。不传则沿用当前剩余期数 |
| 其它 | `name` / `categoryId` / `paymentMethodId` / `firstDueDate` / `remindDaysBefore` / `autoPost` / `note` |

**确认待办**

- `spendDate` 可选，是「实际哪天付的」；**不影响报表月份归属**（归属以计划里的还款日为准）。
- 幂等由两层保证：`(plan_id, period_seq)` 唯一索引 + `UPDATE ... WHERE status = 'pending'` 条件更新。
  两人同时确认时，后到的收到 409「已被家人确认」。
- **记录人 = 点确认的人**；自动入账没有操作人，记录人取计划的所有者。
- 前端会先调 `POST /api/expenses/preview` 之外的路径？不需要 —— 待办本身已带 `postingDate` / `repaymentDate`。

**待办筛选参数**：`today`（触发结算，不传则不结算）、`planId`、`status`、`remindBefore`（取「该处理了」，含逾期）、`from`、`to`、`limit`。

⚠️ **结算是全局的，不受 `planId` 等筛选条件影响** —— 打开一次首页就该把所有到期的都结清。筛选只作用于返回的列表。

---

**monthly 的返回要点**

- `categories` 按**一级分类**聚合（二级分类归并到父级）。
  「花在什么上面」的分析粒度是一级分类。
- `change.ratio` 在上期为 0 时为 `null` —— 「从 0 涨到 X」算不出有意义的百分比，
  显示成 100% 更误导。
- `paymentMethods[].repaymentDate` 取该组记录的 `MIN(repayment_date)`：
  同一张卡在同一账单周期内的还款日必然相同，所以这是精确值，
  不需要按「账单日 + 还款日」反推。
