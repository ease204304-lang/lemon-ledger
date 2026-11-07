-- =====================================================================
-- 小猪记账 · 记账统计模块 数据模型 (SQLite)
-- 依据: 《记账统计模块技术实施说明书》v0.9 / 01 数据模型与历史兼容
-- 金额一律以 TEXT 存储定点十进制字符串, 由应用层 Decimal 负责换算
-- 审计时间 (created_at / updated_at) 存 UTC ISO8601
-- =====================================================================

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------
-- 账本 AccountBook (R1): id / name / 成员权限
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS account_book (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    -- 成员与权限 JSON 文本: [{"user_id":"u1","role":"owner"}, ...]
    members      TEXT NOT NULL DEFAULT '[]',
    -- 维度版本: 分类/标签/对象等全局维度变更时递增, 用于跨账本缓存失效
    dimension_version INTEGER NOT NULL DEFAULT 1,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- 交易对象 Counterparty (R5): 全局对象库, 收入/支出共用
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS counterparty (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'active',  -- active / inactive
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- 交易对象合并 / 拆分映射 + 审计 (R5)
--   merge:  source_id -> target_id  (合并映射)
--   split:  transaction_id -> source_id (拆回原对象, 记录被拆分出的源对象)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS counterparty_merge_map (
    id           TEXT PRIMARY KEY,
    source_id    TEXT NOT NULL,
    target_id    TEXT NOT NULL,
    confidence   TEXT NOT NULL DEFAULT 'high',   -- high / low (D05 待冻结)
    confirmed_by TEXT,                            -- 低置信人工确认人
    created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS counterparty_split_map (
    id           TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL,
    from_id      TEXT NOT NULL,
    to_id        TEXT NOT NULL,
    operator_id  TEXT NOT NULL,
    created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS counterparty_audit (
    id           TEXT PRIMARY KEY,
    action       TEXT NOT NULL,       -- create / rename / deactivate / activate / merge / split
    target_id    TEXT,
    payload      TEXT NOT NULL DEFAULT '{}',
    operator_id  TEXT,
    created_at   TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- 分类 Category (R3): 收支各自独立, 固定两级 (parent_id 为空表示一级)
--   status: active / inactive / deleted
--   名称快照: 交易侧保留 category_name_snapshot, 改名只改主表
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS category (
    id           TEXT PRIMARY KEY,
    parent_id    TEXT REFERENCES category(id),
    type         TEXT NOT NULL,        -- expense / income
    name         TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'active', -- active / inactive / deleted
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_category_parent ON category(parent_id);
CREATE INDEX IF NOT EXISTS idx_category_type   ON category(type, status);

-- ---------------------------------------------------------------------
-- 标签 Tag (R4): 全局标签库, scope 收入/支出适用范围
--   scope: 'income' / 'expense' / 'both'
--   status: active / inactive
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tag (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'active',
    scope        TEXT NOT NULL DEFAULT 'both',
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tag_status ON tag(status);

-- ---------------------------------------------------------------------
-- 交易 Transaction (R2)
--   amount: TEXT 定点十进制字符串, 必须 > 0 (C85/C86)
--   transaction_date: 业务日 YYYY-MM-DD (保持记账时值, 不随手机时区漂移)
--   transaction_time: 日内时间 HH:MM:SS
--   amount_anomaly: 历史异常金额标记 (D07 待冻结)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS "transaction" (
    id                  TEXT PRIMARY KEY,
    book_id             TEXT NOT NULL REFERENCES account_book(id),
    type                TEXT NOT NULL,          -- expense / income
    amount              TEXT NOT NULL,          -- 定点十进制字符串, > 0
    currency            TEXT NOT NULL DEFAULT 'CNY',
    transaction_date    TEXT NOT NULL,          -- YYYY-MM-DD 业务日
    transaction_time    TEXT NOT NULL,          -- HH:MM:SS
    category_id         TEXT REFERENCES category(id),
    category_name_snapshot TEXT,               -- 历史名称快照
    counterparty_id     TEXT REFERENCES counterparty(id),
    counterparty_name_snapshot TEXT,           -- 交易侧历史名称快照 (支持拆分)
    source_counterparty_id  TEXT,               -- 合并前的源对象标识
    note                TEXT,
    amount_anomaly      INTEGER NOT NULL DEFAULT 0, -- 1 = 历史异常金额
    created_at          TEXT NOT NULL,          -- UTC
    updated_at          TEXT NOT NULL           -- UTC
);
-- 索引: (book_id, transaction_date, type) —— 建议的首要扫描/分页索引
CREATE INDEX IF NOT EXISTS idx_tx_book_date_type
    ON "transaction"(book_id, transaction_date, type);
CREATE INDEX IF NOT EXISTS idx_tx_book_date
    ON "transaction"(book_id, transaction_date);
CREATE INDEX IF NOT EXISTS idx_tx_category
    ON "transaction"(category_id);
CREATE INDEX IF NOT EXISTS idx_tx_counterparty
    ON "transaction"(counterparty_id);
CREATE INDEX IF NOT EXISTS idx_tx_book_type
    ON "transaction"(book_id, type);

-- ---------------------------------------------------------------------
-- 交易-标签关联 TransactionTag (R4)
--   role: main / aux  —— 每笔最多一个 main (C58)
--   同一交易与同一标签唯一
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_tag (
    id             TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL REFERENCES "transaction"(id) ON DELETE CASCADE,
    tag_id         TEXT NOT NULL REFERENCES tag(id),
    role           TEXT NOT NULL,   -- main / aux
    created_at     TEXT NOT NULL,
    UNIQUE (transaction_id, tag_id)
);
-- 主标签索引: 主标签聚合只走 role='main'
CREATE INDEX IF NOT EXISTS idx_tt_main   ON transaction_tag(tag_id, role);
CREATE INDEX IF NOT EXISTS idx_tt_tx    ON transaction_tag(transaction_id);
CREATE INDEX IF NOT EXISTS idx_tt_role  ON transaction_tag(role, tag_id);

-- ---------------------------------------------------------------------
-- 版本与缓存 (R6)
--   book_version: 账本数据版本 (交易写入递增)
--   dimension_version: 全局维度版本 (分类/标签/对象变更递增), 跨账本失效
--   statistic_cache: 规范化查询键 -> 结果, TTL 2 小时
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS book_version (
    book_id     TEXT PRIMARY KEY REFERENCES account_book(id),
    version     INTEGER NOT NULL DEFAULT 1,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS dimension_version (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    version     INTEGER NOT NULL DEFAULT 1,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS statistic_cache (
    cache_key     TEXT PRIMARY KEY,
    book_id       TEXT NOT NULL,
    version       INTEGER NOT NULL,
    query_key     TEXT NOT NULL,     -- 规范化条件标识
    payload       TEXT NOT NULL,     -- JSON 结果
    created_at    TEXT NOT NULL,
    expires_at    TEXT NOT NULL      -- TTL = created_at + 2 小时
);
CREATE INDEX IF NOT EXISTS idx_cache_book ON statistic_cache(book_id);
CREATE INDEX IF NOT EXISTS idx_cache_exp  ON statistic_cache(expires_at);

-- ---------------------------------------------------------------------
-- 迁移异常清册 (D07): 保留原值与来源, 供核查
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS migration_issue (
    id           TEXT PRIMARY KEY,
    issue_type   TEXT NOT NULL,   -- duplicate_main_tag / orphan_dimension / amount_precision / timezone
    book_id      TEXT,
    entity       TEXT NOT NULL,
    entity_id    TEXT NOT NULL,
    detail       TEXT NOT NULL DEFAULT '{}',
    original_value TEXT,
    status       TEXT NOT NULL DEFAULT 'open', -- open / resolved / ignored
    created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_mig_issue_type ON migration_issue(issue_type, status);
