/// 标签服务 (v1.2.2 → v1.8.0)
/// 标签 = 用户在备注里高频输入的词, 用来快速复用
///
/// 存储:
///   tag 表 (name PK, use_count, last_used_at, category_id*)
///   tx_tag 关联表 (tx_id, tag_name) — v1.8.0 新增, 支撑标签统计/饼图
/// API:
///   addOrBump / recent(按频次) / search / remove
///   syncForTx (保存流水时同步关联)
///   byCategory (走 tx_tag, 不再 LIKE 反推)
///   statsByTag (周期内按标签聚合: 金额/笔数/最近使用)

library;

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

class Tag {
  final String name;
  final int useCount;
  final int lastUsedAt;
  final String? categoryId; // v1.8.0: 归属分类 (最近一次使用所在)
  Tag({required this.name, required this.useCount, required this.lastUsedAt, this.categoryId});

  factory Tag.fromMap(Map<String, Object?> m) => Tag(
        name: m['name'] as String,
        useCount: (m['use_count'] as int?) ?? 0,
        lastUsedAt: (m['last_used_at'] as int?) ?? 0,
        categoryId: m['category_id'] as String?,
      );
}

/// 标签统计行 (v1.8.0, 图表"标签"视图用)
class TagStat {
  final String name;
  final int totalCents; // 周期内合计
  final int txCount;    // 命中笔数
  final int lastUsedDay; // 最近使用的 epochDay
  TagStat({required this.name, required this.totalCents, required this.txCount, required this.lastUsedDay});
}

/// 标签排序方式 (用户需求: "按时间和按金额")
enum TagSortBy { amount, time }

class TagService {
  static final TagService instance = TagService._();
  TagService._();

  /// 创建或累加一个标签
  Future<void> addOrBump(String name, {String? categoryId}) async {
    final n = name.trim();
    if (n.isEmpty) return;
    final db = await AppDatabase.instance.db;
    // 先看有没有
    final rows = await db.query('tag',
        where: 'name = ?', whereArgs: [n], limit: 1);
    if (rows.isEmpty) {
      await db.insert('tag', {
        'name': n,
        'use_count': 1,
        'last_used_at': DateTime.now().millisecondsSinceEpoch,
        'category_id': categoryId,
      });
    } else {
      await db.rawUpdate('''
        UPDATE tag
        SET use_count = use_count + 1,
            last_used_at = ?,
            category_id = COALESCE(?, category_id)
        WHERE name = ?
      ''', [DateTime.now().millisecondsSinceEpoch, categoryId, n]);
    }
  }

  /// 最近 N 个标签 (按 use_count 倒序, 即使用频次)
  /// v1.7.0: 排序键改 use_count, 因为用户反馈"按使用频次由前到后排序"
  Future<List<Tag>> recent(int limit) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.query('tag',
        orderBy: 'use_count DESC, last_used_at DESC',
        limit: limit);
    return rows.map(Tag.fromMap).toList();
  }

  /// v1.8.0: 某分类的标签 (走 tx_tag 关联表, 精确匹配)
  Future<List<Tag>> byCategory(String categoryId, {int limit = 8}) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT t.name, t.use_count, t.last_used_at, t.category_id
      FROM tag t
      JOIN tx_tag tt ON tt.tag_name = t.name
      JOIN tx x ON x.id = tt.tx_id
      WHERE x.category_id = ?
      GROUP BY t.name
      ORDER BY t.use_count DESC, t.last_used_at DESC
      LIMIT ?
    ''', [categoryId, limit]);
    return rows.map(Tag.fromMap).toList();
  }

  /// v1.8.0: 保存流水后同步标签关联
  ///
  /// 规则:
  ///   1. 备注非空 → 备注整体 addOrBump (历史行为, 有机产生新标签)
  ///   2. 已有标签中, 名字是备注子串的 → 建立 tx_tag 关联 + bump 频次
  ///      (频次要反映真实使用: 存 "星巴克 拿铁" 也算用了 星巴克)
  Future<void> syncForTx(Tx tx) async {
    final note = tx.note.trim();
    final db = await AppDatabase.instance.db;
    // 清掉旧关联 (编辑流水场景)
    await db.delete('tx_tag', where: 'tx_id = ?', whereArgs: [tx.id]);
    if (note.isEmpty) return;

    // 1. 备注整体作为标签 (v1.2 起的有机产生机制)
    await addOrBump(note, categoryId: tx.categoryId);

    // 2. 命中的已有标签 → 关联
    final allTags = await db.query('tag', columns: ['name']);
    final noteLower = note.toLowerCase();
    final matched = <String>[];
    final batch = db.batch();
    for (final t in allTags) {
      final name = t['name'] as String;
      if (name.length < 2) continue; // 单字标签容易误命中, 跳过
      if (name.toLowerCase() == noteLower) continue; // 整体已处理
      if (noteLower.contains(name.toLowerCase())) {
        matched.add(name);
        batch.insert('tx_tag', {'tx_id': tx.id, 'tag_name': name},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await batch.commit(noResult: true);
    // 备注整体也要有关联行 (它本身就是一个标签)
    await db.insert('tx_tag', {'tx_id': tx.id, 'tag_name': note},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    // 3. bump 命中标签的频次 (在关联写完后)
    for (final name in matched) {
      await addOrBump(name, categoryId: tx.categoryId);
    }
  }

  /// v1.8.0: 周期内按标签聚合 (图表"标签"视图 / 饼图数据源)
  Future<List<TagStat>> statsByTag(
    TxType type,
    int fromDay,
    int toDay, {
    TagSortBy sortBy = TagSortBy.amount,
  }) async {
    final db = await AppDatabase.instance.db;
    final rows = await db.rawQuery('''
      SELECT tt.tag_name AS name,
             SUM(x.amount_cents) AS s,
             COUNT(*) AS n,
             MAX(x.epoch_day) AS last_day
      FROM tx_tag tt
      JOIN tx x ON x.id = tt.tx_id
      WHERE x.type = ? AND x.epoch_day BETWEEN ? AND ?
      GROUP BY tt.tag_name
    ''', [type.index, fromDay, toDay]);
    final out = rows
        .map((r) => TagStat(
              name: r['name'] as String,
              totalCents: (r['s'] as int?) ?? 0,
              txCount: (r['n'] as int?) ?? 0,
              lastUsedDay: (r['last_day'] as int?) ?? 0,
            ))
        .toList();
    out.sort((a, b) => sortBy == TagSortBy.amount
        ? b.totalCents.compareTo(a.totalCents)
        : b.lastUsedDay.compareTo(a.lastUsedDay));
    return out;
  }

  /// 模糊搜
  Future<List<Tag>> search(String keyword, {int limit = 8}) async {
    if (keyword.trim().isEmpty) return recent(limit);
    final db = await AppDatabase.instance.db;
    final k = '%${keyword.trim()}%';
    final rows = await db.query('tag',
        where: 'name LIKE ?',
        whereArgs: [k],
        orderBy: 'use_count DESC',
        limit: limit);
    return rows.map(Tag.fromMap).toList();
  }

  /// 删除一个标签 (v1.8.0: 连带清理 tx_tag 关联)
  Future<void> remove(String name) async {
    final db = await AppDatabase.instance.db;
    await db.delete('tx_tag', where: 'tag_name = ?', whereArgs: [name]);
    await db.delete('tag', where: 'name = ?', whereArgs: [name]);
  }
}
