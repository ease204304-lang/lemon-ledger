/// 记账页底部操作栏: 日期 (左) + 金额 (中) + 保存 (右)
library;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'entry_amount_panel.dart';

class EntryBottomActionBar extends StatelessWidget {
  final DateTime date;
  final String amount;
  final VoidCallback onPickDate;
  final VoidCallback onSave;
  const EntryBottomActionBar({
    super.key,
    required this.date,
    required this.amount,
    required this.onPickDate,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          // 日期选择 (左)
          InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: L.dividerLight, width: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 14, color: L.textSecondary),
                  const SizedBox(width: 6),
                  Text(_dateFmt(date),
                      style: const TextStyle(
                          color: L.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          // 金额显示 (中间, 自适应宽度, FittedBox 收缩)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: EntryAmountDisplay(amount: amount),
            ),
          ),
          // 保存按钮 (右)
          ElevatedButton(
            onPressed: onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: L.brandYellow,
              foregroundColor: L.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text('保存',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

String _dateFmt(DateTime d) => '${d.year}-${_2(d.month)}-${_2(d.day)}';
String _2(int v) => v < 10 ? '0$v' : '$v';
