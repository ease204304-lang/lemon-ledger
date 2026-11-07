"""统一条件解析器 (TECH 03「统一聚合与明细穿透」)。

后端用一套条件解析器生成账本、业务日期、交易类型、分类、标签及对象谓词:
    * 自然日首尾均包含
    * 标签作为搜索筛选时用 EXISTS / 交易 ID 去重 (C62/C63)
    * 主标签聚合只使用主标签关系 (C64)
    * 结余两侧各自独立条件 (income_category_mode / expense_category_mode)

规范化条件标识 (query_key): 把所有生效条件排序后拼成稳定字符串, 作为
缓存键与客户端「条件标识」使用, 保证同一条件在多模块间共享同一版本。
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .errors import InvalidFilter

VALID_TYPES = ("expense", "income", "balance")
VALID_GRANULARITY = ("auto", "day", "week", "month")
VALID_CATEGORY_MODES = ("ALL", "SELECTED")
VALID_TAG_ROLES = ("all", "main", "aux")
VALID_SORTS = ("amount", "count", "recent")

# 维度筛选 -> 允许的账目类型 (C113: 结余仅支持分类筛选)
DIMENSION_TYPE_RULES: Dict[str, Set[str]] = {
    "category": {"expense", "income", "balance"},
    "tag": {"expense", "income"},
    "counterparty": {"expense", "income"},
}

DATE_FMT = "%Y-%m-%d"


# ---------------------------------------------------------------------
# 解析辅助
# ---------------------------------------------------------------------
def parse_date(value: Optional[str], field_name: str) -> Optional[date]:
    if value is None or value == "":
        return None
    try:
        return datetime.strptime(value, DATE_FMT).date()
    except ValueError:
        raise InvalidFilter(
            f"日期格式非法: {value}，应为 YYYY-MM-DD。",
            field=field_name,
            reason="bad_date_format",
        )


def parse_timezone(value: Optional[str]) -> Tuple[ZoneInfo, str]:
    """时区使用 IANA 名称 (TECH 03)。"""
    name = value or "Asia/Shanghai"
    try:
        return ZoneInfo(name), name
    except (ZoneInfoNotFoundError, ValueError):
        raise InvalidFilter(
            f"时区非法: {name}，应为 IANA 时区名称。",
            field="timezone",
            reason="bad_timezone",
        )


def parse_id_list(
    values: Optional[Sequence[str]],
    field_name: str,
) -> List[str]:
    """解析数组型查询参数 (逗号分隔或重复传参)。"""
    if values is None:
        return []
    result: List[str] = []
    for chunk in values:
        if chunk is None:
            continue
        for part in str(chunk).split(","):
            part = part.strip()
            if part and part not in result:
                result.append(part)
    return result


def _today_in(tz: ZoneInfo) -> date:
    """当前自然日在指定时区的取值 (C97: 按手机时区确定日期范围)。"""
    return datetime.now(tz).date()


# ---------------------------------------------------------------------
# 条件对象
# ---------------------------------------------------------------------
@dataclass
class CategorySelection:
    """某一侧 (收入/支出) 的分类选择。

    mode = ALL      -> 该侧全部分类
    mode = SELECTED -> 必须有有效 ID, 解析父子树后生成去重成员集合 (C116)
    """

    mode: str = "ALL"
    requested_ids: List[str] = field(default_factory=list)
    member_ids: List[str] = field(default_factory=list)
    invalid_ids: List[str] = field(default_factory=list)
    # 父分类直接记账 (一级分类, 无二级) 在父分类被选中时也要计入 (C54)
    parent_ids: List[str] = field(default_factory=list)

    @property
    def is_selected(self) -> bool:
        return self.mode == "SELECTED"


@dataclass
class FilterContext:
    """解析后的统一条件上下文。"""

    book_id: str
    stat_type: str
    start_date: date
    end_date: date
    tz_name: str
    tz: ZoneInfo
    granularity: str
    comparison_enabled: bool
    snapshot_version: int

    # 维度筛选
    category_ids: List[str] = field(default_factory=list)
    category_ids_invalid: List[str] = field(default_factory=list)
    tag_ids: List[str] = field(default_factory=list)
    tag_ids_invalid: List[str] = field(default_factory=list)
    tag_role: str = "all"
    counterparty_ids: List[str] = field(default_factory=list)
    counterparty_ids_invalid: List[str] = field(default_factory=list)

    # 结余两侧分类选择
    income_category: CategorySelection = field(default_factory=CategorySelection)
    expense_category: CategorySelection = field(default_factory=CategorySelection)

    # 明细分页
    page: int = 1
    page_size: int = 20
    cursor: Optional[str] = None

    # 内部: 缓存/请求标识
    query_key: str = ""
    query_id: str = ""
    sort: str = "amount"
    sort_order: str = "desc"

    @property
    def days(self) -> int:
        """区间自然日天数 (含首尾)。D06 建议口径: 日均按区间自然日。"""
        return (self.end_date - self.start_date).days + 1

    @property
    def effective_granularity(self) -> str:
        """粒度: 1–31 天按天, 32–365 天按周(周一起), >365 天按月 (C29)。"""
        if self.granularity and self.granularity != "auto":
            return self.granularity
        d = self.days
        if d <= 31:
            return "day"
        if d <= 365:
            return "week"
        return "month"

    @property
    def is_balance(self) -> bool:
        return self.stat_type == "balance"


# ---------------------------------------------------------------------
# 分类树解析 (C54 / C116)
# ---------------------------------------------------------------------
def resolve_category_selection(
    mode: str,
    ids: Sequence[str],
    side_type: str,
    category_index: Dict[str, Dict[str, Any]],
) -> CategorySelection:
    """解析一侧的分类选择。

    * ALL: 该侧全部
    * SELECTED: 必须有有效 ID (否则 400), 解析父子树 -> 去重成员集合
    * 停用 (inactive) 分类保留历史交易 (C128); 已删除 (deleted) 分类的 ID
      视为无效 -> 按 D02 建议口径处理 (标注待确认)
    """
    mode = (mode or "ALL").upper()
    if mode not in VALID_CATEGORY_MODES:
        raise InvalidFilter(
            f"分类模式非法: {mode}，应为 ALL 或 SELECTED。",
            field="category_mode",
            reason="bad_category_mode",
        )
    if mode == "ALL":
        return CategorySelection(mode="ALL")

    unique_ids: List[str] = []
    for cid in ids:
        if cid and cid not in unique_ids:
            unique_ids.append(cid)
    if not unique_ids:
        raise InvalidFilter(
            "SELECTED 模式必须提供分类 ID。",
            field="category_ids",
            reason="selected_without_ids",
        )

    member_ids: List[str] = []
    parent_ids: List[str] = []
    invalid: List[str] = []
    for cid in unique_ids:
        node = category_index.get(cid)
        if node is None:
            invalid.append(cid)
            continue
        if node["type"] != side_type:
            raise InvalidFilter(
                f"分类 {cid} 的类型({node['type']})与请求侧({side_type})不符。",
                field="category_ids",
                reason="category_type_mismatch",
            )
        if node["status"] == "deleted":
            # D02 建议口径: 指定项全失效时恢复该侧全部并提示 (待最终确认)
            invalid.append(cid)
            continue
        if cid not in member_ids:
            member_ids.append(cid)
        # 父分类 -> 覆盖其子分类 (C116)
        for child_id, child in category_index.items():
            if child.get("parent_id") == cid and child["type"] == side_type:
                if child["status"] != "deleted" and child_id not in member_ids:
                    member_ids.append(child_id)
        # 一级分类直记记录: 一级分类本身无二级时, 交易直接挂一级 -> 计入
        if node.get("parent_id") is None and cid not in parent_ids:
            parent_ids.append(cid)

    if not member_ids:
        # 全部失效 -> D02 建议口径: 恢复该侧全部并提示
        return CategorySelection(
            mode="ALL",
            requested_ids=unique_ids,
            invalid_ids=invalid,
        )

    return CategorySelection(
        mode="SELECTED",
        requested_ids=unique_ids,
        member_ids=member_ids,
        invalid_ids=invalid,
        parent_ids=parent_ids,
    )


def load_category_index(conn) -> Dict[str, Dict[str, Any]]:
    """加载全部分类 (含已删除, 用于快照与失效判定)。"""
    from .db import fetch_all

    rows = fetch_all("SELECT id, parent_id, type, name, status FROM category")
    return {
        r["id"]: {
            "id": r["id"],
            "parent_id": r["parent_id"],
            "type": r["type"],
            "name": r["name"],
            "status": r["status"],
        }
        for r in rows
    }


# ---------------------------------------------------------------------
# 解析主入口
# ---------------------------------------------------------------------
def parse_filters(
    *,
    book_id: str,
    stat_type: str,
    start_date: Optional[str],
    end_date: Optional[str],
    timezone_name: Optional[str],
    granularity: Optional[str],
    comparison_enabled: bool,
    snapshot_version: Optional[int],
    category_ids: Optional[Sequence[str]] = None,
    tag_ids: Optional[Sequence[str]] = None,
    tag_role: Optional[str] = None,
    counterparty_ids: Optional[Sequence[str]] = None,
    income_category_mode: Optional[str] = None,
    income_category_ids: Optional[Sequence[str]] = None,
    expense_category_mode: Optional[str] = None,
    expense_category_ids: Optional[Sequence[str]] = None,
    page: int = 1,
    page_size: int = 20,
    cursor: Optional[str] = None,
    sort: str = "amount",
    sort_order: str = "desc",
    now: Optional[date] = None,
) -> FilterContext:
    """把原始请求参数解析为统一条件上下文。

    校验 (TECH 03 表 3):
        * 日期逆序 -> 400
        * 未来日期 -> 400
        * 维度类型不符 -> 400
        * SELECTED 未传 ID -> 400
    """
    if not book_id:
        raise InvalidFilter("缺少账本参数 book_id。", field="book_id", reason="missing_book_id")

    stat_type = (stat_type or "expense").lower()
    if stat_type not in VALID_TYPES:
        raise InvalidFilter(
            f"统计类型非法: {stat_type}，应为 expense / income / balance。",
            field="type",
            reason="bad_type",
        )

    tz, tz_name = parse_timezone(timezone_name)
    today = now or _today_in(tz)

    sd = parse_date(start_date, "start_date")
    ed = parse_date(end_date, "end_date")
    if sd is None:
        sd = today - timedelta(days=6)
    if ed is None:
        ed = today
    if sd > ed:
        raise InvalidFilter(
            "开始日期不得晚于结束日期。",
            field="start_date",
            reason="date_reversed",
            extra={"start_date": sd.isoformat(), "end_date": ed.isoformat()},
        )
    if ed > today:
        raise InvalidFilter(
            "结束日期不得晚于今天。",
            field="end_date",
            reason="future_date",
            extra={"end_date": ed.isoformat(), "today": today.isoformat()},
        )

    gran = (granularity or "auto").lower()
    if gran not in VALID_GRANULARITY:
        raise InvalidFilter(
            f"粒度非法: {gran}，应为 day / week / month / auto。",
            field="granularity",
            reason="bad_granularity",
        )

    role = (tag_role or "all").lower()
    if role not in VALID_TAG_ROLES:
        raise InvalidFilter(
            f"标签角色非法: {role}，应为 all / main / aux。",
            field="tag_role",
            reason="bad_tag_role",
        )

    if sort not in VALID_SORTS:
        raise InvalidFilter(
            f"排序键非法: {sort}，应为 amount / count / recent。",
            field="sort",
            reason="bad_sort",
        )
    if sort_order not in ("asc", "desc"):
        raise InvalidFilter(
            f"排序方向非法: {sort_order}，应为 asc / desc。",
            field="sort_order",
            reason="bad_sort_order",
        )

    cat_ids = parse_id_list(category_ids, "category_ids")
    tag_list = parse_id_list(tag_ids, "tag_ids")
    cp_ids = parse_id_list(counterparty_ids, "counterparty_ids")

    # 维度类型不符校验 (C113: 结余仅支持分类筛选)
    if stat_type == "balance":
        for name, ids in (("tag", tag_list), ("counterparty", cp_ids)):
            if ids:
                raise InvalidFilter(
                    f"结余视图不支持 {name} 维度筛选。",
                    field=f"{name}_ids",
                    reason="dimension_not_supported",
                )

    ctx = FilterContext(
        book_id=book_id,
        stat_type=stat_type,
        start_date=sd,
        end_date=ed,
        tz_name=tz_name,
        tz=tz,
        granularity=gran,
        comparison_enabled=bool(comparison_enabled),
        snapshot_version=snapshot_version or 0,
        category_ids=cat_ids,
        tag_ids=tag_list,
        tag_role=role,
        counterparty_ids=cp_ids,
        page=max(1, int(page or 1)),
        page_size=min(200, max(1, int(page_size or 20))),
        cursor=cursor,
        sort=sort,
        sort_order=sort_order,
    )

    # 维度有效性检查
    index = load_category_index(None)
    ctx.category_ids_invalid = [
        cid for cid in cat_ids
        if cid not in index or index[cid]["status"] == "deleted"
    ]
    ctx.tag_ids_invalid = _invalid_tag_ids(tag_list)
    ctx.counterparty_ids_invalid = _invalid_counterparty_ids(cp_ids)

    if stat_type == "balance":
        ctx.income_category = resolve_category_selection(
            income_category_mode or "ALL",
            parse_id_list(income_category_ids, "income_category_ids"),
            "income",
            index,
        )
        ctx.expense_category = resolve_category_selection(
            expense_category_mode or "ALL",
            parse_id_list(expense_category_ids, "expense_category_ids"),
            "expense",
            index,
        )
    else:
        side = stat_type
        sel = resolve_category_selection(
            "SELECTED" if cat_ids else "ALL",
            cat_ids,
            side,
            index,
        )
        if stat_type == "income":
            ctx.income_category = sel
        else:
            ctx.expense_category = sel

    ctx.query_key = build_query_key(ctx)
    ctx.query_id = hashlib.sha256(ctx.query_key.encode("utf-8")).hexdigest()[:16]
    return ctx


def _invalid_tag_ids(tag_list: Sequence[str]) -> List[str]:
    from .db import fetch_all

    if not tag_list:
        return []
    rows = fetch_all(
        f"SELECT id FROM tag WHERE id IN ({','.join('?' * len(tag_list))})", tag_list
    )
    found = {r["id"] for r in rows}
    return [t for t in tag_list if t not in found]


def _invalid_counterparty_ids(cp_list: Sequence[str]) -> List[str]:
    from .db import fetch_all

    if not cp_list:
        return []
    rows = fetch_all(
        f"SELECT id FROM counterparty WHERE id IN ({','.join('?' * len(cp_list))})", cp_list
    )
    found = {r["id"] for r in rows}
    return [c for c in cp_list if c not in found]


# ---------------------------------------------------------------------
# 规范化条件标识
# ---------------------------------------------------------------------
def build_query_key(ctx: FilterContext) -> str:
    """生成稳定的规范化条件标识。

    组成: 账本 / 类型 / 起止日 / 时区 / 粒度 / 对比开关 / 维度筛选 / 排序分页。
    同一条件下多模块共享同一 query_key 与 snapshot_version (C129)。
    """
    payload = {
        "book_id": ctx.book_id,
        "type": ctx.stat_type,
        "start_date": ctx.start_date.isoformat(),
        "end_date": ctx.end_date.isoformat(),
        "timezone": ctx.tz_name,
        "granularity": ctx.effective_granularity,
        "comparison_enabled": ctx.comparison_enabled,
        "category_ids": sorted(ctx.category_ids),
        "tag_ids": sorted(ctx.tag_ids),
        "tag_role": ctx.tag_role,
        "counterparty_ids": sorted(ctx.counterparty_ids),
        "income_category_mode": ctx.income_category.mode,
        "income_category_ids": sorted(ctx.income_category.member_ids),
        "expense_category_mode": ctx.expense_category.mode,
        "expense_category_ids": sorted(ctx.expense_category.member_ids),
        "sort": ctx.sort,
        "sort_order": ctx.sort_order,
    }
    # 明细分页不进入统计缓存键, 但要独立区分明细视图
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def build_view_key(ctx: FilterContext, view: str) -> str:
    """模块视图键 = 条件键 + 模块名 (TECH 04 缓存键含模块)。"""
    return f"{view}|{ctx.query_key}"


def build_page_key(ctx: FilterContext, view: str) -> str:
    """明细分页键 (含分页与游标)。"""
    return f"{view}|{ctx.query_key}|page={ctx.page}|size={ctx.page_size}|cursor={ctx.cursor or ''}"


# ---------------------------------------------------------------------
# 同期对比区间 (C32 / C34 / D06)
# ---------------------------------------------------------------------
def previous_period(ctx: FilterContext) -> Tuple[date, date]:
    """计算同期区间。

    * 本周对上周 / 本月对上月 / 本年对上年 (自然周期)
    * 自定义 -> 紧邻等长历史区间
    * 未结束周期按同进度对齐 (C34): 同期起点对齐, 同期终点 = 同期起点 + 已过天数 - 1
    D06 建议口径: 周一为周起点, 月末/闰日截到可用日期, 待最终确认。
    """
    sd, ed = ctx.start_date, ctx.end_date
    today = _today_in(ctx.tz)

    # 自然周期识别
    if sd <= ed:
        # 本周 (周一起)
        week_start = sd - timedelta(days=sd.weekday())
        if sd == week_start and ed <= week_start + timedelta(days=6):
            prev_end = sd - timedelta(days=1)
            prev_start = prev_end - timedelta(days=6)
            return prev_start, prev_end
        # 本月
        if sd.day == 1:
            next_month = (sd.replace(day=28) + timedelta(days=4)).replace(day=1)
            month_end = next_month - timedelta(days=1)
            if ed <= month_end:
                this_month_end = ed
                prev_month_end = sd - timedelta(days=1)
                prev_month_start = prev_month_end.replace(day=1)
                # 未结束周期: 同期按同进度 -> 从上月末开始对齐第 N 天
                elapsed = (this_month_end - sd).days + 1
                aligned_end = prev_month_start + timedelta(days=elapsed - 1)
                if aligned_end > prev_month_end:
                    aligned_end = prev_month_end
                return prev_month_start, aligned_end
        # 本年
        if sd.month == 1 and sd.day == 1:
            year_end = sd.replace(year=sd.year + 1) - timedelta(days=1)
            if ed <= year_end:
                prev_year_end = sd - timedelta(days=1)
                prev_year_start = prev_year_end.replace(month=1, day=1)
                elapsed = (ed - sd).days + 1
                aligned_end = prev_year_start + timedelta(days=elapsed - 1)
                if aligned_end > prev_year_end:
                    aligned_end = prev_year_end
                return prev_year_start, aligned_end

    # 自定义 -> 紧邻等长区间
    length = (ed - sd).days + 1
    prev_end = sd - timedelta(days=1)
    prev_start = prev_end - timedelta(days=length - 1)
    # 未结束周期按同进度对齐
    if ed >= today:
        elapsed = (today - sd).days + 1
        if elapsed < length:
            prev_end = prev_start + timedelta(days=elapsed - 1)
    return prev_start, prev_end


# ---------------------------------------------------------------------
# 趋势分桶 (C29)
# ---------------------------------------------------------------------
def build_buckets(ctx: FilterContext) -> List[Tuple[date, date]]:
    """按粒度生成桶边界。桶边界裁剪到有效日期 (TECH 03)。"""
    gran = ctx.effective_granularity
    sd, ed = ctx.start_date, ctx.end_date
    buckets: List[Tuple[date, date]] = []
    if gran == "day":
        cur = sd
        while cur <= ed:
            buckets.append((cur, cur))
            cur += timedelta(days=1)
    elif gran == "week":
        cur = sd - timedelta(days=sd.weekday())  # 周一起 (D06 建议)
        while cur <= ed:
            bucket_end = min(cur + timedelta(days=6), ed)
            buckets.append((max(cur, sd), bucket_end))
            cur += timedelta(days=7)
    else:  # month
        cur = sd.replace(day=1)
        while cur <= ed:
            next_month = (cur.replace(day=28) + timedelta(days=4)).replace(day=1)
            month_end = next_month - timedelta(days=1)
            buckets.append((max(cur, sd), min(month_end, ed)))
            cur = next_month
    return buckets
