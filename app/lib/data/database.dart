/// SQLite 数据库初始化与迁移
///
/// v1: category + tx 表
/// v2: + budget 表 (月预算)
/// v3: + tag 表 (标签)
/// v4: + category.pinned (常用分类)
/// v5: + tag.category_id + tx_tag 关联表 (标签统计, U1.9 收尾)
/// v6: 分类清单重整 (用户指定: 支出 14 类 / 收入 8 类)
/// v7: + account (账户/资产) + category_budget (分类预算) + remind (记账提醒) + app_lock (隐私锁)
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
      version: 8,
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
        created_at    INTEGER NOT NULL,
        account_id    TEXT
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
    // v6: 按新清单 — 支出 4 (信用卡 餐饮 零食 交通) + 收入 1 (工资)
    const pinnedIds = ['cat.credit', 'cat.food', 'cat.snack', 'cat.transport', 'cat.salary'];
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

    // v7: 账户 / 分类预算 / 记账提醒 / 隐私锁
    await _createV7Tables(db);
    await _seedDefaultAccounts(db);
    await _createV8Tables(db);
    await _seedIncomeTagBindings(db);
  }

  /// v8 新增表结构 (标签-分类绑定, 按收支类型独立)
  ///
  /// 设计说明 (v1.14.0):
  ///   tag 表的 name 是全局主键, 无法表达「同名标签在支出/收入下
  ///   绑定不同分类」。因此用独立关联表表达绑定关系:
  ///     tag_binding(name, type) → category_id
  ///   type: 0=支出, 1=收入 (与 TxType.index 一致)
  Future<void> _createV8Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tag_binding (
        name        TEXT NOT NULL,
        type        INTEGER NOT NULL,          -- 0=支出 1=收入
        category_id TEXT NOT NULL,
        PRIMARY KEY (name, type)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_tag_bind_cat ON tag_binding(category_id)');

    // 回填: 用历史 tx_tag + tx 推导已有标签的绑定关系
    // 规则: 同一 (name,type) 取最近一笔流水的 category_id
    final rows = await db.rawQuery('''
      SELECT tt.tag_name AS name, x.type AS type, x.category_id AS cid,
             MAX(x.epoch_day) AS d
      FROM tx_tag tt
      JOIN tx x ON x.id = tt.tx_id
      GROUP BY tt.tag_name, x.type
    ''');
    final batch = db.batch();
    for (final r in rows) {
      final name = r['name'] as String?;
      final cid = r['cid'] as String?;
      if (name == null || cid == null) continue;
      batch.insert(
        'tag_binding',
        {'name': name, 'type': r['type'] as int, 'category_id': cid},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// v7 新增表结构 (账户/分类预算/记账提醒/隐私锁)
  Future<void> _createV7Tables(Database db) async {
    // 账户: 现金/银行卡/信用卡/储蓄/理财 (资产与负债统一管理)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS account (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        kind          TEXT NOT NULL DEFAULT 'cash',  -- cash/debit/credit/saving/invest
        balance_cents INTEGER NOT NULL DEFAULT 0,   -- 当前余额 (分)
        initial_cents INTEGER NOT NULL DEFAULT 0,   -- 初始余额 (分, 用于计算净资产变化)
        currency      TEXT NOT NULL DEFAULT 'CNY',
        include_net   INTEGER NOT NULL DEFAULT 1,   -- 是否计入净资产
        archived      INTEGER NOT NULL DEFAULT 0,
        sort_order    INTEGER NOT NULL DEFAULT 0,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_account_sort ON account(sort_order)');

    // 分类预算: 按 (年, 月, 分类) 设置上限, 0 = 不设限
    await db.execute('''
      CREATE TABLE IF NOT EXISTS category_budget (
        year         INTEGER NOT NULL,
        month        INTEGER NOT NULL,
        category_id  TEXT NOT NULL,
        amount_cents INTEGER NOT NULL,
        PRIMARY KEY (year, month, category_id)
      )
    ''');

    // 记账提醒: 每日提醒时间 + 启用开关 (分钟数 0..1439)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS remind (
        id         INTEGER PRIMARY KEY CHECK (id = 1),
        enabled    INTEGER NOT NULL DEFAULT 0,
        minute     INTEGER NOT NULL DEFAULT 1320,   -- 默认 22:00
        last_fired_epoch_day INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 隐私锁: 应用锁 (密码哈希 + 生物识别开关)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_lock (
        id            INTEGER PRIMARY KEY CHECK (id = 1),
        enabled       INTEGER NOT NULL DEFAULT 0,
        password_hash TEXT,
        biometric     INTEGER NOT NULL DEFAULT 0,
        failed_count  INTEGER NOT NULL DEFAULT 0,
        locked_until  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// 首次创建时给几个默认账户 (现金/银行卡/信用卡), 让资产管理页开箱可用
  Future<void> _seedDefaultAccounts(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const defaults = <Map<String, Object?>>[
      {'id': 'acc.cash', 'name': '现金', 'kind': 'cash', 'sort_order': 0},
      {'id': 'acc.bank', 'name': '银行卡', 'kind': 'debit', 'sort_order': 1},
      {'id': 'acc.credit', 'name': '信用卡', 'kind': 'credit', 'sort_order': 2},
    ];
    final batch = db.batch();
    for (final a in defaults) {
      batch.insert('account', {
        ...a,
        'balance_cents': 0,
        'initial_cents': 0,
        'currency': 'CNY',
        'include_net': 1,
        'archived': 0,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  /// v1.14.0: 种子标签-分类绑定 (收入侧)
  ///
  /// 支出侧的绑定由 _backfillTagsFromTxs 从历史流水自动推导;
  /// 收入侧种子流水少, 这里显式给出常见收入标签的绑定,
  /// 让「切到收入 → 标签内容不同」首次安装即可感知。
  Future<void> _seedIncomeTagBindings(Database db) async {
    const incomeBindings = <List<String>>[
      ['工资', 'cat.salary'],       // 工资 → 工资
      ['奖金', 'cat.bonus'],       // 奖金 → 奖金
      ['补贴', 'cat.allowance'],   // 补贴 → 补贴
      ['兼职', 'cat.parttime'],    // 兼职 → 兼职
      ['年终奖', 'cat.bonus'],     // 年终奖 → 奖金
      ['报销', 'cat.refund'],      // 报销 → 退款
      ['退款', 'cat.refund'],      // 退款 → 退款
      ['收礼', 'cat.gift'],        // 收礼 → 收礼
      ['投资收益', 'cat.invest'],   // 投资收益 → 投资
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final b in incomeBindings) {
      // 保证 tag 行存在 (标签库要有这个标签, 否则标签行显示不出来)
      batch.insert('tag', {
        'name': b[0],
        'use_count': 1,
        'last_used_at': now,
        'category_id': b[1],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // 收入类型 = 1
      batch.insert('tag_binding', {
        'name': b[0],
        'type': 1,
        'category_id': b[1],
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
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
    // v6: "旅行" → "旅游" (随分类改名), "咖啡" 归属改到 餐饮
    const seedTagNames = [
      '餐饮', '交通', '停车费', '单车', '充电', '咖啡', '信托',
      '日用', '孩子', '旅游', '医疗',
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
    if (from < 6) {
      // v5 -> v6: 分类清单重整 (用户指定清单)
      await _migrateToV6Categories(db);
    }
    if (from < 7) {
      // v6 -> v7: 资产管理 / 分类预算 / 记账提醒 / 隐私锁
      await _createV7Tables(db);
      await _seedDefaultAccounts(db);
      // tx 加账户关联列 (资产管理: 流水绑定账户 → 自动增减余额)
      try {
        await db.execute('ALTER TABLE tx ADD COLUMN account_id TEXT');
      } catch (_) {
        // 列已存在 (重复迁移)
      }
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_tx_account ON tx(account_id)');
    }
    if (from < 8) {
      // v7 -> v8: 标签-分类绑定 (按收支类型独立)
      await _createV8Tables(db);
      await _seedIncomeTagBindings(db);
    }
  }

  /// v5 -> v6: 分类清单重整
  ///
  /// 目标 (用户指定):
  ///   支出 14 类: 信用卡 餐饮 娱乐 零食 交通 住房 旅游 医疗 运动 汽车 孩子 日用 投资 其他
  ///   收入  8 类: 工资 奖金 补贴 兼职 投资 退款 收礼 其他 (不变)
  ///
  /// 原则 (保护用户数据):
  ///   1. **不删任何分类** — 被移除的分类只置 archived=1 (软删),
  ///      否则用户历史流水的 category_id 会变成悬空引用, 报表金额丢失。
  ///   2. 改名 (旅行→旅游 / 车费→汽车) 走 UPDATE, 保留 id → 历史流水自动跟着变。
  ///   3. 新增分类 (娱乐 / 运动 / 投资支出) 走 INSERT ... ON CONFLICT IGNORE。
  ///   4. 支出「投资」用独立 id (cat.invest_exp), 与收入「投资」(cat.invest) 区分;
  ///      原挂在 cat.invest 上的支出流水迁到 cat.invest_exp (修正类型不一致 bug)。
  ///   5. 常用分类 (pinned) 重置为新清单的常用项。
  ///   6. **所有**保留分类的 sort_order 按新清单重排 (否则旧库顺序错乱)。
  Future<void> _migrateToV6Categories(Database db) async {
    // 1) 先新增分类 (支出侧) — 必须在 sort_order 对齐之前, 否则新 id 无行可更新
    const newCats = <Map<String, Object?>>[
      {'id': 'cat.entertain', 'name': '娱乐', 'icon_key': 'entertain', 'type': 0, 'sort_order': 2, 'archived': 0},
      {'id': 'cat.sport', 'name': '运动', 'icon_key': 'sport', 'type': 0, 'sort_order': 8, 'archived': 0},
      {'id': 'cat.invest_exp', 'name': '投资', 'icon_key': 'invest', 'type': 0, 'sort_order': 12, 'archived': 0},
    ];
    for (final c in newCats) {
      await db.insert('category', c, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // 2) 全量对齐 name + sort_order (改名 + 重排一次做完)
    //    依据 seedCategories() 的当前顺序, 保证新旧库显示一致
    final seedOrder = <String, (String, int)>{
      for (final c in seedCategories())
        if (!c.archived) c.id: (c.name, c.sortOrder),
    };
    for (final e in seedOrder.entries) {
      await db.rawUpdate(
          'UPDATE category SET name = ?, sort_order = ? WHERE id = ?',
          [e.value.$1, e.value.$2, e.key]);
    }

    // 3) 归档被移除的分类 (软删, 保留历史流水可查)
    const removedIds = [
      'cat.market',   // 超市
      'cat.fruit',    // 水果
      'cat.drink',    // 饮品
      'cat.dress',    // 服饰
      'cat.beauty',   // 美妆
      'cat.phone',    // 通讯
      'cat.house',    // 居家
      'cat.book',     // 学习
      'cat.education',// 教育
      'cat.pet',      // 宠物
      'cat.digital',  // 数码
    ];
    for (final id in removedIds) {
      await db.rawUpdate(
          'UPDATE category SET archived = 1, pinned = 0 WHERE id = ?', [id]);
    }

    // 4) 修正「投资」类型不一致 bug:
    //    支出「投资 - 信托」818 元原本挂在收入类 cat.invest 上 → 迁到 cat.invest_exp
    await db.rawUpdate(
        "UPDATE tx SET category_id = 'cat.invest_exp' "
        "WHERE category_id = 'cat.invest' AND type = 0");
    //    咖啡原本在 cat.drink (已归档) → 迁到 cat.food
    await db.rawUpdate(
        "UPDATE tx SET category_id = 'cat.food' "
        "WHERE category_id = 'cat.drink' AND note LIKE '%咖啡%'");

    // 5) 重置常用分类 (新清单: 支出 4 + 收入 1)
    await db.rawUpdate('UPDATE category SET pinned = 0');
    const pinnedIds = ['cat.credit', 'cat.food', 'cat.snack', 'cat.transport', 'cat.salary'];
    for (final id in pinnedIds) {
      await db.rawUpdate('UPDATE category SET pinned = 1 WHERE id = ?', [id]);
    }

    // 6) 归档分类上的标签归属要跟着改 (tag.category_id 指向归档分类会让标签行查不到)
    await db.rawUpdate('''
      UPDATE tag SET category_id = NULL
      WHERE category_id IN (${removedIds.map((_) => '?').join(',')})
    ''', removedIds);
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
