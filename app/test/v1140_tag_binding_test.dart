// v1.14.0 标签-分类绑定测试
//
// 用户需求:
//   1. 标签绑定分类 (如「停车费」绑定「交通」)
//   2. 支出和收入各自独立 (同名标签在两种类型下可绑定不同分类)
//   3. 切换收入/支出 → 标签内容不同
//   4. 点标签 → 自动选中对应分类 (快速记账)
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
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('v1140_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  group('标签绑定分类', () {
    test('bindCategory / categoryOf 往返', () async {
      final svc = TagService.instance;
      await svc.addOrBump('停车费');
      await svc.bindCategory('停车费', TxType.expense, 'cat.transport');
      expect(await svc.categoryOf('停车费', TxType.expense), 'cat.transport');
    });

    test('同名标签在支出/收入下绑定不同分类', () async {
      final svc = TagService.instance;
      await svc.addOrBump('报销');
      await svc.bindCategory('报销', TxType.expense, 'cat.other');
      await svc.bindCategory('报销', TxType.income, 'cat.refund');
      expect(await svc.categoryOf('报销', TxType.expense), 'cat.other');
      expect(await svc.categoryOf('报销', TxType.income), 'cat.refund');
    });

    test('未绑定的标签返回 null', () async {
      final svc = TagService.instance;
      await svc.addOrBump('未绑定');
      expect(await svc.categoryOf('未绑定', TxType.expense), isNull);
      expect(await svc.categoryOf('未绑定', TxType.income), isNull);
    });

    test('重新绑定覆盖旧绑定', () async {
      final svc = TagService.instance;
      await svc.addOrBump('午餐');
      await svc.bindCategory('午餐', TxType.expense, 'cat.food');
      await svc.bindCategory('午餐', TxType.expense, 'cat.snack');
      expect(await svc.categoryOf('午餐', TxType.expense), 'cat.snack');
    });

    test('unbind 解除绑定', () async {
      final svc = TagService.instance;
      await svc.addOrBump('临时');
      await svc.bindCategory('临时', TxType.expense, 'cat.food');
      await svc.unbind('临时', TxType.expense);
      expect(await svc.categoryOf('临时', TxType.expense), isNull);
    });
  });

  group('按类型隔离标签', () {
    test('recentByType: 支出与收入返回不同标签集', () async {
      final svc = TagService.instance;
      // 支出标签
      await svc.addOrBump('停车费');
      await svc.bindCategory('停车费', TxType.expense, 'cat.transport');
      // 收入标签
      await svc.addOrBump('年终奖');
      await svc.bindCategory('年终奖', TxType.income, 'cat.bonus');

      final exp = await svc.recentByType(TxType.expense);
      final inc = await svc.recentByType(TxType.income);

      expect(exp.map((t) => t.name), contains('停车费'));
      expect(exp.map((t) => t.name), isNot(contains('年终奖')));
      expect(inc.map((t) => t.name), contains('年终奖'));
      expect(inc.map((t) => t.name), isNot(contains('停车费')));
    });

    test('byBoundCategory: 按分类 + 类型取标签', () async {
      final svc = TagService.instance;
      await svc.addOrBump('地铁');
      await svc.bindCategory('地铁', TxType.expense, 'cat.transport');
      final ts = await svc.byBoundCategory(TxType.expense, 'cat.transport');
      expect(ts.map((t) => t.name), contains('地铁'));
      // 收入类型下无此绑定
      final tsInc = await svc.byBoundCategory(TxType.income, 'cat.transport');
      expect(tsInc.map((t) => t.name), isNot(contains('地铁')));
    });

    test('allBound: 按类型列出全部绑定标签', () async {
      final svc = TagService.instance;
      await svc.addOrBump('A');
      await svc.addOrBump('B');
      await svc.bindCategory('A', TxType.expense, 'cat.food');
      await svc.bindCategory('B', TxType.income, 'cat.salary');
      final exp = await svc.allBound(TxType.expense);
      final inc = await svc.allBound(TxType.income);
      expect(exp.map((t) => t.name), contains('A'));
      expect(exp.map((t) => t.name), isNot(contains('B')));
      expect(inc.map((t) => t.name), contains('B'));
    });

    test('bindingsOf: 批量查询绑定', () async {
      final svc = TagService.instance;
      await svc.addOrBump('X');
      await svc.addOrBump('Y');
      await svc.bindCategory('X', TxType.expense, 'cat.food');
      await svc.bindCategory('Y', TxType.expense, 'cat.snack');
      final m = await svc.bindingsOf(['X', 'Y', 'Z'], TxType.expense);
      expect(m['X'], 'cat.food');
      expect(m['Y'], 'cat.snack');
      expect(m.containsKey('Z'), isFalse);
    });
  });

  group('记账时自动建立绑定', () {
    test('syncForTx: 备注命中标签 → 绑定到所选分类', () async {
      final svc = TagService.instance;
      final now = DateTime.now();
      final day = now.millisecondsSinceEpoch ~/ 86400000;
      // 已有标签「停车费」
      await svc.addOrBump('停车费');
      // 记一笔: 分类=交通, 备注含「停车费」
      final tx = Tx(
        id: 'tx.tagbind.1',
        epochDay: day,
        type: TxType.expense,
        categoryId: 'cat.transport',
        amountCents: 1000,
        note: '停车费 5元',
        createdAt: now,
      );
      await svc.syncForTx(tx);
      expect(await svc.categoryOf('停车费', TxType.expense), 'cat.transport');
    });

    test('syncForTx: 收入类型独立绑定', () async {
      final svc = TagService.instance;
      final now = DateTime.now();
      final day = now.millisecondsSinceEpoch ~/ 86400000;
      await svc.addOrBump('退款');
      final tx = Tx(
        id: 'tx.tagbind.2',
        epochDay: day,
        type: TxType.income,
        categoryId: 'cat.refund',
        amountCents: 1000,
        note: '退款到账',
        createdAt: now,
      );
      await svc.syncForTx(tx);
      expect(await svc.categoryOf('退款', TxType.income), 'cat.refund');
      expect(await svc.categoryOf('退款', TxType.expense), isNull,
          reason: '收入绑定不应污染支出侧');
    });
  });

  group('数据库迁移', () {
    test('v8 建表: tag_binding 存在且结构正确', () async {
      final db = await AppDatabase.instance.db;
      final rows = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tag_binding'");
      expect(rows, isNotEmpty);
    });

    test('tag_binding 主键为 (name, type)', () async {
      final db = await AppDatabase.instance.db;
      // 同名不同类型可共存
      await db.insert('tag_binding',
          {'name': 'same', 'type': 0, 'category_id': 'cat.food'});
      await db.insert('tag_binding',
          {'name': 'same', 'type': 1, 'category_id': 'cat.salary'});
      final rows = await db.query('tag_binding', where: 'name = ?', whereArgs: ['same']);
      expect(rows.length, 2);
    });

    test('种子数据: 支出侧有绑定 (停车费 → 种子流水所属分类)', () async {
      final svc = TagService.instance;
      final cid = await svc.categoryOf('停车费', TxType.expense);
      expect(cid, isNotNull, reason: '停车费应有支出侧绑定');
      // 种子流水中「停车费」归在汽车分类
      expect(cid, 'cat.car');
    });

    test('种子数据: 收入侧有绑定 (工资 → 工资 / 年终奖 → 工资 / 投资收益 → 理财)', () async {
      final svc = TagService.instance;
      expect(await svc.categoryOf('工资', TxType.income), 'cat.salary');
      // v1.15.0: 奖金类收入分类归档 → 年终奖改绑到 工资
      expect(await svc.categoryOf('年终奖', TxType.income), 'cat.salary');
      expect(await svc.categoryOf('投资收益', TxType.income), 'cat.invest');
    });

    test('严格隔离: 收入侧标签不混入支出侧', () async {
      final svc = TagService.instance;
      final exp = await svc.recentByType(TxType.expense);
      final inc = await svc.recentByType(TxType.income);
      expect(exp.map((t) => t.name), isNotEmpty);
      expect(inc.map((t) => t.name), isNotEmpty);
      // 两边不应有交集
      final expNames = exp.map((t) => t.name).toSet();
      final incNames = inc.map((t) => t.name).toSet();
      expect(expNames.intersection(incNames), isEmpty,
          reason: '支出与收入的标签集必须不相交');
      // 支出侧含停车费, 收入侧不含
      expect(expNames, contains('停车费'));
      expect(incNames, isNot(contains('停车费')));
      // 收入侧含工资, 支出侧不含
      expect(incNames, contains('工资'));
      expect(expNames, isNot(contains('工资')));
    });
  });
}
