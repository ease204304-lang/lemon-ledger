/// 记账页标签栏 (绿色圆圈位置): 最近 5 个标签 + 提示
library;

import 'package:flutter/material.dart';
import '../data/tag_service.dart';
import '../theme/tokens.dart';

class EntryTagBar extends StatelessWidget {
  final List<Tag> tags;
  final ValueChanged<String> onTap;
  const EntryTagBar({super.key, required this.tags, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: L.surface,
      padding: const EdgeInsets.fromLTRB(L.pageH, 0, L.pageH, 4),
      child: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text('在备注里输入后点 + 添加标签',
                    style: TextStyle(color: L.textTertiary, fontSize: 12)),
              )
            else
              for (final t in tags) ...[
                _TagChip(
                    label: t.name,
                    useCount: t.useCount,
                    onTap: () => onTap(t.name)),
                const SizedBox(width: 6),
              ],
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final int useCount;
  final VoidCallback onTap;
  const _TagChip({
    required this.label,
    required this.useCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: L.brandYellowTrack,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: L.brandYellow.withValues(alpha: 0.5), width: 0.5),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_offer_outlined,
                size: 12, color: L.textTertiary),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: L.textPrimary,
                    fontWeight: FontWeight.w500)),
            if (useCount > 1) ...[
              const SizedBox(width: 4),
              Text('×$useCount',
                  style: const TextStyle(
                      fontSize: 10, color: L.textTertiary)),
            ],
          ],
        ),
      ),
    );
  }
}
