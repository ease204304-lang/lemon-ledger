/// 计算器表达式求值 (v1.2.5 重构, v1.5.0 抽出为共享工具)
/// 原内联在 entry_page.dart, 抽到这里供 keypad 复用 + 单测
library calculator_utils;

/// 表达式求值, 返回分 (cents).
/// 支持: +  -  −  ×  ÷
/// 例如:
///   "12"        → 1200
///   "12.5"      → 1250
///   "12+5"      → 1700
///   "100÷4"     → 2500
///   "12+5*3"    → 2700 (先算 ×)
///   "12*3+4"    → 4000 (先算 ×)
///   "10-2-3"    → 500  (左结合)
///   "23−36"     → -1300 (用户截图场景, 中文 minus 字符)
///   "100÷0"     → 0 (不崩溃)
int evalCents(String expr) {
  if (expr.isEmpty || expr == '0') return 0;
  // 单数字
  if (!exprHasOp(expr)) {
    return toCents(expr);
  }
  // 转 token: 数字 (含小数) 与运算符
  final tokens = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < expr.length; i++) {
    final c = expr[i];
    if (isOpChar(c)) {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      tokens.add(c);
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());

  if (tokens.isEmpty) return 0;

  // 先算 × ÷
  final stack = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t == '×' || t == '÷') {
      if (stack.isEmpty || i + 1 >= tokens.length) continue;
      final left = double.tryParse(stack.removeLast()) ?? 0;
      final right = double.tryParse(tokens[++i]) ?? 0;
      final r = t == '×' ? left * right : (right == 0 ? 0 : left / right);
      stack.add(r.toString());
    } else {
      stack.add(t);
    }
  }
  // 再算 + -
  double result = double.tryParse(stack.first) ?? 0;
  for (var i = 1; i < stack.length; i += 2) {
    if (i + 1 >= stack.length) break;
    final op = stack[i];
    // 兼容 − (Chinese minus) 和 - (ASCII)
    final right = double.tryParse(stack[i + 1]) ?? 0;
    if (op == '+') {
      result += right;
    } else if (op == '-' || op == '−') {
      result -= right;
    }
  }
  return (result * 100).round();
}

bool exprHasOp(String s) {
  for (var i = 0; i < s.length; i++) {
    if (isOpChar(s[i])) return true;
  }
  return false;
}

/// 是不是单字符运算符 (+, -, −, ×, ÷)
bool isOpChar(String c) =>
    c == '+' || c == '-' || c == '−' || c == '×' || c == '÷';

/// 是不是单字符显示用运算符 (UI 上显示的 + - × ÷, 不含 - 与 − 的区分)
bool isOp(String c) => c == '+' || c == '−' || c == '×' || c == '÷';

/// 当前正在输入的"数字段"里有没有小数点
bool currentNumberHasDot(String expr) {
  for (var i = expr.length - 1; i >= 0; i--) {
    if (isOp(expr[i])) {
      return expr.substring(i + 1).contains('.');
    }
  }
  return expr.contains('.');
}

int toCents(String s) {
  if (s.isEmpty || s == '0') return 0;
  if (s == '.') return 0;
  final v = double.tryParse(s) ?? 0;
  return (v * 100).round();
}

String toYuanString(int cents) {
  if (cents == 0) return '0';
  return (cents / 100).toStringAsFixed(2);
}
