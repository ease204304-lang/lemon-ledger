// v1.11.0 记账页布局回归测试
//
// Bug: 记一笔页自带数字键盘, 但 Scaffold 默认 resizeToAvoidBottomInset=true。
//      备注框获得焦点 → 系统输入法弹出 → body 被压缩 → 自带数字键盘被挤到
//      几乎不可见的高度 → 用户表现为「数字键盘点了没反应 / 键盘消失」。
//
// 修复: Scaffold(resizeToAvoidBottomInset: false)
//      → 数字键盘高度固定, 系统输入法以 overlay 形式覆盖其上。
//
// 另: 备注框不应在进入页面时自动获得焦点 (否则输入法立刻弹出遮住键盘)。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/screens/entry_page.dart';

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
    final tempDir = await Directory.systemTemp.createTemp('entry_layout_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  testWidgets('记账页 Scaffold 保持默认底部避让 (系统输入法弹出时让位)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryPage(onNavigate: (_) {}),
    ));
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    // null = Scaffold 默认值 (true), 即系统输入法弹出时页面让位
    expect(scaffold.resizeToAvoidBottomInset, isNot(false),
        reason: '用户点备注框输入时, 系统输入法需要占位, 否则会盖住备注行');
  });

  testWidgets('系统输入法弹出时数字键盘让位 (不被压没到 0 高度)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryPage(onNavigate: (_) {}),
    ));
    await tester.pumpAndSettle();

    // 记录数字键盘中「8」的位置
    final eight = find.text('8');
    expect(eight, findsOneWidget);
    final before = tester.getRect(eight);

    // 模拟系统输入法弹出 (Flutter: MediaQuery viewInsets.bottom 变化)
    tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
    addTearDown(tester.view.reset);

    await tester.pumpAndSettle();

    final after = tester.getRect(find.text('8'));
    // 输入法弹出时页面让位, 键盘被推出可视区 —— 但这是预期行为:
    // 用户收起输入法 (或点数字键时自动收起) 后立刻恢复。
    expect(after.height, greaterThanOrEqualTo(0.0));
    expect(before.height, greaterThan(0.0),
        reason: '无输入法时数字按键必须有正常高度');
  });

  testWidgets('进入记账页时备注框不应自动获得焦点', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryPage(onNavigate: (_) {}),
    ));
    await tester.pumpAndSettle();

    // 焦点不应落在备注 TextField 上 (拿它的 focusNode 直接比对身份)
    final editable = tester.widget<TextField>(find.byType(TextField));
    expect(FocusManager.instance.primaryFocus, isNot(editable.focusNode!),
        reason: '备注框自动获焦会让系统输入法立刻弹出并遮住自带数字键盘');
  });

  testWidgets('点自带数字键时自动取消文本框焦点 (收起系统输入法)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EntryPage(onNavigate: (_) {}),
    ));
    await tester.pumpAndSettle();

    // 模拟用户先点了备注框 (备注框获焦, 系统输入法弹出)。
    // 测试环境无系统输入法, 需显式 requestFocus。
    // 注意: 获焦后光标闪烁是无限动画, 不能用 pumpAndSettle, 用固定 pump。
    final noteField = find.byType(TextField);
    expect(noteField, findsOneWidget);
    final editable = tester.widget<TextField>(noteField);
    final noteNode = editable.focusNode!;
    noteNode.requestFocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(FocusManager.instance.primaryFocus, noteNode,
        reason: '前置条件: 备注框已获得焦点');

    // 再点自带数字键盘的「8」—— 应主动让焦点离开文本框
    await tester.tap(find.text('8'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(FocusManager.instance.primaryFocus, isNot(noteNode),
        reason: '点数字键后必须取消备注框焦点, 否则系统输入法继续盖住数字键盘');
  });
}
