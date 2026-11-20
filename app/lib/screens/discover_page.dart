/// 发现页 — 工具中心 (v1.13.0)
///
/// 原来 4 个占位功能中:
///   - 资产管理 → v1.13.0 已实现 (AssetPage)
///   - 预算管理 → v1.13.0 升级为「分类预算」(月预算在「我的」里)
///   - 理财社区 / 购物返现 → 仍占位
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/top_tab_bar.dart';
import 'asset_page.dart';
import 'category_budget_page.dart';
import 'quick_entry_sheet.dart';

class DiscoverPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const DiscoverPage({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(
        title: const Text('发现'),
        actions: const [Padding(
          padding: EdgeInsets.only(right: 16),
          child: Icon(Icons.search, color: L.textPrimary),
        )],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(L.pageH),
          children: [
            _Entry(
              title: '资产管理',
              subtitle: '账户余额 · 净资产 · 负债',
              icon: Icons.account_balance_wallet_outlined,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AssetPage(),
              )),
            ),
            const SizedBox(height: 12),
            _Entry(
              title: '分类预算',
              subtitle: '各分类月度上限 · 超支预警',
              icon: Icons.pie_chart_outline,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoryBudgetPage(
                    year: now.year, month: now.month),
              )),
            ),
            const SizedBox(height: 12),
            _Placeholder(title: '理财社区', subtitle: '该功能将在后续版本提供'),
            const SizedBox(height: 12),
            _Placeholder(title: '购物返现', subtitle: '该功能将在后续版本提供'),
          ],
        ),
      ),
      bottomNavigationBar: TopTabBar(
        currentIndex: 3,
        onTap: onNavigate,
        onAddLongPress: () => showQuickEntrySheet(context),
      ),
    );
  }
}

/// 可点击的功能入口
class _Entry extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _Entry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(L.cardR),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.circular(L.cardR),
        ),
        child: Row(
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: L.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(
                      fontSize: 12, color: L.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: L.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title, subtitle;
  const _Placeholder({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: L.brandYellowTrack,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.star_border, color: L.textPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: L.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    fontSize: 12, color: L.textTertiary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: L.textTertiary),
        ],
      ),
    );
  }
}
