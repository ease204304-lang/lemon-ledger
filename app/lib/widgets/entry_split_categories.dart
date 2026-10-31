/// 记账页分类区 (v1.6.0 U1.5 改造)
///
/// 布局 (按 image.png 设计):
/// ```
/// ┌──────────────────────────┬─────────┐
/// │  全部 (14 分类 网格)      │  常用    │
/// │                          │ 标签     │
/// │   餐饮  超市  交通  水果 日用 │ 餐  餐饮│
/// │   零食  饮品  服饰  美妆 通讯 │ 交  交通│
/// │   居家  信用卡 旅行  学习 教育 │ 零  零食│
/// │                          │ 信 信用卡│
/// └──────────────────────────┴─────────┘
/// ```
///
/// 左侧: 14 支出分类 网格 (5 列 × 3 行)
/// 右侧: 4 常用分类 竖排 (1 列 × 4 行), 顶部 "常用" 标签
///
/// 选中反馈: 选中时整格变品牌黄背景 + 文字深色
library;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';

class EntrySplitCategories extends StatelessWidget {
  final TxType type;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  const EntrySplitCategories({
    super.key,
    required this.type,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: CategoryRepository.instance.byType(type),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const SizedBox.shrink();
        }
        final all = snap.data!.where((c) => !c.archived).toList();
        final pinned = all.where((c) => c.pinned).toList();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左: 全部分类 网格 (5 列 × 3 行)
            Expanded(
              flex: 7,
              child: _AllGrid(
                all: all,
                selected: selected,
                onSelect: onSelect,
              ),
            ),
            // 右: 常用 竖排
            SizedBox(
              width: 100,
              child: _PinnedColumn(
                pinned: pinned,
                selected: selected,
                onSelect: onSelect,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 全部分类 (左侧 70% 宽, 5 列 × 3 行)
class _AllGrid extends StatelessWidget {
  final List<Category> all;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  const _AllGrid({
    required this.all,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        // v1.9.0: 允许滚动 (分类区扩大到 2/3 屏, 22 支出分类需要 5 行)
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: all.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 0.9,
        ),
        itemBuilder: (ctx, i) {
          final c = all[i];
          final isSelected = selected?.id == c.id;
          return InkWell(
            onTap: () => onSelect(c),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: isSelected ? L.brandYellow : L.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? L.brandYellow : L.dividerLight,
                  width: 0.5,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected
                          ? L.textPrimary
                          : L.textBody,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 常用分类 (右侧 30% 宽, 1 列 × 4 行 + "常用" 标签)
class _PinnedColumn extends StatelessWidget {
  final List<Category> pinned;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  const _PinnedColumn({
    required this.pinned,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: L.brandYellowTrack,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "常用" 标签 (顶部)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: L.dividerLight, width: 0.5),
              ),
            ),
            child: const Text('常用',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: L.textSecondary)),
          ),
          // 4 常用 分类
          for (final c in pinned)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(c),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected?.id == c.id
                        ? L.brandYellow
                        : Colors.transparent,
                    border: const Border(
                      bottom: BorderSide(color: L.dividerLight, width: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected?.id == c.id
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected?.id == c.id
                            ? L.textPrimary
                            : L.textBody,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
