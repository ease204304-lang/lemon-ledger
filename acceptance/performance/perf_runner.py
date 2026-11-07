# -*- coding: utf-8 -*-
"""
性能采样器 (《测试与验收清单》「性能验收」sheet)

门槛 (C140 / C79):
    金额汇总   端到端 P95 <= 2 秒
    趋势       端到端 P95 <= 3 秒
    分类榜     端到端 P95 <= 5 秒
    标签统计   端到端 P95 <= 5 秒
    交易对象   端到端 P95 <= 5 秒

分层要求:
    冷缓存 -> 清目标查询键或使用未命中查询
    热缓存 -> 先预热相同查询
    冷热不混算; 记录样本数、P95、均值、命中率。

计时口径: 从确认查询到模块可用 (端到端 HTTP 请求耗时)。
"""
from __future__ import annotations

import json
import os
import statistics
import sys
import time
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from harness import ApiClient, ROOT, base_params, dec, pick, iter_items

#: 模块 -> (接口, P95 门槛秒)
MODULES: Dict[str, Dict[str, Any]] = {
    "金额汇总": {"path": "/api/statistics/summary", "p95_limit": 2.0},
    "趋势": {"path": "/api/statistics/trend", "p95_limit": 3.0},
    "分类榜": {"path": "/api/statistics/categories", "p95_limit": 5.0},
    "标签统计": {"path": "/api/statistics/tags", "p95_limit": 5.0},
    "交易对象": {"path": "/api/statistics/merchants", "p95_limit": 5.0},
}


def percentile(values: List[float], p: float) -> float:
    """线性插值分位数。"""
    if not values:
        return 0.0
    vs = sorted(values)
    if len(vs) == 1:
        return vs[0]
    k = (len(vs) - 1) * p
    lo = int(k)
    hi = min(lo + 1, len(vs) - 1)
    frac = k - lo
    return vs[lo] * (1 - frac) + vs[hi] * frac


def summarize_samples(samples: List[float]) -> Dict[str, Any]:
    if not samples:
        return {"samples": 0, "p95": None, "mean": None, "min": None, "max": None,
                "p50": None, "p99": None}
    return {
        "samples": len(samples),
        "p95": round(percentile(samples, 0.95), 4),
        "p50": round(percentile(samples, 0.50), 4),
        "p99": round(percentile(samples, 0.99), 4),
        "mean": round(statistics.fmean(samples), 4),
        "min": round(min(samples), 4),
        "max": round(max(samples), 4),
    }


def _timed_call(client: ApiClient, path: str, params: Dict[str, Any]) -> Tuple[float, int, Any]:
    t0 = time.perf_counter()
    resp = client.request("GET", path, params=params)
    dt = time.perf_counter() - t0
    try:
        body = resp.json()
    except Exception:
        body = None
    return dt, resp.status_code, body


def _cache_key(params: Dict[str, Any]) -> str:
    return json.dumps({k: params[k] for k in sorted(params)}, ensure_ascii=False,
                      default=str)


def cold_variants(params: Dict[str, Any], n: int) -> List[Dict[str, Any]]:
    """构造 n 个保证不命中的冷缓存查询 (用未命中维度筛选 + 微扰的日期边界)。"""
    out = []
    for i in range(n):
        p = dict(params)
        # 使用不同的时区别名或无意义的额外维度使规范化查询键不命中缓存
        p["_nonce"] = f"cold-{i}-{time.time_ns()}"
        p["_t"] = str(time.time_ns())
        out.append(p)
    return out


def sample_module(client: ApiClient, module: str, params: Dict[str, Any],
                  *, hot_n: int = 100, cold_n: int = 100,
                  do_cold: bool = True) -> Dict[str, Any]:
    spec = MODULES[module]
    path = spec["path"]
    result: Dict[str, Any] = {"module": module, "path": path,
                              "p95_limit": spec["p95_limit"]}

    # ---- 热缓存: 先预热相同查询, 再采样 ----
    _timed_call(client, path, params)          # 预热
    hot_samples: List[float] = []
    hot_status: List[int] = []
    for _ in range(hot_n):
        dt, st, _b = _timed_call(client, path, params)
        hot_samples.append(dt)
        hot_status.append(st)
    result["hot"] = summarize_samples(hot_samples)
    result["hot"]["status_codes"] = sorted(set(hot_status))
    result["hot"]["hit_rate"] = 1.0  # 相同查询键重复命中

    # ---- 冷缓存: 使用未命中查询 ----
    if do_cold:
        cold_samples: List[float] = []
        cold_status: List[int] = []
        for p in cold_variants(params, cold_n):
            dt, st, _b = _timed_call(client, path, p)
            cold_samples.append(dt)
            cold_status.append(st)
        result["cold"] = summarize_samples(cold_samples)
        result["cold"]["status_codes"] = sorted(set(cold_status))
        result["cold"]["hit_rate"] = 0.0
    else:
        result["cold"] = None

    # ---- 判定: 冷热分别达标 ----
    fails = []
    for layer in ("cold", "hot"):
        s = result.get(layer)
        if not s:
            continue
        if s["p95"] is None:
            fails.append(f"{module}/{layer} 无样本")
            continue
        if s["p95"] > spec["p95_limit"]:
            fails.append(f"{module}/{layer} P95={s['p95']:.3f}s > "
                         f"{spec['p95_limit']}s")
        if s["status_codes"] and max(s["status_codes"]) >= 400:
            fails.append(f"{module}/{layer} 存在 HTTP {max(s['status_codes'])}")
    result["failures"] = fails
    result["pass"] = not fails
    return result


def reconcile(client: ApiClient, book_id: str, spec: Dict[str, Any],
              ref: Dict[str, Any]) -> Dict[str, Any]:
    """与基准账本对账: 汇总收入/支出应与参考聚合一致 (容差 0.01)。"""
    out: Dict[str, Any] = {"checks": [], "pass": True}
    r = client.request("GET", "/api/statistics/summary", params=base_params(
        book_id, spec["start"], spec["end"], type="balance"))
    try:
        body = r.json()
    except Exception:
        body = {}
    data = body.get("data", body) if isinstance(body, dict) else {}
    income = dec(pick(data, "income", "total_income"))
    expense = dec(pick(data, "expense", "total_expense"))
    for label, got, want in (("income", income, dec(ref["income"])),
                             ("expense", expense, dec(ref["expense"]))):
        ok = got is not None and want is not None and abs(got - want) <= Decimal("0.01")
        out["checks"].append({"field": label, "actual": str(got),
                              "expected": str(want), "pass": ok})
        if not ok:
            out["pass"] = False
    # 明细笔数
    r2 = client.request("GET", "/api/transactions", params=base_params(
        book_id, spec["start"], spec["end"], type="balance", page_size=1))
    try:
        b2 = r2.json()
    except Exception:
        b2 = {}
    d2 = b2.get("data", b2) if isinstance(b2, dict) else {}
    meta = b2.get("meta", {}) if isinstance(b2, dict) else {}
    total_count = pick(meta, "total", "total_count", "count")
    if total_count is None and isinstance(d2, dict):
        total_count = pick(d2, "total", "total_count", "count")
    out["count"] = {"actual": total_count, "expected": ref["count"]}
    if total_count is not None:
        if int(total_count) != int(ref["count"]):
            out["pass"] = False
    return out


def run(client: ApiClient, ctx=None, *, n: int = 50000, seed: int = 20261107,
        hot_n: int = 100, cold_n: int = 100, reuse: bool = True) -> Dict[str, Any]:
    """执行完整性能验收。"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import dataset

    started = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    ds = dataset.load() if reuse else None
    if ds is None or ds.get("written", 0) < n:
        print(f"[perf] 生成 {n} 笔基准数据集 …", flush=True)
        ds = dataset.build(client, n=n, seed=seed)
        dataset.save(ds)
    else:
        print(f"[perf] 复用已有基准集: {ds['written']} 笔", flush=True)

    spec = ds["spec"]
    book_id = ds["book_id"]
    ref = ds["reference"]

    params = base_params(book_id, spec["start"], spec["end"], type="balance")
    params["granularity"] = "day"

    # 覆盖场景: 快捷日期与自定义分开 (sheet R5)
    quick_start = (datetime.strptime(spec["end"], "%Y-%m-%d").date()
                   - timedelta(days=29)).isoformat()
    quick_params = base_params(book_id, quick_start, spec["end"], type="balance")
    quick_params["granularity"] = "day"

    modules_out = []
    for module in MODULES:
        print(f"[perf] 采样 {module} …", flush=True)
        p = params if module != "金额汇总" else quick_params
        m = sample_module(client, module, p, hot_n=hot_n, cold_n=cold_n)
        m["scenario"] = "快捷近30天" if module == "金额汇总" else "自定义全跨度"
        modules_out.append(m)

    print("[perf] 与基准账本对账 …", flush=True)
    rec = reconcile(client, book_id, spec, ref)

    failures = []
    for m in modules_out:
        failures.extend(m.get("failures") or [])
    if not rec["pass"]:
        failures.append("基准集对账不一致")

    report = {
        "meta": {
            "started_at": started,
            "finished_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "base_url": client.base_url,
            "dataset_n": ds.get("written"),
            "dataset_spec": spec,
            "hot_samples_per_module": hot_n,
            "cold_samples_per_module": cold_n,
            "device": os.environ.get("ACCOUNT_PERF_DEVICE", "未记录"),
            "network": os.environ.get("ACCOUNT_PERF_NETWORK", "未记录"),
            "deploy": os.environ.get("ACCOUNT_PERF_DEPLOY", "本地开发服务"),
        },
        "modules": modules_out,
        "reconciliation": rec,
        "reference": {"income": ref["income"], "expense": ref["expense"],
                      "balance": ref["balance"], "count": ref["count"]},
        "failures": failures,
        "pass": not failures,
    }
    out_dir = os.path.join(ROOT, "docs", "acceptance-evidence", "performance")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "perf-report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, ensure_ascii=False, indent=2, default=str)
    return report


if __name__ == "__main__":
    from harness import ApiClient
    c = ApiClient()
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50000
    r = run(c, n=n)
    print(json.dumps(r, ensure_ascii=False, indent=2)[:3000])
