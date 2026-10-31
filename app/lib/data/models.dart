/// 领域模型
///
/// 命名规范与 `docs/00-基线与术语.md` §6 字段定义保持一致。
library models;

/// 流水类型: 支出 / 收入 / 转账（v1 不展示转账；保留为枚举供 v1.1）
enum TxType { expense, income, transfer }

extension TxTypeName on TxType {
  String get zh {
    switch (this) {
      case TxType.expense: return '支出';
      case TxType.income:  return '收入';
      case TxType.transfer:return '转账';
    }
  }
}

/// 单条流水
class Tx {
  final String id;          // UUID
  final int    epochDay;    // 自 1970-01-01 起的天数
  final TxType type;
  final String categoryId;  // 引用 Category.id
  final int    amountCents; // 单位: 分（正整数）
  final String note;        // 备注/原文
  final String? photoPath;  // v1 暂未启用，预留
  final DateTime createdAt; // 创建时间（用于排序兜底）

  const Tx({
    required this.id,
    required this.epochDay,
    required this.type,
    required this.categoryId,
    required this.amountCents,
    required this.note,
    this.photoPath,
    required this.createdAt,
  });

  /// 金额（元，保留两位小数）。`0.05` 形式，无千分位。
  double get amountYuan => amountCents / 100.0;

  Map<String, Object?> toMap() => {
        'id': id,
        'epoch_day': epochDay,
        'type': type.index,
        'category_id': categoryId,
        'amount_cents': amountCents,
        'note': note,
        'photo_path': photoPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Tx.fromMap(Map<String, Object?> m) => Tx(
        id: m['id'] as String,
        epochDay: m['epoch_day'] as int,
        type: TxType.values[m['type'] as int],
        categoryId: m['category_id'] as String,
        amountCents: m['amount_cents'] as int,
        note: (m['note'] as String?) ?? '',
        photoPath: m['photo_path'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  Tx copyWith({
    int? epochDay,
    TxType? type,
    String? categoryId,
    int? amountCents,
    String? note,
    String? photoPath,
  }) => Tx(
        id: id,
        epochDay: epochDay ?? this.epochDay,
        type: type ?? this.type,
        categoryId: categoryId ?? this.categoryId,
        amountCents: amountCents ?? this.amountCents,
        note: note ?? this.note,
        photoPath: photoPath ?? this.photoPath,
        createdAt: createdAt,
      );
}

/// 分类。type 与 TxType 对应: 同一 category 仅归属一种 type
class Category {
  final String id;          // 稳定字符串，例如 `cat.food` / `cat.invest`
  final String name;        // 中文名
  final String iconKey;     // icon key 映射（见 `widgets/icons.dart`）
  final TxType type;        // 支出 / 收入
  final int    sortOrder;   // 在网格中显示顺序
  final bool   archived;    // 软删除标记
  final bool   pinned;      // v1.6: 常用分类 (记帐页置顶显示)

  const Category({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.type,
    required this.sortOrder,
    this.archived = false,
    this.pinned = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
        'type': type.index,
        'sort_order': sortOrder,
        'archived': archived ? 1 : 0,
        'pinned': pinned ? 1 : 0,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        iconKey: m['icon_key'] as String,
        type: TxType.values[m['type'] as int],
        sortOrder: m['sort_order'] as int,
        archived: (m['archived'] as int) == 1,
        pinned: (m['pinned'] as int? ?? 0) == 1,
      );
}
