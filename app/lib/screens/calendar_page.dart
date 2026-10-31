/// 日历页 (v1.2: 预算感知)
///
/// 月历: 每格显示**净支出** + 红绿圆点 (超预算/未超预算) + 日均预算
/// 点某天 -> 弹当日流水
library calendar_page;

import 'package:flutter/material.dart';

import '../data/budget_service.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import '../widgets/category_icon.dart';

class CalendarPage extends StatefulWidget {
  final DateTime month;
  const CalendarPage({super.key, required this.month});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month;
  Map<int, (int expense, int income)> _dayTotals = {};
  Map<String, Category> _cats = {};
  List<Tx> _dayTxs = const [];
  int? _selectedDay;
  int _monthBudgetCents = 0; // 0 = 未设置预算
  int _dailyBudgetCents = 0;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.month.year, widget.month.month, 1);
    _load();
  }

  Future<void> _load() async {
    final totals = await TxRepository.instance.monthDayTotals(_month.year, _month.month);
    final cats = await CategoryRepository.instance.all();
    final budget = await BudgetService.instance.get(_month.year, _month.month);
    final daily = BudgetService.instance.dailyBudgetCents(budget, _month.year, _month.month);
    if (!mounted) return;
    setState(() {
      _dayTotals = totals;
      _cats = {for (final c in cats) c.id: c};
      _monthBudgetCents = budget;
      _dailyBudgetCents = daily;
    });
  }

  Future<void> _loadDay(int day) async {
    final epoch = _dateToEpochDay(_month.add(Duration(days: day - 1)));
    final txs = await TxRepository.instance.byDay(epoch);
    if (!mounted) return;
    setState(() {
      _selectedDay = day;
      _dayTxs = txs;
    });
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
      _selectedDay = null;
      _dayTxs = const [];
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1, 1);
      _selectedDay = null;
      _dayTxs = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // 周一开始: weekday 1=Mon..7=Sun
    final firstWeekday = _month.weekday;
    // 前面空格数 (header 占 7 列, 前面是 firstWeekday-1 个空格)
    final leading = firstWeekday - 1;
    final total = leading + daysInMonth;
    final rows = (total / 7).ceil();

    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      appBar: AppBar(
        backgroundColor: L.surface,
        elevation: 0,
        title: Text('${_month.year}年${_month.month}月',
            style: const TextStyle(
                color: L.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: L.textPrimary),
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
                _selectedDay = null;
                _dayTxs = const [];
              });
              _load();
            },
            icon: const Icon(Icons.today, color: L.textPrimary),
          ),
        ],
      ),
      body: Column(
        children: [
          // 月份切换
          Container(
            color: L.surface,
            padding: const EdgeInsets.fromLTRB(L.pageH, 4, L.pageH, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: _prevMonth,
                  icon: const Icon(Icons.chevron_left),
                  label: Text('${_month.month - 1 <= 0 ? 12 : _month.month - 1}月'),
                ),
                Text('${_month.year}年${_month.month}月',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: L.textPrimary)),
                TextButton.icon(
                  onPressed: _nextMonth,
                  icon: const Icon(Icons.chevron_right, color: L.textPrimary),
                  label: Text('${_month.month + 1 > 12 ? 1 : _month.month + 1}月'),
                  style: TextButton.styleFrom(foregroundColor: L.textPrimary),
                ),
              ],
            ),
          ),
          // 星期表头
          Container(
            color: L.surface,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: const [
                _Wday('一'), _Wday('二'), _Wday('三'), _Wday('四'),
                _Wday('五'), _Wday('六'), _Wday('日'),
              ],
            ),
          ),
          const Divider(height: 1, color: L.dividerLight),
          // 日历网格
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var r = 0; r < rows; r++)
                    Row(
                      children: [
                        for (var c = 0; c < 7; c++) _buildCell(r, c, leading, daysInMonth),
                      ],
                    ),
                ],
              ),
            ),
          ),
          // 日均预算 + 颜色图例
          Container(
            color: L.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                if (_monthBudgetCents > 0) ...[
                  Text('日均预算: ', style: const TextStyle(color: L.textTertiary, fontSize: 12)),
                  Text(_fmt(_dailyBudgetCents), style: const TextStyle(
                      color: L.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 16),
                ] else ...[
                  const Text('提示: 设置月预算后可显示日均预算', style: TextStyle(color: L.textTertiary, fontSize: 12)),
                  const SizedBox(width: 12),
                ],
                const Spacer(),
                const _LegendDot(color: L.okGreen, label: '节余'),
                const SizedBox(width: 8),
                const _LegendDot(color: L.brandYellow, label: '正常'),
                const SizedBox(width: 8),
                const _LegendDot(color: L.warnRed, label: '超支'),
              ],
            ),
          ),
          // 当日流水
          if (_selectedDay != null) _DayDetail(
            day: _selectedDay!,
            month: _month,
            txs: _dayTxs,
            cats: _cats,
            onClose: () => setState(() {
              _selectedDay = null;
              _dayTxs = const [];
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(int r, int c, int leading, int daysInMonth) {
    final idx = r * 7 + c;
    final dayNum = idx - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const Expanded(child: SizedBox(height: 60));
    }
    final epoch = _dateToEpochDay(DateTime(_month.year, _month.month, dayNum));
    final totals = _dayTotals[epoch];
    final hasData = totals != null && (totals.$1 + totals.$2) > 0;
    final isToday = _isToday(_month.year, _month.month, dayNum);
    final isSelected = _selectedDay == dayNum;

    // 净支出 = 支出 - 收入; 0 = 节余; > 0 = 超支
    final netCents = hasData ? (totals!.$1 - totals.$2) : 0;
    final netYuan = (netCents.abs() / 100).round();

    // 颜色规则: 预算感知
    // 1) 未设置预算: 只看收入/支出 (有=红, 无=浅绿, 收入=绿)
    // 2) 已设置预算: net > 日均 → 红; net <= 0 → 绿; 0 < net <= 日均 → 浅绿/淡黄
    Color bgColor = Colors.transparent;
    if (hasData) {
      if (_dailyBudgetCents > 0) {
        if (netCents <= 0) {
          bgColor = const Color(0x1A4FBC8B); // 浅绿底
        } else if (netCents > _dailyBudgetCents) {
          bgColor = const Color(0x1AF5222D); // 浅红底
        } else {
          bgColor = const Color(0x1AFFD946); // 浅黄底
        }
      } else {
        // 无预算: 收入 → 浅绿; 净支出 → 浅红
        if (totals!.$2 > 0 && totals.$1 == 0) {
          bgColor = const Color(0x1A4FBC8B);
        } else {
          bgColor = const Color(0x1AF5222D);
        }
      }
    }

    return Expanded(
      child: InkWell(
        onTap: () => _loadDay(dayNum),
        child: Container(
          height: 60,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected ? L.brandYellow : bgColor,
            borderRadius: BorderRadius.circular(8),
            border: isToday && !isSelected
                ? Border.all(color: L.brandYellow, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$dayNum',
                style: TextStyle(
                  color: L.textPrimary,
                  fontSize: 15,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 1),
              if (hasData)
                Text(
                  netCents >= 0 ? '-$netYuan' : '+$netYuan',
                  style: TextStyle(
                    color: netCents >= 0 ? L.warnRed : L.okGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                const SizedBox(height: 13),
            ],
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
        child: Text(w, style: const TextStyle(color: L.textTertiary, fontSize: 12)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: L.textTertiary, fontSize: 11)),
      ],
    );
  }
}

class _DayDetail extends StatelessWidget {
  final int day;
  final DateTime month;
  final List<Tx> txs;
  final Map<String, Category> cats;
  final VoidCallback onClose;
  const _DayDetail({
    required this.day, required this.month, required this.txs, required this.cats, required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final inc = txs.where((t) => t.type == TxType.income).fold<int>(0, (s, t) => s + t.amountCents);
    final exp = txs.where((t) => t.type == TxType.expense).fold<int>(0, (s, t) => s + t.amountCents);
    return Container(
      color: L.surface,
      constraints: const BoxConstraints(maxHeight: 280),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Text('${month.month}月$day日',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: L.textPrimary)),
                const Spacer(),
                if (inc > 0) Text('收入 ${_fmt(inc)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF4FBC8B))),
                if (inc > 0 && exp > 0) const SizedBox(width: 12),
                if (exp > 0) Text('支出 ${_fmt(exp)}',
                    style: const TextStyle(fontSize: 12, color: L.warnRed)),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: L.dividerLight),
          Expanded(
            child: txs.isEmpty
                ? const Center(child: Text('该日无流水', style: TextStyle(color: L.textTertiary)))
                : ListView.separated(
                    itemCount: txs.length,
                    separatorBuilder: (_, _) => const Divider(
                        height: 1, thickness: 0.5, color: L.dividerLight, indent: 56),
                    itemBuilder: (context, i) {
                      final t = txs[i];
                      final cat = cats[t.categoryId];
                      return ListTile(
                        leading: CategoryIcon(iconKey: cat?.iconKey ?? 'else', size: 36),
                        title: Text(
                          t.note.isNotEmpty ? t.note : (cat?.name ?? '未分类'),
                          style: const TextStyle(fontSize: 14, color: L.textPrimary, fontWeight: FontWeight.w500),
                        ),
                        trailing: Text(
                          '${t.type == TxType.income ? '+' : '-'}${(t.amountCents / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600, color: L.textPrimary),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int cents) {
  if (cents == 0) return '0';
  final s = (cents / 100).toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${buf.toString()}.${parts[1]}';
}

int _dateToEpochDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
        86400000;

bool _isToday(int y, int m, int d) {
  final n = DateTime.now();
  return n.year == y && n.month == m && n.day == d;
}
