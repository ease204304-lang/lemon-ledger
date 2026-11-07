/// 结余视图 (v1.11.0 W3 — PRD 05 结余视图)
///
/// 页面顺序 (PRD 05):
///   1. 日期及分类筛选
///   2. 结余总览 (结余 + 结余率)
///   3. 结余趋势 (周期净结余)
///   4. 收入贡献榜
///   5. 支出影响榜
///   6. 明细入口
///
/// 颜色规则: 收入用绿色, 支出用橙色, 结余按正负单列。
/// 负结余用负数金额和「本期支出高于收入」提示。
library;

import 'package:flutter/material.dart';

import '../../services/stats_controller.dart';
import '../../theme/tokens.dart';
import 'stats_widgets.dart';

/// 结余总览卡 (结余 + 结余率 + 收入/支出明细)
class BalanceOverviewCard extends StatelessWidget {
  final StatsSummary? summary;
  final VoidCallback? onTapIncome;
  final VoidCallback? onTapExpense;
  final VoidCallback? onTapBalanceRate;
  final VoidCallback? onTapCompareBalance;

  const BalanceOverviewCard({
    super.key,
    this.summary,
    this.onTapIncome,
    this.onTapExpense,
    this.onTapBalanceRate,
    this.onTapCompareBalance,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();

    // 结余正负 → 颜色单列 (PRD 05)
    final bal = _toDouble(s.balance);
    final balColor = bal < 0 ? L.warnRed : L.textPrimary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 结余主数
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('结余', style: TextStyle(fontSize: 13, color: L.textSecondary)),
              const Spacer(),
              // 结余率 — 点击保持当前页面 (PRD 05 R5)
              InkWell(
                onTap: onTapBalanceRate,
                child: Row(
                  children: [
                    const Text('结余率 ', style: TextStyle(fontSize: 12, color: L.textSecondary)),
                    Text(
                      // 收入为 0 → 显示「—」 (PRD 02)
                      s.balanceRate == null ? '—' : '${s.balanceRate}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: s.balanceRate == null ? L.textTertiary : balColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            // 点结余金额 → 查看当前组合范围内的收入及支出 (PRD 05 R1)
            onTap: () {},
            child: Text(
              _fmt(s.balance),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: balColor,
              ),
            ),
          ),
          // 负结余提示
          if (bal < 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '本期支出高于收入',
                style: TextStyle(fontSize: 12, color: L.warnRed),
              ),
            ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: L.dividerLight),
          const SizedBox(height: 12),
          // 收入 / 支出 两侧 — 点金额进入对应类型明细 (PRD 05 R2)
          Row(
            children: [
              Expanded(
                child: _SideStat(
                  label: '收入',
                  amount: s.income,
                  color: L.okGreen,
                  count: s.incomeCount,
                  onTap: onTapIncome,
                ),
              ),
              Container(width: 1, height: 32, color: L.dividerLight),
              Expanded(
                child: _SideStat(
                  label: '支出',
                  amount: s.expense,
                  color: _expenseOrange,
                  count: s.expenseCount,
                  onTap: onTapExpense,
                ),
              ),
            ],
          ),
          // 同期对比
          if (s.compareBalance != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: L.dividerLight),
            const SizedBox(height: 10),
            InkWell(
              // 点同期结余 → 查看同期对比数据 (PRD 05 R6)
              onTap: onTapCompareBalance,
              child: Row(
                children: [
                  const Text('同期结余', style: TextStyle(fontSize: 12, color: L.textSecondary)),
                  const SizedBox(width: 6),
                  Text(s.compareBalance!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (s.balanceDiff != null) ...[
                    const Text('差额 ', style: TextStyle(fontSize: 12, color: L.textSecondary)),
                    Text(
                      s.balanceDiff!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _toDouble(s.balanceDiff!) < 0 ? L.warnRed : L.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 同期结余 ≤ 0 → 变化率显示「—」 (PRD 03)
                    Text(
                      s.balanceChangeRate == null ? '变化率 —' : '变化率 ${s.balanceChangeRate}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: s.balanceChangeRate == null ? L.textTertiary : L.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 收入/支出 单侧统计 (PRD 05: 两个收支指标使用独立进度条)
class _SideStat extends StatelessWidget {
  final String label;
  final String amount;
  final String count;
  final Color color;
  final int countValue;
  final VoidCallback? onTap;

  const _SideStat({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
    required this.countValue,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: L.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
            ),
            Text('$countValue 笔', style: const TextStyle(fontSize: 11, color: L.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// 支出影响 / 收入贡献 单榜 (PRD 05: 各自计算, 默认 Top 5, 可展开, 隐藏零金额项)
class BalanceSideRanking extends StatelessWidget {
  final String title;
  final Color color;
  final List<RankItem> items;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final ValueChanged<RankItem>? onTapItem;

  const BalanceSideRanking({
    super.key,
    required this.title,
    required this.color,
    required this.items,
    required this.expanded,
    this.onToggleExpand,
    this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    // 隐藏零金额项 (PRD 05)
    final visible = items.where((e) => _toDouble(e.amount) != 0).toList();
    final shown = expanded ? visible : visible.take(5).toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (visible.length > 5)
                InkWell(
                  onTap: onToggleExpand,
                  child: Text(
                    expanded ? '收起' : '展开全部',
                    style: const TextStyle(fontSize: 12, color: L.textSecondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 12, color: L.textTertiary)),
              ),
            )
          else
            for (final it in shown)
              RankRow(item: it, barColor: color, onTap: onTapItem == null ? null : () => onTapItem!(it)),
        ],
      ),
    );
  }
}

/// 支出橙色 (PRD 05)
const Color _expenseOrange = Color(0xFFFF8A4A);
