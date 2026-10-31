/// 初始分类与种子流水
///
/// 与 `docs/00-基线与术语.md` §8 初始分类保持一致。
library seed;

import 'models.dart';

/// 初始分类 (v1.2 增 5 个: 信用卡/教育/住房/...)
List<Category> seedCategories() => [
      // 支出
      const Category(id: 'cat.food',      name: '餐饮', iconKey: 'food',      type: TxType.expense, sortOrder: 0),
      const Category(id: 'cat.market',    name: '超市', iconKey: 'market',    type: TxType.expense, sortOrder: 1),
      const Category(id: 'cat.transport', name: '交通', iconKey: 'transport', type: TxType.expense, sortOrder: 2),
      const Category(id: 'cat.fruit',     name: '水果', iconKey: 'fruit',     type: TxType.expense, sortOrder: 3),
      const Category(id: 'cat.daily',     name: '日用', iconKey: 'daily',     type: TxType.expense, sortOrder: 4),
      const Category(id: 'cat.snack',     name: '零食', iconKey: 'snack',     type: TxType.expense, sortOrder: 5),
      const Category(id: 'cat.drink',     name: '饮品', iconKey: 'drink',     type: TxType.expense, sortOrder: 6),
      const Category(id: 'cat.dress',     name: '服饰', iconKey: 'dress',     type: TxType.expense, sortOrder: 7),
      const Category(id: 'cat.beauty',    name: '美妆', iconKey: 'beauty',    type: TxType.expense, sortOrder: 8),
      const Category(id: 'cat.phone',     name: '通讯', iconKey: 'phone',     type: TxType.expense, sortOrder: 9),
      const Category(id: 'cat.house',     name: '居家', iconKey: 'house',     type: TxType.expense, sortOrder: 10),
      // v1.2 新增 (对标鲨鱼记账)
      const Category(id: 'cat.credit',    name: '信用卡', iconKey: 'credit',   type: TxType.expense, sortOrder: 11),
      const Category(id: 'cat.travel',    name: '旅行', iconKey: 'travel',    type: TxType.expense, sortOrder: 12),
      const Category(id: 'cat.book',      name: '学习', iconKey: 'book',      type: TxType.expense, sortOrder: 13),
      const Category(id: 'cat.education', name: '教育', iconKey: 'education', type: TxType.expense, sortOrder: 14),
      const Category(id: 'cat.medical',   name: '医疗', iconKey: 'medical',   type: TxType.expense, sortOrder: 15),
      const Category(id: 'cat.housing',   name: '住房', iconKey: 'housing',   type: TxType.expense, sortOrder: 16),
      const Category(id: 'cat.kid',       name: '孩子', iconKey: 'kid',       type: TxType.expense, sortOrder: 17),
      const Category(id: 'cat.pet',       name: '宠物', iconKey: 'pet',       type: TxType.expense, sortOrder: 18),
      const Category(id: 'cat.digital',   name: '数码', iconKey: 'digital',   type: TxType.expense, sortOrder: 19),
      const Category(id: 'cat.car',       name: '车费', iconKey: 'car',       type: TxType.expense, sortOrder: 20),
      const Category(id: 'cat.else',      name: '其他', iconKey: 'else',      type: TxType.expense, sortOrder: 21),
      // 收入
      const Category(id: 'cat.salary',    name: '工资', iconKey: 'salary',    type: TxType.income,  sortOrder: 100),
      const Category(id: 'cat.bonus',     name: '奖金', iconKey: 'bonus',     type: TxType.income,  sortOrder: 101),
      const Category(id: 'cat.subsidy',   name: '补贴', iconKey: 'subsidy',   type: TxType.income,  sortOrder: 102),
      const Category(id: 'cat.parttime',  name: '兼职', iconKey: 'parttime',  type: TxType.income,  sortOrder: 103),
      const Category(id: 'cat.invest',    name: '投资', iconKey: 'invest',    type: TxType.income,  sortOrder: 104),
      const Category(id: 'cat.refund',    name: '退款', iconKey: 'refund',    type: TxType.income,  sortOrder: 105),
      const Category(id: 'cat.receive',   name: '收礼', iconKey: 'receive',   type: TxType.income,  sortOrder: 106),
      const Category(id: 'cat.in_else',   name: '其他', iconKey: 'else',      type: TxType.income,  sortOrder: 107),
    ];

/// 种子流水（2026-10-05..10-09, 与原型/基线一致）
///
/// 设计目标: 验证
///   - 9 个分类占比加和 = 100%
///   - 平均 = 周期总额 / 已过天数 (5)
///   - 折线图日点值与基线 §7 实测表一致
///   - 总收入 3697.00, 总支出 15887.00
List<Tx> seedTxs() {
  // 2026-10-05 epoch day = 20731 (1970-01-01 起)
  //   2026-01-01 = 20454, +273 (Jan-Sep) + 4 (Oct 1-4) = 20731
  const day0 = 20731;
  // 2026-10-09 epoch day = 20735
  const day4 = day0 + 4;

  Tx t(String id, int day, TxType type, String cat, String amt, String note,
          {String? photo}) =>
      Tx(
        id: id,
        epochDay: day,
        type: type,
        categoryId: cat,
        amountCents: _toCents(amt),
        note: note,
        photoPath: photo,
        createdAt: DateTime.utc(2026, 10, day - 20750 + 5, 8, 0),
      );

  return [
    // 10-05: 总 1045.00
    t('t.001', day0,   TxType.expense, 'cat.daily',     '590.00', '日用'),
    t('t.002', day0,   TxType.expense, 'cat.kid',       '99.00',  '孩子'),
    t('t.003', day0,   TxType.expense, 'cat.travel',    '80.00',  '旅行'),
    t('t.004', day0,   TxType.expense, 'cat.medical',   '55.00',  '医疗'),
    t('t.005', day0,   TxType.expense, 'cat.transport', '162.00', '交通'),
    t('t.006', day0,   TxType.expense, 'cat.food',      '59.00',  '餐饮'),

    // 10-06: 总 152.00 (交通)
    t('t.007', day0+1, TxType.expense, 'cat.transport', '152.00', '交通'),

    // 10-07: 总 97.00 (交通)
    t('t.008', day0+2, TxType.expense, 'cat.transport', '97.00',  '交通'),

    // 10-08: 总 53.00 (餐饮)
    t('t.009', day0+3, TxType.expense, 'cat.food',      '53.00',  '餐饮'),

    // 10-09: 总 934.00 (支出) + 50 (收入)
    t('t.010', day4,   TxType.expense, 'cat.invest',    '818.00', '投资 - 信托'),
    t('t.011', day4,   TxType.income,  'cat.in_else',   '50.00',  '收入'),
    t('t.012', day4,   TxType.expense, 'cat.car',       '5.00',   '停车费'),
    t('t.013', day4,   TxType.expense, 'cat.transport', '3.00',   '单车'),
    t('t.014', day4,   TxType.expense, 'cat.transport', '62.00',  '充电'),
    t('t.015', day4,   TxType.expense, 'cat.drink',     '7.00',   '咖啡'),
    t('t.016', day4,   TxType.expense, 'cat.food',      '15.00',  '餐饮'),
    t('t.017', day4,   TxType.expense, 'cat.food',      '9.00',   '餐饮'),
    t('t.018', day4,   TxType.expense, 'cat.car',       '15.00',  '停车费'),
  ];
}

int _toCents(String yuan) {
  // "590.00" -> 59000
  final s = yuan.replaceAll(',', '');
  final v = double.parse(s);
  return (v * 100).round();
}
