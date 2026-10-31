/// 记账页数字键盘 (v1.9.0 重设计: 顶部加金额显示屏)
///
/// 布局 (v1.9.0):
/// ```
///   ┌──────────────────────┐
///   │     ¥ 12.50          │  ← 金额显示屏 (大字, U2 实时求值)
///   ├──────┬──────┬──────┬─┤
///   │  7   │  8   │  9   │ ×│
///   │  4   │  5   │  6   │ −│
///   │  1   │  2   │  3   │ +│
///   │  .   │  0   │ del  │ =│
///   └──────┴──────┴──────┴─┘
/// ```
/// 数字键 1-9 自底向上 (3x3), 0 居中底行, .  在底行第 1 列
/// 运算符 第 4 列: × − +, = 合并保存 (改动 3)
///
/// U2 实时求值: onChange 会传回 _amount 字符串, 父 widget 自己实时算
/// v1.9.0: 金额显示屏替代原来 _TypeAndDateRow 里的金额预览
///
/// 短按 "." = 小数点
/// 长按 "." = 语音录入
library;

import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../utils/calculator.dart';

class EntryKeypad extends StatelessWidget {
  final String amount;
  final ValueChanged<String> onChange;
  final VoidCallback onDelete;
  final VoidCallback? onEqualsAndSave; // 改动 3: = = 保存 (合并)
  final VoidCallback? onSave; // 编辑模式保留的独立保存按钮
  final VoidCallback? onLongPressMic;
  final bool showSaveButton; // 编辑模式显示
  const EntryKeypad({
    super.key,
    required this.amount,
    required this.onChange,
    required this.onDelete,
    this.onEqualsAndSave,
    this.onSave,
    this.onLongPressMic,
    this.showSaveButton = false,
  });

  @override
  Widget build(BuildContext context) {
    // 4 行 4 列, 123456789 自底向上
    const rows = [
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['.', '0', 'del', '='], // 改动 3: = 列是合并保存
    ];
    return Container(
      color: L.surface,
      child: Column(
        children: [
          // v1.9.0: 金额显示屏 (大字, U2 实时求值, 圆圈位置)
          _AmountDisplay(amount: amount),
          // 键盘 4×4
          for (final row in rows)
            Expanded(
              child: Row(
                children: [
                  for (final k in row)
                    Expanded(
                      child: KeyButton(
                        label: k,
                        onTap: () => _onKey(k),
                        onLongPress: k == '.' ? onLongPressMic : null,
                        isEquals: k == '=',
                      ),
                    ),
                ],
              ),
            ),
          if (showSaveButton)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: L.brandYellow,
                    foregroundColor: L.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('保存修改',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 处理单键按下
  void _onKey(String k) {
    if (k == 'del') {
      onDelete();
      return;
    }
    if (k == '=') {
      // 改动 3: = = 保存 (合并)
      onEqualsAndSave?.call();
      return;
    }
    if (k == '.') {
      // 小数点
      final last = amount.isNotEmpty ? amount[amount.length - 1] : '';
      if (isOp(last)) {
        onChange('$amount' '0.');
      } else if (!currentNumberHasDot(amount)) {
        onChange(amount + '.');
      }
      return;
    }
    if (isOp(k)) {
      // 运算符
      final last = amount.isNotEmpty ? amount[amount.length - 1] : '';
      if (isOp(last)) {
        onChange(amount.substring(0, amount.length - 1) + k);
      } else if (last == '.') {
        return;
      } else {
        onChange(amount + k);
      }
      return;
    }
    // 数字
    final last = amount.isNotEmpty ? amount[amount.length - 1] : '';
    if (amount == '0' && !isOp(k)) {
      onChange(k);
    } else if (isOp(last)) {
      onChange(amount + k);
    } else if (last == '.') {
      final idx = amount.lastIndexOf('.');
      final after = amount.substring(idx + 1);
      if (after.length < 2) {
        onChange(amount + k);
      }
    } else {
      onChange(amount + k);
    }
  }
}

/// v1.9.0: 金额显示屏 (大字 + ¥ 前缀, U2 实时求值)
/// 位于键盘顶部, 替代原来 _TypeAndDateRow 里的金额预览
class _AmountDisplay extends StatelessWidget {
  final String amount;
  const _AmountDisplay({required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: L.surfaceSubtle,
        border: Border(
          bottom: BorderSide(color: L.dividerLight, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('¥',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: L.textTertiary)),
          const SizedBox(width: 4),
          Text(
            _fmtAmount(amount),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: L.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// U2: 实时求值预览 (与原 _TypeAndDateRow._fmtAmount 逻辑一致)
  String _fmtAmount(String expr) {
    if (expr == '0') return '0';
    if (!exprHasOp(expr)) {
      return toYuanString(evalCents(expr));
    }
    final lastOp = expr.lastIndexOf(RegExp(r'[+×−]'));
    if (lastOp < 0) return toYuanString(evalCents(expr));
    final completed = expr.substring(0, lastOp);
    final rest = expr.substring(lastOp);
    final result = evalCents(completed);
    final resultStr = toYuanString(result);
    return '$resultStr$rest';
  }
}

/// 单个键
///
/// 视觉:
///   数字键: 大字号 28pt
///   运算符: 半高小字号 22pt, 浅黄背景
///   =: 大字号 30pt, 品牌黄背景
class KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isEquals;
  const KeyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.isEquals = false,
  });

  @override
  Widget build(BuildContext context) {
    final isOpCharLabel = isOp(label) && !isEquals;
    final isDot = label == '.';

    Widget child;
    if (label == 'del') {
      child = const Icon(Icons.backspace_outlined,
          color: L.textPrimary, size: 18);
    } else if (isEquals) {
      // = 按钮: 品牌黄大字
      child = const Text('=',
          style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: L.textPrimary));
    } else if (isOpCharLabel) {
      // 运算符: 浅色 (在品牌黄底上)
      child = Text(label,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: L.textPrimary.withValues(alpha: 0.7)));
    } else if (isDot) {
      child = Stack(
        alignment: Alignment.center,
        children: [
          const Text('.',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: L.textPrimary)),
          const Positioned(
            right: 12,
            top: 6,
            child: Icon(Icons.mic, size: 9, color: L.textTertiary),
          ),
        ],
      );
    } else {
      // 数字: 大字
      child = Text(label,
          style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w500,
              color: L.textPrimary));
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 第 4 列 (运算符 + =): 统一品牌黄 (像设计图那样整列黄)
          color: isOpCharLabel
              ? L.brandYellowTrack
              : (isEquals
                  ? L.brandYellow
                  : L.surface),
          border: Border(
            top: BorderSide(color: L.dividerLight, width: 0.5),
            right: BorderSide(color: L.dividerLight, width: 0.5),
          ),
        ),
        child: child,
      ),
    );
  }
}
