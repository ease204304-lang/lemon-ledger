/// 记账统计模块主页面 (v1.11.0 W3)
///
/// 对应《记账统计模块产品需求规格说明书》v0.9:
///   - 01 视图与范围: 收入 / 支出 / 结余 三视图 (顶部下拉切换)
///   - 03 时间范围: 7 个快捷项 + 自定义
///   - 04 分类/标签/交易对象 统计与交互
///   - 05 结余视图: 总览 → 趋势 → 收入贡献 → 支出影响 → 明细
///   - 06 页面切换与刷新
library;

import 'package:flutter/material.dart';

import '../services/stats_api.dart';
import '../services/stats_controller.dart';
import '../theme/tokens.dart';
import '../widgets/date_picker_dialog.dart';
import '../widgets/stats/balance_view.dart';
import '../widgets/stats/category_filter_sheet.dart';
import '../widgets/stats/stats_widgets.dart';

/// 统计页 (替换/并入原 ChartPage)
class StatsPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final StatsController? controller;

  const StatsPage({super.key, required this.onNavigate, this.controller});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final StatsController _c;
  final List<FilterCategory> _cats = const [];

  @override
  void initState() {
    super.initState();
    _c = widget.controller ?? StatsController();
    _c.addListener(_onChanged);
    _c.refresh();
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            QuickRangeBar(
              current: _c.quickRange,
              onChanged: (q) => _c.setQuickRange(q),
              onCustom: _pickCustom,
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(L.pageH, 10, L.pageH, 10),
      child: Row(
        children: [
          // 视图下拉 (收入/支出/结余)
          StatsViewDropdown(
            current: _c.view,
            onChanged: (v) => _c.switchView(v),
          ),
          const SizedBox(width: 12),
          // 结余视图显示两侧筛选按钮; 单侧显示分类筛选
          if (_c.view == StatsView.balance) ...[
            _filterBtn('收入分类', _c.appliedIncome.isAll ? '全部' : '已选'),
            const SizedBox(width: 6),
            _filterBtn('支出分类', _c.appliedExpense.isAll ? '全部' : '已选'),
          ] else
            _filterBtn('分类筛选',
                _c.appliedExpense.isAll ? '全部' : '已选'),
          const Spacer(),
          // 同期对比开关
          InkWell(
            onTap: () => _c.setComparisonEnabled(!_c.comparisonEnabled),
            child: Row(
              children: [
                Text('同期',
                    style: TextStyle(
                      fontSize: 12,
                      color: _c.comparisonEnabled
                          ? L.textPrimary
                          : L.textTertiary,
                    )),
                const SizedBox(width: 4),
                Icon(
                  _c.comparisonEnabled
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 16,
                  color: _c.comparisonEnabled ? L.brandYellow : L.textTertiary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBtn(String label, String value) {
    return InkWell(
      onTap: _openFilter,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: L.surfaceSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: L.dividerLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 11, color: L.textSecondary)),
            const Icon(Icons.arrow_drop_down, size: 14, color: L.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilter() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CategoryFilterSheet(
        incomeSide: _c.view == StatsView.income,
        controller: _c,
        categories: _cats,
      ),
    );
  }

  Future<void> _pickCustom() async {
    final r = _c.dateRange;
    final picked = await showAppDatePicker(
      context,
      initialDate: r.start,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    // 自定义: 起始 = 选中日, 结束 = 今天 (或保持原结束)
    final end = r.source == QuickRange.custom ? r.end : DateTime.now();
    if (!_c.setCustomRange(picked, end)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('起始日不得晚于结束日，且不能选择未来日期')),
      );
    }
  }

  Widget _body() {
    if (_c.loading && _c.summary == null) {
      return const SingleChildScrollView(
        child: Column(children: [StatsSkeleton(), StatsSkeleton(lines: 6)]),
      );
    }
    if (_c.error != null && _c.summary == null) {
      return SingleChildScrollView(
        child: Column(
          children: [
            ModuleError(
              message: _c.error!,
              onRetry: () => _c.refresh(),
            ),
          ],
        ),
      );
    }

    final isBalance = _c.view == StatsView.balance;

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        // 汇总卡
        if (isBalance)
          BalanceOverviewCard(
            summary: _c.summary,
            onTapCompareBalance: () => _c.setComparisonEnabled(true),
          )
        else
          _singleSideSummary(),

        // 趋势
        TrendChartCard(
          points: _c.trend,
          balanceMode: isBalance,
          comparisonEnabled: _c.comparisonEnabled,
        ),

        // 分类榜
        if (isBalance)
          ..._balanceRankings()
        else
          RankingCard(
            title: '分类排行',
            items: _c.categories.items,
            expanded: _c.rankingExpanded,
            onToggleExpand: _c.toggleRankingExpanded,
            onSortChanged: _cycleSort,
          ),

        // 标签分析
        TagAnalysisCard(
          chart: _c.tags,
          expanded: _c.rankingExpanded,
          onToggleExpand: _c.toggleRankingExpanded,
        ),
      ],
    );
  }

  /// 单侧视图的汇总卡 (收入/支出)
  Widget _singleSideSummary() {
    final s = _c.summary;
    if (s == null) return const SizedBox.shrink();
    final isIncome = _c.view == StatsView.income;
    final amount = isIncome ? s.income : s.expense;
    final count = isIncome ? s.incomeCount : s.expenseCount;
    final color = isIncome ? L.okGreen : const Color(0xFFFF8A4A);

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
          Row(
            children: [
              Text(isIncome ? '收入' : '支出',
                  style: const TextStyle(fontSize: 13, color: L.textSecondary)),
              const Spacer(),
              if (s.dailyAverage != null)
                Text('日均 ${fmtMoney(s.dailyAverage!)}',
                    style: const TextStyle(fontSize: 12, color: L.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            fmtMoney(amount),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text('$count 笔', style: const TextStyle(fontSize: 11, color: L.textTertiary)),
          // 同期对比
          if (_c.comparisonEnabled && s.compareIncome != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: L.dividerLight),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('同期', style: TextStyle(fontSize: 12, color: L.textSecondary)),
                const SizedBox(width: 6),
                Text(isIncome ? s.compareIncome! : s.compareExpense!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 结余视图: 收入贡献 + 支出影响 两榜
  List<Widget> _balanceRankings() {
    final b = _c.balance;
    if (b == null) return const [];
    return [
      BalanceSideRanking(
        title: '收入贡献',
        color: L.okGreen,
        items: b.incomeContribution.items,
        expanded: _c.rankingExpanded,
        onToggleExpand: _c.toggleRankingExpanded,
      ),
      BalanceSideRanking(
        title: '支出影响',
        color: const Color(0xFFFF8A4A),
        items: b.expenseImpact.items,
        expanded: _c.rankingExpanded,
        onToggleExpand: _c.toggleRankingExpanded,
      ),
    ];
  }

  void _cycleSort() {
    final next = switch (_c.sortBy) {
      RankSort.amount => RankSort.count,
      RankSort.count => RankSort.recent,
      RankSort.recent => RankSort.amount,
    };
    _c.setSortBy(next);
  }
}
