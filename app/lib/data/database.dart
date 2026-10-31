/// SQLite 数据库初始化与迁移
///
/// v1: category + tx 表
/// v2: + budget 表 (月预算)
/// v3: + tag 表 (标签)
/// v4: + category.pinned (常用分类)
/// v5: + tag.category_id + tx_tag 关联表 (标签统计, U1.9 收尾)
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'seed.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._();
  AppDatabase._();
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'lemon_ledger.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // v1
    await db.execute('''
      CREATE TABLE category (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        icon_key    TEXT NOT NULL,
        type        INTEGER NOT NULL,
        sort_order  INTEGER NOT NULL,
        archived    INTEGER NOT NULL DEFAULT 0,
        pinned      INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE tx (
        id            TEXT PRIMARY KEY,
        epoch_day     INTEGER NOT NULL,
        type          INTEGER NOT NULL,
        category_id   TEXT NOT NULL REFERENCES category(id),
        amount_cents  INTEGER NOT NULL,
        note          TEXT NOT NULL DEFAULT '',
        photo_path    TEXT,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tx_epoch_day ON tx(epoch_day)');
    await db.execute(
        'CREATE INDEX idx_tx_category  ON tx(category_id)');

    // v2 新增
    await db.execute('''
      CREATE TABLE budget (
        year         INTEGER NOT NULL,
        month        INTEGER NOT NULL,
        amount_cents INTEGER NOT NULL,
        PRIMARY KEY (year, month)
      )
    ''');

    // v3 新增: 标签
    await db.execute('''
      CREATE TABLE tag (
        name          TEXT PRIMARY KEY,
        use_count     INTEGER NOT NULL DEFAULT 1,
        last_used_at  INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tag_last_used ON tag(last_used_at DESC)');

    final batch = db.batch();
    for (final c in seedCategories()) {
      batch.insert('category', c.toMap());
    }
    for (final t in seedTxs()) {
      batch.insert('tx', t.toMap());
    }
    await batch.commit(noResult: true);

    // v4: 5 个常用分类 (鲨鱼记账风格)
    const pinnedIds = ['cat.credit', 'cat.food', 'cat.transport', 'cat.snack', 'cat.salary'];
    for (final id in pinnedIds) {
      await db.rawUpdate('UPDATE category SET pinned = 1 WHERE id = ?', [id]);
    }

    // v5: tx_tag 关联表 (标签统计)
    await db.execute('''
      CREATE TABLE tx_tag (
        tx_id    TEXT NOT NULL,
        tag_name TEXT NOT NULL,
        PRIMARY KEY (tx_id, tag_name)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tx_tag_name ON tx_tag(tag_name)');
    await db.execute(
        "ALTER TABLE tag ADD COLUMN category_id TEXT");

    // v5: 从种子流水备注提取演示标签 (让标签统计/饼图开箱即有数据)
    await _backfillTagsFromTxs(db);
  }

  /// v5: 扫描 tx 备注, 把出现的标签词建成 tag 行 + tx_tag 关联
  ///
  /// 规则: tag 名是 note 的子串 (不区分大小写) 即关联;
  ///       use_count = 命中笔数, last_used_at = 最新一笔 created_at,
  ///       category_id = 最新一笔的分类。
  /// 新装 (onCreate) 与升级 (onUpgrade v4→v5) 共用。
  Future<void> _backfillTagsFromTxs(Database db) async {
    // 演示标签词表 (取自种子备注中出现的高频词)
    // 注: 不含 "收入" — 会与记帐页类型 chip 同名, 显示混淆
    const seedTagNames = [
      '餐饮', '交通', '停车费', '单车', '充电', '咖啡', '信托',
      '日用', '孩子', '旅行', '医疗',
    ];
    final txs = await db.query('tx',
        columns: ['id', 'epoch_day', 'category_id', 'note', 'created_at'],
        where: "note != ''");
    final now = DateTime.now().millisecondsSinceEpoch;
    final tagStats = <String, Map<String, Object?>>{};
    final links = <Map<String, Object?>>[];
    for (final t in txs) {
      final note = ((t['note'] as String?) ?? '').toLowerCase();
      for (final name in seedTagNames) {
        if (!note.contains(name.toLowerCase())) continue;
        final s = tagStats.putIfAbsent(
            name, () => {'use_count': 0, 'last_used_at': 0, 'category_id': null});
        s['use_count'] = (s['use_count'] as int) + 1;
        final ts = (t['created_at'] as int?) ?? now;
        if (ts > (s['last_used_at'] as int)) {
          s['last_used_at'] = ts;
          s['category_id'] = t['category_id'];
        }
        links.add({'tx_id': t['id'], 'tag_name': name});
      }
    }
    final batch = db.batch();
    for (final e in tagStats.entries) {
      // ignore: 保护用户已创建的同名标签的 use_count
      batch.insert('tag', {
        'name': e.key,
        'use_count': e.value['use_count'],
        'last_used_at': e.value['last_used_at'],
        'category_id': e.value['category_id'],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    for (final l in links) {
      batch.insert('tx_tag', l,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      // v1 -> v2: 加 budget 表 + 增 5 个分类
      await db.execute('''
        CREATE TABLE budget (
          year         INTEGER NOT NULL,
          month        INTEGER NOT NULL,
          amount_cents INTEGER NOT NULL,
          PRIMARY KEY (year, month)
        )
      ''');
      // 增 5 个新分类 (若已存在则忽略)
      final newCats = <Map<String, Object?>>[
        {'id': 'cat.credit',    'name': '信用卡', 'icon_key': 'credit',   'type': 0, 'sort_order': 11, 'archived': 0},
        {'id': 'cat.education', 'name': '教育',   'icon_key': 'education','type': 0, 'sort_order': 14, 'archived': 0},
        {'id': 'cat.housing',   'name': '住房',   'icon_key': 'housing',  'type': 0, 'sort_order': 16, 'archived': 0},
      ];
      for (final c in newCats) {
        await db.insert('category', c, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    if (from < 3) {
      // v2 -> v3: 标签
      await db.execute('''
        CREATE TABLE tag (
          name          TEXT PRIMARY KEY,
          use_count     INTEGER NOT NULL DEFAULT 1,
          last_used_at  INTEGER NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_tag_last_used ON tag(last_used_at DESC)');
    }
    if (from < 4) {
      // v3 -> v4: 常用分类 pinned 字段
      await db.execute('ALTER TABLE category ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
      // 默认 4 支出 + 1 收入为常用 (鲨鱼记账风格)
      const pinnedIds = ['cat.credit', 'cat.food', 'cat.transport', 'cat.snack', 'cat.salary'];
      for (final id in pinnedIds) {
        await db.rawUpdate('UPDATE category SET pinned = 1 WHERE id = ?', [id]);
      }
    }
    if (from < 5) {
      // v4 -> v5: 标签统计体系 (U1.9 收尾)
      // 1) tag 加 category_id 归属列
      await db.execute('ALTER TABLE tag ADD COLUMN category_id TEXT');
      // 2) tx_tag 关联表
      await db.execute('''
        CREATE TABLE tx_tag (
          tx_id    TEXT NOT NULL,
          tag_name TEXT NOT NULL,
          PRIMARY KEY (tx_id, tag_name)
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_tx_tag_name ON tx_tag(tag_name)');
      // 3) 回填: 已有 tag 命中已有 tx 备注的, 建关联
      final tags = (await db.query('tag', columns: ['name']))
          .map((r) => r['name'] as String)
          .toList();
      if (tags.isNotEmpty) {
        final txs = await db.query('tx',
            columns: ['id', 'note', 'created_at', 'category_id'],
            where: "note != ''");
        final batch = db.batch();
        for (final t in txs) {
          final note = ((t['note'] as String?) ?? '').toLowerCase();
          for (final name in tags) {
            if (note.contains(name.toLowerCase())) {
              batch.insert('tx_tag', {'tx_id': t['id'], 'tag_name': name},
                  conflictAlgorithm: ConflictAlgorithm.ignore);
            }
          }
        }
        // 更新 tag 的 category_id (按最近一笔命中的分类)
        for (final name in tags) {
          await db.rawUpdate('''
            UPDATE tag SET category_id = (
              SELECT x.category_id FROM tx_tag tt
              JOIN tx x ON x.id = tt.tx_id
              WHERE tt.tag_name = ?
              ORDER BY x.created_at DESC LIMIT 1
            ) WHERE name = ?
          ''', [name, name]);
        }
        await batch.commit(noResult: true);
      }
      // 4) v1.8.0 修复: 升级也跑一次种子回填 — 让从 v1.7.0 升级上来的用户
      //    立刻看到 11 个演示标签 + 饼图有数据 (而非空态)
      await _backfillTagsFromTxs(db);
    }
  }

  /// 关闭（仅在测试或重置时使用）
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 完全重置（开发用）
  Future<void> resetForDebug() async {
    await close();
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'lemon_ledger.db');
    await deleteDatabase(path);
  }
}
