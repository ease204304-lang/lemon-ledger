/// 统计模块公共组件 (v1.11.0 W3)
///
/// 对应《技术实施说明书》v0.9 §05 公共组件:
///   顶部类型、日期、筛选 · 汇总卡 · 趋势图 · 分类榜 · 标签图及榜单 · 对象榜
///   骨架屏、空状态和错误重试
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../services/stats_api.dart';
import '../../services/stats_controller.dart';
import '../../theme/tokens.dart';

// ── 数值工具 (金额一律十进制字符串) ──

/// 字符串金额 → double (仅用于显示/排序, 计算在服务端)
double _toDouble(String s) {
  if (s.isEmpty) return 0;
  final v = double.tryParse(s);
  return v ?? 0;
}

/// 千分位 + 两位小数 (PRD 02)
String fmtMoney(String amount) {
  final v = _toDouble(amount);
  final neg = v < 0;
  final abs = v.abs();
  final fixed = abs.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}${buf.toString()}.${parts[1]}';
}

/// 百分比 (两位小数)
String fmtRate(String? rate) => rate == null ? '—' : '$rate%';

/// 排行榜行 (PRD 04 榜单共用规则: 名称、金额、金额占比、笔数和金额进度条)
class RankRow extends StatelessWidget {
  final RankItem item;
  final Color? barColor;
  final VoidCallback? onTap;

  const RankRow({super.key, required this.item, this.barColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 二级分类缩进
                if (item.level == 2)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.subdirectory_arrow_right, size: 12, color: L.textTertiary),
                  ),
                Expanded(
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: L.textBody),
                  ),
                ),
                Text(
                  fmtMoney(item.amount),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 46,
                  child: Text(
                    fmtRate(item.rate),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: L.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: item.progress.clamp(0, 1),
                      minHeight: 3,
                      backgroundColor: L.dividerLight,
                      valueColor: AlwaysStoppedAnimation(
                        barColor ?? L.brandYellow,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${item.count} 笔',
                    style: const TextStyle(fontSize: 11, color: L.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类榜卡片 (默认 Top 5, 可展开全部)
class RankingCard extends StatelessWidget {
  final String title;
  final List<RankItem> items;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final ValueChanged<RankItem>? onTapItem;
  final VoidCallback? onSortChanged;

  const RankingCard({
    super.key,
    required this.title,
    required this.items,
    required this.expanded,
    this.onToggleExpand,
    this.onTapItem,
    this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
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
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onSortChanged != null)
                InkWell(
                  onTap: onSortChanged,
                  child: const Text('排序',
                      style: TextStyle(fontSize: 12, color: L.textSecondary)),
                ),
              if (visible.length > 5) ...[
                const SizedBox(width: 12),
                InkWell(
                  onTap: onToggleExpand,
                  child: Text(
                    expanded ? '收起' : '展开全部',
                    style: const TextStyle(fontSize: 12, color: L.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text('暂无数据', style: TextStyle(fontSize: 12, color: L.textTertiary)),
              ),
            )
          else
            for (final it in shown)
              RankRow(
                item: it,
                onTap: onTapItem == null ? null : () => onTapItem!(it),
              ),
        ],
      ),
    );
  }
}

/// 趋势图 (PRD 03: 收入、支出用折线, 无交易周期显示 0; 结余视图用净结余)
class TrendChartCard extends StatelessWidget {
  final List<TrendPoint> points;
  final bool balanceMode; // true = 结余趋势 (正负跨零轴)
  final bool comparisonEnabled;
  final void Function(TrendPoint)? onTapPoint;

  const TrendChartCard({
    super.key,
    required this.points,
    this.balanceMode = false,
    this.comparisonEnabled = false,
    this.onTapPoint,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    final income = points.map((p) => _toDouble(p.income)).toList();
    final expense = points.map((p) => _toDouble(p.expense)).toList();
    final balance = points.map((p) => _toDouble(p.balance)).toList();

    final all = <double>[
      ...income,
      ...expense,
      if (balanceMode) ...balance,
    ];
    var maxY = all.fold<double>(0, (m, v) => v > m ? v : m);
    var minY = all.fold<double>(0, (m, v) => v < m ? v : m);
    if (maxY == 0 && minY == 0) maxY = 1;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                balanceMode ? '结余趋势' : '收支趋势',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (!balanceMode)
                const _LegendDot(color: L.okGreen, label: '收入'),
              if (!balanceMode) const SizedBox(width: 10),
              if (!balanceMode)
                const _LegendDot(color: Color(0xFFFF8A4A), label: '支出'),
              if (balanceMode)
                const _LegendDot(color: L.textPrimary, label: '结余'),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: balanceMode ? minY : 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: L.dividerLight, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (v, meta) => Text(
                        _shortNum(v),
                        style: const TextStyle(fontSize: 10, color: L.textTertiary),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: points.length <= 8 ? 1 : (points.length / 6).ceilToDouble(),
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= points.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _shortDate(points[i].bucketStart),
                            style: const TextStyle(fontSize: 9, color: L.textTertiary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  if (!balanceMode)
                    _line('income', income, L.okGreen, balanceMode),
                  if (!balanceMode)
                    _line('expense', expense, const Color(0xFFFF8A4A), balanceMode),
                  if (balanceMode)
                    _line('balance', balance, L.textPrimary, balanceMode),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final i = s.barIndex;
                      if (i < 0 || i >= points.length) return null;
                      final p = points[i];
                      return LineTooltipItem(
                        '${p.bucketStart}\n',
                        const TextStyle(fontSize: 10, color: L.textSecondary),
                        children: balanceMode
                            ? [
                                TextSpan(
                                  text: '结余 ${fmtMoney(p.balance)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: L.textPrimary),
                                ),
                              ]
                            : [
                                TextSpan(
                                  text: '收入 ${fmtMoney(p.income)}\n支出 ${fmtMoney(p.expense)}',
                                  style: const TextStyle(
                                      fontSize: 11, color: L.textPrimary),
                                ),
                              ],
                      );
                    }).toList(),
                  ),
                  getTouchedSpotIndicator: (barData, indexes) => indexes
                      .map((_) => TouchedSpotIndicatorData(
                            const FlLine(color: L.textTertiary, strokeWidth: 1),
                            FlDotData(
                              getDotPainter: (s, pd, b, r) => FlDotCirclePainter(
                                radius: 3,
                                color: L.surface,
                                strokeWidth: 1.5,
                                strokeColor: L.textPrimary,
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static LineChartBarData _line(
    String name,
    List<double> data,
    Color color,
    bool fillZero,
  ) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < data.length; i++)
          FlSpot(i.toDouble(), data[i]),
      ],
      isCurved: false,
      barWidth: 2,
      color: color,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: fillZero && data.any((v) => v < 0),
        color: color.withValues(alpha: 0.08),
      ),
    );
  }

  static String _shortNum(double v) {
    if (v.abs() >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  static String _shortDate(String d) {
    if (d.length >= 10) return d.substring(5).replaceFirst('-', '/');
    return d;
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: L.textSecondary)),
      ],
    );
  }
}

/// 标签环形图 + 榜单 (PRD 04 标签分析: Top 5＋其他, 「未设置标签」独立保留, 双向联动)
class TagAnalysisCard extends StatelessWidget {
  final TagChart? chart;
  final bool expanded;
  final VoidCallback? onToggleExpand;
  final ValueChanged<RankItem>? onTapItem;

  const TagAnalysisCard({
    super.key,
    this.chart,
    required this.expanded,
    this.onToggleExpand,
    this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final c = chart;
    if (c == null) return const SizedBox.shrink();
    if (c.slices.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.circular(L.cardR),
        ),
        child: const Column(
          children: [
            Text('标签分析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            SizedBox(height: 12),
            Text('暂无标签数据', style: TextStyle(fontSize: 12, color: L.textTertiary)),
          ],
        ),
      );
    }

    final shown = expanded ? c.ranking : c.ranking.take(5).toList();

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
          const Text('标签分析', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 42,
                sections: [
                  for (final s in c.slices)
                    PieChartSectionData(
                      value: _toDouble(s.amount),
                      title: s.progress > 0.06 ? '${(s.progress * 100).toStringAsFixed(0)}%' : '',
                      radius: 30,
                      titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                      color: _sliceColor(s.name),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final it in shown)
            RankRow(
              item: it,
              onTap: onTapItem == null ? null : () => onTapItem!(it),
            ),
          if (c.ranking.length > 5)
            InkWell(
              onTap: onToggleExpand,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  expanded ? '收起' : '展开全部 (${c.ranking.length})',
                  style: const TextStyle(fontSize: 12, color: L.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _palette = [
    L.brandYellow,
    Color(0xFF4A9CF8),
    Color(0xFF67B23A),
    Color(0xFFFF8A4A),
    Color(0xFF9B6BFF),
    Color(0xFFBFBFBF),
    Color(0xFF4FBFA0),
  ];

  static Color _sliceColor(String name) {
    if (name == '未设置标签') return L.textTertiary;
    final h = name.hashCode.abs() % _palette.length;
    return _palette[h];
  }
}

/// 快捷日期选择条 (PRD 03: 近7/30/90天, 本月, 上月, 本年, 自定义)
class QuickRangeBar extends StatelessWidget {
  final QuickRange current;
  final ValueChanged<QuickRange> onChanged;
  final VoidCallback? onCustom;

  const QuickRangeBar({
    super.key,
    required this.current,
    required this.onChanged,
    this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      QuickRange.last7Days,
      QuickRange.last30Days,
      QuickRange.last90Days,
      QuickRange.thisMonth,
      QuickRange.lastMonth,
      QuickRange.thisYear,
    ];
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: L.pageH),
        children: [
          for (final q in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _chip(q.label, current == q, () => onChanged(q)),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _chip('自定义', current == QuickRange.custom,
                () => onCustom?.call() ?? onChanged(QuickRange.custom)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? L.brandYellow : L.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? L.brandYellow : L.dividerLight),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? L.textPrimary : L.textBody,
          ),
        ),
      ),
    );
  }
}

/// 视图切换下拉 (PRD 01: 统计入口顶部下拉切换收入、支出和结余)
class StatsViewDropdown extends StatelessWidget {
  final StatsView current;
  final ValueChanged<StatsView> onChanged;

  const StatsViewDropdown({super.key, required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = switch (current) {
      StatsView.income => '收入',
      StatsView.expense => '支出',
      StatsView.balance => '结余',
    };
    return PopupMenuButton<StatsView>(
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: StatsView.income, child: Text('收入')),
        PopupMenuItem(value: StatsView.expense, child: Text('支出')),
        PopupMenuItem(value: StatsView.balance, child: Text('结余')),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const Icon(Icons.arrow_drop_down, size: 20, color: L.textSecondary),
        ],
      ),
    );
  }
}

/// 空状态 (PRD 06 R6: 模块独立展示空状态)
class ModuleEmpty extends StatelessWidget {
  final String message;
  const ModuleEmpty({super.key, this.message = '暂无数据'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Center(
        child: Text(message, style: const TextStyle(fontSize: 12, color: L.textTertiary)),
      ),
    );
  }
}

/// 错误 + 独立重试 (PRD 06 R6: 模块失败时支持独立重试)
class ModuleError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ModuleError({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: L.surface,
        borderRadius: BorderRadius.circular(L.cardR),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: L.warnRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12, color: L.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 骨架屏 (TECH 05: 骨架屏)
class StatsSkeleton extends StatelessWidget {
  final int lines;
  const StatsSkeleton({super.key, this.lines = 4});

  @override
  Widget build(BuildContext context) {
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
          for (var i = 0; i < lines; i++)
            Container(
              height: 14,
              width: i.isEven ? 160 : 100,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: L.dividerLight,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
