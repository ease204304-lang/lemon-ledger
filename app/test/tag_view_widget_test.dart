// v1.8.0 标签视图 widget 测试
// 覆盖:
//   - 图表页 分类/标签 二级切换 (标签分析卡片 + 饼图 + 排序切换)
//   - 记帐页标签行 "全部" → TagManagerPage 跳转 (P0-2 逻辑级验证)
// 注意: sqflite_ffi 需要真实异步时间, 用 tester.runAsync 模式 (与 ui_test 一致)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/screens/chart_page.dart';
import 'package:lemon_ledger/screens/entry_page.dart';
import 'package:lemon_ledger/screens/tag_manager_page.dart';
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

  setUp(() async {
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('tag_view_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Widget _wrap(Widget child) =>
      MaterialApp(theme: buildLightTheme(), home: child);

  /// 启动 + 等真实异步 (sqflite_ffi 查询) 完成
  Future<void> _boot(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(child));
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
  }

  /// 点击后等动画 (无需真实异步)
  Future<void> _afterTap(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('ChartPage 标签视图 (v1.8.0)', () {
    // 注意: 图表按"当前周/上周"等相对周期取数, 种子流水固定在 2026-10-05..09,
    //       随系统日期推移可能落在周期外 → 标签视图显示空态。
    //       所以这里断言"视图结构"而非"具体数据", 数据口径由 tag_stats_test.dart 覆盖。
    testWidgets('切到标签视图: 显示 标签分析卡片 (或空态) + 排序切换', (tester) async {
      await _boot(tester, ChartPage(onNavigate: (_) {}));

      // 默认分类视图: 排行榜可见, 无 标签分析
      expect(find.text('支出排行榜'), findsOneWidget);
      expect(find.text('标签分析'), findsNothing);

      // 点 "标签" 切换 chip
      await tester.tap(find.text('标签'));
      await _afterTap(tester);

      // 标签视图已激活 (卡片标题 或 空态提示 二者其一)
      final hasCard = find.text('标签分析').evaluate().isNotEmpty;
      final hasEmpty = find.textContaining('本周期暂无标签数据').evaluate().isNotEmpty;
      expect(hasCard || hasEmpty, isTrue);
      // 分类视图内容已隐藏
      expect(find.text('支出排行榜'), findsNothing);

      // 有数据时: 排序切换 + 标签名
      if (hasCard) {
        expect(find.text('按金额'), findsOneWidget);
        expect(find.text('按时间'), findsOneWidget);
        expect(find.text('信托'), findsWidgets);
      }
    });

    testWidgets('按时间排序: 切换后仍渲染标签视图', (tester) async {
      await _boot(tester, ChartPage(onNavigate: (_) {}));
      await tester.tap(find.text('标签'));
      await _afterTap(tester);
      if (find.text('按时间').evaluate().isNotEmpty) {
        await tester.tap(find.text('按时间'));
        await _afterTap(tester);
      }
      final hasCard = find.text('标签分析').evaluate().isNotEmpty;
      final hasEmpty = find.textContaining('本周期暂无标签数据').evaluate().isNotEmpty;
      expect(hasCard || hasEmpty, isTrue);
    });

    testWidgets('切回分类视图: 标签视图消失, 排行榜回来', (tester) async {
      await _boot(tester, ChartPage(onNavigate: (_) {}));
      await tester.tap(find.text('标签'));
      await _afterTap(tester);
      await tester.tap(find.text('分类'));
      await _afterTap(tester);
      expect(find.text('标签分析'), findsNothing);
      expect(find.text('支出排行榜'), findsOneWidget);
    });
  });

  group('记帐页 "全部" 跳转 TagManagerPage (P0-2)', () {
    testWidgets('tap 标签行 全部 → TagManagerPage 出现', (tester) async {
      await _boot(tester, EntryPage(onNavigate: (_) {}));

      // v1.8.0 修复: 标签行接入 build → "全部" 入口可见
      expect(find.text('全部'), findsWidgets);

      // v1.9.0: "全部" 在 SingleChildScrollView 里可能需要滚动到可见
      await tester.ensureVisible(find.text('全部').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部').last, warnIfMissed: false);
      await _afterTap(tester);
      // 等 TagManagerPage 的 _load 真实完成 (避免 tearDown 竞态)
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // TagManagerPage 被推入 (AppBar 标题 "所有标签")
      expect(find.byType(TagManagerPage), findsOneWidget);
      expect(find.text('所有标签'), findsOneWidget);
    });

    testWidgets('TagManagerPage 显示种子标签 (按频次)', (tester) async {
      await _boot(tester, const TagManagerPage());

      // 餐饮 (4 次) / 停车费 (2 次) 在
      expect(find.text('餐饮'), findsWidgets);
      expect(find.text('停车费'), findsWidgets);
      // 新建按钮存在
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('带分类模式: 标题为 分类名 · 标签', (tester) async {
      await _boot(tester, const TagManagerPage(
        categoryId: 'cat.transport',
        categoryName: '交通',
      ));
      expect(find.text('交通 · 标签'), findsOneWidget);
      // 交通分类的标签: 交通/单车/充电
      expect(find.text('单车'), findsOneWidget);
      expect(find.text('充电'), findsOneWidget);
      // 不该有 咖啡 (饮品分类)
      expect(find.text('咖啡'), findsNothing);
    });
  });
}
