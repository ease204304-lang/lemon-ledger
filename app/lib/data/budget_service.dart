/// 预算服务
///
/// 月预算: (year, month) → amount_cents
/// 日均预算: amount_cents / 当月天数
/// 净支出 = 当日支出 - 当日收入
/// 红/绿判定: 净 > 日均 → 红, 净 <= 日均 → 绿 (含 0 与节余)
library;

import 'package:sqflite/sqflite.dart';

import 'database.dart';

class BudgetService {
  static final BudgetService instance = BudgetService._();
  BudgetService._();

  /// 获取某月预算 (分). 不存在返回 0.
  Future<int> get(int year, int month) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query(
      'budget',
      columns: ['amount_cents'],
      where: 'year = ? AND month = ?',
      whereArgs: [year, month],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return rows.first['amount_cents'] as int;
  }

  /// 设置 / 更新月预算
  Future<void> set(int year, int month, int amountCents) async {
    final db = await AppDatabase.instance.db;
    await db.insert(
      'budget',
      {'year': year, 'month': month, 'amount_cents': amountCents},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 删除月预算
  Future<void> remove(int year, int month) async {
    final db = await AppDatabase.instance.db;
    await db.delete('budget',
        where: 'year = ? AND month = ?', whereArgs: [year, month]);
  }

  /// 当月天数
  int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// 日均预算 = 月预算 / 当月天数 (分, 向下取整)
  int dailyBudgetCents(int monthCents, int year, int month) {
    final d = daysInMonth(year, month);
    return d == 0 ? 0 : (monthCents / d).floor();
  }
}
