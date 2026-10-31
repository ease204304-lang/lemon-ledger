/// 备份与导出/导入
///
/// - `exportJson`: 全部流水 + 分类 → JSON 文件，写入应用文档目录
/// - `exportCsv`:  流水 → CSV
/// - `exportXlsx`: 流水 → xlsx
/// - `importJson`: 从 JSON 备份恢复 (v1.5 新增)
library backup;

import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';

/// 导入模式:
/// - [ImportMode.replace] 覆盖: 清空旧分类/流水, 全部用导入的
/// - [ImportMode.merge] 合并: 旧 + 导入, 同 ID 用导入的覆盖
enum ImportMode { replace, merge }

/// 导入结果 (成功)
class ImportResult {
  final int categoriesTotal;
  final int transactionsTotal;
  final int categoriesInserted;
  final int transactionsInserted;
  final int categoriesReplaced;
  final int transactionsReplaced;
  final int transactionsMerged; // merge 模式专用

  ImportResult({
    required this.categoriesTotal,
    required this.transactionsTotal,
    required this.categoriesInserted,
    required this.transactionsInserted,
    required this.categoriesReplaced,
    required this.transactionsReplaced,
    required this.transactionsMerged,
  });

  @override
  String toString() => '导入完成: 分类 ${categoriesInserted + categoriesReplaced} 条, 流水 ${transactionsInserted + transactionsReplaced} 条 (合并 ${transactionsMerged} 条)';
}

/// 导入错误 (抛出)
class ImportError implements Exception {
  final ImportErrorKind kind;
  final String message;
  ImportError(this.kind, this.message);
  @override
  String toString() => '[$kind] $message';
}

enum ImportErrorKind {
  emptyFile,         // 文件 0 字节
  ioError,           // 读文件失败
  badJson,           // 解析失败
  versionMissing,    // 没有 version 字段
  versionMismatch,   // version 不是 1
  missingCategories, // 没有 categories 字段
  missingTransactions, // 没有 transactions 字段
  invalidCategory,   // 分类字段缺/类型错
  invalidTransaction, // 流水字段缺/类型错
  foreignKeyViolation, // 流水引用了不存在的分类
}

class BackupService {
  static final BackupService instance = BackupService._();
  BackupService._();

  // 当前支持的 schema 版本
  static const int kSupportedVersion = 1;

  Future<Directory> _downloadsDir() async {
    // 在桌面/手机上, 优先写应用文档目录.
    return await getApplicationDocumentsDirectory();
  }

  String _stamp() {
    final d = DateTime.now();
    String f(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}${f(d.month)}${f(d.day)}_${f(d.hour)}${f(d.minute)}${f(d.second)}';
  }

  Future<File> _writeTo(String base, List<int> bytes, String ext) async {
    final dir = await _downloadsDir();
    final file = File(p.join(dir.path, '${base}_${_stamp()}.$ext'));
    return file.writeAsBytes(bytes);
  }

  Future<File> exportJson() async {
    final txs = await TxRepository.instance.all();
    final cats = await CategoryRepository.instance.all(includeArchived: true);
    final data = {
      'version': kSupportedVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': '小猪记账',
      'categories': cats.map((c) => c.toMap()).toList(),
      'transactions': txs.map((t) => t.toMap()).toList(),
    };
    final f = await _writeTo('lemon_ledger', utf8.encode(jsonEncode(data)), 'json');
    await _shareOrLog(f.path, 'application/json');
    return f;
  }

  Future<File> exportCsv() async {
    final txs = await TxRepository.instance.all();
    final cats = {for (final c in await CategoryRepository.instance.all()) c.id: c};
    final rows = <List<dynamic>>[
      ['日期', '类型', '分类', '金额(元)', '备注'],
      for (final t in txs) ...[
        [
          _dateStr(t.epochDay),
          t.type.zh,
          cats[t.categoryId]?.name ?? t.categoryId,
          (t.amountCents / 100).toStringAsFixed(2),
          t.note,
        ],
      ],
    ];
    final s = const ListToCsvConverter().convert(rows);
    final f = await _writeTo('lemon_ledger', utf8.encode('\uFEFF$s'), 'csv');
    await _shareOrLog(f.path, 'text/csv');
    return f;
  }

  Future<File> exportXlsx() async {
    final txs = await TxRepository.instance.all();
    final cats = {for (final c in await CategoryRepository.instance.all()) c.id: c};
    final excel = Excel.createExcel();
    final sheet = excel['流水'];
    sheet.appendRow([
      TextCellValue('日期'),
      TextCellValue('类型'),
      TextCellValue('分类'),
      TextCellValue('金额(元)'),
      TextCellValue('备注'),
    ]);
    for (final t in txs) {
      sheet.appendRow([
        TextCellValue(_dateStr(t.epochDay)),
        TextCellValue(t.type.zh),
        TextCellValue(cats[t.categoryId]?.name ?? t.categoryId),
        DoubleCellValue(t.amountCents / 100),
        TextCellValue(t.note),
      ]);
    }
    final bytes = excel.encode()!;
    final f = await _writeTo('lemon_ledger', bytes, 'xlsx');
    await _shareOrLog(f.path, 'application/vnd.openxmlformats');
    return f;
  }

  Future<void> _shareOrLog(String path, String mime) async {
    try {
      await Share.shareXFiles([XFile(path, mimeType: mime)],
          text: '小猪记账 导出');
    } catch (_) {
      // 桌面平台 share 不可用, 仅落到文件即可
    }
  }

  String _dateStr(int day) {
    final d = DateTime.fromMillisecondsSinceEpoch(day * 86400000);
    String f(int v) => v < 10 ? '0$v' : '$v';
    return '${d.year}-${f(d.month)}-${f(d.day)}';
  }

  // ============== 导入 (v1.5 新增) ==============

  /// 导入模式: replace 覆盖 (清空旧) / merge 合并 (同 ID 覆盖, 新 ID 累加)
  Future<ImportResult> importJson(
    File file, {
    ImportMode mode = ImportMode.merge,
  }) async {
    // 1. 读文件
    if (!await file.exists()) {
      throw ImportError(ImportErrorKind.ioError, '文件不存在: ${file.path}');
    }
    final size = await file.length();
    if (size == 0) {
      throw ImportError(ImportErrorKind.emptyFile, '文件为空, 请确认是 JSON 备份文件');
    }

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      throw ImportError(ImportErrorKind.ioError, '读文件失败: $e');
    }

    // 2. 解析 JSON
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw ImportError(ImportErrorKind.badJson, 'JSON 根不是对象');
      }
      data = decoded;
    } catch (e) {
      if (e is ImportError) rethrow;
      throw ImportError(ImportErrorKind.badJson, 'JSON 解析失败: $e');
    }

    // 3. Schema 校验
    if (!data.containsKey('version')) {
      throw ImportError(ImportErrorKind.versionMissing, 'JSON 缺少 version 字段');
    }
    final v = data['version'];
    if (v is! int) {
      throw ImportError(ImportErrorKind.versionMissing, 'version 不是整数: $v');
    }
    if (v != kSupportedVersion) {
      throw ImportError(ImportErrorKind.versionMismatch,
          '不兼容的版本: $v (本应用仅支持 v$kSupportedVersion)');
    }
    if (!data.containsKey('categories') || data['categories'] is! List) {
      throw ImportError(ImportErrorKind.missingCategories, 'JSON 缺少 categories 数组');
    }
    if (!data.containsKey('transactions') || data['transactions'] is! List) {
      throw ImportError(ImportErrorKind.missingTransactions, 'JSON 缺少 transactions 数组');
    }

    // 4. 解析分类与流水
    final rawCats = data['categories'] as List;
    final rawTxs = data['transactions'] as List;
    final List<Category> categories = [];
    for (var i = 0; i < rawCats.length; i++) {
      try {
        categories.add(Category.fromMap(Map<String, dynamic>.from(rawCats[i] as Map)));
      } catch (e) {
        throw ImportError(ImportErrorKind.invalidCategory, '第 ${i + 1} 个分类数据无效: $e');
      }
    }
    final List<Tx> transactions = [];
    for (var i = 0; i < rawTxs.length; i++) {
      try {
        transactions.add(Tx.fromMap(Map<String, dynamic>.from(rawTxs[i] as Map)));
      } catch (e) {
        throw ImportError(ImportErrorKind.invalidTransaction, '第 ${i + 1} 笔流水数据无效: $e');
      }
    }

    // 5. 校验外键: 流水引用的分类必须存在
    //    - replace: 只看 JSON 里的分类 (DB 会被清空)
    //    - merge:   JSON ∪ 当前 DB (已有分类也算合法引用)
    final db = await AppDatabase.instance.db;
    final catIds = {for (final c in categories) c.id};
    if (mode == ImportMode.merge) {
      final dbCats = await db.query('category', columns: ['id']);
      catIds.addAll(dbCats.map((r) => r['id'] as String));
    }
    for (var i = 0; i < transactions.length; i++) {
      if (!catIds.contains(transactions[i].categoryId)) {
        throw ImportError(ImportErrorKind.foreignKeyViolation,
            '第 ${i + 1} 笔流水引用了不存在的分类: ${transactions[i].categoryId}');
      }
    }

    // 6. 在 db.transaction 中导入 (失败自动回滚)
    int catInserted = 0, catReplaced = 0;
    int txInserted = 0, txReplaced = 0, txMerged = 0;

    await db.transaction((txn) async {
      // 6a. 覆盖模式: 先清空
      if (mode == ImportMode.replace) {
        await txn.delete('tx');
        await txn.delete('category');
      }

      // 6b. 导入分类
      for (final c in categories) {
        final existing = await txn.query('category',
            where: 'id = ?', whereArgs: [c.id], limit: 1);
        if (existing.isNotEmpty) {
          if (mode == ImportMode.merge) {
            // merge: 同 ID 覆盖
            await txn.update('category', c.toMap(),
                where: 'id = ?', whereArgs: [c.id]);
            catReplaced++;
          } else if (mode == ImportMode.replace) {
            // replace 模式: 上面已 delete, 这里直接 insert
            await txn.insert('category', c.toMap());
            catInserted++;
          }
        } else {
          // 新分类
          await txn.insert('category', c.toMap());
          catInserted++;
        }
      }

      // 6c. 导入流水
      for (final t in transactions) {
        final existing = await txn.query('tx',
            where: 'id = ?', whereArgs: [t.id], limit: 1);
        if (existing.isNotEmpty) {
          if (mode == ImportMode.merge) {
            // merge: 同 ID 用导入的覆盖
            await txn.update('tx', t.toMap(),
                where: 'id = ?', whereArgs: [t.id]);
            txReplaced++;
            txMerged++;
          } else if (mode == ImportMode.replace) {
            // replace 模式: 上面已 delete, 直接 insert
            await txn.insert('tx', t.toMap());
            txInserted++;
          }
        } else {
          await txn.insert('tx', t.toMap());
          txInserted++;
        }
      }
    });

    return ImportResult(
      categoriesTotal: categories.length,
      transactionsTotal: transactions.length,
      categoriesInserted: catInserted,
      categoriesReplaced: catReplaced,
      transactionsInserted: txInserted,
      transactionsReplaced: txReplaced,
      transactionsMerged: txMerged,
    );
  }

  /// 检查文件是否是有效的 JSON 备份 (供 UI 预先提示)
  /// 不抛错, 只返回 ImportErrorKind? (null 表示 OK)
  Future<ImportErrorKind?> peekJsonFile(File file) async {
    if (!await file.exists()) return ImportErrorKind.ioError;
    if (await file.length() == 0) return ImportErrorKind.emptyFile;
    try {
      final s = await file.readAsString();
      final d = jsonDecode(s);
      if (d is! Map<String, dynamic>) return ImportErrorKind.badJson;
      if (!d.containsKey('version')) return ImportErrorKind.versionMissing;
      if (d['version'] != kSupportedVersion) return ImportErrorKind.versionMismatch;
      return null;
    } catch (e) {
      return ImportErrorKind.badJson;
    }
  }

  /// 用户友好的错误消息
  static String errorMessage(ImportErrorKind kind) {
    switch (kind) {
      case ImportErrorKind.emptyFile:
        return '文件为空, 请选择正确的 JSON 备份文件';
      case ImportErrorKind.ioError:
        return '无法读取文件, 请检查文件权限';
      case ImportErrorKind.badJson:
        return '文件格式错误, 不是有效的 JSON';
      case ImportErrorKind.versionMissing:
        return '备份文件缺少版本号';
      case ImportErrorKind.versionMismatch:
        return '备份版本不兼容, 请用同版本 App 导出';
      case ImportErrorKind.missingCategories:
        return '备份文件缺少分类数据';
      case ImportErrorKind.missingTransactions:
        return '备份文件缺少流水数据';
      case ImportErrorKind.invalidCategory:
        return '备份中部分分类数据无效';
      case ImportErrorKind.invalidTransaction:
        return '备份中部分流水数据无效';
      case ImportErrorKind.foreignKeyViolation:
        return '备份中流水引用了不存在的分类';
    }
  }
}
