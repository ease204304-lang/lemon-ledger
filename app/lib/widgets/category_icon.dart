/// 分类圆角方块 icon（圆角矩形 + 居中 Icon）
library;

import 'package:flutter/material.dart';

import 'icons.dart';

class CategoryIcon extends StatelessWidget {
  final String iconKey;
  final double size;
  const CategoryIcon({super.key, required this.iconKey, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final palette = catColors[iconKey] ?? const CategoryPalette(Color(0xFF999999));
    final icon = catIcons[iconKey] ?? Icons.more_horiz;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: palette.color, size: size * 0.55),
    );
  }
}
