/// 统计模块 API 客户端 (v1.11.0 W3/W4)
///
/// 对应《记账统计模块技术实施说明书》v0.9 §02 查询契约 + §03 请求响应契约。
///
/// 关键约定:
///   - 金额与百分比一律用 **字符串** 传输 (十进制, 避免 float 精度丢失)
///   - 响应统一包裹 `{ data, meta }`, meta 带 snapshot_version / 条件标识 / 生成时间
///   - 错误: 400 INVALID_FILTER / 403 BOOK_FORBIDDEN / 409 SNAPSHOT_STALE / 503 统计暂不可用
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// 统计视图类型 (PRD 01: 收入 / 支出 / 结余 三视图下拉切换)
enum StatsView { income, expense, balance }

/// 分类筛选模式 (PRD 05 分类组合筛选: ALL | SELECTED)
enum CategoryMode { all, selected }

/// 趋势粒度 (PRD 03: 1–31 天按天, 32–365 天按周, >365 天按月)
enum TrendGranularity { day, week, month }

/// 榜单排序维度 (PRD 04: 金额 / 笔数 / 最近发生时间)
enum RankSort { amount, count, recent }

/// 服务端返回的错误码
class StatsApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  const StatsApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  /// 409 SNAPSHOT_STALE — 请求版本已过期, 需重查
  bool get isStale => code == 'SNAPSHOT_STALE';

  /// 503 统计暂不可用 — 可重试
  bool get isRetryable => statusCode == 503;

  @override
  String toString() => 'StatsApiException($statusCode $code): $message';
}

/// 查询条件对象 (TECH 03: 所有统计请求接受的参数)
class StatsQuery {
  final String bookId;
  final StatsView view;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String timezone; // IANA
  final TrendGranularity? granularity;
  final bool comparisonEnabled;

  // 结余组合筛选 (两侧独立)
  final CategoryMode incomeCategoryMode;
  final List<String> incomeCategoryIds;
  final CategoryMode expenseCategoryMode;
  final List<String> expenseCategoryIds;

  // 维度筛选 (标签 / 对象)
  final List<String> tagIds;
  final List<String> counterpartyIds;

  // 榜单排序
  final RankSort sortBy;

  // 明细分页
  final int? limit;
  final String? cursor;

  const StatsQuery({
    required this.bookId,
    required this.view,
    required this.startDate,
    required this.endDate,
    this.timezone = 'Asia/Shanghai',
    this.granularity,
    this.comparisonEnabled = false,
    this.incomeCategoryMode = CategoryMode.all,
    this.incomeCategoryIds = const [],
    this.expenseCategoryMode = CategoryMode.all,
    this.expenseCategoryIds = const [],
    this.tagIds = const [],
    this.counterpartyIds = const [],
    this.sortBy = RankSort.amount,
    this.limit,
    this.cursor,
  });

  /// 结余视图才需要两侧分类条件
  bool get isBalance => view == StatsView.balance;

  /// 视图类型对应的交易类型参数 (income/expense/balance)
  String get typeParam => switch (view) {
        StatsView.income => 'income',
        StatsView.expense => 'expense',
        StatsView.balance => 'balance',
      };

  Map<String, String> toParams() {
    final p = <String, String>{
      'book_id': bookId,
      'type': typeParam,
      'start_date': startDate,
      'end_date': endDate,
      'timezone': timezone,
      'comparison_enabled': comparisonEnabled ? 'true' : 'false',
      'sort_by': switch (sortBy) {
        RankSort.amount => 'amount',
        RankSort.count => 'count',
        RankSort.recent => 'recent',
      },
    };
    if (granularity != null) {
      p['granularity'] = switch (granularity!) {
        TrendGranularity.day => 'day',
        TrendGranularity.week => 'week',
        TrendGranularity.month => 'month',
      };
    }
    if (isBalance) {
      p['income_category_mode'] =
          incomeCategoryMode == CategoryMode.all ? 'ALL' : 'SELECTED';
      p['expense_category_mode'] =
          expenseCategoryMode == CategoryMode.all ? 'ALL' : 'SELECTED';
      if (incomeCategoryIds.isNotEmpty) {
        p['income_category_ids'] = incomeCategoryIds.join(',');
      }
      if (expenseCategoryIds.isNotEmpty) {
        p['expense_category_ids'] = expenseCategoryIds.join(',');
      }
    }
    if (tagIds.isNotEmpty) p['tag_ids'] = tagIds.join(',');
    if (counterpartyIds.isNotEmpty) {
      p['counterparty_ids'] = counterpartyIds.join(',');
    }
    if (limit != null) p['limit'] = '$limit';
    if (cursor != null) p['cursor'] = cursor!;
    return p;
  }

  /// 规范化条件标识 (TECH 03: meta 需返回, 用于缓存键与一致性校验)
  String get normalizedKey {
    final parts = [
      bookId,
      typeParam,
      startDate,
      endDate,
      timezone,
      comparisonEnabled ? 'cmp=1' : 'cmp=0',
      granularity?.name ?? 'auto',
      'i=${incomeCategoryMode.name}:${incomeCategoryIds.join("|")}',
      'e=${expenseCategoryMode.name}:${expenseCategoryIds.join("|")}',
      't=${tagIds.join("|")}',
      'm=${counterpartyIds.join("|")}',
      's=${sortBy.name}',
    ];
    return parts.join('&');
  }

  StatsQuery copyWith({
    StatsView? view,
    String? startDate,
    String? endDate,
    TrendGranularity? granularity,
    bool? comparisonEnabled,
    CategoryMode? incomeCategoryMode,
    List<String>? incomeCategoryIds,
    CategoryMode? expenseCategoryMode,
    List<String>? expenseCategoryIds,
    List<String>? tagIds,
    List<String>? counterpartyIds,
    RankSort? sortBy,
    int? limit,
    String? cursor,
  }) {
    return StatsQuery(
      bookId: bookId,
      view: view ?? this.view,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      timezone: timezone,
      granularity: granularity ?? this.granularity,
      comparisonEnabled: comparisonEnabled ?? this.comparisonEnabled,
      incomeCategoryMode: incomeCategoryMode ?? this.incomeCategoryMode,
      incomeCategoryIds: incomeCategoryIds ?? this.incomeCategoryIds,
      expenseCategoryMode: expenseCategoryMode ?? this.expenseCategoryMode,
      expenseCategoryIds: expenseCategoryIds ?? this.expenseCategoryIds,
      tagIds: tagIds ?? this.tagIds,
      counterpartyIds: counterpartyIds ?? this.counterpartyIds,
      sortBy: sortBy ?? this.sortBy,
      limit: limit ?? this.limit,
      cursor: cursor ?? this.cursor,
    );
  }
}

/// 响应 meta (TECH 03: 版本 / 条件标识 / 生成时间)
class StatsMeta {
  final int snapshotVersion;
  final String conditionKey;
  final String generatedAt;

  const StatsMeta({
    required this.snapshotVersion,
    required this.conditionKey,
    required this.generatedAt,
  });

  factory StatsMeta.fromJson(Map<String, dynamic> j) => StatsMeta(
        snapshotVersion: (j['snapshot_version'] as num?)?.toInt() ?? 0,
        conditionKey: j['condition_key'] as String? ?? '',
        generatedAt: j['generated_at'] as String? ?? '',
      );
}

/// 通用响应包装
class StatsResponse<T> {
  final T data;
  final StatsMeta meta;

  const StatsResponse({required this.data, required this.meta});

  factory StatsResponse.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) parse,
  ) =>
      StatsResponse(
        data: parse((j['data'] as Map<String, dynamic>?) ?? const {}),
        meta: StatsMeta.fromJson((j['meta'] as Map<String, dynamic>?) ?? const {}),
      );
}

/// 汇总指标 (TECH 02 summary)
class StatsSummary {
  final String income; // 十进制字符串
  final String expense;
  final String balance;
  final String? balanceRate; // null 表示无法计算 (收入为 0)
  final int incomeCount;
  final int expenseCount;
  final String? dailyAverage; // 日均 (D06 口径: 区间自然日天数)
  final int dailyAverageDays; // 日均分母 (实际天数)
  // 同期对比 (comparison_enabled 时)
  final String? compareIncome;
  final String? compareExpense;
  final String? compareBalance;
  final String? balanceDiff; // 本期结余 − 同期结余
  final String? balanceChangeRate; // null 表示同期结余 ≤ 0

  const StatsSummary({
    required this.income,
    required this.expense,
    required this.balance,
    required this.balanceRate,
    required this.incomeCount,
    required this.expenseCount,
    required this.dailyAverage,
    required this.dailyAverageDays,
    this.compareIncome,
    this.compareExpense,
    this.compareBalance,
    this.balanceDiff,
    this.balanceChangeRate,
  });

  factory StatsSummary.fromJson(Map<String, dynamic> j) => StatsSummary(
        income: j['income'] as String? ?? '0.00',
        expense: j['expense'] as String? ?? '0.00',
        balance: j['balance'] as String? ?? '0.00',
        balanceRate: j['balance_rate'] as String?,
        incomeCount: (j['income_count'] as num?)?.toInt() ?? 0,
        expenseCount: (j['expense_count'] as num?)?.toInt() ?? 0,
        dailyAverage: j['daily_average'] as String?,
        dailyAverageDays: (j['daily_average_days'] as num?)?.toInt() ?? 0,
        compareIncome: j['compare_income'] as String?,
        compareExpense: j['compare_expense'] as String?,
        compareBalance: j['compare_balance'] as String?,
        balanceDiff: j['balance_diff'] as String?,
        balanceChangeRate: j['balance_change_rate'] as String?,
      );
}

/// 趋势点 (TECH 02 trend)
class TrendPoint {
  final String bucketStart;
  final String bucketEnd;
  final String income;
  final String expense;
  final String balance;
  final String? compareIncome;
  final String? compareExpense;
  final String? compareBalance;

  const TrendPoint({
    required this.bucketStart,
    required this.bucketEnd,
    required this.income,
    required this.expense,
    required this.balance,
    this.compareIncome,
    this.compareExpense,
    this.compareBalance,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        bucketStart: j['bucket_start'] as String? ?? '',
        bucketEnd: j['bucket_end'] as String? ?? '',
        income: j['income'] as String? ?? '0.00',
        expense: j['expense'] as String? ?? '0.00',
        balance: j['balance'] as String? ?? '0.00',
        compareIncome: j['compare_income'] as String?,
        compareExpense: j['compare_expense'] as String?,
        compareBalance: j['compare_balance'] as String?,
      );
}

/// 分类/对象/标签榜单条目 (TECH 02 categories / tags / merchants)
class RankItem {
  final String id;
  final String name;
  final String amount; // 十进制字符串
  final String? rate; // 金额占比 (两位小数字符串)
  final int count;
  final double progress; // 0..1 进度条
  final int level; // 1 = 一级, 2 = 二级, 0 = 特殊桶
  final String? parentId;
  final String? drillKey; // 穿透键 (TECH 02: 榜单返回穿透键)

  const RankItem({
    required this.id,
    required this.name,
    required this.amount,
    required this.rate,
    required this.count,
    required this.progress,
    this.level = 1,
    this.parentId,
    this.drillKey,
  });

  factory RankItem.fromJson(Map<String, dynamic> j) => RankItem(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        amount: j['amount'] as String? ?? '0.00',
        rate: j['rate'] as String?,
        count: (j['count'] as num?)?.toInt() ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
        parentId: j['parent_id'] as String?,
        drillKey: j['drill_key'] as String?,
      );
}

/// 分类榜 (结余时返回两侧)
class CategoryRanking {
  final List<RankItem> items;
  final String total; // 该侧总额 (占比分母)

  const CategoryRanking({required this.items, required this.total});

  factory CategoryRanking.fromJson(Map<String, dynamic> j) => CategoryRanking(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => RankItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as String? ?? '0.00',
      );
}

/// 标签环形图数据 (TECH 02 tags)
class TagChart {
  /// Top 5 + 其他 (「未设置标签」独立保留, PRD 04)
  final List<RankItem> slices;
  /// 榜单 (可展开全部)
  final List<RankItem> ranking;
  final String total;

  const TagChart({
    required this.slices,
    required this.ranking,
    required this.total,
  });

  factory TagChart.fromJson(Map<String, dynamic> j) => TagChart(
        slices: ((j['slices'] as List?) ?? const [])
            .map((e) => RankItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        ranking: ((j['ranking'] as List?) ?? const [])
            .map((e) => RankItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as String? ?? '0.00',
      );
}

/// 交易对象榜 (TECH 02 merchants)
class MerchantRanking {
  final List<RankItem> items;
  final String total;

  const MerchantRanking({required this.items, required this.total});

  factory MerchantRanking.fromJson(Map<String, dynamic> j) => MerchantRanking(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => RankItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as String? ?? '0.00',
      );
}

/// 明细条目 (TECH 02 transactions)
class TxDetail {
  final String id;
  final String bookId;
  final String type; // expense / income
  final String amount;
  final String transactionDate;
  final String? transactionTime;
  final String? categoryId;
  final String? categoryName;
  final String? counterpartyId;
  final String? counterpartyName;
  final String? mainTagId;
  final String? mainTagName;
  final List<String> auxTagNames;
  final String note;
  final String createdAt;
  final String? updatedAt;

  const TxDetail({
    required this.id,
    required this.bookId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    required this.transactionTime,
    required this.categoryId,
    required this.categoryName,
    required this.counterpartyId,
    required this.counterpartyName,
    required this.mainTagId,
    required this.mainTagName,
    required this.auxTagNames,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TxDetail.fromJson(Map<String, dynamic> j) => TxDetail(
        id: j['id'] as String? ?? '',
        bookId: j['book_id'] as String? ?? '',
        type: j['type'] as String? ?? 'expense',
        amount: j['amount'] as String? ?? '0.00',
        transactionDate: j['transaction_date'] as String? ?? '',
        transactionTime: j['transaction_time'] as String?,
        categoryId: j['category_id'] as String?,
        categoryName: j['category_name'] as String?,
        counterpartyId: j['counterparty_id'] as String?,
        counterpartyName: j['counterparty_name'] as String?,
        mainTagId: j['main_tag_id'] as String?,
        mainTagName: j['main_tag_name'] as String?,
        auxTagNames:
            ((j['aux_tag_names'] as List?) ?? const []).map((e) => '$e').toList(),
        note: j['note'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        updatedAt: j['updated_at'] as String?,
      );
}

/// 分页明细
class TxPage {
  final List<TxDetail> items;
  final String? nextCursor;
  final String total;

  const TxPage({
    required this.items,
    required this.nextCursor,
    required this.total,
  });

  factory TxPage.fromJson(Map<String, dynamic> j) => TxPage(
        items: ((j['items'] as List?) ?? const [])
            .map((e) => TxDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: j['next_cursor'] as String?,
        total: j['total'] as String? ?? '0.00',
      );
}

/// 结余分类组合结果 (TECH 02 balance / PRD 05)
class BalanceRanking {
  final CategoryRanking incomeContribution; // 收入贡献
  final CategoryRanking expenseImpact; // 支出影响
  final String incomeTotal;
  final String expenseTotal;
  final String balance;

  const BalanceRanking({
    required this.incomeContribution,
    required this.expenseImpact,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.balance,
  });

  factory BalanceRanking.fromJson(Map<String, dynamic> j) => BalanceRanking(
        incomeContribution: CategoryRanking.fromJson(
            (j['income_contribution'] as Map<String, dynamic>?) ?? const {}),
        expenseImpact: CategoryRanking.fromJson(
            (j['expense_impact'] as Map<String, dynamic>?) ?? const {}),
        incomeTotal: j['income_total'] as String? ?? '0.00',
        expenseTotal: j['expense_total'] as String? ?? '0.00',
        balance: j['balance'] as String? ?? '0.00',
      );
}

/// 统计 API 客户端
class StatsApiClient {
  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  StatsApiClient({
    String? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = baseUrl ?? _defaultBaseUrl,
        _http = httpClient ?? http.Client();

  /// 默认服务端地址 (Android 模拟器访问宿主机用 10.0.2.2)
  static const String _defaultBaseUrl = 'http://10.0.2.2:8800';

  /// 可切换的服务端地址 (设置页 / 调试)
  static String endpoint = _defaultBaseUrl;

  Uri _uri(String path, Map<String, String> params) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path,
      queryParameters: params.isEmpty ? null : params,
    );
  }

  /// 统一错误处理 (TECH 03 错误契约)
  Never _throw(http.Response r) {
    Map<String, dynamic> body = const {};
    try {
      body = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      body = const {};
    }
    final err = (body['error'] as Map<String, dynamic>?) ?? const {};
    throw StatsApiException(
      statusCode: r.statusCode,
      code: err['code'] as String? ?? 'UNKNOWN',
      message: err['message'] as String? ?? 'HTTP ${r.statusCode}',
      details: err['details'] as Map<String, dynamic>?,
    );
  }

  Future<Map<String, dynamic>> _get(String path, StatsQuery q) async {
    final uri = _uri(path, q.toParams());
    final r = await _http.get(uri).timeout(timeout);
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// GET /api/statistics/summary
  Future<StatsResponse<StatsSummary>> summary(StatsQuery q) async {
    final j = await _get('/api/statistics/summary', q);
    return StatsResponse.fromJson(j, StatsSummary.fromJson);
  }

  /// GET /api/statistics/trend
  Future<StatsResponse<List<TrendPoint>>> trend(StatsQuery q) async {
    final j = await _get('/api/statistics/trend', q);
    return StatsResponse.fromJson(
      j,
      (d) => ((d['points'] as List?) ?? const [])
          .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// GET /api/statistics/categories
  /// 结余视图返回两侧 (收入贡献 / 支出影响), 单侧视图返回单个 items 列表。
  Future<StatsResponse<CategoryRanking>> categories(StatsQuery q) async {
    final j = await _get('/api/statistics/categories', q);
    return StatsResponse.fromJson(j, CategoryRanking.fromJson);
  }

  /// GET /api/statistics/balance — 结余组合 (两侧分类榜)
  Future<StatsResponse<BalanceRanking>> balance(StatsQuery q) async {
    final j = await _get('/api/statistics/balance', q);
    return StatsResponse.fromJson(j, BalanceRanking.fromJson);
  }

  /// GET /api/statistics/tags
  Future<StatsResponse<TagChart>> tags(StatsQuery q) async {
    final j = await _get('/api/statistics/tags', q);
    return StatsResponse.fromJson(j, TagChart.fromJson);
  }

  /// GET /api/statistics/merchants
  Future<StatsResponse<MerchantRanking>> merchants(StatsQuery q) async {
    final j = await _get('/api/statistics/merchants', q);
    return StatsResponse.fromJson(j, MerchantRanking.fromJson);
  }

  /// GET /api/transactions — 分页明细
  Future<StatsResponse<TxPage>> transactions(StatsQuery q) async {
    final j = await _get('/api/transactions', q);
    return StatsResponse.fromJson(j, TxPage.fromJson);
  }

  /// GET /api/transactions/{id} — 单笔详情
  Future<StatsResponse<TxDetail>> transaction(String id) async {
    final uri = _uri('/api/transactions/$id', const {});
    final r = await _http.get(uri).timeout(timeout);
    if (r.statusCode != 200) _throw(r);
    return StatsResponse.fromJson(
      jsonDecode(r.body) as Map<String, dynamic>,
      TxDetail.fromJson,
    );
  }

  void dispose() => _http.close();
}
