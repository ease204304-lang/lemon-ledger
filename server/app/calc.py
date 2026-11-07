"""聚合计算核心 (W2)。

所有金额一律使用 decimal.Decimal, 禁止 float。
口径要点:
    * 结余 = 收入 − 支出; 结余率 = 结余 ÷ 收入 × 100% (C124)
      - 收入为 0 -> 结余率 null (客户端显示「—」)
      - 结余率可负, 最高 100%
    * 日均分母 = 区间自然日天数 (D06 建议口径, 待最终确认)
    * 占比 = 榜单金额 ÷ 当前统计层级相应金额 (C46)
    * 分类固定两级: 一级直记 -> 「未细分」; 无分类 -> 「未分类」 (C54)
    * 标签: 仅主标签进入金额/占比/笔数/环形图/榜单; 无主标签 -> 「未设置标签」 (C64/C2)
    * 交易对象: 未填写 -> 「未设置商户」, 纳入金额及笔数 (C11)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional, Sequence, Tuple

from .db import fetch_all, fetch_one
from .filters import (
    CategorySelection,
    FilterContext,
    build_buckets,
    previous_period,
)
from .money import (
    ZERO,
    money_str,
    percent_str,
    quantize_money,
    safe_ratio,
)

UNSET_CATEGORY = "未分类"
UNSUBDIVIDED = "未细分"
UNSET_TAG = "未设置标签"
UNSET_MERCHANT = "未设置商户"

TOP_N_DEFAULT = 5


# ---------------------------------------------------------------------
# SQL 谓词生成
# ---------------------------------------------------------------------
def _in_clause(values: Sequence[str]) -> Tuple[str, List[str]]:
    if not values:
        return "(NULL)", []
    placeholders = ",".join("?" * len(values))
    return f"({placeholders})", list(values)


def _side_category_predicate(
    selection: CategorySelection,
    alias: str = "t",
) -> Tuple[str, List[str]]:
    """某一侧的分类谓词。

    SELECTED 模式: 命中成员集合 (父 + 子, 已去重) -> 父子同选只计一次 (C116)。
    ALL 模式: 不加分类限制。
    """
    if not selection.is_selected or not selection.member_ids:
        return "1=1", []
    clause, params = _in_clause(selection.member_ids)
    return f"{alias}.category_id IN {clause}", params


def _category_filter_predicate(ctx: FilterContext) -> Tuple[str, List[str]]:
    """收入/支出单侧视图的分类筛选 (非结余)。"""
    if ctx.stat_type == "income":
        return _side_category_predicate(ctx.income_category)
    if ctx.stat_type == "expense":
        return _side_category_predicate(ctx.expense_category)
    return "1=1", []


def _type_predicate(ctx: FilterContext, stat_type: str) -> Tuple[str, List[str]]:
    """交易类型谓词。

    * income/expense 单侧 -> 只取该类型
    * balance -> 不限类型 (收入与支出分开聚合)
    """
    if stat_type == "balance":
        return "1=1", []
    return "t.type = ?", [stat_type]


def _date_predicate(start: date, end: date) -> Tuple[str, List[str]]:
    """业务日期谓词, 首尾均包含 (C98)。"""
    return "t.transaction_date >= ? AND t.transaction_date <= ?", [
        start.isoformat(),
        end.isoformat(),
    ]


def _tag_filter_predicate(ctx: FilterContext) -> Tuple[str, List[str]]:
    """标签作为搜索筛选 (C60/C62/C63)。

    用 EXISTS 子查询, 保证一笔交易只计一次; 角色匹配 all/main/aux。
    """
    if not ctx.tag_ids:
        return "1=1", []
    clause, params = _in_clause(ctx.tag_ids)
    if ctx.tag_role == "main":
        role_clause = "AND tt.role = 'main'"
    elif ctx.tag_role == "aux":
        role_clause = "AND tt.role = 'aux'"
    else:
        role_clause = ""
    sql = (
        "EXISTS (SELECT 1 FROM transaction_tag tt "
        f"WHERE tt.transaction_id = t.id AND tt.tag_id IN {clause} {role_clause})"
    )
    return sql, params


def _counterparty_filter_predicate(ctx: FilterContext) -> Tuple[str, List[str]]:
    """交易对象筛选 (C9)。支持显式「未设置商户」桶。"""
    if not ctx.counterparty_ids:
        return "1=1", []
    has_unset = UNSET_MERCHANT in ctx.counterparty_ids
    real = [c for c in ctx.counterparty_ids if c != UNSET_MERCHANT]
    parts: List[str] = []
    params: List[str] = []
    if real:
        clause, p = _in_clause(real)
        parts.append(f"t.counterparty_id IN {clause}")
        params.extend(p)
    if has_unset:
        parts.append("t.counterparty_id IS NULL")
    return "(" + " OR ".join(parts) + ")", params


def build_where(
    ctx: FilterContext,
    start: date,
    end: date,
    stat_type: str,
    selection: Optional[CategorySelection] = None,
    *,
    use_category_filter: bool = True,
    use_tag_filter: bool = True,
    use_counterparty_filter: bool = True,
) -> Tuple[str, List[str]]:
    """组装统一 WHERE 谓词。

    结余两侧分别传入 selection, 使用独立的收入/支出条件聚合 (TECH 03)。
    """
    clauses: List[str] = ["t.book_id = ?"]
    params: List[str] = [ctx.book_id]

    type_clause, type_params = _type_predicate(ctx, stat_type)
    clauses.append(type_clause)
    params.extend(type_params)

    date_clause, date_params = _date_predicate(start, end)
    clauses.append(date_clause)
    params.extend(date_params)

    if use_category_filter:
        if selection is not None:
            # 显式传入 selection (结余两侧独立聚合) 优先, 与 stat_type 无关
            cat_clause, cat_params = _side_category_predicate(selection)
            clauses.append(cat_clause)
            params.extend(cat_params)
        elif stat_type == "balance":
            # 结余未传 selection -> 该侧不限分类
            pass
        else:
            cat_clause, cat_params = _category_filter_predicate(ctx)
            clauses.append(cat_clause)
            params.extend(cat_params)

    if use_tag_filter:
        tag_clause, tag_params = _tag_filter_predicate(ctx)
        clauses.append(tag_clause)
        params.extend(tag_params)

    if use_counterparty_filter:
        cp_clause, cp_params = _counterparty_filter_predicate(ctx)
        clauses.append(cp_clause)
        params.extend(cp_params)

    return " AND ".join(clauses), params


# ---------------------------------------------------------------------
# 聚合结果容器
# ---------------------------------------------------------------------
@dataclass
class Totals:
    amount: Decimal = ZERO
    count: int = 0
    last_date: Optional[str] = None

    def add(self, amount: Decimal, count: int, last_date: Optional[str]) -> None:
        self.amount += amount
        self.count += count
        if last_date and (self.last_date is None or last_date > self.last_date):
            self.last_date = last_date


@dataclass
class BucketPoint:
    bucket_start: date
    bucket_end: date
    income: Decimal = ZERO
    expense: Decimal = ZERO
    income_count: int = 0
    expense_count: int = 0
    comparison_income: Decimal = ZERO
    comparison_expense: Decimal = ZERO

    @property
    def balance(self) -> Decimal:
        return self.income - self.expense

    @property
    def comparison_balance(self) -> Decimal:
        return self.comparison_income - self.comparison_expense


# ---------------------------------------------------------------------
# 基础聚合
# ---------------------------------------------------------------------
def query_totals(
    ctx: FilterContext,
    start: date,
    end: date,
    stat_type: str,
    selection: Optional[CategorySelection] = None,
) -> Totals:
    """单侧金额与笔数合计。"""
    where, params = build_where(ctx, start, end, stat_type, selection)
    sql = (
        "SELECT COALESCE(SUM(CAST(t.amount AS REAL)), 0) AS s, COUNT(*) AS c, "
        "MAX(t.transaction_date) AS d "
        'FROM "transaction" t WHERE ' + where
    )
    # 注意: SUM 在 SQLite 中对 TEXT 金额不可靠, 因此改用逐行 Decimal 累加。
    rows = fetch_all(
        'SELECT t.amount AS amount, t.transaction_date AS d FROM "transaction" t WHERE ' + where,
        params,
    )
    totals = Totals()
    for r in rows:
        totals.add(Decimal(r["amount"]), 1, r["d"])
    return totals


def query_rows(
    ctx: FilterContext,
    start: date,
    end: date,
    stat_type: str,
    selection: Optional[CategorySelection] = None,
) -> List[Dict[str, Any]]:
    """取符合谓词的全部交易行 (含维度快照), 供分类/标签/对象聚合。"""
    where, params = build_where(ctx, start, end, stat_type, selection)
    sql = (
        "SELECT t.id, t.type, t.amount, t.transaction_date, t.transaction_time, "
        "t.category_id, t.category_name_snapshot, t.counterparty_id, "
        "t.counterparty_name_snapshot, t.note, t.amount_anomaly "
        'FROM "transaction" t WHERE ' + where + " ORDER BY t.transaction_date, t.transaction_time"
    )
    return [dict(r) for r in fetch_all(sql, params)]


def _main_tag_map(tx_ids: Sequence[str]) -> Dict[str, Optional[Dict[str, str]]]:
    """取每笔交易的主标签 (只走 role='main') (C64)。

    每笔最多一个主标签; 若历史数据存在多个主标签, 取最早创建的一条 (迁移脚本会
    把重复主标签登记为异常)。

    大账本: 按 900 一组分块 IN 查询, 避免超过 SQLite 变量上限 (默认 32766)。
    """
    if not tx_ids:
        return {}
    result: Dict[str, Optional[Dict[str, str]]] = {}
    ids = list(tx_ids)
    chunk = 900
    for i in range(0, len(ids), chunk):
        part = ids[i : i + chunk]
        marks = ",".join("?" * len(part))
        rows = fetch_all(
            "SELECT tt.transaction_id, tt.tag_id, g.name AS tag_name "
            "FROM transaction_tag tt LEFT JOIN tag g ON g.id = tt.tag_id "
            f"WHERE tt.role = 'main' AND tt.transaction_id IN ({marks}) "
            "ORDER BY tt.created_at, tt.tag_id",
            part,
        )
        for r in rows:
            if r["transaction_id"] not in result:
                result[r["transaction_id"]] = {
                    "id": r["tag_id"],
                    "name": r["tag_name"] or r["tag_id"],
                }
    for tid in ids:
        result.setdefault(tid, None)
    return result


# ---------------------------------------------------------------------
# 分类聚合 (C53/C54/C36–C40)
# ---------------------------------------------------------------------
@dataclass
class CategoryNode:
    id: Optional[str]
    name: str
    parent_id: Optional[str]
    amount: Decimal = ZERO
    count: int = 0
    last_date: Optional[str] = None
    children: List["CategoryNode"] = field(default_factory=list)
    is_placeholder: bool = False

    @property
    def has_children(self) -> bool:
        return bool(self.children)


def _category_display(row: Dict[str, Any]) -> Tuple[Optional[str], str, Optional[str]]:
    """返回 (一级分类 id, 二级分类 id, 展示名)。

    * 无分类 -> (None, None, 「未分类」)
    * 一级直记 -> (一级 id, None, 「一级名/未细分」)
    * 二级 -> (一级 id, 二级 id, 「一级名/二级名」)
    """
    cat_id = row.get("category_id")
    snapshot = row.get("category_name_snapshot")
    if not cat_id:
        return None, None, UNSET_CATEGORY

    node = _CATEGORY_INDEX.get(cat_id)
    if node is None:
        # 历史分类已删除, 保留快照名 (C139)
        return None, None, snapshot or cat_id

    parent_id = node["parent_id"]
    if parent_id is None:
        # 一级直记: 仅当该一级有子分类时归「未细分」; 叶子分类直记就是它本身 (C54)
        has_children = any(c.get("parent_id") == cat_id for c in _CATEGORY_INDEX.values())
        if has_children:
            return cat_id, None, f"{node['name']}/{UNSUBDIVIDED}"
        return cat_id, None, node["name"]
    parent = _CATEGORY_INDEX.get(parent_id)
    parent_name = parent["name"] if parent else (snapshot or "")
    return parent_id, cat_id, f"{parent_name}/{node['name']}"


_CATEGORY_INDEX: Dict[str, Dict[str, Any]] = {}


def load_category_index_cache() -> None:
    """刷新分类索引 (含已删除), 供展示名解析。"""
    global _CATEGORY_INDEX
    rows = fetch_all("SELECT id, parent_id, type, name, status FROM category")
    _CATEGORY_INDEX = {
        r["id"]: {
            "id": r["id"],
            "parent_id": r["parent_id"],
            "type": r["type"],
            "name": r["name"],
            "status": r["status"],
        }
        for r in rows
    }


def aggregate_categories(
    ctx: FilterContext,
    rows: List[Dict[str, Any]],
    level: int = 2,
) -> Dict[str, Any]:
    """分类聚合 + 排名数据 + 穿透键。

    level=1 -> 一级榜 (含「未细分」作为一级分类的二级桶, 一级直记并入该一级)
    level=2 -> 二级榜
    """
    buckets: Dict[Tuple[Optional[str], Optional[str]], CategoryNode] = {}
    for row in rows:
        p_id, c_id, display = _category_display(row)
        if level == 1:
            if c_id is None and p_id is not None:
                # 一级直记 → 该一级下的「未细分」桶 (C54), 与子分类聚合分开
                key = (p_id, "__unsubdivided__")
                name = display  # "父X/未细分"
            else:
                # 子分类聚合到一级
                key = (p_id, None)
                name = display.split("/")[0] if "/" in display else display
        else:
            key = (p_id, c_id)
            name = display
        node = buckets.get(key)
        if node is None:
            node = CategoryNode(id=key[1] if level == 2 else key[0], name=name, parent_id=key[0])
            buckets[key] = node
        node.amount += Decimal(row["amount"])
        node.count += 1
        d = row["transaction_date"]
        if node.last_date is None or d > node.last_date:
            node.last_date = d

    items = list(buckets.values())
    # 隐藏零金额项 (C89); 但分类榜的占比分母为该层全部金额
    total = sum((n.amount for n in items), ZERO)
    visible = [n for n in items if n.count > 0 and n.amount != ZERO]

    ordered = sort_items(visible, ctx.sort, ctx.sort_order)
    top = ordered[:TOP_N_DEFAULT]
    rest = ordered[TOP_N_DEFAULT:]

    def to_payload(n: CategoryNode) -> Dict[str, Any]:
        ratio = safe_ratio(n.amount, total)
        return {
            "category_id": n.id,
            "parent_id": n.parent_id,
            "name": n.name,
            "amount": money_str(n.amount),
            "amount_display": None,  # 由展示层处理千分位
            "ratio": percent_str(ratio),
            "count": n.count,
            "last_transaction_date": n.last_date,
            "progress": percent_str(ratio),
            "drilldown": drilldown_key(ctx, level, n),
        }

    result: Dict[str, Any] = {
        "level": level,
        "total_amount": money_str(total),
        "total_count": sum(n.count for n in items),
        "items": [to_payload(n) for n in top],
        "has_more": len(rest) > 0,
        "remaining_count": len(rest),
    }
    if rest:
        result["remaining_amount"] = money_str(sum((n.amount for n in rest), ZERO))
    return result


def drilldown_key(ctx: FilterContext, level: int, node: CategoryNode) -> Dict[str, Any]:
    """穿透键: 账本 + 时间 + 收支类型 + 维度 ID (或「未设置」桶标识)。

    明细接口据此还原入口上下文 (C120/C132)。
    """
    key: Dict[str, Any] = {
        "book_id": ctx.book_id,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
        "timezone": ctx.tz_name,
    }
    if ctx.stat_type == "balance":
        key["type"] = "balance"
    else:
        key["type"] = ctx.stat_type

    if level == 1:
        if node.id is None:
            key["category_ids"] = [UNSET_CATEGORY]
        else:
            key["category_ids"] = [node.id]
    else:
        if node.id is None:
            key["category_ids"] = [UNSET_CATEGORY]
        else:
            key["category_ids"] = [node.id]

    if ctx.tag_ids:
        key["tag_ids"] = list(ctx.tag_ids)
        key["tag_role"] = ctx.tag_role
    if ctx.counterparty_ids:
        key["counterparty_ids"] = list(ctx.counterparty_ids)
    return key


def sort_items(items: List[Any], sort_key: str, order: str) -> List[Any]:
    """稳定排序: 金额 / 笔数 / 最近发生时间 (C37)。

    D06 建议口径: 使用稳定并列键 (次级键 = 名称升序), 待最终确认。
    """
    reverse = order == "desc"

    def key(item: Any) -> Tuple[Any, ...]:
        if sort_key == "count":
            primary: Any = item.count
        elif sort_key == "recent":
            primary = item.last_date or ""
        else:
            primary = item.amount
        return (primary, item.name)

    return sorted(items, key=key, reverse=reverse)


# ---------------------------------------------------------------------
# 标签聚合 (C1/C2/C6/C64)
# ---------------------------------------------------------------------
def aggregate_tags(
    ctx: FilterContext,
    rows: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """主标签聚合 + 环形图 (Top5 + 其他, 「未设置标签」独立保留) + 榜单。"""
    tx_ids = [r["id"] for r in rows]
    tag_map = _main_tag_map(tx_ids)

    buckets: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        tag = tag_map.get(row["id"])
        if tag is None:
            key = UNSET_TAG
            node = buckets.get(key)
            if node is None:
                node = {"id": UNSET_TAG, "name": UNSET_TAG, "amount": ZERO, "count": 0, "last_date": None}
        else:
            key = tag["id"]
            node = buckets.get(key)
            if node is None:
                node = {"id": tag["id"], "name": tag["name"], "amount": ZERO, "count": 0, "last_date": None}
        node["amount"] += Decimal(row["amount"])
        node["count"] += 1
        d = row["transaction_date"]
        if node["last_date"] is None or d > node["last_date"]:
            node["last_date"] = d
        buckets[key] = node

    total = sum((n["amount"] for n in buckets.values()), ZERO)

    # 零金额项隐藏 (C89)
    visible = [n for n in buckets.values() if n["count"] > 0 and n["amount"] != ZERO]

    # 环形图: Top5 + 其他, 「未设置标签」独立保留 (C6)
    # 「未设置标签」与其它标签分开: 始终单列, 不参与 Top5 截断。
    unset_nodes = [n for n in visible if n["id"] == UNSET_TAG]
    tag_nodes = [n for n in visible if n["id"] != UNSET_TAG]
    chart_list = sorted(tag_nodes, key=lambda n: (-n["amount"], n["name"]))
    chart: List[Dict[str, Any]] = []
    rest_nodes = chart_list[TOP_N_DEFAULT:]
    for n in chart_list[:TOP_N_DEFAULT]:
        chart.append(
            {
                "tag_id": n["id"],
                "name": n["name"],
                "amount": money_str(n["amount"]),
                "ratio": percent_str(safe_ratio(n["amount"], total)),
                "count": n["count"],
                "is_unset": False,
                "drilldown": tag_drilldown(ctx, n["id"]),
            }
        )
    if rest_nodes:
        chart.append(
            {
                "tag_id": "OTHER",
                "name": "其他",
                "amount": money_str(sum((n["amount"] for n in rest_nodes), ZERO)),
                "ratio": percent_str(
                    safe_ratio(sum((n["amount"] for n in rest_nodes), ZERO), total)
                ),
                "count": sum(n["count"] for n in rest_nodes),
                "is_unset": False,
                "is_other": True,
                "member_tag_ids": [n["id"] for n in rest_nodes],
                "drilldown": tag_drilldown(ctx, "OTHER", [n["id"] for n in rest_nodes]),
            }
        )
    # 「未设置标签」独立保留 (C6)
    for n in unset_nodes:
        chart.append(
            {
                "tag_id": UNSET_TAG,
                "name": UNSET_TAG,
                "amount": money_str(n["amount"]),
                "ratio": percent_str(safe_ratio(n["amount"], total)),
                "count": n["count"],
                "is_unset": True,
                "drilldown": tag_drilldown(ctx, UNSET_TAG),
            }
        )

    # 榜单: Top5 随排序变化 (C43); 「未设置标签」独立保留, 不受 Top5 截断
    class _W:
        def __init__(self, n: Dict[str, Any]) -> None:
            self.amount = n["amount"]
            self.count = n["count"]
            self.last_date = n["last_date"]
            self.name = n["name"]
            self.id = n["id"]

    tag_visible = [_W(n) for n in visible if n["id"] != UNSET_TAG]
    unset_visible = [_W(n) for n in visible if n["id"] == UNSET_TAG]
    ordered = sort_items(tag_visible, ctx.sort, ctx.sort_order)
    leaderboard = []

    def _leader_item(w: _W) -> Dict[str, Any]:
        ratio = safe_ratio(w.amount, total)
        return {
            "tag_id": w.id,
            "name": w.name,
            "amount": money_str(w.amount),
            "ratio": percent_str(ratio),
            "count": w.count,
            "last_transaction_date": w.last_date,
            "progress": percent_str(ratio),
            "is_unset": w.id == UNSET_TAG,
            "drilldown": tag_drilldown(ctx, w.id),
        }

    for w in ordered[:TOP_N_DEFAULT]:
        leaderboard.append(_leader_item(w))
    # 「未设置标签」独立保留 (C6)
    for w in unset_visible:
        leaderboard.append(_leader_item(w))

    return {
        "total_amount": money_str(total),
        "total_count": sum(n["count"] for n in buckets.values()),
        "chart": chart,
        "chart_limit": TOP_N_DEFAULT,
        "leaderboard": leaderboard,
        # items 别名: 兼容统一明细/榜单的 iter_items 抽取
        "items": leaderboard,
        "has_more": len(ordered) > TOP_N_DEFAULT,
        "remaining_count": max(0, len(ordered) - TOP_N_DEFAULT),
    }


def tag_drilldown(ctx: FilterContext, tag_id: str, member_ids: Optional[List[str]] = None) -> Dict[str, Any]:
    """标签穿透键 (C4)。继承账本、时间、收支类型和分类。"""
    key: Dict[str, Any] = {
        "book_id": ctx.book_id,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
        "timezone": ctx.tz_name,
        "type": ctx.stat_type,
    }
    if tag_id == UNSET_TAG:
        key["tag_ids"] = [UNSET_TAG]
        key["tag_match"] = "unset"
    elif tag_id == "OTHER":
        key["tag_ids"] = member_ids or []
        key["tag_match"] = "any"
    else:
        key["tag_ids"] = [tag_id]
        key["tag_match"] = "any"
    if ctx.category_ids:
        key["category_ids"] = list(ctx.category_ids)
    if ctx.counterparty_ids:
        key["counterparty_ids"] = list(ctx.counterparty_ids)
    return key


# ---------------------------------------------------------------------
# 交易对象聚合 (C8–C13)
# ---------------------------------------------------------------------
def aggregate_merchants(
    ctx: FilterContext,
    rows: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """对象榜: 收入显示来源/付款方, 支出显示商户 (C12), 收支分开统计 (C13)。"""
    buckets: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        cp_id = row.get("counterparty_id")
        if cp_id:
            node = _COUNTERPARTY_INDEX.get(cp_id)
            name = node["name"] if node else (row.get("counterparty_name_snapshot") or cp_id)
            key = cp_id
        else:
            key = UNSET_MERCHANT
            name = UNSET_MERCHANT
        item = buckets.get(key)
        if item is None:
            item = {"id": key, "name": name, "amount": ZERO, "count": 0, "last_date": None}
            buckets[key] = item
        item["amount"] += Decimal(row["amount"])
        item["count"] += 1
        d = row["transaction_date"]
        if item["last_date"] is None or d > item["last_date"]:
            item["last_date"] = d

    total = sum((n["amount"] for n in buckets.values()), ZERO)
    visible = [n for n in buckets.values() if n["count"] > 0 and n["amount"] != ZERO]

    class _W:
        def __init__(self, n: Dict[str, Any]) -> None:
            self.amount = n["amount"]
            self.count = n["count"]
            self.last_date = n["last_date"]
            self.name = n["name"]
            self.id = n["id"]

    ordered = sort_items([_W(n) for n in visible], ctx.sort, ctx.sort_order)
    items = []
    for w in ordered[:TOP_N_DEFAULT]:
        ratio = safe_ratio(w.amount, total)
        items.append(
            {
                "counterparty_id": w.id,
                "name": w.name,
                "amount": money_str(w.amount),
                "ratio": percent_str(ratio),
                "count": w.count,
                "last_transaction_date": w.last_date,
                "progress": percent_str(ratio),
                "is_unset": w.id == UNSET_MERCHANT,
                "drilldown": merchant_drilldown(ctx, w.id),
            }
        )
    return {
        "total_amount": money_str(total),
        "total_count": sum(n["count"] for n in buckets.values()),
        "items": items,
        "has_more": len(ordered) > TOP_N_DEFAULT,
        "remaining_count": max(0, len(ordered) - TOP_N_DEFAULT),
    }


_COUNTERPARTY_INDEX: Dict[str, Dict[str, Any]] = {}


def load_counterparty_index_cache() -> None:
    global _COUNTERPARTY_INDEX
    rows = fetch_all("SELECT id, name, status FROM counterparty")
    _COUNTERPARTY_INDEX = {
        r["id"]: {"id": r["id"], "name": r["name"], "status": r["status"]} for r in rows
    }


def merchant_drilldown(ctx: FilterContext, cp_id: str) -> Dict[str, Any]:
    """对象穿透键: 账本 + 时间 + 收支类型 + 对象 ID (或「未设置商户」)。"""
    key: Dict[str, Any] = {
        "book_id": ctx.book_id,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
        "timezone": ctx.tz_name,
        "type": ctx.stat_type,
    }
    if cp_id == UNSET_MERCHANT:
        key["counterparty_ids"] = [UNSET_MERCHANT]
    else:
        key["counterparty_ids"] = [cp_id]
    if ctx.category_ids:
        key["category_ids"] = list(ctx.category_ids)
    if ctx.tag_ids:
        key["tag_ids"] = list(ctx.tag_ids)
    return key


# ---------------------------------------------------------------------
# 汇总 (summary)
# ---------------------------------------------------------------------
def compute_summary(
    ctx: FilterContext,
    include_comparison: bool = True,
) -> Dict[str, Any]:
    """汇总: income / expense / balance / balance_rate / 笔数 / 日均。

    结余与结余率使用同版本的收入、支出合计计算 (TECH 03)。
    """
    income_sel = ctx.income_category if ctx.stat_type == "balance" else None
    expense_sel = ctx.expense_category if ctx.stat_type == "balance" else None

    if ctx.stat_type == "income":
        inc = query_totals(ctx, ctx.start_date, ctx.end_date, "income", ctx.income_category)
        exp = Totals()
    elif ctx.stat_type == "expense":
        exp = query_totals(ctx, ctx.start_date, ctx.end_date, "expense", ctx.expense_category)
        inc = Totals()
    else:
        inc = query_totals(ctx, ctx.start_date, ctx.end_date, "income", ctx.income_category)
        exp = query_totals(ctx, ctx.start_date, ctx.end_date, "expense", ctx.expense_category)

    balance = inc.amount - exp.amount
    # C124: 结余率 = 结余 / 收入 * 100%; 收入为 0 -> null; 最高 100%
    balance_rate: Optional[Decimal]
    if inc.amount == ZERO:
        balance_rate = None
    else:
        balance_rate = balance / inc.amount * Decimal("100")
        if balance_rate > Decimal("100"):
            balance_rate = Decimal("100")

    days = Decimal(ctx.days)
    # 视图对应的日均 (PRD 02 日均与笔数): 结余→结余日均, 收入/支出→各自日均
    if ctx.stat_type == "income":
        daily_average = inc.amount / days
    elif ctx.stat_type == "expense":
        daily_average = exp.amount / days
    else:
        daily_average = balance / days
    result: Dict[str, Any] = {
        "type": ctx.stat_type,
        "income": money_str(inc.amount),
        "expense": money_str(exp.amount),
        "balance": money_str(balance),
        "balance_rate": percent_str(balance_rate),
        "income_count": inc.count,
        "expense_count": exp.count,
        "count": inc.count + exp.count,
        # D06 建议口径: 日均分母 = 区间自然日天数 (待最终确认)
        "days": ctx.days,
        "daily_average": money_str(daily_average),
        "average_daily_income": money_str(inc.amount / days),
        "average_daily_expense": money_str(exp.amount / days),
        "average_daily_balance": money_str(balance / days),
        "granularity": ctx.effective_granularity,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
    }

    if include_comparison and ctx.comparison_enabled:
        result["comparison"] = compute_comparison_summary(ctx, inc, exp)
    return result


def compute_comparison_summary(
    ctx: FilterContext,
    cur_income: Totals,
    cur_expense: Totals,
) -> Dict[str, Any]:
    """同期对比 (C32/C33/C127)。

    变化率: 同期金额为 0 -> null (显示「—」)。
    结余变化率: 同期结余 > 0 才计算, 分母为同期结余 (C127)。
    """
    prev_start, prev_end = previous_period(ctx)
    if ctx.stat_type == "income":
        prev_inc = query_totals(ctx, prev_start, prev_end, "income", ctx.income_category)
        prev_exp = Totals()
    elif ctx.stat_type == "expense":
        prev_exp = query_totals(ctx, prev_start, prev_end, "expense", ctx.expense_category)
        prev_inc = Totals()
    else:
        prev_inc = query_totals(ctx, prev_start, prev_end, "income", ctx.income_category)
        prev_exp = query_totals(ctx, prev_start, prev_end, "expense", ctx.expense_category)

    prev_balance = prev_inc.amount - prev_exp.amount
    cur_balance = cur_income.amount - cur_expense.amount

    def block(cur: Decimal, prev: Decimal, count: int, *, require_positive_denominator: bool = False) -> Dict[str, Any]:
        diff = cur - prev
        if require_positive_denominator:
            # C127: 结余变化率只在同期结余 > 0 时计算
            ratio = safe_ratio(diff, prev) if prev > ZERO else None
        else:
            # C32: 同期金额为 0 -> null (显示「—」)
            ratio = safe_ratio(diff, prev) if prev != ZERO else None
        return {
            "amount": money_str(cur),
            "comparison_amount": money_str(prev),
            "difference": money_str(diff),
            "change_rate": percent_str(ratio),
            "count": count,
        }

    if ctx.stat_type == "income":
        body = block(cur_income.amount, prev_inc.amount, cur_income.count)
    elif ctx.stat_type == "expense":
        body = block(cur_expense.amount, prev_exp.amount, cur_expense.count)
    else:
        body = block(cur_balance, prev_balance, cur_income.count + cur_expense.count,
                     require_positive_denominator=True)
        body["income"] = {
            "amount": money_str(cur_income.amount),
            "comparison_amount": money_str(prev_inc.amount),
            "difference": money_str(cur_income.amount - prev_inc.amount),
            "change_rate": percent_str(
                safe_ratio(cur_income.amount - prev_inc.amount, prev_inc.amount)
            ),
        }
        body["expense"] = {
            "amount": money_str(cur_expense.amount),
            "comparison_amount": money_str(prev_exp.amount),
            "difference": money_str(cur_expense.amount - prev_exp.amount),
            "change_rate": percent_str(
                safe_ratio(cur_expense.amount - prev_exp.amount, prev_exp.amount)
            ),
        }

    body["comparison_start_date"] = prev_start.isoformat()
    body["comparison_end_date"] = prev_end.isoformat()
    body["previous_start"] = prev_start.isoformat()
    body["previous_end"] = prev_end.isoformat()
    body["comparison_days"] = (prev_end - prev_start).days + 1
    body["is_partial"] = prev_end >= ctx.end_date
    return body


# ---------------------------------------------------------------------
# 趋势 (trend)
# ---------------------------------------------------------------------
def compute_trend(ctx: FilterContext, include_comparison: bool = True) -> Dict[str, Any]:
    """趋势: 按桶聚合, 桶边界裁剪到有效日期, 缺桶补零 (C31/C126)。

    结余趋势每周期独立计算收入减支出 (C118)。
    """
    buckets = build_buckets(ctx)
    rows = query_rows_for_trend(ctx)

    prev_start, prev_end = previous_period(ctx)
    prev_rows = query_rows_for_trend(ctx, prev_start, prev_end) if (
        include_comparison and ctx.comparison_enabled
    ) else []

    def bucket_of(d: str) -> int:
        dd = datetime.strptime(d, "%Y-%m-%d").date()
        for i, (bs, be) in enumerate(buckets):
            if bs <= dd <= be:
                return i
        return -1

    points: List[BucketPoint] = [
        BucketPoint(bucket_start=bs, bucket_end=be) for bs, be in buckets
    ]

    for row in rows:
        i = bucket_of(row["transaction_date"])
        if i < 0:
            continue
        p = points[i]
        if row["type"] == "income":
            p.income += Decimal(row["amount"])
            p.income_count += 1
        else:
            p.expense += Decimal(row["amount"])
            p.expense_count += 1

    if prev_rows:
        prev_buckets = build_buckets(
            _replace_dates(ctx, prev_start, prev_end)
        )
        for row in prev_rows:
            dd = datetime.strptime(row["transaction_date"], "%Y-%m-%d").date()
            idx = -1
            for i, (bs, be) in enumerate(prev_buckets):
                if bs <= dd <= be:
                    idx = i
                    break
            if idx < 0 or idx >= len(points):
                continue
            if row["type"] == "income":
                points[idx].comparison_income += Decimal(row["amount"])
            else:
                points[idx].comparison_expense += Decimal(row["amount"])

    out: List[Dict[str, Any]] = []
    for p in points:
        item: Dict[str, Any] = {
            "bucket_start": p.bucket_start.isoformat(),
            "bucket_end": p.bucket_end.isoformat(),
            "income": money_str(p.income),
            "expense": money_str(p.expense),
            "balance": money_str(p.balance),
            "income_count": p.income_count,
            "expense_count": p.expense_count,
        }
        if include_comparison and ctx.comparison_enabled:
            item["comparison"] = {
                "income": money_str(p.comparison_income),
                "expense": money_str(p.comparison_expense),
                "balance": money_str(p.comparison_balance),
                "income_difference": money_str(p.income - p.comparison_income),
                "expense_difference": money_str(p.expense - p.comparison_expense),
                "balance_difference": money_str(p.balance - p.comparison_balance),
                "income_change_rate": percent_str(
                    safe_ratio(p.income - p.comparison_income, p.comparison_income)
                ),
                "expense_change_rate": percent_str(
                    safe_ratio(p.expense - p.comparison_expense, p.comparison_expense)
                ),
                # C127: 同期结余 > 0 才计算变化率
                "balance_change_rate": percent_str(
                    safe_ratio(p.balance - p.comparison_balance, p.comparison_balance)
                    if p.comparison_balance > ZERO
                    else None
                ),
            }
        item["drilldown"] = {
            "book_id": ctx.book_id,
            "start_date": p.bucket_start.isoformat(),
            "end_date": p.bucket_end.isoformat(),
            "timezone": ctx.tz_name,
            "type": ctx.stat_type,
        }
        if ctx.category_ids:
            item["drilldown"]["category_ids"] = list(ctx.category_ids)
        if ctx.tag_ids:
            item["drilldown"]["tag_ids"] = list(ctx.tag_ids)
            item["drilldown"]["tag_role"] = ctx.tag_role
        if ctx.counterparty_ids:
            item["drilldown"]["counterparty_ids"] = list(ctx.counterparty_ids)
        out.append(item)

    return {
        "granularity": ctx.effective_granularity,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
        "bucket_count": len(out),
        "points": out,
    }


def _replace_dates(ctx: FilterContext, start: date, end: date) -> FilterContext:
    """复制一份上下文并替换日期 (用于同期分桶)。"""
    import copy

    new = copy.copy(ctx)
    new.start_date = start
    new.end_date = end
    return new


def query_rows_for_trend(
    ctx: FilterContext,
    start: Optional[date] = None,
    end: Optional[date] = None,
) -> List[Dict[str, Any]]:
    """趋势用行集: 取两侧或单侧交易。"""
    start = start or ctx.start_date
    end = end or ctx.end_date
    if ctx.stat_type == "income":
        return query_rows(ctx, start, end, "income", ctx.income_category)
    if ctx.stat_type == "expense":
        return query_rows(ctx, start, end, "expense", ctx.expense_category)
    income_rows = query_rows(ctx, start, end, "income", ctx.income_category)
    expense_rows = query_rows(ctx, start, end, "expense", ctx.expense_category)
    return income_rows + expense_rows


# ---------------------------------------------------------------------
# 明细 (transactions)
# ---------------------------------------------------------------------
def query_transactions(
    ctx: FilterContext,
) -> Dict[str, Any]:
    """统一明细: 按日期倒序分组, 日内按记账时间倒序 (C71/C72)。"""
    where, params = build_where(ctx, ctx.start_date, ctx.end_date, ctx.stat_type)
    sql = (
        "SELECT t.id, t.type, t.amount, t.currency, t.transaction_date, t.transaction_time, "
        "t.category_id, t.category_name_snapshot, t.counterparty_id, "
        "t.counterparty_name_snapshot, t.note, t.created_at, t.updated_at, t.amount_anomaly "
        'FROM "transaction" t WHERE ' + where
    )
    if ctx.stat_type == "balance":
        # 结余明细: 两侧都返回
        sql_income, p_income = build_where(ctx, ctx.start_date, ctx.end_date, "income", ctx.income_category)
        sql_expense, p_expense = build_where(ctx, ctx.start_date, ctx.end_date, "expense", ctx.expense_category)
        rows = list(
            fetch_all(
                'SELECT t.id, t.type, t.amount, t.currency, t.transaction_date, t.transaction_time, '
                "t.category_id, t.category_name_snapshot, t.counterparty_id, "
                "t.counterparty_name_snapshot, t.note, t.created_at, t.updated_at, t.amount_anomaly "
                'FROM "transaction" t WHERE ' + sql_income,
                p_income,
            )
        ) + list(
            fetch_all(
                'SELECT t.id, t.type, t.amount, t.currency, t.transaction_date, t.transaction_time, '
                "t.category_id, t.category_name_snapshot, t.counterparty_id, "
                "t.counterparty_name_snapshot, t.note, t.created_at, t.updated_at, t.amount_anomaly "
                'FROM "transaction" t WHERE ' + sql_expense,
                p_expense,
            )
        )
    else:
        rows = list(fetch_all(sql, params))

    # 日期倒序, 日内记账时间倒序
    rows.sort(key=lambda r: (r["transaction_date"], r["transaction_time"], r["id"]), reverse=True)
    # sqlite3.Row -> dict (_transaction_payload / _category_display 需要 .get)
    rows = [dict(r) for r in rows]

    total = len(rows)
    start_idx = (ctx.page - 1) * ctx.page_size
    page_rows = rows[start_idx : start_idx + ctx.page_size]

    items = [_transaction_payload(r) for r in page_rows]

    # 分组 (按日期倒序)
    groups: List[Dict[str, Any]] = []
    for it in items:
        if not groups or groups[-1]["date"] != it["transaction_date"]:
            groups.append(
                {
                    "date": it["transaction_date"],
                    "items": [],
                    "count": 0,
                    "amount": ZERO,
                }
            )
        g = groups[-1]
        g["items"].append(it)
        g["count"] += 1
        g["amount"] += Decimal(it["amount"])

    total_amount = sum((Decimal(r["amount"]) for r in rows), ZERO)

    return {
        "total": total,
        "page": ctx.page,
        "page_size": ctx.page_size,
        "total_pages": (total + ctx.page_size - 1) // ctx.page_size if ctx.page_size else 0,
        "total_amount": money_str(total_amount),
        "groups": [
            {
                "date": g["date"],
                "count": g["count"],
                "amount": money_str(g["amount"]),
                "items": g["items"],
            }
            for g in groups
        ],
        "items": items,
    }


def _transaction_payload(row: Dict[str, Any]) -> Dict[str, Any]:
    cat_id = row.get("category_id")
    p_id, c_id, display = _category_display(row)
    cp_id = row.get("counterparty_id")
    if cp_id:
        node = _COUNTERPARTY_INDEX.get(cp_id)
        cp_name = node["name"] if node else (row.get("counterparty_name_snapshot") or cp_id)
    else:
        cp_name = UNSET_MERCHANT
    return {
        "id": row["id"],
        "type": row["type"],
        "amount": money_str(Decimal(row["amount"])),
        "currency": row.get("currency", "CNY"),
        "transaction_date": row["transaction_date"],
        "transaction_time": row["transaction_time"],
        "category_id": cat_id,
        "category_name": display,
        "category_path": display,
        "counterparty_id": cp_id,
        "counterparty_name": cp_name,
        "note": row.get("note"),
        "created_at": row.get("created_at"),
        "updated_at": row.get("updated_at"),
        "amount_anomaly": bool(row.get("amount_anomaly")),
    }


def query_transaction_detail(tx_id: str, book_id: str) -> Optional[Dict[str, Any]]:
    """单笔详情: 含辅助标签与完整信息 (PRD 06)。"""
    row = fetch_one(
        'SELECT * FROM "transaction" WHERE id = ? AND book_id = ?', (tx_id, book_id)
    )
    if row is None:
        return None
    data = dict(row)
    payload = _transaction_payload(data)

    cat_id = data.get("category_id")
    if cat_id:
        node = _CATEGORY_INDEX.get(cat_id)
        if node:
            payload["category"] = {
                "id": cat_id,
                "name": node["name"],
                "parent_id": node["parent_id"],
                "type": node["type"],
                "status": node["status"],
            }
    cp_id = data.get("counterparty_id")
    if cp_id:
        node = _COUNTERPARTY_INDEX.get(cp_id)
        if node:
            payload["counterparty"] = {
                "id": cp_id,
                "name": node["name"],
                "status": node["status"],
            }
    else:
        payload["counterparty"] = {"id": None, "name": UNSET_MERCHANT, "status": None}

    tags = fetch_all(
        "SELECT tt.tag_id, tt.role, g.name, g.status, g.scope "
        "FROM transaction_tag tt LEFT JOIN tag g ON g.id = tt.tag_id "
        "WHERE tt.transaction_id = ? ORDER BY tt.role, tt.created_at",
        (tx_id,),
    )
    main_tags = [t for t in tags if t["role"] == "main"]
    aux_tags = [t for t in tags if t["role"] == "aux"]
    payload["tags"] = [
        {"id": t["tag_id"], "name": t["name"], "role": t["role"], "status": t["status"], "scope": t["scope"]}
        for t in tags
    ]
    payload["main_tag"] = (
        {"id": main_tags[0]["tag_id"], "name": main_tags[0]["name"]} if main_tags else None
    )
    payload["aux_tags"] = [
        {"id": t["tag_id"], "name": t["name"]} for t in aux_tags
    ]
    return payload
