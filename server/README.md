# 记账统计模块 服务端 (W1 数据层 + W2 计算与接口)

小猪记账 · 记账统计模块的服务端实现。严格按《记账统计模块技术实施说明书》v0.9
的 REST API 契约实现（7 个统计接口 + 明细 + 维度 CRUD）。

## 启动

```powershell
cd D:\DSH\Account\server
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Python: `D:\UserFiles\eavon.cai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`
（依赖 fastapi / uvicorn / httpx / pydantic 已内置）

交互式文档: `http://127.0.0.1:8000/docs`

## 模块结构

```
server/app/
├── main.py       FastAPI 入口 + 路由层 (7 统计 + 明细 + 维度 CRUD + 鉴权/缓存)
├── schema.sql    SQLite 建表 (账本/交易/分类两级/标签+role/对象+合并拆分/版本缓存/异常清册)
├── db.py         连接、版本管理、缓存读写、权限
├── filters.py    统一条件解析器 (parse_filters + 规范化查询键 + 周期/分桶)
├── calc.py       聚合计算核心 (Decimal 定点, 汇总/趋势/分类/标签/对象)
├── money.py      金额字符串/百分比/比值工具 (禁止 float)
└── errors.py     错误契约 400/403/409/503
```

数据库文件: `server/lemon_stats.db`（SQLite WAL）

## 接口总览 (TECH 02)

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/statistics/summary | 收入/支出/结余/结余率/笔数/日均 (+同期对比) |
| GET | /api/statistics/trend | 分桶趋势 + 零值填充 + 同期点 + 穿透键 |
| GET | /api/statistics/categories | 分类榜 (两级, level=1/2) + 穿透键 |
| GET | /api/statistics/tags | 主标签环形图 + 榜单 + 未设置标签 |
| GET | /api/statistics/merchants | 交易对象榜 + 穿透键 |
| GET | /api/statistics/balance | 结余组合 (两侧分类榜) |
| GET | /api/statistics/anomalies | 历史异常清册 (D07) |
| GET | /api/transactions | 统一分页明细 |
| GET | /api/transactions/{id} | 单笔详情 |
| POST | /api/books · /api/categories · /api/tags · /api/counterparties | 维度创建 |
| GET | 同上 | 维度列表 |
| PATCH | /api/categories/{id} · /api/tags/{id} · /api/counterparties/{id} | 改名/停用/恢复 |
| DELETE | /api/categories/{id} · /api/transactions/{id} | 软删/硬删 |
| POST | /api/counterparties/merge · /split | 对象合并/拆分 (D05) |
| POST | /api/transactions | 写交易 (金额>0 校验) |
| PATCH | /api/transactions/{id} | 编辑交易 |

## 响应契约 (TECH 03)

统一包裹 `{ "data": ..., "meta": {"snapshot_version", "condition_key", "generated_at"} }`。

- 金额/百分比一律**十进制字符串**（单位元/百分数），无法计算的比率返回 `null`
- 错误: 400 INVALID_FILTER / 403 BOOK_FORBIDDEN / 409 SNAPSHOT_STALE / 503 统计暂不可用
- 鉴权: 请求头 `X-User-Id`（缺省 `u1`），账本成员校验；无成员视为开放账本

## 关键计算口径

| 规则 | 实现 |
|---|---|
| 结余 = 收入 − 支出；结余率 = 结余 ÷ 收入 × 100%（收入为 0 → null，可负，上限 100%） | `compute_summary` |
| 结余同期变化率：同期结余 **> 0** 才计算（C127） | `compute_comparison_summary` |
| 金额千分位 + 两位小数；占比两位小数；笔数整数 | `money.py` |
| 日均分母 = 区间自然日天数（D06 建议口径，待确认） | `ctx.days` |
| 粒度: 1–31 天按天 / 32–365 天按周（周一起） / >365 天按月 | `effective_granularity` |
| 分类固定两级；一级直记归「未细分」（仅当该一级有子分类时）；无分类归「未分类」 | `_category_display` |
| 标签: 仅主标签计额；无主标签归「未设置标签」（独立保留）；辅助标签仅供筛选；多标签命中同笔只计一次 | `aggregate_tags` |
| 交易对象: 收入来源/支出商户共用库；未填写归「未设置商户」 | `aggregate_merchants` |
| 金额 > 0（负数/零保存失败，400） | `_parse_amount` |
| 快照版本 = 账本版本 × 1000 + 维度版本；写入主动失效缓存；TTL 2h | `db.py` |

## 验收状态

`acceptance/` 目录的 T01–T34 验收套件（`python run_all.py`）:
- **功能 32/32 PASS**（T01–T34 除 T14 性能 + T33 签核）
- 性能 T14 由 `acceptance/performance/perf_runner.py 50000` 执行

## 未决规则（按 PRD v0.9 建议口径实现，待最终确认）

- **D02** 删除分类: 软删保留历史交易与快照
- **D05** 对象合并: 高置信自动 / 低置信需 `confirmed_by`
- **D06** 周期边界: 周一为周起点；月末/闰日截到可用日期；日均按区间自然日
- **D07** 异常金额: 保留原值与来源，迁移输出异常清册
