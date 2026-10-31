// v1.8.1 Bug 修复测试
//
// Bug1: 增加记录过程点击回退直接退出应用 -> 应回到主页面
// Bug2: 日期选择界面双击具体日期应代替"确定"动作
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lemon_ledger/data/database.dart';
import 'package:lemon_ledger/main.dart';
import 'package:lemon_ledger/screens/entry_page.dart';
import 'package:lemon_ledger/screens/home_page.dart';
import 'package:lemon_ledger/theme/tokens.dart';
import 'package:lemon_ledger/widgets/date_picker_dialog.dart';

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
    final tempDir = await Directory.systemTemp.createTemp('bug81_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<void> _boot(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(child);
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
  }

  // RootShell needs MaterialApp shell (Directionality + Navigator)
  Widget _shell() => MaterialApp(
        theme: buildLightTheme(),
        home: const RootShell(),
      );

  /// 等首页重载完成 (跑在 runAsync 里给 sqflite_ffi 真实时间)
  Future<void> _settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 24; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    // 冲掉 sqflite 的 10s watchdog timer
    await tester.pump(const Duration(seconds: 11));
  }

  group('Bug1: back key on entry page returns home', () {
    testWidgets('RootShell at EntryPage: pop goes home, does not exit',
        (tester) async {
      await _boot(tester, _shell());

      // initial: home
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(EntryPage), findsNothing);

      // tap the + tab to switch to entry page
      await tester.tap(find.text('记帐'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EntryPage), findsOneWidget);

      // simulate system back
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      // key: we are back at home (route NOT exited)
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(EntryPage), findsNothing);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('RootShell at ChartPage: pop goes home', (tester) async {
      await _boot(tester, _shell());

      await tester.tap(find.text('图表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);

      expect(find.byType(HomePage), findsOneWidget);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('RootShell at HomePage: pop allowed (exit app)', (tester) async {
      await _boot(tester, _shell());
      expect(find.byType(HomePage), findsOneWidget);

      // on home the route may pop (exit app) - PopScope.canPop = true
      final scope = tester.widget<PopScope<dynamic>>(
        find.byWidgetPredicate((w) => w is PopScope<dynamic>).first,
      );
      expect(scope.canPop, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Bug2: double tap on a day confirms the date', () {
    // shell that opens the date dialog
    Widget _pickerShell(ValueChanged<DateTime?> onPicked) =>
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  onPicked(await showAppDatePicker(ctx,
                      initialDate: DateTime(2026, 10, 18)));
                },
                child: const Text('open'),
              ),
            ),
          ),
        );

    testWidgets('single tap selects but keeps dialog open', (tester) async {
      DateTime? result;
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('确定'), findsOneWidget);

      // single tap on day 15
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // dialog still open
      expect(find.text('确定'), findsOneWidget);
      expect(result, isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('double tap confirms and closes with that date',
        (tester) async {
      DateTime? result;
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // double tap day 15 (gap < 350ms)
      await tester.tap(find.text('15'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('确定'), findsNothing);
      expect(result, isNotNull);
      expect(result!.year, 2026);
      expect(result!.month, 10);
      expect(result!.day, 15);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('two taps on different days is not a double tap',
        (tester) async {
      DateTime? result;
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('21'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('22'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // different days -> not confirmed
      expect(find.text('确定'), findsOneWidget);
      expect(result, isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('tap the selected day again confirms (speed independent)',
        (tester) async {
      DateTime? result;
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // initialDate is 2026-10-18 -> day 18 is already selected
      await tester.tap(find.text('18'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // tapping the selected day confirms right away
      expect(find.text('确定'), findsNothing);
      expect(result, isNotNull);
      expect(result!.day, 18);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('confirm button still works after single tap',
        (tester) async {
      DateTime? result;
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('确定'), findsNothing);
      expect(result!.day, 8);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('cancel returns null', (tester) async {
      DateTime? result = DateTime(2020);
      await _boot(tester, _pickerShell((d) => result = d));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('取消'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('quick chip today returns today immediately', (tester) async {
      DateTime? result;
      await _boot(
        tester,
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async {
                  result = await showAppDatePicker(ctx,
                      initialDate: DateTime(2026, 10, 18),
                      quickDays: const [0, 1]);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('今天'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(result, isNotNull);
      final now = DateTime.now();
      expect(result!.day, now.day);
      expect(result!.month, now.month);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
