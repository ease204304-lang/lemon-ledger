/// 发现页 — 后续版本内容
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/top_tab_bar.dart';
import 'quick_entry_sheet.dart';

class DiscoverPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const DiscoverPage({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
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
          children: const [
            _Placeholder(title: '理财社区', subtitle: '该功能将在后续版本提供'),
            SizedBox(height: 12),
            _Placeholder(title: '预算管理', subtitle: '该功能将在后续版本提供'),
            SizedBox(height: 12),
            _Placeholder(title: '资产管理', subtitle: '该功能将在后续版本提供'),
            SizedBox(height: 12),
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
