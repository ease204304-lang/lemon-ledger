/// 首页黄色 header (logo + 搜索/日历) + 月份汇总 (含 stat 卡片)
library;

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../utils/date_utils.dart';
import 'date_picker_dialog.dart';

class HomeHeader extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onCalendar;
  const HomeHeader({
    super.key,
    required this.onSearch,
    required this.onCalendar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.brandYellow,
      padding: const EdgeInsets.fromLTRB(L.pageH, 6, L.pageH, 12),
      child: Row(
        children: [
          // 左侧笑脸 logo
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: L.textPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tag_faces, size: 18, color: L.textPrimary),
          ),
          const SizedBox(width: 8),
          // 中心: Logo 文字
          const Expanded(
            child: Text('小猪记账',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: L.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                )),
          ),
          // 右侧: 搜索 + 日历
          IconButton(
            onPressed: onSearch,
            icon: const Icon(Icons.search, color: L.textPrimary),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onCalendar,
            icon: const Icon(Icons.calendar_today, color: L.textPrimary),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// 月份汇总: 月份选择 + 收入/支出 + 可见性切换
/// 包含: 月份 chip (点弹 Material DatePicker), 收入/支出 stat, 眼睛按钮
class HomeMonthSummary extends StatelessWidget {
  final DateTime month;
  final Future<int> incomeCents;
  final Future<int> expenseCents;
  final bool showAmount;
  final VoidCallback onToggleAmount;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onPickMonth;
  final ValueChanged<TxType> onStatTap;
  const HomeMonthSummary({
    super.key,
    required this.month,
    required this.incomeCents,
    required this.expenseCents,
    required this.showAmount,
    required this.onToggleAmount,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onPickMonth,
    required this.onStatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.brandYellow,
      padding: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 16),
      child: Row(
        children: [
          // 月份选择
          GestureDetector(
            onTap: () => _showMonthPicker(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${month.year}年',
                    style: const TextStyle(
                        color: L.textPrimary, fontSize: 14)),
                const SizedBox(width: 4),
                Text('${month.month}月',
                    style: const TextStyle(
                        color: L.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const Icon(Icons.keyboard_arrow_down,
                    color: L.textPrimary, size: 18),
              ],
            ),
          ),
          // 收入
          Expanded(
            child: FutureBuilder<int>(
              future: incomeCents,
              builder: (context, snap) => _HomeStat(
                label: '收入',
                value: snap.hasData
                    ? (showAmount ? fmtCents(snap.data!) : '****')
                    : '--',
                onTap:
                    snap.hasData ? () => onStatTap(TxType.income) : null,
              ),
            ),
          ),
          // 支出
          Expanded(
            child: FutureBuilder<int>(
              future: expenseCents,
              builder: (context, snap) => _HomeStat(
                label: '支出',
                value: snap.hasData
                    ? (showAmount ? fmtCents(snap.data!) : '****')
                    : '--',
                onTap:
                    snap.hasData ? () => onStatTap(TxType.expense) : null,
              ),
            ),
          ),
          // 可见性切换
          IconButton(
            onPressed: onToggleAmount,
            icon: Icon(showAmount ? Icons.visibility : Icons.visibility_off,
                color: L.textPrimary, size: 20),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _showMonthPicker(BuildContext context) async {
    // v1.8.1: 用自定义日期对话框 (双击某天 = 确定)
    final picked = await showAppDatePicker(
      context,
      initialDate: DateTime(month.year, month.month, 1),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onPickMonth(picked);
  }
}

/// 单条 stat: "收入" + 金额 (可点 → 排行)
class _HomeStat extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _HomeStat({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: L.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w400)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: const TextStyle(
                  color: L.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
    if (onTap == null) return inner;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: inner),
    );
  }
}
