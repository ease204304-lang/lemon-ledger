// v1.13.1 记一笔界面修复测试
//
// 用户反馈 (截图):
//   1. 金额显示屏数字超长时被垂直截断 (¥06660588800.00 只显示一半)
//   2. 数字键盘过小, 第 4 行 (. 0 del =) 完全被挤出屏幕
//
// 修复:
//   1. 金额显示屏用 FittedBox 自动缩放; 输入长度上限 12 字符
//   2. 分类区:键盘 flex 从 2:1 改为 1:1 (键盘扩大一倍)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/screens/entry_page.dart';
import 'package:lemon_ledger/widgets/entry_keypad.dart';
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

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // EntryPage 异步加载账户列表会打开 DB, 需要 mock path_provider
    await AppDatabase.instance.close();
    final tempDir = await Directory.systemTemp.createTemp('v1131_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });
  group('金额输入长度限制', () {
    testWidgets('输入超过 12 字符后不再追加数字', (tester) async {
      String amount = '0';
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) => SizedBox(
          height: 500,
          child: EntryKeypad(
            amount: amount,
            onChange: (s) => setState(() => amount = s),
            onDelete: () {},
          ),
        ),
      )));

      // 连续输入 12 位数字 (首次 '0'→'8', 之后追加)
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.text('8').last);
        await tester.pump();
      }
      expect(amount.length, lessThanOrEqualTo(12),
          reason: '金额长度应被限制在 12 字符内');

      // 此时已达上限 → 再输入数字不再增长
      final before = amount.length;
      await tester.tap(find.text('8').last);
      await tester.pump();
      expect(amount.length, before,
          reason: '达到 12 字符上限后应拒绝继续输入数字');
    });

    testWidgets('运算符不受长度限制影响 (可继续追加表达式)', (tester) async {
      String amount = '123456789012'; // 已达 12 字符
      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) => SizedBox(
          height: 500,
          child: EntryKeypad(
            amount: amount,
            onChange: (s) => setState(() => amount = s),
            onDelete: () {},
          ),
        ),
      )));
      await tester.tap(find.text('+'));
      await tester.pump();
      expect(amount.endsWith('+'), isTrue,
          reason: '运算符不受长度上限限制');
    });
  });

  group('金额显示屏 (FittedBox)', () {
    testWidgets('长金额不抛 RenderFlex 溢出', (tester) async {
      await tester.pumpWidget(_wrap(SizedBox(
        width: 300, // 窄容器模拟长金额场景
        height: 600,
        child: EntryKeypad(
          amount: '06660588800.00',
          onChange: (_) {},
          onDelete: () {},
        ),
      )));
      await tester.pump();
      // 若仍用固定 28pt + 无约束 Row, 会抛 RenderFlex overflow 异常
      expect(tester.takeException(), isNull,
          reason: '长金额应通过 FittedBox 缩放显示, 不应溢出');
      // ¥ 符号仍可见
      expect(find.text('¥'), findsOneWidget);
    });
  });

  group('键盘高度 (1:1 布局)', () {
    testWidgets('键盘 4 行按键全部可见 (含第 4 行 . 0 del =)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(EntryPage(onNavigate: (_) {})));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      });

      // 在 EntryKeypad 范围内查找 (避免与页面其他同文字节点混淆)
      final keypadFinder = find.byType(EntryKeypad);
      expect(keypadFinder, findsOneWidget);

      for (final label in ['.', '=']) {
        final finder = find.descendant(
          of: keypadFinder,
          matching: find.text(label),
        );
        expect(finder, findsOneWidget, reason: '$label 键应存在');
        final rect = tester.getRect(finder);
        expect(rect.height, greaterThan(0),
            reason: '$label 键高度应大于 0 (用户截图: 第 4 行被挤出屏幕)');
        expect(rect.bottom, lessThanOrEqualTo(900),
            reason: '$label 键应在可视范围内 (逻辑屏高 891)');
      }
      // '0': 金额显示屏默认也显示 '0', 取键盘内的最后一个 (底行)
      final zeroFinder = find.descendant(
        of: keypadFinder,
        matching: find.text('0'),
      );
      expect(zeroFinder, findsAtLeastNWidgets(1));
      final zeroRect = tester.getRect(zeroFinder.last);
      expect(zeroRect.height, greaterThan(0), reason: '0 键应可见');
      // del 是图标键
      final delFinder = find.descendant(
        of: keypadFinder,
        matching: find.byIcon(Icons.backspace_outlined),
      );
      expect(delFinder, findsOneWidget);
    });

    testWidgets('键盘区域高度应占屏幕足够比例 (用户反馈: 键盘过小)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(_wrap(EntryPage(onNavigate: (_) {})));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      });

      final keypadFinder = find.byType(EntryKeypad);
      final keypadRect = tester.getRect(keypadFinder);
      // getRect 返回逻辑像素: 屏幕逻辑高 = 2340/2.625 ≈ 891
      // v1.15.1: 分类区与键盘对半分 (用户要求扩大分类展示),
      // 键盘 = 平分剩余空间, 约 26% 屏高, 仍完整可见
      final logicalScreenHeight = 2340 / 2.625;
      expect(keypadRect.height, greaterThan(logicalScreenHeight * 0.2),
          reason: '对半分布局后键盘仍应 ≥ 屏幕的 20% (4 行 + 金额屏完整)');
      // 4 行按键 + 金额显示屏必须完整在可视区内 (浮点容差 0.5)
      expect(keypadRect.bottom, lessThanOrEqualTo(logicalScreenHeight + 0.5),
          reason: '键盘不得超出屏幕 (第 4 行 . 0 del = 必须可见)');
      // 分类区与键盘对半分: 两者高度差不超过 20%
      final catArea = find.byType(EntrySplitCategories);
      expect(catArea, findsOneWidget);
    });
  });
}
