// 统计日期范围口径测试 (v1.12.0)
//
// PRD 03 + TECH 契约: 查询结束日不得晚于今天 (服务端返回 400 INVALID_FILTER)。
// 因此「本月」「本年」这类自然周期的结束日必须截断到今天, 而不是周期最后一天。
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_ledger/services/stats_api.dart';
import 'package:lemon_ledger/services/stats_controller.dart';

void main() {
  group('自然周期结束日不得晚于今天', () {
    test('本月: 1 日 → 今天', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.thisMonth);
      final r = c.dateRange;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(r.end, today, reason: '本月结束日必须是今天, 不能是本月最后一天');
      expect(r.start, DateTime(now.year, now.month, 1));
    });

    test('本年: 1/1 → 今天', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.thisYear);
      final r = c.dateRange;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(r.end, today);
      expect(r.start, DateTime(now.year, 1, 1));
    });

    test('上月: 完整已结束周期 (不受影响)', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.lastMonth);
      final r = c.dateRange;
      final now = DateTime.now();
      expect(r.start, DateTime(now.year, now.month - 1, 1));
      expect(r.end, DateTime(now.year, now.month, 0));
      expect(r.end.isBefore(DateTime(now.year, now.month, now.day)), isTrue,
          reason: '上月必须完全结束');
    });

    test('滚动范围: 结束日均为今天', () {
      final c = StatsController();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final q in [
        QuickRange.last7Days,
        QuickRange.last30Days,
        QuickRange.last90Days,
      ]) {
        c.setQuickRange(q);
        expect(c.dateRange.end, today, reason: '$q 结束日应为今天');
      }
    });
  });

  group('同期区间 (同进度对齐)', () {
    test('本月 → 上月同一天止', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.thisMonth);
      final prev = c.dateRange.previousRange();
      expect(prev, isNotNull);
      final now = DateTime.now();
      expect(prev!.start, DateTime(now.year, now.month - 1, 1));
      expect(prev.end.day, c.dateRange.end.day,
          reason: '同期应按同进度对齐 (同一天)');
      expect(prev.end.isBefore(DateTime(now.year, now.month, 1)), isTrue,
          reason: '同期区间必须完全在上月内');
    });

    test('本年 → 去年同一天止', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.thisYear);
      final prev = c.dateRange.previousRange();
      expect(prev, isNotNull);
      final now = DateTime.now();
      expect(prev!.start, DateTime(now.year - 1, 1, 1));
      expect(prev.end.month, c.dateRange.end.month);
      expect(prev.end.day, c.dateRange.end.day);
    });

    test('滚动范围 → 紧邻等长历史周期', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.last30Days);
      final cur = c.dateRange;
      final prev = cur.previousRange()!;
      expect(prev.days, cur.days, reason: '等长');
      expect(prev.end.isBefore(cur.start), isTrue,
          reason: '紧邻且不重叠');
    });
  });

  group('粒度规则 (PRD 03)', () {
    test('≤31 天按天, 32–365 天按周, >365 天按月', () {
      final c = StatsController();
      c.setQuickRange(QuickRange.last7Days);
      expect(c.dateRange.granularity, TrendGranularity.day);
      c.setQuickRange(QuickRange.last90Days);
      expect(c.dateRange.granularity, TrendGranularity.week);
    });

    test('>365 天按月 (自定义跨年区间)', () {
      final c = StatsController();
      final now = DateTime.now();
      final ok = c.setCustomRange(
          DateTime(now.year - 1, now.month, now.day),
          DateTime(now.year, now.month, now.day));
      expect(ok, isTrue);
      expect(c.dateRange.granularity, TrendGranularity.month);
    });
  });

  group('自定义区间校验', () {
    test('起始晚于结束 → 拒绝', () {
      final c = StatsController();
      final now = DateTime.now();
      final ok = c.setCustomRange(
          DateTime(now.year, now.month, 10), DateTime(now.year, now.month, 5));
      expect(ok, isFalse);
    });

    test('未来日期 → 拒绝', () {
      final c = StatsController();
      final now = DateTime.now();
      final ok = c.setCustomRange(
          DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 5));
      expect(ok, isFalse);
    });

    test('合法区间 → 接受并切到自定义', () {
      final c = StatsController();
      final now = DateTime.now();
      final ok = c.setCustomRange(
          DateTime(now.year, now.month, 1), DateTime(now.year, now.month, 2));
      expect(ok, isTrue);
      expect(c.quickRange, QuickRange.custom);
    });
  });
}
