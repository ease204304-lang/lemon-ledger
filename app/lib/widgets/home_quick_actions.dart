/// 首页 5 个快捷入口 (账单/预算/资产管家/购物返现/更多)
/// v1.5.0: 都是占位, 后续版本提供
library;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Row(
        children: const [
          _QuickItem(icon: Icons.receipt_long_outlined, label: '账单'),
          _QuickItem(icon: Icons.account_balance_wallet_outlined, label: '预算'),
          _QuickItem(icon: Icons.shield_outlined, label: '资产管家'),
          _QuickItem(icon: Icons.shopping_bag_outlined, label: '购物返现'),
          _QuickItem(icon: Icons.more_horiz, label: '更多'),
        ],
      ),
    );
  }
}

class _QuickItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _QuickItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label 该功能将在后续版本提供')),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: L.brandYellowTrack,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: L.textPrimary, size: 20),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, color: L.textBody)),
          ],
        ),
      ),
    );
  }
}
