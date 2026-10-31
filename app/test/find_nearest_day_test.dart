// _findNearestDay 算法测试 (v1.4.0 新增)
// 当用户在 DatePicker 选了一个无数据的日, 应跳到最近的有数据的日.

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 算法副本 (必须与 home_page.dart 中 _findNearestDay 保持一致)
  int? findNearest(int target, List<int> days) {
    if (days.isEmpty) return null;
    if (days.contains(target)) return target;
    int lo = 0, hi = days.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (days[mid] < target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final before = lo > 0 ? days[lo - 1] : null;
    final after = lo < days.length ? days[lo] : null;
    if (before == null) return after;
    if (after == null) return before;
    return (target - before) <= (after - target) ? before : after;
  }

  group('_findNearestDay 行为', () {
    test('空列表返回 null', () {
      expect(findNearest(10, const []), isNull);
    });

    test('target 在列表中 → 返回 target', () {
      expect(findNearest(15, [5, 10, 15, 20, 25]), equals(15));
    });

    test('target 介于两个值, 更近前一个', () {
      // target=12, days=[10,15,20] → 10 (距离 2 vs 3)
      expect(findNearest(12, [10, 15, 20]), equals(10));
    });

    test('target 介于两个值, 更近后一个', () {
      // target=13, days=[10,15,20] → 15 (距离 2 vs 3)
      expect(findNearest(13, [10, 15, 20]), equals(15));
    });

    test('target 比所有 day 大 → 返回最大', () {
      expect(findNearest(100, [10, 20, 30]), equals(30));
    });

    test('target 比所有 day 小 → 返回最小', () {
      expect(findNearest(1, [10, 20, 30]), equals(10));
    });

    test('距离相等时返回前一个 (因 <=)', () {
      // target=15, days=[10,20] → 距离都是 5, 返回 10
      expect(findNearest(15, [10, 20]), equals(10));
    });

    test('实际场景: 种子数据 10-05..10-09, 选 10-12 → 跳到 10-09', () {
      // 种子 epochDay: 20731(10-05) ~ 20735(10-09)
      // 10-12 = 20738
      const days = [20731, 20732, 20733, 20734, 20735];
      expect(findNearest(20738, days), equals(20735));
    });

    test('实际场景: 选 10-03 → 跳到 10-05', () {
      // 10-03 = 20729
      const days = [20731, 20732, 20733, 20734, 20735];
      expect(findNearest(20729, days), equals(20731));
    });

    test('实际场景: 选 10-07 → 跳到 10-07 (正好有)', () {
      // 10-07 = 20733
      const days = [20731, 20732, 20733, 20734, 20735];
      expect(findNearest(20733, days), equals(20733));
    });
  });
}
