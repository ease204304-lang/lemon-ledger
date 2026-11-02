// 数据导入 (importJson) 单元测试 (v1.5 D2 改进项)
//
// 覆盖:
//   1. roundtrip: 导出 → 导入 (replace) → 数据完全一致
//   2. 空文件 → emptyFile
//   3. 坏 JSON → badJson
//   4. version 缺失 / 不兼容 → versionMissing / versionMismatch
//   5. 缺 categories / transactions → missingCategories / missingTransactions
//   6. 无效分类数据 → invalidCategory
//   7. 外键违规 (replace 模式, 引用 DB 有而 JSON 没有的分类) → foreignKeyViolation
//   8. merge: 引用 DB 已有分类合法 + 同 ID 覆盖 + 新 ID 累加
//   9. replace: 旧数据全清, 只剩导入的
//  10. peekJsonFile 各场景
//
// 不依赖模拟器, sqflite_common_ffi 内存跑 (秒级).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/repository.dart';
import 'package:lemon_ledger/services/backup.dart';

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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lemon_import_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    // 单例 Repository 直接持有 AppDatabase.instance, close 后会重开,
    // 所以每个测试用全新 tempDir 隔离.
  });

  // ---- 工具 ----

  File _writeJson(String name, Object? data) {
    final f = File('${tempDir.path}${Platform.pathSeparator}$name');
    return f..writeAsStringSync(jsonEncode(data));
  }

  Map<String, Object?> _catMap(String id, {String name = '测试分类'}) => {
        'id': id,
        'name': name,
        'icon_key': 'food',
        'type': 0,
        'sort_order': 99,
        'archived': 0,
      };

  Map<String, Object?> _txMap(String id, String catId,
          {int cents = 12345, int day = 20731}) =>
      {
        'id': id,
        'epoch_day': day,
        'type': 0,
        'category_id': catId,
        'amount_cents': cents,
        'note': '测试',
        'photo_path': null,
        'created_at': 1700000000000,
      };

  Map<String, Object?> _backup({
    int version = 1,
    List<Map<String, Object?>>? cats,
    List<Map<String, Object?>>? txs,
  }) =>
      {
        'version': version,
        'exportedAt': '2026-10-13T00:00:00',
        'categories': cats ?? [_catMap('cat.test')],
        'transactions': txs ?? [_txMap('tx.test', 'cat.test')],
      };

  Future<int> _count(String table) async {
    final db = await AppDatabase.instance.db;
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return r.first['c'] as int;
  }

  // ---- 1. roundtrip ----

  test('roundtrip: 导出 → replace 导入 → 分类/流水数量与内容一致', () async {
    // DB 里有种子 (22 分类 + 18 流水)
    final exported = await BackupService.instance.exportJson();
    final beforeTxs = await TxRepository.instance.all();
    final beforeCats =
        await CategoryRepository.instance.all(includeArchived: true);
    expect(beforeTxs.length, 18);
    expect(beforeCats.length, 22);

    // 改一条数据, 让 replace 有可见差异
    final db = await AppDatabase.instance.db;
    await db.update('tx', {'amount_cents': 1},
        where: 'id = ?', whereArgs: ['t.001']);
    expect((await TxRepository.instance.byId('t.001'))!.amountCents, 1);

    // replace 导入
    final result = await BackupService.instance
        .importJson(exported, mode: ImportMode.replace);

    // replace 模式: 全部是 insert (先清空)
    expect(result.transactionsInserted, 18);
    expect(result.categoriesInserted, 22);
    final afterTxs = await TxRepository.instance.all();
    final afterCats =
        await CategoryRepository.instance.all(includeArchived: true);
    expect(afterTxs.length, 18);
    expect(afterCats.length, 22);
    // 内容恢复
    final t1 = await TxRepository.instance.byId('t.001');
    expect(t1!.amountCents, beforeTxs.firstWhere((t) => t.id == 't.001').amountCents);
    // 金额集合一致
    final beforeSet = beforeTxs.map((t) => '${t.id}:${t.amountCents}').toSet();
    final afterSet = afterTxs.map((t) => '${t.id}:${t.amountCents}').toSet();
    expect(afterSet, beforeSet);
  });

  // ---- 2-5. 错误场景 ----

  test('空文件 → emptyFile', () async {
    final f = File('${tempDir.path}${Platform.pathSeparator}empty.json')
      ..writeAsStringSync('');
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.emptyFile);
    }
  });

  test('坏 JSON → badJson', () async {
    final f = File('${tempDir.path}${Platform.pathSeparator}bad.json')
      ..writeAsStringSync('{not valid json!!!');
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.badJson);
    }
  });

  test('JSON 根是数组 → badJson', () async {
    final f = _writeJson('arr.json', [1, 2, 3]);
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.badJson);
    }
  });

  test('缺 version → versionMissing', () async {
    final f = _writeJson('nov.json', {
      'categories': [],
      'transactions': [],
    });
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.versionMissing);
    }
  });

  test('version=99 → versionMismatch', () async {
    final f = _writeJson('v99.json', _backup(version: 99));
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.versionMismatch);
    }
  });

  test('缺 categories → missingCategories', () async {
    final f = _writeJson('nocat.json', {
      'version': 1,
      'transactions': [],
    });
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.missingCategories);
    }
  });

  test('缺 transactions → missingTransactions', () async {
    final f = _writeJson('notx.json', {
      'version': 1,
      'categories': [],
    });
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.missingTransactions);
    }
  });

  test('分类缺字段 → invalidCategory', () async {
    final f = _writeJson('badcat.json', {
      'version': 1,
      'categories': [
        {'id': 'cat.x'}, // 缺 name/icon_key/type
      ],
      'transactions': [],
    });
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.invalidCategory);
      expect(e.message, contains('分类'));
    }
  });

  test('流水缺字段 → invalidTransaction', () async {
    final f = _writeJson('badtx.json', {
      'version': 1,
      'categories': [_catMap('cat.test')],
      'transactions': [
        {'id': 'tx.x'}, // 缺一堆
      ],
    });
    try {
      await BackupService.instance.importJson(f);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.invalidTransaction);
    }
  });

  test('replace 模式: 引用 DB 有而 JSON 没有的分类 → foreignKeyViolation', () async {
    // cat.food 在 DB (种子), 但 JSON 里没有
    final f = _writeJson('fk.json', _backup(
      cats: [_catMap('cat.test')],
      txs: [_txMap('tx.a', 'cat.food')], // 引用 cat.food
    ));
    try {
      await BackupService.instance.importJson(f, mode: ImportMode.replace);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.foreignKeyViolation);
    }
    // 失败后 DB 未被清空 (事务回滚)
    expect(await _count('tx'), 18);
    expect(await _count('category'), 22);
  });

  // ---- 8. merge ----

  test('merge: 同 ID 覆盖 + 新 ID 累加 + 可引用 DB 已有分类', () async {
    final f = _writeJson('merge.json', _backup(
      cats: [
        _catMap('cat.new'), // 新分类
        _catMap('cat.food', name: '餐饮(改)'), // 已有, 改名
      ],
      txs: [
        _txMap('tx.new', 'cat.new', cents: 999), // 新流水
        _txMap('t.001', 'cat.food', cents: 1), // 已有, 覆盖
        _txMap('tx.dbcat', 'cat.transport', cents: 555), // 引用 DB 已有分类 (JSON 没有)
      ],
    ));

    final result = await BackupService.instance
        .importJson(f, mode: ImportMode.merge);

    expect(result.categoriesInserted, 1); // cat.new
    expect(result.categoriesReplaced, 1); // cat.food
    expect(result.transactionsInserted, 2); // tx.new + tx.dbcat
    expect(result.transactionsReplaced, 1); // t.001
    expect(result.transactionsMerged, 1);

    // 数量: 18 + 2 = 20 笔, 22 + 1 = 23 分类
    expect(await _count('tx'), 20);
    expect(await _count('category'), 23);

    // t.001 被覆盖为 1 分
    final t1 = await TxRepository.instance.byId('t.001');
    expect(t1!.amountCents, 1);
    expect(t1.note, '测试');

    // cat.food 改名生效
    final food = await CategoryRepository.instance.byId('cat.food');
    expect(food!.name, '餐饮(改)');

    // 新流水在
    expect((await TxRepository.instance.byId('tx.new'))!.amountCents, 999);
    expect((await TxRepository.instance.byId('tx.dbcat'))!.amountCents, 555);
  });

  // ---- 9. replace ----

  test('replace: 旧数据全清, 只剩导入的', () async {
    final f = _writeJson('repl.json', _backup(
      cats: [_catMap('cat.only')],
      txs: [_txMap('tx.only', 'cat.only', cents: 100)],
    ));

    final result = await BackupService.instance
        .importJson(f, mode: ImportMode.replace);

    expect(result.categoriesInserted, 1);
    expect(result.transactionsInserted, 1);
    expect(await _count('tx'), 1);
    expect(await _count('category'), 1);
    expect((await TxRepository.instance.byId('tx.only'))!.amountCents, 100);
  });

  test('replace 失败时回滚: 坏数据不会清空现有库', () async {
    // 先确认有种子
    expect(await _count('tx'), 18);

    final f = _writeJson('replfail.json', {
      'version': 1,
      'categories': [_catMap('cat.only')],
      'transactions': [
        _txMap('tx.only', 'cat.only'),
        _txMap('tx.bad', 'cat.missing'), // 第二笔引用不存在分类 → 整体失败
      ],
    });
    try {
      await BackupService.instance.importJson(f, mode: ImportMode.replace);
      fail('应抛 ImportError');
    } on ImportError catch (e) {
      expect(e.kind, ImportErrorKind.foreignKeyViolation);
    }
    // 关键: 数据没被清空 (外键校验在事务前, 但即使事务内失败也应回滚)
    expect(await _count('tx'), 18);
    expect(await _count('category'), 22);
  });

  // ---- 10. peek ----

  test('peekJsonFile: 合法文件返回 null', () async {
    final f = _writeJson('ok.json', _backup());
    expect(await BackupService.instance.peekJsonFile(f), isNull);
  });

  test('peekJsonFile: 坏文件返回对应错误码', () async {
    final empty = File('${tempDir.path}${Platform.pathSeparator}e.json')
      ..writeAsStringSync('');
    expect(await BackupService.instance.peekJsonFile(empty),
        ImportErrorKind.emptyFile);

    final bad = File('${tempDir.path}${Platform.pathSeparator}b.json')
      ..writeAsStringSync('xxx');
    expect(await BackupService.instance.peekJsonFile(bad),
        ImportErrorKind.badJson);

    final v9 = _writeJson('v9.json', _backup(version: 9));
    expect(await BackupService.instance.peekJsonFile(v9),
        ImportErrorKind.versionMismatch);

    final missing = File('${tempDir.path}${Platform.pathSeparator}none.json');
    expect(await BackupService.instance.peekJsonFile(missing),
        ImportErrorKind.ioError);
  });

  test('errorMessage: 每种错误都有非空中文提示', () async {
    for (final kind in ImportErrorKind.values) {
      final msg = BackupService.errorMessage(kind);
      expect(msg, isNotEmpty);
    }
  });
}
