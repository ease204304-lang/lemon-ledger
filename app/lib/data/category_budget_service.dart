/// 分类预算服务 (v1.13.0)
///
/// 对标同类 APP 的「分类预算 + 超支预警」:
///   - 按 (年, 月, 分类) 设置预算上限
///   - 超支 (已用 > 预算) / 预警 (已用 ≥ 80%) 两级状态
///   - 月度总预算沿用既有 budget 表 (BudgetService)
///
/// 状态口径:
///   none    — 未设预算
///   safe    — 已用 < 80%
///   warn    — 80% ≤ 已用 ≤ 100%
///   over    — 已用 > 100% (超支)
library;

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

/// 单个分类的预算执行情况
class CategoryBudgetStatus {
  final String categoryId;
  final int budgetCents; // 预算上限 (分)
  final int usedCents; // 已用 (分)

  const CategoryBudgetStatus({
    required this.categoryId,
    required this.budgetCents,
    required this.usedCents,
  });

  int get remainCents => budgetCents - usedCents;
  double get ratio => budgetCents == 0 ? 0 : usedCents / budgetCents;
  bool get isOver => budgetCents > 0 && usedCents > budgetCents;
  bool get isWarn => budgetCents > 0 && !isOver && ratio >= 0.8;

  /// 供 UI 展示的状态
  BudgetState get state {
    if (budgetCents <= 0) return BudgetState.none;
    if (isOver) return BudgetState.over;
    if (isWarn) return BudgetState.warn;
    return BudgetState.safe;
  }
}

enum BudgetState { none, safe, warn, over }

class CategoryBudgetService {
  static final CategoryBudgetService instance = CategoryBudgetService._();
  CategoryBudgetService._();

  /// 设置某月某分类的预算 (0 = 取消)
  Future<void> set(int year, int month, String categoryId, int amountCents) async {
    final db = await AppDatabase.instance.db;
    if (amountCents <= 0) {
      await remove(year, month, categoryId);
      return;
    }
    await db.insert(
      'category_budget',
      {
        'year': year,
        'month': month,
        'category_id': categoryId,
        'amount_cents': amountCents,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> remove(int year, int month, String categoryId) async {
    final db = await AppDatabase.instance.db;
    await db.delete('category_budget',
        where: 'year = ? AND month = ? AND category_id = ?',
        whereArgs: [year, month, categoryId]);
  }

  /// 某月设置过的全部分类预算 (含已用金额)
  Future<List<CategoryBudgetStatus>> statuses(int year, int month) async {
    final db = await AppDatabase.instance.db;
    final budgets = await db.query('category_budget',
        where: 'year = ? AND month = ?',
        whereArgs: [year, month]);
    if (budgets.isEmpty) return const [];

    // 一次性算出本月各分类支出 (避免 N+1 查询)
    final start = DateTime(year, month, 1).millisecondsSinceEpoch ~/ 86400000;
    final end = DateTime(year, month + 1, 0).millisecondsSinceEpoch ~/ 86400000;
    final usedRows = await db.rawQuery('''
      SELECT category_id, SUM(amount_cents) AS s
      FROM tx
      WHERE type = 0 AND epoch_day BETWEEN ? AND ?
      GROUP BY category_id
    ''', [start, end]);
    final used = <String, int>{
      for (final r in usedRows)
        r['category_id'] as String: (r['s'] as int?) ?? 0,
    };

    return budgets.map((b) {
      final cid = b['category_id'] as String;
      return CategoryBudgetStatus(
        categoryId: cid,
        budgetCents: (b['amount_cents'] as int?) ?? 0,
        usedCents: used[cid] ?? 0,
      );
    }).toList();
  }

  /// 某分类在某月的预算 (分), 0 = 未设
  Future<int> get(int year, int month, String categoryId) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'category_budget',
      columns: ['amount_cents'],
      where: 'year = ? AND month = ? AND category_id = ?',
      whereArgs: [year, month, categoryId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return rows.first['amount_cents'] as int;
  }

  /// 超支 / 预警的分类列表 (给首页或统计页提示)
  Future<List<CategoryBudgetStatus>> alerts(int year, int month) async {
    final list = await statuses(year, month);
    return list.where((s) => s.state == BudgetState.warn || s.state == BudgetState.over)
        .toList();
  }
}
