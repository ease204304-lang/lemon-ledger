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
  // 支出 (v1.15.0: 24 类, 按用户清单顺序)
  'credit':    CategoryPalette(Color(0xFF4A6FA5)),
  'housing':   CategoryPalette(Color(0xFFB58A5E)),
  'relative':  CategoryPalette(Color(0xFF7B68EE)),
  'kid':       CategoryPalette(Color(0xFFFFC857)),
  'food':      CategoryPalette(Color(0xFFFF8A4A)),
  'travel':    CategoryPalette(Color(0xFF3D7BD9)),
  'car':       CategoryPalette(Color(0xFF777777)),
  'invest':    CategoryPalette(Color(0xFFE85D5D)),
  'smoke':     CategoryPalette(Color(0xFF8B4513)),
  'entertain': CategoryPalette(Color(0xFF9B6BFF)),
  'phone':     CategoryPalette(Color(0xFF26A69A)),
  'snack':     CategoryPalette(Color(0xFFFFB1B1)),
  'transport': CategoryPalette(Color(0xFF4A9CF8)),
  'education': CategoryPalette(Color(0xFF5C9DFF)),
  'daily':     CategoryPalette(Color(0xFFFFB73A)),
  'sport':     CategoryPalette(Color(0xFF2FBFA0)),
  'medical':   CategoryPalette(Color(0xFFE26B6B)),
  'beauty':    CategoryPalette(Color(0xFFFF6FA5)),
  'book':      CategoryPalette(Color(0xFFA1887F)),
  'fruit':     CategoryPalette(Color(0xFFE53935)),
  'market':    CategoryPalette(Color(0xFFFB8C00)),
  'donate':    CategoryPalette(Color(0xFF43A047)),
  'cashgift':  CategoryPalette(Color(0xFFD4A017)),
  'else':      CategoryPalette(Color(0xFF9C9C9C)),
  // 收入 (v1.15.0: 4 类)
  'salary':    CategoryPalette(Color(0xFFFF8C42)),
  'bonus':     CategoryPalette(Color(0xFFFFC542)),
  'subsidy':   CategoryPalette(Color(0xFF4FBC8B)),
  'parttime':  CategoryPalette(Color(0xFF6FA8DC)),
  'refund':    CategoryPalette(Color(0xFF4FBC8B)),
  'receive':   CategoryPalette(Color(0xFFFF80B0)),
};

const Map<String, IconData> catIcons = {
  // 支出 (v1.15.0 顺序)
  'credit':    Icons.credit_card,
  'housing':   Icons.home_work,
  'relative':  Icons.group,
  'kid':       Icons.child_care,
  'food':      Icons.restaurant,
  'travel':    Icons.flight,
  'car':       Icons.local_parking,
  'invest':    Icons.trending_up,
  'smoke':     Icons.local_bar,
  'entertain': Icons.movie,
  'phone':     Icons.smartphone,
  'snack':     Icons.cookie,
  'transport': Icons.directions_subway,
  'education': Icons.school,
  'daily':     Icons.shopping_basket,
  'sport':     Icons.fitness_center,
  'medical':   Icons.local_hospital,
  'beauty':    Icons.face_retouching_natural,
  'book':      Icons.menu_book,
  'fruit':     Icons.apple,
  'market':    Icons.shopping_cart,
  'donate':    Icons.volunteer_activism,
  'cashgift':  Icons.redeem,
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