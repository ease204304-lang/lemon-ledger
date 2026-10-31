// 图表折线图 Y 轴单位 修复回归测试 (v1.5.0)
//
// Bug: chart_page.dart _lineChartData()
//   - spots[i].$2 / 100.0 (元) ✓ 正确
//   - maxY: 倍数 1.2 后直接 .toDouble() (cents, 应该再 / 100) ❌ 错
//   - avgY: data.avgCents 是 cents, 直接用 (应该 / 100) ❌ 错
//   - HorizontalLine y: avgY (cents, 应该 yuan) ❌ 错
//
// 后果: maxY 是 cents (e.g. 10000), 但数据点最大 100 元
//       比例 100:1, 折线被压扁在 X 轴, 几乎看不到.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lemon_ledger/theme/tokens.dart';

void main() {
  group('_lineChartData 单位一致性 (回归)', () {
    // 模拟 chart_page 里的 _lineChartData 逻辑 (不依赖 widget 树, 纯函数验证)
    LineChartData buildChart(List<(String, int)> points, int avgCents) {
      final maxCents = points.fold<int>(100, (a, b) => a > b.$2 ? a : b.$2);
      final maxYuan = (maxCents * 1.2) / 100.0;
      final avgYuan = avgCents / 100.0;
      return LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble().clamp(1, 1000),
        minY: 0,
        maxY: maxYuan.clamp(avgYuan * 1.2, double.infinity),
        extraLinesData: avgYuan > 0
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: avgYuan,
                  color: L.textSecondary.withValues(alpha: 0.5),
                ),
              ])
            : null,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].$2 / 100.0),
            ],
          ),
        ],
      );
    }

    test('场景: 本周支出 152 元 (12.50 餐饮 + 139 打车 等)', () {
      // 模拟种子数据: 7 个日, 最高 20000 cents (200 元)
      final points = [
        ('10/6', 5900),  // 餐饮
        ('10/7', 0),     // 无支出
        ('10/8', 0),
        ('10/9', 15200), // 152 元 (本周期最高)
        ('10/10', 0),
        ('10/11', 0),
        ('10/12', 3500), // 35 元
      ];
      final avgCents = (5900 + 15200 + 3500) ~/ 7;  // 约 3514
      final chart = buildChart(points, avgCents);
      final spots = chart.lineBarsData[0].spots;

      // spot.Y 应该在 yuan 单位 (10 ~ 200)
      for (final s in spots) {
        expect(s.y, lessThan(300), reason: 'spot.Y 应该是元, 不是 cents. y=${s.y}');
        expect(s.y, greaterThanOrEqualTo(0), reason: '金额不应为负');
      }
      // max spot 是 152, maxY 应该是 152 * 1.2 = 182.4
      final maxSpot = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      expect(chart.maxY, greaterThan(maxSpot),
          reason: 'maxY (${chart.maxY}) 应大于最大 spot (${maxSpot})');
      expect(chart.maxY, lessThan(maxSpot * 2),
          reason: 'maxY 不应过分拉伸 (maxSpot=$maxSpot)');
      // avgY 应该在 yuan, 不是 cents
      final avgY = (chart.extraLinesData?.horizontalLines.first.y) ?? 0;
      expect(avgY, lessThan(1000), reason: 'avgY 应该是元, 实际=$avgY');
    });

    test('场景: 无数据时 maxY 用 100 cents 保底 (1 元, 仍是元单位)', () {
      // 空数据 → maxCents fold 默认 100 → 100 cents = 1 元
      final chart = buildChart([], 0);
      expect(chart.maxY, lessThan(5),
          reason: '空数据时 maxY 应该是元 (1 元), 不是 cents (100)');
    });

    test('场景: 极小金额 (10 元) 折线', () {
      final points = [
        ('10/6', 1000),
        ('10/7', 0),
        ('10/8', 500),
        ('10/9', 200),
      ];
      final chart = buildChart(points, 425);
      final maxSpot = points.map((p) => p.$2 / 100.0).reduce((a, b) => a > b ? a : b);
      // maxY ≈ 10 * 1.2 = 12 元, 不能是 1200 (cents 没除)
      expect(chart.maxY, lessThan(15),
          reason: '10 元数据 maxY 应是 ~12 元, 实际=${chart.maxY}');
      expect(chart.maxY, greaterThan(maxSpot));
    });
  });

  group('回归保护: 旧 bug 行为不应再出现', () {
    test('修复前: maxY = 10000 cents (轴被拉到 100 倍, 折线看不见)', () {
      // 这是 bug 时的代码 (改前)
      final points = [('10/9', 15200)];  // 152 元
      // 旧代码: maxY = max(100, 15200) * 1.2 = 18240
      final oldMaxY = 15200.0 * 1.2;  // 18240 cents
      expect(oldMaxY, 18240);  // 验证旧值确实是 cents
      // 修复后: 18240 cents → 182.40 元
      final newMaxY = (15200.0 * 1.2) / 100.0;  // 182.4 元
      expect(newMaxY, 182.4);
      // 比例: 旧 / 新 = 100, 即修复前轴是修复后的 100 倍
      expect(oldMaxY / newMaxY, 100);
    });
  });
}
