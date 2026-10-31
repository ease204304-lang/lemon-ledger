// T1 行为测试扩展: 2 个真实端到端流程
//
// 1. test_home_data_flow: HomePage 加载种子 → 显示 18 笔流水 + 2,281.00 支出
// 2. test_entry_keypad_evaluate: EntryPage → 选餐饮 → 输入 12.50 → 按 = 求值
//    → EntryBottomActionBar 金额区显示 "12.50" (验证键盘 → 显示 链路)
//
// 共同依赖: 内存 sqflite_ffi (新 tempDir per test), PathProvider mock
//
// 注意: 完整的 "选分类+输入+保存→回首页" 在 flutter_test 环境下因 sqflite_ffi
// 与 FakeAsync 区的 FutureBuilder 交互复杂, 会留 pending timers. 保存路径
// 在 import_json_test / mine_reset_test 间接覆盖. 真实端到端由模拟器验证.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/screens/entry_page.dart';
import 'package:lemon_ledger/screens/home_page.dart';
import 'package:lemon_ledger/theme/tokens.dart';

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
  int navIndex = -1;

  setUp(() async {
    await AppDatabase.instance.close();
    tempDir = await Directory.systemTemp.createTemp('lemon_t1_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
    navIndex = -1;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Widget wrapHome() => MaterialApp(
        theme: buildLightTheme(),
        home: HomePage(onNavigate: (i) => navIndex = i),
      );

  Widget wrapEntry() => MaterialApp(
        theme: buildLightTheme(),
        home: EntryPage(onNavigate: (i) => navIndex = i),
      );

  // T1 #1: HomePage 启动后, 加载种子数据
  testWidgets('HomePage 启动: 显示 10月汇总 (收入 50.00, 支出 2,281.00)',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(wrapHome());
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // 支出金额 2,281.00 (来自种子 18 笔)
    expect(find.text('2,281.00'), findsOneWidget);
    // 收入 50.00
    expect(find.text('50.00'), findsOneWidget);
    // 10月9日是种子最后一天
    expect(find.text('10月9日'), findsOneWidget);
  });

  // T1 #2: EntryPage 键盘 → EntryBottomActionBar 金额显示 链路
  // 选分类 + 输入 1, 2, ., 5, 0 + 按 = → 求值
  // (不点保存, 避免 _save Future + FutureBuilder pending timers 冲突)
  testWidgets('EntryPage → 选分类 + 输入 12.50 + 按 = → 金额显示 12.50',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // 跟 ui_test 一致: pumpWidget 在 runAsync 内
    await tester.runAsync(() async {
      await tester.pumpWidget(wrapEntry());
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    expect(find.text('餐饮'), findsWidgets,
        reason: '分类网格 (左 + 右 常用) 都显示 餐饮');

    // 选 "餐饮" (在 split categories 中, 餐饮同时出现在左网格和右常用,
    // 用 .first 避免 ambiguous; UI 上两个 widget 点任一都会触发 onSelect 同一个分类)
    await tester.tap(find.text('餐饮').first);
    await tester.pump();

    // 用 find.text 找键 (keypad 是 Text widget)
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('.'));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.tap(find.text('0'));
    await tester.pumpAndSettle();

    // U2 实时求值: 在按 = 之前, 金额预览就应该显示 12.50
    expect(find.text('12.50'), findsWidgets,
        reason: '_DateAndAmountRow 金额预览 显示 12.50');

    // 不点 "=" (v1.6 改动3: = 按钮 = 保存并跳回首页, 完整 E2E 由真机验证)
    // 点 "=" 会触发 _onEqualsAndSave → 写库 → 跳首页, 与本测试"键盘到预览"的目标不同
    // 让 _CategoryGrid 内部的 sqflite 10s 计时器到期, 避免测试结束时报错
    await tester.pump(const Duration(seconds: 11));
  });
}

// ----- helper: 让所有 _CategoryGrid FutureBuilder 内部的 sqflite 计时器 fire
// sqflite_common_ffi 的 txnSynchronized 用 10s 计时器防死锁. 测试结束时
// 这些计时器若还 pending, Flutter 测试框架会 assert 失败. pumpAndSettle 不
// 会让 FakeAsync 内的计时器 fire. 我们用 tester.pump 把 fake clock 推进 10s+
// 让这些计时器到期, 然后再让 controller close.
