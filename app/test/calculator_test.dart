// 计算器键盘测试 (v1.2.5, v1.5.0 改用共享 calculator.dart)
//
// 测试共享的 evalCents() 函数:
//   "12"       → 1200
//   "12.5"     → 1250
//   "12+5"     → 1700
//   "100÷4"    → 2500
//   "12+5*3"   → 2700 (先算 ×)
//   "12*3+4"   → 4000 (先算 ×)
//   "10-2-3"   → 500  (左结合)

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_ledger/utils/calculator.dart';

void main() {
  group('计算器表达式求值', () {
    test('纯数字: 12', () {
      expect(evalCents('12'), equals(1200));
    });

    test('小数: 12.5', () {
      expect(evalCents('12.5'), equals(1250));
    });

    test('加法: 12+5', () {
      expect(evalCents('12+5'), equals(1700));
    });

    test('减法: 100-30', () {
      expect(evalCents('100-30'), equals(7000));
    });

    test('减法: 100−30 (中文 minus 字符)', () {
      expect(evalCents('100−30'), equals(7000));
    });

    test('减法: 23−36 = -13 (用户截图场景)', () {
      expect(evalCents('23−36'), equals(-1300));
    });

    test('乘法: 12×3', () {
      expect(evalCents('12×3'), equals(3600));
    });

    test('除法: 100÷4', () {
      expect(evalCents('100÷4'), equals(2500));
    });

    test('优先级: 12+5×3 = 27 (先乘后加)', () {
      expect(evalCents('12+5×3'), equals(2700));
    });

    test('优先级: 12×3+4 = 40 (先乘后加)', () {
      expect(evalCents('12×3+4'), equals(4000));
    });

    test('连减: 10-2-3 = 5 (左结合)', () {
      expect(evalCents('10-2-3'), equals(500));
    });

    test('除以零: 100÷0 = 0 (不崩溃)', () {
      expect(evalCents('100÷0'), equals(0));
    });

    test('空字符串: 0', () {
      expect(evalCents(''), equals(0));
    });

    test('小数除法: 10÷4 = 2.50', () {
      // (10/4)*100 = 250, .round() = 250
      expect(evalCents('10÷4'), equals(250));
    });

    test('混合小数: 1.5+2.3 = 3.80', () {
      // (1.5+2.3)*100 = 380
      expect(evalCents('1.5+2.3'), equals(380));
    });
  });
}
