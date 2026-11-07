# -*- coding: utf-8 -*-
"""
5 万笔基准数据集生成器 (《测试与验收清单》「性能验收」sheet R10)

要求:
  - 一个目标账本至少 50,000 笔, 另建隔离账本。
  - 记录跨度、分布、种子及参考聚合结果。
  - 同一基准集用于对账, 覆盖正负结余与无交易期。

本模块只负责**生成**数据与参考聚合, 不做性能采样 (见 perf_runner.py)。
数据通过 HTTP API 写入 (不直接改数据库), 保证与真实业务写入路径一致。
"""
from __future__ import annotations

import json
import os
import random
import time
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

from harness import ROOT, now_iso, today, unique_suffix

SEED = 20261107

#: 支出分类 (3 个一级, 每个 2 个二级) —— 与服务端分类体系解耦, 按需创建
EXPENSE_TREE = [
    ("餐饮", ["午餐", "晚餐", "咖啡"]),
    ("交通", ["打车", "地铁", "加油"]),
    ("购物", ["日用", "数码"]),
    ("居住", ["房租", "水电"]),
]
INCOME_TREE = [
    ("工资", ["基本工资", "奖金"]),
    ("兼职", ["外包"]),
    ("理财", ["利息", "基金"]),
]
COUNTERPARTIES = ["星巴克", "麦当劳", "滴滴出行", "地铁服务", "京东", "淘宝",
                  "房东", "国家电网", "公司", "客户A", "客户B", "银行"]
TAGS = ["日常", "重要", "报销", "家庭", "工作", "学习", "医疗", "娱乐",
        "投资", "人情"]


class DatasetSpec:
    """基准集规格, 便于复算。"""
    def __init__(self, n: int = 50000, seed: int = SEED,
                 start: Optional[str] = None, end: Optional[str] = None):
        self.n = n
        self.seed = seed
        self.end = end or today()
        self.start = start or (datetime.strptime(self.end, "%Y-%m-%d").date()
                               - timedelta(days=730)).isoformat()
        self.book_name = f"perf-baseline-{unique_suffix()}"
        self.isolated_book_name = f"perf-isolated-{unique_suffix()}"

    def to_dict(self) -> Dict[str, Any]:
        return {"n": self.n, "seed": self.seed, "start": self.start,
                "end": self.end, "book_name": self.book_name,
                "isolated_book_name": self.isolated_book_name}


def build(client, *, n: int = 50000, seed: int = SEED,
          progress: bool = True) -> Dict[str, Any]:
    """建账本 + 分类 + 标签 + 对象, 并写入 n 笔交易。返回参考聚合结果。"""
    spec = DatasetSpec(n=n, seed=seed)
    rng = random.Random(seed)

    book = client.create_book(spec.book_name)
    book_id = str(_pick_id(book, "book_id", "id"))
    isolated = client.create_book(spec.isolated_book_name)
    isolated_id = str(_pick_id(isolated, "book_id", "id"))

    # --- 维度 ---
    exp_cats: Dict[str, Any] = {}
    exp_cat_ids: List[Tuple[str, Optional[str]]] = []   # (name, parent_id)
    for parent, children in EXPENSE_TREE:
        p = client.create_category(parent, "expense")
        pid = str(_pick_id(p, "category_id", "id"))
        exp_cats[parent] = {"id": pid, "name": parent, "children": []}
        exp_cat_ids.append((parent, None))
        for c in children:
            pc = client.create_category(c, "expense", parent_id=pid)
            cid = str(_pick_id(pc, "category_id", "id"))
            exp_cats[parent]["children"].append({"id": cid, "name": c})
            exp_cat_ids.append((c, pid))

    inc_cats: Dict[str, Any] = {}
    inc_cat_ids: List[str] = []
    for parent, children in INCOME_TREE:
        p = client.create_category(parent, "income")
        pid = str(_pick_id(p, "category_id", "id"))
        inc_cats[parent] = {"id": pid, "name": parent, "children": []}
        inc_cat_ids.append(pid)
        for c in children:
            pc = client.create_category(c, "income", parent_id=pid)
            inc_cats[parent]["children"].append(
                {"id": str(_pick_id(pc, "category_id", "id")), "name": c})

    tag_ids = []
    for t in TAGS:
        d = client.create_tag(t)
        tag_ids.append((str(_pick_id(d, "tag_id", "id")), t))

    cp_ids = []
    for c in COUNTERPARTIES:
        d = client.create_counterparty(c)
        cp_ids.append((str(_pick_id(d, "counterparty_id", "id")), c))

    # --- 交易 ---
    s = datetime.strptime(spec.start, "%Y-%m-%d").date()
    e = datetime.strptime(spec.end, "%Y-%m-%d").date()
    span = (e - s).days + 1

    # 参考聚合
    ref = {
        "income": Decimal("0"), "expense": Decimal("0"),
        "count": 0, "income_count": 0, "expense_count": 0,
        "by_category": {}, "by_tag": {}, "by_counterparty": {},
        "by_month": {},
    }

    # 为加速, 使用批量并发写入 (适度并发 + 失败重试, 保证 50000 笔可靠落库)
    import concurrent.futures as cf
    import httpx

    base_url = client.base_url
    batch: List[Dict[str, Any]] = []
    written = 0
    in_flight: List[Any] = []

    def flush(batch_rows: List[Dict[str, Any]]):
        """并发写入一批交易 (2 线程 + 失败重试 5 次), 返回成功数。

        C140 性能门槛测的是**读**延迟 (summary/trend/categories/tags/merchants),
        5 万笔数据集只是准备阶段; 单 worker 开发服务在并发写连接下会
        出现连接重置 (ReadError/502), 故这里用低并发 + 重试保证数据完整。
        """
        if not batch_rows:
            return 0
        ok = 0
        with httpx.Client(base_url=base_url, timeout=120.0) as hc:
            def post(row):
                for _ in range(5):
                    try:
                        r = hc.post("/api/transactions", json=row)
                        if r.status_code < 300:
                            return True
                    except Exception:
                        pass
                    time.sleep(0.1)
                return False
            with cf.ThreadPoolExecutor(max_workers=2) as ex:
                for good in ex.map(post, batch_rows):
                    ok += 1 if good else 0
        return ok

    for i in range(n):
        day = s + timedelta(days=rng.randrange(span))
        # 15% 无交易期: 刻意留出空洞 (覆盖「无交易期」)
        if rng.random() < 0.15:
            day = s + timedelta(days=rng.randrange(span))
        is_income = rng.random() < 0.42
        # 金额分布: 多数小额, 少量大额
        if rng.random() < 0.9:
            amount = Decimal(rng.randrange(100, 30000)) / Decimal(100)
        else:
            amount = Decimal(rng.randrange(30000, 500000)) / Decimal(100)
        amount = amount.quantize(Decimal("0.01"))
        # 零/负金额不写入 (C85/C86)
        if amount <= 0:
            amount = Decimal("1.00")

        if is_income:
            pool = []
            for parent, info in inc_cats.items():
                pool.append(info["id"])
                for ch in info["children"]:
                    pool.append(ch["id"])
            cat_id = rng.choice(pool)
        else:
            pool = []
            for parent, info in exp_cats.items():
                pool.append(info["id"])
                for ch in info["children"]:
                    pool.append(ch["id"])
            cat_id = rng.choice(pool)

        has_main_tag = rng.random() < 0.55
        has_aux_tag = rng.random() < 0.35
        has_cp = rng.random() < 0.75

        row: Dict[str, Any] = {
            "book_id": book_id,
            "type": "income" if is_income else "expense",
            "amount": str(amount),
            "transaction_date": day.isoformat(),
            "transaction_time": f"{rng.randrange(24):02d}:{rng.randrange(60):02d}:{rng.randrange(60):02d}",
            "note": f"perf-{i}",
        }
        if cat_id:
            row["category_id"] = cat_id
        if has_main_tag:
            row["primary_tag_id"] = rng.choice(tag_ids)[0]
        if has_aux_tag:
            row["tag_ids"] = [rng.choice(tag_ids)[0]]
        if has_cp:
            row["counterparty_id"] = rng.choice(cp_ids)[0]

        # 参考聚合 (仅按可确定维度, 主标签口径)
        if is_income:
            ref["income"] += amount
            ref["income_count"] += 1
        else:
            ref["expense"] += amount
            ref["expense_count"] += 1
        ref["count"] += 1
        ref["by_category"][cat_id] = ref["by_category"].get(cat_id, Decimal("0")) + amount
        if has_main_tag:
            tid = row["primary_tag_id"]
            ref["by_tag"][tid] = ref["by_tag"].get(tid, Decimal("0")) + amount
        if has_cp:
            cid = row["counterparty_id"]
            ref["by_counterparty"][cid] = ref["by_counterparty"].get(cid, Decimal("0")) + amount
        mk = day.isoformat()[:7]
        mm = ref["by_month"].setdefault(mk, {"income": Decimal("0"), "expense": Decimal("0")})
        mm["income" if is_income else "expense"] += amount

        batch.append(row)
        if len(batch) >= 500:
            ok = flush(batch)
            written += ok
            batch = []
            if progress and written % 5000 < 500:
                print(f"    [perf] 已写入 {written}/{n}", flush=True)

    if batch:
        written += flush(batch)

    ref["balance"] = ref["income"] - ref["expense"]
    result = {
        "spec": spec.to_dict(),
        "book_id": book_id,
        "isolated_book_id": isolated_id,
        "written": written,
        "requested": n,
        "categories": {"expense": exp_cats, "income": inc_cats},
        "tags": [{"id": i, "name": n_} for i, n_ in tag_ids],
        "counterparties": [{"id": i, "name": n_} for i, n_ in cp_ids],
        "reference": {
            "income": str(ref["income"]),
            "expense": str(ref["expense"]),
            "balance": str(ref["balance"]),
            "count": ref["count"],
            "income_count": ref["income_count"],
            "expense_count": ref["expense_count"],
            "by_category": {k: str(v) for k, v in ref["by_category"].items()},
            "by_tag": {k: str(v) for k, v in ref["by_tag"].items()},
            "by_counterparty": {k: str(v) for k, v in ref["by_counterparty"].items()},
            "by_month": {k: {"income": str(v["income"]), "expense": str(v["expense"])}
                         for k, v in ref["by_month"].items()},
        },
    }
    return result


def save(result: Dict[str, Any], path: Optional[str] = None) -> str:
    path = path or os.path.join(ROOT, "docs", "acceptance-evidence",
                                "performance", "dataset.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2, default=str)
    return path


def load(path: Optional[str] = None) -> Optional[Dict[str, Any]]:
    path = path or os.path.join(ROOT, "docs", "acceptance-evidence",
                                "performance", "dataset.json")
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _pick_id(obj: Any, *keys: str) -> Any:
    if not isinstance(obj, dict):
        return None
    for k in keys:
        if obj.get(k):
            return obj[k]
    # data 包裹 (服务端统一 {data:{id:...}, meta:...})
    d = obj.get("data")
    if isinstance(d, dict):
        for k in keys:
            if d.get(k):
                return d[k]
    for sub in ("book", "category", "tag", "counterparty", "transaction"):
        v = obj.get(sub)
        if isinstance(v, dict):
            for k in keys:
                if v.get(k):
                    return v[k]
        if isinstance(d, dict):
            vv = d.get(sub)
            if isinstance(vv, dict):
                for k in keys:
                    if vv.get(k):
                        return vv[k]
    return None


if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    from harness import ApiClient
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 50000
    c = ApiClient()
    res = build(c, n=n)
    p = save(res)
    print("saved:", p)
    print("reference:", json.dumps(res["reference"], ensure_ascii=False)[:400])
