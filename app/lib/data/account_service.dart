/// 账户服务 (v1.13.0 资产管理)
///
/// 对标同类 APP 的「资产管理」模块 (iCost / 钱迹 / 鲨鱼):
///   - 账户列表 (现金 / 储蓄卡 / 信用卡 / 存款 / 理财)
///   - 余额维护 + 净资产汇总 (负债账户按负值计入)
///   - 流水可绑定账户, 记一笔时自动增减账户余额
///
/// 余额口径:
///   balance_cents = 初始余额 + 收入 - 支出 (信用卡: 支出时余额为负, 表示欠款)
///   净资产 = Σ 账户净贡献 (负债账户取负)
library;

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

class AccountService {
  static final AccountService instance = AccountService._();
  AccountService._();

  /// 全部账户 (含已归档), 按 sort_order + id 排序
  Future<List<Account>> all({bool includeArchived = false}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('account',
        where: includeArchived ? null : 'archived = 0',
        orderBy: 'sort_order ASC, id ASC');
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> byId(String id) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('account',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<String> insert(Account a) async {
    final db = await AppDatabase.instance.db;
    await db.insert('account', {
      ...a.toMap(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return a.id;
  }

  Future<void> update(Account a) async {
    final db = await AppDatabase.instance.db;
    await db.update('account', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> remove(String id) async {
    final db = await AppDatabase.instance.db;
    await db.delete('account', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> archive(String id, bool archived) async {
    final db = await AppDatabase.instance.db;
    await db.update('account', {'archived': archived ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 设置余额 (余额管理页直接改)
  Future<void> setBalance(String id, int balanceCents) async {
    final db = await AppDatabase.instance.db;
    await db.update('account', {'balance_cents': balanceCents},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 记一笔时调用: 收入 +amount, 支出 -amount
  ///
  /// [deltaCents] 为账户余额变化量 (收入为正, 支出为负)
  Future<void> applyDelta(String? accountId, int deltaCents) async {
    if (accountId == null || accountId.isEmpty || deltaCents == 0) return;
    final db = await AppDatabase.instance.db;
    await db.rawUpdate(
      'UPDATE account SET balance_cents = balance_cents + ? WHERE id = ?',
      [deltaCents, accountId],
    );
  }

  /// 净资产合计 (分) — 只统计 include_net = 1 且未归档的账户
  Future<int> netWorth() async => netWorthSync(await all());

  /// 净资产合计 (同步版本, 传入已加载的列表)
  int netWorthSync(List<Account> list) {
    var sum = 0;
    for (final a in list) {
      sum += a.netCents;
    }
    return sum;
  }

  /// 资产合计 (分) — 仅非负债账户
  Future<int> totalAssets() async => totalAssetsSync(await all());

  int totalAssetsSync(List<Account> list) {
    var sum = 0;
    for (final a in list) {
      if (a.includeNet && !a.kind.isLiability) sum += a.balanceCents;
    }
    return sum;
  }

  /// 负债合计 (分) — 信用卡欠款等, 返回正数
  Future<int> totalLiabilities() async => totalLiabilitiesSync(await all());

  int totalLiabilitiesSync(List<Account> list) {
    var sum = 0;
    for (final a in list) {
      // 信用卡余额为负表示欠款, 取绝对值作为负债额
      if (a.includeNet && a.kind.isLiability && a.balanceCents < 0) {
        sum += -a.balanceCents;
      }
    }
    return sum;
  }

  /// 生成新账户 id (acc.xxx 风格)
  static String newId(String name) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'acc.$ts';
  }
}
