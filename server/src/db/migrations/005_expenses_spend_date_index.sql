-- ---------------------------------------------------------------------------
-- 005: 流水列表核心索引（spend_date）
-- ---------------------------------------------------------------------------
-- 语义：流水列表的默认排序基准是 (spend_date DESC, id DESC)（键集分页），
-- 但此前只有 repayment_date 的索引，默认「按消费时间」的流水查询每次都全表扫描
-- + 内存排序。本索引与列表查询的 WHERE deleted_at IS NULL + ORDER BY 完全对齐。
CREATE INDEX IF NOT EXISTS ix_expenses_spend_date
  ON expenses (spend_date DESC, id DESC) WHERE deleted_at IS NULL;
