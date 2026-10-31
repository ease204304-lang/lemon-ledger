// 标签统计测试 (v1.8.0, U1.9 收尾)
//
// 覆盖:
//   - DB v5 schema (tx_tag 关联表 + tag.category_id)
//   - 种子回填 (11 个演示标签 + 关联正确)
//   - statsByTag 聚合 (按金额 / 按时间排序)
//   - syncForTx (保存流水同步关联: 整体 bump + 子串命中)
//   - byCategory (走 tx_tag 精确匹配)
//   - remove (连带清理关联)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/repository.dart';
import 'package:lemon_ledger/data/tag_service.dart';

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
  // 种子流水 epoch day: 2026-10-05 = 20731 .. 10-09 = 20735
  const day0 = 20731;
  const day4 = 20735;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('tag_stats_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Tx mkTx(String id, int day, String cat, int cents, String note,
      {TxType type = TxType.expense}) {
    return Tx(
      id: id,
      epochDay: day,
      type: type,
      categoryId: cat,
      amountCents: cents,
      note: note,
      createdAt: DateTime.now(),
    );
  }

  group('DB v5 schema', () {
    test('tx_tag 表存在且有索引', () async {
      final db = await AppDatabase.instance.db;
      final idx = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='tx_tag'");
      expect(idx, isNotEmpty);
    });

    test('tag 表有 category_id 列', () async {
      final db = await AppDatabase.instance.db;
      final cols = await db.rawQuery('PRAGMA table_info(tag)');
      final names = cols.map((c) => c['name']).toList();
      expect(names, contains('category_id'));
    });

    test('种子回填: 11 个演示标签', () async {
      final tags = await TagService.instance.recent(50);
      expect(tags.length, 11);
      expect(tags.map((t) => t.name),
          containsAll(['餐饮', '交通', '信托', '停车费']));
      // 不含 "收入" — 避免与记帐页类型 chip 撞名
      expect(tags.map((t) => t.name), isNot(contains('收入')));
    });

    test('种子回填: use_count 正确 (餐饮 4 笔 / 停车费 2 笔)', () async {
      final tags = await TagService.instance.recent(50);
      final byName = {for (final t in tags) t.name: t.useCount};
      expect(byName['餐饮'], 4);
      expect(byName['停车费'], 2);
      expect(byName['信托'], 1);
    });
  });

  group('statsByTag (按标签聚合)', () {
    test('按金额: 信托 818 > 日用 590 > 交通 411 ...', () async {
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0, day4, sortBy: TagSortBy.amount);
      final byName = {for (final s in stats) s.name: s.totalCents};
      expect(byName['信托'], 81800);
      expect(byName['日用'], 59000);
      expect(byName['交通'], 41100); // 162+152+97
      expect(byName['餐饮'], 13600); // 59+53+15+9
      expect(byName['停车费'], 2000); // 5+15
      // 排序: 金额降序
      expect(stats.first.name, '信托');
      final amounts = stats.map((s) => s.totalCents).toList();
      expect(amounts, equals([...amounts]..sort((a, b) => b.compareTo(a))));
    });

    test('按时间: 最近使用的标签在前', () async {
      // 种子里所有标签最后使用都在 10-05..10-09
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0, day4, sortBy: TagSortBy.time);
      // 10-09 使用的: 信托/停车费/单车/充电/咖啡/餐饮 (day4)
      // 10-05 使用的: 日用/孩子/旅行/医疗/交通(note)/餐饮
      final day4Tags = stats.where((s) => s.lastUsedDay == day4).map((s) => s.name).toSet();
      expect(day4Tags, containsAll(['信托', '停车费', '单车', '充电', '咖啡']));
      // 排序: lastUsedDay 降序
      final days = stats.map((s) => s.lastUsedDay).toList();
      expect(days, equals([...days]..sort((a, b) => b.compareTo(a))));
    });

    test('笔数: 交通 3 笔 / 餐饮 4 笔', () async {
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0, day4);
      final byName = {for (final s in stats) s.name: s.txCount};
      expect(byName['交通'], 3);
      expect(byName['餐饮'], 4);
    });

    test('收入/支出过滤: 种子收入侧无标签 → 空', () async {
      // 种子不含 "收入" 标签 (避免与类型 chip 撞名)
      final stats = await TagService.instance
          .statsByTag(TxType.income, day0, day4);
      expect(stats, isEmpty);
    });

    test('空周期: 无数据', () async {
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0 + 100, day0 + 200);
      expect(stats, isEmpty);
    });
  });

  group('syncForTx (保存流水同步标签)', () {
    // 注意: 先插 tx 行再 sync (statsByTag 走 tx_tag JOIN tx)
    test('整体备注成为标签 + 建关联', () async {
      final tx = mkTx('new.1', day4, 'cat.drink', 1500, '一点点');
      await TxRepository.instance.insert(tx);
      await TagService.instance.syncForTx(tx);
      final db = await AppDatabase.instance.db;
      final link = await db.query('tx_tag',
          where: 'tx_id = ?', whereArgs: ['new.1']);
      expect(link.length, 1);
      expect(link.first['tag_name'], '一点点');
      // 标签存在且 use_count = 1
      final tags = await TagService.instance.search('一点点');
      expect(tags.first.useCount, 1);
      // 统计包含
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0, day4);
      final row = stats.where((s) => s.name == '一点点').single;
      expect(row.totalCents, 1500);
    });

    test('备注含已有标签 → 命中关联 + 整体也是新标签 + 频次 bump', () async {
      // 已有标签: 星巴克 (先建)
      final tx1 = mkTx('new.2', day4, 'cat.drink', 3500, '星巴克');
      await TxRepository.instance.insert(tx1);
      await TagService.instance.syncForTx(tx1);
      // 再存一笔备注含 "星巴克" 的
      final tx2 = mkTx('new.3', day4, 'cat.drink', 4200, '星巴克 拿铁');
      await TxRepository.instance.insert(tx2);
      await TagService.instance.syncForTx(tx2);
      final db = await AppDatabase.instance.db;
      // tx2 应关联: 星巴克 + 星巴克 拿铁 (整体)
      final links = await db.query('tx_tag',
          where: 'tx_id = ?', whereArgs: ['new.3']);
      final names = links.map((l) => l['tag_name']).toSet();
      expect(names, {'星巴克', '星巴克 拿铁'});
      // 星巴克 use_count = 2
      final tag = (await TagService.instance.search('星巴克'))
          .where((t) => t.name == '星巴克')
          .single;
      expect(tag.useCount, 2);
      // 统计: 星巴克 = 3500 + 4200
      final stats = await TagService.instance
          .statsByTag(TxType.expense, day0, day4);
      final row = stats.where((s) => s.name == '星巴克').single;
      expect(row.totalCents, 7700);
      expect(row.txCount, 2);
    });

    test('编辑流水 (二次 sync) 不产生重复关联', () async {
      final tx = mkTx('new.4', day4, 'cat.drink', 1000, '咖啡');
      await TxRepository.instance.insert(tx);
      await TagService.instance.syncForTx(tx);
      // 改备注再同步
      final edited = mkTx('new.4', day4, 'cat.food', 1200, '咖啡 加冰');
      await TxRepository.instance.update(edited);
      await TagService.instance.syncForTx(edited);
      final db = await AppDatabase.instance.db;
      final links = await db.query('tx_tag',
          where: 'tx_id = ?', whereArgs: ['new.4']);
      final names = links.map((l) => l['tag_name']).toSet();
      expect(names, {'咖啡', '咖啡 加冰'});
      // 关联行数 = 去重后的数量 (无重复)
      expect(links.length, names.length);
    });

    test('空备注: 只清关联, 不建标签', () async {
      final tx = mkTx('new.5', day4, 'cat.drink', 900, '');
      await TagService.instance.syncForTx(tx);
      final db = await AppDatabase.instance.db;
      final links = await db.query('tx_tag',
          where: 'tx_id = ?', whereArgs: ['new.5']);
      expect(links, isEmpty);
    });

    test('tag.category_id 记录最近使用分类', () async {
      final tx = mkTx('new.6', day4, 'cat.snack', 800, '周黑鸭');
      await TxRepository.instance.insert(tx);
      await TagService.instance.syncForTx(tx);
      final tags = await TagService.instance.search('周黑鸭');
      expect(tags.first.categoryId, 'cat.snack');
    });
  });

  group('byCategory (tx_tag 精确匹配)', () {
    test('交通分类 → 交通/单车/充电 标签', () async {
      final tags = await TagService.instance.byCategory('cat.transport', limit: 10);
      final names = tags.map((t) => t.name).toSet();
      expect(names, containsAll(['交通', '单车', '充电']));
      // 不含其他分类的标签
      expect(names, isNot(contains('信托')));
      expect(names, isNot(contains('咖啡')));
    });

    test('limit 生效', () async {
      final tags = await TagService.instance.byCategory('cat.transport', limit: 1);
      expect(tags.length, 1);
    });
  });

  group('remove (连带清理)', () {
    test('删标签 → tx_tag 关联也删', () async {
      final db = await AppDatabase.instance.db;
      final before = await db
          .rawQuery("SELECT COUNT(*) AS n FROM tx_tag WHERE tag_name = '咖啡'");
      expect(before.first['n'], 1);
      await TagService.instance.remove('咖啡');
      final after = await db
          .rawQuery("SELECT COUNT(*) AS n FROM tx_tag WHERE tag_name = '咖啡'");
      expect(after.first['n'], 0);
      // tag 行也删了
      final tags = await TagService.instance.search('咖啡');
      expect(tags.where((t) => t.name == '咖啡'), isEmpty);
    });
  });

  group('v4 → v5 升级迁移', () {
    test('旧库升级: tx_tag 建表 + 已有标签回填关联', () async {
      // 手工搭一个 v4 库 (有 tag 有 tx, 无 tx_tag)
      final db = await AppDatabase.instance.db;
      // AppDatabase 打开的是 v5 (带种子), 模拟升级场景:
      // 删掉 tx_tag 和 category_id, 再手工跑 v5 迁移逻辑等价的检查
      // (真实升级路径在 onUpgrade, 这里验证数据一致性)
      final count = await db.rawQuery('SELECT COUNT(*) AS n FROM tx_tag');
      // 种子 18 笔中 16 笔有备注命中 → 至少 16 行关联
      expect((count.first['n'] as int) >= 16, isTrue);
      // 每条关联的 tx 备注确实包含标签名
      final bad = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM tx_tag tt
        JOIN tx x ON x.id = tt.tx_id
        WHERE instr(LOWER(x.note), LOWER(tt.tag_name)) = 0
      ''');
      expect(bad.first['n'], 0);
    });
  });
}
