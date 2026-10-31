/// 明细首页 (v1.2 升级, v1.5.0 拆分)
/// 私有 widget 已拆到 lib/widgets/home_*.dart
///
/// 参考"鲨鱼记账":
///   黄色 header (logo + 搜索/日历)
///   月份选择 + 当月 收入/支出 (可点 → 排行页)
///   快捷入口 (账单/预算/资产管家/购物返现/更多)
///   按日分组的流水 (可折叠, 删除需确认)
library home_page;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import '../utils/date_utils.dart';
import '../widgets/date_picker_dialog.dart';
import '../widgets/home_day_section.dart';
import '../widgets/home_header.dart';
import '../widgets/home_quick_actions.dart';
import '../widgets/top_tab_bar.dart';
import 'entry_page.dart';
import 'ranking_page.dart';
import 'quick_entry_sheet.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const HomePage({super.key, required this.onNavigate});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // 当前显示的月份 (年月)
  late DateTime _monthAnchor;
  bool _showAmount = true;
  late Future<_HomeData> _future;
  // 每个 day 配一个 GlobalKey, 给 ListView 滚动用
  final Map<int, GlobalKey> _dayKeys = {};
  // 选完日期后, 高亮该日 (清掉折叠)
  int? _highlightDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthAnchor = DateTime(now.year, now.month, 1);
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final repo = TxRepository.instance;
    final start = DateTime(_monthAnchor.year, _monthAnchor.month, 1);
    final end = DateTime(_monthAnchor.year, _monthAnchor.month + 1, 0);
    final startDay = dateToEpochDay(start);
    final endDay = dateToEpochDay(end);
    final txs = await repo.byDateRange(startDay, endDay);
    final cats = {
      for (final c in await CategoryRepository.instance.all()) c.id: c
    };
    final sum = await repo.sumByRange(startDay, endDay);
    // 提取有数据的日 (升序)
    final availableDays = <int>{for (final t in txs) t.epochDay}.toList()
      ..sort();
    return _HomeData(
      month: _monthAnchor,
      txs: txs,
      cats: cats,
      expenseCents: sum.$1,
      incomeCents: sum.$2,
      availableDays: availableDays,
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _changeMonth(int delta) {
    setState(() {
      _monthAnchor =
          DateTime(_monthAnchor.year, _monthAnchor.month + delta, 1);
      _highlightDay = null;
      _future = _load();
    });
  }

  /// 直接跳到指定年月
  void _setMonth(int year, int month) {
    setState(() {
      _monthAnchor = DateTime(year, month, 1);
      _highlightDay = null;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: L.surfaceSubtle,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. 黄色 header (logo + 搜索/日历)
            HomeHeader(
              onSearch: _openSearch,
              onCalendar: _openCalendar,
            ),
            // 2. 月份 + 收入/支出 + 可见性
            HomeMonthSummary(
              month: _monthAnchor,
              incomeCents:
                  _future.then((d) => d.incomeCents),
              expenseCents:
                  _future.then((d) => d.expenseCents),
              showAmount: _showAmount,
              onToggleAmount: () =>
                  setState(() => _showAmount = !_showAmount),
              onPrevMonth: () => _changeMonth(-1),
              onNextMonth: () => _changeMonth(1),
              onPickMonth: (d) => _setMonth(d.year, d.month),
              onStatTap: _openRanking,
            ),
            // 3. 快捷入口
            const HomeQuickActions(),
            // 4. 流水列表
            Expanded(
              child: FutureBuilder<_HomeData>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('错误: ${snap.error}'));
                  }
                  return HomeBody(
                    data: snap.data!,
                    onChanged: _reload,
                    dayKeys: _dayKeys,
                    highlightDay: _highlightDay,
                    onEdit: _openEntryEdit,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: TopTabBar(
        currentIndex: 0,
        onTap: widget.onNavigate,
        onAddLongPress: () => showQuickEntrySheet(context),
      ),
    );
  }

  void _openSearch() async {
    final picked = await Navigator.of(context).push<Tx>(
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
    if (picked != null) {
      // 跳到该笔所在月份
      final d = epochDayToDate(picked.epochDay);
      setState(() {
        _monthAnchor = DateTime(d.year, d.month, 1);
        _future = _load();
      });
    }
  }

  /// 日历按钮 → 弹出日期选择对话框 (v1.8.1: 双击某天 = 确定)
  /// 选完日期后: 跳到该日所在月份, 自动滚到该日
  /// 如果该日没数据, 滚到最近的有数据的日
  void _openCalendar() async {
    final today = todayEpochDay();
    final picked = await showAppDatePicker(
      context,
      initialDate: epochDayToDate(today),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      quickDays: const [0, 1, 2],
    );
    if (picked != null) {
      final pickedDay = dateToEpochDay(picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('已选择 ${picked.year}年${picked.month}月${picked.day}日'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // 等待数据加载完后, 找最近有数据的日
      setState(() {
        _monthAnchor = DateTime(picked.year, picked.month, 1);
        _highlightDay = pickedDay;
        _future = _load().then((data) {
          int? nearest = _findNearestDay(pickedDay, data.availableDays);
          if (nearest != null && nearest != pickedDay) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _highlightDay = nearest);
                final ndt = epochDayToDate(nearest);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('该日无数据, 已跳到 ${ndt.month}月${ndt.day}日'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            });
          }
          // 5s 后清掉高亮
          Future.delayed(const Duration(milliseconds: 5000), () {
            if (mounted) setState(() => _highlightDay = null);
          });
          return data;
        });
      });
    }
  }

  /// 从 availableDays 找离 targetDay 最近的日 (二分)
  int? _findNearestDay(int targetDay, List<int> days) {
    if (days.isEmpty) return null;
    if (days.contains(targetDay)) return targetDay;
    int lo = 0, hi = days.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (days[mid] < targetDay) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final before = lo > 0 ? days[lo - 1] : null;
    final after = lo < days.length ? days[lo] : null;
    if (before == null) return after;
    if (after == null) return before;
    return (targetDay - before) <= (after - targetDay) ? before : after;
  }

  void _openRanking(TxType type) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RankingPage(
        year: _monthAnchor.year,
        month: _monthAnchor.month,
        type: type,
      ),
    ));
  }

  /// 点流水 → 直接进入 EntryPage (编辑模式)
  void _openEntryEdit(Tx tx) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EntryPage(
        onNavigate: (i) {
          if (i == 0) {
            Navigator.of(context).pop();
            _reload();
          }
        },
        editTxId: tx.id,
      ),
    ));
  }
}

class _HomeData {
  final DateTime month;
  final List<Tx> txs;
  final Map<String, Category> cats;
  final int expenseCents;
  final int incomeCents;
  final List<int> availableDays; // 当月有数据的日 (升序)
  _HomeData({
    required this.month,
    required this.txs,
    required this.cats,
    required this.expenseCents,
    required this.incomeCents,
    required this.availableDays,
  });
}

/// Home 屏内部 Body (ListView + 折叠状态)
class HomeBody extends StatefulWidget {
  final _HomeData data;
  final VoidCallback onChanged;
  final Map<int, GlobalKey>? dayKeys;
  final int? highlightDay;
  final ValueChanged<Tx> onEdit;
  const HomeBody({
    super.key,
    required this.data,
    required this.onChanged,
    this.dayKeys,
    this.highlightDay,
    required this.onEdit,
  });

  @override
  State<HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends State<HomeBody> {
  final Set<int> _collapsed = {};
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void didUpdateWidget(covariant HomeBody old) {
    super.didUpdateWidget(old);
    if (widget.highlightDay != null &&
        widget.highlightDay != old.highlightDay) {
      _collapsed.remove(widget.highlightDay!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollTo(widget.highlightDay!);
      });
    }
  }

  void _scrollTo(int day) {
    final key = widget.dayKeys?[day];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    // 找到 ListView 自身的 RenderObject, 然后用 Scrollable.ensureVisible
    // alignment 0.2 让日期显示在视窗上 1/5 处 (留出顶部黄色 header)
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 600),
      alignment: 0.1,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<Tx>>{};
    for (final t in widget.data.txs) {
      byDay.putIfAbsent(t.epochDay, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    if (widget.data.txs.isEmpty) {
      return const _Empty();
    }
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(L.pageH, 12, L.pageH, 16),
      children: [
        for (final d in days) ...[
          HomeDayHeader(
            day: d,
            txs: byDay[d]!,
            collapsed: _collapsed.contains(d),
            showAmount: true, // day header 始终显示汇总 (顶层没 hide 时)
            highlight: widget.highlightDay == d,
            // 用 compute 方法懒分配: 不存在则新建, 避免 GlobalKey 多处持有冲突
            dayKey: widget.dayKeys!.putIfAbsent(d, () => GlobalKey()),
            onToggle: () => setState(() {
              if (_collapsed.contains(d)) {
                _collapsed.remove(d);
              } else {
                _collapsed.add(d);
              }
            }),
          ),
          if (!_collapsed.contains(d))
            HomeDayGroup(
              txs: byDay[d]!,
              cats: widget.data.cats,
              showAmount: true,
              onTap: widget.onEdit,
            ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
          child:
              Text('本月暂无流水', style: TextStyle(color: L.textSecondary))),
    );
  }
}
