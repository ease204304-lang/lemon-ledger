# -*- coding: utf-8 -*-
"""
小猪记账 — 记账统计模块 验收测试执行器

用法:
    python run_all.py                       # 执行全部 T01–T34
    python run_all.py --only T01,T06,T30    # 只跑指定用例
    python run_all.py --base-url http://127.0.0.1:8000
    python run_all.py --skip-perf           # 跳过 T14 性能用例
    python run_all.py --json-only           # 只输出 JSON

输出:
    docs/acceptance-evidence/acceptance-results.json
    docs/acceptance-evidence/acceptance-results.md
    docs/验收测试报告-v1.11.0.md   (--write-report 时生成)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import traceback
from datetime import datetime
from typing import Any, Dict, List

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Windows 控制台默认 GBK, 强制 UTF-8 输出避免中文乱码
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from harness import (ApiClient, CaseContext, EVIDENCE_DIR, ROOT, BLOCKED, FAIL,
                     PASS, TEST_LEVELS, P0_CASES, D_RULE_CASES, TestResult)
import test_cases

CASES_BY_ID = {fn.__name__: fn for fn in test_cases.ALL_CASES}

# 用例中文名 (来自《测试与验收清单》)
CASE_NAMES = {
    "T01": "正结余", "T02": "负结余", "T03": "零结余", "T04": "无收入有支出",
    "T05": "无交易与零点", "T06": "四种组合筛选", "T07": "父子去重",
    "T08": "编辑交易同步", "T09": "删除交易同步", "T10": "结余同期变化率",
    "T11": "负趋势点穿透", "T12": "账本隔离与切换", "T13": "部分空值与未完周期",
    "T14": "5 万笔性能", "T15": "主辅标签与多标签去重", "T16": "标签图榜与榜单展开",
    "T17": "交易对象展示及入口", "T18": "对象合并及拆分", "T19": "退款与金额校验",
    "T20": "日期选择和比较", "T21": "零点与时区", "T22": "分类详情与排行",
    "T23": "历史标签保留", "T24": "历史分类兼容", "T25": "视图切换与状态恢复",
    "T26": "统一明细与对账", "T27": "快照和缓存并发", "T28": "模块故障与离线",
    "T29": "结余布局及交互", "T30": "金额精度与守恒", "T31": "版本范围核查",
    "T32": "历史异常金额与迁移", "T33": "发布验收签核", "T34": "边界对比与日均",
}


# --------------------------------------------------------------------------
def wait_for_server(client: ApiClient, timeout: int = 60) -> bool:
    t0 = time.time()
    print(f"[等待] 服务端 {client.base_url} …", flush=True)
    while time.time() - t0 < timeout:
        try:
            r = client._client.get("/openapi.json", timeout=3)
            if r.status_code < 500:
                print(f"[就绪] 服务端可用 ({time.time() - t0:.1f}s)", flush=True)
                return True
        except Exception:
            pass
        try:
            r = client._client.get("/docs", timeout=3)
            if r.status_code < 500:
                print(f"[就绪] 服务端可用 ({time.time() - t0:.1f}s)", flush=True)
                return True
        except Exception:
            pass
        time.sleep(1.0)
    print(f"[超时] 服务端在 {timeout}s 内未就绪", flush=True)
    return False


def run_case(fn, client: ApiClient) -> TestResult:
    cid = fn.__name__
    name = CASE_NAMES.get(cid, cid)
    ctx = CaseContext(client=client, case_id=cid, name=name)
    try:
        res = fn(ctx)
    except Exception as e:
        res = TestResult(id=cid, level=TEST_LEVELS.get(cid, "P?"), name=name)
        res.result = BLOCKED
        res.reason = f"执行异常 {type(e).__name__}: {e}"
        res.evidence = list(ctx.evidence)
        res.duration_ms = ctx.elapsed_ms
        res.actual = {"traceback": traceback.format_exc()[-2000:]}
        res.expected = {}
    res.evidence = list(dict.fromkeys(res.evidence + ctx.evidence))
    return res


def summarize(results: List[TestResult]) -> Dict[str, Any]:
    def cnt(r: str) -> int:
        return sum(1 for x in results if x.result == r)
    p0 = [x for x in results if x.level == "P0"]
    p0_pass = sum(1 for x in p0 if x.result == PASS)
    p0_fail = [x.id for x in p0 if x.result == FAIL]
    p0_blocked = [x.id for x in p0 if x.result == BLOCKED]
    perf = next((x for x in results if x.id == "T14"), None)
    return {
        "total": len(results),
        "pass": cnt(PASS),
        "fail": cnt(FAIL),
        "blocked": cnt(BLOCKED),
        "p0_total": len(p0),
        "p0_pass": p0_pass,
        "p0_fail": p0_fail,
        "p0_blocked": p0_blocked,
        "p0_gate_pass": (not p0_fail) and (not p0_blocked) and len(p0) > 0,
        "c140_perf": {
            "result": perf.result if perf else BLOCKED,
            "pass": bool(perf and perf.result == PASS),
        },
    }


def to_markdown(results: List[TestResult], summary: Dict[str, Any],
                meta: Dict[str, Any]) -> str:
    L: List[str] = []
    L.append("# 记账统计模块 验收测试执行结果 (明细)")
    L.append("")
    L.append(f"- 执行时间: {meta['started_at']} ~ {meta['finished_at']}")
    L.append(f"- 服务端: `{meta['base_url']}`")
    L.append(f"- 用例数: {summary['total']} | 通过 {summary['pass']} | "
             f"失败 {summary['fail']} | 阻塞 {summary['blocked']}")
    L.append(f"- P0 门槛: {summary['p0_pass']}/{summary['p0_total']} 通过 "
             f"| 失败 {summary['p0_fail'] or '无'} | 阻塞 {summary['p0_blocked'] or '无'}")
    L.append(f"- C140 性能: {summary['c140_perf']['result']}")
    L.append("")
    L.append("## 逐用例结果")
    L.append("")
    L.append("| 用例 | 级别 | 名称 | 结果 | 实测值 | 预期值 | 证据 | 说明 |")
    L.append("|---|---|---|---|---|---|---|---|")
    for r in results:
        actual = _fmt(r.actual)
        expected = _fmt(r.expected)
        ev = "<br>".join(r.evidence[:6]) if r.evidence else "-"
        note = r.reason or ""
        if r.d_rule:
            note = (note + " " if note else "") + f"（{r.d_rule}：按 PRD v0.9 建议口径，待最终确认）"
        L.append(f"| {r.id} | {r.level} | {r.name} | **{r.result}** | "
                 f"{actual} | {expected} | {ev} | {note} |")
    L.append("")
    return "\n".join(L)


def _fmt(v: Any, limit: int = 220) -> str:
    if v is None:
        return "-"
    try:
        s = json.dumps(v, ensure_ascii=False, default=str)
    except Exception:
        s = str(v)
    s = s.replace("|", "\\|").replace("\n", " ")
    if len(s) > limit:
        s = s[:limit] + "…"
    return s


# --------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description="记账统计模块验收测试执行器")
    ap.add_argument("--base-url", default=os.environ.get(
        "ACCOUNT_API_BASE", "http://127.0.0.1:8000"))
    ap.add_argument("--only", default="", help="逗号分隔的用例 ID, 如 T01,T06")
    ap.add_argument("--skip-perf", action="store_true", help="跳过 T14")
    ap.add_argument("--json-only", action="store_true")
    ap.add_argument("--wait", type=int, default=60, help="等待服务端就绪秒数")
    ap.add_argument("--write-report", action="store_true",
                    help="生成 docs/验收测试报告-v1.11.0.md")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    started_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    os.makedirs(EVIDENCE_DIR, exist_ok=True)

    only = [x.strip().upper() for x in args.only.split(",") if x.strip()]

    client = ApiClient(args.base_url)
    server_up = wait_for_server(client, args.wait)

    selected = [fn for cid, fn in CASES_BY_ID.items()
                if not only or cid in only]
    if args.skip_perf:
        selected = [fn for fn in selected if fn.__name__ != "t14"]
    # 保证 ID 顺序
    selected.sort(key=lambda f: f.__name__)

    results: List[TestResult] = []
    if not server_up:
        for fn in selected:
            r = TestResult(id=fn.__name__, level=TEST_LEVELS.get(fn.__name__, "P?"),
                           name=CASE_NAMES.get(fn.__name__, fn.__name__))
            r.result = BLOCKED
            r.reason = (f"服务端未就绪 ({args.base_url}), 无法执行 HTTP 验收; "
                        f"需先启动 server/ 服务")
            r.expected = {}
            r.actual = None
            results.append(r)
    else:
        for fn in selected:
            cid = fn.__name__
            print(f"[运行] {cid} {CASE_NAMES.get(cid, '')} …", flush=True)
            r = run_case(fn, client)
            results.append(r)
            print(f"       -> {r.result} ({r.duration_ms:.0f}ms)"
                  + (f" | {r.reason}" if r.reason else ""), flush=True)

    client.close()

    finished_at = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    os.makedirs(EVIDENCE_DIR, exist_ok=True)
    json_path = os.path.join(EVIDENCE_DIR, "acceptance-results.json")

    def _meta() -> Dict[str, Any]:
        return {
            "started_at": started_at, "finished_at": finished_at,
            "base_url": args.base_url, "server_up": server_up,
            "suite": "记账统计模块 T01–T34 验收测试",
            "spec": "D:\\07.DevWorkspace\\sys\\testlist.txt (T01–T34, 性能验收 sheet)",
        }

    # 先落盘中间结果 (T01–T34 已跑完, 但 T33 尚未回填) —
    # 这样 T33 回填时读到的是本轮最新结果, 而非上一轮的旧文件。
    _intermediate = {
        "meta": _meta(),
        "summary": summarize(results),
        "cases": [r.to_dict() for r in results],
    }
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(_intermediate, fh, ensure_ascii=False, indent=2, default=str)

    # T33 依赖汇总结果, 故在全部用例跑完后重跑一次 (此时读最新中间结果)
    t33 = CASES_BY_ID.get("t33")
    if t33 and server_up and (not only or "T33" in only):
        print("[回填] T33 发布验收签核 …", flush=True)
        r = run_case(t33, client)
        # 替换原位置
        results = [r if x.id == "T33" else x for x in results]
        print(f"       -> {r.result}" + (f" | {r.reason}" if r.reason else ""), flush=True)

    summary = summarize(results)
    payload = {
        "meta": _meta(),
        "summary": summary,
        "cases": [r.to_dict() for r in results],
    }
    with open(json_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2, default=str)
    md = to_markdown(results, summary, meta)
    md_path = os.path.join(EVIDENCE_DIR, "acceptance-results.md")
    with open(md_path, "w", encoding="utf-8") as fh:
        fh.write(md)

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2, default=str)

    print("")
    print("=" * 64)
    print(f"总计 {summary['total']} | 通过 {summary['pass']} | "
          f"失败 {summary['fail']} | 阻塞 {summary['blocked']}")
    print(f"P0 门槛: {summary['p0_pass']}/{summary['p0_total']} 通过  "
          f"失败={summary['p0_fail'] or '无'} 阻塞={summary['p0_blocked'] or '无'}  "
          f"-> {'通过' if summary['p0_gate_pass'] else '未通过'}")
    print(f"C140 性能: {summary['c140_perf']['result']}")
    print("=" * 64)
    print(f"JSON: {json_path}")
    print(f"MD  : {md_path}")

    if args.write_report:
        import report_writer
        p = report_writer.write_report(payload)
        print(f"报告: {p}")

    if not args.json_only:
        print("")
        print(md)

    return 0 if summary["fail"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
