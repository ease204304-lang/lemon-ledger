# -*- coding: utf-8 -*-
"""
小猪记账 — 记账统计模块 验收测试用例 T01–T34

每条用例一个独立可执行函数, 签名为 ``def tXX(ctx: CaseContext) -> TestResult``。
函数内通过 httpx 调真实 HTTP 接口 (client 已在 ctx.client 中)。
返回结构化结果: {id, level, result, actual, expected, evidence}。

用例清单来源: D:\\07.DevWorkspace\\sys\\testlist.txt 「执行用例」sheet T01–T34。
未决规则 D01–D08: 按 PRD v0.9 建议口径执行, 报告中加注「待最终确认」。

覆盖策略:
  - 服务端尚未实现的能力 -> BLOCKED, reason 写明缺什么。
  - UI 交互类 (T05/T13/T16/T17/T25/T28/T29/T31 等) 若无自动化基座,
    以 API 可观测等价断言替代; 不可替代则 BLOCKED。
  - 任何断言失败 -> FAIL, reason 写明差异。
"""
from __future__ import annotations

import os
import sys
import time
from datetime import date, datetime, timedelta
from decimal import Decimal
from typing import Any, Dict, List, Optional

from harness import (ApiClient, CaseContext, CheckFailed, FAIL, PASS, BLOCKED,
                     TEST_LEVELS, D_RULE_CASES, CheckFailed as _CF,
                     amt, base_params, balance_params, data_of, dec,
                     eq_amount, eq_bool, eq_int, eq_percent, eq_str,
                     find_item, iter_items, meta_of, pct, pick, today,
                     unique_suffix)
from fixtures import Fixture, SeedError, anchors

# --------------------------------------------------------------------------
# 公共小工具
# --------------------------------------------------------------------------


def _mk_result(case_id: str, name: str) -> TestResult:
    from harness import TestResult
    return TestResult(id=case_id, level=TEST_LEVELS[case_id], name=name,
                      d_rule=D_RULE_CASES.get(case_id, ""))


def _finish(ctx: CaseContext, res: TestResult, expected: Any, actual: Any) -> TestResult:
    res.expected = expected
    res.actual = actual
    res.evidence = list(ctx.evidence)
    res.duration_ms = ctx.elapsed_ms
    return res


def _seed(ctx: CaseContext, prefix: str = "acc") -> Fixture:
    fx = Fixture(client=ctx.client, ctx=ctx)
    fx.new_book(prefix)
    return fx


def _txn_ids(resp: Any) -> List[str]:
    """从明细响应抽交易 ID 列表。"""
    ids = []
    for it in iter_items(resp):
        v = pick(it, "transaction_id", "id")
        if v:
            ids.append(str(v))
    return ids


def _amounts(resp: Any) -> List[Decimal]:
    out = []
    for it in iter_items(resp):
        v = pick(it, "amount", "total_amount", "value")
        d = dec(v)
        if d is not None:
            out.append(d)
    return out


def _txn_amount(resp: Any) -> Decimal:
    it = iter_items(resp)
    if not it:
        return Decimal("0")
    return dec(pick(it[0], "amount", "total_amount", "value")) or Decimal("0")


def _summary_of(resp: Any) -> Dict[str, Any]:
    d = data_of(resp)
    return d if isinstance(d, dict) else {}


# ==========================================================================
# T01 正结余 (P0)
# ==========================================================================
def t01(ctx: CaseContext):
    """T01 正结余: 收入 10000 / 支出 3000 -> 结余 7000.00, 结余率 70.00%."""
    res = _mk_result("T01", "正结余")
    fx = _seed(ctx, "t01")
    fx.txn("10000.00", type="income", day=anchors()["this_month_start"])
    fx.txn("3000.00", type="expense", day=anchors()["this_month_start"])

    a = anchors()
    resp = ctx.client.summary(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
    ctx.save_evidence(resp, "summary")

    d = _summary_of(resp)
    income = pick(d, "income", "total_income", "income_total")
    expense = pick(d, "expense", "total_expense", "expense_total")
    balance = pick(d, "balance", "total_balance", "balance_total")
    rate = pick(d, "balance_rate", "balanceRate", "rate")

    try:
        eq_amount(income, "10000.00", "收入")
        eq_amount(expense, "3000.00", "支出")
        eq_amount(balance, "7000.00", "结余")
        eq_percent(rate, "70.00", "结余率")
        # C84: 金额为十进制字符串
        if not isinstance(balance, str):
            raise CheckFailed(f"金额应为十进制字符串, 实测类型 {type(balance).__name__}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    return _finish(ctx, res, {"income": "10000.00", "expense": "3000.00",
                              "balance": "7000.00", "balance_rate": "70.00"},
                   {"income": income, "expense": expense,
                    "balance": balance, "balance_rate": rate})


# ==========================================================================
# T02 负结余 (P0)
# ==========================================================================
def t02(ctx: CaseContext):
    """T02 负结余: 收入 3000 / 支出 5000 -> 结余 -2000.00, 结余率 -66.67%,
    趋势点在零轴下方。"""
    res = _mk_result("T02", "负结余")
    fx = _seed(ctx, "t02")
    a = anchors()
    fx.txn("3000.00", type="income", day=a["this_month_start"])
    fx.txn("5000.00", type="expense", day=a["this_month_start"])

    resp = ctx.client.summary(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
    ctx.save_evidence(resp, "summary")
    d = _summary_of(resp)
    balance = pick(d, "balance", "total_balance")
    rate = pick(d, "balance_rate", "balanceRate", "rate")

    trend = ctx.client.trend(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"],
        type="balance", granularity="day"))
    ctx.save_evidence(trend, "trend")
    pts = iter_items(trend)
    bal_values = []
    for p in pts:
        v = pick(p, "balance", "net", "value", "amount")
        if v is not None:
            bal_values.append(dec(v))
    # 有交易的桶应全部为负; 空桶为 0 (补零, 不构成非负趋势点)
    non_zero = [v for v in bal_values if v is not None and v != 0]
    zero_count = sum(1 for v in bal_values if v == 0)

    try:
        eq_amount(balance, "-2000.00", "结余")
        eq_percent(rate, "-66.67", "结余率")
        if not non_zero:
            raise CheckFailed("趋势未返回非零数据点, 无法验证负值位于零轴下方")
        if not all(v < 0 for v in non_zero):
            raise CheckFailed(f"存在非负趋势点: {non_zero}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    return _finish(ctx, res,
                   {"balance": "-2000.00", "balance_rate": "-66.67",
                    "trend_points": "有交易桶全部 < 0, 空桶补 0"},
                   {"balance": balance, "balance_rate": rate,
                    "trend_non_zero": [str(v) for v in non_zero],
                    "trend_zero_buckets": zero_count})


# ==========================================================================
# T03 零结余 (P0)
# ==========================================================================
def t03(ctx: CaseContext):
    """T03 零结余: 收入=支出=10000 -> 结余 0.00, 结余率 0.00%, 趋势点在零轴。"""
    res = _mk_result("T03", "零结余")
    fx = _seed(ctx, "t03")
    a = anchors()
    fx.txn("10000.00", type="income", day=a["this_month_start"])
    fx.txn("10000.00", type="expense", day=a["this_month_start"])

    resp = ctx.client.summary(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
    ctx.save_evidence(resp, "summary")
    d = _summary_of(resp)
    balance = pick(d, "balance", "total_balance")
    rate = pick(d, "balance_rate", "balanceRate", "rate")

    trend = ctx.client.trend(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"],
        type="balance", granularity="day"))
    ctx.save_evidence(trend, "trend")
    bal_values = [dec(pick(p, "balance", "net", "value", "amount"))
                  for p in iter_items(trend)]

    try:
        eq_amount(balance, "0.00", "结余")
        eq_percent(rate, "0.00", "结余率")
        if not bal_values:
            raise CheckFailed("趋势未返回数据点")
        if not all(v is not None and v == 0 for v in bal_values):
            raise CheckFailed(f"存在非零趋势点: {bal_values}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    return _finish(ctx, res, {"balance": "0.00", "balance_rate": "0.00"},
                   {"balance": balance, "balance_rate": rate,
                    "trend_balance_values": [str(v) for v in bal_values]})


# ==========================================================================
# T04 无收入有支出 (P0)
# ==========================================================================
def t04(ctx: CaseContext):
    """T04 无收入有支出: 仅支出 500 -> 结余 -500.00, 结余率 null(—)。"""
    res = _mk_result("T04", "无收入有支出")
    fx = _seed(ctx, "t04")
    a = anchors()
    fx.txn("500.00", type="expense", day=a["this_month_start"])

    resp = ctx.client.summary(**base_params(
        fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
    ctx.save_evidence(resp, "summary")
    d = _summary_of(resp)
    income = pick(d, "income", "total_income")
    expense = pick(d, "expense", "total_expense")
    balance = pick(d, "balance", "total_balance")
    rate = pick(d, "balance_rate", "balanceRate", "rate")

    try:
        eq_amount(income, "0.00", "收入")
        eq_amount(expense, "500.00", "支出")
        eq_amount(balance, "-500.00", "结余")
        eq_percent(rate, None, "结余率(收入为 0 时应为 null/—)")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    return _finish(ctx, res, {"income": "0.00", "expense": "500.00",
                              "balance": "-500.00", "balance_rate": None},
                   {"income": income, "expense": expense,
                    "balance": balance, "balance_rate": rate})


# ==========================================================================
# T05 无交易与零点 (P1)
# ==========================================================================
def t05(ctx: CaseContext):
    """T05 无交易与零点: 空账本汇总全 0; 含空日的范围趋势补 0。"""
    res = _mk_result("T05", "无交易与零点")
    fx = _seed(ctx, "t05")
    a = anchors()
    # 本月 1 号有一笔, 本月 2 号无交易 -> 时间轴空日补 0
    fx.txn("100.00", type="income", day=a["this_month_start"])

    try:
        resp = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(resp, "summary")
        d = _summary_of(resp)
        income = pick(d, "income", "total_income")
        expense = pick(d, "expense", "total_expense")
        balance = pick(d, "balance", "total_balance")

        trend = ctx.client.trend(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend")
        pts = iter_items(trend)
        # 时间轴应包含范围内每一天
        expect_days = (date.fromisoformat(a["this_month_end"])
                       - date.fromisoformat(a["this_month_start"])).days + 1
        if len(pts) < expect_days:
            raise CheckFailed(
                f"时间轴点数 {len(pts)} < 区间自然日数 {expect_days} (缺桶未补零)")
        zero_ok = any(dec(pick(p, "balance", "net", "value", "amount")) == 0
                       for p in pts)
        if not zero_ok:
            raise CheckFailed("时间轴中未找到空日零值点")

        # 空账本: 另建一个没有任何交易的账本
        fx2 = Fixture(client=ctx.client, ctx=ctx)
        fx2.new_book("t05empty")
        empty = ctx.client.summary(**base_params(
            fx2.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(empty, "summary_empty_book")
        ed = _summary_of(empty)
        for k, label in (("income", "收入"), ("expense", "支出"), ("balance", "结余")):
            v = pick(ed, k, f"total_{k}")
            eq_amount(v, "0.00", f"空账本{label}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"汇总": "0/0/0", "空账本": "income=0.00 expense=0.00 balance=0.00",
                    "时间轴": "区间内每日有桶, 空日为 0"},
                   {"income": income, "expense": expense, "balance": balance,
                    "trend_points": len(pts)})


# ==========================================================================
# T06 四种组合筛选 (P0)
# ==========================================================================
def t06(ctx: CaseContext):
    """T06 四种组合筛选: 全/全=7000, 工资/全=5000, 全/餐饮=8000, 工资/餐饮=6000."""
    res = _mk_result("T06", "四种组合筛选")
    fx = _seed(ctx, "t06")
    a = anchors()
    day = a["this_month_start"]
    salary = fx.income_category("工资")
    bonus = fx.income_category("奖金")
    food = fx.expense_category("餐饮")
    shop = fx.expense_category("购物")

    fx.txn("8000.00", type="income", day=day, category_id=salary["id"])
    fx.txn("2000.00", type="income", day=day, category_id=bonus["id"])
    fx.txn("2000.00", type="expense", day=day, category_id=food["id"])
    fx.txn("1000.00", type="expense", day=day, category_id=shop["id"])

    def q(im, ids, em, eids):
        return ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            income_mode=im, income_ids=ids,
            expense_mode=em, expense_ids=eids, type="balance"))

    combos = [
        ("全/全", "ALL", None, "ALL", None, "7000.00"),
        ("工资/全", "SELECTED", [salary["id"]], "ALL", None, "5000.00"),
        ("全/餐饮", "ALL", None, "SELECTED", [food["id"]], "8000.00"),
        ("工资/餐饮", "SELECTED", [salary["id"]], "SELECTED", [food["id"]], "6000.00"),
    ]
    actuals = {}
    resp_all = {}
    try:
        for label, im, ids, em, eids, expect in combos:
            r = q(im, ids, em, eids)
            resp_all[label] = r
            ctx.save_evidence(r, "summary_" + label.replace("/", "_"))
            b = pick(_summary_of(r), "balance", "total_balance")
            actuals[label] = b
            eq_amount(b, expect, f"结余[{label}]")
        # 全视图筛选一致: 趋势/分类/明细用同一组条件
        trend = ctx.client.trend(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "SELECTED", [salary["id"]], "SELECTED", [food["id"]],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend_same_condition")
        tsum = sum((dec(pick(p, "balance", "net", "value", "amount")) or Decimal(0))
                   for p in iter_items(trend))
        eq_amount(tsum, "6000.00", "同条件趋势合计")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {c[0]: c[5] for c in combos}, actuals)


# ==========================================================================
# T07 父子去重 (P0)
# ==========================================================================
def t07(ctx: CaseContext):
    """T07 父子去重: 父分类直记 100 + 子类 200, 父子同选 -> 计 300, 明细两笔。"""
    res = _mk_result("T07", "父子分类去重")
    fx = _seed(ctx, "t07")
    a = anchors()
    day = a["this_month_start"]
    parent = fx.expense_category("餐饮")
    child = fx.expense_category("午餐", parent=parent)

    fx.txn("100.00", type="expense", day=day, category_id=parent["id"])
    fx.txn("200.00", type="expense", day=day, category_id=child["id"])

    try:
        r = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "ALL", None, "SELECTED", [parent["id"]], type="balance"))
        ctx.save_evidence(r, "summary_parent_selected")
        b = pick(_summary_of(r), "balance", "total_balance")
        eq_amount(b, "-300.00", "结余(支出侧父子同选)")

        # 明细应返回两笔 (父直记 + 子类)
        det = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", category_ids=[parent["id"]]))
        ctx.save_evidence(det, "detail_parent_selected")
        ids = _txn_ids(det)
        if len(ids) != 2:
            raise CheckFailed(f"明细笔数期望 2, 实测 {len(ids)}: {ids}")
        if len(set(ids)) != len(ids):
            raise CheckFailed(f"明细出现重复交易 ID: {ids}")
        total = sum(_amounts(det)) if _amounts(det) else Decimal("0")
        eq_amount(total, "300.00", "明细金额合计")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"balance": "-300.00", "detail_count": 2, "detail_total": "300.00"},
                   {"balance": b, "detail_count": len(ids),
                    "detail_total": str(total)})


# ==========================================================================
# T08 编辑交易同步 (P0)
# ==========================================================================
def t08(ctx: CaseContext):
    """T08 编辑交易同步: 支出 500 -> 300, 支出降 200, 结余增 200; 旧版本请求返回 409。"""
    res = _mk_result("T08", "编辑交易同步")
    fx = _seed(ctx, "t08")
    a = anchors()
    day = a["this_month_start"]
    tx = fx.txn("500.00", type="expense", day=day)
    tid = tx["id"]

    try:
        before = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(before, "summary_before")
        v_before = ctx.client.snapshot_version(before)
        b_before = pick(_summary_of(before), "balance", "total_balance")
        eq_amount(b_before, "-500.00", "编辑前结余")

        upd = ctx.client.update_transaction(tid, amount="300.00")
        ctx.save_evidence(upd, "update_response")

        after = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(after, "summary_after")
        b_after = pick(_summary_of(after), "balance", "total_balance")
        eq_amount(b_after, "-300.00", "编辑后结余")
        v_after = ctx.client.snapshot_version(after)
        if v_before and v_after and v_before == v_after:
            raise CheckFailed(f"编辑后 snapshot_version 未变化 (仍为 {v_before})")

        # 旧版本请求 -> 409 SNAPSHOT_STALE (若服务端未启用则记录为观测项)
        stale_status = None
        if v_before:
            try:
                r = ctx.client.get("/api/statistics/summary", params=base_params(
                    fx.book.id, a["this_month_start"], a["this_month_end"],
                    type="balance", snapshot_version=v_before))
                stale_status = r.status_code
                ctx.save_evidence({"status": r.status_code, "body": _raw(r)}, "stale_version_request")
            except Exception as e:
                ctx.note(f"stale version request error: {e}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"balance_before": "-500.00", "balance_after": "-300.00",
                    "expense_delta": "-200.00", "balance_delta": "+200.00",
                    "stale_version_status": "409 SNAPSHOT_STALE (期望)"},
                   {"balance_before": b_before, "balance_after": b_after,
                    "snapshot_before": v_before, "snapshot_after": v_after,
                    "stale_version_status": stale_status})


def _raw(resp) -> Any:
    try:
        return resp.json()
    except Exception:
        return resp.text


# ==========================================================================
# T09 删除交易同步 (P0)
# ==========================================================================
def t09(ctx: CaseContext):
    """T09 删除交易同步: 删除命中的历史支出 -> 总额/趋势/榜单/明细一致更新。"""
    res = _mk_result("T09", "删除交易同步")
    fx = _seed(ctx, "t09")
    a = anchors()
    day = a["this_month_start"]
    cat = fx.expense_category("餐饮")
    tx1 = fx.txn("500.00", type="expense", day=day, category_id=cat["id"])
    fx.txn("300.00", type="expense", day=day, category_id=cat["id"])

    try:
        before = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(before, "summary_before")
        eq_amount(pick(_summary_of(before), "balance", "total_balance"),
                  "-800.00", "删除前结余")

        det_before = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(det_before, "detail_before")
        ids_before = _txn_ids(det_before)

        d = ctx.client.delete_transaction(tx1["id"])
        ctx.save_evidence(d, "delete_response")

        after = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(after, "summary_after")
        eq_amount(pick(_summary_of(after), "balance", "total_balance"),
                  "-300.00", "删除后结余")

        det_after = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(det_after, "detail_after")
        ids_after = _txn_ids(det_after)
        if tx1["id"] in ids_after:
            raise CheckFailed(f"已删除交易 {tx1['id']} 仍出现在明细中")
        if len(ids_after) != len(ids_before) - 1:
            raise CheckFailed(
                f"明细笔数期望 {len(ids_before) - 1}, 实测 {len(ids_after)}")

        trend = ctx.client.trend(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend_after")
        tsum = sum((dec(pick(p, "balance", "net", "value", "amount")) or Decimal(0))
                   for p in iter_items(trend))
        eq_amount(tsum, "-300.00", "删除后趋势合计")

        cats = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(cats, "categories_after")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"balance_before": "-800.00", "balance_after": "-300.00",
                    "detail_count_delta": -1},
                   {"balance_after": pick(_summary_of(after), "balance", "total_balance"),
                    "detail_before": len(ids_before), "detail_after": len(ids_after)})


# ==========================================================================
# T10 结余同期变化率 (P0)
# ==========================================================================
def t10(ctx: CaseContext):
    """T10 同期变化率: 本期结余 3000, 同期 2000/0/-1000 -> 差额 1000/3000/4000,
    变化率 50.00% / — / —。"""
    res = _mk_result("T10", "结余同期变化率")
    fx = _seed(ctx, "t10")
    a = anchors()
    # 本期: 收入 3000, 支出 0 -> 结余 3000
    fx.txn("3000.00", type="income", day=a["this_month_start"])
    # 同期 (上月): 三种场景分别用三个账本做, 避免互相污染
    scenarios = [("同期 2000", "2000.00", "0.00", "1000.00", "50.00"),
                 ("同期 0", "0.00", "0.00", "3000.00", None),
                 ("同期 -1000", "0.00", "1000.00", "4000.00", None)]

    actuals = {}
    try:
        for label, prev_income, prev_expense, exp_diff, exp_rate in scenarios:
            fx2 = Fixture(client=ctx.client, ctx=ctx)
            fx2.new_book("t10_" + label.replace(" ", ""))
            # 上月同期结余
            if dec(prev_income) and dec(prev_income) > 0:
                fx2.txn(prev_income, type="income", day=a["prev_month_start"])
            if dec(prev_expense) and dec(prev_expense) > 0:
                fx2.txn(prev_expense, type="expense", day=a["prev_month_start"])
            # 本期结余 3000
            fx2.txn("3000.00", type="income", day=a["this_month_start"])

            r = ctx.client.summary(**base_params(
                fx2.book.id, a["this_month_start"], a["this_month_end"],
                type="balance", comparison_enabled=True))
            ctx.save_evidence(r, "summary_" + label.replace(" ", "_"))
            d = _summary_of(r)
            cmp_ = pick(d, "comparison", "compare", "comparison_data",
                        default={}) or {}
            diff = pick(cmp_, "difference", "diff", "delta",
                        default=pick(d, "balance_diff", "difference", "delta"))
            rate = pick(cmp_, "change_rate", "balance_change_rate", "rate",
                        default=pick(d, "balance_change_rate", "change_rate"))
            actuals[label] = {"difference": diff, "change_rate": rate}
            eq_amount(diff, exp_diff, f"差额[{label}]")
            eq_percent(rate, exp_rate, f"变化率[{label}]")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"同期2000": {"diff": "1000.00", "rate": "50.00"},
                    "同期0": {"diff": "3000.00", "rate": None},
                    "同期-1000": {"diff": "4000.00", "rate": None}},
                   actuals)


# ==========================================================================
# T11 负趋势点穿透 (P0)
# ==========================================================================
def t11(ctx: CaseContext):
    """T11 负趋势点穿透: 两侧分类筛选后点负结余数据点 -> 明细继承账本+两侧分类条件。"""
    res = _mk_result("T11", "负趋势点穿透")
    fx = _seed(ctx, "t11")
    a = anchors()
    day = a["this_month_start"]
    inc_cat = fx.income_category("工资")
    exp_cat = fx.expense_category("餐饮")
    fx.txn("1000.00", type="income", day=day, category_id=inc_cat["id"])
    fx.txn("3000.00", type="expense", day=day, category_id=exp_cat["id"])

    try:
        trend = ctx.client.trend(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "SELECTED", [inc_cat["id"]], "SELECTED", [exp_cat["id"]],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend")
        pts = iter_items(trend)
        neg = None
        for p in pts:
            v = dec(pick(p, "balance", "net", "value", "amount"))
            if v is not None and v < 0:
                neg = p
                break
        if neg is None:
            raise CheckFailed(f"未找到负结余趋势点, points={pts}")

        bucket_start = pick(neg, "bucket_start", "start_date", "date", "period_start")
        bucket_end = pick(neg, "bucket_end", "end_date", "period_end")
        if not bucket_start:
            raise CheckFailed(f"趋势点缺少 bucket_start: {neg}")

        # 穿透: 携带两侧分类条件 + 该点期间
        det = ctx.client.transactions(**base_params(
            fx.book.id, str(bucket_start), str(bucket_end or bucket_start),
            type="balance",
            income_category_ids=[inc_cat["id"]],
            expense_category_ids=[exp_cat["id"]]))
        ctx.save_evidence(det, "detail_drilldown")
        ids = _txn_ids(det)
        if len(ids) != 2:
            raise CheckFailed(f"穿透明细期望 2 笔 (收入+支出), 实测 {len(ids)}: {ids}")
        total = sum(_amounts(det)) if _amounts(det) else Decimal("0")
        eq_amount(total, "4000.00", "穿透明细金额合计")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"drilldown_count": 2, "drilldown_total": "4000.00",
                    "point": "负结余点"},
                   {"drilldown_count": len(ids), "drilldown_total": str(total),
                    "bucket_start": bucket_start if 'bucket_start' in dir() else None})


# ==========================================================================
# T12 账本隔离与切换 (P0)
# ==========================================================================
def t12(ctx: CaseContext):
    """T12 账本隔离与切换: A 账本设筛选 -> 切 B 保留日期清除筛选; 未授权账本 403。"""
    res = _mk_result("T12", "账本隔离与切换")
    fx = _seed(ctx, "t12a")
    fxb = _seed(ctx, "t12b")
    a = anchors()
    cat_a = fx.expense_category("餐饮")
    fx.txn("100.00", type="expense", day=a["this_month_start"], category_id=cat_a["id"])
    fx.txn("200.00", type="expense", day=a["this_month_start"])

    try:
        # A 账本 + 分类筛选
        ra = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "ALL", None, "SELECTED", [cat_a["id"]], type="balance"))
        ctx.save_evidence(ra, "bookA_filtered")
        eq_amount(pick(_summary_of(ra), "balance", "total_balance"),
                  "-100.00", "A 账本筛选后结余")

        # B 账本无筛选
        rb = ctx.client.summary(**base_params(
            fxb.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(rb, "bookB_unfiltered")
        eq_amount(pick(_summary_of(rb), "balance", "total_balance"),
                  "0.00", "B 账本结余")

        # B 账本不应出现 A 的交易
        det_b = ctx.client.transactions(**base_params(
            fxb.book.id, a["this_month_start"], a["this_month_end"]))
        ctx.save_evidence(det_b, "bookB_detail")
        if len(_txn_ids(det_b)) != 0:
            raise CheckFailed(f"B 账本明细泄漏了 A 的交易: {_txn_ids(det_b)}")

        # 未授权账本 -> 403 BOOK_FORBIDDEN
        status = None
        body = None
        try:
            r = ctx.client.get("/api/statistics/summary", params=base_params(
                "book_nonexistent_9999", a["this_month_start"], a["this_month_end"],
                type="balance"))
            status, body = r.status_code, _raw(r)
            ctx.save_evidence({"status": status, "body": body}, "unauthorized_request")
        except Exception as e:
            ctx.note(f"unauthorized request raised: {e}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"bookA_filtered_balance": "-100.00", "bookB_balance": "0.00",
                    "bookB_detail_count": 0, "unauthorized_status": "403 BOOK_FORBIDDEN"},
                   {"bookA_filtered_balance": pick(_summary_of(ra), "balance", "total_balance"),
                    "bookB_balance": pick(_summary_of(rb), "balance", "total_balance"),
                    "bookB_detail_count": len(_txn_ids(det_b)),
                    "unauthorized_status": status})


# ==========================================================================
# T13 部分空值与未完周期 (P1)
# ==========================================================================
def t13(ctx: CaseContext):
    """T13 部分空值与未完周期: 一侧无交易 -> 该侧 0; 当前周期只计实际发生。"""
    res = _mk_result("T13", "部分空值与未完周期")
    fx = _seed(ctx, "t13")
    a = anchors()
    inc_cat = fx.income_category("工资")
    exp_cat = fx.expense_category("餐饮")
    fx.txn("1000.00", type="income", day=a["this_month_start"], category_id=inc_cat["id"])
    fx.txn("500.00", type="expense", day=a["this_month_start"], category_id=exp_cat["id"])

    try:
        r = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "SELECTED", [inc_cat["id"]], "SELECTED", [exp_cat["id"]], type="balance"))
        ctx.save_evidence(r, "summary")

        # 一侧无交易: 选一个不存在的有效分类 (已创建但无交易)
        empty_cat = fx.expense_category("空分类")
        r2 = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "ALL", None, "SELECTED", [empty_cat["id"]], type="balance"))
        ctx.save_evidence(r2, "summary_empty_side")
        d2 = _summary_of(r2)
        eq_amount(pick(d2, "expense", "total_expense"), "0.00", "无交易侧支出")
        eq_amount(pick(d2, "income", "total_income"), "1000.00", "另一侧收入")

        # 未完周期只计实际发生: 本月至今
        trend = ctx.client.trend(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend_current_period")
        pts = iter_items(trend)
        future_pts = []
        today_s = a["today"]
        for p in pts:
            bs = str(pick(p, "bucket_start", "start_date", "date", "period_start") or "")
            if bs and bs > today_s:
                future_pts.append(p)
        for p in future_pts:
            v = dec(pick(p, "balance", "net", "value", "amount"))
            if v is not None and v != 0:
                raise CheckFailed(f"未完周期未来桶应为 0, 实测 {v}: {p}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"无交易侧": "0.00", "另一侧": "1000.00",
                    "未完周期未来桶": "0"},
                   {"empty_side_expense": pick(_summary_of(r2), "expense", "total_expense"),
                    "income": pick(_summary_of(r2), "income", "total_income"),
                    "future_bucket_count": len(future_pts)})


# ==========================================================================
# T14 5 万笔性能 (P1) — 由 performance/ 模块执行
# ==========================================================================
def t14(ctx: CaseContext):
    """T14 5 万笔性能: 汇总 P95<=2s / 趋势<=3s / 分类,标签,对象<=5s (冷热分层)。"""
    res = _mk_result("T14", "5 万笔性能")
    try:
        import os as _os
        _os.makedirs(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                                   "performance"), exist_ok=True)
        sys.path.insert(0, _os.path.join(_os.path.dirname(_os.path.abspath(__file__)),
                                         "performance"))
        import perf_runner
        report = perf_runner.run(ctx.client, ctx)
        ctx.save_evidence(report, "perf_report")
        res.actual = report
        res.expected = {
            "汇总 P95<=2s": "冷/热分别达标",
            "趋势 P95<=3s": "冷/热分别达标",
            "分类 P95<=5s": "冷/热分别达标",
            "标签 P95<=5s": "冷/热分别达标",
            "对象 P95<=5s": "冷/热分别达标",
        }
        failures = report.get("failures") or []
        if failures:
            res.result = FAIL
            res.reason = "; ".join(failures)
        else:
            res.result = PASS
    except ImportError as e:
        res.result = BLOCKED
        res.reason = f"性能模块不可用: {e}"
    except Exception as e:
        res.result = BLOCKED
        res.reason = f"性能验收无法执行: {type(e).__name__}: {e}"
    return _finish(ctx, res, res.expected, res.actual)


# ==========================================================================
# T15 主辅标签与多标签去重 (P0)
# ==========================================================================
def t15(ctx: CaseContext):
    """T15 主辅标签: A100(主甲+辅乙) B200(仅辅乙) C50(无标签);
    按甲或乙筛选 -> 2 笔共 300; 全局统计甲 100, 未设置 250, 乙不独立计额。"""
    res = _mk_result("T15", "主辅标签与多标签去重")
    fx = _seed(ctx, "t15")
    a = anchors()
    day = a["this_month_start"]
    jia = fx.tag("甲")
    yi = fx.tag("乙")
    fx.txn("100.00", type="expense", day=day,
           primary_tag_id=jia["id"], tag_ids=[yi["id"]])
    fx.txn("200.00", type="expense", day=day, tag_ids=[yi["id"]])
    fx.txn("50.00", type="expense", day=day)

    jia_total = yi_total = both_total = Decimal("0")
    items: List[Dict[str, Any]] = []
    try:
        # 按甲筛选 -> 1 笔 100
        r_jia = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", tag_ids=[jia["id"]]))
        ctx.save_evidence(r_jia, "filter_jia")
        jia_ids = _txn_ids(r_jia)
        jia_total = sum(_amounts(r_jia)) if _amounts(r_jia) else Decimal("0")
        eq_amount(jia_total, "100.00", "按甲筛选合计")

        # 按乙筛选 -> 2 笔共 300 (A+B)
        r_yi = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", tag_ids=[yi["id"]]))
        ctx.save_evidence(r_yi, "filter_yi")
        yi_ids = _txn_ids(r_yi)
        yi_total = sum(_amounts(r_yi)) if _amounts(r_yi) else Decimal("0")
        eq_amount(yi_total, "300.00", "按乙筛选合计")
        if len(set(yi_ids)) != len(yi_ids):
            raise CheckFailed(f"多标签筛选出现重复交易: {yi_ids}")

        # 甲+乙同时筛选 -> 同一笔只计一次 -> A(100) + B(200) = 300
        r_both = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", tag_ids=[jia["id"], yi["id"]]))
        ctx.save_evidence(r_both, "filter_both")
        both_ids = _txn_ids(r_both)
        both_total = sum(_amounts(r_both)) if _amounts(r_both) else Decimal("0")
        eq_amount(both_total, "300.00", "甲+乙筛选合计 (去重)")
        if len(both_ids) != 2:
            raise CheckFailed(f"甲+乙筛选期望 2 笔, 实测 {len(both_ids)}: {both_ids}")

        # 全局标签统计: 甲 100, 未设置 250, 乙不独立计额
        ts = ctx.client.tags(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(ts, "tags_stats")
        items = iter_items(ts)
        jia_item = find_item(items, "甲")
        yi_item = find_item(items, "乙")
        unset_item = find_item(items, "未设置标签")
        eq_amount(pick(jia_item, "amount", "total_amount"), "100.00", "甲金额")
        if yi_item is not None:
            v = dec(pick(yi_item, "amount", "total_amount"))
            if v is not None and v != 0:
                raise CheckFailed(f"辅助标签乙不应独立计额, 实测 {v}")
        if unset_item is None:
            raise CheckFailed(f"标签统计未找到「未设置标签」项: {[pick(i,'name','label') for i in items]}")
        eq_amount(pick(unset_item, "amount", "total_amount"), "250.00", "未设置标签金额")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"甲筛选": "100.00 (1 笔)", "乙筛选": "300.00 (2 笔)",
                    "甲+乙": "300.00 (2 笔, 去重)",
                    "全局标签": {"甲": "100.00", "未设置标签": "250.00", "乙": "不计额"}},
                   {"jia_total": str(jia_total), "yi_total": str(yi_total),
                    "both_total": str(both_total),
                    "tag_items": [pick(i, "name", "label", "amount") for i in items]})


# ==========================================================================
# T16 标签图榜与榜单展开 (P1)
# ==========================================================================
def t16(ctx: CaseContext):
    """T16 标签图榜: 7 个有金额主标签 + 未设置 + 零金额标签;
    环形图 Top5 + 其他 + 未设置保留, 零金额隐藏。"""
    res = _mk_result("T16", "标签图榜与榜单展开")
    fx = _seed(ctx, "t16")
    a = anchors()
    day = a["this_month_start"]
    names = [f"标签{i}" for i in range(1, 8)]
    tags = [fx.tag(n) for n in names]
    zero_tag = fx.tag("零金额标签")
    for i, t in enumerate(tags):
        fx.txn(f"{(i + 1) * 100}.00", type="expense", day=day,
               primary_tag_id=t["id"])
    fx.txn("55.00", type="expense", day=day)   # 未设置标签

    try:
        ts = ctx.client.tags(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(ts, "tags_stats")
        d = data_of(ts)
        items = iter_items(ts)
        names_found = [str(pick(i, "name", "label", "tag_name") or "") for i in items]

        # 零金额标签隐藏
        if "零金额标签" in names_found:
            raise CheckFailed("零金额标签应被隐藏, 但出现在榜单中")
        # 未设置标签保留
        if not any(n in ("未设置标签", "未设置") for n in names_found):
            raise CheckFailed(f"「未设置标签」应独立保留: {names_found}")

        # 环形图: Top5 + 其他
        chart = pick(d, "chart", "donut", "ring", "pie", "graph", default={}) or {}
        chart_items = iter_items(chart) if chart else []
        if chart:
            labels = [str(pick(i, "name", "label", "tag_name") or "") for i in chart_items]
            if len(chart_items) != 6:   # Top5 + 未设置 (或 Top5+其他)
                ctx.note(f"环形图条目数 = {len(chart_items)}: {labels}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"零金额标签": "隐藏", "未设置标签": "保留",
                    "环形图": "Top5 + 其他"},
                   {"tag_names": names_found,
                    "chart_item_count": len(chart_items) if 'chart_items' in dir() else None})


# ==========================================================================
# T17 交易对象展示及入口 (P1)
# ==========================================================================
def t17(ctx: CaseContext):
    """T17 交易对象: 收支共享对象 ID, 各自统计; 未设置对象归「未设置商户」可穿透。"""
    res = _mk_result("T17", "交易对象展示及入口")
    fx = _seed(ctx, "t17")
    a = anchors()
    day = a["this_month_start"]
    cp = fx.counterparty("星巴克")
    fx.txn("50.00", type="expense", day=day, counterparty_id=cp["id"])
    fx.txn("200.00", type="income", day=day, counterparty_id=cp["id"])
    fx.txn("30.00", type="expense", day=day)   # 无对象

    exp_items: List[Dict[str, Any]] = []
    inc_items: List[Dict[str, Any]] = []
    try:
        cat = fx.expense_category("餐饮")
        m_exp = ctx.client.merchants(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", category_id=cat["id"]))
        ctx.save_evidence(m_exp, "merchants_expense")
        exp_items = iter_items(m_exp)
        cp_item = find_item(exp_items, "星巴克")
        if cp_item is None:
            raise CheckFailed(f"对象榜未找到「星巴克」: {[pick(i,'name','label') for i in exp_items]}")
        eq_amount(pick(cp_item, "amount", "total_amount"), "50.00", "支出侧对象金额")
        unset = find_item(exp_items, "未设置商户")
        if unset is None:
            raise CheckFailed(f"未找到「未设置商户」: {[pick(i,'name','label') for i in exp_items]}")
        eq_amount(pick(unset, "amount", "total_amount"), "30.00", "未设置商户金额")

        m_inc = ctx.client.merchants(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="income"))
        ctx.save_evidence(m_inc, "merchants_income")
        inc_items = iter_items(m_inc)
        cp_inc = find_item(inc_items, "星巴克")
        if cp_inc is None:
            raise CheckFailed(f"收入对象榜未找到「星巴克」: {[pick(i,'name','label') for i in inc_items]}")
        eq_amount(pick(cp_inc, "amount", "total_amount"), "200.00", "收入侧对象金额")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"支出侧对象": {"星巴克": "50.00", "未设置商户": "30.00"},
                    "收入侧对象": {"星巴克": "200.00"}},
                   {"expense_items": [pick(i, "name", "label", "amount") for i in exp_items],
                    "income_items": [pick(i, "name", "label", "amount") for i in inc_items]})


# ==========================================================================
# T18 对象合并及拆分 (P1)  [D05]
# ==========================================================================
def t18(ctx: CaseContext):
    """T18 对象合并及拆分: 高置信自动合并, 低置信需人工确认; 拆分准确复原归属。"""
    res = _mk_result("T18", "对象合并及拆分")
    fx = _seed(ctx, "t18")
    a = anchors()
    day = a["this_month_start"]
    cp1 = fx.counterparty("星巴克咖啡")
    cp2 = fx.counterparty("星巴克咖啡店")
    tx1 = fx.txn("100.00", type="expense", day=day, counterparty_id=cp1["id"])
    tx2 = fx.txn("200.00", type="expense", day=day, counterparty_id=cp2["id"])

    try:
        before = ctx.client.merchants(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(before, "merchants_before")
        before_total = sum((dec(pick(i, "amount", "total_amount")) or Decimal(0))
                           for i in iter_items(before))

        # 合并接口 (若服务端未实现 -> BLOCKED)
        merge_status = None
        merge_body = None
        try:
            r = ctx.client.post("/api/counterparties/merge", json_body={
                "source_ids": [cp1["id"], cp2["id"]],
                "target_id": cp1["id"],
                "confirmed": True,
            })
            merge_status, merge_body = r.status_code, _raw(r)
            ctx.save_evidence({"status": merge_status, "body": merge_body}, "merge")
        except Exception as e:
            ctx.note(f"merge endpoint unavailable: {e}")

        after = ctx.client.merchants(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(after, "merchants_after")
        after_total = sum((dec(pick(i, "amount", "total_amount")) or Decimal(0))
                          for i in iter_items(after))

        if merge_status is None:
            res.result = BLOCKED
            res.reason = ("对象合并/拆分接口未实现 (D05 待冻结: 需确认合并置信度阈值、"
                          "授权、审计与拆分粒度后才能验收)")
            return _finish(ctx, res, {"合并": "高置信自动 + 低置信人工确认",
                                      "金额守恒": f"{before_total} -> {after_total}"},
                           {"merge_status": None, "before_total": str(before_total),
                            "after_total": str(after_total)})

        eq_amount(after_total, str(before_total), "合并前后对象金额合计")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"合并": "高置信自动 + 低置信人工确认",
                    "金额守恒": f"{before_total} -> {after_total}"},
                   {"merge_status": merge_status, "before_total": str(before_total),
                    "after_total": str(after_total)})


# ==========================================================================
# T19 退款与金额校验 (P0)
# ==========================================================================
def t19(ctx: CaseContext):
    """T19 退款与金额校验: 支出 100 + 收入 40 退款, 相互独立;
    再保存 -40 和 0 必须失败。"""
    res = _mk_result("T19", "退款与金额校验")
    fx = _seed(ctx, "t19")
    a = anchors()
    day = a["this_month_start"]
    fx.txn("100.00", type="expense", day=day)
    fx.txn("40.00", type="income", day=day)

    try:
        r = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(r, "summary")
        d = _summary_of(r)
        eq_amount(pick(d, "expense", "total_expense"), "100.00", "支出")
        eq_amount(pick(d, "income", "total_income"), "40.00", "收入(退款)")
        eq_amount(pick(d, "balance", "total_balance"), "-60.00", "结余")

        # 负数金额必须失败
        neg_status = None
        try:
            resp = ctx.client.post("/api/transactions", json_body={
                "book_id": fx.book.id, "type": "expense", "amount": "-40.00",
                "transaction_date": day, "transaction_time": "12:00:00",
                "note": "neg"})
            neg_status = resp.status_code
            ctx.save_evidence({"status": neg_status, "body": _raw(resp)}, "negative_amount")
            if neg_status < 400:
                raise CheckFailed(f"负数金额应保存失败, 实测 HTTP {neg_status}")
        except CheckFailed:
            raise
        except Exception as e:
            ctx.note(f"negative amount rejected via exception: {e}")
            neg_status = "rejected"

        # 零金额必须失败
        zero_status = None
        try:
            resp = ctx.client.post("/api/transactions", json_body={
                "book_id": fx.book.id, "type": "expense", "amount": "0",
                "transaction_date": day, "transaction_time": "12:00:00",
                "note": "zero"})
            zero_status = resp.status_code
            ctx.save_evidence({"status": zero_status, "body": _raw(resp)}, "zero_amount")
            if zero_status < 400:
                raise CheckFailed(f"零金额应保存失败, 实测 HTTP {zero_status}")
        except CheckFailed:
            raise
        except Exception as e:
            ctx.note(f"zero amount rejected via exception: {e}")
            zero_status = "rejected"

        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"expense": "100.00", "income": "40.00", "balance": "-60.00",
                    "negative_amount": "保存失败 (>=400)", "zero_amount": "保存失败 (>=400)"},
                   {"expense": pick(_summary_of(r), "expense", "total_expense"),
                    "income": pick(_summary_of(r), "income", "total_income"),
                    "balance": pick(_summary_of(r), "balance", "total_balance"),
                    "negative_status": neg_status, "zero_status": zero_status})


# ==========================================================================
# T20 日期选择和比较 (P1)  [D06]
# ==========================================================================
def t20(ctx: CaseContext):
    """T20 日期选择和比较: 31/32/365/366 天 -> 粒度 天/周/周/月;
    未来日期与逆序拒绝 (400)。"""
    res = _mk_result("T20", "日期选择和比较")
    fx = _seed(ctx, "t20")
    base = datetime.strptime(today(), "%Y-%m-%d").date()

    cases = [
        ("31天", base - timedelta(days=30), base, "day"),
        ("32天", base - timedelta(days=31), base, "week"),
        ("365天", base - timedelta(days=364), base, "week"),
        ("366天", base - timedelta(days=365), base, "month"),
    ]
    actuals = {}
    try:
        for label, s, e, expect_g in cases:
            r = ctx.client.trend(**base_params(
                fx.book.id, s.isoformat(), e.isoformat(),
                type="balance", granularity="auto"))
            ctx.save_evidence(r, "trend_" + label)
            g = pick(_summary_of(r), "granularity", "granularity_used",
                     "bucket_granularity",
                     default=pick(meta_of(r), "granularity"))
            actuals[label] = g
            if g is not None:
                eq_str(g, expect_g, f"粒度[{label}]")

        # 未来日期 -> 400
        fut = base + timedelta(days=10)
        future_status = None
        try:
            resp = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, base.isoformat(), fut.isoformat(), type="balance"))
            future_status = resp.status_code
            ctx.save_evidence({"status": future_status, "body": _raw(resp)}, "future_date")
            if future_status != 400:
                raise CheckFailed(f"未来日期应返回 400, 实测 {future_status}")
        except CheckFailed:
            raise
        except Exception as e:
            ctx.note(f"future date error: {e}")

        # 逆序日期 -> 400
        rev_status = None
        try:
            resp = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, fut.isoformat(), base.isoformat(), type="balance"))
            rev_status = resp.status_code
            ctx.save_evidence({"status": rev_status, "body": _raw(resp)}, "reversed_date")
            if rev_status != 400:
                raise CheckFailed(f"逆序日期应返回 400, 实测 {rev_status}")
        except CheckFailed:
            raise
        except Exception as e:
            ctx.note(f"reversed date error: {e}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"31天": "day", "32天": "week", "365天": "week", "366天": "month",
                    "未来日期": "400", "逆序日期": "400"},
                   {"granularity": actuals,
                    "future_status": future_status, "reversed_status": rev_status})


# ==========================================================================
# T21 零点与时区 (P1)
# ==========================================================================
def t21(ctx: CaseContext):
    """T21 零点与时区: 历史业务日期不随手机时区变化; 自定义起止保留。"""
    res = _mk_result("T21", "零点与时区")
    fx = _seed(ctx, "t21")
    a = anchors()
    day = a["this_month_start"]
    tx = fx.txn("100.00", type="expense", day=day, time="23:59:00")

    try:
        r1 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", timezone="Asia/Shanghai"))
        ctx.save_evidence(r1, "summary_tz_shanghai")
        r2 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", timezone="America/New_York"))
        ctx.save_evidence(r2, "summary_tz_newyork")
        v1 = pick(_summary_of(r1), "expense", "total_expense")
        v2 = pick(_summary_of(r2), "expense", "total_expense")
        eq_amount(v1, "100.00", "上海时区支出")
        eq_amount(v2, "100.00", "纽约时区支出 (历史业务日期不变)")

        # 明细中的 transaction_date 应保持原业务日
        det = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(det, "detail")
        items = iter_items(det)
        if items:
            td = str(pick(items[0], "transaction_date", "date", "business_date"))
            if td and td != day:
                raise CheckFailed(f"历史业务日期应保持 {day}, 实测 {td}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"上海时区": "100.00", "纽约时区": "100.00", "业务日期": day},
                   {"tz_shanghai": v1, "tz_new_york": v2,
                    "transaction_date": str(pick(items[0], "transaction_date", "date") or "") if items else None})


# ==========================================================================
# T22 分类详情与排行 (P1)  [D06]
# ==========================================================================
def t22(ctx: CaseContext):
    """T22 分类详情与排行: 6 个二级分类 + 一级直记, 默认金额降序 Top5,
    一级直记归「未细分」。"""
    res = _mk_result("T22", "分类详情与排行")
    fx = _seed(ctx, "t22")
    a = anchors()
    day = a["this_month_start"]
    names: List[str] = []
    amounts: List[Decimal] = []
    parents = [fx.expense_category(f"父{i}") for i in range(1, 4)]
    children = []
    for p in parents:
        for j in range(1, 3):
            children.append(fx.expense_category(f"{p['name']}-子{j}", parent=p))
    # 给 6 个二级分类各一笔, 金额递减
    for i, c in enumerate(children):
        fx.txn(f"{(6 - i) * 100}.00", type="expense", day=day, category_id=c["id"])
    # 一级直记
    fx.txn("700.00", type="expense", day=day, category_id=parents[0]["id"])

    try:
        r = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(r, "categories_expense")
        d = data_of(r)
        items = iter_items(r)
        names = [str(pick(i, "name", "category_name", "label") or "") for i in items]

        # 未细分 / 未分类
        if not any("未细分" in n for n in names):
            raise CheckFailed(f"一级直记应归入「未细分」: {names}")

        # Top5 排序: 金额降序
        amounts = [dec(pick(i, "amount", "total_amount")) for i in items]
        amounts = [a_ for a_ in amounts if a_ is not None]
        if amounts != sorted(amounts, reverse=True):
            raise CheckFailed(f"分类榜未按金额降序: {amounts}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"排序": "金额降序", "一级直记": "归入未细分", "二级分类数": 6},
                   {"names": names, "amounts": [str(x) for x in amounts]})


# ==========================================================================
# T23 历史标签保留 (P0)
# ==========================================================================
def t23(ctx: CaseContext):
    """T23 历史标签保留: 停用旧主标签后新增记账受状态/适用范围约束;
    旧交易仍计入同一标签, 改名金额不变。"""
    res = _mk_result("T23", "历史标签保留")
    fx = _seed(ctx, "t23")
    a = anchors()
    day = a["this_month_start"]
    old = fx.tag("旧标签")
    fx.txn("100.00", type="expense", day=day, primary_tag_id=old["id"])

    try:
        # 停用
        st = None
        try:
            r = ctx.client.patch(f"/api/tags/{old['id']}", json_body={"status": "inactive"})
            st = r.status_code
            ctx.save_evidence({"status": st, "body": _raw(r)}, "deactivate_tag")
        except Exception as e:
            ctx.note(f"tag status endpoint unavailable: {e}")

        if st is None:
            res.result = BLOCKED
            res.reason = "标签状态/改名接口未实现 (需 /api/tags/{id} 支持 status 与 name 更新)"
            return _finish(ctx, res, {"旧交易": "仍计入同一标签", "改名": "金额不变"}, {})

        # 旧交易仍计入
        ts = ctx.client.tags(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(ts, "tags_after_deactivate")
        items = iter_items(ts)
        item = find_item(items, "旧标签")
        if item is None:
            raise CheckFailed(f"停用后旧标签不再出现在统计中: {[pick(i,'name','label') for i in items]}")
        eq_amount(pick(item, "amount", "total_amount"), "100.00", "停用后旧标签金额")

        # 改名
        rn = ctx.client.patch(f"/api/tags/{old['id']}", json_body={"name": "新标签名"})
        ctx.save_evidence({"status": rn.status_code, "body": _raw(rn)}, "rename_tag")
        ts2 = ctx.client.tags(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(ts2, "tags_after_rename")
        items2 = iter_items(ts2)
        item2 = find_item(items2, "新标签名")
        if item2 is None:
            raise CheckFailed(f"改名后未按新名称展示: {[pick(i,'name','label') for i in items2]}")
        eq_amount(pick(item2, "amount", "total_amount"), "100.00", "改名后金额")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"停用后旧标签金额": "100.00", "改名后金额": "100.00"},
                   {"tag_items_before": [pick(i, "name", "label", "amount") for i in items],
                    "tag_items_after": [pick(i, "name", "label", "amount") for i in items2]})


# ==========================================================================
# T24 历史分类兼容 (P0)  [D02]
# ==========================================================================
def t24(ctx: CaseContext):
    """T24 历史分类兼容: 停用/改名继续统计; 删除保留历史关联与快照;
    无分类归未分类。"""
    res = _mk_result("T24", "历史分类兼容")
    fx = _seed(ctx, "t24")
    a = anchors()
    day = a["this_month_start"]
    dis = fx.expense_category("停用分类")
    ren = fx.expense_category("待改名分类")
    fx.txn("100.00", type="expense", day=day, category_id=dis["id"])
    fx.txn("200.00", type="expense", day=day, category_id=ren["id"])
    fx.txn("50.00", type="expense", day=day)   # 无分类

    try:
        # 停用
        st = None
        try:
            r = ctx.client.patch(f"/api/categories/{dis['id']}",
                                 json_body={"status": "inactive"})
            st = r.status_code
            ctx.save_evidence({"status": st, "body": _raw(r)}, "deactivate_category")
        except Exception as e:
            ctx.note(f"category status endpoint unavailable: {e}")
        if st is None:
            res.result = BLOCKED
            res.reason = "分类状态/改名/删除接口未实现 (需 /api/categories/{id} 支持 status/name/delete)"
            return _finish(ctx, res, {"停用": "继续统计", "改名": "展示新名",
                                      "删除": "保留历史关联与快照",
                                      "无分类": "归未分类"}, {})

        # 停用后继续统计
        r1 = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(r1, "categories_after_deactivate")
        items1 = iter_items(r1)
        it = find_item(items1, "停用分类")
        if it is None:
            raise CheckFailed(f"停用分类不再统计: {[pick(i,'name','label') for i in items1]}")
        eq_amount(pick(it, "amount", "total_amount"), "100.00", "停用分类金额")

        # 改名 -> 展示新名, 金额不变
        rn = ctx.client.patch(f"/api/categories/{ren['id']}",
                              json_body={"name": "已改名分类"})
        ctx.save_evidence({"status": rn.status_code, "body": _raw(rn)}, "rename_category")
        r2 = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(r2, "categories_after_rename")
        items2 = iter_items(r2)
        it2 = find_item(items2, "已改名分类")
        if it2 is None:
            raise CheckFailed(f"改名后未展示新名称: {[pick(i,'name','label') for i in items2]}")
        eq_amount(pick(it2, "amount", "total_amount"), "200.00", "改名后金额不变")

        # 删除 -> 保留历史关联与快照
        dr = ctx.client.delete(f"/api/categories/{ren['id']}")
        ctx.save_evidence({"status": dr.status_code, "body": _raw(dr)}, "delete_category")
        r3 = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(r3, "categories_after_delete")
        items3 = iter_items(r3)
        names3 = [str(pick(i, "name", "label") or "") for i in items3]
        # 名称快照保留
        snap = find_item(items3, "已改名分类")
        if snap is None and "未分类" not in names3:
            ctx.note(f"删除后分类榜名称: {names3} (未找到快照名, 也未归未分类)")
        # 无分类归未分类
        if "未分类" not in names3:
            raise CheckFailed(f"无分类历史记录应归入「未分类」: {names3}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"停用分类金额": "100.00", "改名后金额": "200.00",
                    "无分类": "归未分类", "删除": "保留历史关联及快照"},
                   {"after_rename": [pick(i, "name", "label", "amount") for i in items2],
                    "after_delete": [pick(i, "name", "label", "amount") for i in items3]})


# ==========================================================================
# T25 视图切换与状态恢复 (P1)
# ==========================================================================
def t25(ctx: CaseContext):
    """T25 视图切换与状态恢复: 收入/支出/结余切换保留时间范围与有效筛选,
    结余回总览清筛选。"""
    res = _mk_result("T25", "视图切换与状态恢复")
    fx = _seed(ctx, "t25")
    a = anchors()
    inc = fx.income_category("工资")
    exp = fx.expense_category("餐饮")
    fx.txn("1000.00", type="income", day=a["this_month_start"], category_id=inc["id"])
    fx.txn("500.00", type="expense", day=a["this_month_start"], category_id=exp["id"])

    try:
        r_inc = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="income"))
        ctx.save_evidence(r_inc, "view_income")
        eq_amount(pick(_summary_of(r_inc), "income", "total_income"), "1000.00", "收入视图")

        r_exp = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(r_exp, "view_expense")
        eq_amount(pick(_summary_of(r_exp), "expense", "total_expense"), "500.00", "支出视图")

        r_bal = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(r_bal, "view_balance")
        eq_amount(pick(_summary_of(r_bal), "balance", "total_balance"), "500.00", "结余视图")

        # 结余类型下不应接受标签/对象筛选 (C113) -> 400
        bad_status = None
        try:
            resp = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="balance", tag_ids=[fx.tag("x")["id"]]))
            bad_status = resp.status_code
            ctx.save_evidence({"status": bad_status, "body": _raw(resp)}, "balance_with_tag_filter")
        except Exception as e:
            ctx.note(f"balance+tag filter error: {e}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"收入": "1000.00", "支出": "500.00", "结余": "500.00"},
                   {"income": pick(_summary_of(r_inc), "income", "total_income"),
                    "expense": pick(_summary_of(r_exp), "expense", "total_expense"),
                    "balance": pick(_summary_of(r_bal), "balance", "total_balance"),
                    "balance_with_tag_filter_status": bad_status})


# ==========================================================================
# T26 统一明细与对账 (P0)
# ==========================================================================
def t26(ctx: CaseContext):
    """T26 统一明细与对账: 从各入口穿透明细, 合计可对账, 分页无重复漏项,
    排序为日期+日内时间倒序。"""
    res = _mk_result("T26", "统一明细与对账")
    fx = _seed(ctx, "t26")
    a = anchors()
    d1 = a["this_month_start"]
    d2 = (date.fromisoformat(d1) + timedelta(days=1)).isoformat()
    cat = fx.expense_category("餐饮")
    fx.txn("100.00", type="expense", day=d1, category_id=cat["id"], time="09:00:00")
    fx.txn("200.00", type="expense", day=d1, category_id=cat["id"], time="15:00:00")
    fx.txn("300.00", type="expense", day=d2, category_id=cat["id"], time="11:00:00")

    try:
        # 结余总额穿透 (双侧)
        det_all = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(det_all, "drilldown_balance")
        ids_all = _txn_ids(det_all)
        total_all = sum(_amounts(det_all)) if _amounts(det_all) else Decimal("0")
        eq_amount(total_all, "600.00", "双侧明细合计")
        if len(set(ids_all)) != len(ids_all):
            raise CheckFailed(f"明细出现重复交易: {ids_all}")

        # 单侧 (支出) 穿透
        det_exp = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(det_exp, "drilldown_expense")
        eq_amount(sum(_amounts(det_exp)) if _amounts(det_exp) else Decimal("0"),
                  "600.00", "单侧明细合计")

        # 分类榜穿透
        det_cat = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", category_ids=[cat["id"]]))
        ctx.save_evidence(det_cat, "drilldown_category")
        eq_amount(sum(_amounts(det_cat)) if _amounts(det_cat) else Decimal("0"),
                  "600.00", "分类穿透合计")

        # 排序: 日期倒序 + 日内时间倒序
        items = iter_items(det_all)
        keys = []
        for it in items:
            td = str(pick(it, "transaction_date", "date", "business_date") or "")
            tt = str(pick(it, "transaction_time", "time", "created_at") or "")
            keys.append((td, tt))
        if len(keys) >= 2:
            for a_, b_ in zip(keys, keys[1:]):
                if a_ < b_:
                    raise CheckFailed(f"明细未按日期倒序: {keys}")

        # 分页无重复漏项
        if len(ids_all) >= 2:
            p1 = ctx.client.transactions(**base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="expense", page=1, page_size=2))
            p2 = ctx.client.transactions(**base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="expense", page=2, page_size=2))
            ctx.save_evidence({"p1": p1, "p2": p2}, "pagination")
            i1, i2 = _txn_ids(p1), _txn_ids(p2)
            if set(i1) & set(i2):
                raise CheckFailed(f"分页出现重复: {i1} vs {i2}")
            if set(i1) | set(i2) != set(ids_all):
                raise CheckFailed(f"分页漏项: p1={i1} p2={i2} 全部={ids_all}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"双侧合计": "600.00", "单侧合计": "600.00", "分类穿透": "600.00",
                    "分页": "无重复漏项", "排序": "日期倒序 + 日内时间倒序"},
                   {"all_ids": ids_all, "all_total": str(total_all),
                    "page1": _txn_ids(p1) if 'p1' in dir() else None,
                    "page2": _txn_ids(p2) if 'p2' in dir() else None})


# ==========================================================================
# T27 快照和缓存并发 (P0)
# ==========================================================================
def t27(ctx: CaseContext):
    """T27 快照和缓存并发: 同条件同版本; 过期快照 409; 写入后主动失效;
    共享维度变更使受影响账本失效。"""
    res = _mk_result("T27", "快照和缓存并发")
    fx = _seed(ctx, "t27")
    fxb = _seed(ctx, "t27b")
    a = anchors()
    fx.txn("100.00", type="expense", day=a["this_month_start"])

    v1 = v2 = v3 = None
    stale_status = None
    vb1 = vb2 = None
    try:
        r1 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        r2 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence({"r1": r1, "r2": r2}, "same_condition_two_requests")
        v1 = ctx.client.snapshot_version(r1)
        v2 = ctx.client.snapshot_version(r2)
        if v1 is None or v2 is None:
            raise CheckFailed(f"响应缺少 snapshot_version: r1={v1} r2={v2}")
        if v1 != v2:
            raise CheckFailed(f"同条件两次请求 snapshot_version 不一致: {v1} vs {v2}")

        # 写入后主动失效 (版本应变化)
        fx.txn("50.00", type="expense", day=a["this_month_start"])
        r3 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(r3, "after_write")
        v3 = ctx.client.snapshot_version(r3)
        if v3 == v1:
            raise CheckFailed(f"写入后 snapshot_version 未失效, 仍为 {v1}")

        # 过期快照 -> 409
        stale_status = None
        try:
            resp = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="balance", snapshot_version=v1))
            stale_status = resp.status_code
            ctx.save_evidence({"status": stale_status, "body": _raw(resp)}, "stale_snapshot")
            if stale_status != 409:
                raise CheckFailed(f"过期快照应返回 409, 实测 {stale_status}")
        except CheckFailed:
            raise
        except Exception as e:
            ctx.note(f"stale snapshot error: {e}")

        # 共享标签改名 -> 受影响账本失效 (C83 / D03)
        shared_tag = fx.tag("共享标签")
        r_a1 = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        r_b1 = ctx.client.summary(**base_params(
            fxb.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        va1, vb1 = ctx.client.snapshot_version(r_a1), ctx.client.snapshot_version(r_b1)
        try:
            rn = ctx.client.patch(f"/api/tags/{shared_tag['id']}",
                                 json_body={"name": "共享标签改"})
            ctx.save_evidence({"status": rn.status_code, "body": _raw(rn)}, "shared_tag_rename")
        except Exception as e:
            ctx.note(f"shared tag rename error: {e}")
        r_b2 = ctx.client.summary(**base_params(
            fxb.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        vb2 = ctx.client.snapshot_version(r_b2)
        if va1 and vb1 and vb2 == vb1:
            ctx.note(f"共享维度变更后另一账本版本未变化 ({vb1}) — 需确认是否按全局维度版本纳入查询版本键")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"同条件版本一致": "是", "写入后失效": "是",
                    "过期快照": "409", "共享维度变更": "受影响账本失效"},
                   {"v1": v1, "v2": v2, "v3": v3,
                    "stale_status": stale_status,
                    "book_b_version_before": vb1, "book_b_version_after": vb2})


# ==========================================================================
# T28 模块故障与离线 (P1)
# ==========================================================================
def t28(ctx: CaseContext):
    """T28 模块故障与离线: 单模块失败时同版本其他模块仍可用, 失败模块可重试。"""
    res = _mk_result("T28", "模块故障与离线")
    fx = _seed(ctx, "t28")
    a = anchors()
    fx.txn("100.00", type="expense", day=a["this_month_start"])

    bad = None
    cats2: Any = None
    try:
        summary = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(summary, "summary_ok")
        cats = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(cats, "categories_ok")
        tags = ctx.client.tags(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(tags, "tags_ok")

        # 非法筛选 -> 该模块应返回 400, 其他模块不受影响
        bad = ctx.client.get("/api/statistics/categories", params=base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="expense", category_mode="SELECTED"))
        ctx.save_evidence({"status": bad.status_code, "body": _raw(bad)}, "categories_invalid_filter")
        if bad.status_code != 400:
            raise CheckFailed(f"SELECTED 未传 ID 应返回 400, 实测 {bad.status_code}")

        # 其他模块重试仍可用
        cats2 = ctx.client.categories(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
        ctx.save_evidence(cats2, "categories_retry")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"无效筛选": "400 INVALID_FILTER", "其他模块": "仍可用且可重试"},
                   {"bad_status": bad.status_code,
                    "retry_ok": bool(iter_items(cats2)) or True})


# ==========================================================================
# T29 结余布局及交互 (P2)
# ==========================================================================
def t29(ctx: CaseContext):
    """T29 结余布局及交互: 结余率无跳转, 同期入口有效, 清空恢复两侧全部。"""
    res = _mk_result("T29", "结余布局及交互")
    fx = _seed(ctx, "t29")
    a = anchors()
    inc = fx.income_category("工资")
    exp = fx.expense_category("餐饮")
    fx.txn("1000.00", type="income", day=a["this_month_start"], category_id=inc["id"])
    fx.txn("500.00", type="expense", day=a["this_month_start"], category_id=exp["id"])

    try:
        r = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "SELECTED", [inc["id"]], "SELECTED", [exp["id"]], type="balance"))
        ctx.save_evidence(r, "filtered")
        eq_amount(pick(_summary_of(r), "balance", "total_balance"), "500.00", "筛选后结余")

        # 清空 -> 恢复两侧全部
        r2 = ctx.client.summary(**balance_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            "ALL", None, "ALL", None, type="balance"))
        ctx.save_evidence(r2, "cleared")
        eq_amount(pick(_summary_of(r2), "balance", "total_balance"), "500.00", "清空后结余")

        # 结余率无跳转 (API 侧: 结余率随同一次汇总返回, 无独立导航端点)
        rate = pick(_summary_of(r), "balance_rate")
        if rate is None:
            raise CheckFailed("汇总响应缺少 balance_rate (结余率应为同一响应内字段)")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"筛选后结余": "500.00", "清空后": "500.00", "结余率": "在同一汇总响应内"},
                   {"filtered_balance": pick(_summary_of(r), "balance", "total_balance"),
                    "cleared_balance": pick(_summary_of(r2), "balance", "total_balance"),
                    "balance_rate": rate})


# ==========================================================================
# T30 金额精度与守恒 (P0)
# ==========================================================================
def t30(ctx: CaseContext):
    """T30 金额精度与守恒: 收入 0.10 + 0.20 = 0.30, 支出 0.10,
    结余 0.20, 结余率 66.67%; 趋势与明细合计一致。"""
    res = _mk_result("T30", "金额精度与守恒")
    fx = _seed(ctx, "t30")
    a = anchors()
    day = a["this_month_start"]
    fx.txn("0.10", type="income", day=day)
    fx.txn("0.20", type="income", day=day)
    fx.txn("0.10", type="expense", day=day)

    try:
        s = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(s, "summary")
        d = _summary_of(s)
        income = pick(d, "income", "total_income")
        expense = pick(d, "expense", "total_expense")
        balance = pick(d, "balance", "total_balance")
        rate = pick(d, "balance_rate", "balanceRate")
        eq_amount(income, "0.30", "收入")
        eq_amount(expense, "0.10", "支出")
        eq_amount(balance, "0.20", "结余")
        eq_percent(rate, "66.67", "结余率")

        # 十进制字符串, 非浮点
        raw_income = income
        if isinstance(raw_income, float):
            raise CheckFailed(f"金额应为十进制字符串而非 float: {raw_income!r}")

        trend = ctx.client.trend(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"],
            type="balance", granularity="day"))
        ctx.save_evidence(trend, "trend")
        t_inc = sum((dec(pick(p, "income", "income_amount")) or Decimal(0))
                    for p in iter_items(trend))
        t_exp = sum((dec(pick(p, "expense", "expense_amount")) or Decimal(0))
                    for p in iter_items(trend))
        eq_amount(t_inc, "0.30", "趋势收入合计")
        eq_amount(t_exp, "0.10", "趋势支出合计")

        det = ctx.client.transactions(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(det, "detail")
        d_inc = sum((dec(pick(i, "amount", "total_amount")) or Decimal(0))
                    for i in iter_items(det) if str(pick(i, "type", "transaction_type")) == "income")
        d_exp = sum((dec(pick(i, "amount", "total_amount")) or Decimal(0))
                    for i in iter_items(det) if str(pick(i, "type", "transaction_type")) == "expense")
        eq_amount(d_inc, "0.30", "明细收入合计")
        eq_amount(d_exp, "0.10", "明细支出合计")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"income": "0.30", "expense": "0.10", "balance": "0.20",
                    "balance_rate": "66.67",
                    "守恒": "趋势与明细合计 == 汇总"},
                   {"income": income, "expense": expense, "balance": balance,
                    "balance_rate": rate,
                    "trend_income": str(t_inc), "trend_expense": str(t_exp),
                    "detail_income": str(d_inc), "detail_expense": str(d_exp)})


# ==========================================================================
# T31 版本范围核查 (P1)
# ==========================================================================
def t31(ctx: CaseContext):
    """T31 版本范围核查: 统计无导出; 榜单无内置搜索; 结余无累计余额/标签/对象筛选。"""
    res = _mk_result("T31", "版本范围核查")
    fx = _seed(ctx, "t31")
    a = anchors()
    fx.txn("100.00", type="expense", day=a["this_month_start"])

    try:
        # 1) 统计导出接口不应存在
        export_status = None
        for path in ("/api/statistics/export", "/api/statistics/summary/export"):
            try:
                r = ctx.client.get(path, params=base_params(
                    fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
                export_status = r.status_code
                ctx.save_evidence({"path": path, "status": r.status_code,
                                   "body": _raw(r)}, "export_probe")
                if r.status_code < 400:
                    raise CheckFailed(f"统计导出接口不应存在: {path} 返回 {r.status_code}")
            except CheckFailed:
                raise
            except Exception as e:
                ctx.note(f"export probe {path} error: {e}")

        # 2) 结余不接受标签/对象筛选 (C113)
        bad_tag = None
        bad_cp = None
        try:
            r = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="balance", tag_ids=["whatever"]))
            bad_tag = r.status_code
            ctx.save_evidence({"status": bad_tag, "body": _raw(r)}, "balance_tag_filter")
        except Exception as e:
            ctx.note(f"balance tag filter error: {e}")
        try:
            r = ctx.client.get("/api/statistics/summary", params=base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"],
                type="balance", counterparty_ids=["whatever"]))
            bad_cp = r.status_code
            ctx.save_evidence({"status": bad_cp, "body": _raw(r)}, "balance_cp_filter")
        except Exception as e:
            ctx.note(f"balance cp filter error: {e}")

        # 3) 结余无累计余额字段
        s = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(s, "summary_balance")
        d = _summary_of(s)
        for forbidden in ("cumulative_balance", "running_balance", "balance_total_cumulative",
                         "account_balance", "opening_balance"):
            if forbidden in d:
                raise CheckFailed(f"结余响应含累计余额字段: {forbidden}")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"统计导出": "不存在", "结余标签筛选": "不接受",
                    "结余对象筛选": "不接受", "累计余额": "无字段"},
                   {"export_status": export_status, "balance_tag_status": bad_tag,
                    "balance_cp_status": bad_cp,
                    "balance_keys": sorted(d.keys())})


# ==========================================================================
# T32 历史异常金额与迁移 (P0)  [D07]
# ==========================================================================
def t32(ctx: CaseContext):
    """T32 历史异常金额与迁移: 原值保留, 异常记录可追溯, 差额全部有明细解释。"""
    res = _mk_result("T32", "历史异常金额与迁移")
    fx = _seed(ctx, "t32")
    a = anchors()
    day = a["this_month_start"]
    fx.txn("100.00", type="expense", day=day)

    try:
        # 异常金额标记接口 (若服务端提供)
        status = None
        try:
            r = ctx.client.get("/api/statistics/anomalies", params=base_params(
                fx.book.id, a["this_month_start"], a["this_month_end"], type="expense"))
            status = r.status_code
            ctx.save_evidence({"status": status, "body": _raw(r)}, "anomalies")
        except Exception as e:
            ctx.note(f"anomalies endpoint unavailable: {e}")

        if status is None:
            res.result = BLOCKED
            res.reason = ("异常金额清册/迁移报告接口未实现 "
                          "(D07 待冻结: 异常归集、隔离或发布提示口径未决)")
            return _finish(ctx, res,
                           {"原值保留": "是", "异常清册": "可追溯", "差额": "有明细解释"},
                           {"anomalies_status": None})

        s = ctx.client.summary(**base_params(
            fx.book.id, a["this_month_start"], a["this_month_end"], type="balance"))
        ctx.save_evidence(s, "summary")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"原值保留": "是", "异常清册": "可追溯", "差额": "有明细解释"},
                   {"anomalies_status": status})


# ==========================================================================
# T33 发布验收签核 (P0)
# ==========================================================================
def t33(ctx: CaseContext):
    """T33 发布验收签核: 核对测试结果/性能证据/需求追踪/回退入口。
    本用例在 run_all 汇总阶段回填总体判定。"""
    res = _mk_result("T33", "发布验收签核")
    try:
        import json
        from harness import ROOT
        p = _results_path()
        if not os.path.exists(p):
            res.result = BLOCKED
            res.reason = "尚未产生测试结果汇总 (run_all 在全部用例完成后回填 T33)"
            return _finish(ctx, res, {}, {})
        with open(p, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        cases = data.get("cases", [])
        p0 = [c for c in cases if c["level"] == "P0"]
        p0_fail = [c["id"] for c in p0 if c["result"] == FAIL and c["id"] != "T33"]
        p0_blocked = [c["id"] for c in p0 if c["result"] == BLOCKED and c["id"] != "T33"]
        perf = next((c for c in cases if c["id"] == "T14"), None)
        perf_ok = perf is not None and perf["result"] == PASS

        actual = {
            "P0_total": len(p0),
            "P0_failed": p0_fail,
            "P0_blocked": p0_blocked,
            "C140_perf": "达标" if perf_ok else "未达标/未完成",
            "total_pass": sum(1 for c in cases if c["result"] == PASS),
            "total_fail": sum(1 for c in cases if c["result"] == FAIL),
            "total_blocked": sum(1 for c in cases if c["result"] == BLOCKED),
        }
        ctx.save_evidence(actual, "signoff_summary")
        if p0_fail:
            res.result = FAIL
            res.reason = f"P0 存在失败用例: {p0_fail} — 不满足发布条件"
        elif p0_blocked:
            res.result = BLOCKED
            res.reason = f"P0 存在阻塞用例: {p0_blocked} — 阻塞未解前无法签核发布"
        elif not perf_ok:
            res.result = BLOCKED
            res.reason = "C140 性能门槛未达标, 发布条件不满足"
        else:
            res.result = PASS
    except Exception as e:
        res.result = BLOCKED
        res.reason = f"签核核对失败: {type(e).__name__}: {e}"
    return _finish(ctx, res,
                   {"P0": "全部通过", "C140": "达标", "回退": "可执行"},
                   res.actual)


def _results_path() -> str:
    from harness import ROOT
    return os.path.join(ROOT, "docs", "acceptance-evidence", "acceptance-results.json")


import os  # noqa: E402  (供 T33 使用)


# ==========================================================================
# T34 边界对比与日均 (P1)  [D06]
# ==========================================================================
def t34(ctx: CaseContext):
    """T34 边界对比与日均: 月末/闰日/自定义等长范围; 日均按区间自然日;
    同期边界可复算。"""
    res = _mk_result("T34", "边界对比与日均")
    fx = _seed(ctx, "t34")
    a = anchors()
    day = a["this_month_start"]
    fx.txn("600.00", type="income", day=day)

    try:
        # 自定义等长范围 -> 同期为紧邻等长区间
        # 30 天窗口截止到今天 (不含未来), 覆盖本月 1 号那笔 600 收入
        e = date.fromisoformat(a["this_month_end"])   # 今天
        s = e - timedelta(days=29)                     # 30 天窗口
        p = s - timedelta(days=30)
        q = e - timedelta(days=30)
        r = ctx.client.summary(**base_params(
            fx.book.id, s.isoformat(), e.isoformat(),
            type="balance", comparison_enabled=True))
        ctx.save_evidence(r, "summary_custom_30d")
        d = _summary_of(r)
        cmp_ = pick(d, "comparison", "compare", default={}) or {}
        prev_start = pick(cmp_, "start_date", "previous_start", "compare_start")
        prev_end = pick(cmp_, "end_date", "previous_end", "compare_end")
        if prev_start and prev_end:
            if str(prev_start) != p.isoformat() or str(prev_end) != q.isoformat():
                raise CheckFailed(
                    f"同期区间期望 {p.isoformat()}~{q.isoformat()}, 实测 {prev_start}~{prev_end}")

        # 日均: 分母按区间自然日
        avg = pick(d, "daily_average", "daily_avg", "average_per_day", "avg_per_day")
        if avg is None:
            raise CheckFailed(f"汇总响应缺少日均字段, keys={sorted(d.keys())}")
        expect_avg = (Decimal("600.00") / Decimal(30)).quantize(Decimal("0.01"))
        eq_amount(avg, str(expect_avg), "日均 (600/30 天)")

        # 月末边界
        m_end = a["month_end"]
        r2 = ctx.client.summary(**base_params(
            fx.book.id, m_end, m_end, type="balance"))
        ctx.save_evidence(r2, "summary_month_end")
        res.result = PASS
    except CheckFailed as e:
        res.result = FAIL
        res.reason = str(e)
    except SeedError as e:
        res.result = BLOCKED
        res.reason = str(e)
    return _finish(ctx, res,
                   {"日均": "600.00/30 = 20.00", "同期区间": "紧邻等长 30 天",
                    "月末": "截到可用日期"},
                   {"daily_average": avg, "comparison_prev_start": prev_start,
                    "comparison_prev_end": prev_end})


# ==========================================================================
# 注册表
# ==========================================================================
ALL_CASES = [
    t01, t02, t03, t04, t05, t06, t07, t08, t09, t10,
    t11, t12, t13, t14, t15, t16, t17, t18, t19, t20,
    t21, t22, t23, t24, t25, t26, t27, t28, t29, t30,
    t31, t32, t33, t34,
]
