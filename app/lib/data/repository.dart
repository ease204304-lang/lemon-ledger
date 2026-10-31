/// 仓储层
///
/// 提供流水与分类的 CRUD 与统计查询。
/// 业务口径与基线 §7 一致: 平均 = 周期总额 / 已过天数。
library repository;

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

class TxRepository {
  static final TxRepository instance = TxRepository._();
  TxRepository._();

  Future<List<Tx>> all() async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('tx', orderBy: 'epoch_day DESC, created_at DESC');
    return rows.map(Tx.fromMap).toList();
  }

  Future<List<Tx>> byDateRange(int startDay, int endDay) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'tx',
      where: 'epoch_day BETWEEN ? AND ?',
      whereArgs: [startDay, endDay],
      orderBy: 'epoch_day DESC, created_at DESC',
    );
    return rows.map(Tx.fromMap).toList();
  }

  Future<Tx?> byId(String id) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('tx', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Tx.fromMap(rows.first);
  }

  Future<void> insert(Tx t) async {
    final db = await AppDatabase.instance.db;
    await db.insert('tx', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(Tx t) async {
    final db = await AppDatabase.instance.db;
    await db.update('tx', t.toMap(), where: 'id = ?', whereArgs: [t.id]);
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.instance.db;
    await db.delete('tx', where: 'id = ?', whereArgs: [id]);
  }

  /// 按 [day] 当天的所有流水（按 created_at 升序）
  Future<List<Tx>> byDay(int day) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('tx',
        where: 'epoch_day = ?',
        whereArgs: [day],
        orderBy: 'created_at ASC');
    return rows.map(Tx.fromMap).toList();
  }

  /// 周期内的合计，单位：分
  /// 返回 (expenseCents, incomeCents)
  Future<(int, int)> sumByRange(int startDay, int endDay) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT type, SUM(amount_cents) AS s
      FROM tx
      WHERE epoch_day BETWEEN ? AND ?
      GROUP BY type
    ''', [startDay, endDay]);
    int exp = 0, inc = 0;
    for (final r in rows) {
      final t = TxType.values[(r['type'] as int)];
      final s = (r['s'] as int?) ?? 0;
      if (t == TxType.expense) exp = s;
      if (t == TxType.income)  inc = s;
    }
    return (exp, inc);
  }

  /// 按 [type] 在周期内按分类汇总。返回: catId -> cents
  Future<Map<String, int>> sumByCategory(
      TxType type, int startDay, int endDay) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT category_id, SUM(amount_cents) AS s
      FROM tx
      WHERE type = ? AND epoch_day BETWEEN ? AND ?
      GROUP BY category_id
    ''', [type.index, startDay, endDay]);
    final out = <String, int>{};
    for (final r in rows) {
      out[r['category_id'] as String] = (r['s'] as int?) ?? 0;
    }
    return out;
  }

  /// 周期内每天的支出合计。返回: 7 个整数（含 0），与基线 §7 实测表一致
  Future<List<int>> dailyExpense7(int startDay) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT epoch_day, SUM(amount_cents) AS s
      FROM tx
      WHERE type = ? AND epoch_day BETWEEN ? AND ?
      GROUP BY epoch_day
      ORDER BY epoch_day ASC
    ''', [TxType.expense.index, startDay, startDay + 6]);
    final byDay = <int, int>{};
    for (final r in rows) {
      byDay[r['epoch_day'] as int] = (r['s'] as int?) ?? 0;
    }
    return List<int>.generate(7, (i) => byDay[startDay + i] ?? 0);
  }

  /// 任意起止范围的支出 (按日聚合, 不含 0 日)
  /// 返回: [(epochDay, amountCents)] 按日期升序
  Future<List<(int, int)>> dailyAmounts(
    TxType type,
    int startDay,
    int endDay,
  ) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT epoch_day, SUM(amount_cents) AS s
      FROM tx
      WHERE type = ? AND epoch_day BETWEEN ? AND ?
      GROUP BY epoch_day
      ORDER BY epoch_day ASC
    ''', [type.index, startDay, endDay]);
    return rows
        .map((r) => (r['epoch_day'] as int, (r['s'] as int?) ?? 0))
        .toList();
  }

  /// 周/月/年期间的折线图数据
  /// granularity: 日 (周/月) / 月 (年)
  /// 返回: [(label, amountCents)] 按时间升序
  Future<List<(String, int)>> groupedAmounts(
    TxType type,
    int fromDay,
    int toDay,
    ChartGranularity granularity,
  ) async {
    // 折线图: 按 granularity 聚合
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT epoch_day, amount_cents
      FROM tx
      WHERE type = ? AND epoch_day BETWEEN ? AND ?
      ORDER BY epoch_day ASC
    ''', [type.index, fromDay, toDay]);
    final Map<String, int> buckets = {};
    for (final r in rows) {
      final day = r['epoch_day'] as int;
      final amt = (r['amount_cents'] as int?) ?? 0;
      final dt = _epochDayToDate(day);
      final key = switch (granularity) {
        ChartGranularity.day => '${dt.month}/${dt.day}',
        ChartGranularity.month => '${dt.year}-${_2(dt.month)}',
      };
      buckets[key] = (buckets[key] ?? 0) + amt;
    }
    return buckets.entries.map((e) => (e.key, e.value)).toList();
  }

  /// 分类汇总 + 上期对比 (用于图表排行)
  /// 返回: [(categoryId, currentCents, prevCents)]
  /// currentFrom/currentTo: 本期
  /// prevFrom/prevTo: 上期
  Future<List<(String, int, int)>> categoryAmountsWithPrev(
    TxType type,
    int currentFrom,
    int currentTo,
    int prevFrom,
    int prevTo,
  ) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT category_id, epoch_day, amount_cents
      FROM tx
      WHERE type = ? AND (
        (epoch_day BETWEEN ? AND ?) OR
        (epoch_day BETWEEN ? AND ?)
      )
      ORDER BY category_id, epoch_day ASC
    ''', [type.index, currentFrom, currentTo, prevFrom, prevTo]);
    // Map: categoryId -> {current, prev}
    final Map<String, Map<String, int>> map = {};
    for (final r in rows) {
      final cid = r['category_id'] as String;
      final day = r['epoch_day'] as int;
      final amt = (r['amount_cents'] as int?) ?? 0;
      map.putIfAbsent(cid, () => {'current': 0, 'prev': 0});
      if (day >= currentFrom && day <= currentTo) {
        map[cid]!['current'] = (map[cid]!['current'] ?? 0) + amt;
      } else {
        map[cid]!['prev'] = (map[cid]!['prev'] ?? 0) + amt;
      }
    }
    return map.entries
        .map((e) => (e.key, e.value['current'] ?? 0, e.value['prev'] ?? 0))
        .toList();
  }

  /// 月度汇总: 收入 / 支出, 单位: 分
  Future<(int, int)> sumByMonth(int year, int month) async {
    final db = await AppDatabase.instance.db;
    final start = _dateToEpochDay(DateTime(year, month, 1));
    final end = _dateToEpochDay(DateTime(year, month + 1, 0));
    final rows = await db.rawQuery('''
      SELECT type, SUM(amount_cents) AS s
      FROM tx
      WHERE epoch_day BETWEEN ? AND ?
      GROUP BY type
    ''', [start, end]);
    int exp = 0, inc = 0;
    for (final r in rows) {
      final t = TxType.values[(r['type'] as int)];
      final s = (r['s'] as int?) ?? 0;
      if (t == TxType.expense) exp = s;
      if (t == TxType.income)  inc = s;
    }
    return (exp, inc);
  }

  /// 月内有数据的日期集合: 返回 epochDay -> (expense, income) 总额
  Future<Map<int, (int, int)> > monthDayTotals(int year, int month) async {
    final db = await AppDatabase.instance.db;
    final start = _dateToEpochDay(DateTime(year, month, 1));
    final end = _dateToEpochDay(DateTime(year, month + 1, 0));
    final rows = await db.rawQuery('''
      SELECT epoch_day, type, SUM(amount_cents) AS s
      FROM tx
      WHERE epoch_day BETWEEN ? AND ?
      GROUP BY epoch_day, type
    ''', [start, end]);
    final out = <int, (int, int)>{};
    for (final r in rows) {
      final d = r['epoch_day'] as int;
      final t = TxType.values[(r['type'] as int)];
      final s = (r['s'] as int?) ?? 0;
      final cur = out[d] ?? (0, 0);
      out[d] = t == TxType.expense
          ? (cur.$1 + s, cur.$2)
          : (cur.$1, cur.$2 + s);
    }
    return out;
  }

  /// 月内某类型所有流水 (排行页用)
  Future<List<Tx>> monthTxs(int year, int month, TxType type) async {
    final db = await AppDatabase.instance.db;
    final start = _dateToEpochDay(DateTime(year, month, 1));
    final end = _dateToEpochDay(DateTime(year, month + 1, 0));
    final rows = await db.query(
      'tx',
      where: 'type = ? AND epoch_day BETWEEN ? AND ?',
      whereArgs: [type.index, start, end],
      orderBy: 'amount_cents DESC',
    );
    return rows.map(Tx.fromMap).toList();
  }

  /// 最近同分类的备注 (推荐 tag)
  Future<List<String>> recentNotes(String categoryId, {int limit = 5}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT DISTINCT note FROM tx
      WHERE category_id = ? AND note != ''
      ORDER BY created_at DESC
      LIMIT ?
    ''', [categoryId, limit * 3]);
    // 去重
    final out = <String>[];
    final seen = <String>{};
    for (final r in rows) {
      final n = (r['note'] as String).trim();
      if (n.isNotEmpty && !seen.contains(n)) {
        out.add(n);
        seen.add(n);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// 搜索: 按 note LIKE 匹配 + 分类名 LIKE 匹配
  Future<List<Tx>> search(String keyword, {int? fromDay, int? toDay}) async {
    final db = await AppDatabase.instance.db;
    final k = '%${keyword.trim()}%';
    final range = (fromDay != null && toDay != null)
        ? 'AND tx.epoch_day BETWEEN ? AND ?'
        : '';
    final args = <Object?>[k];
    if (fromDay != null) args.add(fromDay);
    if (toDay != null)   args.add(toDay);
    final rows = await db.rawQuery('''
      SELECT tx.* FROM tx
      LEFT JOIN category ON tx.category_id = category.id
      WHERE (tx.note LIKE ? OR category.name LIKE ?)
      $range
      ORDER BY tx.epoch_day DESC, tx.created_at DESC
    ''', [k, k, ...args]);
    return rows.map(Tx.fromMap).toList();
  }

  /// 列出某月内全部有数据的日期（仅日期, 倒序）
  Future<List<int>> daysWithDataInMonth(int year, int month) async {
    final db = await AppDatabase.instance.db;
    final start = _dateToEpochDay(DateTime(year, month, 1));
    final end = _dateToEpochDay(DateTime(year, month + 1, 0));
    final rows = await db.rawQuery('''
      SELECT DISTINCT epoch_day FROM tx
      WHERE epoch_day BETWEEN ? AND ?
      ORDER BY epoch_day DESC
    ''', [start, end]);
    return rows.map((r) => r['epoch_day'] as int).toList();
  }
}

int _dateToEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        86400000;

DateTime _epochDayToDate(int day) {
  final ms = day * 86400000;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

String _2(int v) => v < 10 ? '0$v' : '$v';

/// 图表折线图粒度
enum ChartGranularity { day, month }


class CategoryRepository {
  static final CategoryRepository instance = CategoryRepository._();
  CategoryRepository._();

  Future<List<Category>> all({bool includeArchived = false}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'category',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'type ASC, sort_order ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> byType(TxType t) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'category',
      where: 'type = ? AND archived = 0',
      whereArgs: [t.index],
      orderBy: 'sort_order ASC',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<Category?> byId(String id) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('category', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Category.fromMap(rows.first);
  }

  Future<void> insert(Category c) async {
    final db = await AppDatabase.instance.db;
    await db.insert('category', c.toMap());
  }

  Future<void> archive(String id) async {
    final db = await AppDatabase.instance.db;
    await db.update('category', {'archived': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
