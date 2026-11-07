/// 统计模块状态层 (v1.11.0 W3)
///
/// 对应《记账统计模块技术实施说明书》v0.9 §05 前端组件和状态。
///
/// 状态分层 (TECH 05):
///   - 持久偏好: 统计类型 + 日期选择 (快捷项保存类型并重算, 自定义保存日期值)
///   - 会话/临时: 已应用筛选 / 草稿筛选 / 排序 / 折叠 / 滚动位置
///   - 全局: 当前账本
///
/// 一致性 (TECH 04 呈现 / D03):
///   - 客户端按 条件标识 + 请求代次 + 快照版本 接收结果
///   - 切换筛选时清除旧内容; 当前条件刷新可短暂保留整屏旧数据
///   - 切换至新版本时未返回模块显示加载态
///   - 旧请求晚到 → 丢弃, 不得覆盖新结果 (T08)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/stats_api.dart';

/// 快捷日期项 (PRD 03: 近7/30/90天, 本月, 上月, 本年, 自定义)
enum QuickRange {
  last7Days,
  last30Days,
  last90Days,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

extension QuickRangeX on QuickRange {
  String get label => switch (this) {
        QuickRange.last7Days => '近7天',
        QuickRange.last30Days => '近30天',
        QuickRange.last90Days => '近90天',
        QuickRange.thisMonth => '本月',
        QuickRange.lastMonth => '上月',
        QuickRange.thisYear => '本年',
        QuickRange.custom => '自定义',
      };

  /// 快捷项 (自定义除外) 都是滚动范围, 包含今天 (PRD 03)
  bool get isRolling => this != QuickRange.custom;
}

/// 一个已解析的日期区间
class DateRange {
  final DateTime start; // 含
  final DateTime end; // 含
  final QuickRange source;

  const DateRange({
    required this.start,
    required this.end,
    required this.source,
  });

  int get days =>
      end.difference(DateTime(start.year, start.month, start.day)).inDays + 1;

  /// 粒度规则 (PRD 03 / C29):
  ///   1–31 天按天, 32–365 天按周, 超过 365 天按月
  TrendGranularity get granularity {
    final d = days;
    if (d <= 31) return TrendGranularity.day;
    if (d <= 365) return TrendGranularity.week;
    return TrendGranularity.month;
  }

  /// 同期对比区间 (PRD 03):
  ///   本周对上周, 本月对上月, 本年对上年, 自定义对紧邻等长历史周期
  DateRange? previousRange() {
    switch (source) {
      case QuickRange.last7Days:
      case QuickRange.last30Days:
      case QuickRange.last90Days:
        // 滚动范围 → 紧邻等长历史周期
        final len = days;
        return DateRange(
          start: start.subtract(Duration(days: len)),
          end: end.subtract(Duration(days: len)),
          source: source,
        );
      case QuickRange.thisMonth:
        final pm = DateTime(start.year, start.month - 1, 1);
        return DateRange(
          start: pm,
          end: DateTime(pm.year, pm.month + 1, 0),
          source: source,
        );
      case QuickRange.lastMonth:
        final lm = DateTime(start.year, start.month - 1, 1);
        return DateRange(
          start: lm,
          end: DateTime(lm.year, lm.month + 1, 0),
          source: source,
        );
      case QuickRange.thisYear:
        return DateRange(
          start: DateTime(start.year - 1, 1, 1),
          end: DateTime(start.year - 1, 12, 31),
          source: source,
        );
      case QuickRange.custom:
        final len = days;
        return DateRange(
          start: start.subtract(Duration(days: len)),
          end: end.subtract(Duration(days: len)),
          source: source,
        );
    }
  }

  @override
  String toString() =>
      '${_fmt(start)}..${_fmt(end)} (${days}d, ${granularity.name})';

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 草稿筛选 (临时勾选在确认前不触发查询 — PRD 05)
class CategoryDraft {
  final CategoryMode mode;
  final Set<String> ids;

  const CategoryDraft({required this.mode, required this.ids});

  const CategoryDraft.all() : mode = CategoryMode.all, ids = const {};

  bool get isAll => mode == CategoryMode.all;

  CategoryDraft copyWith({CategoryMode? mode, Set<String>? ids}) =>
      CategoryDraft(mode: mode ?? this.mode, ids: ids ?? this.ids);
}

/// 统计模块状态控制器
class StatsController extends ChangeNotifier {
  final StatsApiClient api;

  StatsController({StatsApiClient? api})
      : api = api ?? StatsApiClient(baseUrl: StatsApiClient.endpoint);

  // ── 持久偏好 (统计类型 + 日期选择) ──
  StatsView _view = StatsView.expense;
  QuickRange _quickRange = QuickRange.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _comparisonEnabled = false;

  // ── 会话/临时状态 ──
  CategoryDraft _incomeDraft = const CategoryDraft.all();
  CategoryDraft _expenseDraft = const CategoryDraft.all();
  CategoryDraft _appliedIncome = const CategoryDraft.all();
  CategoryDraft _appliedExpense = const CategoryDraft.all();
  RankSort _sortBy = RankSort.amount;
  bool _rankingExpanded = false;

  // ── 数据 ──
  StatsSummary? _summary;
  List<TrendPoint> _trend = const [];
  CategoryRanking _categories = const CategoryRanking(items: [], total: '0.00');
  BalanceRanking? _balance;
  TagChart? _tags;
  MerchantRanking? _merchants;

  bool _loading = false;
  String? _error;
  int _errorCode;
  int _snapshotVersion = 0;
  String _conditionKey = '';

  /// 请求代次 — 旧请求晚到直接丢弃 (D03 / T08)
  int _requestGeneration = 0;
  /// 已应用筛选版本 — 用于判断草稿是否已应用
  bool _draftDirty = false;

  // ── getters ──
  StatsView get view => _view;
  QuickRange get quickRange => _quickRange;
  bool get comparisonEnabled => _comparisonEnabled;
  RankSort get sortBy => _sortBy;
  bool get rankingExpanded => _rankingExpanded;
  bool get draftDirty => _draftDirty;
  CategoryDraft get incomeDraft => _incomeDraft;
  CategoryDraft get expenseDraft => _expenseDraft;
  CategoryDraft get appliedIncome => _appliedIncome;
  CategoryDraft get appliedExpense => _appliedExpense;
  StatsSummary? get summary => _summary;
  List<TrendPoint> get trend => _trend;
  CategoryRanking get categories => _categories;
  BalanceRanking? get balance => _balance;
  TagChart? get tags => _tags;
  MerchantRanking? get merchants => _merchants;
  bool get loading => _loading;
  String? get error => _error;
  int get errorCode => _errorCode;
  int get snapshotVersion => _snapshotVersion;

  /// 当前已解析的日期区间
  DateRange get dateRange {
    final today = DateTime.now();
    switch (_quickRange) {
      case QuickRange.last7Days:
        return DateRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
          source: _quickRange,
        );
      case QuickRange.last30Days:
        return DateRange(
          start: today.subtract(const Duration(days: 29)),
          end: today,
          source: _quickRange,
        );
      case QuickRange.last90Days:
        return DateRange(
          start: today.subtract(const Duration(days: 89)),
          end: today,
          source: _quickRange,
        );
      case QuickRange.thisMonth:
        return DateRange(
          start: DateTime(today.year, today.month, 1),
          end: DateTime(today.year, today.month + 1, 0),
          source: _quickRange,
        );
      case QuickRange.lastMonth:
        return DateRange(
          start: DateTime(today.year, today.month - 1, 1),
          end: DateTime(today.year, today.month, 0),
          source: _quickRange,
        );
      case QuickRange.thisYear:
        return DateRange(
          start: DateTime(today.year, 1, 1),
          end: DateTime(today.year, 12, 31),
          source: _quickRange,
        );
      case QuickRange.custom:
        final s = _customStart ?? DateTime(today.year, today.month, 1);
        final e = _customEnd ?? today;
        return DateRange(start: s, end: e, source: _quickRange);
    }
  }

  /// 当前查询条件 (已应用)
  StatsQuery buildQuery({String bookId = 'book_001'}) {
    final r = dateRange;
    return StatsQuery(
      bookId: bookId,
      view: _view,
      startDate: DateRange._fmt(r.start),
      endDate: DateRange._fmt(r.end),
      granularity: r.granularity,
      comparisonEnabled: _comparisonEnabled,
      incomeCategoryMode: _appliedIncome.mode,
      incomeCategoryIds: _appliedIncome.ids.toList(),
      expenseCategoryMode: _appliedExpense.mode,
      expenseCategoryIds: _appliedExpense.ids.toList(),
      sortBy: _sortBy,
    );
  }

  // ── 操作 ──

  /// 切换视图 (PRD 06 页面切换)
  ///
  /// 收入 ↔ 支出: 保留时间范围与仍有效的筛选, 自动清除无效条件, 合并为一条轻提示
  /// 进入结余: 进入结余总览并清除原统计筛选
  void switchView(StatsView v) {
    if (_view == v) return;
    _view = v;
    if (v == StatsView.balance) {
      // PRD 06 R3: 进入结余 → 清除原统计筛选
      _appliedIncome = const CategoryDraft.all();
      _appliedExpense = const CategoryDraft.all();
      _incomeDraft = const CategoryDraft.all();
      _expenseDraft = const CategoryDraft.all();
    }
    _draftDirty = false;
    notifyListeners();
    refresh();
  }

  /// 切换快捷日期项 (PRD 03: 选择后全页统一刷新)
  void setQuickRange(QuickRange r) {
    _quickRange = r;
    notifyListeners();
    refresh();
  }

  /// 自定义日期 (含首尾; 起始日不得晚于结束日; 不得进入未来)
  bool setCustomRange(DateTime start, DateTime end) {
    final today = DateTime.now();
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (s.isAfter(e)) return false; // 起始晚于结束 → 拒绝
    if (e.isAfter(DateTime(today.year, today.month, today.day))) {
      return false; // 未来日期 → 拒绝
    }
    _customStart = s;
    _customEnd = e;
    _quickRange = QuickRange.custom;
    notifyListeners();
    refresh();
    return true;
  }

  /// 切换同期对比开关
  void setComparisonEnabled(bool v) {
    _comparisonEnabled = v;
    notifyListeners();
    refresh();
  }

  /// 榜单排序
  void setSortBy(RankSort s) {
    _sortBy = s;
    notifyListeners();
    refresh();
  }

  /// 展开/收起榜单
  void toggleRankingExpanded() {
    _rankingExpanded = !_rankingExpanded;
    notifyListeners();
  }

  // ── 组合筛选草稿 (PRD 05) ──

  /// 草稿勾选 (确认前不触发查询)
  void draftToggleIncome(String categoryId) {
    _incomeDraft = _toggleDraft(_incomeDraft, categoryId);
    _draftDirty = true;
    notifyListeners();
  }

  void draftToggleExpense(String categoryId) {
    _expenseDraft = _toggleDraft(_expenseDraft, categoryId);
    _draftDirty = true;
    notifyListeners();
  }

  /// 草稿清空 → 恢复全部
  void draftClearIncome() {
    _incomeDraft = const CategoryDraft.all();
    _draftDirty = true;
    notifyListeners();
  }

  void draftClearExpense() {
    _expenseDraft = const CategoryDraft.all();
    _draftDirty = true;
    notifyListeners();
  }

  /// 取消 → 恢复原条件 (不应用草稿)
  void cancelDraft() {
    _incomeDraft = _appliedIncome;
    _expenseDraft = _appliedExpense;
    _draftDirty = false;
    notifyListeners();
  }

  /// 确认 → 应用草稿并触发查询
  void confirmDraft() {
    _appliedIncome = _incomeDraft;
    _appliedExpense = _expenseDraft;
    _draftDirty = false;
    notifyListeners();
    refresh();
  }

  CategoryDraft _toggleDraft(CategoryDraft d, String id) {
    final ids = Set<String>.from(d.ids);
    if (ids.contains(id)) {
      ids.remove(id);
    } else {
      ids.add(id);
    }
    // 全部取消 → 回到 ALL
    if (ids.isEmpty) return const CategoryDraft.all();
    return CategoryDraft(mode: CategoryMode.selected, ids: ids);
  }

  /// 切换账本 (PRD 06 R1): 保留时间范围, 清除原账本分类/标签/商户筛选
  void switchBook(String bookId) {
    _appliedIncome = const CategoryDraft.all();
    _appliedExpense = const CategoryDraft.all();
    _incomeDraft = const CategoryDraft.all();
    _expenseDraft = const CategoryDraft.all();
    _draftDirty = false;
    notifyListeners();
    refresh(bookId: bookId);
  }

  // ── 刷新 (渐进加载 + 版本一致性) ──

  /// 刷新所有模块
  ///
  /// 策略 (TECH 05): 先显示同版本已返回的汇总, 再渐进显示其他模块。
  /// 单模块失败保留其他同版本结果。
  Future<void> refresh({String bookId = 'book_001'}) async {
    final gen = ++_requestGeneration;
    _loading = true;
    _error = null;
    _errorCode = 0;
    notifyListeners();

    final q = buildQuery(bookId: bookId);

    try {
      // 1) 汇总 (优先)
      final s = await api.summary(q);
      if (gen != _requestGeneration) return; // 旧请求丢弃
      _summary = s.data;
      _snapshotVersion = s.meta.snapshotVersion;
      _conditionKey = s.meta.conditionKey;
      notifyListeners();

      // 2) 趋势
      try {
        final t = await api.trend(q);
        if (gen != _requestGeneration) return;
        _trend = t.data;
      } catch (e) {
        _recordModuleError(e, gen);
      }

      // 3) 分类榜 / 结余两侧榜
      try {
        if (_view == StatsView.balance) {
          final b = await api.balance(q);
          if (gen != _requestGeneration) return;
          _balance = b.data;
        } else {
          final c = await api.categories(q);
          if (gen != _requestGeneration) return;
          _categories = c.data;
        }
      } catch (e) {
        _recordModuleError(e, gen);
      }

      // 4) 标签统计
      try {
        final tg = await api.tags(q);
        if (gen != _requestGeneration) return;
        _tags = tg.data;
      } catch (e) {
        _recordModuleError(e, gen);
      }

      // 5) 交易对象 (仅分类详情 — PRD 04: 只在一级、二级分类详情显示)
      //    全局不请求, 由详情页触发

      _loading = false;
      notifyListeners();
    } on StatsApiException catch (e) {
      if (gen != _requestGeneration) return;
      _error = e.message;
      _errorCode = e.statusCode;
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (gen != _requestGeneration) return;
      _error = '$e';
      _loading = false;
      notifyListeners();
    }
  }

  /// 单模块失败记录 (不影响其他模块)
  void _recordModuleError(Object e, int gen) {
    if (gen != _requestGeneration) return;
    if (e is StatsApiException) {
      _error = e.message;
      _errorCode = e.statusCode;
    }
  }

  /// 单模块重试 (PRD 06 R6: 模块失败时支持独立重试)
  Future<void> retryModule(String module) async {
    final gen = ++_requestGeneration;
    final q = buildQuery();
    try {
      switch (module) {
        case 'trend':
          final t = await api.trend(q);
          if (gen != _requestGeneration) return;
          _trend = t.data;
        case 'categories':
          final c = await api.categories(q);
          if (gen != _requestGeneration) return;
          _categories = c.data;
        case 'balance':
          final b = await api.balance(q);
          if (gen != _requestGeneration) return;
          _balance = b.data;
        case 'tags':
          final tg = await api.tags(q);
          if (gen != _requestGeneration) return;
          _tags = tg.data;
        case 'merchants':
          final m = await api.merchants(q);
          if (gen != _requestGeneration) return;
          _merchants = m.data;
      }
      _error = null;
      _errorCode = 0;
    } catch (e) {
      _recordModuleError(e, gen);
    }
    notifyListeners();
  }

  /// 加载分类详情下的交易对象榜 (PRD 04: 只在分类详情显示)
  Future<void> loadMerchants({
    required String categoryId,
    String bookId = 'book_001',
  }) async {
    final gen = ++_requestGeneration;
    final q = buildQuery(bookId: bookId).copyWith(
      counterpartyIds: const [],
    );
    try {
      final m = await api.merchants(q);
      if (gen != _requestGeneration) return;
      _merchants = m.data;
      notifyListeners();
    } catch (e) {
      _recordModuleError(e, gen);
      notifyListeners();
    }
  }
}
