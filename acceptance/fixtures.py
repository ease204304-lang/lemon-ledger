# -*- coding: utf-8 -*-
"""
验收测试数据夹具 (fixtures)

为 T01–T34 提供可复用的账本 / 分类 / 标签 / 对象 / 交易数据。
所有写入都通过 HTTP API 完成, 不触碰 server/ 实现代码。

约定:
  - 每个用例创建独立账本 (book_*), 避免相互干扰。
  - 账本名带 uuid 后缀, 保证幂等重跑不冲突。
  - 若服务端未提供某个写入端点, 抛出 SeedError, 由用例转为 BLOCKED。
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional

from harness import (ApiClient, CaseContext, DEFAULT_TZ, unique_suffix,
                     now_iso, today, data_of)


class SeedError(Exception):
    """造数失败 (端点不存在 / 参数不被接受)。"""


@dataclass
class Book:
    id: str
    name: str

    def __str__(self) -> str:
        return f"{self.name}({self.id})"


@dataclass
class Fixture:
    """一个账本及其附属维度数据。"""
    client: ApiClient
    book: Optional[Book] = None
    ctx: Optional[CaseContext] = None
    expense_cats: Dict[str, Any] = field(default_factory=dict)   # name -> category dict
    income_cats: Dict[str, Any] = field(default_factory=dict)
    tags: Dict[str, Any] = field(default_factory=dict)
    counterparties: Dict[str, Any] = field(default_factory=dict)
    tx_ids: List[str] = field(default_factory=list)

    # -- 造数 ---------------------------------------------------------------
    def new_book(self, prefix: str = "acc") -> Book:
        name = f"{prefix}-{unique_suffix()}"
        try:
            data = self.client.create_book(name)
        except Exception as e:
            raise SeedError(f"创建账本失败: {e}") from e
        bid = _first_id(data, "book_id", "id")
        if not bid:
            raise SeedError(f"创建账本响应缺少 id: {data!r}")
        self.book = Book(id=str(bid), name=name)
        return self.book

    def expense_category(self, name: str, parent: Optional[Any] = None) -> Dict[str, Any]:
        return self._category(name, "expense", parent, self.expense_cats)

    def income_category(self, name: str, parent: Optional[Any] = None) -> Dict[str, Any]:
        return self._category(name, "income", parent, self.income_cats)

    def _category(self, name: str, ctype: str, parent: Optional[Any],
                  store: Dict[str, Any]) -> Dict[str, Any]:
        parent_id = None
        if parent is not None:
            parent_id = _first_id(parent, "category_id", "id")
        try:
            data = self.client.create_category(
                name, ctype, parent_id=parent_id, book_id=self.book.id)
        except Exception as e:
            raise SeedError(f"创建分类 {name} 失败: {e}") from e
        cid = _first_id(data, "category_id", "id")
        if not cid:
            raise SeedError(f"创建分类 {name} 响应缺少 id: {data!r}")
        rec = {"id": str(cid), "name": name, "type": ctype, "parent_id": parent_id}
        store[name] = rec
        return rec

    def tag(self, name: str, **extra) -> Dict[str, Any]:
        try:
            data = self.client.create_tag(name, **extra)
        except Exception as e:
            raise SeedError(f"创建标签 {name} 失败: {e}") from e
        tid = _first_id(data, "tag_id", "id")
        if not tid:
            raise SeedError(f"创建标签 {name} 响应缺少 id: {data!r}")
        rec = {"id": str(tid), "name": name}
        rec.update({k: v for k, v in data.items() if k not in ("id", "tag_id")})
        self.tags[name] = rec
        return rec

    def counterparty(self, name: str, **extra) -> Dict[str, Any]:
        try:
            data = self.client.create_counterparty(name, **extra)
        except Exception as e:
            raise SeedError(f"创建对象 {name} 失败: {e}") from e
        cid = _first_id(data, "counterparty_id", "id")
        if not cid:
            raise SeedError(f"创建对象 {name} 响应缺少 id: {data!r}")
        rec = {"id": str(cid), "name": name}
        self.counterparties[name] = rec
        return rec

    def txn(self, amount: Any, *, type: str = "expense", day: str = "",
            category_id: Any = None, tag_ids: Any = None,
            primary_tag_id: Any = None, counterparty_id: Any = None,
            time: str = "12:00:00", note: str = "acc-test",
            book_id: Any = None, **extra) -> Dict[str, Any]:
        """写入一笔交易。tag_ids 为辅助标签列表, primary_tag_id 为主标签。"""
        body: Dict[str, Any] = {
            "book_id": book_id or self.book.id,
            "type": type,
            "amount": str(amount),
            "transaction_date": day or today(),
            "transaction_time": time,
            "note": note,
        }
        if category_id is not None:
            body["category_id"] = category_id
        if counterparty_id is not None:
            body["counterparty_id"] = counterparty_id
        if tag_ids:
            body["tag_ids"] = list(tag_ids)
        if primary_tag_id is not None:
            body["primary_tag_id"] = primary_tag_id
        body.update(extra)
        try:
            data = self.client.create_transaction(**body)
        except Exception as e:
            raise SeedError(f"写入交易 {body.get('amount')} 失败: {e}") from e
        tid = _first_id(data, "transaction_id", "id")
        rec = dict(data) if isinstance(data, dict) else {}
        rec.setdefault("id", str(tid) if tid else "")
        rec["_request"] = body
        self.tx_ids.append(rec["id"])
        return rec


def _first_id(obj: Any, *keys: str) -> Any:
    """从响应中抽 id。兼容 {id}, {data:{id}}, {book_id} 等多种形态。"""
    if not isinstance(obj, dict):
        return None
    for k in keys:
        if obj.get(k):
            return obj[k]
    # data 包裹
    d = obj.get("data")
    if isinstance(d, dict):
        for k in keys:
            if d.get(k):
                return d[k]
        for sub in ("book", "category", "tag", "counterparty", "transaction"):
            v = d.get(sub)
            if isinstance(v, dict):
                for k in keys:
                    if v.get(k):
                        return v[k]
    # 嵌套一层
    for sub in ("book", "category", "tag", "counterparty", "transaction"):
        v = obj.get(sub)
        if isinstance(v, dict):
            for k in keys:
                if v.get(k):
                    return v[k]
    return None


# --------------------------------------------------------------------------
# 常用日期锚点 (全部相对「今天」计算, 保证脚本任何时候可跑)
# --------------------------------------------------------------------------
def anchors(today_str: Optional[str] = None) -> Dict[str, str]:
    """返回一个月的日期锚点集合。"""
    base = datetime.strptime(today_str or today(), "%Y-%m-%d").date()
    y, m, d = base.year, base.month, base.day
    # 本月 1 号, 上月同期
    first_this = date(y, m, 1)
    if m == 1:
        first_prev = date(y - 1, 12, 1)
    else:
        first_prev = date(y, m - 1, 1)
    # 上月月末
    if m == 1:
        last_prev = date(y - 1, 12, 31)
    else:
        last_prev = date(y, m, 1) - timedelta(days=1)
    return {
        "today": base.isoformat(),
        "this_month_start": first_this.isoformat(),
        "this_month_end": base.isoformat(),
        "prev_month_start": first_prev.isoformat(),
        "prev_month_end": last_prev.isoformat(),
        "month_end": last_prev.isoformat(),
        "d06_same_day": base.isoformat(),
        "d05_same_day": (
            date(y - 1, m, min(d, 28)) if m <= 2 or d <= 28 else base
        ).isoformat(),
    }
