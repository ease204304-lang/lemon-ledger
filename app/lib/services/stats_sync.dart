/// 统计服务数据同步层 (v1.12.0)
///
/// 把 App 本地 SQLite 的账本数据 (分类 / 标签 / 流水) 同步到统计服务端
/// (server/ FastAPI), 让「统计」页 (StatsPage) 能展示 PRD 完整口径的报表。
///
/// 设计:
///   - 幂等: 服务端支持 client_ref (本地流水 id) 去重, 重复同步不产生重复数据
///   - 维度映射: 本地分类/标签按 (名称, 类型) 对齐服务端, 缺失则创建;
///     映射持久化到 SharedPreferences, 避免重复建维度
///   - 账本: 首次同步按名字「我的账本」查找/创建, book_id 持久化
///   - 全量推送: 本地是数据主权方, 每次同步把本地全部流水按 client_ref 上传,
///     服务端自动去重 (未做增量删除 — 本地删除的流水服务端保留, 属于"追加式"同步)
///
/// 时区口径: 本地 epochDay 是业务日 (不随时区漂移, 与服务端 T21 契约一致)。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'stats_api.dart';

/// 单次同步结果
class SyncResult {
  final bool ok;
  final String? error;
  final int totalTx; // 本地流水总数 (不含转账)
  final int uploaded; // 新上传
  final int deduplicated; // 服务端判定重复跳过
  final int failed; // 失败笔数
  final String? bookId;
  final DateTime? finishedAt;

  const SyncResult({
    required this.ok,
    this.error,
    this.totalTx = 0,
    this.uploaded = 0,
    this.deduplicated = 0,
    this.failed = 0,
    this.bookId,
    this.finishedAt,
  });

  bool get hasFailures => failed > 0;
}

class StatsSyncService {
  static final StatsSyncService instance = StatsSyncService._();
  StatsSyncService._();

  static const _kUrl = 'stats.server_url';
  static const _kBookId = 'stats.book_id';
  static const _kBookName = 'stats.book_name';
  static const _kCatMap = 'stats.cat_map';
  static const _kTagMap = 'stats.tag_map';
  static const _kLastSync = 'stats.last_sync_at';

  static const String defaultBookName = '我的账本';

  // ── 设置读写 ────────────────────────────────────────────────────────────

  Future<String> getUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kUrl) ?? StatsApiClient.endpoint;
  }

  Future<void> setUrl(String url) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  Future<String?> getBookId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kBookId);
  }

  Future<String> getBookName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kBookName) ?? defaultBookName;
  }

  Future<void> _setBook(String id, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kBookId, id);
    await p.setString(_kBookName, name);
  }

  Future<DateTime?> getLastSyncAt() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kLastSync);
    if (s == null) return null;
    return DateTime.tryParse(s);
  }

  Future<Map<String, String>> _getMap(String key) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j.map((k, v) => MapEntry(k, '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _setMap(String key, Map<String, String> m) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(m));
  }

  /// 丢弃已有账本绑定与维度映射 (换服务器 / 重新开始)
  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kBookId);
    await p.remove(_kBookName);
    await p.remove(_kCatMap);
    await p.remove(_kTagMap);
    await p.remove(_kLastSync);
  }

  // ── 同步主流程 ──────────────────────────────────────────────────────────

  /// 全量同步本地数据到服务端。
  ///
  /// [onProgress] 每完成一笔回调 (done, total), 供 UI 显示进度。
  Future<SyncResult> sync({
    void Function(int done, int total)? onProgress,
    StatsApiClient? client,
  }) async {
    final url = await getUrl();
    final api = client ?? StatsApiClient(baseUrl: url);
    DateTime? finishedAt;

    // 1) 连通性
    if (!await api.ping()) {
      return const SyncResult(
          ok: false, error: '无法连接服务端, 请确认服务已启动且地址正确');
    }

    // 2) 账本: 查找或创建
    String bookId;
    final bookName = await getBookName();
    final savedBookId = await getBookId();
    try {
      final books = await api.listBooks();
      final existing =
          books.where((b) => b['id'] == savedBookId || b['name'] == bookName);
      if (existing.isNotEmpty) {
        bookId = '${existing.first['id']}';
        if (savedBookId != bookId) {
          await _setBook(bookId, '${existing.first['name']}');
        }
      } else {
        final created = await api.createBook(bookName);
        bookId = '${created['id']}';
        await _setBook(bookId, bookName);
      }
    } on StatsApiException catch (e) {
      return SyncResult(ok: false, error: '账本获取失败: ${e.message}');
    }

    // 3) 分类映射 (按 名称+类型 对齐; 本地是单级, 服务端也用一级)
    final Map<String, String> catMap = await _getMap(_kCatMap);
    try {
      final localCats =
          await CategoryRepository.instance.all(includeArchived: true);
      final serverCats = await api.listCategories();
      for (final c in localCats) {
        if (catMap.containsKey(c.id)) continue;
        final type = c.type == TxType.income ? 'income' : 'expense';
        final hit = serverCats.firstWhere(
          (s) =>
              s['name'] == c.name &&
              ('${s['type']}' == type || s['type'] == null),
          orElse: () => const {},
        );
        if (hit.isNotEmpty) {
          catMap[c.id] = '${hit['id']}';
        } else {
          final created = await api.createCategory(c.name, type);
          catMap[c.id] = '${created['id']}';
        }
      }
      await _setMap(_kCatMap, catMap);
    } on StatsApiException catch (e) {
      return SyncResult(ok: false, error: '分类同步失败: ${e.message}');
    }

    // 4) 标签映射 (本地标签以 name 为主键语义; 服务端同)
    final Map<String, String> tagMap = await _getMap(_kTagMap);
    final db = await AppDatabase.instance.db;
    try {
      // 标签名有两个来源: tag 表 (标签库) 与 tx_tag.tag_name (实际用到的标签)
      // 两者取并集, 避免关联里出现但标签库里没有的标签被漏掉。
      final localTagRows = await db.query('tag', columns: ['name']);
      final usedTagRows = await db.query('tx_tag',
          columns: ['tag_name'], distinct: true);
      final localNames = <String>{
        ...localTagRows.map((r) => '${r['name']}'),
        ...usedTagRows.map((r) => '${r['tag_name']}'),
      }..removeWhere((e) => e.isEmpty);

      final serverTags = await api.listTags();
      for (final name in localNames) {
        if (tagMap.containsKey(name)) continue;
        final hit = serverTags.where((s) => s['name'] == name);
        if (hit.isNotEmpty) {
          tagMap[name] = '${hit.first['id']}';
        } else {
          final created = await api.createTag(name);
          tagMap[name] = '${created['id']}';
        }
      }
      await _setMap(_kTagMap, tagMap);
    } on StatsApiException catch (e) {
      return SyncResult(ok: false, error: '标签同步失败: ${e.message}');
    }

    // 5) 流水 (client_ref 幂等, 全量推送, 服务端自动去重)
    final allTx = await TxRepository.instance.all();
    final txs = allTx.where((t) => t.type != TxType.transfer).toList();
    int uploaded = 0, deduplicated = 0, failed = 0;
    final failures = <String>[];

    for (var i = 0; i < txs.length; i++) {
      final tx = txs[i];
      onProgress?.call(i, txs.length);
      final date =
          DateTime.fromMillisecondsSinceEpoch(tx.epochDay * 86400000);
      final body = <String, dynamic>{
        'book_id': bookId,
        'type': tx.type == TxType.income ? 'income' : 'expense',
        'amount': (tx.amountCents / 100).toStringAsFixed(2),
        'transaction_date':
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        'note': tx.note,
        'client_ref': tx.id, // 幂等键: 本地流水 id
        if (catMap[tx.categoryId] != null)
          'category_id': catMap[tx.categoryId],
      };
      // 标签: 第一个作为主标签 (main), 其余 aux
      try {
        final tagRows = await db.query('tx_tag',
            columns: ['tag_name'],
            where: 'tx_id = ?',
            whereArgs: [tx.id],
            orderBy: 'rowid');
        final names =
            tagRows.map((r) => '${r['tag_name']}').toSet().toList();
        final serverIds = names
            .map((n) => tagMap[n])
            .whereType<String>()
            .toList();
        if (serverIds.isNotEmpty) {
          body['primary_tag_id'] = serverIds.first;
          if (serverIds.length > 1) {
            body['tag_ids'] = serverIds.sublist(1);
          }
        }
      } catch (_) {
        // 标签关联查不到不阻断流水同步
      }

      try {
        final r = await api.createTransaction(body);
        if (r['deduplicated'] == true) {
          deduplicated++;
        } else {
          uploaded++;
        }
      } on StatsApiException catch (e) {
        failed++;
        if (failures.length < 5) failures.add('${e.statusCode} ${e.message}');
      }
    }
    onProgress?.call(txs.length, txs.length);

    // 6) 记录完成时间
    finishedAt = DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kLastSync, finishedAt.toIso8601String());

    if (failed > 0 && failed >= txs.length) {
      return SyncResult(
        ok: false,
        error: '全部流水同步失败: ${failures.join("; ")}',
        totalTx: txs.length,
        uploaded: uploaded,
        deduplicated: deduplicated,
        failed: failed,
        bookId: bookId,
      );
    }
    return SyncResult(
      ok: true,
      totalTx: txs.length,
      uploaded: uploaded,
      deduplicated: deduplicated,
      failed: failed,
      bookId: bookId,
      finishedAt: finishedAt,
      error: failures.isEmpty
          ? null
          : '部分流水失败 (${failures.length}+): ${failures.join("; ")}',
    );
  }
}
