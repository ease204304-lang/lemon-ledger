// 黄金数据集与核心算法验证
//
// 关键不变量（与 docs/00-基线与术语.md §7、§8、§12.2 一致）：
//   - 9 个分类占比合计 = 100% (允许 0.1% 误差)
//   - 平均 = 周期总额 / 已过天数 = 2281.00 / 5 = 456.20
//   - 7 日点值 = [1045.00, 152.00, 97.00, 53.00, 934.00, 0, 0]
//   - 9 分类比例与原型一致
//   - 总收入 = 50.00
//   - 总支出 = 2281.00 (10-05..10-09, 仅种子 18 笔)

import 'package:flutter_test/flutter_test.dart';

import 'package:lemon_ledger/data/seed.dart';
import 'package:lemon_ledger/data/models.dart';

void main() {
  group('Seed data invariants', () {
    final txs = seedTxs();
    final cats = seedCategories();

    int sumByType(TxType t) =>
        txs.where((x) => x.type == t).fold<int>(0, (s, x) => s + x.amountCents);

    test('总支出 = 2281.00, 总收入 = 50.00 (10-05..10-09, 仅种子 18 笔)', () {
      expect(sumByType(TxType.expense), equals(228100));
      expect(sumByType(TxType.income),  equals(5000));
    });

    test('平均 = 2281.00 / 5 = 456.20', () {
      final exp = sumByType(TxType.expense);
      final avg = exp ~/ 5;
      expect(avg, equals(45620));
    });

    test('7 日点值 = 1045/152/97/53/934/0/0 (cents)', () {
      const day0 = 20731; // 2026-10-05
      const List<int> expected = [104500, 15200, 9700, 5300, 93400, 0, 0];
      final List<int> actual = List<int>.generate(7, (i) {
        final d = day0 + i;
        return txs.where((x) => x.type == TxType.expense && x.epochDay == d)
            .fold<int>(0, (s, x) => s + x.amountCents);
      });
      expect(actual, equals(expected));
    });

    test('9 分类金额 = 与基线 §7 实测一致 (5/100/200/100/100/100/200/100/50 元级)', () {
      final byCat = <String, int>{};
      for (final t in txs) {
        if (t.type != TxType.expense) continue;
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountCents;
      }
      final expected = <String, int>{
        'cat.invest_exp':81800,  // v6: 支出投资 (原 cat.invest)
        'cat.daily':    59000,
        'cat.transport':47600,  // 162+152+97+3+62
        'cat.food':     14300,  // 59+53+15+9+咖啡7
        'cat.kid':       9900,
        'cat.travel':    8000,
        'cat.medical':   5500,
        'cat.car':       2000,  // 5+15
      };
      // 排序后比较
      final a = (byCat.entries.toList()..sort((x, y) => x.key.compareTo(y.key)));
      final b = (expected.entries.toList()..sort((x, y) => x.key.compareTo(y.key)));
      for (var i = 0; i < a.length; i++) {
        expect(a[i].key,   equals(b[i].key));
        expect(a[i].value, equals(b[i].value));
      }
      // 合计
      final sum = byCat.values.fold<int>(0, (s, v) => s + v);
      expect(sum, equals(228100));
    });

    test('9 分类百分比合计 = 100.0% (允许 0.1% 误差)', () {
      final byCat = <String, int>{};
      for (final t in txs) {
        if (t.type != TxType.expense) continue;
        byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountCents;
      }
      final total = byCat.values.fold<int>(0, (s, v) => s + v);
      double pct(int v) => total == 0 ? 0 : v * 100.0 / total;
      final sum = byCat.values.map(pct).fold<double>(0, (s, v) => s + v);
      expect(sum, closeTo(100.0, 0.1));
    });

    test('seed 包含 14 支出 + 8 收入 分类 (v6 按用户清单重整)', () {
      expect(cats.where((c) => c.type == TxType.expense).length, equals(14));
      expect(cats.where((c) => c.type == TxType.income).length, equals(8));
    });

    test('v6 支出分类名 = 用户清单顺序', () {
      final names = cats
          .where((c) => c.type == TxType.expense)
          .map((c) => c.name)
          .toList();
      expect(names, equals([
        '信用卡', '餐饮', '娱乐', '零食', '交通', '住房', '旅游',
        '医疗', '运动', '汽车', '孩子', '日用', '投资', '其他',
      ]));
    });
  });

  group('模型换算', () {
    test('cents ↔ 元', () {
      final t = Tx(
        id: 't', epochDay: 0, type: TxType.expense,
        categoryId: 'cat.food', amountCents: 12345,
        note: '', createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(t.amountYuan, closeTo(123.45, 1e-9));
    });

    test('toMap/fromMap 往返一致', () {
      final t = Tx(
        id: 'id', epochDay: 100, type: TxType.income,
        categoryId: 'cat.salary', amountCents: 50000,
        note: '工资', createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final back = Tx.fromMap(t.toMap());
      expect(back.id, equals(t.id));
      expect(back.epochDay, equals(t.epochDay));
      expect(back.type, equals(t.type));
      expect(back.amountCents, equals(t.amountCents));
      expect(back.note, equals(t.note));
    });
  });
}
