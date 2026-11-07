# -*- coding: utf-8 -*-
"""
本地桩服务 (stub) —— 仅用于校验 acceptance 测试脚本自身的连通性与断言逻辑。

用途:
  - 在 server/ 尚未就绪时, 验证 harness / fixtures / test_cases 能否跑通。
  - 不属于验收交付物的一部分, 不替代真实服务端验收。

启动:
    python acceptance/stub_server.py  (默认 127.0.0.1:8899)

实现要点: 覆盖 TECH 02 约定的接口, 金额用十进制字符串, 附带
snapshot_version、比较指标、日均等字段, 以便测试脚本各分支都能被执行。
"""
from __future__ import annotations

import os
import sys
import threading
import uuid
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi import FastAPI, Query, Request, HTTPException
from fastapi.responses import JSONResponse

app = FastAPI(title="Account Statistics Stub")

LOCK = threading.Lock()

BOOKS: Dict[str, Dict[str, Any]] = {}
CATEGORIES: Dict[str, Dict[str, Any]] = {}
TAGS: Dict[str, Dict[str, Any]] = {}
COUNTERPARTIES: Dict[str, Dict[str, Any]] = {}
TXS: Dict[str, Dict[str, Any]] = {}
VERSIONS: Dict[str, int] = {}
GLOBAL_DIM_VERSION = 1


def _now() -> str:
    return datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _dec(v: Any) -> Decimal:
    if v is None:
        return Decimal("0")
    return Decimal(str(v))


def _s(v: Decimal) -> str:
    return str(v.quantize(Decimal("0.01")))


def _book_version(book_id: str) -> int:
    return VERSIONS.get(book_id, 1)


def _bump(book_id: str) -> int:
    VERSIONS[book_id] = _book_version(book_id) + 1
    return VERSIONS[book_id]


def _resolve_category(cat_id: str) -> Optional[Dict[str, Any]]:
    cat = CATEGORIES.get(cat_id)
    if not cat:
        return None
    if cat.get("parent_id"):
        parent = CATEGORIES.get(cat["parent_id"])
        if parent:
            return parent
    return cat


def _tx_match(t: Dict[str, Any], params: Dict[str, Any]) -> bool:
    book_id = params.get("book_id")
    if book_id and t["book_id"] != book_id:
        return False
    start = params.get("start_date")
    end = params.get("end_date")
    if start and t["transaction_date"] < start:
        return False
    if end and t["transaction_date"] > end:
        return False
    ttype = params.get("type")
    if ttype in ("income", "expense") and t["type"] != ttype:
        return False

    def _ids(key: str) -> List[str]:
        v = params.get(key)
        if v is None:
            return []
        if isinstance(v, str):
            return [x for x in v.split(",") if x]
        return list(v)

    # 分类筛选 (父子展开 + 去重)
    for mode_key, ids_key, side in (("income_category_mode", "income_category_ids", "income"),
                                    ("expense_category_mode", "expense_category_ids", "expense")):
        mode = params.get(mode_key)
        if not mode:
            continue
        if side != "expense" and t["type"] != side:
            return False
        if side == "expense" and t["type"] != "expense":
            continue
        if mode.upper() != "SELECTED":
            continue
        ids = set(_ids(ids_key))
        if not ids:
            continue
        cid = t.get("category_id")
        if not cid:
            return False
        # 父子展开
        expanded = set(ids)
        for i in list(ids):
            for c in CATEGORIES.values():
                if c.get("parent_id") == i:
                    expanded.add(c["id"])
        if cid not in expanded:
            return False

    # 标签筛选
    tag_ids = _ids("tag_ids")
    if tag_ids:
        hit = False
        for tid in tag_ids:
            for tt in TXS.get(t["id"], {}).get("_tags", {}).items():
                if tt == tid:
                    hit = True
                    break
        if not hit:
            return False
    return True


def _aggregate(params: Dict[str, Any]) -> Dict[str, Any]:
    income = Decimal("0")
    expense = Decimal("0")
    ic = ec = 0
    for t in TXS.values():
        if not _tx_match(t, params):
            continue
        if t["type"] == "income":
            income += _dec(t["amount"])
            ic += 1
        else:
            expense += _dec(t["amount"])
            ec += 1
    return {"income": income, "expense": expense,
            "income_count": ic, "expense_count": ec,
            "count": ic + ec, "balance": income - expense}


def _meta(book_id: str, params: Dict[str, Any]) -> Dict[str, Any]:
    return {"snapshot_version": _book_version(book_id),
            "query_key": str(sorted(params.items())),
            "generated_at": _now()}


def _granularity_for(start: str, end: str) -> str:
    s = datetime.strptime(start, "%Y-%m-%d").date()
    e = datetime.strptime(end, "%Y-%m-%d").date()
    days = (e - s).days + 1
    if days <= 31:
        return "day"
    if days <= 365:
        return "week"
    return "month"


# ---------------------------------------------------------------- 写入接口
@app.post("/api/books")
def create_book(body: Dict[str, Any]):
    bid = _new_id("book")
    BOOKS[bid] = {"id": bid, "name": body.get("name", ""), "members": []}
    VERSIONS[bid] = 1
    return {"data": {"book_id": bid, "id": bid, "name": body.get("name", "")},
            "meta": {"snapshot_version": 1}}


@app.get("/api/books")
def list_books():
    return {"data": [{"book_id": b, "id": b, "name": v["name"]}
                     for b, v in BOOKS.items()], "meta": {}}


@app.post("/api/categories")
def create_category(body: Dict[str, Any]):
    cid = _new_id("cat")
    CATEGORIES[cid] = {"id": cid, "name": body.get("name", ""),
                        "type": body.get("type", "expense"),
                        "parent_id": body.get("parent_id"),
                        "status": "active"}
    return {"data": {"category_id": cid, "id": cid, "name": body.get("name", ""),
                     "parent_id": body.get("parent_id"), "status": "active"},
            "meta": {}}


@app.get("/api/categories")
def list_categories(type: Optional[str] = None):
    return {"data": [{"category_id": c, "id": c, "name": v["name"],
                      "type": v["type"], "parent_id": v.get("parent_id"),
                      "status": v.get("status", "active")}
                     for c, v in CATEGORIES.items()
                     if type is None or v["type"] == type], "meta": {}}


@app.patch("/api/categories/{cid}")
def patch_category(cid: str, body: Dict[str, Any]):
    c = CATEGORIES.get(cid)
    if not c:
        raise HTTPException(404, "not found")
    c.update({k: v for k, v in body.items() if k in ("name", "status")})
    return {"data": {"category_id": cid, **c}, "meta": {}}


@app.delete("/api/categories/{cid}")
def delete_category(cid: str):
    c = CATEGORIES.get(cid)
    if not c:
        raise HTTPException(404, "not found")
    c["status"] = "deleted"
    return {"data": {"category_id": cid, "status": "deleted"}, "meta": {}}


@app.post("/api/tags")
def create_tag(body: Dict[str, Any]):
    tid = _new_id("tag")
    TAGS[tid] = {"id": tid, "name": body.get("name", ""),
                 "status": "active", "scope": body.get("scope", "both")}
    return {"data": {"tag_id": tid, "id": tid, "name": body.get("name", "")},
            "meta": {}}


@app.get("/api/tags")
def list_tags():
    return {"data": [{"tag_id": t, "id": t, "name": v["name"],
                      "status": v.get("status", "active")} for t, v in TAGS.items()],
            "meta": {}}


@app.patch("/api/tags/{tid}")
def patch_tag(tid: str, body: Dict[str, Any]):
    t = TAGS.get(tid)
    if not t:
        raise HTTPException(404, "not found")
    t.update({k: v for k, v in body.items() if k in ("name", "status", "scope")})
    return {"data": {"tag_id": tid, **t}, "meta": {}}


@app.post("/api/counterparties")
def create_counterparty(body: Dict[str, Any]):
    cid = _new_id("cp")
    COUNTERPARTIES[cid] = {"id": cid, "name": body.get("name", ""), "status": "active"}
    return {"data": {"counterparty_id": cid, "id": cid, "name": body.get("name", "")},
            "meta": {}}


@app.get("/api/counterparties")
def list_counterparties():
    return {"data": [{"counterparty_id": c, "id": c, "name": v["name"]}
                     for c, v in COUNTERPARTIES.items()], "meta": {}}


@app.post("/api/transactions")
def create_transaction(body: Dict[str, Any]):
    amount = _dec(body.get("amount"))
    if amount <= 0:
        return JSONResponse(status_code=400,
                            content={"error": {"code": "INVALID_AMOUNT",
                                               "message": "金额必须大于零"}})
    tid = _new_id("tx")
    TXS[tid] = {
        "id": tid, "book_id": body.get("book_id"),
        "type": body.get("type", "expense"),
        "amount": _s(amount),
        "transaction_date": body.get("transaction_date"),
        "transaction_time": body.get("transaction_time", "12:00:00"),
        "category_id": body.get("category_id"),
        "counterparty_id": body.get("counterparty_id"),
        "note": body.get("note", ""),
        "_tags": {},
    }
    if body.get("primary_tag_id"):
        TXS[tid]["_tags"][body["primary_tag_id"]] = "main"
    for x in body.get("tag_ids") or []:
        TXS[tid]["_tags"].setdefault(x, "aux")
    _bump(body.get("book_id"))
    return {"data": {"transaction_id": tid, "id": tid, "amount": _s(amount)},
            "meta": {"snapshot_version": _book_version(body.get("book_id"))}}


@app.patch("/api/transactions/{tid}")
def patch_transaction(tid: str, body: Dict[str, Any]):
    t = TXS.get(tid)
    if not t:
        raise HTTPException(404, "not found")
    if "amount" in body:
        a = _dec(body["amount"])
        if a <= 0:
            return JSONResponse(status_code=400,
                                content={"error": {"code": "INVALID_AMOUNT"}})
        t["amount"] = _s(a)
    for k in ("note", "transaction_date", "transaction_time"):
        if k in body:
            t[k] = body[k]
    _bump(t["book_id"])
    return {"data": {"transaction_id": tid, **t}, "meta": {}}


@app.delete("/api/transactions/{tid}")
def delete_transaction(tid: str):
    t = TXS.pop(tid, None)
    if not t:
        raise HTTPException(404, "not found")
    _bump(t["book_id"])
    return {"data": {"transaction_id": tid, "deleted": True}, "meta": {}}


# ---------------------------------------------------------------- 统计接口
def _params(request: Request) -> Dict[str, Any]:
    q = request.query_params
    out: Dict[str, Any] = {}
    for k in q.keys():
        v = q.get(k)
        if k.endswith("_ids"):
            out[k] = [x for x in v.split(",") if x]
        else:
            out[k] = v
    return out


def _validate(params: Dict[str, Any]) -> Optional[JSONResponse]:
    start = params.get("start_date")
    end = params.get("end_date")
    today_s = date.today().isoformat()
    if start and end and start > end:
        return JSONResponse(status_code=400,
                            content={"error": {"code": "INVALID_FILTER",
                                               "field": "start_date",
                                               "message": "起始日不得晚于结束日"}})
    if end and end > today_s:
        return JSONResponse(status_code=400,
                            content={"error": {"code": "INVALID_FILTER",
                                               "field": "end_date",
                                               "message": "日期不得进入未来"}})
    for side in ("income", "expense"):
        mode = params.get(f"{side}_category_mode")
        if mode and mode.upper() == "SELECTED" and not params.get(f"{side}_category_ids"):
            return JSONResponse(status_code=400,
                                content={"error": {"code": "INVALID_FILTER",
                                                   "field": f"{side}_category_ids",
                                                   "message": "SELECTED 必须有有效 ID"}})
    return None


@app.get("/api/statistics/summary")
def summary(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    book_id = p.get("book_id")
    agg = _aggregate(p)
    income, expense = agg["income"], agg["expense"]
    balance = income - expense
    rate = None if income == 0 else (balance / income * 100).quantize(Decimal("0.01"))
    data = {
        "income": _s(income), "expense": _s(expense), "balance": _s(balance),
        "balance_rate": None if rate is None else str(rate),
        "income_count": agg["income_count"], "expense_count": agg["expense_count"],
        "count": agg["count"],
    }
    start, end = p.get("start_date"), p.get("end_date")
    if start and end:
        days = (datetime.strptime(end, "%Y-%m-%d").date()
                - datetime.strptime(start, "%Y-%m-%d").date()).days + 1
        data["daily_average"] = _s(income / days) if days else "0.00"
        data["expense_daily_average"] = _s(expense / days) if days else "0.00"
    # 同期
    if p.get("comparison_enabled") in ("true", "True", "1", 1, True):
        if start and end:
            s = datetime.strptime(start, "%Y-%m-%d").date()
            e = datetime.strptime(end, "%Y-%m-%d").date()
            days = (e - s).days + 1
            pp = dict(p)
            pp["start_date"] = (s - timedelta(days=days)).isoformat()
            pp["end_date"] = (e - timedelta(days=days)).isoformat()
            pa = _aggregate(pp)
            pbal = pa["income"] - pa["expense"]
            diff = balance - pbal
            crate = None if pbal <= 0 else (diff / pbal * 100).quantize(Decimal("0.01"))
            data["comparison"] = {
                "start_date": pp["start_date"], "end_date": pp["end_date"],
                "income": _s(pa["income"]), "expense": _s(pa["expense"]),
                "balance": _s(pbal),
                "difference": _s(diff),
                "change_rate": None if crate is None else str(crate),
            }
    return {"data": data, "meta": _meta(book_id, p)}


@app.get("/api/statistics/trend")
def trend(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    start, end = p.get("start_date"), p.get("end_date")
    g = p.get("granularity")
    if not start or not end:
        return JSONResponse(status_code=400, content={"error": {"code": "INVALID_FILTER"}})
    if g in (None, "auto", ""):
        g = _granularity_for(start, end)
    s = datetime.strptime(start, "%Y-%m-%d").date()
    e = datetime.strptime(end, "%Y-%m-%d").date()
    pts: List[Dict[str, Any]] = []
    if g == "day":
        cur = s
        while cur <= e:
            bs = cur.isoformat()
            be = cur.isoformat()
            q = dict(p); q["start_date"] = bs; q["end_date"] = be
            a = _aggregate(q)
            pts.append({"bucket_start": bs, "bucket_end": be,
                        "income": _s(a["income"]), "expense": _s(a["expense"]),
                        "balance": _s(a["income"] - a["expense"])})
            cur += timedelta(days=1)
    elif g == "week":
        cur = s - timedelta(days=s.weekday())
        while cur <= e:
            bs = max(cur, s).isoformat()
            be = min(cur + timedelta(days=6), e).isoformat()
            q = dict(p); q["start_date"] = bs; q["end_date"] = be
            a = _aggregate(q)
            pts.append({"bucket_start": bs, "bucket_end": be,
                        "income": _s(a["income"]), "expense": _s(a["expense"]),
                        "balance": _s(a["income"] - a["expense"])})
            cur += timedelta(days=7)
    else:
        cur = s.replace(day=1)
        while cur <= e:
            nxt = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
            bs = max(cur, s).isoformat()
            be = min(nxt - timedelta(days=1), e).isoformat()
            q = dict(p); q["start_date"] = bs; q["end_date"] = be
            a = _aggregate(q)
            pts.append({"bucket_start": bs, "bucket_end": be,
                        "income": _s(a["income"]), "expense": _s(a["expense"]),
                        "balance": _s(a["income"] - a["expense"])})
            cur = nxt
    return {"data": {"items": pts, "granularity": g, "points": pts},
            "meta": _meta(p.get("book_id"), p)}


@app.get("/api/statistics/categories")
def categories(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    agg_by: Dict[str, Decimal] = {}
    cnt_by: Dict[str, int] = {}
    for t in TXS.values():
        if not _tx_match(t, p):
            continue
        cid = t.get("category_id")
        key = cid or "__unset__"
        agg_by[key] = agg_by.get(key, Decimal("0")) + _dec(t["amount"])
        cnt_by[key] = cnt_by.get(key, 0) + 1
    items: List[Dict[str, Any]] = []
    total = sum(agg_by.values())
    for cid, amt_ in agg_by.items():
        if amt_ == 0:
            continue
        if cid == "__unset__":
            name, typ, lvl = "未分类", p.get("type", "expense"), 1
            cid_out = None
        else:
            cat = CATEGORIES.get(cid)
            if cat is None:
                continue
            cid_out = cid
            if cat.get("parent_id"):
                name = cat["name"]
                typ, lvl = cat["type"], 2
            else:
                name = cat["name"]
                typ, lvl = cat["type"], 1
        items.append({"category_id": cid_out, "id": cid_out, "name": name,
                      "type": typ, "level": lvl, "amount": _s(amt_),
                      "count": cnt_by.get(cid, 0),
                      "percentage": _s(amt_ / total * 100) if total else "0.00"})
    items.sort(key=lambda x: _dec(x["amount"]), reverse=True)
    return {"data": {"items": items, "categories": items},
            "meta": _meta(p.get("book_id"), p)}


@app.get("/api/statistics/tags")
def tags(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    main_amt: Dict[str, Decimal] = {}
    main_cnt: Dict[str, int] = {}
    unset = Decimal("0")
    unset_cnt = 0
    for t in TXS.values():
        if not _tx_match(t, p):
            continue
        roles = t.get("_tags", {})
        mains = [k for k, v in roles.items() if v == "main"]
        if mains:
            for m in mains:
                main_amt[m] = main_amt.get(m, Decimal("0")) + _dec(t["amount"])
                main_cnt[m] = main_cnt.get(m, 0) + 1
        else:
            unset += _dec(t["amount"])
            unset_cnt += 1
    total = sum(main_amt.values()) + unset
    items: List[Dict[str, Any]] = []
    for tid, amt_ in main_amt.items():
        if amt_ == 0:
            continue
        items.append({"tag_id": tid, "id": tid, "name": TAGS.get(tid, {}).get("name", tid),
                      "amount": _s(amt_), "count": main_cnt.get(tid, 0),
                      "percentage": _s(amt_ / total * 100) if total else "0.00"})
    items.sort(key=lambda x: _dec(x["amount"]), reverse=True)
    if unset != 0:
        items.append({"tag_id": None, "id": None, "name": "未设置标签",
                      "amount": _s(unset), "count": unset_cnt,
                      "percentage": _s(unset / total * 100) if total else "0.00"})
    top = items[:5]
    rest = items[5:]
    chart = list(top)
    if rest:
        chart.append({"name": "其他", "amount": _s(sum(_dec(x["amount"]) for x in rest)),
                      "count": sum(x["count"] for x in rest)})
    return {"data": {"items": items, "tags": items, "chart": chart,
                     "donut": chart},
            "meta": _meta(p.get("book_id"), p)}


@app.get("/api/statistics/merchants")
def merchants(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    agg_by: Dict[str, Decimal] = {}
    cnt_by: Dict[str, int] = {}
    for t in TXS.values():
        if not _tx_match(t, p):
            continue
        cid = t.get("counterparty_id")
        key = cid or "__unset__"
        agg_by[key] = agg_by.get(key, Decimal("0")) + _dec(t["amount"])
        cnt_by[key] = cnt_by.get(key, 0) + 1
    items: List[Dict[str, Any]] = []
    total = sum(agg_by.values())
    for cid, amt_ in agg_by.items():
        if amt_ == 0:
            continue
        if cid == "__unset__":
            items.append({"counterparty_id": None, "id": None, "name": "未设置商户",
                          "amount": _s(amt_), "count": cnt_by.get(cid, 0),
                          "percentage": _s(amt_ / total * 100) if total else "0.00"})
        else:
            c = COUNTERPARTIES.get(cid)
            if not c:
                continue
            items.append({"counterparty_id": cid, "id": cid, "name": c["name"],
                          "amount": _s(amt_), "count": cnt_by.get(cid, 0),
                          "percentage": _s(amt_ / total * 100) if total else "0.00"})
    items.sort(key=lambda x: _dec(x["amount"]), reverse=True)
    return {"data": {"items": items, "merchants": items},
            "meta": _meta(p.get("book_id"), p)}


@app.get("/api/statistics/balance")
def balance(request: Request):
    return summary(request)


@app.get("/api/transactions")
def transactions(request: Request):
    p = _params(request)
    err = _validate(p)
    if err:
        return err
    rows = [t for t in TXS.values() if _tx_match(t, p)]
    rows.sort(key=lambda t: (t["transaction_date"], t["transaction_time"]), reverse=True)
    page = int(p.get("page", 1) or 1)
    size = int(p.get("page_size", 50) or 50)
    total = len(rows)
    page_rows = rows[(page - 1) * size: page * size]
    data = [{
        "transaction_id": t["id"], "id": t["id"], "type": t["type"],
        "amount": t["amount"], "transaction_date": t["transaction_date"],
        "transaction_time": t["transaction_time"],
        "category_id": t.get("category_id"),
        "category_name": (CATEGORIES.get(t.get("category_id"), {}) or {}).get("name"),
        "counterparty_id": t.get("counterparty_id"),
        "counterparty_name": (COUNTERPARTIES.get(t.get("counterparty_id"), {}) or {}).get("name"),
        "note": t.get("note", ""),
    } for t in page_rows]
    return {"data": data, "items": data,
            "meta": {"total": total, "page": page, "page_size": size,
                     "snapshot_version": _book_version(p.get("book_id"))}}


@app.get("/api/transactions/{tid}")
def transaction_detail(tid: str, request: Request):
    t = TXS.get(tid)
    if not t:
        raise HTTPException(404, "not found")
    return {"data": {"transaction_id": tid, **t}, "meta": {}}


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("STUB_PORT", "8899"))
    uvicorn.run(app, host="127.0.0.1", port=port, log_level="warning")
