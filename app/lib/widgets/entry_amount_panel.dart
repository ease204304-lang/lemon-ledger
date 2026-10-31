/// 记账页金额区: 支出/收入 chips + 大字金额显示
library;

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../theme/tokens.dart';

/// 类型选择面板 (支出/收入 chips)
class EntryAmountPanel extends StatelessWidget {
  final TxType type;
  final ValueChanged<TxType> onType;
  const EntryAmountPanel({super.key, required this.type, required this.onType});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _TypeChip(label: '支出',
              selected: type == TxType.expense,
              onTap: () => onType(TxType.expense)),
          const SizedBox(width: 16),
          _TypeChip(label: '收入',
              selected: type == TxType.income,
              onTap: () => onType(TxType.income)),
        ],
      ),
    );
  }
}

/// 单个类型 chip
class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                color: selected ? L.textPrimary : L.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 15,
              )),
          if (selected) ...[
            const SizedBox(width: 6),
            Container(width: 14, height: 2, color: L.brandYellow),
          ],
        ],
      ),
    );
  }
}

/// 金额显示: 数字大字号 + "元", FittedBox 收缩防溢出
class EntryAmountDisplay extends StatelessWidget {
  final String amount;
  const EntryAmountDisplay({super.key, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              amount == '0' ? '0' : amount,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: L.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        const Text('元',
            style: TextStyle(color: L.textSecondary, fontSize: 14)),
      ],
    );
  }
}
