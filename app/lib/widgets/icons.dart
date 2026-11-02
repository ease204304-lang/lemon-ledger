/// 分类与导航的 SVG icon
///
/// 由于 Material Icons 与原型差异较大，本项目用 [IconData] 的 CodePoint 复用
/// Material 的字形，但通过颜色与尺寸控制接近原型的视觉表现。
/// 关键差异：填充色（彩色而非主题色），尺寸 24。
library icons;

import 'package:flutter/material.dart';

/// 分类色板（每个 icon 配独立色）
class CategoryPalette {
  final Color color;
  const CategoryPalette(this.color);
}

const Map<String, CategoryPalette> catColors = {
  // 支出 (v1.10.0: 15 类, 按用户清单顺序)
  'credit':    CategoryPalette(Color(0xFF4A6FA5)),
  'food':      CategoryPalette(Color(0xFFFF8A4A)),
  'entertain': CategoryPalette(Color(0xFF9B6BFF)),
  'snack':     CategoryPalette(Color(0xFFFFB1B1)),
  'transport': CategoryPalette(Color(0xFF4A9CF8)),
  'housing':   CategoryPalette(Color(0xFFB58A5E)),
  'travel':    CategoryPalette(Color(0xFF3D7BD9)),
  'medical':   CategoryPalette(Color(0xFFE26B6B)),
  'sport':     CategoryPalette(Color(0xFF2FBFA0)),
  'car':       CategoryPalette(Color(0xFF777777)),
  'kid':       CategoryPalette(Color(0xFFFFC857)),
  'daily':     CategoryPalette(Color(0xFFFFB73A)),
  'invest':    CategoryPalette(Color(0xFFE85D5D)),
  'else':      CategoryPalette(Color(0xFF9C9C9C)),
  // 收入
  'salary':    CategoryPalette(Color(0xFFFF8C42)),
  'bonus':     CategoryPalette(Color(0xFFFFC542)),
  'subsidy':   CategoryPalette(Color(0xFF4FBC8B)),
  'parttime':  CategoryPalette(Color(0xFF6FA8DC)),
  'refund':    CategoryPalette(Color(0xFF4FBC8B)),
  'receive':   CategoryPalette(Color(0xFFFF80B0)),
};

const Map<String, IconData> catIcons = {
  // 支出
  'credit':    Icons.credit_card,
  'food':      Icons.restaurant,
  'entertain': Icons.movie,
  'snack':     Icons.cookie,
  'transport': Icons.directions_subway,
  'housing':   Icons.home_work,
  'travel':    Icons.flight,
  'medical':   Icons.local_hospital,
  'sport':     Icons.fitness_center,
  'car':       Icons.local_parking,
  'kid':       Icons.child_care,
  'daily':     Icons.shopping_basket,
  'invest':    Icons.trending_up,
  'else':      Icons.more_horiz,
  // 收入
  'salary':    Icons.payments,
  'bonus':     Icons.card_giftcard,
  'subsidy':   Icons.volunteer_activism,
  'parttime':  Icons.work_outline,
  'refund':    Icons.assignment_return,
  'receive':   Icons.redeem,
};

/// 顶部 5 标签栏 icon
const Map<String, IconData> tabIcons = {
  'list':     Icons.list_alt,
  'chart':    Icons.insert_chart_outlined,
  'add':      Icons.add,
  'discover': Icons.explore_outlined,
  'mine':     Icons.person_outline,
};