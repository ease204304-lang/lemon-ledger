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
  // 支出
  'food':      CategoryPalette(Color(0xFFFF8A4A)),
  'market':    CategoryPalette(Color(0xFF67B23A)),
  'transport': CategoryPalette(Color(0xFF4A9CF8)),
  'fruit':     CategoryPalette(Color(0xFFFF6E6E)),
  'daily':     CategoryPalette(Color(0xFFFFB73A)),
  'snack':     CategoryPalette(Color(0xFFFFB1B1)),
  'drink':     CategoryPalette(Color(0xFFB07A4A)),
  'dress':     CategoryPalette(Color(0xFFE85AC2)),
  'beauty':    CategoryPalette(Color(0xFFFF80B0)),
  'phone':    CategoryPalette(Color(0xFF8C9BFF)),
  'house':     CategoryPalette(Color(0xFF7FB89E)),
  'travel':    CategoryPalette(Color(0xFF3D7BD9)),
  'book':      CategoryPalette(Color(0xFF5C8FCB)),
  'education': CategoryPalette(Color(0xFF6E89C9)),
  'medical':   CategoryPalette(Color(0xFFE26B6B)),
  'housing':   CategoryPalette(Color(0xFFB58A5E)),
  'kid':       CategoryPalette(Color(0xFFFFC857)),
  'pet':       CategoryPalette(Color(0xFFA57F4A)),
  'digital':   CategoryPalette(Color(0xFF6E89C9)),
  'car':       CategoryPalette(Color(0xFF777777)),
  'credit':    CategoryPalette(Color(0xFF4A6FA5)),
  'else':      CategoryPalette(Color(0xFF9C9C9C)),
  // 收入
  'salary':    CategoryPalette(Color(0xFFFF8C42)),
  'bonus':     CategoryPalette(Color(0xFFFFC542)),
  'subsidy':   CategoryPalette(Color(0xFF4FBC8B)),
  'parttime':  CategoryPalette(Color(0xFF6FA8DC)),
  'invest':    CategoryPalette(Color(0xFFE85D5D)),
  'refund':    CategoryPalette(Color(0xFF4FBC8B)),
  'receive':   CategoryPalette(Color(0xFFFF80B0)),
};

const Map<String, IconData> catIcons = {
  'food':      Icons.restaurant,
  'market':    Icons.local_grocery_store,
  'transport': Icons.directions_subway,
  'fruit':     Icons.apple,
  'daily':     Icons.shopping_basket,
  'snack':     Icons.cookie,
  'drink':     Icons.local_cafe,
  'dress':     Icons.checkroom,
  'beauty':    Icons.face_retouching_natural,
  'phone':     Icons.phone_iphone,
  'house':     Icons.cottage,
  'travel':    Icons.flight,
  'book':      Icons.menu_book,
  'education': Icons.school,
  'medical':   Icons.local_hospital,
  'housing':   Icons.home_work,
  'kid':       Icons.child_care,
  'pet':       Icons.pets,
  'digital':   Icons.devices,
  'car':       Icons.local_parking,
  'credit':    Icons.credit_card,
  'else':      Icons.more_horiz,
  // 收入
  'salary':    Icons.payments,
  'bonus':     Icons.card_giftcard,
  'subsidy':   Icons.volunteer_activism,
  'parttime':  Icons.work_outline,
  'invest':    Icons.trending_up,
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
