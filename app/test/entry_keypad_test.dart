// EntryKeypad 交互回归测试 (v1.11.0)
//
// 背景: 模拟器端到端测试时发现「App 自带数字键盘点击无响应」, 分类按钮却正常。
// 本测试直接对 EntryKeypad 做 widget 级点击, 定位问题在 widget 本身还是在
// 宿主的触摸注入 / 系统输入法干扰。
//
// 覆盖:
//   1. 点击数字键 → onChange 收到新金额
//   2. 点击小数点 → 金额带小数
//   3. 点击退格 → onDelete 触发
//   4. 点击 = → onEqualsAndSave 触发
//   5. 长按 . → onLongPressMic 触发 (语音录入入口)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_ledger/widgets/entry_keypad.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 420,
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('点击数字键应触发 onChange', (tester) async {
    var amount = '0';
    await tester.pumpWidget(_wrap(EntryKeypad(
      amount: amount,
      onChange: (s) => amount = s,
      onDelete: () {},
    )));

    // 「5」在第 2 行第 2 列
    final five = find.text('5');
    expect(five, findsOneWidget);

    await tester.tap(five);
    await tester.pump();

    expect(amount, '5', reason: '点击数字键后金额应更新');
  });

  testWidgets('连续点击 3 8 应拼成 38', (tester) async {
    var amount = '0';
    // 用 StatefulBuilder 把最新金额回传给 widget, 模拟真实页面的受控用法
    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => EntryKeypad(
        amount: amount,
        onChange: (s) => setState(() => amount = s),
        onDelete: () {},
      ),
    )));

    await tester.tap(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('8'));
    await tester.pump();

    expect(amount, '38');
  });

  testWidgets('点击小数点应追加小数', (tester) async {
    var amount = '0';
    await tester.pumpWidget(_wrap(EntryKeypad(
      amount: amount,
      onChange: (s) => amount = s,
      onDelete: () {},
    )));

    await tester.tap(find.text('.'));
    await tester.pump();

    expect(amount.contains('.'), isTrue,
        reason: '点击小数点后金额应包含小数点');
  });

  testWidgets('点击退格应触发 onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(_wrap(EntryKeypad(
      amount: '12',
      onChange: (_) {},
      onDelete: () => deleted = true,
    )));

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();

    expect(deleted, isTrue);
  });

  testWidgets('点击 = 应触发 onEqualsAndSave', (tester) async {
    var saved = false;
    await tester.pumpWidget(_wrap(EntryKeypad(
      amount: '0',
      onChange: (_) {},
      onDelete: () {},
      onEqualsAndSave: () => saved = true,
    )));

    await tester.tap(find.text('='));
    await tester.pump();

    expect(saved, isTrue);
  });

  testWidgets('长按小数点应触发语音录入', (tester) async {
    var mic = false;
    await tester.pumpWidget(_wrap(EntryKeypad(
      amount: '0',
      onChange: (_) {},
      onDelete: () {},
      onLongPressMic: () => mic = true,
    )));

    await tester.longPress(find.text('.'));
    await tester.pump();

    expect(mic, isTrue);
  });
}
