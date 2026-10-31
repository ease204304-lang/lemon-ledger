/// 底部 5 标签栏
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'icons.dart';

class TopTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onAddLongPress;
  const TopTabBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onAddLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // 5 标签: 明细 / 图表 / 记帐 (中央 + 按钮) / 发现 / 我的
    // 中央记帐按钮是黄色 + 圆形 + 下方 "记帐" label (与原型对齐)
    const items = [
      ('list', '明细'),
      ('chart', '图表'),
      ('add', '记帐'),
      ('discover', '发现'),
      ('mine', '我的'),
    ];
    // 重要: 固定高度, 否则 Container 在 Scaffold.bottomNavigationBar 槽里
    // 会撑满整个剩余空间, 导致 body 高度被压成 0
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: L.surface,
        border: Border(top: BorderSide(color: L.dividerLight, width: 0.5)),
      ),
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: List.generate(items.length, (i) {
          final (key, label) = items[i];
          final selected = i == currentIndex;
          if (key == 'add') {
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(2),
                onLongPress: onAddLongPress,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        color: L.brandYellow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: L.textPrimary, size: 22),
                    ),
                    const SizedBox(height: 1),
                    Text(label,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? L.textPrimary : L.textSecondary,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ],
                ),
              ),
            );
          }
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(tabIcons[key],
                      color: selected ? L.textPrimary : L.textSecondary,
                      size: 22),
                  const SizedBox(height: 1),
                  Text(label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? L.textPrimary : L.textSecondary,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
