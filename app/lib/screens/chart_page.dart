/// 图表统计页 (v1.4.1 重做)
///
/// 参考鲨鱼记账:
/// - 顶部 "支出▼" 大字切换 + 饼图
/// - 周/月/年 segment
/// - 快速周期选择 (横向 ListView)
/// - 总支出 + 平均值
/// - 折线图 (缩窄, + 平均线)
/// - 排行 + 同分类环比 ±50% 警示
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../data/tag_service.dart';
import '../theme/tokens.dart';
import '../widgets/category_icon.dart';
import '../widgets/segment.dart';
import '../widgets/top_tab_bar.dart';
import 'quick_entry_sheet.dart';
import 'tag_manager_page.dart';

enum ChartScope { week, month, year }

/// v1.8.0: 图表二级视图 (分类排行 | 标签统计)
enum ChartView { category, tag }

class ChartPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const ChartPage({super.key, required this.onNavigate});

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  ChartScope _scope = ChartScope.week;
  TxType _displayType = TxType.expense; // 默认显示支出
  int _selectedOffset = -1; // 默认上周 (历史数据通常在这里), 0=本周/本月 今年
  ChartView _view = ChartView.category; // v1.8.0: 默认分类视图
  TagSortBy _tagSort = TagSortBy.amount; // v1.8.0: 标签排序 (按金额/按时间)
  late Future<_ChartData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// 算出 (currentFrom, currentTo, prevFrom, prevTo) for a scope + offset
  /// offset = 0 means current period, -1 means previous, etc.
  ({int from, int to, int prevFrom, int prevTo}) _rangeForOffset(int offset) {
    final today = _todayDate();
    final anchor = _anchorForOffset(today, _scope, offset);
    late DateTime from, to;
    late DateTime prevFrom, prevTo;
    switch (_scope) {
      case ChartScope.week:
        // anchor: 该周的周一
        from = _weekStart(anchor);
        to = from.add(const Duration(days: 6));
        // 上周
        prevFrom = from.subtract(const Duration(days: 7));
        prevTo = from.subtract(const Duration(days: 1));
        break;
      case ChartScope.month:
        from = DateTime(anchor.year, anchor.month, 1);
        to = DateTime(anchor.year, anchor.month + 1, 0);
        prevFrom = DateTime(anchor.year, anchor.month - 1, 1);
        prevTo = DateTime(anchor.year, anchor.month, 0);
        break;
      case ChartScope.year:
        from = DateTime(anchor.year, 1, 1);
        to = DateTime(anchor.year, 12, 31);
        prevFrom = DateTime(anchor.year - 1, 1, 1);
        prevTo = DateTime(anchor.year - 1, 12, 31);
        break;
    }
    return (
      from: _dateToEpochDay(from),
      to: _dateToEpochDay(to),
      prevFrom: _dateToEpochDay(prevFrom),
      prevTo: _dateToEpochDay(prevTo),
    );
  }

  /// anchor date: offset=0 => today, offset=-1 => 1 period ago, etc.
  DateTime _anchorForOffset(DateTime today, ChartScope scope, int offset) {
    switch (scope) {
      case ChartScope.week:
        final monday = _weekStart(today);
        return monday.add(Duration(days: offset * 7));
      case ChartScope.month:
        return DateTime(today.year, today.month + offset, 1);
      case ChartScope.year:
        return DateTime(today.year + offset, 1, 1);
    }
  }

  DateTime _weekStart(DateTime d) {
    final delta = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day - delta);
  }

  Future<_ChartData> _load() async {
    final today = _todayEpochDay();
    final range = _rangeForOffset(_selectedOffset);
    final cats = {
      for (final c in await CategoryRepository.instance.all()) c.id: c,
    };
    // 当前周期
    final currentSum = await TxRepository.instance.sumByRange(range.from, range.to);
    final currentByCat = await TxRepository.instance.sumByCategory(
        _displayType, range.from, range.to);
    // 上期
    final prevSum = await TxRepository.instance.sumByRange(
        range.prevFrom, range.prevTo);
    final prevByCat = await TxRepository.instance.sumByCategory(
        _displayType, range.prevFrom, range.prevTo);
    // 折线图 (按日聚合, 当月/当周, 当年按月聚合)
    final granularity = _scope == ChartScope.year
        ? ChartGranularity.month
        : ChartGranularity.day;
    final chartData = await TxRepository.instance.groupedAmounts(
        _displayType, range.from, range.to, granularity);
    // 排名 (按 currentByCat + 同比上期)
    final ranked = currentByCat.entries
        .map((e) => (e.key, e.value, prevByCat[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    // v1.8.0: 标签聚合 (标签视图 + 饼图数据源)
    final tagStats = await TagService.instance
        .statsByTag(_displayType, range.from, range.to);

    // 算出锚点日期 (用于显示标签)
    final todayDate = _todayDate();
    final anchor = _anchorForOffset(todayDate, _scope, _selectedOffset);

    return _ChartData(
      scope: _scope,
      type: _displayType,
      anchor: anchor,
      today: today,
      from: range.from,
      to: range.to,
      prevFrom: range.prevFrom,
      prevTo: range.prevTo,
      expense: currentSum.$1,
      income: currentSum.$2,
      prevExpense: prevSum.$1,
      prevIncome: prevSum.$2,
      chartData: chartData,
      granularity: granularity,
      ranked: ranked,
      cats: cats,
      tagStats: tagStats,
    );
  }

  DateTime _todayDate() {
    final ms = _todayEpochDay() * 86400000;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _setType(TxType t) {
    setState(() {
      _displayType = t;
      _future = _load();
    });
  }

  void _setOffset(int o) {
    // 限制最大 0 (不显示未来)
    final clamped = o > 0 ? 0 : o;
    setState(() {
      _selectedOffset = clamped;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              type: _displayType,
              onTypeChanged: _setType,
              scope: _scope,
              onScopeChanged: (s) {
                setState(() {
                  _scope = s;
                  _selectedOffset = 0;
                });
                _reload();
              },
              view: _view,
              onViewChanged: (v) => setState(() => _view = v),
            ),
            Expanded(
              child: FutureBuilder<_ChartData>(
                future: _future,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _Body(
                    data: snap.data!,
                    selectedOffset: _selectedOffset,
                    onOffsetChanged: _setOffset,
                    view: _view,
                    tagSort: _tagSort,
                    onTagSortChanged: (s) => setState(() => _tagSort = s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: TopTabBar(
        currentIndex: 1,
        onTap: widget.onNavigate,
        onAddLongPress: () => showQuickEntrySheet(context),
      ),
    );
  }
}

class _ChartData {
  final ChartScope scope;
  final TxType type;
  final DateTime anchor;
  final int today;
  final int from, to;
  final int prevFrom, prevTo;
  final int expense, income;
  final int prevExpense, prevIncome;
  final List<(String, int)> chartData;
  final ChartGranularity granularity;
  final List<(String, int, int)> ranked; // (catId, current, prev)
  final Map<String, Category> cats;
  final List<TagStat> tagStats; // v1.8.0: 标签聚合
  _ChartData({
    required this.scope,
    required this.type,
    required this.anchor,
    required this.today,
    required this.from,
    required this.to,
    required this.prevFrom,
    required this.prevTo,
    required this.expense,
    required this.income,
    required this.prevExpense,
    required this.prevIncome,
    required this.chartData,
    required this.granularity,
    required this.ranked,
    required this.cats,
    required this.tagStats,
  });

  /// 周期内显示的金额
  int get amount => type == TxType.expense ? expense : income;
  int get prevAmount => type == TxType.expense ? prevExpense : prevIncome;

  /// 已过天数 (公式与原版一致: 平均 = 周期总额 / 已过天数)
  int get elapsedDays {
    if (scope == ChartScope.week) return 7;
    if (scope == ChartScope.month) return anchor.day;
    // 年: 当年 1/1 到 anchor 的天数
    final yearStart = DateTime(anchor.year, 1, 1);
    final anchorDate = anchor;
    return anchorDate.difference(yearStart).inDays + 1;
  }

  int get avgCents => elapsedDays == 0 ? 0 : amount ~/ elapsedDays;
}

// =============== UI ===============

class _Header extends StatelessWidget {
  final TxType type;
  final ValueChanged<TxType> onTypeChanged;
  final ChartScope scope;
  final ValueChanged<ChartScope> onScopeChanged;
  final ChartView view; // v1.8.0
  final ValueChanged<ChartView> onViewChanged; // v1.8.0
  const _Header({
    required this.type,
    required this.onTypeChanged,
    required this.scope,
    required this.onScopeChanged,
    required this.view,
    required this.onViewChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = type == TxType.expense;
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部: 大字 "支出 ▼" / "收入 ▼" + 右上饼图 icon (v1.8.0: 切到标签视图)
          Row(
            children: [
              InkWell(
                onTap: () =>
                    onTypeChanged(isExpense ? TxType.income : TxType.expense),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpense ? '支出' : '收入',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: L.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down,
                          color: L.textPrimary, size: 22),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // v1.8.0: 饼图 icon → 切换 分类/标签 视图
              IconButton(
                onPressed: () => onViewChanged(
                    view == ChartView.category ? ChartView.tag : ChartView.category),
                tooltip: '标签统计 (饼图)',
                icon: Icon(
                  view == ChartView.tag
                      ? Icons.pie_chart
                      : Icons.pie_chart_outline,
                  color: view == ChartView.tag ? L.brandYellow : L.textPrimary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 周/月/年 segment + 分类/标签 二级切换 (v1.8.0)
          Row(
            children: [
              Segment<ChartScope>(
                values: const [
                  ChartScope.week,
                  ChartScope.month,
                  ChartScope.year
                ],
                labels: const ['周', '月', '年'],
                current: scope,
                onChanged: onScopeChanged,
              ),
              const Spacer(),
              // v1.8.0: 分类 | 标签 切换 chips
              _ViewToggle(current: view, onChanged: onViewChanged),
            ],
          ),
        ],
      ),
    );
  }
}

/// v1.8.0: 分类 / 标签 视图切换 (小 chips)
class _ViewToggle extends StatelessWidget {
  final ChartView current;
  final ValueChanged<ChartView> onChanged;
  const _ViewToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ChartView v) {
      final sel = current == v;
      return InkWell(
        onTap: () => onChanged(v),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? L.brandYellow : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? L.brandYellow : L.dividerStrong),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
              color: sel ? L.textPrimary : L.textSecondary,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('分类', ChartView.category),
        const SizedBox(width: 6),
        chip('标签', ChartView.tag),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  final _ChartData data;
  final int selectedOffset;
  final ValueChanged<int> onOffsetChanged;
  final ChartView view; // v1.8.0
  final TagSortBy tagSort; // v1.8.0
  final ValueChanged<TagSortBy> onTagSortChanged; // v1.8.0
  const _Body({
    required this.data,
    required this.selectedOffset,
    required this.onOffsetChanged,
    required this.view,
    required this.tagSort,
    required this.onTagSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(L.pageH, 4, L.pageH, 16),
      children: [
        // 快速周期选择
        _QuickPeriodSelector(
          scope: data.scope,
          selectedOffset: selectedOffset,
          onChanged: onOffsetChanged,
        ),
        const SizedBox(height: 8),
        // 摘要卡片
        _SummaryCard(data: data),
        const SizedBox(height: 12),
        if (view == ChartView.tag) ...[
          // v1.8.0: 标签视图 — 饼图 + 按时间/按金额排序 + 列表
          _TagStatsCard(
            data: data,
            tagSort: tagSort,
            onTagSortChanged: onTagSortChanged,
          ),
        ] else ...[
          // 折线图 (缩窄 + 平均线)
          _ChartCard(data: data),
          const SizedBox(height: 12),
          // 排行榜 (含 ⚠️ 警示)
          _RankingCard(data: data),
        ],
      ],
    );
  }
}

class _QuickPeriodSelector extends StatelessWidget {
  final ChartScope scope;
  final int selectedOffset;
  final ValueChanged<int> onChanged;
  const _QuickPeriodSelector({
    required this.scope,
    required this.selectedOffset,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 只显示过去 + 当前 (不显示未来)
    // 周: [39周, 上周, 本周] (3 个)
    // 月: [8月, 上月, 本月] (3 个)
    // 年: [2024, 去年, 今年] (3 个)
    final labels = <int, String>{};
    for (var off = -2; off <= 0; off++) {
      final d = _formatPeriod(scope, off);
      labels[off] = d;
    }
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final off = i - 2; // -2, -1, 0
          final selected = off == selectedOffset;
          return GestureDetector(
            onTap: () => onChanged(off),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? L.textPrimary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                labels[off]!,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? L.textPrimary : L.textTertiary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatPeriod(ChartScope scope, int off) {
    final today = DateTime.now();
    switch (scope) {
      case ChartScope.week:
        // off=0 -> "本周", off=-1 -> "上周", off=-2 -> "上上周", off=1 -> "下周"
        if (off == 0) return '本周';
        if (off == -1) return '上周';
        if (off < -1) {
          // 计算 ISO 周数
          final week = _isoWeekNumber(today.add(Duration(days: off * 7)));
          return '$week周';
        }
        final week = _isoWeekNumber(today.add(Duration(days: off * 7)));
        return '$week周';
      case ChartScope.month:
        if (off == 0) return '本月';
        if (off == -1) return '上月';
        final d = DateTime(today.year, today.month + off, 1);
        return '${d.month}月';
      case ChartScope.year:
        if (off == 0) return '今年';
        if (off == -1) return '去年';
        return '${today.year + off}年';
    }
  }

  /// ISO 周数 (简化版)
  int _isoWeekNumber(DateTime d) {
    final yearStart = DateTime(d.year, 1, 4);
    final delta = d.difference(yearStart).inDays;
    return (delta / 7).floor() + 1;
  }
}

class _SummaryCard extends StatelessWidget {
  final _ChartData data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 总金额
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.type == TxType.expense ? '总支出' : '总收入',
                style: const TextStyle(fontSize: 12, color: L.textTertiary),
              ),
              const SizedBox(height: 4),
              Text(_fmt(data.amount),
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: L.textPrimary,
                      letterSpacing: -0.5)),
            ],
          ),
          const Spacer(),
          // 平均值
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('平均值', style: TextStyle(fontSize: 12, color: L.textTertiary)),
              const SizedBox(height: 4),
              Text(_fmt(data.avgCents),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: L.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final _ChartData data;
  const _ChartCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 折线图 (高度 140, 比之前 220 缩小)
          SizedBox(
            height: 140,
            child: data.chartData.isEmpty
                ? const Center(
                    child: Text('本周无支出',
                        style: TextStyle(color: L.textTertiary)))
                : LineChart(
                    _lineChartData(data),
                    duration: const Duration(milliseconds: 300),
                  ),
          ),
          // X 轴 label
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _xAxisLabels(data),
          ),
        ],
      ),
    );
  }

  LineChartData _lineChartData(_ChartData data) {
    final points = data.chartData;
    // 单位统一为"元" (Y 轴显示元, spot.Y 也是元)
    // points[i].$2 是 cents, 除以 100 得元
    final maxCents = points.fold<int>(100, (a, b) => a > b.$2 ? a : b.$2);
    final maxYuan = (maxCents * 1.2) / 100.0;  // 元
    final avgYuan = data.avgCents / 100.0;        // 元
    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).toDouble().clamp(1, 1000),
      minY: 0,
      // maxY 单位是元 (与 spot.Y 一致)
      maxY: maxYuan.clamp(avgYuan * 1.2, double.infinity),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      lineTouchData: const LineTouchData(enabled: false),
      extraLinesData: avgYuan > 0
          ? ExtraLinesData(horizontalLines: [
              HorizontalLine(
                y: avgYuan,
                color: L.textSecondary.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ])
          : null,
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < points.length; i++)
              FlSpot(i.toDouble(), points[i].$2 / 100.0),  // 元
          ],
          isCurved: true,
          curveSmoothness: 0.3,
          color: L.brandYellow,
          barWidth: 2.5,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: L.brandYellow.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  Widget _xAxisLabels(_ChartData data) {
    if (data.chartData.isEmpty) return const SizedBox.shrink();
    // 取头/中/尾 3 个
    final pts = data.chartData;
    final indices = pts.length <= 4
        ? List.generate(pts.length, (i) => i)
        : [0, pts.length ~/ 3, 2 * pts.length ~/ 3, pts.length - 1];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final i in indices)
          Text(pts[i].$1, style: const TextStyle(fontSize: 11, color: L.textTertiary)),
      ],
    );
  }
}

class _RankingCard extends StatelessWidget {
  final _ChartData data;
  const _RankingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.type == TxType.expense ? '支出排行榜' : '收入排行榜',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: L.textPrimary),
          ),
          const SizedBox(height: 12),
          if (data.ranked.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('本周无数据',
                    style: TextStyle(color: L.textTertiary, fontSize: 13)),
              ),
            )
          else
            for (var i = 0; i < data.ranked.length; i++) ...[
              _RankingRow(
                rank: i + 1,
                categoryId: data.ranked[i].$1,
                current: data.ranked[i].$2,
                prev: data.ranked[i].$3,
                total: data.amount,
                category: data.cats[data.ranked[i].$1],
                // v1.7.0 U1.9: 点排行 → 跳到该分类的标签管理
                onTap: () {
                  final cat = data.cats[data.ranked[i].$1];
                  if (cat == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TagManagerPage(
                        categoryId: cat.id,
                        categoryName: cat.name,
                      ),
                    ),
                  );
                },
              ),
              if (i < data.ranked.length - 1) const SizedBox(height: 14),
            ],
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int rank;
  final String categoryId;
  final int current;
  final int prev;
  final int total;
  final Category? category;
  /// v1.7.0: 点单笔/单分类 → 跳到该分类的标签管理页
  final VoidCallback? onTap;
  const _RankingRow({
    required this.rank,
    required this.categoryId,
    required this.current,
    required this.prev,
    required this.total,
    required this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : current / total;
    final warning = _computeWarning(current, prev);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            CategoryIcon(iconKey: category?.iconKey ?? 'else', size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(category?.name ?? '未分类',
                          style: const TextStyle(
                              fontSize: 14, color: L.textPrimary, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 6),
                      if (warning != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: warning.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(warning.icon, size: 10, color: warning.color),
                              const SizedBox(width: 2),
                              Text(warning.label,
                                  style: TextStyle(
                                      fontSize: 10, color: warning.color, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        current == 0 ? '0' : (current / 100).toStringAsFixed(0),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700, color: L.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${(pct * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 11, color: L.textTertiary)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: L.surfaceNote,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: pct.clamp(0, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                color: L.brandYellow,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 警示: ±50% + ≥200 元 (按 Q3-C)
  ({IconData icon, Color color, String label})? _computeWarning(int cur, int pre) {
    if (pre == 0) return null;
    final delta = (cur - pre) / pre;
    if (cur < 20000 || delta.abs() < 0.5) return null;
    if (delta > 0) {
      return (icon: Icons.arrow_upward, color: L.warnRed, label: '涨');
    } else {
      return (icon: Icons.arrow_downward, color: L.okGreen, label: '降');
    }
  }
}

// =============== v1.8.0 标签统计卡片 ===============

/// 标签饼图配色 (暖色系, 与品牌黄呼应)
const _tagPieColors = [
  Color(0xFFFFD946), // 品牌黄
  Color(0xFFFF9F43), // 橙
  Color(0xFF54A0FF), // 蓝
  Color(0xFF4FBC8B), // 绿
  Color(0xFFEE5253), // 红
  Color(0xFFA55EEA), // 紫
  Color(0xFFFF6B81), // 粉
  Color(0xFF1ABC9C), // 青
];

class _TagStatsCard extends StatelessWidget {
  final _ChartData data;
  final TagSortBy tagSort;
  final ValueChanged<TagSortBy> onTagSortChanged;
  const _TagStatsCard({
    required this.data,
    required this.tagSort,
    required this.onTagSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 排序副本 (data.tagStats 本身是按金额的, 这里按需重排)
    final stats = [...data.tagStats]..sort((a, b) => tagSort == TagSortBy.amount
        ? b.totalCents.compareTo(a.totalCents)
        : b.lastUsedDay.compareTo(a.lastUsedDay));
    final total = stats.fold<int>(0, (s, t) => s + t.totalCents);

    return Container(
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      padding: const EdgeInsets.all(16),
      child: stats.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('本周期暂无标签数据\n(记账时填写备注即可生成标签)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: L.textTertiary, fontSize: 13)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题 + 排序切换
                Row(
                  children: [
                    const Text('标签分析',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text('${stats.length} 个标签',
                        style: const TextStyle(
                            color: L.textTertiary, fontSize: 12)),
                    const Spacer(),
                    _SortToggle(current: tagSort, onChanged: onTagSortChanged),
                  ],
                ),
                const SizedBox(height: 16),
                // 饼图 + 图例
                Row(
                  children: [
                    SizedBox(
                      width: 150,
                      height: 150,
                      child: _TagPie(stats: stats, total: total),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = 0; i < stats.take(6).length; i++)
                            _PieLegendRow(
                              color: _tagPieColors[i % _tagPieColors.length],
                              name: stats[i].name,
                              cents: stats[i].totalCents,
                              total: total,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32, color: L.dividerLight),
                // 列表
                ...List.generate(stats.length, (i) {
                  final s = stats[i];
                  final pct = total == 0 ? 0.0 : s.totalCents / total;
                  return _TagRowWidget(
                    index: i,
                    stat: s,
                    pct: pct,
                    maxCents: stats.first.totalCents,
                    sortBy: tagSort,
                  );
                }),
              ],
            ),
    );
  }
}

/// 按金额 / 按时间 排序切换 (用户需求: "按时间和按金额")
class _SortToggle extends StatelessWidget {
  final TagSortBy current;
  final ValueChanged<TagSortBy> onChanged;
  const _SortToggle({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, TagSortBy v) {
      final sel = current == v;
      return InkWell(
        onTap: () => onChanged(v),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: sel ? L.segmentSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: 12,
                color: sel ? Colors.white : L.textSecondary,
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
              )),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip('按金额', TagSortBy.amount),
        const SizedBox(width: 4),
        chip('按时间', TagSortBy.time),
      ],
    );
  }
}

/// 标签饼图 (fl_chart PieChart)
class _TagPie extends StatelessWidget {
  final List<TagStat> stats;
  final int total;
  const _TagPie({required this.stats, required this.total});

  @override
  Widget build(BuildContext context) {
    // 最多 6 块, 其余合并 "其他"
    final top = stats.take(6).toList();
    final restTotal =
        stats.skip(6).fold<int>(0, (s, t) => s + t.totalCents);
    final sections = <PieChartSectionData>[
      for (var i = 0; i < top.length; i++)
        PieChartSectionData(
          value: top[i].totalCents.toDouble(),
          color: _tagPieColors[i % _tagPieColors.length],
          radius: 18,
          showTitle: false,
          badgeWidget: total > 0 && top[i].totalCents / total >= 0.12
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: Text(
                      '${(top[i].totalCents / total * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: L.textPrimary)),
                )
              : null,
          badgePositionPercentageOffset: 0.98,
        ),
      if (restTotal > 0)
        PieChartSectionData(
          value: restTotal.toDouble(),
          color: L.textDisabled,
          radius: 14,
          showTitle: false,
        ),
    ];
    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 34,
        sectionsSpace: 2,
      ),
    );
  }
}

class _PieLegendRow extends StatelessWidget {
  final Color color;
  final String name;
  final int cents;
  final int total;
  const _PieLegendRow({
    required this.color,
    required this.name,
    required this.cents,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : cents / total * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: L.textBody)),
          ),
          Text('${pct.toStringAsFixed(0)}%',
              style: const TextStyle(
                  fontSize: 12,
                  color: L.textSecondary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 标签统计行 (排行 + 金额条 / 最近日期)
class _TagRowWidget extends StatelessWidget {
  final int index;
  final TagStat stat;
  final double pct;
  final int maxCents;
  final TagSortBy sortBy;
  const _TagRowWidget({
    required this.index,
    required this.stat,
    required this.pct,
    required this.maxCents,
    required this.sortBy,
  });

  String _lastDate() {
    final d =
        DateTime.fromMillisecondsSinceEpoch(stat.lastUsedDay * 86400000,
            isUtc: true);
    return '${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: L.textTertiary)),
              ),
              // 色点 (与饼图一致)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: _tagPieColors[index % _tagPieColors.length],
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(stat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: L.textPrimary)),
              ),
              if (sortBy == TagSortBy.time) ...[
                Text(_lastDate(),
                    style: const TextStyle(
                        fontSize: 11, color: L.textTertiary)),
                const SizedBox(width: 8),
              ],
              Text('${stat.txCount} 笔',
                  style:
                      const TextStyle(fontSize: 11, color: L.textTertiary)),
              const SizedBox(width: 10),
              Text('¥${_fmt(stat.totalCents)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: L.textPrimary)),
            ],
          ),
          const SizedBox(height: 5),
          // 金额条 (与饼图占比一致)
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: L.dividerLight),
                  FractionallySizedBox(
                    widthFactor: maxCents == 0 ? 0.0 : stat.totalCents / maxCents,
                    child:
                        Container(color: _tagPieColors[index % _tagPieColors.length]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============== utils ===============

String _fmt(int cents) {
  if (cents == 0) return '0';
  final s = (cents / 100).toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${buf.toString()}.${parts[1]}';
}

int _todayEpochDay() {
  final n = DateTime.now();
  return _dateToEpochDay(DateTime(n.year, n.month, n.day));
}

int _dateToEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        86400000;
