"""小猪记账 · 记账统计模块 FastAPI 入口 (W2 路由层)。

启动:
    cd D:\\DSH\\Account\\server
    python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

接口总览 (TECH 02):
    GET  /api/statistics/summary     汇总: 收入/支出/结余/结余率/笔数/日均 (+同期)
    GET  /api/statistics/trend       趋势: 分桶 + 零值填充 + 同期点 + 穿透键
    GET  /api/statistics/categories  分类榜 (两级, 排名 + 穿透键)
    GET  /api/statistics/tags        主标签环形图 + 榜单 + 未设置标签
    GET  /api/statistics/merchants   交易对象榜 + 穿透键
    GET  /api/statistics/balance     结余组合 (两侧分类榜)
    GET  /api/statistics/anomalies   历史异常清册 (D07)
    GET  /api/transactions           统一分页明细
    GET  /api/transactions/{id}      单笔详情
    POST /api/books | GET /api/books
    POST /api/categories | GET | PATCH /{id} | DELETE /{id}
    POST /api/tags | GET | PATCH /{id}
    POST /api/counterparties | GET | POST /merge | POST /split
    POST /api/transactions | PATCH /{id} | DELETE /{id}

响应统一: {"data": ..., "meta": {"snapshot_version", "condition_key", "generated_at"}}
金额/百分比一律十进制字符串 (C84); 无法计算的比率返回 null。

未决规则 D01–D08 按 PRD v0.9 建议口径实现, 代码注释逐处标注「待最终确认」。
"""

from __future__ import annotations

import json
import uuid
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, List, Optional

from fastapi import Depends, FastAPI, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from . import calc
from .db import (
    bump_book_version,
    bump_dimension_version,
    close_conn,
    fetch_all,
    fetch_one,
    get_book,
    get_conn,
    init_db,
    invalidate_cache,
    list_books,
    read_cache,
    user_has_book_access,
    write_cache,
    write_lock,
)
from .errors import (
    ApiError,
    BookForbidden,
    InvalidFilter,
    api_error_handler,
    new_request_id,
    unhandled_error_handler,
)
from .filters import build_query_key, build_view_key, parse_filters
from .money import ZERO, money_str

app = FastAPI(
    title="小猪记账 · 统计模块 API",
    version="0.9.0",
    description="记账统计模块 (TECH v0.9) · 金额均为十进制字符串",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def _request_id_mw(request: Request, call_next):
    request.state.request_id = new_request_id()
    response = await call_next(request)
    response.headers["X-Request-Id"] = request.state.request_id
    return response


app.add_exception_handler(ApiError, api_error_handler)
app.add_exception_handler(Exception, unhandled_error_handler)


@app.on_event("startup")
def _startup() -> None:
    init_db()
    calc.load_category_index_cache()
    calc.load_counterparty_index_cache()


@app.on_event("shutdown")
def _shutdown() -> None:
    close_conn()


# =====================================================================
# 公共辅助
# =====================================================================

def _user_id(request: Request) -> str:
    return request.headers.get("X-User-Id", "u1")


def _require_book(book_id: str, request: Request) -> None:
    """账本存在性 + 成员权限 (TECH 03: 403 BOOK_FORBIDDEN)。"""
    if not book_id:
        raise InvalidFilter("缺少 book_id。", field="book_id", reason="missing_book_id")
    if get_book(book_id) is None:
        raise BookForbidden(f"账本不存在: {book_id}")
    if not user_has_book_access(book_id, _user_id(request)):
        raise BookForbidden("当前用户无该账本权限。")


def _envelope(data: Any, condition_key: str, snapshot_version: int) -> Dict[str, Any]:
    return {
        "data": data,
        "meta": {
            "snapshot_version": snapshot_version,
            "condition_key": condition_key,
            "generated_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        },
    }


def _stats_ctx(request: Request, **kw: Any):
    """统计 GET 统一入口: 权限 → 条件解析 (含 400/409)。"""
    book_id = kw.get("book_id") or ""
    _require_book(str(book_id), request)
    # 单侧视图的 category_mode=SELECTED 且未传 category_ids → 400 (TECH 03)
    if str(kw.get("category_mode") or "").upper() == "SELECTED" and not kw.get("category_ids"):
        raise InvalidFilter(
            "SELECTED 模式必须提供分类 ID。",
            field="category_ids", reason="selected_without_ids",
        )
    kw.pop("category_mode", None)
    return parse_filters(**kw)


def _cached_compute(ctx, view_key: str, computer) -> Dict[str, Any]:
    """缓存读取 (TECH 04): 键 = 账本+条件+模块视图+版本; TTL 2h; 写入主动失效。"""
    from .db import resolve_snapshot_version

    # parse_filters 把缺省 snapshot_version 归一为 0; 0 视为"未携带"→ 用当前版本
    requested = ctx.snapshot_version if ctx.snapshot_version and ctx.snapshot_version > 0 else None
    version = resolve_snapshot_version(ctx.book_id, requested)
    # view_key 必须进缓存键, 否则同条件的 summary/trend/categories 互相串数据
    qkey = build_view_key(ctx, view_key)
    cached = read_cache(ctx.book_id, qkey, version)
    if cached is not None:
        return _envelope(cached, qkey, version)

    data = computer(ctx)
    write_cache(ctx.book_id, qkey, version, data)
    return _envelope(data, qkey, version)


def _commit() -> None:
    get_conn().commit()


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:16]}"


def _now_iso() -> str:
    from .db import utc_now_iso

    return utc_now_iso()


# =====================================================================
# 统计接口 (TECH 02)
# =====================================================================

def _common_params(
    book_id: str = Query(..., description="账本 ID"),
    type: str = Query("expense"),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    timezone: Optional[str] = Query(None),
    granularity: Optional[str] = Query(None),
    comparison_enabled: bool = Query(False),
    snapshot_version: Optional[int] = Query(None),
    category_ids: Optional[List[str]] = Query(None),
    category_mode: Optional[str] = Query(None),
    tag_ids: Optional[List[str]] = Query(None),
    tag_role: Optional[str] = Query(None),
    counterparty_ids: Optional[List[str]] = Query(None),
    income_category_mode: Optional[str] = Query(None),
    income_category_ids: Optional[List[str]] = Query(None),
    expense_category_mode: Optional[str] = Query(None),
    expense_category_ids: Optional[List[str]] = Query(None),
    sort: str = Query("amount"),
    sort_order: str = Query("desc"),
) -> Dict[str, Any]:
    return dict(
        book_id=book_id,
        stat_type=type,
        start_date=start_date,
        end_date=end_date,
        timezone_name=timezone,
        granularity=granularity,
        comparison_enabled=comparison_enabled,
        snapshot_version=snapshot_version,
        category_ids=category_ids,
        category_mode=category_mode,
        tag_ids=tag_ids,
        tag_role=tag_role,
        counterparty_ids=counterparty_ids,
        income_category_mode=income_category_mode,
        income_category_ids=income_category_ids,
        expense_category_mode=expense_category_mode,
        expense_category_ids=expense_category_ids,
        sort=sort,
        sort_order=sort_order,
    )


@app.get("/api/statistics/summary")
def stats_summary(request: Request, p: Dict[str, Any] = Depends(_common_params)):
    """汇总: income/expense/balance/balance_rate/笔数/日均 (+同期对比)。"""
    ctx = _stats_ctx(request, **p)
    return _cached_compute(ctx, "summary", lambda c: calc.compute_summary(c))


@app.get("/api/statistics/trend")
def stats_trend(
    request: Request,
    p: Dict[str, Any] = Depends(_common_params),
):
    """趋势: 分桶聚合 + 缺桶补零 + 同期点 + 穿透键。"""
    ctx = _stats_ctx(request, **p)
    return _cached_compute(ctx, "trend", lambda c: calc.compute_trend(c))


@app.get("/api/statistics/categories")
def stats_categories(
    request: Request,
    level: int = Query(1, description="1=一级榜 2=二级榜"),
    p: Dict[str, Any] = Depends(_common_params),
):
    """分类榜: 固定两级; 一级直记归「未细分」, 无分类归「未分类」。"""
    if level not in (1, 2):
        raise InvalidFilter("level 应为 1 或 2。", field="level", reason="bad_level")
    ctx = _stats_ctx(request, **p)

    def _compute(c):
        stat = c.stat_type
        if stat == "balance":
            rows_i = calc.query_rows(c, c.start_date, c.end_date, "income", c.income_category)
            rows_e = calc.query_rows(c, c.start_date, c.end_date, "expense", c.expense_category)
            return {
                "level": level,
                "income": calc.aggregate_categories(c, rows_i, level),
                "expense": calc.aggregate_categories(c, rows_e, level),
            }
        sel = c.income_category if stat == "income" else c.expense_category
        rows = calc.query_rows(c, c.start_date, c.end_date, stat, sel)
        return calc.aggregate_categories(c, rows, level)

    return _cached_compute(ctx, f"categories:{level}", _compute)


@app.get("/api/statistics/tags")
def stats_tags(request: Request, p: Dict[str, Any] = Depends(_common_params)):
    """主标签统计: 环形图 Top5+其他 + 未设置标签独立保留 + 榜单。"""
    ctx = _stats_ctx(request, **p)

    def _compute(c):
        rows = calc.query_rows(c, c.start_date, c.end_date, c.stat_type,
                               c.income_category if c.stat_type == "income" else c.expense_category)
        return calc.aggregate_tags(c, rows)

    return _cached_compute(ctx, "tags", _compute)


@app.get("/api/statistics/merchants")
def stats_merchants(request: Request, p: Dict[str, Any] = Depends(_common_params)):
    """交易对象榜 (C10: 仅分类详情显示; 此处为数据接口)。"""
    ctx = _stats_ctx(request, **p)

    def _compute(c):
        rows = calc.query_rows(c, c.start_date, c.end_date, c.stat_type,
                               c.income_category if c.stat_type == "income" else c.expense_category)
        return calc.aggregate_merchants(c, rows)

    return _cached_compute(ctx, "merchants", _compute)


@app.get("/api/statistics/balance")
def stats_balance(request: Request, p: Dict[str, Any] = Depends(_common_params)):
    """结余组合 (C143): 复用 summary/trend/categories 逻辑。"""
    p["stat_type"] = "balance"  # 强制结余语义 (客户端可能省略 type)
    ctx = _stats_ctx(request, **p)

    def _compute(c):
        summary = calc.compute_summary(c)
        rows_i = calc.query_rows(c, c.start_date, c.end_date, "income", c.income_category)
        rows_e = calc.query_rows(c, c.start_date, c.end_date, "expense", c.expense_category)
        return {
            "summary": summary,
            "income_contribution": calc.aggregate_categories(c, rows_i, 1),
            "expense_impact": calc.aggregate_categories(c, rows_e, 1),
            "income": calc.aggregate_categories(c, rows_i, 1),
            "expense": calc.aggregate_categories(c, rows_e, 1),
        }

    return _cached_compute(ctx, "balance", _compute)


@app.get("/api/statistics/anomalies")
def stats_anomalies(
    request: Request,
    book_id: str = Query(...),
    status: Optional[str] = Query(None),
):
    """历史异常清册 (D07 建议口径: 保留原值与来源, 待最终确认)。"""
    _require_book(book_id, request)
    where, params = "book_id = ?", [book_id]
    if status:
        where += " AND status = ?"
        params.append(status)
    rows = fetch_all(
        f"SELECT * FROM migration_issue WHERE {where} ORDER BY created_at", params
    )
    data = {
        "total": len(rows),
        "items": [dict(r) for r in rows],
    }
    return _envelope(data, f"anomalies:{book_id}", 0)


# =====================================================================
# 统一明细 (TECH 02: /api/transactions)
# =====================================================================

@app.get("/api/transactions")
def list_transactions(
    request: Request,
    p: Dict[str, Any] = Depends(_common_params),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    cursor: Optional[str] = Query(None),
):
    """统一分页明细: 日期倒序分组, 日内按记账时间倒序 (C71/C72)。"""
    ctx = _stats_ctx(request, page=page, page_size=page_size, cursor=cursor, **p)
    data = calc.query_transactions(ctx)
    return _envelope(data, build_query_key(ctx) + f"|p{page}:{page_size}", 0)


@app.get("/api/transactions/{tx_id}")
def transaction_detail(
    tx_id: str,
    request: Request,
    book_id: Optional[str] = Query(None),
):
    """单笔详情: 完整信息含辅助标签与账户信息 (PRD 06)。"""
    row = fetch_one('SELECT book_id FROM "transaction" WHERE id = ?', (tx_id,))
    if row is None:
        raise InvalidFilter(
            f"交易不存在: {tx_id}", field="id", reason="not_found",
            code="NOT_FOUND", status_code=404,
        )
    bid = book_id or row["book_id"]
    _require_book(bid, request)
    data = calc.query_transaction_detail(tx_id, bid)
    if data is None:
        raise InvalidFilter(
            f"交易不存在: {tx_id}", field="id", reason="not_found",
            code="NOT_FOUND", status_code=404,
        )
    return _envelope(data, f"tx:{tx_id}", 0)


# =====================================================================
# 账本
# =====================================================================

@app.post("/api/books")
def create_book(request: Request, body: Dict[str, Any]):
    name = (body.get("name") or "").strip()
    if not name:
        raise InvalidFilter("账本名称不能为空。", field="name", reason="empty_name")
    bid = _new_id("book")
    members = [{"user_id": _user_id(request), "role": "owner"}]
    now = _now_iso()
    conn = get_conn()
    conn.execute(
        "INSERT INTO account_book (id, name, members, dimension_version, created_at, updated_at) "
        "VALUES (?, ?, ?, 1, ?, ?)",
        (bid, name, json.dumps(members, ensure_ascii=False), now, now),
    )
    conn.execute(
        "INSERT INTO book_version (book_id, version, updated_at) VALUES (?, 1, ?)",
        (bid, now),
    )
    _commit()
    data = {"id": bid, "book_id": bid, "name": name, "members": members}
    return _envelope(data, f"book:{bid}", 1)


@app.get("/api/books")
def get_books(request: Request):
    rows = list_books()
    uid = _user_id(request)
    items = []
    for r in rows:
        try:
            members = json.loads(r["members"] or "[]")
        except json.JSONDecodeError:
            members = []
        if not members or any(m.get("user_id") == uid for m in members):
            items.append({"id": r["id"], "name": r["name"]})
    return _envelope({"items": items, "total": len(items)}, "books", 0)


# =====================================================================
# 分类 (C36–C40: 固定两级, 停用/改名/删除保留历史)
# =====================================================================

@app.post("/api/categories")
def create_category(request: Request, body: Dict[str, Any]):
    name = (body.get("name") or "").strip()
    ctype = (body.get("type") or body.get("ctype") or "expense").lower()
    parent_id = body.get("parent_id")
    if not name:
        raise InvalidFilter("分类名称不能为空。", field="name", reason="empty_name")
    if ctype not in ("expense", "income"):
        raise InvalidFilter("分类类型应为 expense / income。", field="type", reason="bad_type")
    if parent_id:
        parent = fetch_one("SELECT * FROM category WHERE id = ?", (parent_id,))
        if parent is None:
            raise InvalidFilter(
                f"父分类不存在: {parent_id}", field="parent_id", reason="parent_missing"
            )
        if parent["parent_id"]:
            # 固定两级: 父分类不能再有父 (C54)
            raise InvalidFilter(
                "分类最多两级, 不能在二级分类下再建子分类。",
                field="parent_id", reason="max_depth",
            )
        if parent["type"] != ctype:
            raise InvalidFilter(
                "子分类收支类型必须与父分类一致。", field="type", reason="type_mismatch"
            )
    cid = _new_id("cat")
    now = _now_iso()
    conn = get_conn()
    conn.execute(
        "INSERT INTO category (id, parent_id, type, name, status, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, 'active', ?, ?)",
        (cid, parent_id, ctype, name, now, now),
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_category_index_cache()
    return _envelope(
        {"id": cid, "category_id": cid, "name": name, "type": ctype, "parent_id": parent_id},
        f"cat:{cid}", 0,
    )


@app.get("/api/categories")
def get_categories(
    request: Request,
    type: Optional[str] = Query(None),
    book_id: Optional[str] = Query(None),
    status: str = Query("active"),
):
    if book_id:
        _require_book(book_id, request)
    where, params = "status != 'deleted'", []
    if type:
        where += " AND type = ?"
        params.append(type)
    if status != "all":
        where += " AND status = ?"
        params.append(status)
    rows = fetch_all(f"SELECT * FROM category WHERE {where} ORDER BY type, name", params)
    items = [
        {"id": r["id"], "name": r["name"], "type": r["type"],
         "parent_id": r["parent_id"], "status": r["status"]}
        for r in rows
    ]
    return _envelope({"items": items, "total": len(items)}, "categories", 0)


@app.patch("/api/categories/{cid}")
def patch_category(cid: str, request: Request, body: Dict[str, Any]):
    row = fetch_one("SELECT * FROM category WHERE id = ?", (cid,))
    if row is None:
        raise InvalidFilter(f"分类不存在: {cid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    name = body.get("name")
    status = body.get("status")
    if status is not None and status not in ("active", "inactive"):
        raise InvalidFilter("status 应为 active / inactive。", field="status", reason="bad_status")
    now = _now_iso()
    conn = get_conn()
    if name and name.strip():
        # C139: 改名全局更新展示 —— 主表改名, 交易侧快照保留 (历史归属不变)
        conn.execute(
            "UPDATE category SET name = ?, updated_at = ? WHERE id = ?",
            (name.strip(), now, cid),
        )
    if status is not None:
        conn.execute(
            "UPDATE category SET status = ?, updated_at = ? WHERE id = ?",
            (status, now, cid),
        )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_category_index_cache()
    updated = fetch_one("SELECT * FROM category WHERE id = ?", (cid,))
    return _envelope(dict(updated), f"cat:{cid}", 0)


@app.delete("/api/categories/{cid}")
def delete_category(cid: str, request: Request):
    """删除分类 (D02 建议口径: 软删 status=deleted, 历史交易与快照保留, 待最终确认)。"""
    row = fetch_one("SELECT * FROM category WHERE id = ?", (cid,))
    if row is None:
        raise InvalidFilter(f"分类不存在: {cid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    now = _now_iso()
    conn = get_conn()
    conn.execute(
        "UPDATE category SET status = 'deleted', updated_at = ? WHERE id = ?", (now, cid)
    )
    # 子分类一并软删
    conn.execute(
        "UPDATE category SET status = 'deleted', updated_at = ? WHERE parent_id = ?", (now, cid)
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_category_index_cache()
    return _envelope({"id": cid, "status": "deleted"}, f"cat:{cid}", 0)


# =====================================================================
# 标签 (C55–C59: scope 适用范围; 停用保留历史归属; 改名全局更新)
# =====================================================================

@app.post("/api/tags")
def create_tag(request: Request, body: Dict[str, Any]):
    name = (body.get("name") or "").strip()
    if not name:
        raise InvalidFilter("标签名称不能为空。", field="name", reason="empty_name")
    scope = (body.get("scope") or "both").lower()
    if scope not in ("income", "expense", "both"):
        raise InvalidFilter("scope 应为 income / expense / both。", field="scope", reason="bad_scope")
    status = (body.get("status") or "active").lower()
    if status not in ("active", "inactive"):
        raise InvalidFilter("status 应为 active / inactive。", field="status", reason="bad_status")
    tid = _new_id("tag")
    now = _now_iso()
    conn = get_conn()
    conn.execute(
        "INSERT INTO tag (id, name, status, scope, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
        (tid, name, status, scope, now, now),
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    return _envelope({"id": tid, "tag_id": tid, "name": name, "scope": scope, "status": status},
                     f"tag:{tid}", 0)


@app.get("/api/tags")
def get_tags(request: Request, status: Optional[str] = Query(None)):
    where, params = "1=1", []
    if status:
        where += " AND status = ?"
        params.append(status)
    rows = fetch_all(f"SELECT * FROM tag WHERE {where} ORDER BY name", params)
    items = [
        {"id": r["id"], "name": r["name"], "status": r["status"], "scope": r["scope"]}
        for r in rows
    ]
    return _envelope({"items": items, "total": len(items)}, "tags", 0)


@app.patch("/api/tags/{tid}")
def patch_tag(tid: str, request: Request, body: Dict[str, Any]):
    row = fetch_one("SELECT * FROM tag WHERE id = ?", (tid,))
    if row is None:
        raise InvalidFilter(f"标签不存在: {tid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    name = body.get("name")
    status = body.get("status")
    scope = body.get("scope")
    if status is not None and status not in ("active", "inactive"):
        raise InvalidFilter("status 应为 active / inactive。", field="status", reason="bad_status")
    if scope is not None and scope not in ("income", "expense", "both"):
        raise InvalidFilter("scope 应为 income / expense / both。", field="scope", reason="bad_scope")
    now = _now_iso()
    conn = get_conn()
    if name and name.strip():
        conn.execute("UPDATE tag SET name = ?, updated_at = ? WHERE id = ?",
                     (name.strip(), now, tid))
    if status is not None:
        conn.execute("UPDATE tag SET status = ?, updated_at = ? WHERE id = ?",
                     (status, now, tid))
    if scope is not None:
        conn.execute("UPDATE tag SET scope = ?, updated_at = ? WHERE id = ?",
                     (scope, now, tid))
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    updated = fetch_one("SELECT * FROM tag WHERE id = ?", (tid,))
    return _envelope(dict(updated), f"tag:{tid}", 0)


# =====================================================================
# 交易对象 (C8–C25: 全局对象库, 合并/拆分 D05 建议口径)
# =====================================================================

@app.post("/api/counterparties")
def create_counterparty(request: Request, body: Dict[str, Any]):
    name = (body.get("name") or "").strip()
    if not name:
        raise InvalidFilter("对象名称不能为空。", field="name", reason="empty_name")
    status = (body.get("status") or "active").lower()
    cid = _new_id("cp")
    now = _now_iso()
    conn = get_conn()
    conn.execute(
        "INSERT INTO counterparty (id, name, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
        (cid, name, status, now, now),
    )
    conn.execute(
        "INSERT INTO counterparty_audit (id, action, target_id, payload, operator_id, created_at) "
        "VALUES (?, 'create', ?, '{}', ?, ?)",
        (_new_id("cpa"), cid, _user_id(request), now),
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_counterparty_index_cache()
    return _envelope({"id": cid, "counterparty_id": cid, "name": name, "status": status},
                     f"cp:{cid}", 0)


@app.get("/api/counterparties")
def get_counterparties(request: Request, status: Optional[str] = Query(None)):
    where, params = "1=1", []
    if status:
        where += " AND status = ?"
        params.append(status)
    rows = fetch_all(f"SELECT * FROM counterparty WHERE {where} ORDER BY name", params)
    items = [{"id": r["id"], "name": r["name"], "status": r["status"]} for r in rows]
    return _envelope({"items": items, "total": len(items)}, "counterparties", 0)


@app.patch("/api/counterparties/{cpid}")
def patch_counterparty(cpid: str, request: Request, body: Dict[str, Any]):
    """嵌入式治理 (C19–C25): 改名 / 停用 / 恢复。"""
    row = fetch_one("SELECT * FROM counterparty WHERE id = ?", (cpid,))
    if row is None:
        raise InvalidFilter(f"对象不存在: {cpid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    name = body.get("name")
    status = body.get("status")
    now = _now_iso()
    conn = get_conn()
    action = None
    if name and name.strip():
        conn.execute("UPDATE counterparty SET name = ?, updated_at = ? WHERE id = ?",
                     (name.strip(), now, cpid))
        action = "rename"
    if status is not None:
        if status not in ("active", "inactive"):
            raise InvalidFilter("status 应为 active / inactive。",
                                field="status", reason="bad_status")
        conn.execute("UPDATE counterparty SET status = ?, updated_at = ? WHERE id = ?",
                     (status, now, cpid))
        action = "deactivate" if status == "inactive" else "activate"
    _commit()
    if action:
        conn.execute(
            "INSERT INTO counterparty_audit (id, action, target_id, payload, operator_id, created_at) "
            "VALUES (?, ?, ?, '{}', ?, ?)",
            (_new_id("cpa"), action, cpid, _user_id(request), now),
        )
        _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_counterparty_index_cache()
    updated = fetch_one("SELECT * FROM counterparty WHERE id = ?", (cpid,))
    return _envelope(dict(updated), f"cp:{cpid}", 0)


@app.post("/api/counterparties/merge")
def merge_counterparties(request: Request, body: Dict[str, Any]):
    """合并 (D05 建议口径: 高置信自动, 低置信需人工确认; 待最终确认)。

    body: {source_ids: [..], target_id: "..", confidence: "high"|"low", confirmed_by: ".."?}
    合并: 交易对象引用迁到 target, 保留 source_counterparty_id + 名称快照支持拆分。
    """
    source_ids = body.get("source_ids") or []
    target_id = body.get("target_id")
    confidence = (body.get("confidence") or "high").lower()
    confirmed_by = body.get("confirmed_by")
    if not source_ids or not isinstance(source_ids, list):
        raise InvalidFilter("source_ids 不能为空。", field="source_ids", reason="empty")
    if not target_id:
        raise InvalidFilter("缺少 target_id。", field="target_id", reason="missing")
    if confidence not in ("high", "low"):
        raise InvalidFilter("confidence 应为 high / low。",
                            field="confidence", reason="bad_confidence")
    target = fetch_one("SELECT * FROM counterparty WHERE id = ?", (target_id,))
    if target is None:
        raise InvalidFilter(f"目标对象不存在: {target_id}",
                            field="target_id", reason="not_found")
    # D05: 低置信必须人工确认
    if confidence == "low" and not confirmed_by:
        raise InvalidFilter(
            "低置信合并需要人工确认 (confirmed_by)。", field="confirmed_by",
            reason="manual_confirm_required",
        )
    now = _now_iso()
    conn = get_conn()
    moved = 0
    for sid in source_ids:
        if sid == target_id:
            continue
        src = fetch_one("SELECT * FROM counterparty WHERE id = ?", (sid,))
        if src is None:
            continue
        cur = conn.execute(
            'UPDATE "transaction" SET counterparty_id = ?, source_counterparty_id = ?, '
            "counterparty_name_snapshot = ? WHERE counterparty_id = ?",
            (target_id, sid, src["name"], sid),
        )
        moved += cur.rowcount
        conn.execute(
            "UPDATE counterparty SET status = 'inactive', updated_at = ? WHERE id = ?",
            (now, sid),
        )
        conn.execute(
            "INSERT INTO counterparty_merge_map (id, source_id, target_id, confidence, confirmed_by, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (_new_id("cpm"), sid, target_id, confidence, confirmed_by, now),
        )
    conn.execute(
        "INSERT INTO counterparty_audit (id, action, target_id, payload, operator_id, created_at) "
        "VALUES (?, 'merge', ?, ?, ?, ?)",
        (_new_id("cpa"), target_id,
         json.dumps({"moved": moved, "source_ids": source_ids, "confidence": confidence},
                    ensure_ascii=False),
         _user_id(request), now),
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_counterparty_index_cache()
    return _envelope(
        {"target_id": target_id, "merged_from": source_ids, "moved_transactions": moved,
         "confidence": confidence},
        f"merge:{target_id}", 0,
    )


@app.post("/api/counterparties/split")
def split_counterparty(request: Request, body: Dict[str, Any]):
    """拆分 (D05): 把误合并的所选交易迁回其源对象 (source_counterparty_id)。"""
    transaction_ids = body.get("transaction_ids") or []
    if not transaction_ids:
        raise InvalidFilter("transaction_ids 不能为空。",
                            field="transaction_ids", reason="empty")
    now = _now_iso()
    conn = get_conn()
    moved = []
    for tid in transaction_ids:
        row = fetch_one(
            'SELECT id, counterparty_id, source_counterparty_id FROM "transaction" WHERE id = ?',
            (tid,),
        )
        if row is None or not row["source_counterparty_id"]:
            continue
        from_id = row["counterparty_id"]
        to_id = row["source_counterparty_id"]
        conn.execute(
            'UPDATE "transaction" SET counterparty_id = ?, source_counterparty_id = NULL '
            "WHERE id = ?",
            (to_id, tid),
        )
        conn.execute(
            "UPDATE counterparty SET status = 'active', updated_at = ? WHERE id = ?",
            (now, to_id),
        )
        conn.execute(
            "INSERT INTO counterparty_split_map (id, transaction_id, from_id, to_id, operator_id, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (_new_id("cps"), tid, from_id, to_id, _user_id(request), now),
        )
        moved.append(tid)
    conn.execute(
        "INSERT INTO counterparty_audit (id, action, target_id, payload, operator_id, created_at) "
        "VALUES (?, 'split', NULL, ?, ?, ?)",
        (_new_id("cpa"), json.dumps({"moved": moved}, ensure_ascii=False),
         _user_id(request), now),
    )
    _commit()
    bump_dimension_version()
    invalidate_cache(None)
    calc.load_counterparty_index_cache()
    return _envelope({"moved_transactions": moved, "count": len(moved)}, "split", 0)


# =====================================================================
# 交易写入 (C47–C50: 金额必须 > 0; 退款为独立普通记账)
# =====================================================================

def _parse_amount(raw: Any) -> Decimal:
    """C85/C86: 金额必须为可解析的正数十进制。"""
    try:
        v = Decimal(str(raw))
    except (InvalidOperation, ValueError):
        raise InvalidFilter(
            f"金额格式非法: {raw!r}", field="amount", reason="bad_amount_format"
        )
    if v <= ZERO:
        # C85/C86 + T19: 负数与零金额保存失败
        raise InvalidFilter(
            "交易金额必须大于零。", field="amount", reason="non_positive_amount",
            extra={"amount": str(raw)},
        )
    return v


def _valid_date(raw: Any, field: str) -> str:
    try:
        d = datetime.strptime(str(raw), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        raise InvalidFilter(
            f"日期格式非法: {raw!r} (应为 YYYY-MM-DD)", field=field, reason="bad_date"
        )
    return d.isoformat()


@app.post("/api/transactions")
def create_transaction(request: Request, body: Dict[str, Any]):
    book_id = body.get("book_id")
    _require_book(str(book_id), request)

    ttype = (body.get("type") or "expense").lower()
    if ttype not in ("expense", "income"):
        raise InvalidFilter("type 应为 expense / income。", field="type", reason="bad_type")

    amount = _parse_amount(body.get("amount"))

    tx_date = _valid_date(body.get("transaction_date") or date.today().isoformat(),
                          "transaction_date")
    tx_time = str(body.get("transaction_time") or "12:00:00")
    try:
        datetime.strptime(tx_time, "%H:%M:%S")
    except ValueError:
        raise InvalidFilter(
            f"时间格式非法: {tx_time!r} (应为 HH:MM:SS)",
            field="transaction_time", reason="bad_time",
        )

    category_id = body.get("category_id")
    cat_snapshot = None
    if category_id:
        cat = fetch_one("SELECT * FROM category WHERE id = ?", (category_id,))
        if cat is None or cat["status"] == "deleted":
            raise InvalidFilter(
                f"分类不存在或已删除: {category_id}",
                field="category_id", reason="category_missing",
            )
        if cat["type"] != ttype:
            # C113: 收支分类独立
            raise InvalidFilter(
                f"分类 {cat['name']} 是 {cat['type']} 分类, 与交易类型 {ttype} 不符。",
                field="category_id", reason="category_type_mismatch",
            )
        cat_snapshot = cat["name"]

    counterparty_id = body.get("counterparty_id")
    cp_snapshot = None
    if counterparty_id:
        cp = fetch_one("SELECT * FROM counterparty WHERE id = ?", (counterparty_id,))
        if cp is None:
            raise InvalidFilter(
                f"交易对象不存在: {counterparty_id}",
                field="counterparty_id", reason="counterparty_missing",
            )
        cp_snapshot = cp["name"]

    primary_tag_id = body.get("primary_tag_id")
    aux_tag_ids = list(body.get("tag_ids") or [])
    for tid in [primary_tag_id, *aux_tag_ids]:
        if tid and fetch_one("SELECT 1 FROM tag WHERE id = ?", (tid,)) is None:
            raise InvalidFilter(f"标签不存在: {tid}", field="tag_ids", reason="tag_missing")

    txid = _new_id("tx")
    now = _now_iso()
    conn = get_conn()
    # 写锁: 序列化整个写事务 (INSERT + 标签 + 版本 bump + 缓存失效),
    # 避免 16 线程并发下 SQLite 写锁竞争导致 database is locked / 长等待。
    with write_lock:
        conn.execute(
            'INSERT INTO "transaction" (id, book_id, type, amount, currency, transaction_date, '
            "transaction_time, category_id, category_name_snapshot, counterparty_id, "
            "counterparty_name_snapshot, note, amount_anomaly, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)",
            (txid, book_id, ttype, money_str(amount), body.get("currency") or "CNY",
             tx_date, tx_time, category_id, cat_snapshot, counterparty_id, cp_snapshot,
             body.get("note") or "", now, now),
        )
        # 标签关联: primary -> main; tag_ids -> aux (C58: 每笔最多一个 main)
        if primary_tag_id:
            conn.execute(
                "INSERT OR IGNORE INTO transaction_tag (id, transaction_id, tag_id, role, created_at) "
                "VALUES (?, ?, ?, 'main', ?)",
                (_new_id("tt"), txid, primary_tag_id, now),
            )
        for tid in aux_tag_ids:
            if tid == primary_tag_id:
                continue  # 同一交易同标签唯一
            conn.execute(
                "INSERT OR IGNORE INTO transaction_tag (id, transaction_id, tag_id, role, created_at) "
                "VALUES (?, ?, ?, 'aux', ?)",
                (_new_id("tt"), txid, tid, now),
            )
        _commit()
        version = bump_book_version(str(book_id))
        invalidate_cache(str(book_id))

    data = {
        "id": txid, "transaction_id": txid, "book_id": book_id, "type": ttype,
        "amount": money_str(amount), "transaction_date": tx_date,
        "transaction_time": tx_time, "category_id": category_id,
        "counterparty_id": counterparty_id, "note": body.get("note") or "",
    }
    return _envelope(data, f"tx:{txid}", version)


@app.patch("/api/transactions/{txid}")
def patch_transaction(txid: str, request: Request, body: Dict[str, Any]):
    row = fetch_one('SELECT * FROM "transaction" WHERE id = ?', (txid,))
    if row is None:
        raise InvalidFilter(f"交易不存在: {txid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    _require_book(row["book_id"], request)

    updates: Dict[str, Any] = {}
    if "amount" in body:
        updates["amount"] = money_str(_parse_amount(body["amount"]))
    if "type" in body:
        ttype = body["type"].lower()
        if ttype not in ("expense", "income"):
            raise InvalidFilter("type 应为 expense / income。",
                                field="type", reason="bad_type")
        updates["type"] = ttype
    if "transaction_date" in body:
        updates["transaction_date"] = _valid_date(body["transaction_date"], "transaction_date")
    if "transaction_time" in body:
        updates["transaction_time"] = str(body["transaction_time"])
    if "note" in body:
        updates["note"] = str(body["note"])
    if "category_id" in body:
        cid = body["category_id"]
        if cid:
            cat = fetch_one("SELECT * FROM category WHERE id = ?", (cid,))
            if cat is None or cat["status"] == "deleted":
                raise InvalidFilter(f"分类不存在: {cid}",
                                    field="category_id", reason="category_missing")
            ttype = updates.get("type", row["type"])
            if cat["type"] != ttype:
                raise InvalidFilter("分类收支类型与交易不符。",
                                    field="category_id", reason="category_type_mismatch")
            updates["category_id"] = cid
            updates["category_name_snapshot"] = cat["name"]
        else:
            updates["category_id"] = None
            updates["category_name_snapshot"] = None
    if "counterparty_id" in body:
        cpid = body["counterparty_id"]
        if cpid:
            cp = fetch_one("SELECT * FROM counterparty WHERE id = ?", (cpid,))
            if cp is None:
                raise InvalidFilter(f"对象不存在: {cpid}",
                                    field="counterparty_id", reason="counterparty_missing")
            updates["counterparty_id"] = cpid
            updates["counterparty_name_snapshot"] = cp["name"]
        else:
            updates["counterparty_id"] = None
            updates["counterparty_name_snapshot"] = None

    now = _now_iso()
    if updates:
        sets = ", ".join(f"{k} = ?" for k in updates)
        conn = get_conn()
        conn.execute(
            f'UPDATE "transaction" SET {sets}, updated_at = ? WHERE id = ?',
            (*updates.values(), now, txid),
        )
        _commit()

    # 标签更新
    conn = get_conn()
    if "primary_tag_id" in body:
        conn.execute(
            "DELETE FROM transaction_tag WHERE transaction_id = ? AND role = 'main'", (txid,)
        )
        pid = body["primary_tag_id"]
        if pid:
            conn.execute(
                "INSERT OR IGNORE INTO transaction_tag (id, transaction_id, tag_id, role, created_at) "
                "VALUES (?, ?, ?, 'main', ?)",
                (_new_id("tt"), txid, pid, now),
            )
        _commit()
    if "tag_ids" in body:
        conn.execute(
            "DELETE FROM transaction_tag WHERE transaction_id = ? AND role = 'aux'", (txid,)
        )
        for tid in body["tag_ids"] or []:
            conn.execute(
                "INSERT OR IGNORE INTO transaction_tag (id, transaction_id, tag_id, role, created_at) "
                "VALUES (?, ?, ?, 'aux', ?)",
                (_new_id("tt"), txid, tid, now),
            )
        _commit()

    version = bump_book_version(row["book_id"])
    invalidate_cache(row["book_id"])
    updated = calc.query_transaction_detail(txid, row["book_id"])
    return _envelope(updated, f"tx:{txid}", version)


@app.delete("/api/transactions/{txid}")
def delete_transaction(txid: str, request: Request, book_id: Optional[str] = Query(None)):
    row = fetch_one('SELECT book_id FROM "transaction" WHERE id = ?', (txid,))
    if row is None:
        raise InvalidFilter(f"交易不存在: {txid}", field="id", reason="not_found",
                            code="NOT_FOUND", status_code=404)
    bid = book_id or row["book_id"]
    _require_book(bid, request)
    conn = get_conn()
    conn.execute("DELETE FROM transaction_tag WHERE transaction_id = ?", (txid,))
    conn.execute('DELETE FROM "transaction" WHERE id = ?', (txid,))
    _commit()
    version = bump_book_version(bid)
    invalidate_cache(bid)
    return _envelope({"id": txid, "deleted": True}, f"tx:{txid}", version)
