/// 分类组合筛选底部面板 (v1.11.0 W3 — PRD 05 分类组合筛选)
///
/// 规则 (PRD 05):
///   - 收入和支出各有「全部分类」与「指定分类」两种状态
///   - 独立底部面板支持两级分类多选
///   - 临时勾选在确认前不触发查询
///   - 取消恢复原条件, 清空恢复全部
///   - 选择父分类覆盖其子分类及一级直接记账
///   - 父子同选仅计一次
library;

import 'package:flutter/material.dart';

import '../../services/stats_api.dart';
import '../../services/stats_controller.dart';
import '../../theme/tokens.dart';

/// 可供筛选的分类项 (来自服务端或本地分类表)
class FilterCategory {
  final String id;
  final String name;
  final int level; // 1 / 2
  final String? parentId;

  const FilterCategory({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
  });
}

/// 分类组合筛选面板
class CategoryFilterSheet extends StatefulWidget {
  /// 哪一侧
  final bool incomeSide;
  final StatsController controller;
  final List<FilterCategory> categories;

  const CategoryFilterSheet({
    super.key,
    required this.incomeSide,
    required this.controller,
    required this.categories,
  });

  @override
  State<CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<CategoryFilterSheet> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final draft = widget.incomeSide ? c.incomeDraft : c.expenseDraft;
    final parents = widget.categories.where((e) => e.level == 1).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: L.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 头部
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  Text(
                    widget.incomeSide ? '收入分类' : '支出分类',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton(
                    // 清空恢复全部
                    onPressed: () {
                      if (widget.incomeSide) {
                        c.draftClearIncome();
                      } else {
                        c.draftClearExpense();
                      }
                      setState(() {});
                    },
                    child: const Text('清空', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton(
                    // 取消恢复原条件
                    onPressed: () {
                      c.cancelDraft();
                      Navigator.pop(ctx);
                    },
                    child: const Text('取消', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton(
                    // 确认才触发查询
                    onPressed: () {
                      c.confirmDraft();
                      Navigator.pop(ctx);
                    },
                    child: const Text('确定',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            // 模式切换: 全部分类 / 指定分类
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _modeChip(ctx, '全部分类', draft.isAll, () {
                    if (widget.incomeSide) {
                      c.draftClearIncome();
                    } else {
                      c.draftClearExpense();
                    }
                    setState(() {});
                  }),
                  const SizedBox(width: 10),
                  _modeChip(ctx, '指定分类', !draft.isAll, () {
                    // 切到指定分类: 若当前是 ALL, 保持空集合 (用户需勾选)
                    if (draft.isAll) {
                      if (widget.incomeSide) {
                        c.draftToggleIncome(''); // 触发 draftDirty
                      } else {
                        c.draftToggleExpense('');
                      }
                    }
                    setState(() {});
                  }),
                  const Spacer(),
                  if (!draft.isAll)
                    Text('已选 ${draft.ids.length} 项',
                        style: const TextStyle(fontSize: 11, color: L.textTertiary)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: L.dividerLight),
            // 两级分类树
            Expanded(
              child: draft.isAll
                  ? const Center(
                      child: Text('当前统计该侧全部分类',
                          style: TextStyle(fontSize: 13, color: L.textTertiary)),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: parents.length,
                      itemBuilder: (ctx, i) {
                        final p = parents[i];
                        final children = widget.categories
                            .where((e) => e.parentId == p.id)
                            .toList();
                        final parentChecked = draft.ids.contains(p.id);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _checkRow(
                              p,
                              parentChecked,
                              () {
                                if (widget.incomeSide) {
                                  c.draftToggleIncome(p.id);
                                } else {
                                  c.draftToggleExpense(p.id);
                                }
                                setState(() {});
                              },
                            ),
                            for (final ch in children)
                              _checkRow(
                                ch,
                                draft.ids.contains(ch.id),
                                () {
                                  if (widget.incomeSide) {
                                    c.draftToggleIncome(ch.id);
                                  } else {
                                    c.draftToggleExpense(ch.id);
                                  }
                                  setState(() {});
                                },
                                indent: 22,
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(
    BuildContext ctx,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? L.brandYellow : L.surfaceSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? L.brandYellow : L.dividerLight),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _checkRow(
    FilterCategory cat,
    bool checked,
    VoidCallback onTap, {
    double indent = 12,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 10, 16, 10),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: checked ? L.brandYellow : L.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(cat.name,
                style: const TextStyle(fontSize: 13, color: L.textBody)),
          ],
        ),
      ),
    );
  }
}
