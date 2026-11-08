// 统计 API 客户端契约测试 (v1.12.0)
//
// 用服务端 (server/app) 的真实响应 JSON 验证 Dart 解析层:
//   - summary: 嵌套 comparison 对象 + days 字段
//   - RankItem: category_id/tag_id 别名, ratio, progress 百分数字符串
//   - TagChart: chart/leaderboard 键
//   - BalanceRanking: 嵌套 summary
//   - TxPage: total (int 笔数) + total_amount (金额)
// JSON 样本来自 2026-11-08 对真实服务的抓包 (docs/acceptance-evidence 契约核对)。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_ledger/services/stats_api.dart';

void main() {
  group('StatsSummary.fromJson 服务端契约', () {
    test('基础字段 + 嵌套 comparison', () {
      const body = '''
      {"data":{"type":"expense","income":"0.00","expense":"10.00","balance":"-10.00",
        "balance_rate":null,"income_count":0,"expense_count":1,"days":8,
        "daily_average":"1.25",
        "comparison":{"amount":"10.00","comparison_amount":"0.00","difference":"10.00",
          "change_rate":null,"count":1,
          "income":{"amount":"0.00","comparison_amount":"0.00","difference":"0.00"},
          "expense":{"amount":"10.00","comparison_amount":"0.00","difference":"10.00"}}},
       "meta":{"snapshot_version":3784,"condition_key":"k","generated_at":"t"}}''';
      final s = StatsResponse.fromJson(
          jsonDecode(body) as Map<String, dynamic>, StatsSummary.fromJson);
      expect(s.data.expense, '10.00');
      expect(s.data.income, '0.00');
      expect(s.data.balance, '-10.00');
      expect(s.data.balanceRate, isNull);
      expect(s.data.dailyAverage, '1.25');
      expect(s.data.dailyAverageDays, 8, reason: '服务端字段是 days');
      expect(s.data.compareIncome, '0.00', reason: '嵌套 comparison.income.amount');
      expect(s.data.compareExpense, '10.00');
      expect(s.data.compareBalance, '0.00');
      expect(s.data.balanceDiff, '10.00');
      expect(s.data.balanceChangeRate, isNull);
      expect(s.meta.snapshotVersion, 3784);
    });
  });

  group('RankItem.fromJson 别名', () {
    test('分类榜条目: category_id / ratio / progress 百分数字符串', () {
      const j = {
        'category_id': 'cat_497',
        'parent_id': 'cat_497',
        'name': '餐饮',
        'amount': '10.00',
        'ratio': '100.00',
        'count': 1,
        'last_transaction_date': '2026-11-01',
        'progress': '100.00',
        'drilldown': {'book_id': 'b1'},
      };
      final r = RankItem.fromJson(j);
      expect(r.id, 'cat_497');
      expect(r.rate, '100.00');
      expect(r.progress, 1.0, reason: '百分数字符串归一到 0..1');
      expect(r.drillKey, isA<Map<String, dynamic>>());
    });

    test('标签榜条目: tag_id 别名 + 小数 progress', () {
      const j = {
        'tag_id': '未设置标签',
        'name': '未设置标签',
        'amount': '55.00',
        'ratio': '35.71',
        'count': 1,
        'progress': '35.71',
      };
      final r = RankItem.fromJson(j);
      expect(r.id, '未设置标签');
      expect(r.progress, closeTo(0.3571, 0.0001));
    });

    test('数字 progress 直接可用', () {
      const j = {'id': 'x', 'name': 'n', 'amount': '1.00', 'progress': 0.42};
      expect(RankItem.fromJson(j).progress, 0.42);
    });
  });

  group('榜单容器', () {
    test('CategoryRanking: total_amount', () {
      const j = {
        'total_amount': '10.00',
        'items': [
          {'category_id': 'c1', 'name': 'a', 'amount': '10.00'}
        ]
      };
      final c = CategoryRanking.fromJson(j);
      expect(c.total, '10.00');
      expect(c.items.single.name, 'a');
    });

    test('TagChart: chart + leaderboard', () {
      const j = {
        'total_amount': '100.00',
        'chart': [
          {'tag_id': 't1', 'name': '日常', 'amount': '60.00'}
        ],
        'leaderboard': [
          {'tag_id': 't1', 'name': '日常', 'amount': '60.00'},
          {'tag_id': '未设置标签', 'name': '未设置标签', 'amount': '40.00'},
        ],
      };
      final t = TagChart.fromJson(j);
      expect(t.slices.single.name, '日常');
      expect(t.ranking.length, 2);
      expect(t.total, '100.00');
    });

    test('MerchantRanking: counterparty_id 别名', () {
      const j = {
        'total_amount': '9.00',
        'items': [
          {'counterparty_id': 'cp1', 'name': '星巴克', 'amount': '9.00'}
        ]
      };
      expect(MerchantRanking.fromJson(j).items.single.id, 'cp1');
    });

    test('BalanceRanking: 嵌套 summary', () {
      const j = {
        'summary': {
          'income': '100.00',
          'expense': '10.00',
          'balance': '90.00',
          'balance_rate': '90.00'
        },
        'income_contribution': {
          'total_amount': '100.00',
          'items': [
            {'category_id': null, 'name': '未分类', 'amount': '100.00'}
          ]
        },
        'expense_impact': {
          'total_amount': '10.00',
          'items': [
            {'category_id': 'c1', 'name': '餐饮', 'amount': '10.00'}
          ]
        },
      };
      final b = BalanceRanking.fromJson(j);
      expect(b.incomeTotal, '100.00');
      expect(b.expenseTotal, '10.00');
      expect(b.balance, '90.00');
      expect(b.incomeContribution.items.single.name, '未分类');
      expect(b.expenseImpact.items.single.name, '餐饮');
    });
  });

  group('TrendPoint / TxPage', () {
    test('TrendPoint: 嵌套 comparison', () {
      const j = {
        'bucket_start': '2026-11-01',
        'bucket_end': '2026-11-01',
        'income': '0.00',
        'expense': '10.00',
        'balance': '-10.00',
        'comparison': {
          'income': '0.00',
          'expense': '0.00',
          'balance': '0.00',
        },
      };
      final p = TrendPoint.fromJson(j);
      expect(p.bucketStart, '2026-11-01');
      expect(p.compareExpense, '0.00');
    });

    test('TxPage: total(int 笔数) + total_amount(金额)', () {
      const j = {
        'total': 2,
        'page': 1,
        'total_amount': '110.00',
        'items': [
          {'id': 'tx1', 'amount': '100.00', 'transaction_date': '2026-11-02'},
          {'id': 'tx2', 'amount': '10.00', 'transaction_date': '2026-11-01'},
        ]
      };
      final p = TxPage.fromJson(j);
      expect(p.totalCount, 2, reason: '服务端 total 是笔数');
      expect(p.total, '110.00');
      expect(p.items.length, 2);
    });
  });
}
