/// 首页日分组: 头部 (日期 + 折叠) + 流水列表
library;

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../utils/date_utils.dart';
import 'category_icon.dart';

/// 单日头部: 日期 + 星期 + 收入/支出汇总 (可折叠)
class HomeDayHeader extends StatelessWidget {
  final int day;
  final List<Tx> txs;
  final bool collapsed;
  final bool showAmount;
  final bool highlight;
  final GlobalKey? dayKey;
  final VoidCallback onToggle;
  const HomeDayHeader({
    super.key,
    required this.day,
    required this.txs,
    required this.collapsed,
    required this.showAmount,
    this.highlight = false,
    this.dayKey,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final dt = epochDayToDate(day);
    final today = todayEpochDay();
    final isToday = day == today;
    final weekday = [
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日'
    ][dt.weekday - 1];
    final inc = txs
        .where((t) => t.type == TxType.income)
        .fold<int>(0, (s, t) => s + t.amountCents);
    final exp = txs
        .where((t) => t.type == TxType.expense)
        .fold<int>(0, (s, t) => s + t.amountCents);
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        key: dayKey,
        decoration: highlight
            ? BoxDecoration(
                color: L.brandYellow.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: L.brandYellow,
                  width: 2,
                ),
              )
            : null,
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: L.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              isToday ? '今天' : '${dt.month}月${dt.day}日',
              style: const TextStyle(
                  color: L.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(weekday,
                style:
                    const TextStyle(color: L.textTertiary, fontSize: 12)),
            const SizedBox(width: 8),
            // 右侧金额: 占用剩余空间, 必要时缩字
            Expanded(
              child: Text(
                _summaryRight(inc, exp, hidden: !showAmount),
                textAlign: TextAlign.right,
                style: const TextStyle(color: L.textTertiary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单日流水分组 (白色卡片 + divider 分割)
class HomeDayGroup extends StatelessWidget {
  final List<Tx> txs;
  final Map<String, Category> cats;
  final bool showAmount;
  final ValueChanged<Tx> onTap;
  const HomeDayGroup({
    super.key,
    required this.txs,
    required this.cats,
    required this.showAmount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        children: [
          for (var i = 0; i < txs.length; i++) ...[
            _DayTxRow(
              tx: txs[i],
              cat: cats[txs[i].categoryId],
              showAmount: showAmount,
              onTap: () => onTap(txs[i]),
            ),
            if (i != txs.length - 1)
              const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: L.dividerLight,
                  indent: 64,
                  endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _DayTxRow extends StatelessWidget {
  final Tx tx;
  final Category? cat;
  final bool showAmount;
  final VoidCallback onTap;
  const _DayTxRow({
    required this.tx,
    required this.cat,
    required this.showAmount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(
          children: [
            CategoryIcon(iconKey: cat?.iconKey ?? 'else'),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // 标题规则: 备注优先, 缺则分类名
                tx.note.isNotEmpty
                    ? tx.note
                    : (cat?.name ?? '未分类'),
                style: const TextStyle(
                    fontSize: 15,
                    color: L.textPrimary,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              showAmount
                  ? signedAmountCents(tx.amountCents, tx.type == TxType.income)
                  : '****',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: L.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _summaryRight(int inc, int exp, {bool hidden = false}) {
  // 当日 "收入: X  支出: Y" (hidden=true 时全部 ***)
  if (hidden) {
    final parts = <String>[];
    if (inc > 0) parts.add('收入: ****');
    if (exp > 0) parts.add('支出: ****');
    if (parts.isEmpty) return '';
    return parts.join('  ');
  }
  final parts = <String>[];
  if (inc > 0) parts.add('收入: ${fmtCents(inc)}');
  if (exp > 0) parts.add('支出: ${fmtCents(exp)}');
  if (parts.isEmpty) return '';
  return parts.join('  ');
}
