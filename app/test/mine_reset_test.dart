// 重置数据 (U3) 行为测试
//
// 验证 AppDatabase.resetForDebug() 后:
//   - DB 文件被删除
//   - 下次 .db 调用重新 onCreate seed 全部 30 分类 + 18 流水
//   - 用户写的脏数据 (预算/自定义分类) 全部清空

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/budget_service.dart';
import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/repository.dart';

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
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('lemon_reset_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('重置前 DB 有种子 (22 分类 + 18 流水)', () async {
    final cats = await CategoryRepository.instance.all();
    final txs = await TxRepository.instance.all();
    // v6: 分类清单重整 → 支出 14 + 收入 8 = 22
    expect(cats.length, 22);
    expect(txs.length, 18);
  });

  test('重置后 DB 重新 seed 全部初始数据', () async {
    // 1. 写入用户数据
    final t = Tx(
      id: 'dirty.001',
      epochDay: 20740,
      type: TxType.expense,
      categoryId: 'cat.food',
      amountCents: 99900,
      note: '脏数据',
      createdAt: DateTime(2026, 10, 1),
    );
    await TxRepository.instance.insert(t);
    await BudgetService.instance.set(2026, 11, 500000);
    expect((await TxRepository.instance.all()).length, 19);

    // 2. 重置
    await AppDatabase.instance.resetForDebug();

    // 3. 再开 DB → 应该重新 onCreate seed
    final db = await AppDatabase.instance.db;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM tx'));
    expect(count, 18);
    // 脏数据没了
    final dirty = await TxRepository.instance.byId('dirty.001');
    expect(dirty, isNull);
  });

  test('重置后预算也清空', () async {
    // 设置预算
    await BudgetService.instance.set(2026, 12, 123400);
    expect(await BudgetService.instance.get(2026, 12), 123400);

    // 重置
    await AppDatabase.instance.resetForDebug();

    // 预算也清空 (再 onCreate 不 seed 预算)
    expect(await BudgetService.instance.get(2026, 12), 0);
  });

  test('resetForDebug 是幂等的: 连续 3 次都不崩', () async {
    await AppDatabase.instance.resetForDebug();
    await AppDatabase.instance.resetForDebug();
    await AppDatabase.instance.resetForDebug();
    final cats = await CategoryRepository.instance.all();
    expect(cats.length, 22);
  });

  // ----- U3 二次确认对话框: ValueListenableBuilder 行为 -----
  // 验证输入 "确认" 文字的逻辑: ValueListenableBuilder 监听 controller,
  // 文字 == "确认" 时按钮 enabled, 否则 disabled.
  testWidgets('U3 二次确认: ValueListenableBuilder 响应 controller 变化',
      (tester) async {
    final controller = TextEditingController();
    bool? lastEnabled;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, __) {
            final match = v.text == '确认';
            lastEnabled = match;
            return ElevatedButton(
              onPressed: match ? () {} : null,
              child: const Text('执行重置'),
            );
          },
        ),
      ),
    ));

    // 空 → disabled
    expect(lastEnabled, false);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull);

    // 输 "确认" → enabled
    controller.text = '确认';
    controller.notifyListeners();
    await tester.pump();
    expect(lastEnabled, true);
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);

    // 改 "确认吧" → disabled
    controller.text = '确认吧';
    controller.notifyListeners();
    await tester.pump();
    expect(lastEnabled, false);

    // 改 "确 认" (中间空格) → disabled (精确匹配)
    controller.text = '确 认';
    controller.notifyListeners();
    await tester.pump();
    expect(lastEnabled, false);

    // 再改回 "确认" → enabled
    controller.text = '确认';
    controller.notifyListeners();
    await tester.pump();
    expect(lastEnabled, true);

    controller.dispose();
  });
}
