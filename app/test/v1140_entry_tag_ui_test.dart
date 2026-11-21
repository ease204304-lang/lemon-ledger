// v1.14.0 UI 行为测试: 标签点击 → 自动选中分类; 切换收支 → 标签集不同
//
// 关键: 沿用项目既有模式 (见 ui_test.dart) —— 所有交互放在同一个
//       tester.runAsync 内, 否则 setState 触发的 FutureBuilder 重建会在
//       FakeAsync 区里卡住 sqflite_ffi 查询。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/data/models.dart';
import 'package:lemon_ledger/data/tag_service.dart';
import 'package:lemon_ledger/screens/entry_page.dart';
import 'package:lemon_ledger/theme/tokens.dart';
import 'package:lemon_ledger/widgets/entry_split_categories.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String tempDir;
  _MockPathProvider(this.tempDir);
  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir;
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child, backgroundColor: L.surfaceSubtle));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('v1140ui_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  group('标签点击行为', () {
    testWidgets('点击标签 → 自动选中绑定分类 + 追加到备注', (tester) async {
      // 准备: 「停车费」绑定到支出·交通
      // (在 runAsync 外做 DB 写入会与 widget tree 的 DB 访问竞争, 放入 runAsync)
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      String noteText = '';
      String? selectedCatName;
      String? selectedCatId;

      await tester.runAsync(() async {
        final svc = TagService.instance;
        await svc.addOrBump('停车费');
        await svc.bindCategory('停车费', TxType.expense, 'cat.transport');

        // 关键: DB 数据必须在 pumpWidget 之前就绪,
        // 否则 initState 里的 _loadTags() 查询不到绑定数据
        await tester.pumpWidget(_wrap(EntryPage(onNavigate: (_) {})));
        // 等首屏分类 + 标签加载完
        for (var i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        // 关键: setState 后必须 pump 才会重建 (否则标签仍是空列表)
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        // 标签行应显示「停车费」
        expect(find.text('停车费'), findsOneWidget,
            reason: '未选分类时应显示当前类型的常用标签');

        // 点击标签
        await tester.tap(find.text('停车费'));
        for (var i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        // setState 后必须 pump 才会重建 widget 树
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        // 读备注框内容
        final noteField = find.byType(TextField).first;
        noteText = tester.widget<TextField>(noteField).controller!.text;

        // 断言: 「交通」分类被自动选中
        // 最可靠方式: 读 EntrySplitCategories 的 selected 属性
        final split = tester.widget<EntrySplitCategories>(
          find.byType(EntrySplitCategories),
        );
        selectedCatName = split.selected?.name;
        selectedCatId = split.selected?.id;
      });

      expect(noteText, '停车费', reason: '点击标签应把标签追加到备注');
      expect(selectedCatId, 'cat.transport',
          reason: '点「停车费」应自动选中绑定的「交通」分类');
      expect(selectedCatName, '交通');
    });

    testWidgets('切换收入 → 标签行内容变为收入标签', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      var expHasParking = false;
      var incHasParking = false;
      var incHasBonus = false;

      await tester.runAsync(() async {
        final svc = TagService.instance;
        await svc.addOrBump('停车费');
        await svc.bindCategory('停车费', TxType.expense, 'cat.transport');
        await svc.addOrBump('年终奖');
        await svc.bindCategory('年终奖', TxType.income, 'cat.bonus');

        await tester.pumpWidget(_wrap(EntryPage(onNavigate: (_) {})));
        for (var i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        // 支出态
        expHasParking = find.text('停车费').evaluate().isNotEmpty;
        expect(find.text('年终奖').evaluate(), isEmpty,
            reason: '支出态不应显示收入侧标签');

        // 切到收入
        await tester.tap(find.text('收入'));
        for (var i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        incHasParking = find.text('停车费').evaluate().isNotEmpty;
        incHasBonus = find.text('年终奖').evaluate().isNotEmpty;
      });

      expect(expHasParking, isTrue, reason: '支出态应显示「停车费」');
      expect(incHasBonus, isTrue, reason: '收入态应显示「年终奖」');
      expect(incHasParking, isFalse,
          reason: '支出侧标签不应出现在收入态');
    });
  });
}
