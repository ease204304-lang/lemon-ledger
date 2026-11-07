# -*- coding: utf-8 -*-
"""
验收报告生成器: 把 run_all.py 的执行结果渲染为
docs/验收测试报告-v1.11.0.md
"""
from __future__ import annotations

import json
import os
from datetime import datetime
from typing import Any, Dict, List

from harness import ROOT, BLOCKED, FAIL, PASS, TEST_LEVELS, P0_CASES, D_RULE_CASES

REPORT_PATH = os.path.join(ROOT, "docs", "验收测试报告-v1.11.0.md")
PERF_DIR = os.path.join(ROOT, "docs", "acceptance-evidence", "performance")

D_RULE_TEXT = {
    "D02": "D02 删除分类：指定项全失效时恢复该侧全部并提示，保留历史金额和可穿透历史桶",
    "D05": "D05 对象合并：高置信自动合并，低置信需人工确认；合并迁移前留来源映射，按账本校验收支与笔数",
    "D06": "D06 周期边界：周一为周起点；月末/闰日截到可用日期；日均按区间自然日；榜单用稳定并列键；百分比约定舍入",
    "D07": "D07 异常金额：保留原值和来源，迁移输出异常清册及差额",
}


def _fmt(v: Any, limit: int = 200) -> str:
    if v is None:
        return "—"
    try:
        s = json.dumps(v, ensure_ascii=False, default=str)
    except Exception:
        s = str(v)
    s = s.replace("|", "\\|").replace("\n", " ")
    return s if len(s) <= limit else s[:limit] + "…"


def _load_perf() -> Dict[str, Any]:
    p = os.path.join(PERF_DIR, "perf-report.json")
    if not os.path.exists(p):
        return {}
    try:
        with open(p, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {}


def write_report(payload: Dict[str, Any], path: str = REPORT_PATH) -> str:
    meta = payload.get("meta", {})
    summary = payload.get("summary", {})
    cases: List[Dict[str, Any]] = payload.get("cases", [])
    perf = _load_perf()

    by_id = {c["id"]: c for c in cases}
    L: List[str] = []
    A = L.append

    # ---------------- 封面 ----------------
    A("# 记账统计模块 验收测试报告")
    A("")
    A(f"**版本**: v1.11.0　|　**执行时间**: {meta.get('started_at')} ~ "
      f"{meta.get('finished_at')}　|　**被测服务**: `{meta.get('base_url')}`")
    A("")
    A("**用例来源**: 《测试与验收清单》T01–T34 及「性能验收」sheet "
      "(`D:\\07.DevWorkspace\\sys\\testlist.txt`)　|　"
      "**需求依据**: PRD v0.9 / TECH v0.9 / 需求决策追踪表 v0.9")
    A("")
    A("---")
    A("")

    # ---------------- 执行摘要 ----------------
    A("## 1. 执行摘要")
    A("")
    A("| 指标 | 数值 |")
    A("|---|---|")
    A(f"| 用例总数 | {summary.get('total', 0)} |")
    A(f"| 通过 PASS | {summary.get('pass', 0)} |")
    A(f"| 失败 FAIL | {summary.get('fail', 0)} |")
    A(f"| 阻塞 BLOCKED | {summary.get('blocked', 0)} |")
    A(f"| P0 用例数 | {summary.get('p0_total', 0)} |")
    A(f"| P0 通过 | {summary.get('p0_pass', 0)} |")
    A(f"| P0 失败 | {', '.join(summary.get('p0_fail') or []) or '无'} |")
    A(f"| P0 阻塞 | {', '.join(summary.get('p0_blocked') or []) or '无'} |")
    A(f"| C140 性能门槛 | {_perf_verdict(summary)} |")
    A("")
    A(_verdict_block(summary, perf))
    A("")
    A("---")
    A("")

    # ---------------- 逐用例结果 ----------------
    A("## 2. 逐用例结果")
    A("")
    A("| 用例 | 级别 | 场景 | 结果 | 实测值 | 预期值 | 差异/阻塞原因 | 证据 |")
    A("|---|---|---|---|---|---|---|---|")
    for c in cases:
        ev = "<br>".join(f"`{e}`" for e in c.get("evidence", [])[:5]) or "—"
        note = c.get("reason") or ""
        if c.get("d_rule"):
            tag = f"（{c['d_rule']} 按 PRD v0.9 建议口径，待最终确认）"
            note = (note + " " + tag).strip()
        A(f"| {c['id']} | {c['level']} | {c['name']} | **{c['result']}** | "
          f"{_fmt(c.get('actual'))} | {_fmt(c.get('expected'))} | {note} | {ev} |")
    A("")
    A("---")
    A("")

    # ---------------- P0 门槛 ----------------
    A("## 3. P0 功能门槛判定")
    A("")
    A("门槛定义（《测试与验收清单》验收说明 R5）：金额正确、组合筛选、快照一致、"
      "账本隔离、明细穿透正确，**全部通过后才发布**。")
    A("")
    p0 = [c for c in cases if c["level"] == "P0"]
    A("| P0 用例 | 场景 | 结果 | 说明 |")
    A("|---|---|---|---|")
    for c in p0:
        A(f"| {c['id']} | {c['name']} | **{c['result']}** | "
          f"{c.get('reason') or '符合预期'} |")
    A("")
    p0_fail = [c["id"] for c in p0 if c["result"] == FAIL]
    p0_block = [c["id"] for c in p0 if c["result"] == BLOCKED]
    if p0_fail:
        A(f"**判定: ❌ 未通过** —— P0 失败用例 {', '.join(p0_fail)}。")
    elif p0_block:
        A(f"**判定: ⚠️ 暂不可判定（存在阻塞）** —— P0 阻塞用例 "
          f"{', '.join(p0_block)}，阻塞未解除前不满足发布条件。")
    else:
        A("**判定: ✅ 全部通过** —— P0 功能门槛满足。")
    A("")
    A("---")
    A("")

    # ---------------- 性能 ----------------
    A("## 4. C140 性能门槛")
    A("")
    A("门槛（《技术实施说明书》/ PRD §07）：5 万笔下金额汇总 P95 ≤ 2s、趋势 ≤ 3s、"
      "分类/标签/交易对象各 ≤ 5s，冷/热缓存分层记录，不混算。")
    A("")
    if not perf:
        A("**未产生性能数据** —— 基准数据集与采样报告缺失"
          "（`docs/acceptance-evidence/performance/`）。")
    else:
        pm = perf.get("meta", {})
        A(f"- 数据集: {pm.get('dataset_n')} 笔，跨度 {pm.get('dataset_spec', {}).get('start')}"
          f" ~ {pm.get('dataset_spec', {}).get('end')}，种子 {pm.get('dataset_spec', {}).get('seed')}")
        A(f"- 采样: 每模块每层 {pm.get('hot_samples_per_module')} 次，"
          f"部署 `{pm.get('deploy')}`，设备 {pm.get('device')}，网络 {pm.get('network')}")
        A(f"- 对账: {'一致' if perf.get('reconciliation', {}).get('pass') else '不一致'}"
          f"（参考 income={perf.get('reference', {}).get('income')}, "
          f"expense={perf.get('reference', {}).get('expense')}, "
          f"count={perf.get('reference', {}).get('count')}）")
        A("")
        A("| 模块 | 场景 | 冷缓存 P95 | 热缓存 P95 | 冷均值 | 热均值 | 门槛 | 判定 |")
        A("|---|---|---|---|---|---|---|---|")
        for m in perf.get("modules", []):
            cold = m.get("cold") or {}
            hot = m.get("hot") or {}
            lim = m.get("p95_limit")
            ok = "✅" if m.get("pass") else "❌"
            A(f"| {m['module']} | {m.get('scenario', '')} | "
              f"{cold.get('p95', '—')} s | {hot.get('p95', '—')} s | "
              f"{cold.get('mean', '—')} s | {hot.get('mean', '—')} s | "
              f"≤ {lim} s | {ok} |")
        A("")
        fails = perf.get("failures") or []
        if fails:
            A("**性能门槛未达标:**")
            for f in fails:
                A(f"- {f}")
        else:
            A("**性能门槛达标** —— 各模块冷/热缓存分层 P95 均满足 C140 目标。")
    A("")
    A("---")
    A("")

    # ---------------- 阻塞项 ----------------
    A("## 5. 阻塞项与原因")
    A("")
    blocked = [c for c in cases if c["result"] == BLOCKED]
    if not blocked:
        A("无阻塞用例。")
    else:
        A("| 用例 | 级别 | 阻塞原因 | 类别 |")
        A("|---|---|---|---|")
        for c in blocked:
            A(f"| {c['id']} | {c['level']} | {c.get('reason') or '—'} | "
              f"{_block_category(c.get('reason', ''))} |")
    A("")
    A("---")
    A("")

    # ---------------- 未决规则 ----------------
    A("## 6. 未决规则标注 (D01–D08)")
    A("")
    A("本次执行按 **PRD v0.9 建议口径** 执行（用户已确认）。以下用例受未决规则影响，"
      "结果待最终评审冻结后复验。")
    A("")
    A("| 未决事项 | 建议口径 | 影响用例 |")
    A("|---|---|---|")
    for rule, text in D_RULE_TEXT.items():
        affected = sorted({c["id"] for c in cases if c.get("d_rule") == rule})
        A(f"| **{rule}** | {text} | {', '.join(affected) or '—'} |")
    A("")
    A("---")
    A("")

    # ---------------- 结论 ----------------
    A("## 7. 验收结论")
    A("")
    A(_conclusion(summary, perf, cases))
    A("")
    A("---")
    A("")
    A("### 附: 证据索引")
    A("")
    A(f"- 汇总 JSON: `docs/acceptance-evidence/acceptance-results.json`")
    A(f"- 汇总 Markdown: `docs/acceptance-evidence/acceptance-results.md`")
    A(f"- 逐用例证据: `docs/acceptance-evidence/<用例号>/*.json`")
    A(f"- 性能报告: `docs/acceptance-evidence/performance/perf-report.json`")
    A(f"- 性能基准集: `docs/acceptance-evidence/performance/dataset.json`")
    A(f"- 截图证据: `docs/screenshots/acceptance/`")
    A("")

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(L))
    return path


def _perf_verdict(summary: Dict[str, Any]) -> str:
    p = summary.get("c140_perf", {})
    return {"PASS": "✅ 达标", "FAIL": "❌ 未达标",
            "BLOCKED": "⚠️ 未完成/阻塞"}.get(p.get("result"), "未知")


def _verdict_block(summary: Dict[str, Any], perf: Dict[str, Any]) -> str:
    p0_ok = summary.get("p0_gate_pass")
    perf_ok = summary.get("c140_perf", {}).get("pass")
    if p0_ok and perf_ok:
        return ("> **发布判定: ✅ 可发布** —— P0 功能门槛全部通过，C140 性能门槛达标。")
    reasons = []
    if not p0_ok:
        if summary.get("p0_fail"):
            reasons.append("P0 存在失败用例 " + ", ".join(summary["p0_fail"]))
        if summary.get("p0_blocked"):
            reasons.append("P0 存在阻塞用例 " + ", ".join(summary["p0_blocked"]))
    if not perf_ok:
        reasons.append("C140 性能门槛未达标")
    return ("> **发布判定: ❌ 暂不可发布** —— " + "；".join(reasons) + "。")


def _block_category(reason: str) -> str:
    r = reason or ""
    if "未实现" in r or "未就绪" in r or "不可用" in r:
        return "缺特性"
    if "环境" in r or "服务" in r or "连接" in r:
        return "需环境"
    if "待冻结" in r or "未决" in r or "未实现" in r:
        return "依赖未冻结"
    return "其他"


def _conclusion(summary: Dict[str, Any], perf: Dict[str, Any],
                cases: List[Dict[str, Any]]) -> str:
    lines: List[str] = []
    p0_ok = summary.get("p0_gate_pass")
    perf_ok = summary.get("c140_perf", {}).get("pass")
    fails = [c["id"] for c in cases if c["result"] == FAIL]
    blocks = [c["id"] for c in cases if c["result"] == BLOCKED]

    lines.append("| 门槛项 | 判定 | 依据 |")
    lines.append("|---|---|---|")
    lines.append(f"| P0 功能门槛（{summary.get('p0_total', 0)} 条） | "
                 f"{'✅ 通过' if p0_ok else '❌ 未通过'} | "
                 f"失败 {', '.join(summary.get('p0_fail') or []) or '无'}；"
                 f"阻塞 {', '.join(summary.get('p0_blocked') or []) or '无'} |")
    lines.append(f"| C140 性能门槛 | {'✅ 达标' if perf_ok else '❌ 未达标'} | "
                 f"5 万笔分层 P95，见第 4 节 |")
    lines.append(f"| P1/P2 | {'全部通过' if not fails and not blocks else '需评审/记录处置'} | "
                 f"失败 {len(fails)} 条，阻塞 {len(blocks)} 条 |")
    lines.append(f"| 回退可执行性 (T33) | "
                 f"{'✅ 已验证' if by_res(cases, 'T33') == PASS else '⚠️ 未通过/待验证'} | "
                 f"发布回退入口 |")
    lines.append("")
    if p0_ok and perf_ok:
        lines.append("**结论：满足发布条件。** P0 功能门槛全部通过，C140 性能门槛达标，"
                     "建议进入发布签核流程。")
    else:
        parts = []
        if not p0_ok:
            parts.append("P0 功能门槛未全部通过（"
                         + ("存在失败: " + ", ".join(summary.get("p0_fail") or []) if summary.get("p0_fail") else "")
                         + ("；" if summary.get("p0_fail") and summary.get("p0_blocked") else "")
                         + ("存在阻塞: " + ", ".join(summary.get("p0_blocked") or []) if summary.get("p0_blocked") else "")
                         + "）")
        if not perf_ok:
            parts.append("C140 性能门槛未达标")
        lines.append("**结论：暂不满足发布条件。** " + "；".join(parts)
                     + "。需先修复失败项并解除阻塞，再复验并签核。")
    return "\n".join(lines)


def by_res(cases: List[Dict[str, Any]], cid: str) -> str:
    for c in cases:
        if c["id"] == cid:
            return c["result"]
    return BLOCKED


if __name__ == "__main__":
    import sys
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, "docs", "acceptance-evidence", "acceptance-results.json")
    with open(src, "r", encoding="utf-8") as fh:
        p = json.load(fh)
    print(write_report(p))
