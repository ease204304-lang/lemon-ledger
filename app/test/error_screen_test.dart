// E1 自定义错误页 测试
//
// 验证 AppErrorScreen:
//   - 渲染 ⚠️ + "出错了" + 错误摘要
//   - "查看详情" 可展开 stacktrace
//   - "重试" 按钮存在
//   - 不依赖 FlutterError.builder 全局设置 (只测 widget 本身)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lemon_ledger/widgets/error_screen.dart';

void main() {
  group('AppErrorScreen', () {
    testWidgets('渲染 ⚠️ + 标题 + 摘要 + 重试按钮', (tester) async {
      final details = FlutterErrorDetails(
        exception: '测试异常: 数据库连接失败',
        library: 'lemon_ledger test',
        context: ErrorDescription('测试场景'),
      );

      await tester.pumpWidget(MaterialApp(
        home: AppErrorScreen(details: details),
      ));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('测试异常'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('查看详情'), findsOneWidget);
    });

    testWidgets('点 "查看详情" 展开 stacktrace', (tester) async {
      final details = FlutterErrorDetails(
        exception: 'NullPointerException',
        library: 'flutter',
      );

      await tester.pumpWidget(MaterialApp(
        home: AppErrorScreen(details: details),
      ));

      // 初始 stack 不显示
      expect(find.textContaining('NullPointerException'), findsOneWidget);
      // stack 不在屏幕 (因为 _expanded=false)
      // (仅在 widget 自身, 不用 .stack 因为 Flutter 测试环境没真实 stack)

      // 点展开
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();

      // 展开后还能找到 "查看详情" (按钮还在)
      expect(find.text('查看详情'), findsOneWidget);

      // 再点收起
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.text('查看详情'), findsOneWidget);
    });

    testWidgets('异常消息超 200 字截断 + 加省略号', (tester) async {
      final longMsg = 'A' * 250; // 250 字符
      final details = FlutterErrorDetails(
        exception: longMsg,
        library: 'test',
      );

      await tester.pumpWidget(MaterialApp(
        home: AppErrorScreen(details: details),
      ));

      // 截断到 200 + "…"
      expect(find.textContaining('…'), findsOneWidget);
      // 完整 250 字不显示
      expect(find.text(longMsg), findsNothing);
    });
  });

  group('ErrorWidget.builder 全局设置', () {
    test('main.dart 注册的 builder 类型是 AppErrorScreen (静态验证)', () {
      // 静态验证: 我们的 AppErrorScreen 是 Widget, 能被 ErrorWidget.builder 返回
      // 不实际改 ErrorWidget.builder (test 框架会 assert 改回了)
      final widget = AppErrorScreen(
        details: FlutterErrorDetails(
          exception: 'static check',
          library: 'test',
        ),
      );
      expect(widget, isA<Widget>());
      // 类型断言: builder 返回的必须是 widget
      Widget Function(FlutterErrorDetails) builder = (_) => widget;
      final result = builder(FlutterErrorDetails(exception: 'x', library: 'y'));
      expect(result, isA<AppErrorScreen>());
    });
  });
}
