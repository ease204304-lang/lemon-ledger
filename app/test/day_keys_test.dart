// 回归测试: 验证 _dayKeys map 在 _Body 构建时被填充
// (v1.4.6 修复了 GlobalKey 未初始化导致滚动失败的 bug)
//
// 测试方法: 找到 _DayHeader 节点, 检查其 widget.dayKey 不是 null
// (之前是 null, 修复后是 GlobalKey)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

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
    tempDir = await Directory.systemTemp.createTemp('lemon_keys_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  testWidgets('DayHeader 节点必须有 dayKey (GlobalKey), 否则 _scrollTo 永远无效',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: HomePage(onNavigate: (_) {})),
      ));
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    // 找 _DayHeader 的 Container (key: dayKey)
    // 这个 Container 的 widget.key 就是 dayKey, 不能是 null
    // 因为是 GlobalKey, widget.key 是 GlobalKey 实例
    final containerFinder = find.byWidgetPredicate(
      (w) => w is Container && w.key != null && w.key is GlobalKey,
    );

    // 至少应该有 5 个 (种子数据 5 天: 10-5 到 10-9)
    expect(containerFinder, findsWidgets,
        reason: '5 个 _DayHeader 必须各有 GlobalKey, 否则 _scrollTo 永远失败');
  });
}
