/// 记账页分类网格: 5 列 × N 行, 单选, FutureBuilder 加载
library;

import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme/tokens.dart';
import 'category_icon.dart';

class EntryCategoryGrid extends StatelessWidget {
  final TxType type;
  final Category? selected;
  final ValueChanged<Category> onSelect;
  const EntryCategoryGrid({
    super.key,
    required this.type,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Category>>(
      future: CategoryRepository.instance.byType(type),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cats = snap.data!;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(L.pageH, 8, L.pageH, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: cats.length,
          itemBuilder: (context, i) {
            final c = cats[i];
            final sel = c.id == selected?.id;
            return GestureDetector(
              onTap: () => onSelect(c),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Stack(alignment: Alignment.center, children: [
                    CategoryIcon(iconKey: c.iconKey, size: 44),
                    if (sel)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(
                              color: L.brandYellow, shape: BoxShape.circle),
                          child: const Icon(Icons.check,
                              size: 10, color: L.textPrimary),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? L.textPrimary : L.textBody,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w400)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
