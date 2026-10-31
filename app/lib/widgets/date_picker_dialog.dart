/// 日期选择对话框 (v1.8.1)
///
/// 相比系统 `showDatePicker` 的改进:
///   1. **双击某一天 = 确定** (直接选好并关闭, 不用再点"确定")
///      实现: 点已选中的那天 → 直接确定 (不限点击速度); 或 400ms 内双击同一天 → 确定
///   2. 单击 = 选中 (高亮), 再点一次 = 确认返回
///   3. 保留"取消"按钮 + 底部快捷入口 (今天 / 昨天 / 前天)
///   4. 风格与应用一致 (品牌黄选中态, 7 列网格, 周一开头)
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 弹出日期选择对话框
///
/// 返回选中的日期; 用户取消则返回 null。
///
/// [initialDate] 初始选中的日期
/// [firstDate] / [lastDate] 可选范围
/// [quickDays] 底部快捷天数 (相对今天), 默认 [0] 今天
Future<DateTime?> showAppDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  List<int> quickDays = const [0],
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _DatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
      quickDays: quickDays,
    ),
  );
}

class _DatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<int> quickDays;
  const _DatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.quickDays,
  });

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late DateTime _month; // 当前显示的月份 (1 号)
  late DateTime _selected; // 当前选中日期
  DateTime? _lastTapDay; // 上一次点击的日期 (用于双击判定)
  DateTime? _lastTapAt; // 上一次点击时间

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _month = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
  }

  bool _inRange(DateTime d) =>
      !d.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day)) &&
      !d.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day));

  /// 双击判定: 同一日期 + 400ms 内
  bool _isDoubleTap(DateTime day) {
    final now = DateTime.now();
    if (_lastTapDay != null &&
        _lastTapDay!.year == day.year &&
        _lastTapDay!.month == day.month &&
        _lastTapDay!.day == day.day &&
        _lastTapAt != null &&
        now.difference(_lastTapAt!).inMilliseconds < 400) {
      _lastTapDay = null;
      return true;
    }
    _lastTapDay = day;
    _lastTapAt = now;
    return false;
  }

  void _onDayTap(DateTime day) {
    if (!_inRange(day)) return;
    final isSameAsSelected = _selected.year == day.year &&
        _selected.month == day.month &&
        _selected.day == day.day;
    // 规则 1: 点已选中的那天 → 直接确定 (双击的等价操作, 不受点击速度限制)
    // 规则 2: 快速双击同一天 (400ms 内) → 确定
    if (isSameAsSelected || _isDoubleTap(day)) {
      Navigator.of(context).pop(day);
      return;
    }
    // 单击 → 选中
    setState(() => _selected = day);
  }

  void _confirm() => Navigator.of(context).pop(_selected);

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  /// 快捷日期 (今天 / 昨天 ...)
  DateTime? _quickDate(int daysAgo) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
    return _inRange(d) ? d : null;
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // 周一开头: leading = weekday - 1
    final leading = _month.weekday - 1;
    final total = leading + daysInMonth;
    final rows = (total / 7).ceil();
    final today = DateTime.now();

    return Dialog(
      backgroundColor: L.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部: 取消 + 年月 + 确定
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消',
                      style: TextStyle(color: L.textSecondary, fontSize: 14)),
                ),
                const Spacer(),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: L.textPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: _confirm,
                  child: const Text('确定',
                      style: TextStyle(
                          color: L.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            // 月份切换
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left, color: L.textPrimary),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: L.textBody)),
                const Spacer(),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right, color: L.textPrimary),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 星期表头
            Row(
              children: const [
                _Wday('一'), _Wday('二'), _Wday('三'), _Wday('四'),
                _Wday('五'), _Wday('六'), _Wday('日'),
              ],
            ),
            const SizedBox(height: 4),
            // 日期网格
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    _buildCell(r, c, leading, daysInMonth, today),
                ],
              ),
            const SizedBox(height: 6),
            const Divider(height: 1, color: L.dividerLight),
            // 底部快捷 + 提示
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  for (final d in widget.quickDays) ...[
                    if (_quickDate(d) != null)
                      _QuickChip(
                        label: _quickLabel(d),
                        onTap: () => Navigator.of(context).pop(_quickDate(d)),
                      ),
                    const SizedBox(width: 8),
                  ],
                  const Spacer(),
                  const Text('单击选中 · 再点一次确定',
                      style: TextStyle(fontSize: 11, color: L.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _quickLabel(int daysAgo) {
    if (daysAgo == 0) return '今天';
    if (daysAgo == 1) return '昨天';
    if (daysAgo == 2) return '前天';
    return '$daysAgo 天前';
  }

  Widget _buildCell(int r, int c, int leading, int daysInMonth, DateTime today) {
    final dayNum = r * 7 + c - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const Expanded(child: SizedBox(height: 40));
    }
    final day = DateTime(_month.year, _month.month, dayNum);
    final enabled = _inRange(day);
    final isSelected = _selected.year == day.year &&
        _selected.month == day.month &&
        _selected.day == day.day;
    final isToday = today.year == day.year &&
        today.month == day.month &&
        today.day == day.day;

    return Expanded(
      child: InkWell(
        onTap: enabled ? () => _onDayTap(day) : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 40,
          margin: const EdgeInsets.all(2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? L.brandYellow : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday && !isSelected
                ? Border.all(color: L.brandYellow, width: 1.5)
                : null,
          ),
          child: Text(
            '$dayNum',
            style: TextStyle(
              color: enabled ? L.textPrimary : L.textDisabled,
              fontSize: 14,
              fontWeight: isSelected || isToday
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _Wday extends StatelessWidget {
  final String w;
  const _Wday(this.w);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(w,
            style: const TextStyle(fontSize: 12, color: L.textTertiary)),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: L.surfaceNote,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: L.textBody)),
      ),
    );
  }
}
