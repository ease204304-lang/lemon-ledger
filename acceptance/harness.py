# -*- coding: utf-8 -*-
"""
小猪记账 — 记账统计模块 验收测试公共支撑 (acceptance harness)

职责:
  1. HTTP 客户端封装 (httpx, 直连真实服务)
  2. 测试数据准备 (账本 / 分类 / 标签 / 交易对象 / 交易)
  3. 结果对象 TestResult, 供 test_cases.py 填充, run_all.py 汇总
  4. 证据落盘 (JSON 响应 -> docs/acceptance-evidence/)

设计原则:
  - 只使用 TECH 02 「统计查询契约」中约定的接口路径与字段名。
  - 不修改 server/ 下任何实现代码; 需要特殊数据时通过 API 写入,
    或退化为 BLOCKED 判定。
  - 所有金额按十进制字符串比较, 避免浮点误差 (C84)。
"""
from __future__ import annotations

import json
import os
import re
import threading
import time
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import httpx

# --------------------------------------------------------------------------
# 路径常量
# --------------------------------------------------------------------------
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EVIDENCE_DIR = os.path.join(ROOT, "docs", "acceptance-evidence")
SCREENSHOT_DIR = os.path.join(ROOT, "docs", "screenshots", "acceptance")

DEFAULT_BASE_URL = os.environ.get("ACCOUNT_API_BASE", "http://127.0.0.1:8000")
TIMEOUT = float(os.environ.get("ACCOUNT_API_TIMEOUT", "60"))

# --------------------------------------------------------------------------
# 结果对象
# --------------------------------------------------------------------------
PASS = "PASS"
FAIL = "FAIL"
BLOCKED = "BLOCKED"

#: 级别映射 (来自 《测试与验收清单》「执行用例」sheet R5:R38)
TEST_LEVELS: Dict[str, str] = {
    "T01": "P0", "T02": "P0", "T03": "P0", "T04": "P0", "T05": "P1",
    "T06": "P0", "T07": "P0", "T08": "P0", "T09": "P0", "T10": "P0",
    "T11": "P0", "T12": "P0", "T13": "P1", "T14": "P1",
    "T15": "P0", "T16": "P1", "T17": "P1", "T18": "P1", "T19": "P0",
    "T20": "P1", "T21": "P1", "T22": "P1", "T23": "P0", "T24": "P0",
    "T25": "P1", "T26": "P0", "T27": "P0", "T28": "P1", "T29": "P2",
    "T30": "P0", "T31": "P1", "T32": "P0", "T33": "P0", "T34": "P1",
}

#: P0 门槛用例 (必须全过才发布)
P0_CASES = [k for k, v in TEST_LEVELS.items() if v == "P0"]

#: 受未决规则 D02/D05/D06/D07 影响的用例 -> 报告需加注「按 PRD v0.9 建议口径, 待最终确认」
D_RULE_CASES: Dict[str, str] = {
    "T02": "D06", "T10": "D06", "T11": "D06", "T13": "D06", "T20": "D06",
    "T24": "D02", "T22": "D06", "T34": "D06",
    "T18": "D05", "T17": "D05",
    "T32": "D07", "T30": "D07",
}

#: 性能门槛用例
PERF_CASES = {"T14"}


@dataclass
class TestResult:
    """单条用例的执行结果。"""
    id: str
    level: str
    name: str
    result: str = BLOCKED
    actual: Any = None
    expected: Any = None
    evidence: List[str] = field(default_factory=list)
    reason: str = ""            # BLOCKED 阻塞原因 / FAIL 差异说明
    duration_ms: float = 0.0
    d_rule: str = ""            # 关联未决规则 D0x

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "level": self.level,
            "name": self.name,
            "result": self.result,
            "actual": self.actual,
            "expected": self.expected,
            "evidence": self.evidence,
            "reason": self.reason,
            "duration_ms": round(self.duration_ms, 1),
            "d_rule": self.d_rule,
        }


class CaseContext:
    """用例执行上下文: 持有 client, 测试数据, 证据收集器。"""

    def __init__(self, client: "ApiClient", case_id: str, name: str):
        self.client = client
        self.case_id = case_id
        self.name = name
        self.evidence: List[str] = []
        self.started = time.perf_counter()

    # -- 证据 ---------------------------------------------------------------
    def save_evidence(self, payload: Any, label: str = "") -> str:
        """把 JSON 响应写入 docs/acceptance-evidence/<case_id>/<label>.json"""
        d = os.path.join(EVIDENCE_DIR, self.case_id)
        os.makedirs(d, exist_ok=True)
        label = label or "evidence"
        safe = re.sub(r"[^0-9A-Za-z_.-]", "_", label)
        path = os.path.join(d, safe + ".json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2, default=str)
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        self.evidence.append(rel)
        return rel

    def note(self, text: str) -> None:
        self.evidence.append(text)

    @property
    def elapsed_ms(self) -> float:
        return (time.perf_counter() - self.started) * 1000.0


# --------------------------------------------------------------------------
# 断言工具
# --------------------------------------------------------------------------
class CheckFailed(Exception):
    """断言失败 -> 用例 FAIL。"""


def fail(msg: str) -> "CheckFailed":
    return CheckFailed(msg)


def dec(v: Any) -> Optional[Decimal]:
    """把响应中的金额字符串/数字转 Decimal。"""
    if v is None:
        return None
    if isinstance(v, Decimal):
        return v
    if isinstance(v, (int, float)):
        return Decimal(str(v))
    s = str(v).strip()
    if s in ("", "—", "-", "null", "None"):
        return None
    s = s.replace(",", "").replace("，", "")
    try:
        return Decimal(s)
    except Exception:
        return None


def amt(v: Any) -> str:
    """金额规范化到 2 位小数字符串, 用于比较。"""
    d = dec(v)
    if d is None:
        return "<none>"
    return str(d.quantize(Decimal("0.01")))


def pct(v: Any) -> Optional[Decimal]:
    """百分比规范化到 2 位小数。null/— 返回 None。"""
    d = dec(v)
    if d is None:
        return None
    return d.quantize(Decimal("0.01"))


def eq_amount(actual: Any, expected: str, label: str = "金额") -> None:
    a, e = amt(actual), amt(expected)
    if a != e:
        raise fail(f"{label} 期望 {e}, 实测 {a}")


def eq_percent(actual: Any, expected: Optional[str], label: str = "比率") -> None:
    """expected 为 None 表示期望 null (显示「—」)。"""
    if expected is None:
        if pct(actual) is not None:
            raise fail(f"{label} 期望 null(—), 实测 {actual}")
        return
    a, e = pct(actual), pct(expected)
    if a != e:
        raise fail(f"{label} 期望 {e}%, 实测 {a}%")


def eq_bool(actual: Any, expected: bool, label: str) -> None:
    if bool(actual) != expected:
        raise fail(f"{label} 期望 {expected}, 实测 {actual}")


def eq_int(actual: Any, expected: int, label: str) -> None:
    try:
        a = int(actual)
    except Exception:
        raise fail(f"{label} 期望 {expected}, 实测 {actual!r} (非整数)")
    if a != expected:
        raise fail(f"{label} 期望 {expected}, 实测 {a}")


def eq_str(actual: Any, expected: str, label: str) -> None:
    if str(actual) != expected:
        raise fail(f"{label} 期望 {expected!r}, 实测 {actual!r}")


# --------------------------------------------------------------------------
# HTTP 客户端
# --------------------------------------------------------------------------
class ApiClient:
    """薄封装 httpx.Client, 暴露统计与交易接口。"""

    def __init__(self, base_url: str = DEFAULT_BASE_URL, timeout: float = TIMEOUT):
        self.base_url = base_url.rstrip("/")
        self._client = httpx.Client(base_url=self.base_url, timeout=timeout)
        self._lock = threading.Lock()
        self.request_log: List[Dict[str, Any]] = []

    # -- 生命周期 -----------------------------------------------------------
    def close(self) -> None:
        try:
            self._client.close()
        except Exception:
            pass

    def __enter__(self) -> "ApiClient":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # -- 底层 ---------------------------------------------------------------
    def request(self, method: str, path: str, *, params: Any = None,
                json_body: Any = None, headers: Any = None,
                expect_status: Optional[Sequence[int]] = None) -> httpx.Response:
        t0 = time.perf_counter()
        resp = self._client.request(method, path, params=params,
                                    json=json_body, headers=headers)
        dt = (time.perf_counter() - t0) * 1000.0
        entry = {
            "method": method, "path": path,
            "params": _jsonable(params), "body": _jsonable(json_body),
            "status": resp.status_code, "elapsed_ms": round(dt, 2),
            "response": _safe_json(resp),
        }
        with self._lock:
            self.request_log.append(entry)
        if expect_status is not None and resp.status_code not in expect_status:
            raise fail(
                f"{method} {path} 期望 HTTP {list(expect_status)}, 实测 {resp.status_code}; "
                f"body={_short(resp.text)}"
            )
        return resp

    def get(self, path: str, **kw) -> httpx.Response:
        return self.request("GET", path, **kw)

    def post(self, path: str, **kw) -> httpx.Response:
        return self.request("POST", path, **kw)

    def put(self, path: str, **kw) -> httpx.Response:
        return self.request("PUT", path, **kw)

    def patch(self, path: str, **kw) -> httpx.Response:
        return self.request("PATCH", path, **kw)

    def delete(self, path: str, **kw) -> httpx.Response:
        return self.request("DELETE", path, **kw)

    # -- 统计接口 (TECH 02) -------------------------------------------------
    def summary(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/summary", params=_clean(params)))

    def trend(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/trend", params=_clean(params)))

    def categories(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/categories", params=_clean(params)))

    def tags(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/tags", params=_clean(params)))

    def merchants(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/merchants", params=_clean(params)))

    def balance(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/statistics/balance", params=_clean(params)))

    def transactions(self, **params) -> Dict[str, Any]:
        return self._data(self.get("/api/transactions", params=_clean(params)))

    def transaction(self, tid: str, **params) -> Dict[str, Any]:
        return self._data(self.get(f"/api/transactions/{tid}", params=_clean(params)))

    # -- 便捷断言辅助 -------------------------------------------------------
    def snapshot_version(self, resp_or_data: Any) -> Optional[str]:
        meta = _meta(resp_or_data)
        if isinstance(meta, dict):
            v = meta.get("snapshot_version", meta.get("version"))
            return None if v is None else str(v)
        return None

    @staticmethod
    def _data(resp: httpx.Response) -> Dict[str, Any]:
        """返回响应体的 data 字段; 若响应体本身就是字典则整体返回。"""
        payload = _safe_json(resp)
        if isinstance(payload, dict) and "data" in payload:
            return payload
        return payload if isinstance(payload, dict) else {"_raw": payload}

    # -- 写入接口 (用于造数) -------------------------------------------------
    def create_book(self, name: str, **extra) -> Dict[str, Any]:
        body = {"name": name}
        body.update(extra)
        return self._data(self.post("/api/books", json_body=body))

    def list_books(self) -> Any:
        return self._data(self.get("/api/books"))

    def create_category(self, name: str, ctype: str, *, parent_id: Any = None,
                        book_id: Any = None, **extra) -> Dict[str, Any]:
        body: Dict[str, Any] = {"name": name, "type": ctype}
        if parent_id is not None:
            body["parent_id"] = parent_id
        if book_id is not None:
            body["book_id"] = book_id
        body.update(extra)
        return self._data(self.post("/api/categories", json_body=body))

    def list_categories(self, **params) -> Any:
        return self._data(self.get("/api/categories", params=_clean(params)))

    def create_tag(self, name: str, **extra) -> Dict[str, Any]:
        body = {"name": name}
        body.update(extra)
        return self._data(self.post("/api/tags", json_body=body))

    def list_tags(self, **params) -> Any:
        return self._data(self.get("/api/tags", params=_clean(params)))

    def create_counterparty(self, name: str, **extra) -> Dict[str, Any]:
        body = {"name": name}
        body.update(extra)
        return self._data(self.post("/api/counterparties", json_body=body))

    def list_counterparties(self, **params) -> Any:
        return self._data(self.get("/api/counterparties", params=_clean(params)))

    def create_transaction(self, **body) -> Dict[str, Any]:
        return self._data(self.post("/api/transactions", json_body=body))

    def update_transaction(self, tid: str, **body) -> Dict[str, Any]:
        return self._data(self.patch(f"/api/transactions/{tid}", json_body=body))

    def delete_transaction(self, tid: str) -> Any:
        return self._data(self.delete(f"/api/transactions/{tid}"))

    def health(self) -> bool:
        try:
            r = self._client.get("/health", timeout=5)
            return r.status_code < 500
        except Exception:
            return False

    def root_alive(self) -> bool:
        try:
            r = self._client.get("/", timeout=5)
            return r.status_code < 500
        except Exception:
            return False


# --------------------------------------------------------------------------
# 辅助函数
# --------------------------------------------------------------------------
def _clean(params: Dict[str, Any]) -> Dict[str, Any]:
    """去掉 None 值; 保留 False / 0 / 空列表。"""
    return {k: v for k, v in params.items() if v is not None}


def _jsonable(obj: Any) -> Any:
    try:
        json.dumps(obj, default=str)
        return obj
    except Exception:
        return str(obj)


def _safe_json(resp: httpx.Response) -> Any:
    try:
        return resp.json()
    except Exception:
        return {"_text": resp.text[:2000]}


def _short(text: str, n: int = 600) -> str:
    text = text or ""
    return text if len(text) <= n else text[:n] + "..."


def _meta(obj: Any) -> Any:
    if isinstance(obj, dict):
        return obj.get("meta")
    return None


def data_of(obj: Any) -> Any:
    if isinstance(obj, dict) and "data" in obj:
        return obj["data"]
    return obj


def meta_of(obj: Any) -> Dict[str, Any]:
    if isinstance(obj, dict) and isinstance(obj.get("meta"), dict):
        return obj["meta"]
    return {}


def pick(obj: Any, *names: str, default: Any = None) -> Any:
    """从字典中按顺序取第一个存在的 key。"""
    if not isinstance(obj, dict):
        return default
    for n in names:
        if n in obj and obj[n] is not None:
            return obj[n]
    # 嵌套一层
    for sub in ("summary", "totals", "overview", "result"):
        v = obj.get(sub)
        if isinstance(v, dict):
            for n in names:
                if n in v and v[n] is not None:
                    return v[n]
    return default


def iter_items(obj: Any) -> List[Dict[str, Any]]:
    """把榜单/分类/标签/对象列表结果抽成 list[dict]。"""
    obj = data_of(obj)
    if isinstance(obj, list):
        return [x for x in obj if isinstance(x, dict)]
    if isinstance(obj, dict):
        for key in ("items", "list", "rows", "rankings", "entries",
                    "categories", "tags", "merchants", "counterparties",
                    "data", "buckets", "points", "transactions"):
            v = obj.get(key)
            if isinstance(v, list):
                return [x for x in v if isinstance(x, dict)]
        # 双侧结构 {income: [...], expense: [...]}
        out: List[Dict[str, Any]] = []
        for side in ("income", "expense"):
            v = obj.get(side)
            if isinstance(v, list):
                out.extend(x for x in v if isinstance(x, dict))
        if out:
            return out
    return []


def find_item(items: Iterable[Dict[str, Any]], name: str,
              *name_keys: str) -> Optional[Dict[str, Any]]:
    keys = name_keys or ("name", "category_name", "tag_name", "merchant_name",
                         "counterparty_name", "label", "title", "display_name")
    for it in items:
        for k in keys:
            v = it.get(k)
            if v is not None and str(v) == str(name):
                return it
    return None


def daterange(start: str, end: str) -> List[str]:
    s = datetime.strptime(start, "%Y-%m-%d").date()
    e = datetime.strptime(end, "%Y-%m-%d").date()
    out = []
    while s <= e:
        out.append(s.isoformat())
        s += timedelta(days=1)
    return out


def unique_suffix() -> str:
    return uuid.uuid4().hex[:8]


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


def today() -> str:
    return date.today().isoformat()


# --------------------------------------------------------------------------
# 通用条件构造
# --------------------------------------------------------------------------
DEFAULT_TZ = "Asia/Shanghai"


def base_params(book_id: Any, start: str, end: str, **kw) -> Dict[str, Any]:
    p: Dict[str, Any] = {
        "book_id": book_id,
        "start_date": start,
        "end_date": end,
        "timezone": DEFAULT_TZ,
    }
    p.update(kw)
    return p


def balance_params(book_id: Any, start: str, end: str,
                   income_mode: str = "ALL", income_ids: Any = None,
                   expense_mode: str = "ALL", expense_ids: Any = None,
                   **kw) -> Dict[str, Any]:
    """结余组合筛选参数。type 固定为 balance, 允许 kw 覆盖其它条件。"""
    kw.pop("type", None)
    p = base_params(book_id, start, end,
                    type="balance",
                    income_category_mode=income_mode,
                    expense_category_mode=expense_mode,
                    **kw)
    if income_ids:
        p["income_category_ids"] = income_ids
    if expense_ids:
        p["expense_category_ids"] = expense_ids
    return p
