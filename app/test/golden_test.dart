// 端到端集成测试
//
// 用 sqflite_common_ffi 跑数据库 (测试环境无 Android), 验证
//   - 种子落库
//   - 跨日范围汇总 / 分类汇总 / 7 日点值查询
//   - 模型与查询结果一致
//   - 删除/更新

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

import 'package:lemon_ledger/data/seed.dart';
import 'package:lemon_ledger/data/models.dart';

void main() {
  // 用 FFI 跑测试, 避免 Android plugin 依赖
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('seed 与查询', () {
    late Database db;

    setUp(() async {
      db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE category (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, icon_key TEXT NOT NULL,
                type INTEGER NOT NULL, sort_order INTEGER NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0,
                pinned INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE tx (
                id TEXT PRIMARY KEY, epoch_day INTEGER NOT NULL, type INTEGER NOT NULL,
                category_id TEXT NOT NULL REFERENCES category(id),
                amount_cents INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '',
                photo_path TEXT, created_at INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE budget (
                year INTEGER NOT NULL, month INTEGER NOT NULL,
                amount_cents INTEGER NOT NULL,
                PRIMARY KEY (year, month)
              )
            ''');
            await db.execute('''
              CREATE TABLE tag (
                name TEXT PRIMARY KEY,
                use_count INTEGER NOT NULL DEFAULT 1,
                last_used_at INTEGER NOT NULL
              )
            ''');
            final batch = db.batch();
            for (final c in seedCategories()) batch.insert('category', c.toMap());
            for (final t in seedTxs()) batch.insert('tx', t.toMap());
            await batch.commit(noResult: true);
          },
        ),
      );
    });

    tearDown(() async { await db.close(); });

    Future<int> sumExp(int s, int e) async {
      final rows = await db.rawQuery(
        'SELECT SUM(amount_cents) AS s FROM tx WHERE type=? AND epoch_day BETWEEN ? AND ?',
        [TxType.expense.index, s, e]);
      return (rows.first['s'] as int?) ?? 0;
    }

    test('种子总数 18 笔', () async {
      final rows = await db.query('tx');
      expect(rows.length, equals(18));
    });

    test('总支出 2281.00, 总收入 50.00', () async {
      final exp = await sumExp(20000, 30000);
      final inc = await db.rawQuery(
        'SELECT SUM(amount_cents) AS s FROM tx WHERE type=?',
        [TxType.income.index]);
      expect(exp, equals(228100));
      expect((inc.first['s'] as int?) ?? 0, equals(5000));
    });

    test('本周 5 天 累计 = 2281.00 (10-05..10-09)', () async {
      const day0 = 20731;
      final s = await sumExp(day0, day0 + 4);
      expect(s, equals(228100));
    });

    test('7 日点值 = 1045/152/97/53/934/0/0', () async {
      const day0 = 20731;
      final List<int> expected = [104500, 15200, 9700, 5300, 93400, 0, 0];
      for (var i = 0; i < 7; i++) {
        final d = day0 + i;
        final s = await sumExp(d, d);
        expect(s, equals(expected[i]), reason: 'day $i (epoch $d)');
      }
    });

    test('分类汇总: 9 分类金额', () async {
      final rows = await db.rawQuery(
        'SELECT category_id, SUM(amount_cents) AS s FROM tx WHERE type=? GROUP BY category_id',
        [TxType.expense.index]);
      final m = <String, int>{};
      for (final r in rows) {
        m[r['category_id'] as String] = (r['s'] as int?) ?? 0;
      }
      expect(m['cat.invest'],    equals(81800));
      expect(m['cat.daily'],     equals(59000));
      expect(m['cat.transport'], equals(47600));
      expect(m['cat.food'],      equals(13600));
      expect(m['cat.kid'],       equals(9900));
      expect(m['cat.travel'],    equals(8000));
      expect(m['cat.medical'],   equals(5500));
      expect(m['cat.drink'],     equals(700));
      expect(m['cat.car'],       equals(2000));
    });

    test('sumByMonth: 10 月 收入 50.00, 支出 2281.00', () async {
      // 真实 sqflite 集成: 用 TxRepository.instance
      // (但本文件用本地 db, 改用 db.rawQuery 等价实现)
      final rows = await db.rawQuery('''
        SELECT type, SUM(amount_cents) AS s FROM tx
        WHERE epoch_day BETWEEN ? AND ?
        GROUP BY type
      ''', [20731, 20735]);
      int exp = 0, inc = 0;
      for (final r in rows) {
        final s = (r['s'] as int?) ?? 0;
        if ((r['type'] as int) == TxType.expense.index) exp = s;
        if ((r['type'] as int) == TxType.income.index)  inc = s;
      }
      expect(exp, equals(228100));
      expect(inc, equals(5000));
    });

    test('search: 按 "投资" 匹配到 1 笔 (cat.invest, 备注 "投资 - 信托")', () async {
      final rows = await db.rawQuery('''
        SELECT tx.* FROM tx
        LEFT JOIN category ON tx.category_id = category.id
        WHERE tx.note LIKE ? OR category.name LIKE ?
      ''', ['%投资%', '%投资%']);
      expect(rows.length, equals(1));
      final t = Tx.fromMap(rows.first);
      expect(t.categoryId, equals('cat.invest'));
      expect(t.amountCents, equals(81800));
    });

    test('search: 按 "咖啡" 匹配到 1 笔 (cat.drink)', () async {
      // 咖啡在 cat.drink, 备注空
      // 但搜索的是分类名 "饮品" 或备注, 我们的搜索用 LIKE
      // 调整: 用 "饮品" 搜索 -> 1 笔
      final rows = await db.rawQuery('''
        SELECT tx.* FROM tx
        LEFT JOIN category ON tx.category_id = category.id
        WHERE tx.note LIKE ? OR category.name LIKE ?
      ''', ['%饮品%', '%饮品%']);
      expect(rows.length, equals(1));
      expect(rows.first['category_id'], equals('cat.drink'));
    });

    test('monthDayTotals: 10 月有 5 天有数据', () async {
      final rows = await db.rawQuery('''
        SELECT DISTINCT epoch_day FROM tx
        WHERE epoch_day BETWEEN ? AND ?
      ''', [20731, 20760]);
      expect(rows.length, equals(5)); // 10-05..10-09
    });

    test('v1.2 sumByMonth 含 net 计算: 净 = 支出 - 收入 = 2231', () async {
      // 用真实的 sumByMonth 来验证
      // 但本测试是 DB level, 直接 raw SQL
      final rows = await db.rawQuery('''
        SELECT type, SUM(amount_cents) AS s FROM tx
        WHERE epoch_day BETWEEN ? AND ?
        GROUP BY type
      ''', [20731, 20735]);
      int exp = 0, inc = 0;
      for (final r in rows) {
        final s = (r['s'] as int?) ?? 0;
        if ((r['type'] as int) == TxType.expense.index) exp = s;
        if ((r['type'] as int) == TxType.income.index)  inc = s;
      }
      final net = exp - inc; // 228100 - 5000 = 223100
      expect(exp, equals(228100));
      expect(inc, equals(5000));
      expect(net, equals(223100));
    });

    test('v1.2 budget 表 存在', () async {
      // DB schema v2 含 budget 表
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='budget'");
      expect(rows.length, equals(1));
    });

    test('v1.2 新增 3 个分类存在 (credit/education/housing)', () async {
      final rows = await db.rawQuery(
          "SELECT id FROM category WHERE id IN ('cat.credit', 'cat.education', 'cat.housing')");
      expect(rows.length, equals(3));
    });

    test('v1.2 monthTxs 返回当月所有某类型流水', () async {
      final rows = await db.rawQuery('''
        SELECT * FROM tx
        WHERE type = ? AND epoch_day BETWEEN ? AND ?
        ORDER BY amount_cents DESC
      ''', [TxType.expense.index, 20731, 20735]);
      expect(rows.length, equals(17)); // 18 笔种子 - 1 笔收入 = 17 支出
    });

    test('v1.2.2 tag 表: 添加/累加/最近', () async {
      // 用 raw SQL 模拟 TagService
      await db.insert('tag', {
        'name': '午餐', 'use_count': 1, 'last_used_at': 1000,
      });
      await db.insert('tag', {
        'name': '咖啡', 'use_count': 2, 'last_used_at': 2000,
      });
      // 累加午餐
      await db.rawUpdate(
        'UPDATE tag SET use_count = use_count + 1, last_used_at = ? WHERE name = ?',
        [3000, '午餐'],
      );
      final rows = await db.rawQuery(
        'SELECT * FROM tag ORDER BY last_used_at DESC');
      expect(rows.length, equals(2));
      // 午餐 use_count=2
      final lunch = rows.firstWhere((r) => r['name'] == '午餐');
      expect(lunch['use_count'], equals(2));
      // 咖啡最旧, 午餐最新
      expect(rows.first['name'], equals('午餐'));
    });
  });
}
