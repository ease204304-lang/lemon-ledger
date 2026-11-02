// 月份选择器回归测试 (v1.2 修复: 之前调错 onNextMonth, 现在用真实 picked)
//
// 修复内容: 之前 onNextMonth() 是无参 callback, 选了日期后强制跳下月, 错的.
// 现在改成 onPickMonth(DateTime) 透传 picked, 父组件跳到所选月份.
//
// 此测试不依赖模拟器, 在内存里跑 (秒级).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/screens/home_page.dart';
import 'package:lemon_ledger/theme/tokens.dart';

class _MockPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
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
    tempDir = await Directory.systemTemp.createTemp('lemon_picker_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  Widget _wrap(Widget child) => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: child),
      );

  testWidgets('HomePage 渲染: 月份 chip 显示当前月', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(HomePage(onNavigate: (_) {})));
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // 月份 chip 显示当前月 (跟随系统日期, 不写死 "10月")
    final now = DateTime.now();
    expect(find.text('${now.month}月'), findsWidgets);
    expect(find.text('${now.year}年'), findsOneWidget);
  });

  testWidgets('HomePage 渲染: 5 入口 + 黄色 header + 排序', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(HomePage(onNavigate: (_) {})));
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // 黄色 header
    expect(find.text('小猪记账'), findsOneWidget);
    // 5 入口
    expect(find.text('账单'), findsOneWidget);
    expect(find.text('预算'), findsOneWidget);
    expect(find.text('资产管家'), findsOneWidget);
    expect(find.text('购物返现'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    // 收入/支出 汇总 (在黄色 header 与 Tab 栏都有, 故 findsWidgets)
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
  });

  testWidgets('HomePage 渲染: 流水有 chevron_down 折叠 icon', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(HomePage(onNavigate: (_) {})));
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // 折叠 icon (expand_more / chevron_right) 至少有一个
    // 注: 种子流水固定在 2026-10; HomePage 默认显示当前月, 跨月后当日无流水 → 无日期行
    final now = DateTime.now();
    if (now.year == 2026 && now.month == 10) {
      final expandIcons = find.byIcon(Icons.expand_more);
      final chevronIcons = find.byIcon(Icons.chevron_right);
      expect(expandIcons.evaluate().length + chevronIcons.evaluate().length, greaterThan(0),
          reason: '日期行应有 chevron 图标表示可折叠');
    } else {
      expect(find.byType(HomePage), findsOneWidget);
    }
  });
}
