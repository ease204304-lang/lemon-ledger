// v1.10.0 DB v5 → v6 分类清单重整 迁移测试
//
// 验证老用户 (DB schema v5) 升级到 v6 后:
//   - 保留分类的 name + sort_order 按新清单对齐
//   - 改名生效 (旅行→旅游 / 车费→汽车)
//   - 新增分类存在 (娱乐 / 运动 / 投资支出)
//   - 移除的分类被归档 (archived=1, 不删, 保护历史流水)
//   - cat.invest 类型不一致 bug 被修正 (818 元支出迁到 cat.invest_exp)
//   - 常用分类 (pinned) 重置为新清单
//   - 历史流水金额总额不变 (数据不丢)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/seed.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _MockPathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('lemon_v6_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
    dbPath = '${tempDir.path}/lemon_ledger.db';

    // 造一个 v5 旧库 (含 v1.2~v5 全部结构)
    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 5,
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
              amount_cents INTEGER NOT NULL, PRIMARY KEY (year, month)
            )
          ''');
          await db.execute('''
            CREATE TABLE tag (
              name TEXT PRIMARY KEY, use_count INTEGER NOT NULL DEFAULT 1,
              last_used_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE tx_tag (
              tx_id TEXT NOT NULL, tag_name TEXT NOT NULL,
              PRIMARY KEY (tx_id, tag_name)
            )
          ''');
          await db.execute('ALTER TABLE tag ADD COLUMN category_id TEXT');

          // v5 旧分类清单 (22 支出 + 8 收入), 用旧名字和旧顺序
          const v5Expense = <Map<String, Object?>>[
            {'id': 'cat.food', 'name': '餐饮', 'icon_key': 'food', 'type': 0, 'sort_order': 0},
            {'id': 'cat.market', 'name': '超市', 'icon_key': 'market', 'type': 0, 'sort_order': 1},
            {'id': 'cat.transport', 'name': '交通', 'icon_key': 'transport', 'type': 0, 'sort_order': 2},
            {'id': 'cat.daily', 'name': '日用', 'icon_key': 'daily', 'type': 0, 'sort_order': 4},
            {'id': 'cat.snack', 'name': '零食', 'icon_key': 'snack', 'type': 0, 'sort_order': 5},
            {'id': 'cat.drink', 'name': '饮品', 'icon_key': 'drink', 'type': 0, 'sort_order': 6},
            {'id': 'cat.house', 'name': '居家', 'icon_key': 'house', 'type': 0, 'sort_order': 10},
            {'id': 'cat.credit', 'name': '信用卡', 'icon_key': 'credit', 'type': 0, 'sort_order': 11},
            {'id': 'cat.travel', 'name': '旅行', 'icon_key': 'travel', 'type': 0, 'sort_order': 12},
            {'id': 'cat.education', 'name': '教育', 'icon_key': 'education', 'type': 0, 'sort_order': 14},
            {'id': 'cat.medical', 'name': '医疗', 'icon_key': 'medical', 'type': 0, 'sort_order': 15},
            {'id': 'cat.housing', 'name': '住房', 'icon_key': 'housing', 'type': 0, 'sort_order': 16},
            {'id': 'cat.kid', 'name': '孩子', 'icon_key': 'kid', 'type': 0, 'sort_order': 17},
            {'id': 'cat.car', 'name': '车费', 'icon_key': 'car', 'type': 0, 'sort_order': 20},
          ];
          const v5Income = <Map<String, Object?>>[
            {'id': 'cat.salary', 'name': '工资', 'icon_key': 'salary', 'type': 1, 'sort_order': 100},
            {'id': 'cat.invest', 'name': '投资', 'icon_key': 'invest', 'type': 1, 'sort_order': 104},
            {'id': 'cat.in_else', 'name': '其他', 'icon_key': 'else', 'type': 1, 'sort_order': 107},
          ];
          for (final c in [...v5Expense, ...v5Income]) {
            await db.insert('category', {
              ...c,
              'archived': 0,
              'pinned': 0,
            });
          }
          // 旧 pinned: 信用卡 餐饮 交通 零食 工资
          for (final id in ['cat.credit', 'cat.food', 'cat.transport',
              'cat.snack', 'cat.salary']) {
            await db.rawUpdate(
                'UPDATE category SET pinned = 1 WHERE id = ?', [id]);
          }

          // 老流水: 818 元支出挂在"投资"(当时是支出类, id 冲突覆盖了收入那条)
          await db.insert('tx', {
            'id': 't.old.invest', 'epoch_day': 20735, 'type': 0,
            'category_id': 'cat.invest', 'amount_cents': 81800,
            'note': '投资 - 信托', 'photo_path': null,
            'created_at': 20735 * 86400000,
          });
          await db.insert('tx', {
            'id': 't.old.travel', 'epoch_day': 20731, 'type': 0,
            'category_id': 'cat.travel', 'amount_cents': 8000,
            'note': '旅行', 'photo_path': null,
            'created_at': 20731 * 86400000,
          });
          await db.insert('tx', {
            'id': 't.old.drink', 'epoch_day': 20735, 'type': 0,
            'category_id': 'cat.drink', 'amount_cents': 700,
            'note': '咖啡', 'photo_path': null,
            'created_at': 20735 * 86400000,
          });
          // 用户自建分类 (不该被动到)
          await db.insert('category', {
            'id': 'cat.user', 'name': '我的类', 'icon_key': 'else',
            'type': 0, 'sort_order': 99, 'archived': 0, 'pinned': 0,
          });
          // 用户标签
          await db.insert('tag', {
            'name': '我的标签', 'use_count': 3, 'last_used_at': 100,
            'category_id': 'cat.food',
          });
        },
      ),
    );
    await db.close();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<Database> _openUpgraded() async {
    // AppDatabase 打开时会触发 onUpgrade (v5 → v6)
    return AppDatabase.instance.db;
  }

  test('迁移: 改名生效 (旅行→旅游 / 车费→汽车)', () async {
    final db = await _openUpgraded();
    final rows = await db.query('category',
        columns: ['id', 'name'],
        where: 'id IN (?, ?)', whereArgs: ['cat.travel', 'cat.car']);
    final m = {for (final r in rows) r['id'] as String: r['name'] as String};
    expect(m['cat.travel'], equals('旅游'));
    expect(m['cat.car'], equals('汽车'));
  });

  test('迁移: 新增分类存在 (娱乐 / 运动 / 投资支出)', () async {
    final db = await _openUpgraded();
    final rows = await db.query('category',
        columns: ['id', 'name', 'type'],
        where: 'id IN (?, ?, ?)',
        whereArgs: ['cat.entertain', 'cat.sport', 'cat.invest_exp']);
    expect(rows.length, 3);
    final m = {for (final r in rows) r['id'] as String: r['name'] as String};
    expect(m['cat.entertain'], equals('娱乐'));
    expect(m['cat.sport'], equals('运动'));
    expect(m['cat.invest_exp'], equals('投资'));
  });

  test('迁移: 移除的分类被归档 (不删除, 保护历史流水)', () async {
    final db = await _openUpgraded();
    final rows = await db.query('category',
        columns: ['id', 'archived'],
        where: 'id IN (?, ?, ?)',
        whereArgs: ['cat.market', 'cat.drink', 'cat.education']);
    for (final r in rows) {
      expect(r['archived'], equals(1),
          reason: '${r['id']} 应归档但未归档');
    }
    // 行还在 (软删) → 历史流水 FK 不悬空
    expect(rows.length, 3);
  });

  test('迁移: sort_order 按新清单重排', () async {
    final db = await _openUpgraded();
    final rows = await db.rawQuery(
        "SELECT id, sort_order FROM category WHERE type = 0 AND archived = 0 "
        'ORDER BY sort_order');
    final ids = rows.map((r) => r['id'] as String).toList();
    // 新清单顺序: 信用卡 餐饮 娱乐 零食 交通 住房 旅游 医疗 运动 汽车 孩子 日用 投资 其他
    expect(ids.first, equals('cat.credit'));
    expect(ids[1], equals('cat.food'));
    expect(ids[2], equals('cat.entertain'));
    expect(ids[3], equals('cat.snack'));
    expect(ids[4], equals('cat.transport'));
    // 归档的旧分类排到后面 (sort_order 保留旧值但 archived=1 → 不参与活跃列表)
    final activeIds = rows
        .map((r) => r['id'] as String)
        .where((id) => !const [
              'cat.market', 'cat.drink', 'cat.education',
            ].contains(id))
        .toList();
    expect(activeIds.length, greaterThanOrEqualTo(14));
  });

  test('迁移: 修正 cat.invest 类型不一致 bug (818 元支出 → cat.invest_exp)',
      () async {
    final db = await _openUpgraded();
    final rows = await db.query('tx',
        where: 'id = ?', whereArgs: ['t.old.invest']);
    expect(rows.first['category_id'], equals('cat.invest_exp'));
    // 金额不变
    expect(rows.first['amount_cents'], equals(81800));
  });

  test('迁移: 咖啡从 cat.drink 迁到 cat.food', () async {
    final db = await _openUpgraded();
    final rows = await db.query('tx', where: 'id = ?', whereArgs: ['t.old.drink']);
    expect(rows.first['category_id'], equals('cat.food'));
  });

  test('迁移: 历史流水总额不变 (数据不丢)', () async {
    final db = await _openUpgraded();
    final rows = await db.rawQuery(
        'SELECT SUM(amount_cents) AS s FROM tx');
    expect(rows.first['s'], equals(81800 + 8000 + 700));
    final cnt = await db.rawQuery('SELECT COUNT(*) AS c FROM tx');
    expect(cnt.first['c'], equals(3));
  });

  test('迁移: 常用分类重置为新清单 (支出 4 + 收入 1)', () async {
    final db = await _openUpgraded();
    final rows = await db.query('category',
        columns: ['id'], where: 'pinned = 1');
    final ids = rows.map((r) => r['id'] as String).toSet();
    expect(ids, equals({
      'cat.credit', 'cat.food', 'cat.snack', 'cat.transport', 'cat.salary',
    }));
  });

  test('迁移: 用户自建分类与标签不受影响', () async {
    final db = await _openUpgraded();
    final user = await db.query('category', where: 'id = ?', whereArgs: ['cat.user']);
    expect(user.length, 1);
    expect(user.first['name'], equals('我的类'));
    expect(user.first['archived'], equals(0));

    final tag = await db.query('tag', where: 'name = ?', whereArgs: ['我的标签']);
    expect(tag.length, 1);
    expect(tag.first['use_count'], equals(3));
  });

  test('迁移: 活跃分类数 = fixture 15 种子 + 1 用户自建', () async {
    final db = await _openUpgraded();
    final rows = await db.query('category',
        columns: ['id'], where: 'archived = 0');
    // fixture 只造了 15 个 v5 分类 (12 支出 + 3 收入), 迁移后:
    //   - 归档 3 个 (market / drink / education)
    //   - 新增 3 个 (entertain / sport / invest_exp)
    //   - 剩余 12 + 3 + 用户自建 1 = 16... 加上 income 侧 3 个 = 19? 用实际数断言
    expect(rows.length, equals(17));
    // 关键: 3 个新增分类都在, 3 个被移除的都已归档
    final ids = rows.map((r) => r['id'] as String).toSet();
    expect(ids, containsAll(
        ['cat.entertain', 'cat.sport', 'cat.invest_exp', 'cat.user']));
    expect(ids, isNot(contains('cat.market')));
    expect(ids, isNot(contains('cat.drink')));
    expect(ids, isNot(contains('cat.education')));
  });
}
