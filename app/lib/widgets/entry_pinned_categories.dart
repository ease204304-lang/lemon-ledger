/// 常用分类横排 (v1.6.0 U1)
///
/// 鲨鱼记账风格:
///   - 支出: 显示 pinned=1 的 4 个常用 (信用卡/餐饮/交通/零食)
///   - 收入: 显示 pinned=1 的 1 个 (工资)
///   - 其他分类: 点 "全部" 进入全部分类页
library;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';

class EntryPinnedCategories extends StatelessWidget {
  final TxType type;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  final VoidCallback onTapAll;
  const EntryPinnedCategories({
    super.key,
    required this.type,
    required this.selected,
    required this.onSelect,
    required this.onTapAll,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: FutureBuilder<List<Category>>(
        future: CategoryRepository.instance.byType(type),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const SizedBox.shrink();
          }
          final all = snap.data!;
          final pinned = all.where((c) => c.pinned).toList();
          return Row(
            children: [
              for (final c in pinned)
                Expanded(
                  child: _PinnedTile(
                    cat: c,
                    selected: selected?.id == c.id,
                    onTap: () => onSelect(c),
                  ),
                ),
              // "全部" 入口
              SizedBox(
                width: 64,
                child: _AllTile(onTap: onTapAll),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  final Category cat;
  final bool selected;
  final VoidCallback onTap;
  const _PinnedTile({
    required this.cat,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 圆形彩色 icon 背景
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: selected ? L.brandYellow : L.surfaceSubtle,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: Text(
              cat.name.substring(0, 1),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? L.textPrimary : L.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cat.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: L.textBody),
          ),
        ],
      ),
    );
  }
}

class _AllTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AllTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.grid_view, size: 24, color: L.textTertiary),
          SizedBox(height: 4),
          Text('全部',
              style: TextStyle(fontSize: 11, color: L.textTertiary)),
        ],
      ),
    );
  }
}
